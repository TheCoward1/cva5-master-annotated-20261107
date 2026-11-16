// ============================================================================
// 文件：core/memory_sub_units/local_mem_sub_unit.sv
// 类型：module
// 名称：local_mem_sub_unit
// 作用：提供本地存储器子单元接口，连接本地 RAM。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017 Eric Matthews, Chris Keilbart, Lesley Shannon
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
 *             Chris Keilbart <ckeilbar@sfu.ca>
 */

module local_mem_sub_unit // 定义 local_mem_sub_unit 模块。

    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        output logic write_outstanding, // 声明输出端口。
        input logic amo, // 声明输入端口。
        input amo_t amo_type, // 声明输入端口。
        amo_interface.subunit amo_unit,
        memory_sub_unit_interface.responder unit,
        local_memory_interface.master local_mem
    );

    //If amo is tied to 0 and amo_unit is disconnected the tools can optimize most of the logic away

    logic rmw; // 声明信号、变量或生成变量。
    logic[31:2] rmw_addr; // 声明信号、变量或生成变量。
    logic[31:0] rmw_rs2; // 声明信号、变量或生成变量。
    amo_t rmw_op;
    logic sc_valid; // 声明信号、变量或生成变量。
    logic sc_valid_r; // 声明信号、变量或生成变量。
    
    assign write_outstanding = 0; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign sc_valid = amo & amo_type == AMO_SC_FN5 & amo_unit.reservation_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.set_reservation = unit.new_request & amo & amo_type == AMO_LR_FN5; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.clear_reservation = unit.new_request; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.reservation = unit.addr; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign amo_unit.rmw_valid = rmw; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.op = rmw_op; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.rs1 = local_mem.data_out; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.rs2 = rmw_rs2; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (rmw) begin // 执行条件判断，满足条件时进入对应分支。
            unit.ready = 0;
            local_mem.addr = rmw_addr;
            local_mem.en = 1;
            local_mem.be = '1;
            local_mem.data_in = amo_unit.rd;
            unit.data_out = local_mem.data_out;
        end else begin // 结束语句块。
            unit.ready = 1;
            local_mem.addr = unit.addr[31:2];
            local_mem.en = unit.new_request;
            local_mem.be = {4{unit.we | sc_valid}} & unit.be; //SC only writes when it succeeds
            local_mem.data_in = unit.data_in;
            unit.data_out = sc_valid_r ? 32'b1 : local_mem.data_out;
        end // 结束语句块。
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            unit.data_valid <= 0;
            rmw <= 0;
            sc_valid_r <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            unit.data_valid <= unit.new_request & unit.re;
            rmw <= unit.new_request & amo & ~(amo_type inside {AMO_LR_FN5, AMO_SC_FN5});
            sc_valid_r <= sc_valid;
        end // 结束语句块。
        rmw_addr <= unit.addr[31:2];
        rmw_rs2 <= unit.data_in;
        rmw_op <= amo_type;
    end // 结束语句块。

endmodule // 结束模块定义。
