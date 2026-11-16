// ============================================================================
// 文件：core/execution_units/fp_unit/fp_wb2int_misc.sv
// 类型：module
// 名称：fp_wb2int_misc
// 作用：处理浮点结果转整数写回和杂项。
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

module fp_wb2int_misc // 定义 fp_wb2int_misc 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        input fp_wb2int_misc_inputs_t args, // 声明输入端口。
        unit_issue_interface.unit issue,
        unit_writeback_interface.unit wb,
        output fflags_t fflags // 声明输出端口。
    );

    ////////////////////////////////////////////////////
    //Implementation
    //Comparisons, classifications, conversions to integer, and moves sharing a single writeback port
    //Implemented as a 2 cycle pipeline (though only the conversion needs the second cycle)
    logic advance; // 声明信号、变量或生成变量。
    assign advance = wb.ack | ~wb.done; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign issue.ready = advance; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            wb.done <= 0;
        else begin // 执行否则分支。
            if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
                wb.done <= 1;
            else if (wb.ack) // 执行否则如果分支的条件判断。
                wb.done <= 0;
        end // 结束语句块。
        
        if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
            wb.id <= issue.id;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //FMV
    //Transfers bits unchanged from an FP register to an INT register
    //This instruction is meant to transfer single precision numbers, so in reduced precision only the single precision bits are used
    logic[31:0] fmv_rd; // 声明信号、变量或生成变量。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        fmv_rd = '0;
        fmv_rd[FLEN_F-1:0] = args.rs1.raw[FLEN_F-1:0];
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //FCLASS
    //Outputs a number indicating the type of the operand
    //Encoded one hot
    logic[31:0] fclass_rd; // 声明信号、变量或生成变量。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        fclass_rd = '0;
        fclass_rd[0] = args.rs1.d.sign & args.rs1_special_case.inf;
        fclass_rd[1] = args.rs1.d.sign & args.rs1_original_hidden_bit & ~|args.rs1_special_case;
        fclass_rd[2] = args.rs1.d.sign & ~args.rs1_original_hidden_bit & ~args.rs1_special_case.zero;
        fclass_rd[3] = args.rs1.d.sign & args.rs1_special_case.zero;
        fclass_rd[4] = ~args.rs1.d.sign & args.rs1_special_case.zero;
        fclass_rd[5] = ~args.rs1.d.sign & ~args.rs1_original_hidden_bit & ~args.rs1_special_case.zero;
        fclass_rd[6] = ~args.rs1.d.sign & args.rs1_original_hidden_bit & ~|args.rs1_special_case;
        fclass_rd[7] = ~args.rs1.d.sign & args.rs1_special_case.inf;
        fclass_rd[8] = args.rs1_special_case.snan;
        fclass_rd[9] = args.rs1_special_case.qnan;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //FCMP
    //Implements equal, less than, and less than or equal
    //For these instructions, +-0 are identical and flags can be raised for NaN operands
    logic[31:0] fcmp_rd; // 声明信号、变量或生成变量。
    logic invalid_cmp; // 声明信号、变量或生成变量。
    logic unordered; // 声明信号、变量或生成变量。
    logic sign_eq; // 声明信号、变量或生成变量。
    logic expo_eq; // 声明信号、变量或生成变量。
    logic frac_eq; // 声明信号、变量或生成变量。
    logic feq; // 声明信号、变量或生成变量。
    logic flt; // 声明信号、变量或生成变量。
    logic fle; // 声明信号、变量或生成变量。

    //FLT/FLE are signalling (raise on NaN)
    assign invalid_cmp = (~args.rm[1] & (args.rs1_special_case.qnan | args.rs2_special_case.qnan)) | args.rs1_special_case.snan | args.rs2_special_case.snan; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign unordered = args.rs1_special_case.qnan | args.rs1_special_case.snan | args.rs2_special_case.qnan | args.rs2_special_case.snan; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign sign_eq = args.rs1.d.sign == args.rs2.d.sign; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign expo_eq = args.rs1.d.expo == args.rs2.d.expo; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign frac_eq = args.rs1.d.frac == args.rs2.d.frac; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign feq = (args.rs1_special_case.zero & args.rs2_special_case.zero) | (sign_eq & expo_eq & frac_eq); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign flt = sign_eq ? (args.swap ^ args.rs1.d.sign) & ~(sign_eq & expo_eq & frac_eq) : args.rs1.d.sign & ~(args.rs1_special_case.zero & args.rs2_special_case.zero); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fle = flt | feq; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        fcmp_rd = '0;
        if (args.rm[1]) // 执行条件判断，满足条件时进入对应分支。
            fcmp_rd[0] = feq & ~unordered;
        else if (args.rm[0]) // 执行否则如果分支的条件判断。
            fcmp_rd[0] = flt & ~unordered;
        else // 执行否则分支。
            fcmp_rd[0] = fle & ~unordered;
    end // 结束语句块。


    //Choose between the three single cycle operations
    logic[31:0] single_rd; // 声明信号、变量或生成变量。
    logic single_valid; // 声明信号、变量或生成变量。
    logic single_invalid; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) begin // 执行条件判断，满足条件时进入对应分支。
            single_valid <= ~args.f2i;
            single_invalid <= args.fcmp & invalid_cmp;
            if (args.fcmp) // 执行条件判断，满足条件时进入对应分支。
                single_rd <= fcmp_rd;
            else if (args.fclass) // 执行否则如果分支的条件判断。
                single_rd <= fclass_rd;
            else // 执行否则分支。
                single_rd <= fmv_rd;
        end // 结束语句块。
    end // 结束语句块。


    ////////////////////////////////////////////////////
    //F2I
    //First cycle detects edge cases and shifts args
    //Second cycle rounds
    logic[2:0] grs; // 声明信号、变量或生成变量。
    logic[FRAC_WIDTH:0] rs1_frac; // 声明信号、变量或生成变量。
    logic[FRAC_WIDTH:0] f2i_frac; // 声明信号、变量或生成变量。
    logic[31:0] f2i_int; // 声明信号、变量或生成变量。
    logic[32+FRAC_WIDTH-1:0] shift_in; // 声明信号、变量或生成变量。
    logic[32+FRAC_WIDTH-1:0] f2i_int_dot_frac; // 声明信号、变量或生成变量。
    logic rs1_expo_unbiased_greater_than_31; // 声明信号、变量或生成变量。
    logic rs1_expo_unbiased_greater_than_30; // 声明信号、变量或生成变量。
    logic subtract; // 声明信号、变量或生成变量。
    logic roundup; // 声明信号、变量或生成变量。
    
    //Cycle 1 - calculate roundup and detect special and edge cases
    assign rs1_expo_unbiased_greater_than_31 = args.rs1.d.expo > (BIAS+31); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs1_expo_unbiased_greater_than_30 = args.rs1.d.expo > (BIAS+30); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs1_frac = {args.rs1_hidden, args.rs1.d.frac}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign shift_in = {{31{1'b0}}, rs1_frac}; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Left shift according to exponent
    assign f2i_int_dot_frac = shift_in << args.rs1_expo_unbiased; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (args.int_less_than_1) begin // 执行条件判断，满足条件时进入对应分支。
            f2i_int = '0;
            f2i_frac = rs1_frac;
        end else // 结束语句块。
            {f2i_int, f2i_frac} = {f2i_int_dot_frac, 1'b0};
    end // 结束语句块。

    //Calculate rounding bits and -roundup or +roundup
    logic sticky; // 声明信号、变量或生成变量。
    assign sticky = |f2i_frac[FRAC_WIDTH-2:0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (args.int_less_than_1) begin // 执行条件判断，满足条件时进入对应分支。
            if (args.rs1.d.expo == expo_d_t'(BIAS-1)) // 执行条件判断，满足条件时进入对应分支。
                grs = {f2i_frac[FRAC_WIDTH-:2], sticky};
            else if (args.rs1.d.expo == expo_d_t'(BIAS-2)) // 执行否则如果分支的条件判断。
                grs = {1'b0, f2i_frac[FRAC_WIDTH], f2i_frac[FRAC_WIDTH-1] | sticky};
            else // 执行否则分支。
                grs = {2'b0, (|f2i_frac[FRAC_WIDTH-:2] | sticky)};
        end else // 结束语句块。
            grs = {f2i_frac[FRAC_WIDTH-:2], sticky};
    end // 结束语句块。

    fp_roundup f2i_int_roundup (
        .sign(args.rs1.d.sign),
        .rm(args.rm),
        .grs(grs),
        .lsb(f2i_int[0]),
        .roundup(roundup),
        .result_if_overflow()
    );

    assign subtract = args.rs1.d.sign & args.is_signed; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Special case handling - this is sometimes the critical path in the FPU
    //This special case detection can be done in the second cycle, which may make that a new critical path
    //However, calculating the roundup takes approximately the same amount of time as these special cases
    logic inexact; // 声明信号、变量或生成变量。
    logic all_frac; // 声明信号、变量或生成变量。
    logic greater_than_largest_unsigned_int; // 声明信号、变量或生成变量。
    logic smaller_than_smallest_unsigned_int; // 声明信号、变量或生成变量。
    logic greater_than_largest_signed_int; // 声明信号、变量或生成变量。
    logic smaller_than_smallest_signed_int; // 声明信号、变量或生成变量。
    logic special; // 声明信号、变量或生成变量。
    assign inexact = |grs; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign all_frac = &f2i_int[30:0]; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign greater_than_largest_unsigned_int = ~args.is_signed & (~args.rs1.d.sign | args.rs1_special_case.snan | args.rs1_special_case.qnan) & ((f2i_int[31] & all_frac & roundup) | rs1_expo_unbiased_greater_than_31); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign smaller_than_smallest_unsigned_int = ~args.is_signed & args.rs1.d.sign & ~args.rs1_special_case.zero & ~(args.int_less_than_1 & ~roundup); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign greater_than_largest_signed_int = args.is_signed & ((args.rs1_special_case.snan | args.rs1_special_case.qnan | ~args.rs1.d.sign) & ((~f2i_int[31] & all_frac & roundup) | rs1_expo_unbiased_greater_than_30)); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign smaller_than_smallest_signed_int = args.is_signed & args.rs1.d.sign & ((f2i_int[31] & (|f2i_int[30:0] | roundup)) | rs1_expo_unbiased_greater_than_31); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign special = (~args.is_signed & (greater_than_largest_unsigned_int | smaller_than_smallest_unsigned_int)) | (args.is_signed & (greater_than_largest_signed_int | smaller_than_smallest_signed_int)); // 执行连续赋值，把组合逻辑连接到目标信号。


    //Cycle 2 - do the rounding and override special cases
    //Input negative -> -roundup - f2i_int
    //Input positive ->  roundup + f2i_int
    logic r_greater_than_largest_unsigned_int; // 声明信号、变量或生成变量。
    logic r_greater_than_largest_signed_int; // 声明信号、变量或生成变量。
    logic r_smaller_than_smallest_signed_int; // 声明信号、变量或生成变量。
    logic r_inexact; // 声明信号、变量或生成变量。
    logic r_special; // 声明信号、变量或生成变量。
    logic r_subtract; // 声明信号、变量或生成变量。
    logic r_roundup; // 声明信号、变量或生成变量。
    logic[31:0] r_f2i_int; // 声明信号、变量或生成变量。
    logic[31:0] in1; // 声明信号、变量或生成变量。
    logic[31:0] in2; // 声明信号、变量或生成变量。
    logic[31:0] f2i_int_rounded; // 声明信号、变量或生成变量。
    logic[31:0] special_case_result; // 声明信号、变量或生成变量。
    logic carry_in; // 声明信号、变量或生成变量。
    assign in1 = r_subtract ? -(32'(r_roundup)) : 32'(r_roundup); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign in2 = r_f2i_int ^ {32{r_subtract}}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign {f2i_int_rounded, carry_in} = {in1, 1'b1} + {in2, r_subtract}; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (r_greater_than_largest_unsigned_int) // 执行条件判断，满足条件时进入对应分支。
            special_case_result = 32'hffffffff; //2^32 - 1;
        else if (r_greater_than_largest_signed_int) // 执行否则如果分支的条件判断。
            special_case_result = 32'h7fffffff; //2^31 - 1;
        else if (r_smaller_than_smallest_signed_int) // 执行否则如果分支的条件判断。
            special_case_result = 32'h80000000; //-2^31;
        else // 执行否则分支。
            special_case_result = 0;
    end // 结束语句块。

    //F2I pipeline
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) begin // 执行条件判断，满足条件时进入对应分支。
            r_greater_than_largest_unsigned_int <= greater_than_largest_unsigned_int;
            r_greater_than_largest_signed_int <= greater_than_largest_signed_int;
            r_smaller_than_smallest_signed_int <= smaller_than_smallest_signed_int;
            r_inexact <= inexact;
            r_special <= special;
            r_f2i_int <= f2i_int;
            r_subtract <= subtract;
            r_roundup <= roundup;
        end // 结束语句块。
    end // 结束语句块。

    //Multiplex the outputs from f2i and the single cycle units
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        fflags = '0;
        if (single_valid) begin // 执行条件判断，满足条件时进入对应分支。
            wb.rd = single_rd;
            fflags.nv = single_invalid;
        end // 结束语句块。
        else begin // 执行否则分支。
            wb.rd = r_special ? special_case_result : f2i_int_rounded;
            fflags.nv = r_special;
            fflags.nx = r_inexact & ~r_special;
        end // 结束语句块。
    end // 结束语句块。

endmodule // 结束模块定义。
