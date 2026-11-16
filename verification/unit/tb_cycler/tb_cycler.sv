module tb_cycler #(
    parameter C_WIDTH = 4
)
(
    output logic done
); 

    logic clk;
    logic rst;
    logic en;
    logic [C_WIDTH-1:0] one_hot;
    logic [C_WIDTH-1:0] expected_one_hot;

    cycler #(.C_WIDTH(C_WIDTH)) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .one_hot(one_hot)
    );

    covergroup cycler_cover @(posedge clk);
        cp_rst: coverpoint rst {
            bins disabled = {0};
            bins enabled = {1};
        }
        cp_en: coverpoint en {
            bins disabled = {0};
            bins enabled = {1};
        }
        cp_one_hot: coverpoint ($onehot(one_hot)) {
            bins valid = {1};
            bins invalid = {0};
        }
        cp_rotate: coverpoint (en && !rst) {
            bins rotate = {1};
            bins not_rotate = {0};
        }

    endgroup
    cycler_cover cg ;
    //产生预期结果
    function automatic [C_WIDTH-1:0] check(
        input logic [C_WIDTH-1:0] current_one_hot,
        input logic rst,
        input logic en
    );
        if (rst) begin
            return 1;
        end
        else if(C_WIDTH == 1) begin
            return 1;
        end
        else if (en) begin
            return (current_one_hot << 1) |
               (current_one_hot >> (C_WIDTH - 1));
        end
        else begin
            return current_one_hot;
        end
        
    endfunction : check

    task automatic check_one_hot(
        input logic [C_WIDTH-1:0] exp
        );
        if (one_hot !== exp) begin
            $fatal(1, "Error: one_hot=%b, expected_one_hot=%b", one_hot, expected_one_hot);
        end else begin
            $display("one_hot=%b, expected_one_hot=%b", one_hot, expected_one_hot);
        end
    endtask : check_one_hot

    task automatic check_cycler(
        input logic r,
        input logic e
    );
        @(negedge clk);
        rst = r;
        en = e;
        expected_one_hot = check(expected_one_hot, r, e);
        @(posedge clk);
        #1;
        check_one_hot(expected_one_hot);
    endtask : check_cycler

    //clk
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        done = 0;
        cg = new();

        rst = 1;
        en = 0;
        expected_one_hot = 1;
        repeat (32) begin
            check_cycler(rst, en); // rst=1, en=0
        end

        rst = 1;
        en = 1;
        repeat (32) begin
            check_cycler(rst, en); // rst=1, en=1
        end

        rst = 0;
        en = 1;
        repeat (32) begin
            check_cycler(rst, en); // rst=0, en=1
        end

        rst = 0;
        en = 0;
        repeat (32) begin
            check_cycler(rst, en); // rst=0, en=0
        end

        done = 1;

    end
endmodule

module tb_all ;
    localparam int width_num = 11;
    localparam int width[width_num] ={1, 2, 3, 4, 5, 6, 7, 8, 15, 16, 32}; 
    wire [width_num-1:0] done;
    generate
        for(genvar i=0 ; i < width_num ; i++ )
        begin : gen_tb_cycler
            tb_cycler #(.C_WIDTH(width[i])) tb_cycler_inst (
                .done(done[i])
            );
        end
    endgenerate
    initial begin
        wait(&done);
        $display("All tb_cycler instances completed successfully.");
        $finish;
    end


endmodule
