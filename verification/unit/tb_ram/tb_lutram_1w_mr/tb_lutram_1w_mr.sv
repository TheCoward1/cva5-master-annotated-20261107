`timescale 1ns/1ps

module tb_lutram_1w_mr #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 32,
    parameter int NUM_READ_PORTS = 2,
    parameter int NUM_RANDOM_WRITES = 256,
    parameter int NUM_RANDOM_READS = 512,
    parameter int NUM_RANDOM_MIXED_OPS = 1000
)(
    output logic done
);

    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic [$clog2(DEPTH)-1:0] addr_t;

    logic clk;
    logic ram_write;

    logic [$clog2(DEPTH)-1:0] waddr;
    logic [$clog2(DEPTH)-1:0] raddr [NUM_READ_PORTS];

    data_t new_ram_data;
    data_t ram_data_out [NUM_READ_PORTS];

    // 参考存储模型：与 DUT 同步更新，用于逐端口比较读数据。
    data_t ref_mem [DEPTH];

    int check_count;

    lutram_1w_mr #(
        .DATA_TYPE(data_t),
        .DEPTH(DEPTH),
        .NUM_READ_PORTS(NUM_READ_PORTS)
    ) dut (
        .clk(clk),
        .waddr(waddr),
        .raddr(raddr),
        .ram_write(ram_write),
        .new_ram_data(new_ram_data),
        .ram_data_out(ram_data_out)
    );

    task automatic reset_ref_mem();
        for (int i = 0; i < DEPTH; i++) begin
            ref_mem[i] = '0;
        end
    endtask

    // 写一个存储字，并在写入完成后同步更新参考模型。
    task automatic write_word(
        input addr_t addr,
        input data_t data
    );
        @(negedge clk);
        waddr        = addr;
        new_ram_data = data;
        ram_write    = 1'b1;

        @(posedge clk);
        #1;
        ref_mem[addr] = data;

        @(negedge clk);
        ram_write = 1'b0;
    endtask

    // 连续两个时钟都写入，验证背靠背写和 ram_write 保持为 1。
    task automatic write_back_to_back(
        input addr_t addr0,
        input data_t data0,
        input addr_t addr1,
        input data_t data1
    );
        @(negedge clk);
        waddr        = addr0;
        new_ram_data = data0;
        ram_write    = 1'b1;

        @(posedge clk);
        #1;
        ref_mem[addr0] = data0;

        @(negedge clk);
        waddr        = addr1;
        new_ram_data = data1;

        @(posedge clk);
        #1;
        ref_mem[addr1] = data1;

        @(negedge clk);
        ram_write = 1'b0;
    endtask

    // 多读端口检查：每个端口使用自己的地址，并分别与参考模型比较。
    task automatic check_read(
        input addr_t read_addrs [NUM_READ_PORTS]
    );
        @(negedge clk);

        for (int i = 0; i < NUM_READ_PORTS; i++) begin
            raddr[i] = read_addrs[i];
        end

        #1;

        for (int i = 0; i < NUM_READ_PORTS; i++) begin
            if (ram_data_out[i] !== ref_mem[read_addrs[i]]) begin
                $fatal(1,
                    "Read mismatch: port=%0d addr=%0d expected=%h actual=%h",
                    i, read_addrs[i],
                    ref_mem[read_addrs[i]], ram_data_out[i]);
            end else begin
                $display("MATCH: port=%0d addr=%0d data=%h",
                         i, read_addrs[i], ram_data_out[i]);
            end
        end

        check_count++;
    endtask

    // 所有读端口读取同一地址。
    task automatic check_same_address(
        input addr_t addr
    );
        addr_t read_addrs [NUM_READ_PORTS];

        for (int i = 0; i < NUM_READ_PORTS; i++) begin
            read_addrs[i] = addr;
        end

        check_read(read_addrs);
    endtask

    // 检查全部地址；每个地址都用所有读端口读取一次。
    task automatic check_all();
        for (int i = 0; i < DEPTH; i++) begin
            check_same_address(addr_t'(i));
        end
    endtask

    // 写使能无效时连续多个周期保持，检查存储内容不变。
    task automatic check_write_disabled(
        input addr_t addr
    );
        @(negedge clk);
        waddr        = addr;
        new_ram_data = ~ref_mem[addr];
        ram_write    = 1'b0;

        repeat (3) @(posedge clk);

        check_same_address(addr);
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        done         = 1'b0;
        ram_write    = 1'b0;
        waddr        = '0;
        new_ram_data = '0;
        check_count  = 0;

        for (int i = 0; i < NUM_READ_PORTS; i++) begin
            raddr[i] = '0;
        end

        reset_ref_mem();

        $display("START LUTRAM_1W_MR TEST: DATA_WIDTH=%0d DEPTH=%0d READ_PORTS=%0d",
                 DATA_WIDTH, DEPTH, NUM_READ_PORTS);

        // 等待 DUT 的仿真初始化完成。
        repeat (2) @(posedge clk);
        #1;

        $display("=== 1. Initial zero check ===");
        check_all();

        $display("=== 2. Single write and same-address reads ===");
        write_word(addr_t'(0), data_t'(32'hDEAD_BEEF));
        check_same_address(addr_t'(0));

        write_word(addr_t'(DEPTH-1), data_t'(32'h1234_5678));
        check_same_address(addr_t'(DEPTH-1));

        $display("=== 3. Fill all addresses ===");
        for (int i = 0; i < DEPTH; i++) begin
            write_word(addr_t'(i), data_t'(32'h1000_0000 + i));
        end
        check_all();

        $display("=== 4. Multi-read with different addresses ===");
        for (int k = 0; k < DEPTH; k++) begin
            addr_t read_addrs [NUM_READ_PORTS];
            for (int i = 0; i < NUM_READ_PORTS; i++) begin
                read_addrs[i] = addr_t'((i * 3 + k) % DEPTH);
            end
            check_read(read_addrs);
        end

        $display("=== 5. Write-disabled hold check ===");
        check_write_disabled(addr_t'(0));
        check_write_disabled(addr_t'(DEPTH-1));

        $display("=== 6. Back-to-back writes ===");
        write_back_to_back(
            addr_t'(0),
            data_t'(32'h1111_1111),
            addr_t'(DEPTH > 1 ? 1 : 0),
            data_t'(32'h2222_2222)
        );
        check_same_address(addr_t'(0));
        check_same_address(addr_t'(DEPTH > 1 ? 1 : 0));

        $display("=== 7. Random writes ===");
        for (int i = 0; i < NUM_RANDOM_WRITES; i++) begin
            addr_t rand_addr;
            data_t rand_data;

            rand_addr = addr_t'($urandom_range(0, DEPTH-1));
            rand_data = data_t'($urandom);
            write_word(rand_addr, rand_data);
        end

        $display("=== 8. Random reads ===");
        for (int i = 0; i < NUM_RANDOM_READS; i++) begin
            addr_t read_addrs [NUM_READ_PORTS];
            for (int p = 0; p < NUM_READ_PORTS; p++) begin
                read_addrs[p] = addr_t'($urandom_range(0, DEPTH-1));
            end
            check_read(read_addrs);
        end

        $display("=== 9. Random mixed write/read ===");
        for (int i = 0; i < NUM_RANDOM_MIXED_OPS; i++) begin
            if ($urandom_range(0, 1)) begin
                addr_t rand_addr;
                data_t rand_data;

                rand_addr = addr_t'($urandom_range(0, DEPTH-1));
                rand_data = data_t'($urandom);
                write_word(rand_addr, rand_data);
            end
            else begin
                addr_t read_addrs [NUM_READ_PORTS];
                for (int p = 0; p < NUM_READ_PORTS; p++) begin
                    read_addrs[p] = addr_t'($urandom_range(0, DEPTH-1));
                end
                check_read(read_addrs);
            end
        end

        $display("=== 10. Final full-memory check ===");
        check_all();

        done = 1'b1;
        $display("LUTRAM_1W_MR TEST PASSED: DATA_WIDTH=%0d DEPTH=%0d checks=%0d",
                 DATA_WIDTH, DEPTH, check_count);
    end

endmodule

// 多配置回归顶层：
// - 固定 DEPTH=10，扫描 DATA_WIDTH；
// - 固定 DATA_WIDTH=32，扫描 DEPTH；
// - 每个子测试完成后置位 done，全部完成后顶层结束仿真。
module tb_lutram_1w_mr_top;

    localparam int WIDTH_NUM = 8;
    localparam int DEPTH_NUM = 8;
    localparam int NUM_TESTS = WIDTH_NUM + DEPTH_NUM;

    localparam int WIDTH_LIST [WIDTH_NUM] = '{
        1, 2, 4, 8, 15, 16, 25, 32
    };

    localparam int DEPTH_LIST [DEPTH_NUM] = '{
        1, 2, 3, 5, 8, 10, 16, 32
    };

    wire [NUM_TESTS-1:0] done;

    generate
        // 数据位宽扫描：固定深度 10。
        for (genvar i = 0; i < WIDTH_NUM; i++) begin : width_gen
            tb_lutram_1w_mr #(
                .DATA_WIDTH(WIDTH_LIST[i]),
                .DEPTH(10),
                .NUM_READ_PORTS(2),
                .NUM_RANDOM_WRITES(256),
                .NUM_RANDOM_READS(512),
                .NUM_RANDOM_MIXED_OPS(1000)
            ) tb_inst (
                .done(done[i])
            );
        end

        // 深度扫描：固定数据位宽 32。
        for (genvar j = 0; j < DEPTH_NUM; j++) begin : depth_gen
            tb_lutram_1w_mr #(
                .DATA_WIDTH(32),
                .DEPTH(DEPTH_LIST[j]),
                .NUM_READ_PORTS(2),
                .NUM_RANDOM_WRITES(256),
                .NUM_RANDOM_READS(512),
                .NUM_RANDOM_MIXED_OPS(1000)
            ) tb_inst (
                .done(done[WIDTH_NUM+j])
            );
        end
    endgenerate

    initial begin
        wait (&done);
        $display("ALL LUTRAM_1W_MR TESTS PASSED");
        $finish;
    end

endmodule