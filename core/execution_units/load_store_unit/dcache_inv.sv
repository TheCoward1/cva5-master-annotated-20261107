// ============================================================================
// 文件：core/execution_units/load_store_unit/dcache_inv.sv
// 类型：module
// 名称：dcache_inv
// 作用：实现带外部缓存行失效接口的写回数据缓存。
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

module dcache_inv // 定义 dcache_inv 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG // 声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        mem_interface.rw_master mem,
        output logic write_outstanding, // 声明输出端口。
        input logic amo, // 声明输入端口。
        input amo_t amo_type, // 声明输入端口。
        amo_interface.subunit amo_unit,
        input logic cbo, // 声明输入端口。
        input logic uncacheable, // 声明输入端口。
        memory_sub_unit_interface.responder ls,
        input logic load_peek, //If the next request may be a load；声明输入端口。
        input logic[31:0] load_addr_peek //The address in that case；声明输入端口。
    );

    localparam derived_cache_config_t SCONFIG = get_derived_cache_params(CONFIG, CONFIG.DCACHE, CONFIG.DCACHE_ADDR); // 声明局部常量。
    localparam DB_ADDR_LEN = SCONFIG.LINE_ADDR_W + SCONFIG.SUB_LINE_ADDR_W; // 声明局部常量。

    cache_functions_interface # (.TAG_W(SCONFIG.TAG_W), .LINE_W(SCONFIG.LINE_ADDR_W), .SUB_LINE_W(SCONFIG.SUB_LINE_ADDR_W)) addr_utils ();

// 定义类型别名或枚举/结构类型。
    typedef logic[SCONFIG.TAG_W-1:0] tag_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[SCONFIG.LINE_ADDR_W-1:0] line_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[SCONFIG.SUB_LINE_ADDR_W-1:0] block_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic valid; // 声明信号、变量或生成变量。
        tag_t tag;
    } tb_entry_t;

