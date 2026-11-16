// ============================================================================
// 文件：core/execution_units/fp_unit/divider/carry_save_shift.sv
// 类型：module
// 名称：carry_save_shift
// 作用：实现浮点除法中的进位保存移位步骤。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2023 Chris Keilbart, Lesley Shannon
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Initial code developed under the supervision of Dr. Lesley Shannon,
 * Reconfigurable Computing Lab, Simon Fraser University.
 *
 * Author(s):
 *             Chris Keilbart <ckeilbar@sfu.ca>
 */

module carry_save_shift // 定义 carry_save_shift 模块。

    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    #(
        parameter WIDTH = 32 //Includes the integer bit；声明可配置参数。
    )(
        input logic[WIDTH-1:0] four_wsum, //Shifted twice by the CALLER (because of special initialization)；声明输入端口。
        input logic[WIDTH-3:0] wcarry, // 声明输入端口。
        input logic[WIDTH-4:0] divisor, // 声明输入端口。

        output logic[WIDTH-3:0] next_wsum, // 声明输出端口。
        output logic[WIDTH-3:0] next_wcarry, // 声明输出端口。
        output q_t next_q, // 声明输出端口。
        output logic not_in_table //Only used for assertion；声明输出端口。
    );

    logic[WIDTH-1:0] four_wcarry; // 声明信号、变量或生成变量。
    assign four_wcarry = {wcarry, 1'b0, (next_q == POS_ONE || next_q == POS_TWO)}; //Include the carry in from converting -qd to 2s complement here；执行连续赋值，把组合逻辑连接到目标信号。

    logic[WIDTH-3:0] neg_q_d; // 声明信号、变量或生成变量。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (next_q == POS_TWO || next_q == NEG_TWO) // 执行条件判断，满足条件时进入对应分支。
            neg_q_d = {divisor, 1'b0};
        else if (next_q == ZERO) // 执行否则如果分支的条件判断。
            neg_q_d = '0;
        else // 执行否则分支。
            neg_q_d = {1'b0, divisor};
        
        if (next_q == POS_ONE || next_q == POS_TWO) // 执行条件判断，满足条件时进入对应分支。
            neg_q_d = ~neg_q_d;
    end // 结束语句块。

    q_lookup lut (
        .d(divisor[WIDTH-5 -: 3]),
        .ws(four_wsum[WIDTH-1 -: 7]),
        .wc(four_wcarry[WIDTH-1 -: 7]),
        .q(next_q),
        .not_in_table(not_in_table)
    );

    generate for (genvar i = 0; i < WIDTH-3; i++) begin : gen_carry_save_adder // 开始生成块，在编译期展开硬件结构。
        assign {next_wcarry[i+1], next_wsum[i]} = four_wsum[i] + four_wcarry[i] + neg_q_d[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

    //Last adder - ignore the carry out
    assign next_wsum[WIDTH-3] = four_wsum[WIDTH-3] + four_wcarry[WIDTH-3] + neg_q_d[WIDTH-3]; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign next_wcarry[0] = 0; // 执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
