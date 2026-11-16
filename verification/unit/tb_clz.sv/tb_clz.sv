//`timescale 1ns/1ps // 仿真时间单位 1 ns，时间精度 1 ps

module tb_clz #(
    parameter width = 32
)();

    logic [width-1:0] clz_input;
    logic [$clog2(width)-1:0] clz;         // DUT 实际输出
    logic [$clog2(width)-1:0] expected_clz; // 参考模型输出
    logic zero;
    logic expected_zero;
    int errors = 0;
    int checks = 0;

    clz #(.WIDTH(width)) dut (
        .clz_input(clz_input),
        .clz(clz),
        .zero(zero)
    );

    // 参考模型：计算非零输入向量的前导零个数。
    // 注意：输入全为 0 时 clz 不是有效结果，由 zero 单独表示。
    function automatic logic [$clog2(width)-1:0] ref_clz(
        input logic [width-1:0] v
    );
        for (int i = width - 1; i >= 0; i--) begin
            if (v[i] == 1'b1) begin
                return $clog2(width)'(width - 1 - i);
            end
        end
        return '0;
    endfunction

    // 参考模型：判断输入是否全为 0。
    function automatic logic ref_zero(
        input logic [width-1:0] v
    );
        for (int i = width - 1; i >= 0; i--) begin
            if (v[i] == 1'b1) begin
                return 1'b0;
            end
        end
        return 1'b1;
    endfunction

    task automatic check(
        input logic [width-1:0] v
    );
        logic [$clog2(width)-1:0] expected_clz;
        logic expected_zero;
        clz_input = v;
        #1; // 等待组合逻辑传播稳定
        expected_zero = ref_zero(clz_input);
        expected_clz  = ref_clz(clz_input);
        checks++;
        if (zero !== expected_zero) begin
            errors++;
            $fatal(1, "ERROR zero: input=%b expected=%b got=%b",
                   clz_input, expected_zero, zero);

        end else begin
            $display("zero: input=%b expected=%b got=%b",
                     clz_input, expected_zero, zero);

        end
        if (!expected_zero && clz !== expected_clz) begin
            errors++;
            $fatal(1, "ERROR clz: input=%b expected=%0d got=%0d",
                   clz_input, expected_clz, clz);
            
        end else begin
            $display("clz: input=%b expected=%0d got=%0d",
                     clz_input, expected_clz, clz);
        end


    endtask : check

    initial begin

        // 测试所有可能的输入向量。
        check(32'h0000_0000);
        check(32'hffff_ffff);

        // 3. 最高位为 1
        check(32'h8000_0000);

        // 4. 最低位为 1
        check(32'h0000_0001);

        // 5. 边界模式
        check(32'h7fff_ffff);
        check(32'hffff_0000);
        check(32'h0000_ffff);

        // 6. 连续零的边界模式
        check(32'h0000_0003);
        check(32'h0000_0007);
        check(32'h0000_00ff);
        check(32'h00ff_ffff);
        check(32'h0fff_ffff);
        check(32'hffff_fff0);

        // 7. 32 个单 bit 输入
        for (int i = 0; i < 32; i++) begin
            check(32'h1 << i);
        end

        // 8. 随机测试 10000 组
        repeat (10000) begin
            check(32'($urandom));
        end

        // 9. 测试完成，打印统计信息
                // 最终结果
        if (errors == 0 &&
            checks == 10000 + 32 + 13) begin
            $display("CLZ 32-BIT TEST PASSED: %0d checks", checks);
        end
        else begin
            $fatal(1, "CLZ 32-BIT TEST FAILED: %0d errors, %0d checks",
                   errors, checks);
        end

    end

endmodule
