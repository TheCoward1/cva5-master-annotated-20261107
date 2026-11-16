// ============================================================================
// 文件：core/execution_units/load_store_unit/dcache_noinv.sv
// 类型：module
// 名称：dcache_noinv
// 作用：实现不带外部失效接口的写回数据缓存。
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

module dcache_noinv // 定义 dcache_noinv 模块。

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
    typedef struct packed {
        logic valid; // 声明信号、变量或生成变量。
        tag_t tag;
    } tb_entry_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic[31:0] addr; // 声明信号、变量或生成变量。
        logic[31:0] data; // 声明信号、变量或生成变量。
        logic[3:0] be; // 声明信号、变量或生成变量。
        logic rnw; // 声明信号、变量或生成变量。
        logic uncacheable; // 声明信号、变量或生成变量。
        logic amo; // 声明信号、变量或生成变量。
        amo_t amo_type;
        logic cbo; // 声明信号、变量或生成变量。
    } req_t;

// 定义类型别名或枚举/结构类型。
    typedef enum {
        IDLE,
        FIRST_CYCLE,
        REQUESTING_READ,
        FILLING,
        UNCACHEABLE_WAITING_READ,
        AMO_WRITE
    } stage1_t;

    //Implementation
    req_t stage0;
    req_t stage1;
    logic stage1_done; // 声明信号、变量或生成变量。
    logic stage0_advance_r; // 声明信号、变量或生成变量。
    stage1_t current_state;
    logic[DB_ADDR_LEN-1:0] db_addr; // 声明信号、变量或生成变量。
    logic db_wen; // 声明信号、变量或生成变量。
    logic stage1_is_lr; // 声明信号、变量或生成变量。
    logic stage1_is_sc; // 声明信号、变量或生成变量。

    assign write_outstanding = ((current_state != IDLE) & (~stage1.rnw | stage1.amo)) | mem.write_outstanding; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Peeking avoids circular logic
    assign ls.ready = (current_state == IDLE) | (stage1_done & ~stage1.cbo & ~(db_wen & load_peek & load_addr_peek[31:DB_ADDR_LEN+2] == stage1.addr[31:DB_ADDR_LEN+2] & load_addr_peek[2+:DB_ADDR_LEN] == db_addr)); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            stage0_advance_r <= 0;
        else // 执行否则分支。
            stage0_advance_r <= ls.new_request;
        if (ls.new_request) // 执行条件判断，满足条件时进入对应分支。
            stage1 <= stage0;
    end // 结束语句块。

    assign stage0 = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        addr : ls.addr,
        data : ls.data_in,
        be : ls.be,
        rnw : ls.re,
        uncacheable : uncacheable,
        amo : amo,
        amo_type : amo_type,
        cbo : cbo
    };
    
    //Replacement policy
    logic[CONFIG.DCACHE.WAYS-1:0] replacement_way; // 声明信号、变量或生成变量。
    cycler #(.C_WIDTH(CONFIG.DCACHE.WAYS)) replacement_policy (
        .en(ls.new_request),
        .one_hot(replacement_way),
    .*);

    //Tagbank
    tb_entry_t[CONFIG.DCACHE.WAYS-1:0] tb_entries;
    tb_entry_t new_entry;
    logic[CONFIG.DCACHE.WAYS-1:0] hit_ohot; // 声明信号、变量或生成变量。
    logic[CONFIG.DCACHE.WAYS-1:0] hit_ohot_r; // 声明信号、变量或生成变量。
    logic hit; // 声明信号、变量或生成变量。
    logic hit_r; // 声明信号、变量或生成变量。
    logic tb_write; // 声明信号、变量或生成变量。

    assign tb_write = stage0_advance_r & ~stage1.uncacheable & ((~hit & stage1.rnw & ~stage1_is_sc) | (stage1.cbo & hit)); // 执行连续赋值，把组合逻辑连接到目标信号。

    assign new_entry = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        valid : ~stage1.cbo,
        tag : addr_utils.getTag(stage1.addr)
    };

    sdp_ram_padded #(
        .ADDR_WIDTH(SCONFIG.LINE_ADDR_W),
        .NUM_COL(CONFIG.DCACHE.WAYS),
        .COL_WIDTH($bits(tb_entry_t)),
        .PIPELINE_DEPTH(0)
    ) tagbank (
        .a_en(tb_write),
        .a_wbe(replacement_way),
        .a_wdata({CONFIG.DCACHE.WAYS{new_entry}}),
        .a_addr(addr_utils.getTagLineAddr(stage1.addr)),
        .b_en(ls.new_request),
        .b_addr(addr_utils.getTagLineAddr(stage0.addr)),
        .b_rdata(tb_entries),
    .*);

    //Hit detection
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        hit_ohot = '0;
        for (int i = 0; i < CONFIG.DCACHE.WAYS; i++) // 执行循环或遍历。
            hit_ohot[i] = tb_entries[i].valid & (tb_entries[i].tag == addr_utils.getTag(stage1.addr));
    end // 结束语句块。
    assign hit = |hit_ohot; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (stage0_advance_r) begin // 执行条件判断，满足条件时进入对应分支。
            hit_r <= hit;
            hit_ohot_r <= hit_ohot;
        end // 结束语句块。
    end // 结束语句块。

    //Databank
    logic[CONFIG.DCACHE.WAYS-1:0][31:0] db_entries; // 声明信号、变量或生成变量。
    logic[31:0] db_hit_entry; // 声明信号、变量或生成变量。
    logic[$clog2(CONFIG.DCACHE.WAYS > 1 ? CONFIG.DCACHE.WAYS : 2)-1:0] hit_int; // 声明信号、变量或生成变量。
    logic[CONFIG.DCACHE.WAYS-1:0] db_way; // 声明信号、变量或生成变量。
    logic[CONFIG.DCACHE.WAYS-1:0][3:0] db_wbe_full; // 声明信号、变量或生成变量。
    logic[31:0] db_wdata; // 声明信号、变量或生成变量。
    logic[SCONFIG.SUB_LINE_ADDR_W-1:0] word_counter; // 声明信号、变量或生成变量。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < CONFIG.DCACHE.WAYS; i++) // 执行循环或遍历。
            db_wbe_full[i] = {4{db_way[i]}} & stage1.be;
    end // 结束语句块。

    assign db_addr = current_state == FILLING ? {addr_utils.getTagLineAddr(stage1.addr), word_counter} : addr_utils.getDataLineAddr(stage1.addr); // 执行连续赋值，把组合逻辑连接到目标信号。

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

    //Arbiter response
    logic correct_word; // 声明信号、变量或生成变量。
    logic return_done; // 声明信号、变量或生成变量。
    assign return_done = mem.rvalid & word_counter == SCONFIG.SUB_LINE_ADDR_W'(CONFIG.DCACHE.LINE_W-1); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign correct_word = mem.rvalid & word_counter == stage1.addr[2+:SCONFIG.SUB_LINE_ADDR_W]; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (mem.rvalid) // 执行条件判断，满足条件时进入对应分支。
            word_counter <= word_counter+1;
        if (ls.new_request) // 执行条件判断，满足条件时进入对应分支。
            word_counter <= 0;
    end // 结束语句块。

    stage1_t next_state;
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            current_state <= IDLE;
        else // 执行否则分支。
            current_state <= next_state;
    end // 结束语句块。

    //Have to pull this into its own block to prevent a verilator circular dependency
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        unique case (current_state)
            IDLE : stage1_done = 0;
            FIRST_CYCLE : stage1_done = ((~stage1.rnw | (stage1_is_sc & amo_unit.reservation_valid)) & mem.ack) | (stage1_is_sc & ~amo_unit.reservation_valid) | (stage1.rnw & hit & (~stage1.amo | stage1_is_lr) & ~stage1.uncacheable) | stage1.cbo;
            REQUESTING_READ : stage1_done = 0;
            FILLING : stage1_done = return_done & (stage1_is_lr | ~stage1.amo);
            UNCACHEABLE_WAITING_READ : stage1_done = mem.rvalid & (stage1_is_lr | ~stage1.amo);
            AMO_WRITE : stage1_done = mem.ack;
        endcase // 结束多分支选择。
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        unique case (current_state)
            IDLE : begin
                mem.request = 0;
                mem.wdata = 'x;
                mem.rnw = 'x;
                mem.rlen = 'x;
                db_wen = 0;
                db_wdata = 'x;
                db_way = 'x;
                ls.data_valid = 0;
                ls.data_out = 'x;
                next_state = ls.new_request ? FIRST_CYCLE : IDLE;
            end // 结束语句块。
            FIRST_CYCLE : begin //Handles writes, read hits, uncacheable reads, and SC
                mem.request = ~stage1.cbo & (~stage1.rnw | (stage1.uncacheable & ~stage1_is_sc) | (stage1_is_sc & amo_unit.reservation_valid));
                mem.wdata = stage1.data;
                mem.rnw = stage1.rnw & ~stage1_is_sc;
                mem.rlen = '0;
                db_wen = ~stage1.cbo & hit & ~stage1.uncacheable & (~stage1.rnw | (stage1_is_sc & amo_unit.reservation_valid));
                db_wdata = stage1.data;
                db_way = hit_ohot;
                ls.data_valid = (stage0_advance_r & stage1_is_sc) | (stage1.rnw & ~stage1.uncacheable & hit & ~stage1_is_sc);
                ls.data_out = stage1_is_sc ? {31'b0, ~amo_unit.reservation_valid} : db_hit_entry;
                if (stage1_done) // 执行条件判断，满足条件时进入对应分支。
                    next_state = ls.new_request ? FIRST_CYCLE : IDLE;
                else if (stage1.uncacheable & mem.ack) // 执行否则如果分支的条件判断。
                    next_state = UNCACHEABLE_WAITING_READ;
                else if (stage1.rnw & ~stage1.uncacheable & ~hit & ~stage1_is_sc) // 执行否则如果分支的条件判断。
                    next_state = REQUESTING_READ;
                else if (stage1.amo & hit & ~stage1.uncacheable & ~stage1_is_sc) // 执行否则如果分支的条件判断。
                    next_state = AMO_WRITE;
                else // 执行否则分支。
                    next_state = FIRST_CYCLE;
            end // 结束语句块。
            REQUESTING_READ : begin
                mem.request = 1;
                mem.wdata = 'x;
                mem.rnw = 1;
                mem.rlen = 5'(CONFIG.DCACHE.LINE_W-1);
                db_wen = 0;
                db_wdata = 'x;
                db_way = 'x;
                ls.data_valid = 0;
                ls.data_out = 'x;
                next_state = mem.ack ? FILLING : REQUESTING_READ;
            end // 结束语句块。
            FILLING : begin
                mem.request = 0;
                mem.wdata = 'x;
                mem.rnw = 'x;
                mem.rlen = 'x;
                db_wen = mem.rvalid;
                db_wdata = mem.rdata;
                db_way = replacement_way;
                ls.data_valid = correct_word;
                ls.data_out = mem.rdata;
                if (return_done) begin // 执行条件判断，满足条件时进入对应分支。
                    if (stage1.amo & ~stage1_is_lr) // 执行条件判断，满足条件时进入对应分支。
                        next_state = AMO_WRITE;
                    else // 执行否则分支。
                        next_state = ls.new_request ? FIRST_CYCLE : IDLE;
                end // 结束语句块。
                else // 执行否则分支。
                    next_state = FILLING;
            end // 结束语句块。
            UNCACHEABLE_WAITING_READ : begin
                mem.request = 0;
                mem.wdata = 'x;
                mem.rnw = 'x;
                mem.rlen = 'x;
                db_wen = 0;
                db_wdata = 'x;
                db_way = 'x;
                ls.data_valid = mem.rvalid;
                ls.data_out = mem.rdata;
                if (mem.rvalid) begin // 执行条件判断，满足条件时进入对应分支。
                    if (stage1.amo & ~stage1_is_lr) // 执行条件判断，满足条件时进入对应分支。
                        next_state = AMO_WRITE;
                    else // 执行否则分支。
                        next_state = ls.new_request ? FIRST_CYCLE : IDLE;
                end // 结束语句块。
                else // 执行否则分支。
                    next_state = UNCACHEABLE_WAITING_READ;
            end // 结束语句块。
            AMO_WRITE : begin
                mem.request = 1;
                mem.wdata = amo_unit.rd;
                mem.rnw = 0;
                mem.rlen = 'x;
                db_wen = ~stage1.uncacheable;
                db_wdata = amo_unit.rd;
                db_way = hit_r ? hit_ohot_r : replacement_way;
                ls.data_valid = 0;
                ls.data_out = 'x;
                if (mem.ack) // 执行条件判断，满足条件时进入对应分支。
                    next_state = ls.new_request ? FIRST_CYCLE : IDLE;
                else // 执行否则分支。
                    next_state = AMO_WRITE;
            end // 结束语句块。
        endcase // 结束多分支选择。
    end // 结束语句块。

    //AMO
    assign stage1_is_lr = stage1.amo & stage1.amo_type == AMO_LR_FN5; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign stage1_is_sc = stage1.amo & stage1.amo_type == AMO_SC_FN5; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign amo_unit.reservation = stage1.addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.rs2 = stage1.data; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.rmw_valid = (current_state != IDLE) & stage1.amo; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.op = stage1.amo_type; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.set_reservation = stage1_is_lr & stage1_done; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign amo_unit.clear_reservation = stage1_done; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (stage0_advance_r) // 执行条件判断，满足条件时进入对应分支。
            amo_unit.rs1 <= db_hit_entry;
        else if (correct_word | (mem.rvalid & stage1.uncacheable)) // 执行否则如果分支的条件判断。
            amo_unit.rs1 <= mem.rdata;
    end // 结束语句块。

    assign mem.addr = stage1.addr[31:2]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.wbe = stage1.be; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.rmw = 0; //Although this unit can issue RMWs, they do not need special treatment as they are not coherent with other units；执行连续赋值，把组合逻辑连接到目标信号。

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
