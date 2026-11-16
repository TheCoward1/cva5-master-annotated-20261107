// ============================================================================
// 文件：apu/busses/multicore_arbiter.sv
// 类型：module
// 名称：multicore_arbiter
// 作用：仲裁多个核心对共享存储器资源的访问，避免请求冲突。
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

module multicore_arbiter // 定义 multicore_arbiter 模块。

    #(
        parameter int unsigned NUM_CORES = 1 // 声明可配置参数。
    ) (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        mem_interface.mem_slave mems[NUM_CORES-1:0],

        //Requests can be returned out of order for different IDs
        //However, the original ordering of writes and reads to
        //the same address must be preserved
        input logic request_pop, // 声明输入端口。
        output logic request_valid, // 声明输出端口。
        output logic[31:2] request_addr, // 声明输出端口。
        output logic request_rnw, // 声明输出端口。
        output logic[4:0] request_rlen, // 声明输出端口。
        output logic[31:0] request_wdata, // 声明输出端口。
        output logic[3:0] request_wbe, // 声明输出端口。
        output logic[1+$clog2(NUM_CORES):0] request_id, // 声明输出端口。

        input logic request_rvalid, // 声明输入端口。
        input logic[31:0] request_rdata, // 声明输入端口。
        input logic[1+$clog2(NUM_CORES):0] request_rid, // 声明输入端口。
        input logic[NUM_CORES-1:0] write_outstanding // 声明输入端口。
    );

    //Multiplexes memory requests and submits invalidations
    //Write coalescing would be a nice future improvement
    localparam FIFO_DEPTH = 32; // 声明局部常量。
