// ============================================================================
// 文件：core/execution_units/fp_unit/divider/on_the_fly.sv
// 类型：module
// 名称：on_the_fly
// 作用：在浮点除法/开方过程中在线生成商或余数。
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

module on_the_fly // 定义 on_the_fly 模块。

    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    #(
        parameter WIDTH = 32 // 声明可配置参数。
    )(
        input logic[WIDTH-1:0] current_Q, // 声明输入端口。
        input logic[WIDTH-1:0] current_QM, // 声明输入端口。
        input q_t q, // 声明输入端口。
        output logic[WIDTH-1:0] next_Q, // 声明输出端口。
        output logic[WIDTH-1:0] next_QM, // 声明输出端口。
        output logic bad_quotient_digit //Only used for assertion；声明输出端口。
    );

    logic[1:0] qin; // 声明信号、变量或生成变量。
    logic[1:0] qmin; // 声明信号、变量或生成变量。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        bad_quotient_digit = 0;
        unique case (q)
            POS_TWO,
            NEG_TWO: begin
                qin = 2'b10;
                qmin = 2'b01;
            end // 结束语句块。
            NEG_ONE: begin
                qin = 2'b11;
                qmin = 2'b10;
            end // 结束语句块。
            ZERO: begin
                qin = 2'b00;
                qmin = 2'b11;
            end // 结束语句块。
            NEG_THREE,
            POS_ONE: begin
                qin = 2'b01;
                qmin = 2'b00;
            end // 结束语句块。
            default: begin // 执行默认分支。
                qin = 2'bXX;
                qmin = 2'bXX;
                bad_quotient_digit = 1;
            end // 结束语句块。
        endcase // 结束多分支选择。
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (q == NEG_TWO || q == NEG_ONE || q == NEG_THREE) // 执行条件判断，满足条件时进入对应分支。
            next_Q = {current_QM[WIDTH-3:0], qin};
        else // 执行否则分支。
            next_Q = {current_Q[WIDTH-3:0], qin};
        
        if (q == NEG_TWO || q == NEG_ONE || q == ZERO) // 执行条件判断，满足条件时进入对应分支。
            next_QM = {current_QM[WIDTH-3:0], qmin};
        else // 执行否则分支。
            next_QM = {current_Q[WIDTH-3:0], qmin};
    end // 结束语句块。

endmodule // 结束模块定义。