// 定义类型别名或枚举/结构类型。
    typedef enum {
        WRITE,
        CBO,
        READ,
        AMO_LR,
        AMO_SC,
        AMO_RMW
    } req_type_t;
    req_type_t stage0_type;
    req_type_t stage1_type;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic[31:0] addr; // 声明信号、变量或生成变量。
        logic[31:0] wdata; // 声明信号、变量或生成变量。
        logic[3:0] be; // 声明信号、变量或生成变量。
        amo_t amo_type;
        logic uncacheable; // 声明信号、变量或生成变量。
    } req_t;
    req_t stage0;
    req_t stage1;
    logic stage1_valid; // 声明信号、变量或生成变量。
    logic stage1_done; // 声明信号、变量或生成变量。
    logic stage0_advance_r; // 声明信号、变量或生成变量。

    logic resetting; // 声明信号、变量或生成变量。

    ////////////////////////////////////////////////////
    //Implementation
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            stage0_advance_r <= 0;
            stage1_valid <= 0;
            stage1_type <= WRITE;
        end // 结束语句块。
        else begin // 执行否则分支。
            stage0_advance_r <= ls.new_request;
            if (ls.new_request) begin // 执行条件判断，满足条件时进入对应分支。
                stage1_valid <= 1;
                stage1_type <= stage0_type;
            end // 结束语句块。
            else if (stage1_done) // 执行否则如果分支的条件判断。
                stage1_valid <= 0;
        end // 结束语句块。
        if (ls.new_request) // 执行条件判断，满足条件时进入对应分支。
            stage1 <= stage0;
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (cbo) // 执行条件判断，满足条件时进入对应分支。
            stage0_type = CBO;
        else if (ls.we) // 执行否则如果分支的条件判断。
            stage0_type = WRITE;
        else if (amo & amo_type == AMO_LR_FN5) // 执行否则如果分支的条件判断。
            stage0_type = AMO_LR;
        else if (amo & amo_type == AMO_SC_FN5) // 执行否则如果分支的条件判断。
            stage0_type = AMO_SC;
        else if (amo) // 执行否则如果分支的条件判断。
            stage0_type = AMO_RMW;
        else // 执行否则分支。
            stage0_type = READ;
    end // 结束语句块。

    assign stage0 = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        addr : ls.addr,
        wdata : ls.data_in,
        be : ls.be,
        amo_type : amo_type,
        uncacheable : uncacheable
    };

    ////////////////////////////////////////////////////
    //Snooping
    //Invalidate a line in the tagbank upon a hit
    line_t snoop_line;
    tag_t snoop_tag;
    logic snoop_valid; // 声明信号、变量或生成变量。
    tb_entry_t[CONFIG.DCACHE.WAYS-1:0] snoop_rdata;
    line_t snoop_line_r;
    tag_t snoop_tag_r;
    logic[CONFIG.DCACHE.WAYS-1:0] snoop_hit; // 声明信号、变量或生成变量。
    logic snoop_write; // 声明信号、变量或生成变量。

    //Technically snoop addresses do not need to lie within our addressable space, so their tag should be wider
    //But this is a niche scenario and there is no harm in aliasing requests into our address space (beyond performance)

    assign {snoop_tag, snoop_line} = mem.inv_addr[2+SCONFIG.SUB_LINE_ADDR_W+:SCONFIG.TAG_W+SCONFIG.LINE_ADDR_W]; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            snoop_valid <= 0;
        else // 执行否则分支。
            snoop_valid <= mem.inv;
        snoop_line_r <= snoop_line;
        snoop_tag_r <= snoop_tag;
    end // 结束语句块。

    //Hit detection
    assign snoop_write = snoop_valid & |snoop_hit; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < CONFIG.DCACHE.WAYS; i++) // 执行循环或遍历。
            snoop_hit[i] = {snoop_rdata[i].valid, snoop_rdata[i].tag} == {1'b1, snoop_tag_r};
    end // 结束语句块。

    //Random replacement policy (cycler)
    logic[CONFIG.DCACHE.WAYS-1:0] replacement_way; // 声明信号、变量或生成变量。
    cycler #(.C_WIDTH(CONFIG.DCACHE.WAYS)) replacement_policy (
        .en(ls.new_request),
        .one_hot(replacement_way),
    .*);

    ////////////////////////////////////////////////////
    //Tagbank
    //Snoops are always accepted and cannot be delayed
    //Port A therefore handles all requests and snoop writes
    //Port B handles snoop reads + resets
    logic a_en; // 声明信号、变量或生成变量。
    logic[CONFIG.DCACHE.WAYS-1:0] a_wbe; // 声明信号、变量或生成变量。
    tb_entry_t a_wdata;
    line_t a_addr;
    tb_entry_t[CONFIG.DCACHE.WAYS-1:0] a_rdata;
    logic stage1_tb_write; // 声明信号、变量或生成变量。
    logic stage1_tb_wval; // 声明信号、变量或生成变量。
    logic stage1_tb_write_r; // 声明信号、变量或生成变量。
    logic inv_matches_stage1; // 声明信号、变量或生成变量。
    logic stage1_tb_wval_r; // 声明信号、变量或生成变量。
    logic[CONFIG.DCACHE.WAYS-1:0] hit_ohot_r; // 声明信号、变量或生成变量。

    assign a_en = snoop_write | stage1_tb_write_r | ls.new_request; // & ~inv_matches_stage1 )；执行连续赋值，把组合逻辑连接到目标信号。
    assign a_wbe = ({CONFIG.DCACHE.WAYS{snoop_write}} & snoop_hit) | ({CONFIG.DCACHE.WAYS{stage1_tb_write_r}} & (stage1_type == CBO | (stage1_type == AMO_RMW & hit_r) ? hit_ohot_r : replacement_way)); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (snoop_write) // 执行条件判断，满足条件时进入对应分支。
            a_addr = snoop_line_r;
        else if (stage1_tb_write_r) // 执行否则如果分支的条件判断。
            a_addr = stage1.addr[2+SCONFIG.SUB_LINE_ADDR_W+:SCONFIG.LINE_ADDR_W];
        else // 执行否则分支。
            a_addr = stage0.addr[2+SCONFIG.SUB_LINE_ADDR_W+:SCONFIG.LINE_ADDR_W];
    end // 结束语句块。

    assign a_wdata = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        valid : stage1_tb_write_r & stage1_tb_wval_r & ~inv_matches_stage1 ,
        tag : stage1.addr[2+SCONFIG.SUB_LINE_ADDR_W+SCONFIG.LINE_ADDR_W+:SCONFIG.TAG_W]
    };

    //Reset routine
    logic b_en; // 声明信号、变量或生成变量。
    logic[CONFIG.DCACHE.WAYS-1:0] b_wbe; // 声明信号、变量或生成变量。
    tb_entry_t b_wdata;
    line_t b_addr;
    logic rst_invalid; // 声明信号、变量或生成变量。
    line_t rst_line;
    assign resetting = ~rst_invalid; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign b_en = mem.inv | resetting; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign b_wbe = {CONFIG.DCACHE.WAYS{resetting}}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign b_wdata = '{default: '0}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign b_addr = resetting ? rst_line : snoop_line; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            rst_invalid <= 0;
            rst_line <= '0;
        end // 结束语句块。
        else if (resetting) // 执行否则如果分支的条件判断。
            {rst_invalid, rst_line} <= rst_line + 1;
    end // 结束语句块。

    tdp_ram #(
        .ADDR_WIDTH(SCONFIG.LINE_ADDR_W),
        .NUM_COL(CONFIG.DCACHE.WAYS),
        .COL_WIDTH($bits(tb_entry_t)),
        .PIPELINE_DEPTH(0),
        .USE_PRELOAD(0)
    ) tagbank (
        .a_en(a_en),
        .a_wbe(a_wbe),
        .a_wdata({CONFIG.DCACHE.WAYS{a_wdata}}),
        .a_addr(a_addr),
        .a_rdata(a_rdata),
        .b_en(b_en),
        .b_wbe(b_wbe),
        .b_wdata({CONFIG.DCACHE.WAYS{b_wdata}}),
        .b_addr(b_addr),
        .b_rdata(snoop_rdata),
    .*);

    //Hit detection
    logic hit; // 声明信号、变量或生成变量。
    logic hit_r; // 声明信号、变量或生成变量。
    logic[CONFIG.DCACHE.WAYS-1:0] hit_ohot; // 声明信号、变量或生成变量。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        hit_ohot = '0;
        for (int i = 0; i < CONFIG.DCACHE.WAYS; i++) // 执行循环或遍历。
            hit_ohot[i] = a_rdata[i].valid & (a_rdata[i].tag == stage1.addr[2+SCONFIG.SUB_LINE_ADDR_W+SCONFIG.LINE_ADDR_W+:SCONFIG.TAG_W]);
    end // 结束语句块。
    assign hit = |hit_ohot; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (stage0_advance_r) begin // 执行条件判断，满足条件时进入对应分支。
            hit_r <= hit;
            hit_ohot_r <= hit_ohot;
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Atomic read/modify/write state machine
    //Separate from other logic because atomic requests will need to be retried on a snoop invalidation
