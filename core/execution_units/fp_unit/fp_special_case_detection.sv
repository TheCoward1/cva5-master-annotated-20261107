// ============================================================================
// 文件：core/execution_units/fp_unit/fp_special_case_detection.sv
// 类型：module
// 名称：fp_special_case_detection
// 作用：检测 NaN、无穷、零等浮点特殊值。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2019-2023 Yuhui Gao, Chris Keilbart, Lesley Shannon
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
 *             Yuhui Gao <yuhuig@sfu.ca>
 *             Chris Keilbart <ckeilbar@sfu.ca>
 */

module fp_special_case_detection // 定义 fp_special_case_detection 模块。

    #(
        parameter FRAC_W = 52, // 声明可配置参数。
        parameter EXPO_W = 11, // 声明可配置参数。
        parameter SUBNORMAL = 1 // 声明可配置参数。
    )(
        input logic[EXPO_W-1:0] expo, // 声明输入端口。
        input logic[FRAC_W-1:0] frac, // 声明输入端口。
        output logic is_inf, // 声明输出端口。
        output logic is_SNaN, // 声明输出端口。
        output logic is_QNaN, // 声明输出端口。
        output logic is_zero, // 声明输出端口。
        output logic hidden // 声明输出端口。
    );

    logic expo_all_1s; // 声明信号、变量或生成变量。
    logic frac_lower_0s; // 声明信号、变量或生成变量。
    assign expo_all_1s = &expo; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign frac_lower_0s = ~|frac[FRAC_W-2:0]; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign hidden = |expo; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign is_inf = expo_all_1s & ~frac[FRAC_W-1] & frac_lower_0s; //Fully 0；执行连续赋值，把组合逻辑连接到目标信号。
    assign is_SNaN = expo_all_1s & ~frac[FRAC_W-1] & ~frac_lower_0s; //Leading 0 but not fully 0；执行连续赋值，把组合逻辑连接到目标信号。
    assign is_QNaN = expo_all_1s & frac[FRAC_W-1]; //Leading 1；执行连续赋值，把组合逻辑连接到目标信号。
    assign is_zero = SUBNORMAL ? ~hidden & ~frac[FRAC_W-1] & frac_lower_0s : ~hidden; //Flush to 0 when not enabled；执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
