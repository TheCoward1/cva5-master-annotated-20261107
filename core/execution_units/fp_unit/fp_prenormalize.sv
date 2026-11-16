// ============================================================================
// 文件：core/execution_units/fp_unit/fp_prenormalize.sv
// 类型：module
// 名称：fp_prenormalize
// 作用：对浮点操作数进行运算前规格化。
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

module fp_prenormalize // 定义 fp_prenormalize 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    (
        input logic single, // 声明输入端口。
        input logic right_shift_in, // 声明输入端口。
        input logic overflow_in, // 声明输入端口。
        input logic subnormal, // 声明输入端口。
        input expo_d_t expo_in, // 声明输入端口。
        input logic ignore_max_expo, // 声明输入端口。
        input fp_shift_amt_t left_shift_amt, // 声明输入端口。
        input fp_shift_amt_t right_shift_amt, // 声明输入端口。

        output logic right_shift_out, // 声明输出端口。
        output logic dp_overflow_out, // 声明输出端口。
        output logic sp_overflow_out, // 声明输出端口。
        output fp_shift_amt_t shift_amt_out, // 声明输出端口。
        output expo_d_t dp_expo_out, // 声明输出端口。
        output expo_s_t sp_expo_out // 声明输出端口。
    );

    logic[EXPO_WIDTH:0] starting_expo; // 声明信号、变量或生成变量。
    assign starting_expo = {overflow_in, expo_in}; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Double precision
    //Left shifts are capped at reducing the exponent to 0
    //Right shifts increment the exponent except when subnormal
    logic expo_less_than_left_shift_amt; // 声明信号、变量或生成变量。
    fp_shift_amt_t left_shift_amt_adjusted;
    logic[EXPO_WIDTH:0] expo_norm_left_shift_intermediate; // 声明信号、变量或生成变量。
    logic[EXPO_WIDTH:0] expo_norm_left_shift; // 声明信号、变量或生成变量。
    logic[EXPO_WIDTH:0] expo_norm_right_shift; // 声明信号、变量或生成变量。
    logic dp_overflow_intermediate; // 声明信号、变量或生成变量。

    //Left shift logic - cap the left shift amount to the exponent if it would turn negative
    assign {expo_less_than_left_shift_amt, expo_norm_left_shift_intermediate} = {starting_expo & {(EXPO_WIDTH+1){~subnormal}}} - (EXPO_WIDTH+1)'(left_shift_amt); //drive to zero if subnormal；执行连续赋值，把组合逻辑连接到目标信号。
    assign left_shift_amt_adjusted = expo_less_than_left_shift_amt ? expo_in : left_shift_amt; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign expo_norm_left_shift = expo_less_than_left_shift_amt ? '0 : expo_norm_left_shift_intermediate; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Right shift logic - exponent is zero if subnormal
    assign expo_norm_right_shift = subnormal ? '0 : starting_expo + (EXPO_WIDTH+1)'(right_shift_amt); // 执行连续赋值，把组合逻辑连接到目标信号。
    
    //Select the final double precision exponent and overflow value
    assign {dp_overflow_intermediate, dp_expo_out} = right_shift_in ? expo_norm_right_shift : expo_norm_left_shift; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dp_overflow_out = dp_overflow_intermediate | (~ignore_max_expo & &dp_expo_out); // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Single precision
    //Normal double numbers map onto the subnormal single range
    //This means left shifts may turn into right shifts
    logic[EXPO_WIDTH-1:0] single_shift_amt; // 声明信号、变量或生成变量。
    logic[EXPO_WIDTH-1:0] expo_sum; // 声明信号、变量或生成变量。
    logic shift_sign; // 声明信号、变量或生成变量。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        single_shift_amt = right_shift_in ? right_shift_amt : -left_shift_amt;
        expo_sum = expo_in + single_shift_amt;
        sp_overflow_out = overflow_in | (expo_sum > BIAS+BIAS_F & ~&expo_sum); //All 1 = NaN/infinity but not an overflow
        
        //Determine SP expo and shift amount due to subnormal numbers
        sp_expo_out = '0;
        if (expo_sum <= BIAS-BIAS_F && expo_sum > BIAS-BIAS_F-FRAC_WIDTH_F-3) // 执行条件判断，满足条件时进入对应分支。
            single_shift_amt += (BIAS-BIAS_F+1) - expo_sum;
        else if (expo_sum <= BIAS-BIAS_F-FRAC_WIDTH_F-3) //Cap shift amount to prevent losing the sticky bit entirely；执行否则如果分支的条件判断。
            single_shift_amt += FRAC_WIDTH_F+3;
        else //Maps onto regular range；执行否则分支。
            sp_expo_out = {expo_sum[EXPO_WIDTH-1], expo_sum[EXPO_WIDTH_F-2:0]};
        
        shift_sign = single_shift_amt[EXPO_WIDTH-1];
        if (shift_sign) // 执行条件判断，满足条件时进入对应分支。
            single_shift_amt = -single_shift_amt;
        
        if (single) begin // 执行条件判断，满足条件时进入对应分支。
            right_shift_out = ~shift_sign;
            shift_amt_out = single_shift_amt;
        end // 结束语句块。
        else begin // 执行否则分支。
            right_shift_out = right_shift_in;
            shift_amt_out = right_shift_in ? right_shift_amt : left_shift_amt_adjusted;
        end // 结束语句块。
    end // 结束语句块。

endmodule // 结束模块定义。
