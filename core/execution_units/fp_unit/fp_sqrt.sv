// ============================================================================
// 文件：core/execution_units/fp_unit/fp_sqrt.sv
// 类型：module
// 名称：fp_sqrt
// 作用：实现浮点平方根顶层。
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
 *             Chris Keilbart <ckeilbar@sfu.ca>
 */

module fp_sqrt // 定义 fp_sqrt 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        input fp_sqrt_inputs_t args, // 声明输入端口。
        unit_issue_interface.unit issue,
        fp_intermediate_wb_interface.unit wb
    );

    //Hidden + GRS + 1 (because without the +1 it gave the wrong sticky bit in certain cases)
    unsigned_sqrt_interface #(.DATA_WIDTH(FRAC_WIDTH+5)) sqrt();

    ////////////////////////////////////////////////////
    //Implementation
    //Iterative square root core, bypassed on special cases
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
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Special cases
    //Handle edge cases like negative numbers, infinity, NaN, zero, and powers of 2
    //Don't require mantissa calculation and bypass the core
    logic nv, nv_r; // 声明信号、变量或生成变量。
    logic inf; //Default if not qnan_r or zero_r；声明信号、变量或生成变量。
    logic qnan, qnan_r; // 声明信号、变量或生成变量。
    logic zero, zero_r; // 声明信号、变量或生成变量。
    logic early_exit; // 声明信号、变量或生成变量。
    logic result_sign; // 声明信号、变量或生成变量。
    fp_t special_result;
    expo_d_t result_expo;

    assign nv = (args.rs1.d.sign & ~args.special_case.qnan & ~args.special_case.zero) | args.special_case.snan; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign qnan = args.special_case.qnan | nv; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign zero = args.special_case.zero; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign inf = args.special_case.inf & ~args.rs1.d.sign; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            early_exit <= 0;
        else if (wb.ack) // 执行否则如果分支的条件判断。
            early_exit <= 0;
        else if (issue.new_request) // 执行否则如果分支的条件判断。
            early_exit <= inf | zero | qnan;
        
        if (issue.new_request) begin // 执行条件判断，满足条件时进入对应分支。
            result_sign <= args.rs1.d.sign;
            nv_r <= nv;
            qnan_r <= qnan;
            zero_r <= zero;
        end // 结束语句块。
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (qnan_r) // 执行条件判断，满足条件时进入对应分支。
            special_result.raw = CANONICAL_NAN;
        else if (zero_r) begin // 执行否则如果分支的条件判断。
            special_result.d.sign = result_sign;
            special_result.d.expo = '0;
            special_result.d.frac = '0;
        end // 结束语句块。
        else begin //Inf；执行否则分支。
            special_result.d.sign = 0;
            special_result.d.expo = '1;
            special_result.d.frac = '0;
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Exponent logic
    //Normalized for subnormal inputs
    //Halved for positive exponents and doubled for negative exponents
    logic[EXPO_WIDTH:0] norm_expo; // 声明信号、变量或生成变量。
    logic[EXPO_WIDTH:0] norm_expo_r; // 声明信号、变量或生成变量。
    logic[EXPO_WIDTH:0] unbiased_expo; // 声明信号、变量或生成变量。
    assign norm_expo = args.rs1.d.expo + {{(EXPO_WIDTH-1){1'b0}}, ~args.rs1_hidden} - args.rs1_prenormalize_shift_amt; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign unbiased_expo = norm_expo_r - {{(EXPO_WIDTH-1){1'b0}}, ~norm_expo_r[0]} - BIAS; // 执行连续赋值，把组合逻辑连接到目标信号。
    //Right shift by 1 halves both positive and negative numbers
    assign result_expo = unbiased_expo[EXPO_WIDTH:1] + BIAS; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
            norm_expo_r <= norm_expo;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Mantissa square root core
    //Designed to be swappable
    //Operates on normalized values shifted for alignment
    logic result_hidden; // 声明信号、变量或生成变量。
    logic[3:0] result_grs; // 声明信号、变量或生成变量。
    frac_d_t result_frac;
    assign sqrt.radicand = norm_expo[0] ? {2'b01, args.rs1.d.frac, 3'b0} : {1'b1, args.rs1.d.frac, 4'b0}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sqrt.start = issue.new_request & ~(inf | zero | qnan); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign {result_hidden, result_frac, result_grs} = sqrt.result; // 执行连续赋值，把组合逻辑连接到目标信号。

    fp_sqrt_core sqrt_core (
        .sqrt(sqrt),
    .*);

    ////////////////////////////////////////////////////
    //Output management
    //Either return the early execute values on cycle 1, or the regular values once the square root finishes
    logic sqrt_hold; // 声明信号、变量或生成变量。
    assign wb.done = sqrt.done | sqrt_hold | early_exit; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            sqrt_hold <= 0;
        else // 执行否则分支。
            sqrt_hold <= ~wb.ack & (sqrt.done | sqrt_hold);
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
            wb.rd.d.sign = 0;
            wb.rd.d.expo = result_expo;
            wb.rd.d.frac = result_frac;
        end // 结束语句块。
        wb.grs = '0;
        if (~new_request_r) begin // 执行条件判断，满足条件时进入对应分支。
            wb.grs[GRS_WIDTH-1-:4] = result_grs;
            wb.grs[GRS_WIDTH-5-:FRAC_WIDTH+5] = sqrt.remainder;
        end // 结束语句块。
    end // 结束语句块。
    assign wb.expo_overflow = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.nv = nv_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.dz = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.of = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.uf = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.fflags.nx = 0; //Set in writeback；执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.carry = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.safe = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.subnormal = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.hidden = (new_request_r & ~zero_r) | (~new_request_r & result_hidden); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.clz = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.right_shift = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.right_shift_amt = 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.ignore_max_expo = 1; // 执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
