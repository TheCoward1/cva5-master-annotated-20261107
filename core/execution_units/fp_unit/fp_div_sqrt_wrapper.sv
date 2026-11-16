// ============================================================================
// 文件：core/execution_units/fp_unit/fp_div_sqrt_wrapper.sv
// 类型：module
// 名称：fp_div_sqrt_wrapper
// 作用：统一浮点除法和平方根的数据通路。
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

module fp_div_sqrt_wrapper // 定义 fp_div_sqrt_wrapper 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        input fp_div_inputs_t div_inputs, // 声明输入端口。
        input fp_sqrt_inputs_t sqrt_inputs, // 声明输入端口。
        unit_issue_interface.unit div_issue,
        unit_issue_interface.unit sqrt_issue,
        fp_intermediate_wb_interface.unit wb
    );

    fp_intermediate_wb_interface div_wb();
    fp_intermediate_wb_interface sqrt_wb();

    ////////////////////////////////////////////////////
    //Implementation
    //Div/Sqrt with distinct issue
    //Shared writeback
    fp_div div (
        .args(div_inputs),
        .issue(div_issue),
        .wb(div_wb),
    .*);

    fp_sqrt sqrt (
        .args(sqrt_inputs),
        .issue(sqrt_issue),
        .wb(sqrt_wb),
    .*);

    //SQRT has higher priority on ties because of longer latency
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        sqrt_wb.ack = wb.ack & sqrt_wb.done;
        div_wb.ack = wb.ack & ~sqrt_wb.done;
        
        if (sqrt_wb.done) begin // 执行条件判断，满足条件时进入对应分支。
            wb.id = sqrt_wb.id;
            wb.done = 1;
            wb.rd = sqrt_wb.rd;
            wb.expo_overflow = sqrt_wb.expo_overflow;
            wb.fflags = sqrt_wb.fflags;
            wb.rm = sqrt_wb.rm;
            wb.carry = sqrt_wb.carry;
            wb.safe = sqrt_wb.safe;
            wb.hidden = sqrt_wb.hidden;
            //Collapse sticky - this saves a wide 2:1 mux
            wb.grs[GRS_WIDTH-1-:2] = sqrt_wb.grs[GRS_WIDTH-1-:2];
            wb.grs[GRS_WIDTH-3] = |sqrt_wb.grs[GRS_WIDTH-3:0];
            wb.grs[GRS_WIDTH-4:0] = '0;
            wb.clz = sqrt_wb.clz;
            wb.right_shift = sqrt_wb.right_shift;
            wb.right_shift_amt = sqrt_wb.right_shift_amt;
            wb.subnormal = sqrt_wb.subnormal;
            wb.ignore_max_expo = sqrt_wb.ignore_max_expo;
            wb.d2s = sqrt_wb.d2s;
        end else begin // 结束语句块。
            wb.id = div_wb.id;
            wb.done = div_wb.done;
            wb.rd = div_wb.rd;
            wb.expo_overflow = div_wb.expo_overflow;
            wb.fflags = div_wb.fflags;
            wb.rm = div_wb.rm;
            wb.carry = div_wb.carry;
            wb.safe = div_wb.safe;
            wb.hidden = div_wb.hidden;
            //Collapse sticky - this saves a wide 2:1 mux
            wb.grs[GRS_WIDTH-1-:3] = div_wb.grs[GRS_WIDTH-1-:3]; //Preserve MSB sticky because there can be a left shift of 1
            wb.grs[GRS_WIDTH-4] = |div_wb.grs[GRS_WIDTH-4:0];
            wb.grs[GRS_WIDTH-5:0] = '0;
            wb.clz = div_wb.clz;
            wb.right_shift = div_wb.right_shift;
            wb.right_shift_amt = div_wb.right_shift_amt;
            wb.subnormal = div_wb.subnormal;
            wb.ignore_max_expo = div_wb.ignore_max_expo;
            wb.d2s = div_wb.d2s;
        end // 结束语句块。
    end // 结束语句块。

endmodule // 结束模块定义。
