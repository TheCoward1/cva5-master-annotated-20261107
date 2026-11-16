// ============================================================================
// 文件：core/execution_units/fp_unit/fp_roundup.sv
// 类型：module
// 名称：fp_roundup
// 作用：执行浮点舍入增量处理。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2019-2023 Yuhui Gao, Lesley Shannon
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
 */

module fp_roundup // 定义 fp_roundup 模块。
    
    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    (
        input logic sign, // 声明输入端口。
        input rm_t rm, // 声明输入端口。
        input logic[2:0] grs, // 声明输入端口。
        input logic lsb, // 声明输入端口。
        output logic roundup, // 声明输出端口。
        output fp_t result_if_overflow // 声明输出端口。
    );

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        result_if_overflow.d.sign = sign;
        
        unique case(rm)
            default: begin  //nearest ties to even；执行默认分支。
                result_if_overflow.d.expo = '1;
                result_if_overflow.d.frac = '0;
                roundup = grs[2] & (lsb | |grs[1:0]);
            end // 结束语句块。
            3'b100: begin  //nearest ties to away
                result_if_overflow.d.expo = '1;
                result_if_overflow.d.frac = '0;
                roundup = grs[2];
            end // 结束语句块。
            3'b011: begin //round to positive inf
                //only round if: positive, has extra bits in grs
                result_if_overflow.d.expo = {{(EXPO_WIDTH-1){1'b1}}, ~sign};
                result_if_overflow.d.frac = {FRAC_WIDTH{sign}};
                roundup = ~sign & |grs;
            end // 结束语句块。
            3'b010: begin  //round to negative inf
                //only round if: negative, has extra bits in grs
                result_if_overflow.d.expo = {{(EXPO_WIDTH-1){1'b1}}, sign};
                result_if_overflow.d.frac = {FRAC_WIDTH{~sign}};
                roundup = sign & |grs;
            end // 结束语句块。
            3'b001: begin //round to zero
                result_if_overflow.d.expo = {{(EXPO_WIDTH-1){1'b1}}, 1'b0};
                result_if_overflow.d.frac = '1;
                roundup = 0;
            end // 结束语句块。
        endcase // 结束多分支选择。
    end // 结束语句块。

endmodule // 结束模块定义。
