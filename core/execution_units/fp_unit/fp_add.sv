// ============================================================================
// 文件：core/execution_units/fp_unit/fp_add.sv
// 类型：module
// 名称：fp_add
// 作用：实现浮点加法和减法，并处理规格化、舍入和特殊值。
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

module fp_add // 定义 fp_add 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        input fp_add_inputs_t args, // 声明输入端口。
        unit_issue_interface.unit issue,
        fp_intermediate_wb_interface.unit wb
    );

    logic advance_to_add; // 声明信号、变量或生成变量。
    logic advance_to_final; // 声明信号、变量或生成变量。

    /////////////////////////////////////////////
    //Cycle 1
    //Swap and align arguments
    //Also detect special cases
    logic temp_rs2_sign; // 声明信号、变量或生成变量。
    assign temp_rs2_sign = args.add ? args.rs2.d.sign : ~args.rs2.d.sign; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Special case handling
    logic nv[2:0]; // 声明信号、变量或生成变量。
    logic inf[2:0]; // 声明信号、变量或生成变量。
    logic qnan[1:0]; // 声明信号、变量或生成变量。
    logic subtract[2:0]; // 声明信号、变量或生成变量。
    logic zero_result_sign[2:0]; // 声明信号、变量或生成变量。
    logic inf_sign[2:0]; // 声明信号、变量或生成变量。

    //SNAN or "magnitude subtraction of infinities"
    assign nv[0] = args.rs1_special_case.snan | args.rs2_special_case.snan | (args.rs1_special_case.inf & args.rs2_special_case.inf & (args.rs1.d.sign ^ temp_rs2_sign)); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign qnan[0] = args.rs1_special_case.snan | args.rs1_special_case.qnan | args.rs2_special_case.snan | args.rs2_special_case.qnan | nv[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign inf[0] = (args.rs1_special_case.inf | args.rs2_special_case.inf) & ~qnan[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign inf_sign[0] = args.rs1_special_case.inf ? args.rs1.d.sign : temp_rs2_sign; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign subtract[0] = args.rs1.d.sign ^ temp_rs2_sign; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign zero_result_sign[0] = args.rm == 3'b010; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Swap arguments, moving input with larger expo to rs1
    logic rs1_sign[2:0]; // 声明信号、变量或生成变量。
    expo_d_t rs1_expo[2:0];
    logic rs1_expo_overflow[2:0]; // 声明信号、变量或生成变量。
    logic[FRAC_WIDTH+1:0] rs1_frac[1:0]; // 声明信号、变量或生成变量。
    logic[FRAC_WIDTH+1:0] rs2_frac[0:0]; // 声明信号、变量或生成变量。
    grs_t rs1_grs[1:0];
    grs_t temp_rs2_grs;
    
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (~args.swap) begin // 执行条件判断，满足条件时进入对应分支。
            rs1_sign[0] = args.rs1.d.sign;
            rs1_expo_overflow[0] = args.rs1_expo_overflow;
            rs1_expo[0] = args.rs1.d.expo;
            rs1_frac[0] = {args.rs1_safe, args.rs1_hidden, args.rs1.d.frac};
            rs1_grs[0] = args.fp_add_grs;

            rs2_frac[0] = {args.rs2_safe, args.rs2_hidden, args.rs2.d.frac};
            temp_rs2_grs = '0;
        end else begin // 结束语句块。
            rs1_sign[0] = temp_rs2_sign;
            rs1_expo_overflow[0] = 1'b0;
            rs1_expo[0] = args.rs2.d.expo;
            rs1_frac[0] = {args.rs2_safe, args.rs2_hidden, args.rs2.d.frac};
            rs1_grs[0] = '0;

            rs2_frac[0] = {args.rs1_safe, args.rs1_hidden, args.rs1.d.frac};
            temp_rs2_grs = args.fp_add_grs;
        end // 结束语句块。
    end // 结束语句块。

    //Alignment through shifting
    logic shift_sticky[1:0]; // 声明信号、变量或生成变量。
    logic[FRAC_WIDTH+1:0] rs2_frac_aligned[1:0]; // 声明信号、变量或生成变量。
    grs_t rs2_grs[1:0];
    logic[FRAC_WIDTH+GRS_WIDTH+1:0] shifter_input; // 声明信号、变量或生成变量。
    
    assign shifter_input = {rs2_frac[0], temp_rs2_grs}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign {rs2_frac_aligned[0], rs2_grs[0]} = shifter_input >> args.expo_diff; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    //If the shift amount is too large, bits might get shifted out so this checks for them
    fp_sticky_tracking #(.INPUT_WIDTH($bits(shifter_input)), .SHIFT_WIDTH(EXPO_WIDTH+1)) sticky_tracking (
        .shifter_input(shifter_input),
        .shift_amount(args.expo_diff),
        .sticky_bit(shift_sticky[0])
    );

    //Pipeline to next stage
    logic valid_r; // 声明信号、变量或生成变量。
    rm_t rm_r;
    id_t id_r;
    logic d2s_r; // 声明信号、变量或生成变量。
    
    assign advance_to_add = ~valid_r | advance_to_final; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            valid_r <= 0;
        else if (advance_to_add) // 执行否则如果分支的条件判断。
            valid_r <= issue.new_request;

        if (advance_to_add) begin // 执行条件判断，满足条件时进入对应分支。
            d2s_r <= args.single;
            id_r <= issue.id;
            rm_r <= args.rm;

            nv[1] <= nv[0];
            qnan[1] <= qnan[0];
            inf[1] <= inf[0];
            inf_sign[1] <= inf_sign[0];
            subtract[1] <= subtract[0];
            zero_result_sign[1] <= zero_result_sign[0];

            rs1_sign[1] <= rs1_sign[0];
            rs1_expo[1] <= rs1_expo[0];
            rs1_expo_overflow[1] <= rs1_expo_overflow[0];
            rs1_frac[1] <= rs1_frac[0];
            rs1_grs[1] <= rs1_grs[0];

            rs2_grs[1] <= rs2_grs[0];
            rs2_frac_aligned[1] <= rs2_frac_aligned[0];
            shift_sticky[1] <= shift_sticky[0];
        end // 结束语句块。
    end // 结束语句块。


    /////////////////////////////////////////////
    //Cycle 2
    //Perform the sign-magnitude mantissa addition
    //Coded as an adder followed by negation, but the tools will transform this into two parallel additions with a muxing of the result
    //Negation is only required for different sign addition that returns a negative result
    logic[FRAC_WIDTH+GRS_WIDTH+2:0] adder_in1; // 声明信号、变量或生成变量。
    logic[FRAC_WIDTH+GRS_WIDTH+2:0] adder_in2, adder_in2_1s; // 声明信号、变量或生成变量。
    logic carry_add; // 声明信号、变量或生成变量。
    grs_t grs_add;
    logic[FRAC_WIDTH+1:0] frac_add; // 声明信号、变量或生成变量。
    logic sticky_add; // 声明信号、变量或生成变量。
    logic[1+GRS_WIDTH+FRAC_WIDTH+2-1:0] sum; // 声明信号、变量或生成变量。
    logic[1+GRS_WIDTH+FRAC_WIDTH+2-1:0] sum_final; // 声明信号、变量或生成变量。

    assign adder_in2 = {rs2_frac_aligned[1], rs2_grs[1], shift_sticky[1]}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign adder_in2_1s = adder_in2 ^ {(FRAC_WIDTH+GRS_WIDTH+3){subtract[1]}}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign adder_in1 = {rs1_frac[1], rs1_grs[1], 1'b0}; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign {carry_add, sum} = adder_in1 + adder_in2_1s + {{(FRAC_WIDTH+GRS_WIDTH+2){1'b0}}, subtract[1]}; // 执行连续赋值，把组合逻辑连接到目标信号。
    //subtract & ~carry_add = 1 if subtract and adder_in1 > adder_in2_1s, 0 if adder_in1 < adder_in2_1s
    assign sum_final = ~carry_add & subtract[1] ? -sum : sum; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign {frac_add, grs_add, sticky_add} = sum_final; // 执行连续赋值，把组合逻辑连接到目标信号。


    //Pipeline to next stage
    logic[FRAC_WIDTH+1:0] result_frac; // 声明信号、变量或生成变量。
    grs_t result_grs;
    logic result_carry_out; // 声明信号、变量或生成变量。
    logic output_special; // 声明信号、变量或生成变量。
    logic result_expo_zero; // 声明信号、变量或生成变量。

    assign advance_to_final = wb.ack | ~wb.done; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            wb.done <= 0;
        else if (advance_to_final) // 执行否则如果分支的条件判断。
            wb.done <= valid_r;

        if (advance_to_final) begin // 执行条件判断，满足条件时进入对应分支。
            wb.d2s <= d2s_r;
            wb.id <= id_r;
            wb.rm <= rm_r;

            nv[2] <= nv[1];
            inf[2] <= inf[1];
            inf_sign[2] <= inf_sign[1];
            output_special <= inf[1] | qnan[1];
            subtract[2] <= subtract[1];
            zero_result_sign[2] <= zero_result_sign[1];

            rs1_sign[2] <= rs1_sign[1];
            rs1_expo[2] <= rs1_expo[1];
            result_expo_zero <= ~|rs1_expo[1];
            rs1_expo_overflow[2] <= rs1_expo_overflow[1];

            result_frac <= frac_add;
            result_carry_out <= carry_add;
            result_grs[GRS_WIDTH-1:1] <= grs_add[GRS_WIDTH-1:1];
            result_grs[0] <= grs_add[0] | sticky_add; //Don't lose the sticky
        end // 结束语句块。
    end // 结束语句块。


    /////////////////////////////////////////////
    //Cycle 3
    //Find CLZ and determine shift amount
    //Override on special case and drive outputs
    logic result_zero; // 声明信号、变量或生成变量。
    logic[$clog2(FRAC_WIDTH+1+GRS_WIDTH)-1:0] clz_count; // 声明信号、变量或生成变量。
    clz #(.WIDTH(FRAC_WIDTH+1+GRS_WIDTH)) shift_clz (
        .clz_input({result_frac[FRAC_WIDTH:0], result_grs}),
        .clz(clz_count),
        .zero(result_zero)
    );

    //Determine exponent and sign
    logic carry_set; // 声明信号、变量或生成变量。
    logic output_zero; // 声明信号、变量或生成变量。
    logic result_sign; // 声明信号、变量或生成变量。
    logic result_expo_overflow; // 声明信号、变量或生成变量。
    expo_d_t result_expo;
    fp_shift_amt_t clz_shift_amt;

    assign carry_set = ~subtract[2] & result_carry_out; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign output_zero = result_zero & ~result_frac[FRAC_WIDTH+1] & ~carry_set; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign result_sign = output_zero & subtract[2] ? zero_result_sign[2] : (~result_carry_out & subtract[2]) ^ rs1_sign[2]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign result_expo_overflow = ~output_zero & rs1_expo_overflow[2]; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        clz_shift_amt = '0;
        clz_shift_amt[$bits(clz_count)-1:0] = clz_count;

        if (output_zero) // 执行条件判断，满足条件时进入对应分支。
            result_expo = '0;
        else if (result_expo_zero & (result_frac[FRAC_WIDTH] | carry_set | result_frac[FRAC_WIDTH+1])) //Subnormal promotion；执行否则如果分支的条件判断。
            result_expo = 1; //Will be added to the right shift amount to get the correct exponent
        else if (clz_shift_amt >= rs1_expo[2] & ~result_expo_zero & ~result_frac[FRAC_WIDTH+1] & ~carry_set) //Subnormal demotion；执行否则如果分支的条件判断。
            result_expo = rs1_expo[2] - 1;
        else // 执行否则分支。
            result_expo = rs1_expo[2];
    end // 结束语句块。

    fp_t special_result;
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (inf[2]) begin // 执行条件判断，满足条件时进入对应分支。
            special_result.d.sign = inf_sign[2];
            special_result.d.expo = '1;
            special_result.d.frac = '0;
        end // 结束语句块。
        else //qnan；执行否则分支。
            special_result.raw = CANONICAL_NAN;
    end // 结束语句块。

    //Writeback
    assign issue.ready = advance_to_add; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.nv = nv[2]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.of = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.uf = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.dz = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.nx = 0; //Will be set by normalization；执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.carry = ~output_special & carry_set; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.safe = result_frac[FRAC_WIDTH+1] & ~output_special; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.hidden = result_frac[FRAC_WIDTH] | output_special; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.grs = output_special ? '0 : result_grs; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        wb.clz = '0;
        if (~output_zero & ~output_special) // 执行条件判断，满足条件时进入对应分支。
            wb.clz[$bits(clz_count)-1:0] = clz_count;
        
        if (output_special) // 执行条件判断，满足条件时进入对应分支。
            wb.rd = special_result;
        else begin // 执行否则分支。
            wb.rd.d.sign = result_sign;
            wb.rd.d.expo = result_expo;
            wb.rd.d.frac = result_frac[FRAC_WIDTH-1:0];
        end // 结束语句块。
    end // 结束语句块。
    assign wb.expo_overflow = result_expo_overflow & ~output_special; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.subnormal = ~|result_expo & ~output_special & ~wb.right_shift & ~result_expo_overflow; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.right_shift = ~output_special & (result_frac[FRAC_WIDTH+1] | carry_set); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.right_shift_amt = {{(EXPO_WIDTH-2){1'b0}}, carry_set, result_frac[FRAC_WIDTH+1] & ~carry_set}; //Either 1 or 2；执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.ignore_max_expo = output_special; // 执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
