// ============================================================================
// 文件：core/memory_sub_units/axi_master.sv
// 类型：module
// 名称：axi_master
// 作用：把 CVA5 内存请求转换为 AXI 主设备事务并处理读写通道握手。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2024 Eric Matthews, Chris Keilbart, Lesley Shannon
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

module axi_master // 定义 axi_master 模块。

    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        output logic write_outstanding, // 声明输出端口。
        axi_interface.master m_axi,

        input logic amo, // 声明输入端口。
        input amo_t amo_type, // 声明输入端口。
        amo_interface.subunit amo_unit,
        memory_sub_unit_interface.responder ls
    );

    ////////////////////////////////////////////////////
    //Implementation
// 定义类型别名或枚举/结构类型。
    typedef enum {
        READY,
        REQUESTING_WRITE,
        REQUESTING_READ,
        REQUESTING_AMO_M,
        WAITING_READ,
        WAITING_WRITE
    } state_t;
    state_t current_state;

    logic request_is_invalid_sc; // 声明信号、变量或生成变量。
    assign request_is_invalid_sc = amo & amo_type == AMO_SC_FN5 & ~amo_unit.reservation_valid; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign amo_unit.set_reservation = ls.new_request & amo & amo_type == AMO_LR_FN5; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.clear_reservation = ls.new_request; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.reservation = ls.addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.rs1 = ls.data_out; // 执行连续赋值，把组合逻辑连接到目标信号。

    logic[29:0] addr; // 声明信号、变量或生成变量。
    assign m_axi.awaddr = {addr, 2'b0}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.araddr = {addr, 2'b0}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.awlen = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.arlen = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.awburst = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.arburst = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.awid = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.arid = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.rready = 1; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.bready = 1; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        unique case (current_state)
            READY : begin //Accept any request
                ls.ready <= ~ls.new_request | request_is_invalid_sc;
                ls.data_out <= 1;
                ls.data_valid <= ls.new_request & request_is_invalid_sc;
                addr <= ls.addr[31:2];
                m_axi.awlock <= amo & amo_type != AMO_LR_FN5; //Used in WAITING_READ to determine if it was a RMW
                m_axi.awvalid <= ls.new_request & (ls.we | (amo & amo_type == AMO_SC_FN5 & amo_unit.reservation_valid));
                m_axi.arlock <= amo & amo_type != AMO_SC_FN5; //Used in WAITING_WRITE to determine if it was a RNW
                m_axi.arvalid <= ls.new_request & ls.re & ~(amo & amo_type == AMO_SC_FN5);
                m_axi.wvalid <= ls.new_request & (ls.we | (amo & amo_type == AMO_SC_FN5 & amo_unit.reservation_valid));
                m_axi.wdata <= ls.data_in;
                m_axi.wstrb <= ls.be;
                write_outstanding <= ls.new_request & (ls.we | amo);
                amo_unit.rmw_valid <= 0;
                amo_unit.op <= amo_type;
                amo_unit.rs2 <= ls.data_in; //Cannot use wdata because wdata will be overwritten if the RMW is not exclusive
                if (ls.new_request & (ls.we | (amo & amo_type == AMO_SC_FN5 & amo_unit.reservation_valid))) // 执行条件判断，满足条件时进入对应分支。
                    current_state <= REQUESTING_WRITE;
                else if (ls.new_request & ~request_is_invalid_sc) // 执行否则如果分支的条件判断。
                    current_state <= REQUESTING_READ;
            end // 结束语句块。
            REQUESTING_READ : begin //Wait for read to be accepted
                m_axi.arvalid <= ~m_axi.arready;
                if (m_axi.arready) // 执行条件判断，满足条件时进入对应分支。
                    current_state <= WAITING_READ;
            end // 结束语句块。
            WAITING_READ : begin //Wait for read response
                ls.ready <= m_axi.rvalid & ~m_axi.awlock;
                ls.data_out <= m_axi.rdata;
                ls.data_valid <= m_axi.rvalid;
                amo_unit.rmw_valid <= m_axi.rvalid;
                if (m_axi.rvalid) // 执行条件判断，满足条件时进入对应分支。
                    current_state <= m_axi.awlock ? REQUESTING_AMO_M : READY;
            end // 结束语句块。
            REQUESTING_AMO_M : begin //One cycle for computing the AMO write value
                ls.data_valid <= 0;
                m_axi.awvalid <= 1;
                m_axi.wvalid <= 1;
                m_axi.wdata <= amo_unit.rd;
                amo_unit.rmw_valid <= 0;
                current_state <= REQUESTING_WRITE;
            end // 结束语句块。
            REQUESTING_WRITE : begin //Wait for write (address and data) to be accepted
                m_axi.awvalid <= m_axi.awvalid & ~m_axi.awready;
                m_axi.wvalid <= m_axi.wvalid & ~m_axi.wready;
                if ((~m_axi.awvalid | m_axi.awready) & (~m_axi.wvalid | m_axi.wready)) // 执行条件判断，满足条件时进入对应分支。
                    current_state <= WAITING_WRITE;
            end // 结束语句块。
            WAITING_WRITE : begin //Wait for write response; resubmit if RMW was not exclusive
                ls.ready <= m_axi.bvalid & (~m_axi.arlock | m_axi.bresp == 2'b01);
                ls.data_out <= {31'b0, m_axi.bresp != 2'b01};
                ls.data_valid <= m_axi.bvalid & m_axi.awlock & ~m_axi.arlock;
                m_axi.arvalid <= m_axi.bvalid & m_axi.arlock & m_axi.bresp != 2'b01;
                write_outstanding <= ~(m_axi.bvalid & (~m_axi.arlock | m_axi.bresp == 2'b01));
                if (m_axi.bvalid) // 执行条件判断，满足条件时进入对应分支。
                    current_state <= m_axi.arlock & m_axi.bresp != 2'b01 ? REQUESTING_READ : READY;
            end // 结束语句块。
        endcase // 结束多分支选择。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            current_state <= READY;
    end // 结束语句块。

endmodule // 结束模块定义。
