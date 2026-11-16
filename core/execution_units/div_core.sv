// ============================================================================
// 文件：core/execution_units/div_core.sv
// 类型：module
// 名称：div_core
// 作用：实现整数除法的迭代数据通路和商/余数计算。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2021 Eric Matthews,  Lesley Shannon
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
 *             Eric Matthews <ematthew@sfu.ca>
  *             
 */
module div_core // 定义 div_core 模块。
    #(
        parameter DIV_WIDTH = 32 // 声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        unsigned_division_interface.divider div
    );
    
    localparam CLZ_W = $clog2(DIV_WIDTH); // 声明局部常量。
    logic [CLZ_W-1:0] CLZ_delta; // 声明信号、变量或生成变量。
    
    logic divisor_greater_than_dividend; // 声明信号、变量或生成变量。

    logic [DIV_WIDTH-1:0] shifted_divisor; // 声明信号、变量或生成变量。

    logic [1:0] new_quotient_bits; // 声明信号、变量或生成变量。
    logic [DIV_WIDTH-1:0] sub_1x; // 声明信号、变量或生成变量。
    logic [DIV_WIDTH-1:0] sub_2x; // 声明信号、变量或生成变量。
    logic sub_1x_overflow; // 声明信号、变量或生成变量。
    logic sub_2x_overflow; // 声明信号、变量或生成变量。

    logic [CLZ_W-2:0] cycles_remaining; // 声明信号、变量或生成变量。
    logic [CLZ_W-2:0] cycles_remaining_next; // 声明信号、变量或生成变量。

    logic running; // 声明信号、变量或生成变量。
    logic terminate; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation
    //First cycle
    assign {divisor_greater_than_dividend, CLZ_delta} = div.divisor_CLZ - div.dividend_CLZ; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (running) // 执行条件判断，满足条件时进入对应分支。
            shifted_divisor <= {2'b0, shifted_divisor[DIV_WIDTH-1:2]};
        else // 执行否则分支。
            shifted_divisor <= div.divisor << {CLZ_delta[CLZ_W-1:1], 1'b0};//Rounding down when CLZ_delta is odd
    end // 结束语句块。

    //Subtractions
    logic sub2x_toss; // 声明信号、变量或生成变量。
    assign {sub_2x_overflow, sub2x_toss, sub_2x} = {1'b0, div.remainder} - {shifted_divisor, 1'b0}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign {sub_1x_overflow, sub_1x} = sub_2x_overflow ? {sub2x_toss, sub_2x} + {1'b0, shifted_divisor} : {sub2x_toss, sub_2x} - {1'b0, shifted_divisor}; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign new_quotient_bits[1] = ~sub_2x_overflow; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign new_quotient_bits[0] = ~sub_1x_overflow; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (div.start) // 执行条件判断，满足条件时进入对应分支。
            div.quotient <= '0;
        else if (running) // 执行否则如果分支的条件判断。
            div.quotient <= {div.quotient[(DIV_WIDTH-3):0], new_quotient_bits};
    end // 结束语句块。

    //Remainder mux, when quotient bits are zero value is held
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (div.start | (running & |new_quotient_bits)) begin  //enable: on div.start for init and so long as we are in the running state and the quotient pair is not zero；执行条件判断，满足条件时进入对应分支。
            case ({~running, sub_1x_overflow}) // 开始多分支选择，根据表达式选择对应分支。
                0 : div.remainder <= sub_1x;
                1 : div.remainder <= sub_2x;
                default : div.remainder <= div.dividend;//Overloading the quotient zero case to fit the initial loading of the dividend in；执行默认分支。
            endcase // 结束多分支选择。
        end // 结束语句块。
    end // 结束语句块。
    
    ////////////////////////////////////////////////////
    //Control Signals

    //can merge with CLZ subtraction and remove mux on divisor if inputs held constant
    assign {terminate, cycles_remaining_next} = cycles_remaining - 1; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        cycles_remaining <= running ? cycles_remaining_next : CLZ_delta[CLZ_W-1:1];
    end // 结束语句块。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            running <= 0;
        else // 执行否则分支。
            running <= (running & ~terminate) | (div.start & ~divisor_greater_than_dividend);
    end // 结束语句块。
    
    assign div.done = (running & terminate) | (div.start & divisor_greater_than_dividend); // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions

endmodule // 结束模块定义。
