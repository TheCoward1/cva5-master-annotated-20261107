// ============================================================================
// 文件：core/execution_units/fp_unit/fp_wb2fp_misc.sv
// 类型：module
// 名称：fp_wb2fp_misc
// 作用：处理浮点结果写回和浮点相关杂项。
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

module fp_wb2fp_misc // 定义 fp_wb2fp_misc 模块。

    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。
    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。

    (
        input fp_wb2fp_misc_inputs_t args, // 声明输入端口。
        unit_issue_interface.unit issue,
        fp_intermediate_wb_interface.unit wb
    );

    ////////////////////////////////////////////////////
    //Implementation
    //Sign injections, min/max, s2d, d2s, i2f, and moves
    //Single cycle, sharing a writeback port
    assign issue.ready = wb.ack; //ACK functions as READY here；执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.id = issue.id; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.done = issue.new_request; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.rm = args.rm; //Only used for i2f；执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //FMV
    //Transfers bits unchanged from an INT register to an FP register, boxing them
    //In reduced precision, transfers the lower bits
    fp_t fmv_rd;
    assign fmv_rd.s.box = '1; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign {fmv_rd.s.sign, fmv_rd.s.expo, fmv_rd.s.frac} = args.int_rs[FLEN_F-1:0]; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //FS2D
    //The actual conversion is done in preprocessing
    //Can only raise on SNAN
    fp_t s2d_rd;
    assign s2d_rd = args.rs1; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //FD2S
    //The actual conversion is done in postprocessing
    //Canonicalizes NaNs and can also raise on SNAN
    fp_t d2s_rd;
    assign d2s_rd.raw = args.rs1_special_case.snan | args.rs1_special_case.qnan ? CANONICAL_NAN : args.rs1.raw; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //FSGN
    //Modifies the sign of the first operand
    //Does NOT canonicalize NaNs and does not raise any flags
    logic sgn_sign; // 声明信号、变量或生成变量。
    logic rs1_sign; // 声明信号、变量或生成变量。
    logic rs2_sign; // 声明信号、变量或生成变量。
    fp_t sgn_rd;

    assign rs1_sign = args.fsgnj_single ? args.rs1_boxed & args.rs1.s.sign : args.rs1.d.sign; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs2_sign = args.fsgnj_single ? args.rs2_boxed & args.rs2.s.sign : args.rs2.d.sign; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (args.rm[1]) //JX；执行条件判断，满足条件时进入对应分支。
            sgn_sign = rs1_sign ^ rs2_sign;
        else if (args.rm[0]) //JN；执行否则如果分支的条件判断。
            sgn_sign = ~rs2_sign;
        else //J；执行否则分支。
            sgn_sign = rs2_sign;

        if (args.fsgnj_single) begin // 执行条件判断，满足条件时进入对应分支。
            sgn_rd.s.box = '1;
            sgn_rd.s.sign = sgn_sign;
            //If rs1 is unboxed it is treated as the canonical NaN
            if (args.rs1_boxed) // 执行条件判断，满足条件时进入对应分支。
                sgn_rd.raw[FLEN_F-2:0] = args.rs1.raw[FLEN_F-2:0];
            else // 执行否则分支。
                sgn_rd.raw[FLEN_F-2:0] = {{EXPO_WIDTH_F{1'b1}}, 1'b1, {FRAC_WIDTH_F-1{1'b0}}};
        end // 结束语句块。
        else begin // 执行否则分支。
            sgn_rd.d.sign = sgn_sign;
            sgn_rd.d.expo = args.rs1.d.expo;
            sgn_rd.d.frac = args.rs1.d.frac;
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //FMIN/FMAX
    //Returns the larger/smaller argument
    //Canonicalizes NaNs and can raise invalid
    fp_t fminmax_rd;
    logic fminmax_hidden; // 声明信号、变量或生成变量。
    logic rs1_nan; // 声明信号、变量或生成变量。
    logic rs2_nan; // 声明信号、变量或生成变量。

    assign rs1_nan = args.rs1_special_case.qnan | args.rs1_special_case.snan; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs2_nan = args.rs2_special_case.qnan | args.rs2_special_case.snan; // 执行连续赋值，把组合逻辑连接到目标信号。

    //args.rm[0] = MAX, args.swap means rs2 > rs1
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case({rs1_nan, rs2_nan, args.rs1.d.sign, args.rs2.d.sign, args.rm[0], args.swap}) inside // 开始多分支选择，根据表达式选择对应分支。
            6'b11????: begin
                fminmax_rd = CANONICAL_NAN;
                fminmax_hidden = 1;
            end // 结束语句块。
            6'b01????,
            6'b00100?,
            6'b00011?,
            6'b000010,
            6'b000001,
            6'b001111,
            6'b001100: begin
                fminmax_rd = args.rs1;
                fminmax_hidden = ~args.rs1_special_case.zero;
            end // 结束语句块。
            default: begin // 执行默认分支。
                fminmax_rd = args.rs2;
                fminmax_hidden = ~args.rs2_special_case.zero;
            end // 结束语句块。
        endcase // 结束多分支选择。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //I2F
    //Converts an integer to a FP number
    //The actual shifting is done in postprocessing
    fp_t i2f_rd;
    grs_t i2f_grs;
    logic[4:0] int_clz; // 声明信号、变量或生成变量。
    fp_shift_amt_t i2f_clz;
    logic int_rs1_zero; // 声明信号、变量或生成变量。

    clz #(.WIDTH(32)) clz_inst (
        .clz_input(args.int_rs_abs),
        .clz(int_clz),
        .zero(int_rs1_zero)
    );

    assign i2f_rd.d.sign = args.i2f_sign; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (int_rs1_zero) begin // 执行条件判断，满足条件时进入对应分支。
            i2f_clz = '0;
            i2f_rd.d.expo = '0;
        end // 结束语句块。
        else begin // 执行否则分支。
            i2f_clz = '0;
            i2f_clz[5:0] = int_clz + 1;
            i2f_rd.d.expo = BIAS+32;
        end // 结束语句块。
    end // 结束语句块。

    //When the mantissa shrinks sufficiently, the integer can no longer fit in the mantissa so it spills into the grs bits
    generate if (FRAC_WIDTH >= 32) begin : gen_int_fits // 开始生成块，在编译期展开硬件结构。
        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            i2f_grs = '0;
            i2f_rd.d.frac = '0;
            i2f_rd.d.frac[FRAC_WIDTH-1-:32] = args.int_rs_abs;
        end // 结束语句块。
    end else begin : gen_int_in_grs // 结束语句块。
        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            i2f_rd.d.frac[FRAC_WIDTH-1:0] = args.int_rs_abs[31-:FRAC_WIDTH];
            i2f_grs = '0;
            i2f_grs[GRS_WIDTH-1-:32-FRAC_WIDTH] = args.int_rs_abs[31-FRAC_WIDTH:0];
        end // 结束语句块。
    end endgenerate // 结束语句块。


    //Multiplex outputs of different units
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        wb.expo_overflow = 0;
        wb.fflags = '0;
        wb.carry = 0;
        wb.safe = 0;
        wb.hidden = 0;
        wb.grs = '0;
        wb.clz = '0;
        wb.right_shift = 0;
        wb.right_shift_amt = 'x;
        wb.subnormal = 0;
        wb.ignore_max_expo = 1;
        wb.d2s = 0;

        if (args.fmv) // 执行条件判断，满足条件时进入对应分支。
            wb.rd = fmv_rd;
        else if (args.d2s) begin // 执行否则如果分支的条件判断。
            wb.rd = d2s_rd;
            wb.hidden = args.rs1_hidden;
            wb.d2s = 1;
            wb.fflags.nv = args.rs1_special_case.snan;
        end // 结束语句块。
        else if (args.fsgnj) begin // 执行否则如果分支的条件判断。
            wb.hidden = 1;
            wb.rd = sgn_rd;
        end // 结束语句块。
        else if (args.fminmax) begin // 执行否则如果分支的条件判断。
            wb.rd = fminmax_rd;
            wb.hidden = fminmax_hidden;
            wb.fflags.nv = args.rs1_special_case.snan | args.rs2_special_case.snan;
            wb.d2s = args.single;
        end // 结束语句块。
        else if (args.i2f) begin // 执行否则如果分支的条件判断。
            wb.rd = i2f_rd;
            wb.grs = i2f_grs;
            wb.clz = i2f_clz;
            wb.d2s = args.single;
        end // 结束语句块。
        else begin // 执行否则分支。
            wb.rd = s2d_rd;
            wb.hidden = args.rs1_hidden;
            wb.fflags.nv = args.rs1_special_case.snan;
        end // 结束语句块。
    end // 结束语句块。

endmodule // 结束模块定义。
