// ============================================================================
// 文件：core/execution_units/barrel_shifter.sv
// 类型：module
// 名称：barrel_shifter
// 作用：实现 32 位移位器，支持左移、逻辑右移和按填充位右移。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017-2019 Eric Matthews,  Lesley Shannon
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

module barrel_shifter // 定义 barrel_shifter 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    
    (
        input logic[31:0] shifter_input, // 声明输入端口。
        input logic[4:0] shift_amount, // 声明输入端口。
        input logic arith, // 声明输入端口。
        input logic lshift, // 声明输入端口。
        output logic[31:0] shifted_result // 声明输出端口。
        );

    logic [62:0] shift_in; // 声明信号、变量或生成变量。
    logic [4:0] adjusted_shift_amount; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation
    //Performs a 63-bit right shift
    //Left shift is handled by placing the left shift in the upper portion shifted by (~shift_amount + 1)
    //with the value initially shifted by one so that only the complement of the shift_amount is needed
    assign shift_in = lshift ? {shifter_input, 31'b0} : {{31{arith}}, shifter_input}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign adjusted_shift_amount = shift_amount ^ {5{lshift}}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign shifted_result = 32'(shift_in >> adjusted_shift_amount); // 执行连续赋值，把组合逻辑连接到目标信号。
endmodule // 结束模块定义。
