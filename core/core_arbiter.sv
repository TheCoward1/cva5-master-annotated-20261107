// ============================================================================
// 文件：core/core_arbiter.sv
// 类型：module
// 名称：core_arbiter
// 作用：仲裁多个内部请求源对共享资源的访问。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2024 Chris Keilbart
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

module core_arbiter // 定义 core_arbiter 模块。

    #(
        parameter logic INCLUDE_DCACHE = 1'b1, // 声明可配置参数。
        parameter logic INCLUDE_ICACHE = 1'b1, // 声明可配置参数。
        parameter logic INCLUDE_MMUS = 1'b1 // 声明可配置参数。
    ) (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        mem_interface.rw_slave dcache,
        mem_interface.ro_slave icache,
        mem_interface.ro_slave dmmu,
        mem_interface.ro_slave immu,
        mem_interface.mem_master mem
    );

    //Multiplexes memory requests and demultiplexes memory responses
    //If the MMUs are not present the MSB of the memory ID is always 0
    //If the I$ is also not present the entire ID can be set to 0

    logic[3:0] request; // 声明信号、变量或生成变量。
    logic[3:0][31:2] addr; // 声明信号、变量或生成变量。
    logic[3:0][4:0] rlen; // 声明信号、变量或生成变量。
    logic[3:0] rnw; // 声明信号、变量或生成变量。
    logic[3:0] rmw; // 声明信号、变量或生成变量。
    logic[1:0] port; // 声明信号、变量或生成变量。

    ////////////////////////////////////////////////////
    //Implementation

    //D$
    assign request[0] = INCLUDE_DCACHE ? dcache.request : 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign addr[0] = INCLUDE_DCACHE ? dcache.addr : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rlen[0] = INCLUDE_DCACHE ? dcache.rlen : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rnw[0] = INCLUDE_DCACHE ? dcache.rnw : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rmw[0] = INCLUDE_DCACHE ? dcache.rmw : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.wbe = dcache.wbe; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.wdata = dcache.wdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dcache.inv = mem.inv; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dcache.inv_addr = mem.inv_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dcache.write_outstanding = mem.write_outstanding; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dcache.ack = mem.ack & port == 2'b00; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dcache.rvalid = mem.rvalid & mem.rid == 2'b00; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dcache.rdata = mem.rdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    //I$
    assign request[1] = INCLUDE_ICACHE ? icache.request : 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign addr[1] = INCLUDE_ICACHE ? icache.addr : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rlen[1] = INCLUDE_ICACHE ? icache.rlen : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rnw[1] = INCLUDE_ICACHE ? 1 : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rmw[1] = INCLUDE_ICACHE ? 0 : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign icache.ack = mem.ack & port == 2'b01; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign icache.rvalid = mem.rvalid & mem.rid == 2'b01; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign icache.rdata = mem.rdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    //DMMU
    assign request[2] = INCLUDE_MMUS ? dmmu.request : 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign addr[2] = INCLUDE_MMUS ? dmmu.addr : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rlen[2] = INCLUDE_MMUS ? dmmu.rlen : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rnw[2] = INCLUDE_MMUS ? 1 : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rmw[2] = INCLUDE_MMUS ? 0 : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dmmu.rdata = mem.rdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dmmu.ack = mem.ack & port == 2'b10; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dmmu.rvalid = mem.rvalid & mem.rid == 2'b10; // 执行连续赋值，把组合逻辑连接到目标信号。
    //IMMU
    assign request[3] = INCLUDE_MMUS ? immu.request : 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign addr[3] = INCLUDE_MMUS ? immu.addr : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rlen[3] = INCLUDE_MMUS ? immu.rlen : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rnw[3] = INCLUDE_MMUS ? 1 : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rmw[3] = INCLUDE_MMUS ? 0 : 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign immu.rdata = mem.rdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign immu.ack = mem.ack & port == 2'b11; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign immu.rvalid = mem.rvalid & mem.rid == 2'b11; // 执行连续赋值，把组合逻辑连接到目标信号。

    
    ////////////////////////////////////////////////////
    //Arbitration
    round_robin #(.NUM_PORTS(4)) rr (
        .requests(request),
        .grant(mem.request & mem.ack),
        .grantee(port),
    .*);

    assign mem.request = |request; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.addr = addr[port]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.rlen = rlen[port]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.rnw = rnw[port]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.rmw = rmw[port]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.id = port; // 执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
