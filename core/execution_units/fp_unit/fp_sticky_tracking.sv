// ============================================================================
// 文件：core/execution_units/fp_unit/fp_sticky_tracking.sv
// 类型：module
// 名称：fp_sticky_tracking
// 作用：跟踪浮点舍入所需的 sticky 位。
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

module fp_sticky_tracking // 定义 fp_sticky_tracking 模块。

    #(
        parameter INPUT_WIDTH = 24, // 声明可配置参数。
        parameter SHIFT_WIDTH = 11 // 声明可配置参数。
    )(
        input logic[INPUT_WIDTH-1:0] shifter_input, // 声明输入端口。
        input logic[SHIFT_WIDTH-1:0] shift_amount, // 声明输入端口。
        output logic sticky_bit // 声明输出端口。
    );
    
    //This unit returns a single bit which indicates whether a 1 got right shifted out of the input

    //ORs all shifted
    function logic shift_reduce(input logic[3:0] a, input logic[1:0] sel, input logic fully_shifted); // 开始函数定义，用于组合计算或辅助逻辑。
        case({fully_shifted, sel}) // 开始多分支选择，根据表达式选择对应分支。
            0 : shift_reduce = a[0];
            1 : shift_reduce = |a[1:0];
            2 : shift_reduce = |a[2:0];
            default : shift_reduce = |a; // 执行默认分支。
        endcase // 结束多分支选择。
    endfunction // 结束函数定义。

    localparam PADDED_WIDTH = 2**SHIFT_WIDTH; // 声明局部常量。
    localparam NUM_TIERS = (SHIFT_WIDTH+1)/2; //log4 - each level reduces width by a factor of 4；声明局部常量。
    logic[PADDED_WIDTH-1:0] tier[NUM_TIERS]; // 声明信号、变量或生成变量。

    ////////////////////////////////////////////////////
    //Implementation
    int tier_width; // 声明信号、变量或生成变量。
    int curr_shift_amount; // 声明信号、变量或生成变量。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        tier = '{default: '0};
        //Pad with 0s to ensure that shift amounts larger than INPUT_WIDTH generate the correct sticky
        tier[0] = {{(PADDED_WIDTH-INPUT_WIDTH){1'b0}}, shifter_input};

        tier_width = PADDED_WIDTH/4;
        for (int i = 1; i < NUM_TIERS; i++) begin // 执行循环或遍历。
            curr_shift_amount = 32'(shift_amount) >> 2*i;
            for (int j = 0; j < tier_width; j++) // 执行循环或遍历。
                tier[i][j] = shift_reduce(tier[i-1][j*4 +: 4], shift_amount[(i-1)*2 +: 2], j < curr_shift_amount);
            tier_width = tier_width/4;
        end // 结束语句块。

        sticky_bit = shift_reduce(tier[NUM_TIERS-1][3:0], shift_amount[$clog2(PADDED_WIDTH)-1 -: 2], 1'b0);
    end // 结束语句块。
endmodule // 结束模块定义。
