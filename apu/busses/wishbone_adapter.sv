// ============================================================================
// 文件：apu/busses/wishbone_adapter.sv
// 类型：module
// 名称：wishbone_adapter
// 作用：把 CVA5 内部存储器请求转换为 Wishbone 总线事务。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2022 Eric Matthews, Chris Keilbart
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

module wishbone_adapter // 定义 wishbone_adapter 模块。

    #(
        parameter int unsigned NUM_CORES = 1 // 声明可配置参数。
    ) (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        mem_interface.mem_slave mems[NUM_CORES-1:0],
        wishbone_interface.master wishbone
    );

    ////////////////////////////////////////////////////
    //Multicore interface
    //Arbitrates requests
    logic request_pop; // 声明信号、变量或生成变量。
    logic request_valid; // 声明信号、变量或生成变量。
    logic[31:2] request_addr; // 声明信号、变量或生成变量。
    logic request_rnw; // 声明信号、变量或生成变量。
    logic[4:0] request_rlen; // 声明信号、变量或生成变量。
    logic[31:0] request_wdata; // 声明信号、变量或生成变量。
    logic[3:0] request_wbe; // 声明信号、变量或生成变量。
    logic[1+$clog2(NUM_CORES):0] request_id; // 声明信号、变量或生成变量。
    logic request_rvalid; // 声明信号、变量或生成变量。
    logic[31:0] request_rdata; // 声明信号、变量或生成变量。
    logic[1+$clog2(NUM_CORES):0] request_rid; // 声明信号、变量或生成变量。

    multicore_arbiter #(.NUM_CORES(NUM_CORES)) arb (
        .mems(mems),
        .request_pop(request_pop),
        .request_valid(request_valid),
        .request_addr(request_addr),
        .request_rnw(request_rnw),
        .request_rlen(request_rlen),
        .request_wdata(request_wdata),
        .request_wbe(request_wbe),
        .request_id(request_id),
        .request_rvalid(request_rvalid),
        .request_rdata(request_rdata),
        .request_rid(request_rid),
        .write_outstanding('0),
    .*);

    ////////////////////////////////////////////////////
    //Wishbone interface
    //Read bursts and single writes
    logic[4:0] rcount; // 声明信号、变量或生成变量。
    logic[4:0] len; // 声明信号、变量或生成变量。
    logic last; // 声明信号、变量或生成变量。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst | request_pop) // 执行条件判断，满足条件时进入对应分支。
            rcount <= '0;
        else // 执行否则分支。
            rcount <= rcount + 5'(wishbone.ack);
    end // 结束语句块。

    assign request_pop = wishbone.ack & last; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign len = {5{request_rnw}} & request_rlen; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign last = rcount == len; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign wishbone.cyc = request_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wishbone.stb = request_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wishbone.we = ~request_rnw; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wishbone.sel = request_rnw ? '1 : request_wbe; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wishbone.dat_w = request_wdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wishbone.bte = 2'b00; //Incrementing burst；执行连续赋值，把组合逻辑连接到目标信号。
    assign wishbone.cti = {last, last, 1'b1}; //End of burst is used even for single-cycle transfers；执行连续赋值，把组合逻辑连接到目标信号。
    assign wishbone.adr[29:5] = request_addr[31:7]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wishbone.adr[4:0] = (request_addr[6:2] & ~len) | (rcount & len); // 执行连续赋值，把组合逻辑连接到目标信号。
    

    //Return data registered for frequency
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        request_rdata <= wishbone.dat_r;
        request_rvalid <= request_rnw & wishbone.ack;
        request_rid <= request_id;
    end // 结束语句块。

endmodule // 结束模块定义。
