// ============================================================================
// 文件：core/execution_units/branch_comparator.sv
// 类型：module
// 名称：branch_comparator
// 作用：比较两个 33 位操作数，生成相等、小于和大于等分支条件。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2019 Eric Matthews,  Lesley Shannon
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
 *             Eric Matthews <ematthew@sfu.ca>
 */

module branch_comparator // 定义 branch_comparator 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    (
        input logic less_than, // 声明输入端口。
        input logic [32:0] a, // 声明输入端口。
        input logic [32:0] b, // 声明输入端口。
        input logic xor_result, // 声明输入端口。
        output logic result // 声明输出端口。
    );

    logic [31:0] eq_a; // 声明信号、变量或生成变量。
    logic [31:0] eq_b; // 声明信号、变量或生成变量。
    logic [31:0] ls_a; // 声明信号、变量或生成变量。
    logic [31:0] ls_b; // 声明信号、变量或生成变量。

    logic [15:0] sub_ls_a; // 声明信号、变量或生成变量。
    logic [15:0] sub_ls_b; // 声明信号、变量或生成变量。
    logic [15:0] sub_eq_a; // 声明信号、变量或生成变量。

    logic [15:0] sub_toss; // 声明信号、变量或生成变量。
    logic carry_out; // 声明信号、变量或生成变量。

    logic eq_carry_in; // 声明信号、变量或生成变量。
    logic ls_carry_in; // 声明信号、变量或生成变量。
    logic carry_in; // 声明信号、变量或生成变量。

    //implementation
    ////////////////////////////////////////////////////
    //Combines less than and equality comparison into the same carry chain logic
    //For equality: carry out from ab + ~a~b + 1 (sums pairs of zeros or ones)
    //For less than:carry out from  a +~b + 1
    ////////////////////////////////////////////////////
    assign eq_carry_in = // 执行连续赋值，把组合逻辑连接到目标信号。
       ((a[0] & b[0]) | (~a[0] & ~b[0])) &
       ((a[1] & b[1]) | (~a[1] & ~b[1]));

    assign ls_carry_in = // 执行连续赋值，把组合逻辑连接到目标信号。
        ((a[0] | ~b[0]) & (a[1] | ~b[1])) |
        (a[1] & ~b[1]);

    assign carry_in = less_than ? ls_carry_in : eq_carry_in; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign ls_a = {1'b0, a[32:2]}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ls_b = {1'b1, ~b[32:2]}; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign eq_a = {1'b0, a[32:2]} & {1'b0, b[32:2]}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign eq_b = {1'b0, ~a[32:2]} & {1'b0, ~b[32:2]}; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Compressor
    //pairwise reduces carry generation
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        foreach(sub_ls_a[i]) begin // 执行循环或遍历。
            sub_ls_a[i] = ((ls_a[2*i] & ls_b[2*i]) & (ls_a[2*i + 1] | ls_b[2*i + 1])) | (ls_a[2*i + 1] & ls_b[2*i + 1]); //carry produced regardless of carry in
            sub_ls_b[i] = ((ls_a[2*i] & ls_b[2*i]) & (ls_a[2*i + 1] | ls_b[2*i + 1])) | (ls_a[2*i + 1] & ls_b[2*i + 1]) |
                ((ls_a[2*i] | ls_b[2*i]) & (ls_a[2*i + 1] | ls_b[2*i + 1])); // carry produced regardless of carry in OR carry produced if carry in

            sub_eq_a[i] = (eq_a[2*i] | eq_b[2*i]) & (eq_a[2*i + 1] | eq_b[2*i + 1]); //bits are equal
        end // 结束语句块。
        //branch_inputs.fn3[0] is xor_result and selects the inverse result
        //i.e. (not eq, greater than).  Included here to reduce the number of inputs
        //in the branch target adder
        sub_ls_a[15] ^= xor_result;
        sub_eq_a[15] ^= xor_result;
    end // 结束语句块。

    assign {result, sub_toss} = {less_than ? sub_ls_a : sub_eq_a, carry_in} + {less_than ? sub_ls_b : 16'b0, carry_in}; // 执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