// 定义类型别名或枚举/结构类型。
    typedef logic[$clog2(FIFO_DEPTH):0] count_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[2+$clog2(NUM_CORES)-1:0] full_id_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic[31:2] addr; // 声明信号、变量或生成变量。
        logic[4:0] rlen; // 声明信号、变量或生成变量。
        logic rnw; // 声明信号、变量或生成变量。
        logic[3:0] wbe; // 声明信号、变量或生成变量。
        logic[31:0] wdata; // 声明信号、变量或生成变量。
        full_id_t id;
        logic rmw; // 声明信号、变量或生成变量。
    } request_t;
    request_t in_req;
    request_t out_req;
    fifo_interface #(.DATA_TYPE(request_t)) request_fifo();

    logic[NUM_CORES-1:0] requests; // 声明信号、变量或生成变量。
    logic[NUM_CORES-1:0] acks; // 声明信号、变量或生成变量。
    logic[NUM_CORES-1:0][31:2] addr; // 声明信号、变量或生成变量。
    logic[NUM_CORES-1:0][4:0] rlen; // 声明信号、变量或生成变量。
    logic[NUM_CORES-1:0] rnw; // 声明信号、变量或生成变量。
    logic[NUM_CORES-1:0] rmw; // 声明信号、变量或生成变量。
    logic[NUM_CORES-1:0][3:0] wbe; // 声明信号、变量或生成变量。
    logic[NUM_CORES-1:0][31:0] wdata; // 声明信号、变量或生成变量。
    logic[NUM_CORES-1:0][1:0] id; // 声明信号、变量或生成变量。
    full_id_t padded_id;
    logic[NUM_CORES-1:0] rvalids; // 声明信号、变量或生成变量。
    logic[(NUM_CORES == 1 ? 1 : $clog2(NUM_CORES))-1:0] chosen_port; // 声明信号、变量或生成变量。
    logic rvalid; // 声明信号、变量或生成变量。
    logic[31:0] rdata; // 声明信号、变量或生成变量。
    full_id_t rid;
    logic[NUM_CORES-1:0] out_core; // 声明信号、变量或生成变量。
    count_t[NUM_CORES-1:0] wcounts;
    
    logic request_push; // 声明信号、变量或生成变量。
    logic request_finished; // 声明信号、变量或生成变量。

    genvar i; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation
    
    //Unpack interface
    generate for (i = 0; i < NUM_CORES; i++) begin : gen_unpack // 开始生成块，在编译期展开硬件结构。
        assign requests[i] = mems[i].request; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign addr[i] = mems[i].addr; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign rlen[i] = mems[i].rlen; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign rnw[i] = mems[i].rnw; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign rmw[i] = mems[i].rmw; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign wbe[i] = mems[i].wbe; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign wdata[i] = mems[i].wdata; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign id[i] = mems[i].id; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign acks[i] = request_push & i == int'(chosen_port); // 执行连续赋值，把组合逻辑连接到目标信号。
        assign mems[i].ack = acks[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign mems[i].inv_addr = in_req.addr; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign mems[i].inv = request_push & ~in_req.rnw & i != int'(chosen_port); // 执行连续赋值，把组合逻辑连接到目标信号。
        assign mems[i].rvalid = rvalids[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign mems[i].rdata = request_rdata; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign mems[i].rid = request_rid[1:0]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign mems[i].write_outstanding = wcounts[i][$clog2(FIFO_DEPTH)] | write_outstanding[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。
    
    //Once accepted, stall until the RMW is resolved
    logic[(NUM_CORES == 1 ? 1 : $clog2(NUM_CORES))-1:0] rmw_index; // 声明信号、变量或生成变量。
    logic rmw_is_on; // 声明信号、变量或生成变量。
    logic[NUM_CORES-1:0] accept_request_from_rmw_core; // 声明信号、变量或生成变量。
    logic rmw_hit; // 声明信号、变量或生成变量。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (in_req.rmw & request_push) // 执行条件判断，满足条件时进入对应分支。
            rmw_index <= chosen_port;
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            rmw_is_on <= 0;
        else if (in_req.rmw & request_push) // 执行否则如果分支的条件判断。
            rmw_is_on <= 1;
        else if (~in_req.rmw) // 执行否则如果分支的条件判断。
            rmw_is_on <= 0;
    end // 结束语句块。

    assign accept_request_from_rmw_core = (rmw_is_on ? (1'b1 << rmw_index) : {NUM_CORES{1'b1}}); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rmw_hit = |(requests & accept_request_from_rmw_core); // 执行连续赋值，把组合逻辑连接到目标信号。

    //Request FIFO
    assign request_push = ~request_fifo.full & |requests & (~rmw_is_on | rmw_hit); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_fifo.data_in = in_req; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign out_req = request_fifo.data_out; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_valid = request_fifo.valid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_addr = out_req.addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_rnw = out_req.rnw; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_rlen = out_req.rlen; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_wdata = out_req.wdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_wbe = out_req.wbe; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_id = out_req.id; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign request_fifo.push = request_push; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_fifo.potential_push = request_push; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_fifo.pop = request_pop; // 执行连续赋值，把组合逻辑连接到目标信号。
    cva5_fifo #(.DATA_TYPE(request_t), .FIFO_DEPTH(FIFO_DEPTH)) fifo_inst (.fifo(request_fifo), .*);

    //Arbitration
    round_robin #(.NUM_PORTS(NUM_CORES)) rr (
        .requests(requests & accept_request_from_rmw_core),
        .grant(request_push),
        .grantee(chosen_port),
    .*);

    //Select input
    assign in_req = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        addr : addr[chosen_port],
        rlen : rlen[chosen_port],
        rnw : rnw[chosen_port],
        wbe : wbe[chosen_port],
        wdata : wdata[chosen_port],
        id : padded_id,
        rmw : rmw[chosen_port]
    };

    generate if (NUM_CORES == 1) begin : gen_no_id // 开始生成块，在编译期展开硬件结构。
        assign padded_id = id[chosen_port]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign rvalids[0] = request_rvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign out_core[0] = 1; // 执行连续赋值，把组合逻辑连接到目标信号。
    end else begin : gen_id // 结束语句块。
        assign padded_id = {chosen_port, id[chosen_port]}; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign rvalids = request_rvalid << request_rid[2+:$clog2(NUM_CORES)]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign out_core = 1 << request_id[2+:$clog2(NUM_CORES)]; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

    //Write tracking; tracked for each core
    logic[NUM_CORES-1:0] wcount_incr; // 声明信号、变量或生成变量。
    logic[NUM_CORES-1:0] wcount_decr; // 声明信号、变量或生成变量。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int j = 0; j < NUM_CORES; j++) begin // 执行循环或遍历。
            wcount_incr[j] = acks[j] & ~rnw[j];
            wcount_decr[j] = out_core[j] & ~request_rnw & request_pop;
        end // 结束语句块。
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            wcounts <= '0;
        else begin // 执行否则分支。
            for (int j = 0; j < NUM_CORES; j++) //Flipped increment / decrement allows the MSB to be used as a nonzero signal；执行循环或遍历。
                wcounts[j] <= wcounts[j] - count_t'(wcount_incr[j]) + count_t'(wcount_decr[j]);
        end // 结束语句块。
    end // 结束语句块。

endmodule // 结束模块定义。
