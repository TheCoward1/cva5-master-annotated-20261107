// ============================================================================
// 文件：apu/busses/axi_adapter.sv
// 类型：module
// 名称：axi_adapter
// 作用：把 CVA5 内部存储器请求转换为 AXI 事务，并处理读写通道握手。
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

module axi_adapter // 定义 axi_adapter 模块。

    #(
        parameter int unsigned NUM_CORES = 1 // 声明可配置参数。
    ) (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        mem_interface.mem_slave mems[NUM_CORES-1:0],
        axi_interface.master axi
    );

    localparam MAX_OUTSTANDING = 8; // 声明局部常量。
    localparam MAX_W = $clog2(MAX_OUTSTANDING); // 声明局部常量。

// 定义类型别名或枚举/结构类型。
    typedef logic[7:0] hash_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[MAX_W:0] count_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[MAX_W-1:0] index_t;

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
    logic[NUM_CORES-1:0] write_outstanding; // 声明信号、变量或生成变量。

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
        .write_outstanding(write_outstanding),
    .*);

    ////////////////////////////////////////////////////
    //AXI interface
    //Read bursts and single writes
    //Ordering between reads and writes must be enforced
    logic addr_blocked; // 声明信号、变量或生成变量。

    //AR
    assign axi.arvalid = request_valid & request_rnw & ~addr_blocked; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.araddr = {request_addr[31:7], request_addr[6:2] & ~request_rlen, 2'b00}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.arlen = {3'b0, request_rlen}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.arsize = 3'b010; //4 bytes；执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.arburst = 2'b01; //Incrementing；执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.arcache = 4'b0011; //Bufferable and non-cacheable memory；执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.arlock = 0; //Not locked；执行连续赋值，把组合逻辑连接到目标信号。

    //R
    assign axi.rready = 1; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_rdata = axi.rdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_rvalid = axi.rvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
    //Don't care about rresp or rlast

    logic sent_aw; // 声明信号、变量或生成变量。
    logic sent_w; // 声明信号、变量或生成变量。
    logic write_sent; // 声明信号、变量或生成变量。
    assign write_sent = (axi.awvalid & axi.awready | sent_aw) & (axi.wvalid & axi.wready | sent_w); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst | write_sent) begin // 执行条件判断，满足条件时进入对应分支。
            sent_aw <= 0;
            sent_w <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            sent_aw <= sent_aw | (axi.awvalid & axi.awready);
            sent_w <= sent_w | (axi.wvalid & axi.wready);
        end // 结束语句块。
    end // 结束语句块。

    //AW
    assign axi.awvalid = request_valid & ~request_rnw & ~sent_aw & ~addr_blocked; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.awaddr = {request_addr, 2'b00}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.awlen = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.awsize = 3'b010; //4 bytes；执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.awburst = 2'b01; //Incrementing；执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.awcache = 4'b0011; //Bufferable and non-cacheable memory；执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.awlock = 0; //Not locked；执行连续赋值，把组合逻辑连接到目标信号。

    //W
    assign axi.wvalid = request_valid & ~request_rnw & ~sent_w; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.wdata = request_wdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.wstrb = request_wbe; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.wlast = 1; // 执行连续赋值，把组合逻辑连接到目标信号。

    //B
    assign axi.bready = 1; // 执行连续赋值，把组合逻辑连接到目标信号。
    //Don't care about bresp

    assign request_pop = (axi.arvalid & axi.arready) | write_sent; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Outstanding tracking
    //Outstanding requests are tracked using a fully-associative array
    
    //Writes need to wait for outstanding write collisions to finish
    //Writes need to wait for outstanding read collisions to finish
    //Reads need to wait for outstanding write collisions to finish

    //Free slots
    logic[MAX_OUTSTANDING-1:0] frees; // 声明信号、变量或生成变量。
    index_t free_index;

    priority_encoder #(.WIDTH(MAX_OUTSTANDING)) free_enc (
        .priority_vector(frees),
        .encoded_result(free_index)
    );

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            frees <= '1;
        else begin // 执行否则分支。
            if (axi.rvalid & axi.rlast) // 执行条件判断，满足条件时进入对应分支。
                frees[axi.rid[MAX_W-1:0]] <= 1;
            if (axi.bvalid) // 执行条件判断，满足条件时进入对应分支。
                frees[axi.bid[MAX_W-1:0]] <= 1;
            if ((axi.awvalid & axi.awready) | (axi.arvalid & axi.arready)) // 执行条件判断，满足条件时进入对应分支。
                frees[free_index] <= 0;
        end // 结束语句块。
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        axi.arid = '0;
        axi.awid = '0;
        axi.arid[MAX_W-1:0] = free_index;
        axi.awid[MAX_W-1:0] = free_index;
    end // 结束语句块。

    //Outstanding storage
    hash_t request_hash;
    logic[5:0] request_lower; // 声明信号、变量或生成变量。
    logic[5:0] request_upper; // 声明信号、变量或生成变量。

    hash_t[MAX_OUTSTANDING-1:0] hashes;
    logic[MAX_OUTSTANDING-1:0] rnws; // 声明信号、变量或生成变量。
    logic[MAX_OUTSTANDING-1:0][5:0] lowers; // 声明信号、变量或生成变量。
    logic[MAX_OUTSTANDING-1:0][5:0] uppers; // 声明信号、变量或生成变量。
    logic[MAX_OUTSTANDING-1:0][3:0] wbes; // 声明信号、变量或生成变量。
    logic[MAX_OUTSTANDING-1:0][1+$clog2(NUM_CORES):0] ids; // 声明信号、变量或生成变量。
    
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if ((axi.awvalid & axi.awready) | (axi.arvalid & axi.arready)) begin // 执行条件判断，满足条件时进入对应分支。
            rnws[free_index] <= request_rnw;
            lowers[free_index] <= request_lower;
            uppers[free_index] <= request_upper;
            wbes[free_index] <= request_wbe;
            ids[free_index] <= request_id;
            hashes[free_index] <= request_hash;
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Hash function
    //8-bit hashes can easily be compared using the carry circuitry
    //Only hash address bits that do not correspond to a line
    assign request_hash[0] = request_addr[8] ^ request_addr[16] ^ request_addr[24]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_hash[1] = request_addr[9] ^ request_addr[17] ^ request_addr[25]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_hash[2] = request_addr[10] ^ request_addr[18] ^ request_addr[26]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_hash[3] = request_addr[11] ^ request_addr[19] ^ request_addr[27]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_hash[4] = request_addr[12] ^ request_addr[20] ^ request_addr[28]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_hash[5] = request_addr[13] ^ request_addr[21] ^ request_addr[29]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_hash[6] = request_addr[14] ^ request_addr[22] ^ request_addr[30]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_hash[7] = request_addr[15] ^ request_addr[23] ^ request_addr[31]; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Collision check
    //Collisions are checked at byte granularity; this is complicated by burst requests
    //Therefore, the lower and upper boundaries of the request within a 64-byte "arena" are stored
    //Collisions must therefore be within the boundaries
    //Writes collide with all outstanding requests
    //Reads only collide with outstanding writes
    logic[MAX_OUTSTANDING-1:0] range_collision; // 声明信号、变量或生成变量。
    logic[MAX_OUTSTANDING-1:0] wbe_collision; // 声明信号、变量或生成变量。
    logic[MAX_OUTSTANDING-1:0] hash_collision; // 声明信号、变量或生成变量。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < MAX_OUTSTANDING; i++) begin // 执行循环或遍历。
            hash_collision[i] = ~frees[i] & request_hash == hashes[i];
            if (request_rnw) begin // 执行条件判断，满足条件时进入对应分支。
                range_collision[i] = (axi.araddr[7:2] <= lowers[i]) & (axi.araddr[7:2] + {1'b0, request_rlen} >= uppers[i]);
                wbe_collision[i] = ~rnws[i];
            end // 结束语句块。
            else begin // 执行否则分支。
                range_collision[i] = (request_addr[7:2] >= lowers[i]) & (request_addr[7:2] <= uppers[i]);
                wbe_collision[i] = rnws[i] | |(request_wbe & wbes[i]);
            end // 结束语句块。
        end // 结束语句块。
    end // 结束语句块。
    assign addr_blocked = |(hash_collision & range_collision & wbe_collision) | ~|frees; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign request_lower = request_rnw ? axi.araddr[7:2] : request_addr[7:2]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign request_upper = request_rnw ? axi.araddr[7:2] + {1'b0, request_rlen} : request_addr[7:2]; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign request_rid = ids[axi.rid[MAX_W-1:0]]; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Write outstanding check
    logic[NUM_CORES-1:0][MAX_OUTSTANDING-1:0] outstanding_is_core; // 声明信号、变量或生成变量。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        write_outstanding = '0;
        for (int i = 0; i < NUM_CORES; i++) begin // 执行循环或遍历。
            for (int j = 0; j < MAX_OUTSTANDING; j++) // 执行循环或遍历。
                write_outstanding[i] |= ~frees[j] & ~rnws[j] & outstanding_is_core[i][j];
        end // 结束语句块。
    end // 结束语句块。

    generate if (NUM_CORES > 1) begin : gen_id_check // 开始生成块，在编译期展开硬件结构。
        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            for (int i = 0; i < NUM_CORES; i++) begin // 执行循环或遍历。
                for (int j = 0; j < MAX_OUTSTANDING; j++) // 执行循环或遍历。
                    outstanding_is_core[i][j] = i == ids[j][2+:$clog2(NUM_CORES)];
            end // 结束语句块。
    end // 结束语句块。
    end else begin : gen_no_check // 结束语句块。
        assign outstanding_is_core = '1; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

endmodule // 结束模块定义。
