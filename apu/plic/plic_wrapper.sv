// ============================================================================
// 文件：apu/plic/plic_wrapper.sv
// 类型：module
// 名称：plic_wrapper
// 作用：为 PLIC 增加总线寄存器接口和中断源连接。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2024 Chris Keilbart, Mohammad Shahidzadeh
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
 *             Mohammad Shahidzadeh <mohammad_shahidzadeh_asadi@sfu.ca>
 */

module plic_wrapper // 定义 plic_wrapper 模块。

    #(
        parameter int unsigned NUM_SOURCES = 1, // 声明可配置参数。
        parameter int unsigned NUM_TARGETS = 1, // 声明可配置参数。
        parameter int unsigned PRIORITY_W = 4, // 声明可配置参数。
        parameter int unsigned REG_STAGE = 1, //The stage in the comparison tree to insert registers at, must be 1 <= N <= clog2(NUM_SOURCES+1)；声明可配置参数。
        parameter logic AXI = 1'b0 //Else the wishbone bus is used；声明可配置参数。
    ) (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        input logic[NUM_SOURCES:1] irq_srcs, // 声明输入端口。
        input logic[NUM_SOURCES-1:0] edge_sensitive, //Both rising and falling edges, else level sensitive and active high；声明输入端口。
        output logic[NUM_TARGETS-1:0] eip, // 声明输出端口。

        //Address bits 31:26 are ignored, 1:0 assumed to be 00

        //Compliant Wishbone classic (not pipelined)
        input logic wb_cyc, // 声明输入端口。
        input logic wb_stb, // 声明输入端口。
        input logic wb_we, // 声明输入端口。
        input logic [25:2] wb_adr, // 声明输入端口。
        input logic [31:0] wb_dat_i, // 声明输入端口。
        output logic [31:0] wb_dat_o, // 声明输出端口。
        output logic wb_ack, // 声明输出端口。

        //Compliant AXI Lite interface; does not include optional awprot, wstrb, bresp, arprot, and rresp
        input logic s_axi_awvalid, // 声明输入端口。
        input logic[31:0] s_axi_awaddr, // 声明输入端口。
        output logic s_axi_awready, // 声明输出端口。
        input logic s_axi_wvalid, // 声明输入端口。
        input logic[31:0] s_axi_wdata, // 声明输入端口。
        output logic s_axi_wready, // 声明输出端口。
        output logic s_axi_bvalid, // 声明输出端口。
        input logic s_axi_bready, // 声明输入端口。
        input logic s_axi_arvalid, // 声明输入端口。
        input logic[31:0] s_axi_araddr, // 声明输入端口。
        output logic s_axi_arready, // 声明输出端口。
        output logic s_axi_rvalid, // 声明输出端口。
        output logic[31:0] s_axi_rdata, // 声明输出端口。
        input logic s_axi_rready // 声明输入端口。
    );

    ////////////////////////////////////////////////////
    //RISC-V Platform-Level Interrupt Controller (PLIC) wrapper
    //Handles bus interface
    //26-bit address space

    //If the parameter is too large such that the register stage is skipped, force it lower to enforce correct functionality
    localparam int unsigned REG_STAGE_CORRECTED = REG_STAGE > $clog2(NUM_SOURCES+1)+1 ? 1 : REG_STAGE; // 声明局部常量。

    logic read_reg; // 声明信号、变量或生成变量。
    logic write_reg; // 声明信号、变量或生成变量。
    logic[25:2] addr; // 声明信号、变量或生成变量。
    logic[31:0] rdata; // 声明信号、变量或生成变量。
    logic[31:0] wdata; // 声明信号、变量或生成变量。

    plic #(
        .NUM_SOURCES(NUM_SOURCES),
        .NUM_TARGETS(NUM_TARGETS),
        .PRIORITY_W(PRIORITY_W),
        .REG_STAGE(REG_STAGE_CORRECTED)
    ) plic_inst (
        .irq_srcs(irq_srcs),
        .edge_sensitive(edge_sensitive),
        .read_reg(read_reg),
        .write_reg(write_reg),
        .addr(addr),
        .wdata(wdata),
        .rdata(rdata),
        .eip(eip),
    .*);


    //Interface
    generate if (AXI) begin : gen_axi_if // 开始生成块，在编译期展开硬件结构。
        //Simple implementation uses state machine for reads and writes
// 定义类型别名或枚举/结构类型。
        typedef enum logic [2:0] {
            IDLE,
            RACCEPT,
            WACCEPT,
            RRESP,
            WRESP
        } state_t;
        state_t state;
        state_t next_state;

        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) // 执行条件判断，满足条件时进入对应分支。
                state <= IDLE;
            else // 执行否则分支。
                state <= next_state;
        end // 结束语句块。

        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            unique case (state) inside
                IDLE : begin
                    if (s_axi_awvalid & s_axi_wvalid) // 执行条件判断，满足条件时进入对应分支。
                        next_state = WACCEPT;
                    else if (s_axi_arvalid) // 执行否则如果分支的条件判断。
                        next_state = RACCEPT;
                    else // 执行否则分支。
                        next_state = IDLE;
                end // 结束语句块。
                RACCEPT : next_state = RRESP;
                WACCEPT : next_state = WRESP;
                RRESP : next_state = s_axi_rready ? IDLE : RRESP;
                WRESP : next_state = s_axi_bready ? IDLE : WRESP;
            endcase // 结束多分支选择。
        end // 结束语句块。

        //Reads
        assign read_reg = state == RACCEPT; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_arready = read_reg; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_rvalid = state == RRESP; // 执行连续赋值，把组合逻辑连接到目标信号。

        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (read_reg) // 执行条件判断，满足条件时进入对应分支。
                s_axi_rdata <= rdata;
        end // 结束语句块。

        //Writes
        assign write_reg = state == WACCEPT; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_awready = write_reg; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_wready = write_reg; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign wdata = s_axi_wdata; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_bvalid = state == WRESP; // 执行连续赋值，把组合逻辑连接到目标信号。

        //Must use the read address while in the idle state to ensure read_reg claims the right interrupt
        assign addr = write_reg ? s_axi_awaddr[25:2] : s_axi_araddr[25:2]; // 执行连续赋值，把组合逻辑连接到目标信号。

        //Not in use
        assign wb_ack = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    end else begin : gen_wishbone_if // 结束语句块。
        //Writes are asynchronous, reads need two cycles
        logic read_done; // 声明信号、变量或生成变量。
        assign addr = wb_adr[25:2]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign wdata = wb_dat_i; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign write_reg = wb_cyc & wb_stb & wb_we; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign wb_ack = write_reg | read_done; // 执行连续赋值，把组合逻辑连接到目标信号。

        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            read_reg <= wb_cyc & wb_stb & ~wb_we & ~read_reg & ~read_done;
            read_done <= read_reg;
            wb_dat_o <= rdata;
        end // 结束语句块。

        //Not in use
        assign s_axi_awready = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_wready = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_bvalid = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_arready = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_rvalid = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

endmodule // 结束模块定义。
