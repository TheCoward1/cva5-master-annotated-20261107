// ============================================================================
// 文件：core/common_components/set_clr_reg_with_rst.sv
// 类型：module
// 名称：set_clr_reg_with_rst
// 作用：实现带同步复位、置位（set）和清零（clear）控制的向量寄存器。
// 参数：SET_OVER_CLR 选择 set 和 clr 同时有效时的优先级；
//       WIDTH 为寄存器位宽；RST_VALUE 为同步复位后的值。
// 语义：复位优先于 set/clr；每个 bit 可独立保持、置位或清零；
//       未操作位保持上一拍值；同一 bit 同时 set 和 clr 时由 SET_OVER_CLR 决定。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2020 Eric Matthews,  Lesley Shannon
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


 /*
  * Two varients are offered, one with set having precedence over clear and
  * vice versa.
  */
module set_clr_reg_with_rst

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    // SET_OVER_CLR=0：clear 优先；SET_OVER_CLR=1：set 优先。
    // WIDTH 为寄存器位宽，RST_VALUE 为同步复位后的值。
    #(parameter SET_OVER_CLR = 0, parameter WIDTH = 16, parameter logic[WIDTH-1:0] RST_VALUE = '0)
    (
        input logic clk, // 寄存器时钟
        input logic rst, // 同步复位，高有效；复位优先于 set/clr

        input logic [WIDTH-1:0] set, // 置位控制：为 1 的 bit 置 1
        input logic [WIDTH-1:0] clr, // 清零控制：为 1 的 bit 清 0
        output logic [WIDTH-1:0] result // 寄存器当前值
    );

    ////////////////////////////////////////////////////
    //Implementation
    // SET_OVER_CLR=1：set 优先。set=1 的 bit 最终为 1；
    // 未被 set 且 clr=1 的 bit 被清零，其余 bit 保持上一拍值。
    generate if (SET_OVER_CLR) begin : gen_set_over_clear
        always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) // 执行条件判断，满足条件时进入对应分支。
                result <= RST_VALUE;
            else // 执行否则分支。
                result <= set | (result & ~clr); // set 覆盖 clr 的结果
        end // 结束语句块。
    // SET_OVER_CLR=0：clr 优先。clr=1 的 bit 最终为 0；
    // 未被 clr 且 set=1 的 bit 被置 1，其余 bit 保持上一拍值。
    end else begin : gen_clear_over_set
        always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) // 执行条件判断，满足条件时进入对应分支。
                result <= RST_VALUE;
            else // 执行否则分支。
                result <= (set | result) & ~clr; // clr 覆盖 set 的结果
        end // 结束语句块。
    end // 结束语句块。
    endgenerate // 结束生成块。

endmodule // 结束模块定义。