// 定义类型别名或枚举/结构类型。
    typedef enum {
        RMW_IDLE,
        RMW_READ,
        RMW_WRITE,
        RMW_FILLING
    } rmw_state_t;
    rmw_state_t current_state;
    rmw_state_t next_state;

    logic rmw_mem_request; // 声明信号、变量或生成变量。
    logic rmw_mem_rnw; // 声明信号、变量或生成变量。
    logic rmw_stage1_tb_write; // 声明信号、变量或生成变量。
    logic rmw_db_wen; // 声明信号、变量或生成变量。
    logic[31:0] rmw_db_wdata; // 声明信号、变量或生成变量。
    logic rmw_ls_data_valid; // 声明信号、变量或生成变量。
    logic rmw_stage1_done; // 声明信号、变量或生成变量。
    logic rmw_retry; // 声明信号、变量或生成变量。
    logic force_miss; // 声明信号、变量或生成变量。
    logic return_done; // 声明信号、变量或生成变量。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            current_state <= RMW_IDLE;
        else // 执行否则分支。
            current_state <= next_state;
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        unique case (current_state)
            RMW_READ : begin
                rmw_mem_request = 1;
                rmw_mem_rnw = 1;
                rmw_stage1_tb_write = mem.ack & ~stage1.uncacheable;
                rmw_db_wen = 0;
                rmw_db_wdata = 'x;
                rmw_ls_data_valid = 0;
                rmw_stage1_done = 0;
                next_state = mem.ack ? RMW_FILLING : RMW_READ;
            end // 结束语句块。
            RMW_WRITE : begin
                rmw_mem_request = ~rmw_retry;
                rmw_mem_rnw = 0;
                rmw_stage1_tb_write = 0;
                rmw_db_wen = ~stage1.uncacheable & mem.ack;
                rmw_db_wdata = amo_unit.rd;
                rmw_ls_data_valid = mem.ack;
                rmw_stage1_done = mem.ack;
                if (mem.ack) // 执行条件判断，满足条件时进入对应分支。
                    next_state = RMW_IDLE;
                else if (rmw_retry) // 执行否则如果分支的条件判断。
                    next_state = RMW_READ;
                else // 执行否则分支。
                    next_state = RMW_WRITE;
            end // 结束语句块。
            RMW_FILLING : begin
                rmw_mem_request = 0;
                rmw_mem_rnw = 'x;
                rmw_stage1_tb_write = 0;
                rmw_db_wen = mem.rvalid & ~stage1.uncacheable;
                rmw_db_wdata = mem.rdata;
                rmw_ls_data_valid = 0;
                rmw_stage1_done = 0;
                if (return_done) // 执行条件判断，满足条件时进入对应分支。
                    next_state = rmw_retry ? RMW_READ : RMW_WRITE;
                else // 执行否则分支。
                    next_state = RMW_FILLING;
            end // 结束语句块。
            RMW_IDLE : begin
                rmw_mem_request = 0;
                rmw_mem_rnw = 'x;
                rmw_stage1_tb_write = 0;
                rmw_db_wen = 0;
                rmw_db_wdata = 'x;
                rmw_ls_data_valid = 0;
                rmw_stage1_done = 0;
                if (stage1_valid & stage1_type == AMO_RMW) // 执行条件判断，满足条件时进入对应分支。
                    next_state = hit & ~force_miss & ~stage1.uncacheable ? RMW_WRITE : RMW_READ;
                else // 执行否则分支。
                    next_state = RMW_IDLE;
            end // 结束语句块。
        endcase // 结束多分支选择。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Supporting logic
    //Various piece of additional stateful logic supporting stage one requests

    //Tagbank write logic; always on ack_r because it is guaranteed that there won't be a conflicting snoop tb write
    logic ack_r; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        ack_r <= mem.ack;
        stage1_tb_write_r <= stage1_tb_write;
        stage1_tb_wval_r <= stage1_tb_wval;
    end // 结束语句块。

    //Track if a request has been sent in stage 1 to prevent duplicates
    logic request_sent; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst | stage1_done) // 执行条件判断，满足条件时进入对应分支。
            request_sent <= 0;
        else if (mem.ack) // 执行否则如果分支的条件判断。
            request_sent <= 1;
    end // 结束语句块。

    //Atomics that collide with a snoop on stage0 must be treated as a miss
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (ls.new_request) // 执行条件判断，满足条件时进入对应分支。
            force_miss <= amo & mem.inv & mem.inv_addr[31:2+SCONFIG.SUB_LINE_ADDR_W] == stage0.addr[31:2+SCONFIG.SUB_LINE_ADDR_W];
    end // 结束语句块。

    //RMW requests must be retried if invalidated after the read but before the write
    assign inv_matches_stage1 = mem.inv & stage1.addr[31:2+SCONFIG.SUB_LINE_ADDR_W] == mem.inv_addr[31:2+SCONFIG.SUB_LINE_ADDR_W]; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        case (current_state) // 开始多分支选择，根据表达式选择对应分支。
            RMW_IDLE, RMW_FILLING, RMW_WRITE : rmw_retry <= stage1_valid & stage1_type == AMO_RMW & (rmw_retry | inv_matches_stage1);
            default: rmw_retry <= 0; // 执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

    //Fill burst word counting
    logic correct_word; // 声明信号、变量或生成变量。
    block_t word_counter;
    assign return_done = mem.rvalid & (stage1.uncacheable | word_counter == SCONFIG.SUB_LINE_ADDR_W'(CONFIG.DCACHE.LINE_W-1)); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign correct_word = mem.rvalid & (stage1.uncacheable | word_counter == stage1.addr[2+:SCONFIG.SUB_LINE_ADDR_W]); // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst | stage1_done) // 执行条件判断，满足条件时进入对应分支。
            word_counter <= '0;
        else // 执行否则分支。
            word_counter <= word_counter + block_t'(mem.rvalid);
    end // 结束语句块。


    ////////////////////////////////////////////////////
    //Stage 1 request handling
    //Heavily dependent on request type
    logic db_wen; // 声明信号、变量或生成变量。
    logic[CONFIG.DCACHE.WAYS-1:0] db_way; // 声明信号、变量或生成变量。
    logic[31:0] db_wdata; // 声明信号、变量或生成变量。
    logic lr_valid; // 声明信号、变量或生成变量。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        unique case (stage1_type)
            WRITE : begin
                mem.request = stage1_valid;
                mem.wdata = stage1.wdata;
                mem.rnw = 0;
                mem.rmw = 0;
                stage1_tb_write = 0;
                stage1_tb_wval = 'x;
                db_wen = stage0_advance_r & hit & ~stage1.uncacheable;
                db_wdata = stage1.wdata;
                db_way = hit_ohot;
                ls.data_valid = 0;
                ls.data_out = 'x;
                stage1_done = mem.ack;
            end // 结束语句块。
            CBO : begin
                mem.request = stage1_valid & ~request_sent;
                mem.wdata = 'x;
                mem.rnw = 0;
                mem.rmw = 0;
                stage1_tb_write = ~stage1.uncacheable & mem.ack & (stage0_advance_r ? hit : hit_r);
                stage1_tb_wval = 0;
                db_wen = 0;
                db_wdata = 'x;
                db_way = 'x;
                ls.data_valid = 0;
                ls.data_out = 'x;
                stage1_done = request_sent & ~stage1_tb_write_r;
            end // 结束语句块。
            AMO_LR, READ : begin
                mem.request = stage1_valid & ~stage0_advance_r & (stage1.uncacheable | ~hit_r) & ~request_sent;
                mem.wdata = 'x;
                mem.rnw = 1;
                mem.rmw = 0;
                stage1_tb_write = ~stage1.uncacheable & mem.ack;
                stage1_tb_wval = 1;
                db_wen = mem.rvalid & ~stage1.uncacheable;
                db_wdata = mem.rdata;
                db_way = replacement_way;
                ls.data_valid = stage0_advance_r ? hit & ~stage1.uncacheable : correct_word;
                ls.data_out = stage0_advance_r ? db_hit_entry : mem.rdata;
                stage1_done = stage0_advance_r ? hit & ~stage1.uncacheable : return_done;
            end // 结束语句块。
            AMO_SC : begin
                mem.request = stage1_valid & lr_valid;
                mem.wdata = stage1.wdata;
                mem.rnw = 0;
                mem.rmw = 0;
                stage1_tb_write = 0;
                stage1_tb_wval = 'x;
                db_wen = ~stage1.uncacheable & mem.ack;
                db_wdata = stage1.wdata;
                db_way = stage0_advance_r ? hit_ohot : hit_ohot_r;
                ls.data_valid = stage1_valid & (mem.ack | ~lr_valid);
                ls.data_out = {31'b0, ~lr_valid};
                stage1_done = stage1_valid & (mem.ack | ~lr_valid);
            end // 结束语句块。
            AMO_RMW : begin
                mem.request = rmw_mem_request;
                mem.wdata = amo_unit.rd;
                mem.rnw = rmw_mem_rnw;
                mem.rmw = 1;
                stage1_tb_write = rmw_stage1_tb_write;
                stage1_tb_wval = 1;
                db_wen = rmw_db_wen;
                db_wdata = rmw_db_wdata;
                db_way = hit_r ? hit_ohot_r : replacement_way; //Will not write on first cycle so can use registered
                ls.data_valid = rmw_ls_data_valid;
                ls.data_out = amo_unit.rs1;
                stage1_done = rmw_stage1_done;
            end // 结束语句块。
        endcase // 结束多分支选择。
    end // 结束语句块。

    assign mem.addr = stage1.addr[31:2]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.wbe = stage1.be; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.rlen = stage1.uncacheable ? '0 : 5'(CONFIG.DCACHE.LINE_W-1); // 执行连续赋值，把组合逻辑连接到目标信号。
    
    logic[DB_ADDR_LEN-1:0] db_addr; // 声明信号、变量或生成变量。
    assign ls.ready = ~resetting & ~snoop_write & (~stage1_valid | stage1_done) & ~(db_wen & load_peek & load_addr_peek[31:DB_ADDR_LEN+2] == stage1.addr[31:DB_ADDR_LEN+2] & load_addr_peek[2+:DB_ADDR_LEN] == db_addr); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign write_outstanding = (stage1_valid & ~(stage1_type inside {READ, AMO_LR})) | mem.write_outstanding; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Atomics
    logic local_reservation_valid; // 声明信号、变量或生成变量。
    //local_reservation_valid is with respect to invalidations, the amo.reservation_valid is for other ports
    assign lr_valid = amo_unit.reservation_valid & local_reservation_valid; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst | inv_matches_stage1) // 执行条件判断，满足条件时进入对应分支。
            local_reservation_valid <= 0;
        else if (amo_unit.set_reservation) // 执行否则如果分支的条件判断。
            local_reservation_valid <= 1;
    end // 结束语句块。

    assign amo_unit.reservation = stage1.addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    //On a miss, set on ack_r
    //On a hit, set as long as ~force_miss & ~inv_matches_stage1
    assign amo_unit.set_reservation = stage1_valid & stage1_type == AMO_LR & (stage0_advance_r & hit & ~stage1.uncacheable & ~force_miss & ~inv_matches_stage1 | ack_r); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.clear_reservation = stage1_done & stage1_type != AMO_LR; // 执行连续赋值，把组合逻辑连接到目标信号。

    //RMW
    assign amo_unit.rs2 = stage1.wdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.rmw_valid = stage1_valid & stage1_type == AMO_RMW; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.op = stage1.amo_type; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (stage0_advance_r) // 执行条件判断，满足条件时进入对应分支。
            amo_unit.rs1 <= db_hit_entry;
        else if (correct_word) // 执行否则如果分支的条件判断。
            amo_unit.rs1 <= mem.rdata;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Databank
    logic[CONFIG.DCACHE.WAYS-1:0][31:0] db_entries; // 声明信号、变量或生成变量。
    logic[31:0] db_hit_entry; // 声明信号、变量或生成变量。
    logic[CONFIG.DCACHE.WAYS-1:0][3:0] db_wbe_full; // 声明信号、变量或生成变量。
    logic[$clog2(CONFIG.DCACHE.WAYS > 1 ? CONFIG.DCACHE.WAYS : 2)-1:0] hit_int; // 声明信号、变量或生成变量。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < CONFIG.DCACHE.WAYS; i++) // 执行循环或遍历。
            db_wbe_full[i] = {4{db_way[i]}} & stage1.be;
    end // 结束语句块。

    assign db_addr[SCONFIG.SUB_LINE_ADDR_W+:SCONFIG.LINE_ADDR_W] = stage1.addr[2+SCONFIG.SUB_LINE_ADDR_W+:SCONFIG.LINE_ADDR_W]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign db_addr[SCONFIG.SUB_LINE_ADDR_W-1:0] = mem.rvalid ? word_counter : stage1.addr[2+:SCONFIG.SUB_LINE_ADDR_W]; // 执行连续赋值，把组合逻辑连接到目标信号。

    sdp_ram #(
        .ADDR_WIDTH(DB_ADDR_LEN),
        .NUM_COL(4*CONFIG.DCACHE.WAYS),
        .COL_WIDTH(8),
        .PIPELINE_DEPTH(0)
    ) databank (
        .a_en(db_wen),
        .a_wbe(db_wbe_full),
        .a_wdata({CONFIG.DCACHE.WAYS{db_wdata}}),
        .a_addr(db_addr),
        .b_en(ls.new_request),
        .b_addr(addr_utils.getDataLineAddr(stage0.addr)),
        .b_rdata(db_entries),
    .*);

    one_hot_to_integer #(.C_WIDTH(CONFIG.DCACHE.WAYS)) hit_conv (
        .one_hot(hit_ohot),
        .int_out(hit_int)
    );
    assign db_hit_entry = db_entries[hit_int]; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Assertions
    dcache_request_when_not_ready_assertion:
        assert property (@(posedge clk) disable iff (rst) ls.new_request |-> ls.ready) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("dcache received request when not ready"); // 执行否则分支。

    dcache_spurious_l1_ack_assertion:
        assert property (@(posedge clk) disable iff (rst) mem.ack |-> mem.request) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("dcache received ack without a request"); // 执行否则分支。

    // dcache_ohot_assertion:
    //     assert property (@(posedge clk) disable iff (rst) ls.new_request |=> $onehot0(hit_ohot))
    //     else $error("dcache hit multiple ways");

endmodule // 结束模块定义。
