module tb_round_robin #(
    parameter int unsigned NUM_PORTS = 2
) (
    output logic done
);

    logic clk;
    logic rst;
    logic [NUM_PORTS-1:0] requests;
    logic grant;
    logic [(NUM_PORTS == 1 ? 1 : $clog2(NUM_PORTS))-1:0] grantee;
    localparam int INDEX_W = (NUM_PORTS == 1) ? 1 : $clog2(NUM_PORTS);
    logic [INDEX_W-1:0] expected_state;
    logic [INDEX_W-1:0] expected_grantee;

    covergroup cg @(posedge clk);
        cp_rst:coverpoint rst{
            bins rst_off ={0};
            bins rst_on = {1};
        }

        cp_requests: coverpoint requests{
            bins all_request[] = {[0:(1<<NUM_PORTS)-1]};
        }

        cp_requests_count:coverpoint $countones(requests){
            bins none     = {0};
            bins one      = {1};
            bins multiple = default;
        }

        cp_requests_onehot: coverpoint $onehot(requests){
            bins onehot = {1};
            bins no_onehot ={0};
        }

        cp_all: coverpoint (&requests) {
            bins all_requests = {1};
            bins not_all      = {0};
        }

        cp_state: coverpoint expected_state {
            bins state_value[] = {[0:NUM_PORTS-1]};
        }

        cp_grant: coverpoint grant{
            bins grant_off ={0};
            bins grant_on = {1};
        }

        cp_selected_active: coverpoint (requests[grantee]) {
            bins active   = {1};
            bins inactive = {0};
        }

        cp_grantee: coverpoint grantee{
            bins all_grantee[] = {[0:NUM_PORTS-1]};
        }

        cp_grantee_prev: coverpoint expected_grantee{
            bins all_grantee_pref[] = {[0:NUM_PORTS-1]};
        }

        cx_rst_grant: cross cp_rst, cp_grant;
        cx_count_state: cross cp_requests_count, cp_state;
        cx_state_grantee: cross cp_state, cp_grantee;
        cx_request_selected: cross cp_requests_count, cp_selected_active;

    endgroup


    round_robin // 定义多请求轮询仲裁器。
        #(
            .NUM_PORTS(NUM_PORTS) // 配置参数：请求端口数量，默认为 2。
        ) but(
            .clk(clk), // 时钟输入：state 在上升沿更新。
            .rst(rst), // 同步高有效复位：复位时清除轮转位置。
            .requests(requests), // 请求向量：每个 bit 对应一个请求端口，允许多个 bit 同时有效。
            .grant(grant), // 授权握手输入：1 表示当前 grantee 已被接受，可以推进轮转位置。
            .grantee(grantee) // 授权结果：输出被选中的端口索引；单端口时固定为 1 bit。
        );



    function automatic [INDEX_W-1:0] ref_grant(
        input logic [NUM_PORTS-1:0] requests,
        input logic [INDEX_W-1:0] current_state//当前状态 位于 current_state 位置的端口
    );
        for (int i = 1; i < NUM_PORTS; i++) begin
            if (requests[(current_state - i + NUM_PORTS) % NUM_PORTS]) begin
                return (current_state - i + NUM_PORTS) % NUM_PORTS;
            end
        end
        return current_state;

    endfunction : ref_grant

    //检查预计和实际
    task automatic check_grant(
        input logic [NUM_PORTS-1:0] req,
        input logic r,
        input logic g
    );
        @(negedge clk);
        rst = r;
        grant = g;
        requests =req;
        #1;
        expected_grantee = ref_grant(requests, expected_state);
        #1;
        if (grantee !== expected_grantee) begin
            $fatal(1,"Mismatch: expected grantee = %4d, actual grantee = %4d", expected_grantee, grantee);
        end else begin
            $display("Match: expected grantee = %4d, actual grantee = %4d", expected_grantee, grantee);
        end
        @(posedge clk)
        if(r) expected_state = 0;
        else if(g) expected_state =expected_grantee;
    endtask : check_grant

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    cg cg_init;

    initial begin
        expected_state =0;
        done = 0;
        requests = 0;
        grant =0;
        rst = 0;
        cg_init = new();
        rst = 1;
        repeat (2) @(posedge clk);

        rst = 0;

        repeat (2**NUM_PORTS) begin
            requests++;
            check_grant(requests, rst ,grant);
        end

        requests = 0;
        grant = 0;
        rst = 1;
        repeat (2**NUM_PORTS) begin
            requests++;
            check_grant(requests, rst ,grant);
        end
        requests = 0;
        grant = 1;
        rst = 1;
        repeat (2**NUM_PORTS) begin
            requests++;
            check_grant(requests, rst ,grant);
        end
        requests = 0;
        grant = 1;
        rst = 0;
        repeat (2**NUM_PORTS) begin
            requests++;
            check_grant(requests, rst ,grant);
        end

        // 新增随机测试
        repeat (1000) begin
            logic rnd_rst;
            logic rnd_grant;
            logic [NUM_PORTS-1:0] rnd_requests;

            rnd_rst = ($urandom_range(0, 99) < 5);
            rnd_grant = ($urandom_range(0, 1) == 1);
            rnd_requests = $urandom;

            check_grant(rnd_requests, rnd_rst, rnd_grant);


        end
        done = 1;
    end

endmodule

module tb_round_robin_top #(
    parameter int unsigned NUM_PORTS = 2
);

    localparam num = 4;
    wire [num-1:0]done;

    generate
        for (genvar i = 0; i < num; i++) begin : gen_tb
            tb_round_robin #(
                .NUM_PORTS(i+1)
            ) tb_inst (
                .done(done[i])
            );
        end
    endgenerate

    initial begin
        wait (&done);
        $display("All tests passed");
        $finish;
    end

endmodule