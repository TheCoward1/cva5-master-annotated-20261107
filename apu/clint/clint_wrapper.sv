// ============================================================================
// 文件：apu/clint/clint_wrapper.sv
// 类型：module
// 名称：clint_wrapper
// 作用：为 CLINT 增加总线寄存器接口和地址译码。
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

module clint_wrapper // 定义 clint_wrapper 模块。

    #(
        parameter int unsigned NUM_CORES = 1, // 声明可配置参数。
        parameter logic AXI = 1'b1 //Else the wishbone bus is used；声明可配置参数。
    ) (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        output logic[63:0] mtime, // 声明输出端口。
        output logic[NUM_CORES-1:0] msip, // 声明输出端口。
        output logic[NUM_CORES-1:0] mtip, // 声明输出端口。

        //Address bits 31:16 are ignored, 1:0 assumed to be 00

        //Compliant Wishbone classic (not pipelined)
        input logic wb_cyc, // 声明输入端口。
        input logic wb_stb, // 声明输入端口。
        input logic wb_we, // 声明输入端口。
        input logic [15:2] wb_adr, // 声明输入端口。
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
    //Core Local INTerrupt unit (CLINT) wrapper
    //Handles addressing and bus interface
    //16-bit address space
    localparam logic [15:0] MSIP_BASE = 16'h0; //Must be 4-byte aligned；声明局部常量。
    localparam logic [15:0] MTIMECMP_BASE = 16'h4000; //Must be 8-byte aligned；声明局部常量。
    localparam logic [15:0] MTIME_BASE = 16'hbff8; //Must be 8-byte aligned；声明局部常量。
    localparam logic [15:0] CORES_MINUS_ONE = 16'(NUM_CORES-1); // 声明局部常量。

    localparam CORE_W = NUM_CORES == 1 ? 1 : $clog2(NUM_CORES); // 声明局部常量。

    logic[NUM_CORES-1:0][1:0][31:0] mtimecmp; // 声明信号、变量或生成变量。
    logic write_mtime; // 声明信号、变量或生成变量。
    logic write_mtimecmp; // 声明信号、变量或生成变量。
    logic write_msip; // 声明信号、变量或生成变量。
    logic write_upper; // 声明信号、变量或生成变量。
    logic[CORE_W-1:0] write_msip_core; // 声明信号、变量或生成变量。
    logic[CORE_W-1:0] write_mtimecmp_core; // 声明信号、变量或生成变量。
    logic[31:0] write_data; // 声明信号、变量或生成变量。
    logic[1:0][31:0] mtime_packed; // 声明信号、变量或生成变量。
    assign mtime = {mtime_packed[1], mtime_packed[0]}; // 执行连续赋值，把组合逻辑连接到目标信号。

    clint #(.NUM_CORES(NUM_CORES)) core (
        .write_mtime(write_mtime),
        .write_mtimecmp(write_mtimecmp),
        .write_msip(write_msip),
        .write_upper(write_upper),
        .write_msip_core(write_msip_core),
        .write_mtimecmp_core(write_mtimecmp_core),
        .write_data(write_data),
        .mtime(mtime_packed),
        .mtimecmp(mtimecmp),
        .msip(msip),
        .mtip(mtip),
    .*);


    //Interface
    generate if (AXI) begin : gen_axi_if // 开始生成块，在编译期展开硬件结构。
        //Simple implementation uses state machine for reads and writes
