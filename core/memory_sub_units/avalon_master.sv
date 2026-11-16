// ============================================================================
// 文件：core/memory_sub_units/avalon_master.sv
// 类型：module
// 名称：avalon_master
// 作用：把 CVA5 内存请求转换为 Avalon 主设备事务。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2019 Eric Matthews, Chris Keilbart, Lesley Shannon
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

module avalon_master // 定义 avalon_master 模块。

    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。

    #(
        parameter int unsigned LR_WAIT = 32, //The number of cycles lock is held after an LR；声明可配置参数。
        parameter logic INCLUDE_AMO = 1 //Required because the tools cannot fully optimize even if amo signals are tied off；声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        output logic write_outstanding, // 声明输出端口。
        avalon_interface.master m_avalon,

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
        REQUESTING,
        REQUESTING_AMO_R,
        REQUESTING_AMO_M,
        REQUESTING_AMO_W,
        READY_LR,
        REQUESTING_SC
    } state_t;
    state_t current_state;

    logic[$clog2(LR_WAIT)-1:0] lock_counter; // 声明信号、变量或生成变量。
    logic request_is_sc; // 声明信号、变量或生成变量。
    assign request_is_sc = amo & amo_type == AMO_SC_FN5; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign amo_unit.set_reservation = ls.new_request & amo & amo_type == AMO_LR_FN5; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.clear_reservation = ls.new_request; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.reservation = ls.addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.rs1 = ls.data_out; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.rs2 = m_avalon.writedata; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        m_avalon.addr[1:0] <= '0;
        unique case (current_state)
            READY : begin //Accept any request
                ls.ready <= ~ls.new_request | request_is_sc;
                ls.data_out <= 32'b1;
                ls.data_valid <= ls.new_request & request_is_sc;
                m_avalon.addr[31:2] <= ls.addr[31:2];
                m_avalon.byteenable <= ls.be;
                m_avalon.writedata <= ls.data_in;
                m_avalon.read <= ls.new_request & ls.re & ~request_is_sc;
                m_avalon.write <= ls.new_request & ls.we;
                m_avalon.lock <= ls.new_request & amo;
                write_outstanding <= ls.new_request & (ls.we | amo);
                amo_unit.rmw_valid <= 0;
                amo_unit.op <= amo_type;
                lock_counter <= '0;
                if (ls.new_request & (~amo | amo_type == AMO_LR_FN5)) // 执行条件判断，满足条件时进入对应分支。
                    current_state <= REQUESTING;
                else if (ls.new_request & amo & amo_type != AMO_SC_FN5) // 执行否则如果分支的条件判断。
                    current_state <= REQUESTING_AMO_R;
            end // 结束语句块。
            REQUESTING : begin //Wait for response
                ls.ready <= ~m_avalon.waitrequest;
                ls.data_out <= m_avalon.readdata;
                ls.data_valid <= m_avalon.read & ~m_avalon.waitrequest;
                m_avalon.read <= m_avalon.read & m_avalon.waitrequest;
                m_avalon.write <= m_avalon.write & m_avalon.waitrequest;
                write_outstanding <= m_avalon.write & ~m_avalon.waitrequest;
                if (~m_avalon.waitrequest) // 执行条件判断，满足条件时进入对应分支。
                    current_state <= m_avalon.lock ? READY_LR : READY;
            end // 结束语句块。
            REQUESTING_AMO_R : begin //Read for an AMO
                if (INCLUDE_AMO) begin // 执行条件判断，满足条件时进入对应分支。
                    ls.data_out <= m_avalon.readdata;
                    ls.data_valid <= ~m_avalon.waitrequest;
                    m_avalon.read <= m_avalon.waitrequest;
                    amo_unit.rmw_valid <= ~m_avalon.waitrequest;
                    if (~m_avalon.waitrequest) // 执行条件判断，满足条件时进入对应分支。
                        current_state <= REQUESTING_AMO_M;
                end // 结束语句块。
            end // 结束语句块。
            REQUESTING_AMO_M : begin //One cycle for computing the AMO write value
                if (INCLUDE_AMO) begin // 执行条件判断，满足条件时进入对应分支。
                    ls.data_valid <= 0;
                    m_avalon.writedata <= amo_unit.rd;
                    m_avalon.write <= 1;
                    amo_unit.rmw_valid <= 0;
                    current_state <= REQUESTING_AMO_W;
                end // 结束语句块。
            end // 结束语句块。
            REQUESTING_AMO_W : begin //Write for an AMO
                if (INCLUDE_AMO) begin // 执行条件判断，满足条件时进入对应分支。
                    ls.ready <= ~m_avalon.waitrequest;
                    m_avalon.write <= m_avalon.waitrequest;
                    m_avalon.lock <= m_avalon.waitrequest;
                    write_outstanding <= m_avalon.waitrequest;
                    if (~m_avalon.waitrequest) // 执行条件判断，满足条件时进入对应分支。
                        current_state <= READY;
                end // 结束语句块。
            end // 结束语句块。
            READY_LR : begin //Lock is held; hold for LR_WAIT cycles
                if (INCLUDE_AMO) begin // 执行条件判断，满足条件时进入对应分支。
                    ls.ready <= ~ls.new_request | (request_is_sc & ~amo_unit.reservation_valid);
                    ls.data_out <= {31'b0, ~amo_unit.reservation_valid};
                    ls.data_valid <= ls.new_request & request_is_sc;
                    m_avalon.addr[31:2] <= ls.addr[31:2];
                    m_avalon.byteenable <= ls.be;
                    m_avalon.writedata <= ls.data_in;
                    m_avalon.read <= ls.new_request & ls.re & ~request_is_sc;
                    m_avalon.write <= ls.new_request & (ls.we | (request_is_sc & amo_unit.reservation_valid));
                    
                    write_outstanding <= ls.new_request & (ls.we | amo);
                    amo_unit.rmw_valid <= 0;
                    amo_unit.op <= amo_type;

                    if (ls.new_request) // 执行条件判断，满足条件时进入对应分支。
                        m_avalon.lock <= amo;
                    else if (32'(lock_counter) == LR_WAIT-1) // 执行否则如果分支的条件判断。
                        m_avalon.lock <= 0;

                    lock_counter <= lock_counter + 1;

                    if (ls.new_request & (~amo | amo_type == AMO_LR_FN5)) // 执行条件判断，满足条件时进入对应分支。
                        current_state <= REQUESTING;
                    else if (ls.new_request & amo & amo_type != AMO_SC_FN5) // 执行否则如果分支的条件判断。
                        current_state <= REQUESTING_AMO_R;
                    else if (ls.new_request & amo & amo_type == AMO_SC_FN5 & amo_unit.reservation_valid) // 执行否则如果分支的条件判断。
                        current_state <= REQUESTING_SC;
                    else if (32'(lock_counter) == LR_WAIT-1 | ls.new_request) // 执行否则如果分支的条件判断。
                        current_state <= READY;
                end // 结束语句块。
            end // 结束语句块。
            REQUESTING_SC : begin //Exclusive write
                if (INCLUDE_AMO) begin // 执行条件判断，满足条件时进入对应分支。
                    ls.ready <= ~m_avalon.waitrequest;
                    ls.data_valid <= 0;
                    m_avalon.write <= m_avalon.waitrequest;
                    m_avalon.lock <= m_avalon.waitrequest;
                    write_outstanding <= m_avalon.waitrequest;
                    if (~m_avalon.waitrequest) // 执行条件判断，满足条件时进入对应分支。
                        current_state <= REQUESTING;
                end // 结束语句块。
            end // 结束语句块。
        endcase // 结束多分支选择。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            current_state <= READY;
    end // 结束语句块。

endmodule // 结束模块定义。
