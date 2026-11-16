// ============================================================================
// 文件：core/execution_units/fp_unit/fp_preprocessing.sv
// 类型：module
// 名称：fp_preprocessing
// 作用：拆包浮点操作数并检测类别、指数和尾数信息。
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

module fp_preprocessing // 定义 fp_preprocessing 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    #(
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG, // 声明可配置参数。
        parameter FP_NUM_UNITS = 5 // 声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        unit_issue_interface.decode unit_issue[FP_NUM_UNITS-1:0],

        //Unit Inputs
        input fp_preprocessing_packet_t pkt, // 声明输入端口。

        output logic ready, // 声明输出端口。
        output fp_madd_inputs_t madd_args, // 声明输出端口。
        output fp_div_inputs_t div_args, // 声明输出端口。
        output fp_sqrt_inputs_t sqrt_args, // 声明输出端口。
        output fp_wb2fp_misc_inputs_t wb2fp_args, // 声明输出端口。
        output fp_wb2int_misc_inputs_t wb2int_args // 声明输出端口。
    );

    /////////////////////////////////////////////
    //Control Logic
    //Cycle 0 has combinational speculative preprocessing that is registered on valid requests
    //Cycle 1 has some additional preprocessing and also issues the instruction
    id_t id_r;
    rm_t rm_r;
    logic single; // 声明信号、变量或生成变量。
    logic single_r; // 声明信号、变量或生成变量。
    logic[FP_NUM_UNITS-1:0] target_unit; // 声明信号、变量或生成变量。
    logic[FP_NUM_UNITS-1:0] issue_to; // 声明信号、变量或生成变量。
    logic[FP_NUM_UNITS-1:0] unit_ready; // 声明信号、变量或生成变量。
    logic accept_request; // 声明信号、变量或生成变量。
    logic stage2_valid; // 声明信号、变量或生成变量。
    logic stage2_advance; // 声明信号、变量或生成变量。

    //Unpack interface array
    generate for (genvar i = 0; i < FP_NUM_UNITS; i++) begin : gen_interface_unpack // 开始生成块，在编译期展开硬件结构。
        assign unit_ready[i] = unit_issue[i].ready; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign unit_issue[i].new_request = issue_to[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign unit_issue[i].id = id_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

    assign stage2_advance = stage2_valid & |(unit_ready & target_unit); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign issue_to = target_unit & {FP_NUM_UNITS{stage2_advance}}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ready = ~stage2_valid | stage2_advance; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign accept_request = ready & pkt.valid; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign single = pkt.is_single; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            target_unit <= '0;
            stage2_valid <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            if (accept_request) begin // 执行条件判断，满足条件时进入对应分支。
                target_unit <= pkt.unit;
                stage2_valid <= 1;
            end // 结束语句块。
            else if (stage2_advance) // 执行否则如果分支的条件判断。
                stage2_valid <= 0;
        end // 结束语句块。

        if (accept_request) begin // 执行条件判断，满足条件时进入对应分支。
            id_r <= pkt.id;
            rm_r <= pkt.rm;
            single_r <= single;
        end // 结束语句块。
    end // 结束语句块。

    /////////////////////////////////////////////
    //Cycle 0 preprocessing
    //Single to double, normalization, and special case detection
    //Also computes whether the arguments should be swapped
    fp_t rs1, rs1_r;
    fp_t rs2, rs2_r;
    fp_t rs3, rs3_r;
    special_case_t[2:0] special_case, special_case_r;
    logic[2:0] hidden, hidden_r; // 声明信号、变量或生成变量。
    logic[0:0] hidden_single; // 声明信号、变量或生成变量。
    logic[1:0] hidden_double; // 声明信号、变量或生成变量。
    fp_t[2:0] rs_converted;
    logic rs1_boxed, rs2_boxed; // 声明信号、变量或生成变量。
    fp_shift_amt_t rs1_norm_shift, rs1_norm_shift_r;
    fp_shift_amt_t rs2_norm_shift, rs2_norm_shift_r;
    frac_d_t rs1_norm_frac, rs1_norm_frac_r;
    frac_d_t rs2_norm_frac, rs2_norm_frac_r;

    assign rs1 = pkt.rs1; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs2 = pkt.rs2; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs3 = pkt.rs3; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Unit instantiation
    fp_rs_preprocess #(.CONFIG(CONFIG)) rs1_pre (
        .in(rs1),
        .single(single),
        .double(rs_converted[0]),
        .special(special_case[0]),
        .is_boxed(rs1_boxed),
        .hidden(hidden[0]),
        .hidden_double(hidden_double[0]),
        .hidden_single(hidden_single[0]),
        .prenormalize_shift(rs1_norm_shift),
        .prenormalize_frac(rs1_norm_frac)
    );

    fp_rs_preprocess #(.CONFIG(CONFIG)) rs2_pre (
        .in(rs2),
        .single(single),
        .double(rs_converted[1]),
        .special(special_case[1]),
        .is_boxed(rs2_boxed),
        .hidden(hidden[1]),
        .hidden_double(hidden_double[1]),
        .hidden_single(),
        .prenormalize_shift(rs2_norm_shift),
        .prenormalize_frac(rs2_norm_frac)
    );

    fp_rs_preprocess #(.CONFIG(CONFIG)) rs3_pre (
        .in(rs3),
        .single(single),
        .double(rs_converted[2]),
        .special(special_case[2]),
        .is_boxed(),
        .hidden(hidden[2]),
        .hidden_double(),
        .hidden_single(),
        .prenormalize_shift(),
        .prenormalize_frac()
    );
    
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (accept_request) begin // 执行条件判断，满足条件时进入对应分支。
            rs1_r <= single ? rs_converted[0] : rs1;
            rs2_r <= single ? rs_converted[1] : rs2;
            rs3_r <= single ? rs_converted[2] : rs3;
            special_case_r <= special_case;
            hidden_r <= hidden;
            rs1_norm_shift_r <= rs1_norm_shift;
            rs2_norm_shift_r <= rs2_norm_shift;
            rs1_norm_frac_r <= rs1_norm_frac;
            rs2_norm_frac_r <= rs2_norm_frac;
        end // 结束语句块。
    end // 结束语句块。


    //Swap calculation
    logic[EXPO_WIDTH:0] expo_diff; // 声明信号、变量或生成变量。
    logic swap, swap_r; // 声明信号、变量或生成变量。
    logic rs1_smaller_mantissa; // 声明信号、变量或生成变量。
    expo_d_t rs1_expo_padded;
    expo_d_t rs2_expo_padded;
    logic[FRAC_WIDTH_F-1:0] rs1_mant; // 声明信号、变量或生成变量。
    logic[FRAC_WIDTH_F-1:0] rs2_mant; // 声明信号、变量或生成变量。

    assign swap = expo_diff[EXPO_WIDTH] ? 1 : |expo_diff[EXPO_WIDTH-1:0] ? 0 : rs1_smaller_mantissa; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign rs1_expo_padded[EXPO_WIDTH-1:EXPO_WIDTH_F] = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs2_expo_padded[EXPO_WIDTH-1:EXPO_WIDTH_F] = '0; // 执行连续赋值，把组合逻辑连接到目标信号。

    //The exponent comparison checks boxing because the minmax instruction assumes NaNs are the larger operand
    assign rs1_expo_padded[EXPO_WIDTH_F-1:0] = rs1_boxed ? rs1.s.expo : '1; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs2_expo_padded[EXPO_WIDTH_F-1:0] = rs2_boxed ? rs2.s.expo : '1; // 执行连续赋值，把组合逻辑连接到目标信号。
    //For the mantissa, all that is required is inf < snan/qnan
    assign rs1_mant = {~rs1_boxed | rs1.s.frac[FRAC_WIDTH_F-1], rs1.s.frac[FRAC_WIDTH_F-2:0]}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs2_mant = {~rs2_boxed | rs2.s.frac[FRAC_WIDTH_F-1], rs2.s.frac[FRAC_WIDTH_F-2:0]}; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (single) begin // 执行条件判断，满足条件时进入对应分支。
            rs1_smaller_mantissa = rs1_mant < rs2_mant;
            expo_diff = rs1_expo_padded - rs2_expo_padded;
        end // 结束语句块。
        else begin // 执行否则分支。
            rs1_smaller_mantissa = rs1.d.frac < rs2.d.frac;
            expo_diff = rs1.d.expo - rs2.d.expo;
        end // 结束语句块。
    end // 结束语句块。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (accept_request) // 执行条件判断，满足条件时进入对应分支。
            swap_r <= swap;
    end // 结束语句块。

    /////////////////////////////////////////////
    //Cycle 1 swap
    //After the swap RS1 will hold the larger argument
    fp_t rs1_norm;
    fp_t rs2_norm;
    fp_t rs1_swapped;
    fp_t rs2_swapped;
    fp_shift_amt_t rs2_swapped_shift;
    logic rs1_swapped_hidden; // 声明信号、变量或生成变量。
    logic rs2_swapped_hidden; // 声明信号、变量或生成变量。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        rs1_norm.d.sign = rs1_r.d.sign;
        rs1_norm.d.expo = rs1_r.d.expo;
        rs1_norm.d.frac = rs1_norm_frac_r;
        rs2_norm.d.sign = rs2_r.d.sign;
        rs2_norm.d.expo = rs2_r.d.expo;
        rs2_norm.d.frac = rs2_norm_frac_r;

        //Do not need to swap special case, because multiplication is the only unit that needs it and the order doesn't matter there
        if (swap_r) begin // 执行条件判断，满足条件时进入对应分支。
            {rs1_swapped, rs2_swapped} = {rs2_norm, rs1_norm};
            {rs1_swapped_hidden, rs2_swapped_hidden} = {hidden_r[1], hidden_r[0]};
            rs2_swapped_shift = rs1_norm_shift_r;
        end else begin // 结束语句块。
            {rs1_swapped, rs2_swapped} = {rs1_norm, rs2_norm};
            {rs1_swapped_hidden, rs2_swapped_hidden} = {hidden_r[0], hidden_r[1]};
            rs2_swapped_shift = rs2_norm_shift_r;
        end // 结束语句块。
    end // 结束语句块。


    /////////////////////////////////////////////
    //FMA Unit
    //Issue cycle FMA
    logic is_fma_r; // 声明信号、变量或生成变量。
    logic is_fadd_r; // 声明信号、变量或生成变量。
    logic add_r; // 声明信号、变量或生成变量。
    logic neg_mul_r; // 声明信号、变量或生成变量。

    //FMA
    assign madd_args.fma = is_fma_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.fma_args.mul_sign = neg_mul_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.fma_args.add_sign = add_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.fma_args.rs3 = rs3_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.fma_args.rs3_hidden = hidden_r[2]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.fma_args.rs3_special_case = special_case_r[2]; // 执行连续赋值，把组合逻辑连接到目标信号。

    //FMUL
    assign madd_args.mul_args.rs1_special_case = special_case_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.mul_args.rs2_special_case = special_case_r[1]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.mul_args.rs1_hidden = rs1_swapped_hidden; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.mul_args.rs2_hidden = rs2_swapped_hidden; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.mul_args.rs1 = rs1_swapped; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.mul_args.rs2 = rs2_swapped; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.mul_args.rm = rm_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.mul_args.single = single_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.mul_args.rs2_prenormalize_shift_amt = rs2_swapped_shift; // 执行连续赋值，把组合逻辑连接到目标信号。

    //FADD
    logic[EXPO_WIDTH:0] expo_diff_issued; // 声明信号、变量或生成变量。
    logic[EXPO_WIDTH:0] double_expo_diff; // 声明信号、变量或生成变量。
    logic[EXPO_WIDTH:0] double_expo_diff_r; // 声明信号、变量或生成变量。

    //Precalculate the double exponent difference, saves time in the next cycle (because the hidden bits don't need to be included)
    assign double_expo_diff = (rs1.d.expo + {{(EXPO_WIDTH-1){1'b0}}, ~hidden_double[0]}) - (rs2.d.expo + {{(EXPO_WIDTH-1){1'b0}}, ~hidden_double[1]}); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (single_r) // 执行条件判断，满足条件时进入对应分支。
            expo_diff_issued = rs1_r.d.expo - rs2_r.d.expo;
        else // 执行否则分支。
            expo_diff_issued = double_expo_diff_r;
        if (swap_r) // 执行条件判断，满足条件时进入对应分支。
            expo_diff_issued = -expo_diff_issued;
    end // 结束语句块。

    assign madd_args.add = is_fadd_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.rs1 = rs1_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.rs2 = rs2_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.rs1_hidden = hidden_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.rs2_hidden = hidden_r[1]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.rs1_safe = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.rs2_safe = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.rs1_special_case = special_case_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.rs2_special_case = special_case_r[1]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.rs1_expo_overflow = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.expo_diff = expo_diff_issued; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.add = add_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.swap = swap_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.fp_add_grs = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.rm = rm_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign madd_args.add_args.single = single_r; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (accept_request) begin // 执行条件判断，满足条件时进入对应分支。
            is_fma_r <= pkt.is_fma;
            is_fadd_r <= pkt.is_fadd;
            add_r <= pkt.add;
            neg_mul_r <= pkt.neg_mul;
            double_expo_diff_r <= double_expo_diff;
        end // 结束语句块。
    end // 结束语句块。

    /////////////////////////////////////////////
    //FDIV
    assign div_args.rs1 = rs1_norm; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_args.rs2 = rs2_norm; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_args.rm = rm_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_args.rs1_hidden = hidden_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_args.rs2_hidden = hidden_r[1]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_args.rs1_prenormalize_shift_amt = rs1_norm_shift_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_args.rs2_prenormalize_shift_amt = rs2_norm_shift_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_args.single = single_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_args.rs1_special_case = special_case_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_args.rs2_special_case = special_case_r[1]; // 执行连续赋值，把组合逻辑连接到目标信号。

    /////////////////////////////////////////////
    //FSQRT
    assign sqrt_args.rs1 = rs1_norm; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sqrt_args.rs1_hidden = hidden_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sqrt_args.special_case = special_case_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sqrt_args.rs1_prenormalize_shift_amt = rs1_norm_shift_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sqrt_args.rm = rm_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sqrt_args.single = single_r; // 执行连续赋值，把组合逻辑连接到目标信号。

    /////////////////////////////////////////////
    //WB2FP
    //Issue cycle F2I
    logic rs1_boxed_r; // 声明信号、变量或生成变量。
    logic rs2_boxed_r; // 声明信号、变量或生成变量。
    logic[31:0] int_rs_abs; // 声明信号、变量或生成变量。
    logic[31:0] int_rs_abs_r; // 声明信号、变量或生成变量。
    logic[31:0] int_rs1_r; // 声明信号、变量或生成变量。
    logic i2f_sign; // 声明信号、变量或生成变量。
    logic i2f_sign_r; // 声明信号、变量或生成变量。
    logic is_i2f_r; // 声明信号、变量或生成变量。
    logic is_minmax_r; // 声明信号、变量或生成变量。
    logic is_sign_inj_r; // 声明信号、变量或生成变量。
    logic is_sign_inj_single_r; // 声明信号、变量或生成变量。
    logic is_mv_i2f_r; // 声明信号、变量或生成变量。
    logic is_d2s_r; // 声明信号、变量或生成变量。
    
    assign i2f_sign = pkt.conv_signed & pkt.int_rs1[31]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign int_rs_abs = i2f_sign ? -pkt.int_rs1 : pkt.int_rs1; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Cycle 1 - WB2FP
    assign wb2fp_args.i2f = is_i2f_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.fminmax = is_minmax_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.fsgnj = is_sign_inj_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.fmv = is_mv_i2f_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.d2s = is_d2s_r; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign wb2fp_args.int_rs = int_rs1_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.rs1 = rs1_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.rs1_hidden = hidden_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.rs1_special_case = special_case_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.fsgnj_single = is_sign_inj_single_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.rs1_boxed = rs1_boxed_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.rs2_boxed = rs2_boxed_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.swap = swap_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.rs2 = rs2_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.single = single_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.rm = rm_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.rs2_special_case = special_case_r[1]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.int_rs_abs = int_rs_abs_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2fp_args.i2f_sign = i2f_sign_r; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (accept_request) begin // 执行条件判断，满足条件时进入对应分支。
            rs1_boxed_r <= rs1_boxed;
            rs2_boxed_r <= rs2_boxed;
            int_rs1_r <= pkt.int_rs1;
            int_rs_abs_r <= int_rs_abs;
            i2f_sign_r <= i2f_sign;
            is_i2f_r <= pkt.is_i2f;
            is_minmax_r <= pkt.is_minmax;
            is_sign_inj_r <= pkt.is_sign_inj;
            is_sign_inj_single_r <= pkt.is_sign_inj_single;
            is_mv_i2f_r <= pkt.is_mv_i2f;
            is_d2s_r <= pkt.is_d2s;
        end // 结束语句块。
    end // 结束语句块。

    /////////////////////////////////////////////
    //WB2INT
    //Issue cycle F2I
    logic f2i_is_signed_r; // 声明信号、变量或生成变量。
    logic is_class_r; // 声明信号、变量或生成变量。
    logic is_fcmp_r; // 声明信号、变量或生成变量。
    logic is_f2i_r; // 声明信号、变量或生成变量。
    logic rs1_hidden_single_r; // 声明信号、变量或生成变量。
    expo_d_t rs1_expo_unbiased;
    expo_d_t rs1_expo_unbiased_r;
    logic int_less_than_1; // 声明信号、变量或生成变量。
    logic int_less_than_1_r; // 声明信号、变量或生成变量。

    //Cycle 0 F2I preprocessing
    expo_d_t expo_amt;
    expo_d_t bias_amt;
    assign expo_amt = single ? {{(EXPO_WIDTH-EXPO_WIDTH_F){1'b0}}, rs1.s.expo} : rs1.d.expo; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign bias_amt = single ? BIAS_F : BIAS; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign {int_less_than_1, rs1_expo_unbiased} = expo_amt - bias_amt; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Cycle 1 - WB2INT
    assign wb2int_args.fclass = is_class_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.fcmp = is_fcmp_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.f2i = is_f2i_r; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign wb2int_args.int_less_than_1 = int_less_than_1_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.rs1_expo_unbiased = rs1_expo_unbiased_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.rs1 = rs1_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.rs1_original_hidden_bit = single_r ? rs1_hidden_single_r : hidden_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.rs1_special_case = special_case_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.rs2_special_case = special_case_r[1]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.rs2 = rs2_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.swap = swap_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.rm = rm_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.rs1_hidden = hidden_r[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb2int_args.is_signed = f2i_is_signed_r; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (accept_request) begin // 执行条件判断，满足条件时进入对应分支。
            f2i_is_signed_r <= pkt.conv_signed;
            is_class_r <= pkt.is_class;
            is_fcmp_r <= pkt.is_fcmp;
            is_f2i_r <= pkt.is_f2i;
            rs1_hidden_single_r <= hidden_single[0];
            int_less_than_1_r <= int_less_than_1;
            rs1_expo_unbiased_r <= rs1_expo_unbiased;
        end // 结束语句块。
    end // 结束语句块。

endmodule // 结束模块定义。
