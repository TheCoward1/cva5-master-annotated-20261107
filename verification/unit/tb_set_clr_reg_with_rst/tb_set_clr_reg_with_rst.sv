module tb_set_clr_reg_with_rst #(
    parameter SET_OVER_CLR = 0, 
    parameter WIDTH = 16,
    parameter [WIDTH-1:0] RST_VALUE = '0
)(
    output logic done
);

    logic clk;
    logic rst;
    logic [WIDTH-1:0] set;
    logic [WIDTH-1:0] clr;
    logic [WIDTH-1:0] result;
    logic [WIDTH-1:0] expected_result;


    set_clr_reg_with_rst #(.SET_OVER_CLR(SET_OVER_CLR), .WIDTH(WIDTH), .RST_VALUE(RST_VALUE)) dut (
        .clk(clk),
        .rst(rst),
        .set(set),
        .clr(clr),
        .result(result)
    );

    function automatic logic [WIDTH-1:0] calc_next(
        input logic [WIDTH-1:0] current,// 当前寄存器值
        input logic             r,// 同步复位信号
        input logic [WIDTH-1:0] s,// set 信号
        input logic [WIDTH-1:0] c// clr 信号
    );
        if (r) begin
            return RST_VALUE;
        end
        else if (SET_OVER_CLR) begin
            // set 优先
            return s | (current & ~c);
        end
        else begin
            // clear 优先
            return (s | current) & ~c;
        end
    endfunction

    class set_clr_stim #(parameter int WIDTH = 16);
        rand logic [WIDTH-1:0] set;
        rand logic [WIDTH-1:0] clr;
    endclass

    covergroup set_clr_cover @(posedge clk);

        cp_rst: coverpoint rst {
            bins disabled = {0};
            bins enabled = {1};
        }
        cp_set: coverpoint (set == '0) {
            bins no = {0};
            bins yes = {1};
        }
        cp_clr: coverpoint (clr == '0) {
            bins no = {0};
            bins yes = {1};
        }
        cp_clr_all: coverpoint (clr == {WIDTH{1'b1}}) {
            bins no = {0};
            bins yes = {1};
        }
        cp_set_all: coverpoint (set == {WIDTH{1'b1}}) {
            bins no = {0};
            bins yes = {1};
        }
        cp_overlap: coverpoint ((set & clr) != 0) {
            bins no = {0};
            bins yes = {1};
        }

    endgroup

    set_clr_cover cg;

    task automatic check_cycle(
        input logic             r, 
        input logic [WIDTH-1:0] s,
        input logic [WIDTH-1:0] c   
    );
        begin
            rst = r;
            set = s;
            clr = c;
            @(negedge clk);
            expected_result = calc_next(expected_result, rst, set, clr);
            @(posedge clk);
            #1;
            if(result !== expected_result) begin
                $fatal(1,"Mismatch: expected %h, got %h", expected_result, result);
            end else begin
                $display("set: %h, clr: %h, result: %h,expected_result: %h", set, clr, result,expected_result) ;
            end
        end
    endtask

    //clk
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns clock period
    end

    initial begin
        //
        set_clr_stim #(WIDTH) stim = new();
        done = 0;
        rst = 1;
        cg = new();

        // 复位
        check_cycle(1'b1, '0, '0);

        // 保持
        check_cycle(1'b0, '0, '0);

        // 只 set
        check_cycle(1'b0, '1, '0);

        // 只 clr
        check_cycle(1'b0, '0, '1);

        // set 和 clr 重叠
        check_cycle(1'b0, '1, '1);

        // 全 1
        check_cycle(1'b0, '1, '0);
        check_cycle(1'b0, '0, '1);

        // 不同 bit 的 set/clr
        if (WIDTH > 1) begin
            check_cycle(1'b0, WIDTH'(2), WIDTH'(1));
        end

        expected_result = RST_VALUE;
        repeat(1000) begin
            assert(stim.randomize()) else $fatal("Failed to randomize stimulus");
            set = stim.set;
            clr = stim.clr;
            @(negedge clk);
            expected_result = calc_next(expected_result, rst, set, clr);
            @(posedge clk);
            #1;
            if(result !== expected_result) begin
                $fatal(1,"Mismatch: expected %h, got %h", expected_result, result);
            end else begin
                $display("set: %h, clr: %h, result: %h,expected_result: %h", set, clr, result,expected_result) ;
            end
           
            $display("Test completed successfully.");
        end

        rst = 0;
        repeat(10000) begin
            assert(stim.randomize()) else $fatal("Failed to randomize stimulus");
            set = stim.set;
            clr = stim.clr;
            @(negedge clk);
            expected_result = calc_next(expected_result, rst, set, clr);
            @(posedge clk);
            #1;
            if(result !== expected_result) begin
                $fatal(1,"Mismatch: expected %h, got %h", expected_result, result);
            end else begin
                $display("set: %h, clr: %h, result: %h,expected_result: %h", set, clr, result,expected_result) ;
            end
        end
        $display("Test completed successfully.");      
        done = 1;
    end
endmodule

module tb_set_clr_reg_with_rst_top();

    localparam int NUM_CASES  = 7;
    localparam int widths[NUM_CASES] = '{1, 2, 4, 8, 15, 16, 32};
    wire [NUM_CASES-1:0]done;
    generate
        for (genvar i = 0; i < NUM_CASES; i++) begin : gen_tb
            tb_set_clr_reg_with_rst #(.SET_OVER_CLR(i%2), .WIDTH(widths[i]), .RST_VALUE('0)) dut (done[i]);
        end

    endgenerate

    initial begin
        wait (&done);
        $display("ALL SET_CLR_REG_WITH_RST TESTS PASSED");
        $finish;
    end
endmodule
