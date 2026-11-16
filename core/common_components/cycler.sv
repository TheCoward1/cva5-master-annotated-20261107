// ============================================================================
// 文件：core/common_components/cycler.sv
// 类型：module
// 名称：cycler
// 作用：生成循环 one-hot 状态，常用于轮询仲裁、轮流服务和循环选择。
// 行为：
//   C_WIDTH == 1：输出固定为 1；
//   C_WIDTH > 1：复位时输出 bit0=1，en=1 时把 one-hot 依次循环左移。
// 示例（C_WIDTH=4）：
//   rst -> 0001 -> 0010 -> 0100 -> 1000 -> 0001 ...
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017, 2018 Eric Matthews,  Lesley Shannon
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


module cycler
        #(
        parameter C_WIDTH = 2 // one-hot 输出位宽
        )
        (
        input logic clk, // 时钟
        input logic rst, // 同步复位，高有效
        input logic en, // 轮转使能，高有效
        output logic [C_WIDTH - 1: 0] one_hot // 当前 one-hot 状态
        );

    // C_WIDTH=1 时只有一个可选择的位置，输出恒为 1。
    generate if (C_WIDTH == 1) begin : gen_width_one
        assign one_hot = 1;
    // C_WIDTH>1 时使用寄存器保存当前 one-hot 状态。
    end else begin : gen_width_two_plus
        always_ff @ (posedge clk) begin // 同步时序：状态只在时钟上升沿更新
            if (rst) // 同步复位优先，恢复到最低位为 1
                one_hot <= 1; // 初始 one-hot 状态为 bit0=1
            else if (en) // 使能有效时轮转；en=0 时保持当前状态
                one_hot <= {one_hot[C_WIDTH-2:0], one_hot[C_WIDTH-1]}; // 左旋一位：bit0->bit1->...->bit0
        end // 结束语句块。
    end // 结束语句块。
    endgenerate // 结束生成块。

endmodule // 结束模块定义。
