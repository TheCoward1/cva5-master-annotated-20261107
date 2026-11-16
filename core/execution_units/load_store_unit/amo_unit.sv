// ============================================================================
// 文件：core/execution_units/load_store_unit/amo_unit.sv
// 类型：module
// 名称：amo_unit
// 作用：处理 LR/SC 和 AMO 原子内存操作、保留集和响应。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2024 Chris Keilbart, Lesley Shannon
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

module amo_unit // 定义 amo_unit 模块。

    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。

    #(
        parameter int NUM_UNITS = 3, // 声明可配置参数。
        parameter int RESERVATION_WORDS = 4 // 声明可配置参数。
    ) //TODO: reservation shape and size must be discoverable(?)
    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        amo_interface.amo_unit agents[NUM_UNITS]
    );

    localparam RESERVATION_WIDTH = 30 - $clog2(RESERVATION_WORDS); // 声明局部常量。
// 定义类型别名或枚举/结构类型。
    typedef logic[RESERVATION_WIDTH-1:0] reservation_t;

    ////////////////////////////////////////////////////
    //Interface unpacking
    logic[NUM_UNITS-1:0] set_reservation; // 声明信号、变量或生成变量。
    logic[NUM_UNITS-1:0] clear_reservation; // 声明信号、变量或生成变量。
    reservation_t[NUM_UNITS-1:0] reservation;
    reservation_t lr_addr;
    logic lr_valid; // 声明信号、变量或生成变量。

    logic[NUM_UNITS-1:0] rmw_valid; // 声明信号、变量或生成变量。
    amo_t[NUM_UNITS-1:0] op;
    logic[NUM_UNITS-1:0][31:0] rs1; // 声明信号、变量或生成变量。
    logic[NUM_UNITS-1:0][31:0] rs2; // 声明信号、变量或生成变量。
    logic[31:0] rd; // 声明信号、变量或生成变量。

    generate for (genvar i = 0; i < NUM_UNITS; i++) begin : gen_unpacking // 开始生成块，在编译期展开硬件结构。
        assign set_reservation[i] = agents[i].set_reservation; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign clear_reservation[i] = agents[i].clear_reservation; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign reservation[i] = agents[i].reservation[31-:RESERVATION_WIDTH]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign agents[i].reservation_valid = lr_valid & lr_addr == reservation[i]; // 执行连续赋值，把组合逻辑连接到目标信号。

        assign rmw_valid[i] = agents[i].rmw_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign op[i] = agents[i].op; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign rs1[i] = agents[i].rs1; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign rs2[i] = agents[i].rs2; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign agents[i].rd = rd; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

    ////////////////////////////////////////////////////
    //Multiplexing
    //Shared LR-SC and RMW port across all units
    reservation_t set_val;
    amo_t selected_op;
    logic[31:0] selected_rs1; // 声明信号、变量或生成变量。
    logic[31:0] selected_rs2; // 声明信号、变量或生成变量。
    logic[$clog2(NUM_UNITS > 1 ? NUM_UNITS : 2)-1:0] reservation_int; // 声明信号、变量或生成变量。
    logic[$clog2(NUM_UNITS > 1 ? NUM_UNITS : 2)-1:0] rmw_int; // 声明信号、变量或生成变量。
    
    one_hot_to_integer #(.C_WIDTH(NUM_UNITS)) reservation_conv (
        .one_hot(set_reservation),
        .int_out(reservation_int)
    );
    assign set_val = reservation[reservation_int]; // 执行连续赋值，把组合逻辑连接到目标信号。

    one_hot_to_integer #(.C_WIDTH(NUM_UNITS)) rmw_conv (
        .one_hot(rmw_valid),
        .int_out(rmw_int)
    );
    assign selected_op = op[rmw_int]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign selected_rs1 = rs1[rmw_int]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign selected_rs2 = rs2[rmw_int]; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //RISC-V LR-SC
    //One address is reserved at a time for all units
    //The reservation can be set or cleared at any time by any unit, but set has priority over clear on same cycle
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            lr_valid <= 0;
        else // 执行否则分支。
            lr_valid <= (lr_valid & ~|clear_reservation) | |set_reservation;
        if (|set_reservation) // 执行条件判断，满足条件时进入对应分支。
            lr_addr <= set_val;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //RISC-V Atomic ALU
    //Combinational; results valid in same cycle
    amo_alu #(.WIDTH(32)) alu_inst (
        .amo_type(selected_op),
        .rs1(selected_rs1),
        .rs2(selected_rs2),
        .rd(rd)
    );

endmodule // 结束模块定义。
