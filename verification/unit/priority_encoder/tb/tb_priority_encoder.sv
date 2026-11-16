// ============================================================================
// 文件：verification/unit/priority_encoder/tb/tb_priority_encoder.sv
// 类型：testbench
// 名称：tb_priority_encoder
// 作用：穷举测试真实 CVA5 priority_encoder，检查输出是否为输入向量中最低有效
//       置位位的索引；输入全零时，预期输出为 WIDTH-1。
// 方法：使用独立参考模型 ref_encode 计算期望值，check 任务施加激励、等待组合
//       逻辑稳定并自动比较结果，最终输出 PASS/FAIL 和检查次数。
// 编码：UTF-8
// ============================================================================

`timescale 1ns/1ps // 仿真时间单位 1 ns，时间精度 1 ps

module tb_priority_encoder #(
    parameter int WIDTH = 8 // 被测 priority_encoder 的输入位宽
) ();

 // priority_encoder 的模块级自检查 testbench
    // 被测输入位宽为 8；输出位宽需要容纳 0 到 WIDTH-1 的索引。
    //localparam int WIDTH = 8;
    localparam int OUT_W = (WIDTH == 1) ? 1 : $clog2(WIDTH);
    // DUT 输入和输出信号。
    logic [WIDTH-1:0] priority_vector;
    logic [OUT_W-1:0] encoded_result;

    // tests 统计执行次数，errors 统计期望值与实际值不一致的次数。
    int tests;
    int errors;

    // 实例化真实 CVA5 priority_encoder；使用命名端口连接，避免端口顺序变化影响 TB。
    priority_encoder #(.WIDTH(WIDTH)) dut (
        .priority_vector(priority_vector),
        .encoded_result(encoded_result)
    );

    // 独立参考模型：priority_encoder 的优先级是“索引 0 最高”，因此最终应返回
    // 输入中最低有效置位位的索引；若所有位都为 0，则保持默认值 WIDTH-1。
    function automatic logic [OUT_W-1:0] ref_encode(
        input logic [WIDTH-1:0] v
    );
        // 先假设没有有效请求，使用最低优先级索引 WIDTH-1 作为默认输出。
        ref_encode = OUT_W'(WIDTH-1);

        // 从最高索引向最低索引扫描；每次遇到置位位就更新结果。
        // 因为最后处理的是最低索引，所以最终保留最低有效置位位的索引。
        for (int i = WIDTH-1; i >= 0; i--) begin
            if (v[i]) ref_encode = OUT_W'(i);
        end
    endfunction

    // 单次检查任务：施加一个输入向量，等待组合逻辑稳定，然后与参考模型比较。
    task automatic check(input logic [WIDTH-1:0] v);
        logic [OUT_W-1:0] expected; // 当前输入对应的参考模型期望值
        begin
            priority_vector = v; // 驱动 DUT 输入
            #1;                  // 等待组合逻辑传播稳定

            expected = ref_encode(v); // 独立计算期望结果
            tests++;                  // 记录一次检查

            // 使用 !== 而不是 !=，这样 X/Z 也会被判定为失败。
            if (encoded_result !== expected) begin
                errors++; // 累计错误次数
                // 打印输入、期望值和实际值，便于失败时直接定位问题。
                $display("FAIL input=%08b expected=%0d actual=%0d", v, expected, encoded_result);
            end
        end
    endtask

    initial begin
        // 初始化统计变量和 DUT 输入，保证仿真从确定状态开始。
        tests = 0;
        errors = 0;
        priority_vector = '0;
        #1; // 等待复位后的初始输入传播到 DUT 输出
        //
        //展示区间 ******
        $display("******************************");
        //
        // 穷举 0 到 255 的全部 8 bit 输入，共 2^WIDTH = 256 组。
        // WIDTH'(i) 将循环变量 i 明确转换为 WIDTH 位宽，避免位宽不够或隐式扩展。
        for (int i = 0; i < (1 << WIDTH); i++) begin
            check(WIDTH'(i));
        end

        // 汇总测试结果：没有错误则正常结束，否则打印失败信息并以非零状态退出。
        if (errors == 0) begin
            $display("PRIORITY_ENCODER TEST PASSED: %0d checks", tests);
            $finish;
        end else begin
            $display("PRIORITY_ENCODER TEST FAILED: %0d errors / %0d checks", errors, tests);
            $fatal(1, "priority_encoder verification failed");
        end

        $display("******************************");

    end
endmodule

// module tb_priority_encoder_all;
//     genvar i;

//     generate
//         for ( i = 1; i <= 14; i++) begin
//             tb_priority_encoder #(.WIDTH(i))  tb();
//         end
//     endgenerate

// endmodule
