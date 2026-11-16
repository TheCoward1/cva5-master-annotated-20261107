module tb_lfsr 
    #(
        parameter int unsigned WIDTH = 3, // LFSR 状态位宽，支持 3~16
        parameter NEEDS_RESET = 1 // 是否需要同步复位清零
    )
    (
        output logic done // 测试完成标志
    );

    logic clk;
    logic rst;
    logic en;
    logic [WIDTH-1:0] value;
    logic [WIDTH-1:0] expect_value;// 参考值
    logic [WIDTH-1:0] start_value;// [新增] 完整 LFSR 周期的起始状态
    bit seen[logic [WIDTH-1:0]];// [新增] 记录已经出现过的 LFSR 状态

    covergroup lfsr_cg @(posedge clk);

        cp_rst: coverpoint rst{
            bins rst_off ={0};
            bins rst_on = {1};
        }

        cp_en: coverpoint en{
            bins en_off ={0};
            bins en_on = {1};
        }
        cp_zero: coverpoint (value == '0) {
            bins zero    = {1};
            bins nonzero = {0};
        }

        cp_rotate: coverpoint (en && !(rst && NEEDS_RESET)) {
            bins hold   = {0};
            bins rotate = {1};
        }

        cp_active_reset: coverpoint (rst && NEEDS_RESET) {
            bins normal = {0};
            bins reset  = {1};
        }

        cp_operation: cross cp_rst, cp_en;

    endgroup



    lfsr 
    #(
        .WIDTH(WIDTH), // LFSR 状态位宽，支持 3~16
        .NEEDS_RESET(NEEDS_RESET) // 是否需要同步复位清零
    )lfsr_1
    (
        .clk(clk), // 时钟
        .rst(rst), // 同步复位，高有效
        .en(en), // 移位使能，高有效
        .value(value) // 当前 LFSR 状态
    );

    // TAPS 保存 LFSR 的反馈抽头：NUM 是抽头数量，INDICIES 是抽头位置列表。
    typedef struct packed {
        int unsigned NUM; // 抽头数量
        bit [3:0][31:0] INDICIES; // 最多 4 个反馈抽头的位置
    } tap_t;
    localparam tap_t LFSR_TAPS [17] = '{ // 索引 0~16；0~2 项只是占位
        //Dummy entries for widths 0-2
        '{NUM : 1,    INDICIES : '{0,0,0,0}},
        '{NUM : 1,    INDICIES : '{0,0,0,0}},
        '{NUM : 1,    INDICIES : '{0,0,0,0}},
        //Number of taps and indicies[3:0] for LFSRs width 3 to 16
        '{NUM : 2,    INDICIES : '{0,0,1,2}}, //3
        '{NUM : 2,    INDICIES : '{0,0,2,3}}, //4
        '{NUM : 2,    INDICIES : '{0,0,2,4}},
        '{NUM : 2,    INDICIES : '{0,0,4,5}},
        '{NUM : 2,    INDICIES : '{0,0,5,6}},
        '{NUM : 4,    INDICIES : '{3,4,5,7}}, //8
        '{NUM : 2,    INDICIES : '{0,0,4,8}},
        '{NUM : 2,    INDICIES : '{0,0,6,9}},
        '{NUM : 2,    INDICIES : '{0,0,8,10}},
        '{NUM : 4,    INDICIES : '{0,3,5,11}}, //12
        '{NUM : 4,    INDICIES : '{0,2,3,12}},
        '{NUM : 4,    INDICIES : '{0,2,4,13}},
        '{NUM : 2,    INDICIES : '{0,0,13,14}}, //15
        '{NUM : 4,    INDICIES : '{3,12,14,15}} //16
    }; 

    localparam tap_t TAPS = LFSR_TAPS[WIDTH];

    function automatic logic [WIDTH-1 : 0] ref_next(
        input logic [WIDTH-1 : 0] current
    );
        logic [WIDTH-1:0] next;
        logic [TAPS.NUM-1:0] feedback_input; // 各反馈抽头当前取出的值
        logic feedback; // 计算出的下一位反馈值

        for (int i = 0; i < TAPS.NUM; i++) begin
            feedback_input[i] = current[int'(TAPS.INDICIES[i])]; // 取出第 i 个抽头位
        end // 结束语句块。

        if (WIDTH <= 2) begin : gen_width_one_or_two
            feedback = ~current[WIDTH-1];
        end // 结束语句块。
        else begin : gen_width_three_plus
            for (int i = 0; i < TAPS.NUM; i++) begin
                feedback_input[i] = current[int'(TAPS.INDICIES[i])]; // 取出第 i 个抽头位
            end // 结束语句块。
            // 抽头先做 XNOR；再与低 WIDTH-1 位的 OR 异或，扩大序列覆盖范围。
            feedback = (~^feedback_input) ^ |current[WIDTH-2:0];
        end // 结束语句块。

        next = {current[WIDTH-2:0], feedback};
        return next;

    endfunction : ref_next  

    property p_reset_clear;
        @(posedge clk)
        disable iff(!NEEDS_RESET)
        rst |=> value == '0;
    endproperty : p_reset_clear

    assert property (p_reset_clear) else $fatal(1,"Reset did not clear LFSR");

    task automatic check(
        input logic r,
        input logic e
    );
        @(negedge clk);
        rst = r;
        en = e;

        if(rst && NEEDS_RESET) begin
            expect_value = 0;
        end
        else if (en) begin
            expect_value = ref_next(expect_value);
        end
        else begin
            expect_value = expect_value;
        end

        @(posedge clk);
        #1;

        if (value !== expect_value) begin
            $fatal(1, "Mismatch: value=%b, expected=%b", value, expect_value);
        end else begin
            $display("Match: value=%b, expected=%b", value, expect_value);
        end
    endtask : check 

    //clk
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    initial begin
        done = 0;
        rst = 1;
        en = 0;
        
        expect_value = 0;
        if (!NEEDS_RESET) begin
            force lfsr_1.value = '0;
            #1;
            release lfsr_1.value;
        end

        repeat (2) begin
            check(rst, en);
        end
        rst = 1;
        en = 1;
        repeat (2) begin
            check(rst, en);
        end
        rst = 0;
        en = 1;

        // [新增] 进入完整周期前，记录起始状态并清空重复检测表
        start_value = value;
        seen.delete();
        seen[value] = 1;

        // [新增] 除最后回到起始状态外，其余 2^WIDTH-1 个状态必须互不重复
        repeat ((2**WIDTH) - 1) begin
            check(rst, en);

            if (seen.exists(value)) begin
                $fatal(1, "Repeated LFSR state: %b", value);
            end
            seen[value] = 1;
        end

        // [新增] 最后一步应回到完整周期的起始状态
        check(rst, en);
        if (value !== start_value) begin
            $fatal(1, "LFSR did not return to start state: %b", value);
        end

        repeat (10) 
        check(rst, en);
        check(1'b1, 1'b0);

        repeat (1000) begin
            logic r;
            logic e;

            r = ($urandom_range(0, 99) < 5); // 约 5% 概率复位
            e = $urandom_range(0, 1);        // 50% 概率使能

            check(r, e);
        end

        rst = 0;
        en = 0;
        repeat (2) begin
            check(rst, en);
        end
        done = 1;
    end
endmodule

module tb_lfsr_top;

    localparam int width_sum = 14;
    localparam int widths[width_sum]={3,4,5,6,7,8,9,10,11,12,13,14,15,16} ;
    wire [2*width_sum-1:0]done;
    generate
        for(genvar i=0 ; i<width_sum ; i++) begin
            tb_lfsr #(.WIDTH(widths[i]), .NEEDS_RESET(0)) tb_lfsr_inst (.done(done[width_sum+i]));
        end 
        for(genvar i=0 ; i<width_sum ; i++) begin
            tb_lfsr #(.WIDTH(widths[i]), .NEEDS_RESET(1)) tb_lfsr_inst (.done(done[i]));
        end 
  
    endgenerate

    initial begin
        wait(&done);
        $display("Test completed successfully.");
        $finish;
    end
endmodule