// 定义类型别名或枚举/结构类型。
        typedef enum logic[2:0] {
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
            unique case (state)
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
        logic doing_read; // 声明信号、变量或生成变量。
        assign doing_read = state == RACCEPT; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_arready = doing_read; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_rvalid = state == RRESP; // 执行连续赋值，把组合逻辑连接到目标信号。

        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (doing_read) begin // 执行条件判断，满足条件时进入对应分支。
                case ({s_axi_araddr[15:2], 2'b00}) inside // 开始多分支选择，根据表达式选择对应分支。
                    [MSIP_BASE:MSIP_BASE+4*CORES_MINUS_ONE] : s_axi_rdata <= {31'b0, msip[NUM_CORES == 1 ? '0 : s_axi_araddr[2+:CORE_W]]};
                    [MTIME_BASE:MTIME_BASE+4] : s_axi_rdata <= mtime_packed[s_axi_araddr[2]];
                    [MTIMECMP_BASE:MTIMECMP_BASE+4+8*CORES_MINUS_ONE] : s_axi_rdata <= mtimecmp[NUM_CORES == 1 ? '0 : s_axi_araddr[3+:CORE_W]][s_axi_araddr[2]];
                    default : s_axi_rdata <= '0; // 执行默认分支。
                endcase // 结束多分支选择。
            end // 结束语句块。
        end // 结束语句块。

        //Writes
        logic doing_write; // 声明信号、变量或生成变量。
        assign doing_write = state == WACCEPT; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_awready = doing_write; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_wready = doing_write; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_bvalid = state == WRESP; // 执行连续赋值，把组合逻辑连接到目标信号。

        assign write_data = s_axi_wdata; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign write_upper = s_axi_awaddr[2]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign write_msip_core = NUM_CORES == 1 ? '0 : s_axi_awaddr[2+:CORE_W]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign write_mtimecmp_core = NUM_CORES == 1 ? '0 : s_axi_awaddr[3+:CORE_W]; // 执行连续赋值，把组合逻辑连接到目标信号。

        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            write_msip = 0;
            write_mtime = 0;
            write_mtimecmp = 0;
            case ({s_axi_awaddr[15:2], 2'b00}) inside // 开始多分支选择，根据表达式选择对应分支。
                [MSIP_BASE:MSIP_BASE+4*CORES_MINUS_ONE] : write_msip = doing_write;
                [MTIME_BASE:MTIME_BASE+4] : write_mtime = doing_write;
                [MTIMECMP_BASE:MTIMECMP_BASE+4+8*CORES_MINUS_ONE] : write_mtimecmp = doing_write;
            endcase // 结束多分支选择。
        end // 结束语句块。

        //Not in use
        assign wb_ack = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    end else begin : gen_wishbone_if // 结束语句块。
        //Combinational response
        assign write_data = wb_dat_i; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign write_upper = wb_adr[2]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign wb_ack = wb_cyc & wb_stb; // 执行连续赋值，把组合逻辑连接到目标信号。

        assign write_msip_core = NUM_CORES == 1 ? '0 : wb_adr[2+:CORE_W]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign write_mtimecmp_core = NUM_CORES == 1 ? '0 : wb_adr[3+:CORE_W]; // 执行连续赋值，把组合逻辑连接到目标信号。

        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            write_mtime = 0;
            write_mtimecmp = 0;
            write_msip = 0;
            wb_dat_o = '0;

            case ({wb_adr[15:2], 2'b00}) inside // 开始多分支选择，根据表达式选择对应分支。
                [MSIP_BASE:MSIP_BASE+4*CORES_MINUS_ONE] : begin
                    write_msip = wb_cyc & wb_stb & wb_we;
                    wb_dat_o = {31'b0, msip[write_msip_core]};
                end // 结束语句块。
                [MTIME_BASE:MTIME_BASE+4] : begin
                    write_mtime = wb_cyc & wb_stb & wb_we;
                    wb_dat_o = mtime_packed[write_upper];
                end // 结束语句块。
                [MTIMECMP_BASE:MTIMECMP_BASE+4+8*CORES_MINUS_ONE] : begin
                    write_mtimecmp = wb_cyc & wb_stb & wb_we;
                    wb_dat_o = mtimecmp[write_mtimecmp_core][write_upper];
                end // 结束语句块。
            endcase // 结束多分支选择。
        end // 结束语句块。

        //Not in use
        assign s_axi_awready = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_wready = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_bvalid = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_arready = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_axi_rvalid = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

endmodule // 结束模块定义。
