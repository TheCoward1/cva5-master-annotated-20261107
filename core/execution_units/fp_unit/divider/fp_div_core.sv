// ============================================================================
// 文件：core/execution_units/fp_unit/divider/fp_div_core.sv
// 类型：module
// 名称：fp_div_core
// 作用：实现浮点除法核心的迭代计算。
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

module fp_div_core // 定义 fp_div_core 模块。

    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        unsigned_division_interface.divider div
    );

    localparam DIV_WIDTH = div.DATA_WIDTH; // 声明局部常量。
    localparam COUNTER_WIDTH = $clog2((1+DIV_WIDTH)/2+3); // 声明局部常量。
    localparam QUOTIENT_WIDTH = 2*((1+DIV_WIDTH)/2)+2; // 声明局部常量。
    localparam DECIMAL_WIDTH = DIV_WIDTH+1; // 声明局部常量。
    localparam RESIDUE_WIDTH = DIV_WIDTH+3; // 声明局部常量。

    ////////////////////////////////////////////////////
    //Radix 4 divider
    //Follows the design in "Digital Arithmetic" by Ercegovac and Lang
    //Uses the digit set {-2, -1, 0, 1, 2}
    logic[RESIDUE_WIDTH-1:0] four_wsum; //Shifted left twice；声明信号、变量或生成变量。
    logic[DECIMAL_WIDTH-1:0] wcarry; // 声明信号、变量或生成变量。
    logic[DECIMAL_WIDTH-2:0] divisor_r; // 声明信号、变量或生成变量。
    logic[DECIMAL_WIDTH-1:0] next_wsum; // 声明信号、变量或生成变量。
    logic[DECIMAL_WIDTH-1:0] next_wcarry; // 声明信号、变量或生成变量。

    q_t current_q;
    q_t next_q;
    q_t muxed_q;

    logic[QUOTIENT_WIDTH-1:0] quotient; // 声明信号、变量或生成变量。
    logic[QUOTIENT_WIDTH-1:0] quotient_m; // 声明信号、变量或生成变量。
    logic[QUOTIENT_WIDTH-1:0] next_quotient; // 声明信号、变量或生成变量。
    logic[QUOTIENT_WIDTH-1:0] next_quotient_m; // 声明信号、变量或生成变量。

    //Assertions
    logic decremented_invalid; // 声明信号、变量或生成变量。
    logic bad_quotient_digit; // 声明信号、变量或生成变量。
    logic not_in_table; // 声明信号、变量或生成变量。

    //Control logic
    logic [COUNTER_WIDTH-1:0] counter; // 声明信号、变量或生成变量。
    logic counter_full; // 声明信号、变量或生成变量。
    assign counter_full = counter == COUNTER_WIDTH'((1+DIV_WIDTH)/2+2); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            counter <= '0;
            div.done <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            div.done <= counter_full;
            if (counter_full) // 执行条件判断，满足条件时进入对应分支。
                counter <= '0;
            else if (div.start | |counter) // 执行否则如果分支的条件判断。
                counter <= counter + 1;
        end // 结束语句块。
    end // 结束语句块。

    //Iterate over the digits
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            divisor_r <= '0;
            four_wsum <= '0;
            wcarry <= '0;
            quotient <= '0;
            quotient_m <= '0;
            current_q <= ZERO;
        end // 结束语句块。
        else begin // 执行否则分支。
            if (div.start) begin // 执行条件判断，满足条件时进入对应分支。
                divisor_r <= div.divisor;
                four_wsum <= {3'b0, div.dividend}; //First iteration doesn't shift the inputs
                current_q <= ZERO;
                wcarry <= '0;
                quotient <= '0;
                quotient_m <= '0;
            end // 结束语句块。
            else if (|counter) begin // 执行否则如果分支的条件判断。
                current_q <= next_q;
                four_wsum <= {next_wsum, 2'b0};
                wcarry <= next_wcarry;
                quotient <= next_quotient;
                quotient_m <= next_quotient_m;
            end // 结束语句块。
        end // 结束语句块。
    end // 结束语句块。
    assign div.quotient = quotient[QUOTIENT_WIDTH-2 -: DIV_WIDTH]; //Shift only once instead of twice because inputs are in the range 0.1X but the output can be X.XX；执行连续赋值，把组合逻辑连接到目标信号。


    //Carry save adder operating on shifted input
    carry_save_shift #(.WIDTH(RESIDUE_WIDTH)) partial_sum (
        .four_wsum(four_wsum),
        .wcarry(wcarry),
        .divisor(divisor_r),
        .next_wsum(next_wsum),
        .next_wcarry(next_wcarry),
        .next_q(next_q),
        .not_in_table(not_in_table)
    );

    //Digit conversion
    on_the_fly #(.WIDTH(QUOTIENT_WIDTH)) quotient_conv (
        .current_Q(quotient),
        .current_QM(quotient_m),
        .q(muxed_q),
        .next_Q(next_quotient),
        .next_QM(next_quotient_m),
        .bad_quotient_digit(bad_quotient_digit)
    );

    ////////////////////////////////////////////////////
    //Sign/zero detection using an adder
    //The alternative is a tree of generate/propagate blocks (see page 265 of "Digital Arithmetic" by Ercegovac and Lang)
    //For a 55 bit width, both have very similar delays but the tree uses slightly more resources
    logic is_negative; // 声明信号、变量或生成变量。
    logic[DECIMAL_WIDTH-1:0] sz_sum; // 声明信号、变量或生成变量。
    assign sz_sum = four_wsum[RESIDUE_WIDTH-1:2] + wcarry; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign is_negative = sz_sum[DECIMAL_WIDTH-1]; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        div.remainder = sz_sum[DIV_WIDTH-1:0];

        muxed_q = current_q;
        decremented_invalid = 0;
        if (counter_full & is_negative) begin //Subtract 1；执行条件判断，满足条件时进入对应分支。
            unique case (current_q)
                POS_TWO: muxed_q = POS_ONE;
                POS_ONE: muxed_q = ZERO;
                ZERO: muxed_q = NEG_ONE;
                NEG_ONE: muxed_q = NEG_TWO;
                NEG_TWO: muxed_q = NEG_THREE;
                default: decremented_invalid = 1; //For assertions only；执行默认分支。
            endcase // 结束多分支选择。
        end // 结束语句块。
    end // 结束语句块。


    //Assertions
    decrement_bad_quotient_assertion:
        assert property (@(posedge clk) disable iff (rst) (!(decremented_invalid))) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("Invalid decrement of quotient digit"); // 执行否则分支。

    decoding_bad_digit_assertion:
        assert property (@(posedge clk) disable iff (rst) (!(|counter & bad_quotient_digit))) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("Bad quotient digit for decoding"); // 执行否则分支。

    missed_lut_assertion:
        assert property (@(posedge clk) disable iff (rst) (!(|counter & not_in_table))) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("Sum out of range of quotient lookup"); // 执行否则分支。

endmodule // 结束模块定义。
