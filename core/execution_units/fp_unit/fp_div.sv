// ============================================================================
// 文件：core/execution_units/fp_unit/fp_div.sv
// 类型：module
// 名称：fp_div
// 作用：实现浮点除法顶层，连接预处理、迭代和舍入模块。
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

module fp_div // 定义 fp_div 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        input fp_div_inputs_t args, // 声明输入端口。
        unit_issue_interface.unit issue,
        fp_intermediate_wb_interface.unit wb
    );

    unsigned_division_interface #(.DATA_WIDTH(FRAC_WIDTH+3)) div();

    ////////////////////////////////////////////////////
    //Implementation
    //Iterative divider core, bypassed on special cases
    logic result_sign; // 声明信号、变量或生成变量。
    logic busy; // 声明信号、变量或生成变量。
    logic new_request_r; // 声明信号、变量或生成变量。
    assign issue.ready = ~busy | wb.ack; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            busy <= 0;
            new_request_r <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            if (wb.ack) // 执行条件判断，满足条件时进入对应分支。
                busy <= 0;
            if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
                busy <= 1;
            new_request_r <= issue.new_request;
        end // 结束语句块。
        if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
            result_sign <= args.rs1.d.sign ^ args.rs2.d.sign;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Special cases
    //Edge cases like NaN, infinity, and zero don't require division so return immediately
    logic nv, nv_r; // 声明信号、变量或生成变量。
    logic dz, dz_r; // 声明信号、变量或生成变量。
    logic qnan, qnan_r; // 声明信号、变量或生成变量。
    logic inf; // 声明信号、变量或生成变量。
    logic zero, zero_r; // 声明信号、变量或生成变量。
    logic early_exit; // 声明信号、变量或生成变量。
    fp_t special_result;
    
    //Special case handling
    assign nv = (args.rs1_special_case.zero & args.rs2_special_case.zero) | (args.rs1_special_case.inf & args.rs2_special_case.inf) | args.rs1_special_case.snan | args.rs2_special_case.snan; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dz = ~|args.rs1_special_case & args.rs2_special_case.zero; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign qnan = nv | args.rs1_special_case.qnan | args.rs2_special_case.qnan; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign inf = ~qnan & (dz | args.rs1_special_case.inf); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign zero = ~qnan & (args.rs1_special_case.zero | args.rs2_special_case.inf); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            early_exit <= 0;
        else if (wb.ack) // 执行否则如果分支的条件判断。
            early_exit <= 0;
        else if (issue.new_request) // 执行否则如果分支的条件判断。
            early_exit <= qnan | inf | zero;
        
        if (issue.new_request) begin // 执行条件判断，满足条件时进入对应分支。
            nv_r <= nv;
            dz_r <= dz;
            qnan_r <= qnan;
            zero_r <= zero;
        end // 结束语句块。
    end // 结束语句块。
    
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (zero_r) begin // 执行条件判断，满足条件时进入对应分支。
            special_result.d.sign = result_sign;
            special_result.raw[FLEN-2:0] = '0;
        end // 结束语句块。
        else if (qnan_r) // 执行否则如果分支的条件判断。
            special_result.raw = CANONICAL_NAN;
        else begin // 执行否则分支。
            special_result.d.sign = result_sign;
            special_result.d.expo = '1;
            special_result.d.frac = '0;
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Mantissa division core
    //Designed to be swappable (though note that only a subset of the division interface ports are used)
    //Operates on normalized values and width is extended to compute guard/round/sticky
    logic result_hidden; // 声明信号、变量或生成变量。
    frac_d_t result_frac;
    logic[1:0] result_gr; // 声明信号、变量或生成变量。
    fp_shift_amt_t left_shift_amt;

    assign div.dividend = {1'b1, args.rs1.d.frac, 2'b0}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div.divisor = {1'b1, args.rs2.d.frac, 2'b0}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div.start = issue.new_request & ~(qnan | inf | zero); //start div only if no special cases；执行连续赋值，把组合逻辑连接到目标信号。
    assign {result_hidden, result_frac, result_gr} = div.quotient; // 执行连续赋值，把组合逻辑连接到目标信号。
    fp_div_core div_core (
        .div(div),
    .*);

    //Calculate CLZ: because 0.5 < result < 2, the shift amount is either 0 or 1
    assign left_shift_amt[EXPO_WIDTH-1:1] = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign left_shift_amt[0] = ~result_hidden; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Exponent handling
    //Subtract exponents
    //Special considerations for subnormal numbers
    logic right_shift; // 声明信号、变量或生成变量。
    fp_shift_amt_t right_shift_amt;
    logic[EXPO_WIDTH+1:0] expo_intermediate; // 声明信号、变量或生成变量。
    logic[EXPO_WIDTH+1:0] expo_intermediate_r; // 声明信号、变量或生成变量。
    
    assign expo_intermediate = // 执行连续赋值，把组合逻辑连接到目标信号。
        ({1'b0, args.rs1.d.expo} + {{EXPO_WIDTH{1'b0}}, ~args.rs1_hidden} - {1'b0, args.rs1_prenormalize_shift_amt}) -
        ({1'b0, args.rs2.d.expo} + {{EXPO_WIDTH{1'b0}}, ~args.rs2_hidden} - {1'b0, args.rs2_prenormalize_shift_amt})
        + BIAS;

    assign right_shift = expo_intermediate_r[EXPO_WIDTH+1] | (~|expo_intermediate_r[EXPO_WIDTH:1] & ((~result_hidden & expo_intermediate_r[0]) | ~expo_intermediate_r[0])); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign right_shift_amt = ~expo_intermediate_r[EXPO_WIDTH-1:0] + 2; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
            expo_intermediate_r <= expo_intermediate;
    end // 结束语句块。


    ////////////////////////////////////////////////////
    //Output management
    //Either return the early execute values on cycle 1, or the regular values once the divider finishes
    logic div_hold; // 声明信号、变量或生成变量。
    assign wb.done = div.done | div_hold | early_exit; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            div_hold <= 0;
        else // 执行否则分支。
            div_hold <= ~wb.ack & (div.done | div_hold);
    end // 结束语句块。
    
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) begin // 执行条件判断，满足条件时进入对应分支。
            wb.id <= issue.id;
            wb.rm <= args.rm;
            wb.d2s <= args.single;
        end // 结束语句块。
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (new_request_r) // 执行条件判断，满足条件时进入对应分支。
            wb.rd = special_result;
        else begin // 执行否则分支。
            wb.rd.d.sign = result_sign;
            wb.rd.d.expo = expo_intermediate_r[EXPO_WIDTH-1:0];
            wb.rd.d.frac = result_frac;
        end // 结束语句块。
    end // 结束语句块。
    //Note that this overflow detection also captures subnormal numbers but they are ignored when subnormal is set
    assign wb.expo_overflow = expo_intermediate_r[EXPO_WIDTH] & ~new_request_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.nv = nv_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.dz = dz_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    //Set in writeback
    assign wb.fflags.of = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.uf = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.nx = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.carry = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.safe = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.hidden = (new_request_r & ~zero_r) | (~new_request_r & result_hidden); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.grs = new_request_r ? '0 : {result_gr, div.remainder, {(GRS_WIDTH-FRAC_WIDTH-5){1'b0}}}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.clz = new_request_r ? '0 : left_shift_amt; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.subnormal = ~new_request_r & right_shift; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.right_shift = ~new_request_r & right_shift; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.right_shift_amt = right_shift_amt; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.ignore_max_expo = new_request_r; // 执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
