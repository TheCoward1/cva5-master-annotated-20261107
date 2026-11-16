// ============================================================================
// 文件：core/execution_units/fp_unit/fp_sqrt_core.sv
// 类型：module
// 名称：fp_sqrt_core
// 作用：实现浮点平方根的核心迭代算法。
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

module fp_sqrt_core // 定义 fp_sqrt_core 模块。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        unsigned_sqrt_interface.sqrt sqrt
    );

// 定义类型别名或枚举/结构类型。
    typedef logic[$clog2(sqrt.DATA_WIDTH)-1:0] counter_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[sqrt.DATA_WIDTH-1:0] frac_t;

    ////////////////////////////////////////////////////
    //Radix 2 square root
    //Fixed latency generating one result bit per cycle

    //Control logic
    logic counter_full; // 声明信号、变量或生成变量。
    counter_t counter;
    assign counter_full = counter == counter_t'(sqrt.DATA_WIDTH); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            counter <= '0;
            sqrt.done <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            sqrt.done <= counter_full;
            if (counter_full) // 执行条件判断，满足条件时进入对应分支。
                counter <= '0;
            else if (sqrt.start | |counter) // 执行否则如果分支的条件判断。
                counter <= counter + 1;
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Subtraction
    frac_t rad;
    frac_t current_subtractend;
    frac_t next_subtractend;
    frac_t subtractor;
    frac_t subtraction;
    logic overflow; // 声明信号、变量或生成变量。

    assign subtractor = {sqrt.result[sqrt.DATA_WIDTH-3:0], 2'b01}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign {overflow, subtraction} = current_subtractend - subtractor; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Next Working subtractend Determination
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (overflow) // 执行条件判断，满足条件时进入对应分支。
            next_subtractend = {current_subtractend[sqrt.DATA_WIDTH-3:0], rad[sqrt.DATA_WIDTH-1-:2]};
        else // 执行否则分支。
            next_subtractend = {subtraction[sqrt.DATA_WIDTH-3:0], rad[sqrt.DATA_WIDTH-1-:2]};
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (sqrt.start) //First working subtractend extracts the upper 2 bits of the radicand；执行条件判断，满足条件时进入对应分支。
            current_subtractend <= {{(sqrt.DATA_WIDTH-2){1'b0}}, sqrt.radicand[sqrt.DATA_WIDTH-1-:2]};
        else // 执行否则分支。
            current_subtractend <= next_subtractend;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Update remaining radicand digits
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (sqrt.start) //The upper two bits are pushed to the working subtractend register；执行条件判断，满足条件时进入对应分支。
            rad <= {sqrt.radicand[sqrt.DATA_WIDTH-3:0], 2'b00};
        else // 执行否则分支。
            rad <= rad << 2;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Quotient Determination
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (sqrt.start) begin // 执行条件判断，满足条件时进入对应分支。
            sqrt.result <= '0;
            sqrt.remainder <= '0;
        end // 结束语句块。
        else if (|counter) begin // 执行否则如果分支的条件判断。
            //Shift in new quotient bit
            sqrt.result <= {sqrt.result[sqrt.DATA_WIDTH-2:0], ~overflow};
            sqrt.remainder <= next_subtractend;
        end // 结束语句块。
    end // 结束语句块。

endmodule // 结束模块定义。
