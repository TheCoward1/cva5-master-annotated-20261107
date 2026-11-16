// ============================================================================
// 文件：core/execution_units/fp_unit/fp_rs_preprocess.sv
// 类型：module
// 名称：fp_rs_preprocess
// 作用：处理舍入前移位、粘滞位和尾数准备。
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

module fp_rs_preprocess // 定义 fp_rs_preprocess 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    #(
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG // 声明可配置参数。
    )
    (
        input fp_t in, //Packed form；声明输入端口。
        input logic single, // 声明输入端口。
        output fp_t double, //Only valid if input was single；声明输出端口。

        //Special cases
        output special_case_t special, // 声明输出端口。
        output logic is_boxed, // 声明输出端口。
        output logic hidden, // 声明输出端口。
        output logic hidden_double, // 声明输出端口。
        output logic hidden_single, // 声明输出端口。

        //Pre normalization
        output fp_shift_amt_t prenormalize_shift, // 声明输出端口。
        output frac_d_t prenormalize_frac // 声明输出端口。
    );

    ////////////////////////////////////////////////////
    //Special case detection
    //Depends on the type of the input
    //Single precision must check NaN boxing
    logic inf_d, inf_s; // 声明信号、变量或生成变量。
    logic snan_d, snan_s; // 声明信号、变量或生成变量。
    logic qnan_d, qnan_s; // 声明信号、变量或生成变量。
    logic zero_d, zero_s; // 声明信号、变量或生成变量。

    assign is_boxed = &in.s.box; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign special.inf = single ? inf_s & is_boxed : inf_d; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign special.snan = single ? snan_s & is_boxed : snan_d; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign special.qnan = single ? qnan_s | ~is_boxed : qnan_d; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign special.zero = single ? zero_s & is_boxed : zero_d; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign hidden = single ? ~zero_s : hidden_double; //TODO: singles sharing subnormal range with doubles；执行连续赋值，把组合逻辑连接到目标信号。

    fp_special_case_detection #(.FRAC_W(FRAC_WIDTH_F), .EXPO_W(EXPO_WIDTH_F), .SUBNORMAL(1)) input_case_s (
        .expo(in.s.expo),
        .frac(in.s.frac),
        .is_inf(inf_s),
        .is_SNaN(snan_s),
        .is_QNaN(qnan_s),
        .is_zero(zero_s),
        .hidden(hidden_single)
    );
    fp_special_case_detection #(.FRAC_W(FRAC_WIDTH), .EXPO_W(EXPO_WIDTH), .SUBNORMAL(1)) input_case_d (
        .expo(in.d.expo),
        .frac(in.d.frac),
        .is_inf(inf_d),
        .is_SNaN(snan_d),
        .is_QNaN(qnan_d),
        .is_zero(zero_d),
        .hidden(hidden_double)
    );

    ////////////////////////////////////////////////////
    //Normalization
    //Done by shifting to set the implicit leading 1 (required by many execution units for subnormal numbers)
    //Does CLZ + shift in one cycle
    logic[EXPO_WIDTH_F-1:0] exponent_add; // 声明信号、变量或生成变量。
    logic[FRAC_WIDTH-1:0] shift_arr; // 声明信号、变量或生成变量。
    logic clz_hidden; // 声明信号、变量或生成变量。
    logic[FRAC_WIDTH+1:0] clz_arr; // 声明信号、变量或生成变量。
    logic[$clog2(FRAC_WIDTH+2)-1:0] clz_count; // 声明信号、变量或生成变量。

    //Set up the array for shifting
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (single) begin // 执行条件判断，满足条件时进入对应分支。
            clz_hidden = hidden_single;
            shift_arr = '0;
            shift_arr[FRAC_WIDTH-1 -: FRAC_WIDTH_F] = in.s.frac;
        end // 结束语句块。
        else begin // 执行否则分支。
            clz_hidden = hidden_double;
            shift_arr = in.d.frac;
        end // 结束语句块。
    end // 结束语句块。

    //Check leading zero to get shift count
    assign clz_arr = {clz_hidden, shift_arr, 1'b1}; //Pad to ensure the count is always accurate；执行连续赋值，把组合逻辑连接到目标信号。
    clz #(.WIDTH(FRAC_WIDTH+2)) frac_clz (
        .clz_input(clz_arr),
        .clz(clz_count),
        .zero()
    );
    
    //Do the normalization shift
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        prenormalize_frac = shift_arr << clz_count;
        prenormalize_shift = '0;
        if (~single) // 执行条件判断，满足条件时进入对应分支。
            prenormalize_shift[$clog2(FRAC_WIDTH)-1:0] = clz_count[$clog2(FRAC_WIDTH)-1:0];
        exponent_add = '0;
        exponent_add[$clog2(FRAC_WIDTH+2)-1:0] = clz_count;
    end // 结束语句块。


    ////////////////////////////////////////////////////
    //Single to Double
    //Scales exponent considering different ranges and shifting amounts
    //Uses normalized mantissa
    expo_d_t add_amt;
    expo_d_t bias_amt;
    expo_d_t expo_out;

    //Input case -> Output
    //Not NaN boxed -> CNaN
    //sNaN -> CNaN
    //qNaN -> CNaN
    //+-0 -> +-0
    //+-infty -> +-infty
    //subnormal -> not subnormal (this depends on relative widths)
    //regular -> regular

    //Sign
    assign double.d.sign = snan_s | qnan_s | ~is_boxed ? 1'b0 : in.s.sign; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Exponent
    assign add_amt = hidden_single ? {{(EXPO_WIDTH-EXPO_WIDTH_F){1'b0}}, in.s.expo} : -{{(EXPO_WIDTH-EXPO_WIDTH_F){1'b0}}, exponent_add}; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        bias_amt = BIAS - BIAS_F;
        if (~hidden_single) // 执行条件判断，满足条件时进入对应分支。
            bias_amt[0] = 1;
    end // 结束语句块。
    assign expo_out = bias_amt + add_amt; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (inf_s | snan_s | qnan_s | ~is_boxed) // 执行条件判断，满足条件时进入对应分支。
            double.d.expo = '1;
        else if (zero_s) // 执行否则如果分支的条件判断。
            double.d.expo = '0;
        else // 执行否则分支。
            double.d.expo = expo_out;
    end // 结束语句块。

    //Mantissa
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (snan_s | qnan_s | ~is_boxed) //NaNs get canonicalized from s->d；执行条件判断，满足条件时进入对应分支。
            double.d.frac = {1'b1, {(FRAC_WIDTH-1){1'b0}}};
        else // 执行否则分支。
            double.d.frac = prenormalize_frac;
    end // 结束语句块。

endmodule // 结束模块定义。
