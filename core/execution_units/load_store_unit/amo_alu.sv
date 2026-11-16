// ============================================================================
// 文件：core/execution_units/load_store_unit/amo_alu.sv
// 类型：module
// 名称：amo_alu
// 作用：执行原子内存操作所需的算术逻辑。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017 Eric Matthews, Chris Keilbart, Lesley Shannon
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
 *             Chris Keilbart <ckeilbar@sfu.ca>
 */

module amo_alu // 定义 amo_alu 模块。

    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。

    #(
        parameter int WIDTH = 32 // 声明可配置参数。
    )
    (
        input amo_t amo_type, // 声明输入端口。
        input logic[WIDTH-1:0] rs1, // 声明输入端口。
        input logic[WIDTH-1:0] rs2, // 声明输入端口。
        output logic[WIDTH-1:0] rd // 声明输出端口。
    );

    logic signed_op; // 声明信号、变量或生成变量。
    logic rs1_smaller_than_rs2; // 声明信号、变量或生成变量。
    logic signed [WIDTH:0] rs1_ext; // 声明信号、变量或生成变量。
    logic signed [WIDTH:0] rs2_ext; // 声明信号、变量或生成变量。
    
    assign signed_op = amo_type == AMO_MIN_FN5 | amo_type == AMO_MAX_FN5; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs1_ext = {(signed_op & rs1[WIDTH-1]), rs1}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs2_ext = {(signed_op & rs2[WIDTH-1]), rs2}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs1_smaller_than_rs2 = rs1_ext < rs2_ext; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        unique case (amo_type)
            AMO_XOR_FN5 : rd = rs1 ^ rs2;
            AMO_OR_FN5 : rd = rs1 | rs2;
            AMO_AND_FN5 : rd = rs1 & rs2;
            AMO_SWAP_FN5 : rd = rs2;
            AMO_MIN_FN5 : rd = rs1_smaller_than_rs2 ? rs1 : rs2;
            AMO_MAX_FN5 : rd = rs1_smaller_than_rs2 ? rs2 : rs1;
            AMO_MINU_FN5 : rd = rs1_smaller_than_rs2 ? rs1 : rs2;
            AMO_MAXU_FN5 : rd = rs1_smaller_than_rs2 ? rs2 : rs1;
            AMO_ADD_FN5 : rd = rs1 + rs2;
            default : rd = 'x; //Default don't care allows some optimization；执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

endmodule // 结束模块定义。
