`timescale 1ns/1ps

module tb_lutram_1w_1r #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 32,
    parameter int NUM_RANDOM_WRITES = 256,
    parameter int NUM_RANDOM_READS = 512,
    parameter int NUM_RANDOM_MIXED_OPS = 1000
)(
    output logic done
);

    localparam int ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;

    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic [ADDR_W-1:0]    addr_t;

    logic clk;
    logic ram_write;

    addr_t waddr;
    addr_t raddr;

    data_t new_ram_data;
    data_t ram_data_out;
    data_t expect_ram_data_out;

    // 参考存储模型：每次写操作后同步更新，读取时用于计算期望值。
    data_t ref_mem [DEPTH];

    int check_count;

    covergroup cp_ram @(posedge clk);
        
        cp_ram_write: coverpoint ram_write {
            bins write_disabled = {0};
            bins write_enabled  = {1};
        }
        //读写地址不同 写使能跳变分仓
        cp_write_trands: coverpoint ram_write {
            bins idle = (0=>0);
            bins start_write = (0=>1);
            bins write_hold  = (1=>1);
            bins stop_write   = (1=>0);
        }

        cp_waddr: coverpoint waddr {
            bins addr_bins[] = {[0:DEPTH-1]};
        }
        cp_raddr: coverpoint raddr {
            bins addr_bins[] = {[0:DEPTH-1]};
        }
        cp_same_addr: coverpoint (waddr == raddr) {
            bins same_addr = {1};
            bins diff_addr = {0};
        }
        cp_data_0: coverpoint (new_ram_data == '0)iff (ram_write) {
            bins zero    = {1};
            bins nonzero = {0};
        }
        cp_data_1: coverpoint (new_ram_data == '1)iff (ram_write) {
            bins zero    = {0};
            bins nonzero = {1};
        }

    endgroup

    lutram_1w_1r #(
        .DATA_TYPE(data_t),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .waddr(waddr),
        .raddr(raddr),
        .ram_write(ram_write),
        .new_ram_data(new_ram_data),
        .ram_data_out(ram_data_out)
    );

    function automatic data_t tb_lw_lr(
        input addr_t addr
    );
        return ref_mem[addr];
    endfunction

    // 写一个存储字：
    // 在 negedge 驱动写端口，在下一个 posedge 完成写入。
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

    // 设置读地址并检查组合读输出是否与参考模型一致。
    task automatic check_read(
        input addr_t addr
    );
        @(negedge clk);
        raddr = addr;
        #1;

        expect_ram_data_out = tb_lw_lr(addr);

        if (ram_data_out !== expect_ram_data_out) begin
            $fatal(1,
                "RAM mismatch: addr=%0d actual=%h expected=%h",
                addr, ram_data_out, expect_ram_data_out);
        end else begin
            check_count++;
            $display("MATCH: addr=%0d data=%h", addr, ram_data_out);
        end
    endtask

    // 检查全部地址。
    task automatic check_all();
        for (int i = 0; i < DEPTH; i++) begin
            check_read(addr_t'(i));
        end
    endtask

    // 写使能无效时，写入数据不能改变存储内容。
    task automatic check_write_disabled(
        input addr_t addr
    );
        @(negedge clk);
        waddr        = addr;
        new_ram_data = ~ref_mem[addr];
        ram_write    = 1'b0;

        repeat (3) @(posedge clk);

        @(negedge clk);
        raddr = addr;
        #1;

        expect_ram_data_out = ref_mem[addr];
        if (ram_data_out !== expect_ram_data_out) begin
            $fatal(1,
                "Write-disabled failed: addr=%0d actual=%h expected=%h",
                addr, ram_data_out, expect_ram_data_out);
        end else begin
            check_count++;
            $display("WRITE-DISABLED MATCH: addr=%0d data=%h",
                     addr, ram_data_out);
        end
    endtask

    task automatic write_word_hold(
        input addr_t addr,
        input data_t data
    );
        @(negedge clk);
        waddr        = addr;
        new_ram_data = data;
        ram_write    = 1'b1;

        repeat (3) @(posedge clk);
        ref_mem[addr] = data;
        @(negedge clk);
        ram_write = 1'b0;
    endtask


    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end
    cp_ram ram = new();
    initial begin
        // 时序信号初始化。
        done         = 1'b0;
        ram_write    = 1'b0;
        waddr        = '0;
        raddr        = '0;
        new_ram_data = '0;
        expect_ram_data_out = '0;
        check_count  = 0;

        for (int i = 0; i < DEPTH; i++) begin
            ref_mem[i] = '0;
        end

        $display("START LUTRAM_1W_1R TEST: DATA_WIDTH=%0d DEPTH=%0d",
                 DATA_WIDTH, DEPTH);

        // 等待存储阵列完成仿真初始化。
        repeat (2) @(posedge clk);
        #1;

        $display("=== 1. Initial zero check ===");
        check_all();

        $display("=== 2. Single write and read back ===");
        write_word(addr_t'(0), data_t'(32'hDEAD_BEEF));
        check_read(addr_t'(0));

        write_word(addr_t'(DEPTH-1), data_t'(32'h1234_5678));
        check_read(addr_t'(DEPTH-1));

        write_word(addr_t'(DEPTH/2), data_t'(32'hA5A5_5A5A));
        check_read(addr_t'(DEPTH/2));

        $display("=== 3. Overwrite same address ===");
        write_word(addr_t'(0), data_t'(32'hCAFE_F00D));
        check_read(addr_t'(0));

        $display("=== 4. Write-disabled hold check ===");
        check_write_disabled(addr_t'(0));
        check_write_disabled(addr_t'(DEPTH-1));

        $display("=== 5. Address independence check ===");
        check_all();

        $display("=== 6. Write all addresses with walking-one pattern ===");
        for (int i = 0; i < DEPTH; i++) begin
            write_word(addr_t'(i), data_t'(32'h1 << (i % DATA_WIDTH)));
        end
        check_all();

        $display("=== 7. Random-address random-data writes ===");
        for (int i = 0; i < NUM_RANDOM_WRITES; i++) begin
            addr_t rand_addr;
            data_t rand_data;

            rand_addr = addr_t'($urandom_range(0, DEPTH-1));
            rand_data = data_t'($urandom);

            if ((i % 32) == 0) begin
                $display("RANDOM WRITE progress: %0d/%0d",
                         i, NUM_RANDOM_WRITES);
            end

            write_word(rand_addr, rand_data);
        end

        $display("=== 8. Random-address reads ===");
        for (int i = 0; i < NUM_RANDOM_READS; i++) begin
            addr_t rand_addr;

            rand_addr = addr_t'($urandom_range(0, DEPTH-1));
            check_read(rand_addr);
        end

        $display("=== 9. Random mixed write/read regression (%0d iterations) ===",
                 NUM_RANDOM_MIXED_OPS);
        for (int i = 0; i < NUM_RANDOM_MIXED_OPS; i++) begin
            addr_t rand_addr;
            rand_addr = addr_t'($urandom_range(0, DEPTH-1));

            if ($urandom_range(0, 1)) begin
                write_word(rand_addr, data_t'($urandom));
            end else begin
                check_read(rand_addr);
            end
        end

        $display("=== 10. Final full-memory check ===");
        check_all();

        $display("=== 11. Random hold-write stress ===");
        repeat (100) begin
            addr_t rand_addr = addr_t'($urandom_range(0, DEPTH-1));
            data_t rand_data = data_t'($urandom);
            write_word_hold(rand_addr, rand_data);
        end

        $display("=== 12. Directed all-zero writes ===");
        repeat (100) begin
            addr_t rand_addr = addr_t'($urandom_range(0, DEPTH-1));
            write_word(rand_addr, data_t'('0));
            check_read(rand_addr);
        end

        $display("=== 13. Directed all-one writes ===");
        repeat (100) begin
            addr_t rand_addr = addr_t'($urandom_range(0, DEPTH-1));
            write_word(rand_addr, data_t'('1));
            check_read(rand_addr);
        end

        $display("=== 14. Final full-memory check ===");
        check_all();

        done = 1'b1;
        $display("LUTRAM_1W_1R TEST PASSED: DATA_WIDTH=%0d DEPTH=%0d checks=%0d",
                 DATA_WIDTH, DEPTH, check_count);
    end

endmodule

// 多配置回归顶层：
// - 固定 DATA_WIDTH=32，扫描 DEPTH；
// - 固定 DEPTH=32，扫描 DATA_WIDTH；
// - 每个子测试完成后置位 done，全部完成后顶层结束仿真。
module tb_lutram_1w_1r_top;

    localparam int NUM_DEPTH_TESTS = 6;
    localparam int NUM_WIDTH_TESTS = 4;
    localparam int NUM_TESTS       = NUM_DEPTH_TESTS + NUM_WIDTH_TESTS;

    localparam int DEPTH_LIST [NUM_DEPTH_TESTS] = '{1, 2, 3, 5, 8, 32};
    localparam int WIDTH_LIST [NUM_WIDTH_TESTS] = '{1, 8, 32, 64};

    wire [NUM_TESTS-1:0] done;

    generate
        // 深度扫描：验证地址位宽、边界地址和非 2 的幂深度。
        for (genvar i = 0; i < NUM_DEPTH_TESTS; i++) begin : gen_depth
            tb_lutram_1w_1r #(
                .DATA_WIDTH(32),
                .DEPTH(DEPTH_LIST[i]),
                .NUM_RANDOM_WRITES(64),
                .NUM_RANDOM_READS(128),
                .NUM_RANDOM_MIXED_OPS(256)
            ) tb_inst (
                .done(done[i])
            );
        end

        // 数据位宽扫描：验证不同字宽下的读写和覆盖分仓。
        for (genvar j = 0; j < NUM_WIDTH_TESTS; j++) begin : gen_width
            tb_lutram_1w_1r #(
                .DATA_WIDTH(WIDTH_LIST[j]),
                .DEPTH(32),
                .NUM_RANDOM_WRITES(64),
                .NUM_RANDOM_READS(128),
                .NUM_RANDOM_MIXED_OPS(256)
            ) tb_inst (
                .done(done[NUM_DEPTH_TESTS+j])
            );
        end
    endgenerate

    initial begin
        wait (&done);
        $display("ALL LUTRAM_1W_1R TESTS PASSED");
        $finish;
    end

endmodule