// ============================================================================
// 文件：test_benches/verilator/cva5_sim.sv
// 类型：module
// 名称：cva5_sim
// 作用：Verilator 顶层测试平台，连接 CVA5、本地存储器、AXI、UART 和退休跟踪。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017 Eric Matthews, Chris Keilbart, Lesley Shannon
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
 */

module cva5_sim // 定义 cva5_sim 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        //DDR AXI
        output logic [31:0]ddr_axi_araddr, // 声明输出端口。
        output logic [1:0]ddr_axi_arburst, // 声明输出端口。
        output logic [3:0]ddr_axi_arcache, // 声明输出端口。
        output logic [5:0]ddr_axi_arid, // 声明输出端口。
        output logic [7:0]ddr_axi_arlen, // 声明输出端口。
        output logic [0:0]ddr_axi_arlock, // 声明输出端口。
        output logic [2:0]ddr_axi_arprot, // 声明输出端口。
        output logic [3:0]ddr_axi_arqos, // 声明输出端口。
        input logic ddr_axi_arready, // 声明输入端口。
        output logic [3:0]ddr_axi_arregion, // 声明输出端口。
        output logic [2:0]ddr_axi_arsize, // 声明输出端口。
        output logic ddr_axi_arvalid, // 声明输出端口。
        output logic [31:0]ddr_axi_awaddr, // 声明输出端口。
        output logic [1:0]ddr_axi_awburst, // 声明输出端口。
        output logic [3:0]ddr_axi_awcache, // 声明输出端口。
        output logic [5:0]ddr_axi_awid, // 声明输出端口。
        output logic [7:0]ddr_axi_awlen, // 声明输出端口。
        output logic [0:0]ddr_axi_awlock, // 声明输出端口。
        output logic [2:0]ddr_axi_awprot, // 声明输出端口。
        output logic [3:0]ddr_axi_awqos, // 声明输出端口。
        input logic ddr_axi_awready, // 声明输入端口。
        output logic [3:0]ddr_axi_awregion, // 声明输出端口。
        output logic [2:0]ddr_axi_awsize, // 声明输出端口。
        output logic ddr_axi_awvalid, // 声明输出端口。
        output logic [5:0]ddr_axi_bid, // 声明输出端口。
        output logic ddr_axi_bready, // 声明输出端口。
        input logic [1:0]ddr_axi_bresp, // 声明输入端口。
        input logic ddr_axi_bvalid, // 声明输入端口。
        input logic [31:0]ddr_axi_rdata, // 声明输入端口。
        input logic [5:0]ddr_axi_rid, // 声明输入端口。
        input logic ddr_axi_rlast, // 声明输入端口。
        output logic ddr_axi_rready, // 声明输出端口。
        input logic [1:0]ddr_axi_rresp, // 声明输入端口。
        input logic ddr_axi_rvalid, // 声明输入端口。
        output logic [31:0]ddr_axi_wdata, // 声明输出端口。
        output logic ddr_axi_wlast, // 声明输出端口。
        input logic ddr_axi_wready, // 声明输入端口。
        output logic [3:0]ddr_axi_wstrb, // 声明输出端口。
        output logic ddr_axi_wvalid, // 声明输出端口。
        output logic [5:0]ddr_axi_wid, // 声明输出端口。

        //Local Memory
        output logic [29:0] instruction_bram_addr, // 声明输出端口。
        output logic instruction_bram_en, // 声明输出端口。
        output logic [3:0] instruction_bram_be, // 声明输出端口。
        output logic [31:0] instruction_bram_data_in, // 声明输出端口。
        input logic [31:0] instruction_bram_data_out, // 声明输入端口。

        output logic [29:0] data_bram_addr, // 声明输出端口。
        output logic data_bram_en, // 声明输出端口。
        output logic [3:0] data_bram_be, // 声明输出端口。
        output logic [31:0] data_bram_data_in, // 声明输出端口。
        input logic [31:0] data_bram_data_out, // 声明输入端口。

        //Used by verilator
        output logic write_uart, // 声明输出端口。
        output logic [7:0] uart_byte, // 声明输出端口。

        //Trace Interface
        output integer NUM_RETIRE_PORTS, // 声明输出端口。
        output logic [31:0] retire_ports_instruction [RETIRE_PORTS], // 声明输出端口。
        output logic [31:0] retire_ports_pc [RETIRE_PORTS], // 声明输出端口。
        output logic retire_ports_valid [RETIRE_PORTS], // 声明输出端口。
        output logic store_queue_empty // 声明输出端口。
    );

    //Peripheral busses
    local_memory_interface instruction_bram();
    local_memory_interface data_bram();
    axi_interface m_axi();
    avalon_interface m_avalon();
    wishbone_interface dwishbone();
    wishbone_interface iwishbone();

    //Primary memory busses
    axi_interface axi();
    mem_interface mem[0:0]();

    //Additional CPU signals
    interrupt_t s_interrupt;
    interrupt_t m_interrupt;
    logic[63:0] mtime; // 声明信号、变量或生成变量。

    ////////////////////////////////////////////////////
    //CPU instantiation and mapping
    cva5 #(.CONFIG(EXAMPLE_CONFIG)) cpu(.mem(mem[0]), .*);
    axi_adapter #(.NUM_CORES(1)) arb(.mems(mem), .axi(axi), .*);

    //Local memory port mapping
    assign instruction_bram_addr = instruction_bram.addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign instruction_bram_en = instruction_bram.en; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign instruction_bram_be = instruction_bram.be; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign instruction_bram_data_in = instruction_bram.data_in; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign instruction_bram.data_out = instruction_bram_data_out; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign data_bram_addr = data_bram.addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign data_bram_en = data_bram.en; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign data_bram_be = data_bram.be; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign data_bram_data_in = data_bram.data_in; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign data_bram.data_out = data_bram_data_out; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Main memory port mapping
    assign ddr_axi_araddr = axi.araddr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_arburst = axi.arburst; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_arcache = axi.arcache; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_arid = axi.arid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_arlen = axi.arlen; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.arready = ddr_axi_arready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_arsize = axi.arsize; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_arvalid = axi.arvalid; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign ddr_axi_awaddr = axi.awaddr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_awburst = axi.awburst; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_awcache = axi.awcache; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_awid = axi.awid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_awlen =  axi.awlen; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.awready = ddr_axi_awready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_awvalid = axi.awvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    assign axi.bid = ddr_axi_bid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_bready = axi.bready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.bresp = ddr_axi_bresp; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.bvalid = ddr_axi_bvalid; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign axi.rdata = ddr_axi_rdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.rid = ddr_axi_rid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.rlast = ddr_axi_rlast; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_rready = axi.rready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.rresp = ddr_axi_rresp; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.rvalid = ddr_axi_rvalid; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign ddr_axi_wdata = axi.wdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_wlast = axi.wlast; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign axi.wready = ddr_axi_wready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_wstrb = axi.wstrb; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ddr_axi_wvalid = axi.wvalid; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Other CPU signals
    assign s_interrupt = '{default: 0}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_interrupt = '{default: 0}; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mtime <= '0;
        else // 执行否则分支。
            mtime <= mtime + 1;
    end // 结束语句块。

    //Simulate a UART on the peripheral AXI bus
    //Write channels
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            m_axi.awready <= 1;
            m_axi.wready <= 0;
            m_axi.bvalid <= 0;
            write_uart <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            write_uart <= 0;
            if (m_axi.awvalid & m_axi.awready) begin // 执行条件判断，满足条件时进入对应分支。
                m_axi.awready <= 0;
                m_axi.wready <= 1;
            end // 结束语句块。
            else if (m_axi.wvalid & m_axi.wready) begin // 执行否则如果分支的条件判断。
                m_axi.wready <= 0;
                m_axi.bvalid <= 1;
                write_uart <= 1;
            end // 结束语句块。
            else if (m_axi.bvalid & m_axi.bready) begin // 执行否则如果分支的条件判断。
                m_axi.bvalid <= 0;
                m_axi.awready <= 1;
            end // 结束语句块。
        end // 结束语句块。
        uart_byte <= m_axi.wdata[7:0];
    end // 结束语句块。

    //Read channels
    assign m_axi.rdata = 32'hFFFFFF21; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            m_axi.arready <= 1;
            m_axi.rvalid <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            if (m_axi.arvalid & m_axi.arready) begin // 执行条件判断，满足条件时进入对应分支。
                m_axi.arready <= 0;
                m_axi.rvalid <= 1;
            end // 结束语句块。
            else if (m_axi.rvalid & m_axi.rready) begin // 执行否则如果分支的条件判断。
                m_axi.rvalid <= 0;
                m_axi.arready <= 1;
            end // 结束语句块。
        end // 结束语句块。
    end // 结束语句块。


    ////////////////////////////////////////////////////
    //Trace Interface
    localparam BENCHMARK_START_COLLECTION_NOP = 32'h00C00013; // 声明局部常量。
    localparam BENCHMARK_END_COLLECTION_NOP = 32'h00D00013; // 声明局部常量。

    logic start_collection; // 声明信号、变量或生成变量。
    logic end_collection; // 声明信号、变量或生成变量。

    //NOP detection
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        start_collection = 0;
        end_collection = 0;
        foreach(retire_ports_valid[i]) begin // 执行循环或遍历。
            start_collection |= retire_ports_valid[i] & (retire_ports_instruction[i] == BENCHMARK_START_COLLECTION_NOP);
            end_collection |= retire_ports_valid[i] & (retire_ports_instruction[i] == BENCHMARK_END_COLLECTION_NOP);
        end // 结束语句块。
    end // 结束语句块。

    //Hierarchy paths for major components 
// 定义编译期宏。
    `define FETCH_P cpu.fetch_block
// 定义编译期宏。
    `define ICACHE_P cpu.fetch_block.gen_fetch_icache.i_cache
// 定义编译期宏。
    `define BRANCH_P cpu.branch_unit_block
// 定义编译期宏。
    `define ISSUE_P cpu.decode_and_issue_block
// 定义编译期宏。
    `define RENAME_P cpu.renamer_block
// 定义编译期宏。
    `define METADATA_P cpu.id_block
// 定义编译期宏。
    `define LS_P cpu.load_store_unit_block
// 定义编译期宏。
    `define DIV_P cpu.gen_div.div_unit_block
// 定义编译期宏。
    `define LSQ_P cpu.load_store_unit_block.lsq_block
// 定义编译期宏。
    `define DCACHE_P cpu.load_store_unit_block.gen_ls_dcache.data_cache

    stats_t stats_enum;
    instruction_mix_stats_t instruction_mix_enum;
    localparam NUM_STATS = stats_enum.num(); // 声明局部常量。
    localparam NUM_INSTRUCTION_MIX_STATS = instruction_mix_enum.num(); // 声明局部常量。

    logic stats [NUM_STATS]; // 声明信号、变量或生成变量。
    logic is_mul [RETIRE_PORTS]; // 声明信号、变量或生成变量。
    logic is_div [RETIRE_PORTS]; // 声明信号、变量或生成变量。
    logic [NUM_INSTRUCTION_MIX_STATS-1:0] instruction_mix_stats [RETIRE_PORTS]; // 声明信号、变量或生成变量。

    logic icache_hit; // 声明信号、变量或生成变量。
    logic icache_miss; // 声明信号、变量或生成变量。
    logic iarb_stall; // 声明信号、变量或生成变量。
    logic dcache_hit; // 声明信号、变量或生成变量。
    logic dcache_miss; // 声明信号、变量或生成变量。
    logic darb_stall; // 声明信号、变量或生成变量。

    //Issue stalls
    logic base_no_instruction_stall; // 声明信号、变量或生成变量。
    logic base_no_id_sub_stall; // 声明信号、变量或生成变量。
    logic base_flush_sub_stall; // 声明信号、变量或生成变量。
    logic base_unit_busy_stall; // 声明信号、变量或生成变量。
    logic base_operands_stall; // 声明信号、变量或生成变量。
    logic base_hold_stall; // 声明信号、变量或生成变量。
    logic single_source_issue_stall; // 声明信号、变量或生成变量。

    logic [3:0] stall_source_count; // 声明信号、变量或生成变量。
    ///////////////

    //Issue rd_addr to unit mem
    //Used for determining what outputs an operand stall is waiting on
    logic [MAX_NUM_UNITS-1:0] rd_addr_table [32]; // 声明信号、变量或生成变量。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (cpu.instruction_issued_with_rd) // 执行条件判断，满足条件时进入对应分支。
            rd_addr_table[`ISSUE_P.issue.rd_addr] <= `ISSUE_P.unit_needed_issue_stage;
    end // 结束语句块。

    generate if (EXAMPLE_CONFIG.INCLUDE_ICACHE) begin // 开始生成块，在编译期展开硬件结构。
        assign icache_hit = `ICACHE_P.tag_hit; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign icache_miss = `ICACHE_P.second_cycle & ~`ICACHE_P.tag_hit; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign iarb_stall = `ICACHE_P.request_r & ~cpu.icache_mem.ack; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

    generate if (EXAMPLE_CONFIG.INCLUDE_DCACHE) begin // 开始生成块，在编译期展开硬件结构。
        //Depends on data cache type; not enabled for now
        // assign dcache_hit = `DCACHE_P.load_hit;
        // assign dcache_miss = `DCACHE_P.line_complete;
        // assign darb_stall = cpu.dcache_mem.request & ~cpu.dcache_mem.ack;
    end endgenerate // 结束语句块。

    logic [MAX_NUM_UNITS-1:0] unit_ready; // 声明信号、变量或生成变量。
    generate for (i=0; i<MAX_NUM_UNITS; i++) // 开始生成块，在编译期展开硬件结构。
        assign unit_ready[i] = cpu.unit_issue[i].ready; // 执行连续赋值，把组合逻辑连接到目标信号。
    endgenerate // 结束生成块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        stats = '{default: '0};
        //Fetch
        stats[FETCH_EARLY_BR_CORRECTION_STAT] = `FETCH_P.early_branch_flush;
        stats[FETCH_SUB_UNIT_STALL_STAT] = `METADATA_P.pc_id_available & ~`FETCH_P.units_ready;
        stats[FETCH_ID_STALL_STAT] = ~`METADATA_P.pc_id_available;
        stats[FETCH_IC_HIT_STAT] = icache_hit;
        stats[FETCH_IC_MISS_STAT] = icache_miss;
        stats[FETCH_IC_ARB_STALL_STAT] = iarb_stall;

        //Branch predictor
        stats[FETCH_BP_BR_CORRECT_STAT] = `BRANCH_P.instruction_is_completing & ~`BRANCH_P.is_return_ex & ~`BRANCH_P.branch_flush;
        stats[FETCH_BP_BR_MISPREDICT_STAT] = `BRANCH_P.instruction_is_completing & ~`BRANCH_P.is_return_ex & `BRANCH_P.branch_flush;
        stats[FETCH_BP_RAS_CORRECT_STAT] = `BRANCH_P.instruction_is_completing & `BRANCH_P.is_return_ex & ~`BRANCH_P.branch_flush;
        stats[FETCH_BP_RAS_MISPREDICT_STAT] = `BRANCH_P.instruction_is_completing & `BRANCH_P.is_return_ex & `BRANCH_P.branch_flush;

        //Issue stalls
        base_no_instruction_stall = ~`ISSUE_P.issue.stage_valid | cpu.gc.fetch_flush;
        base_no_id_sub_stall = (`METADATA_P.post_issue_count == MAX_IDS);
        base_flush_sub_stall = cpu.gc.fetch_flush;
        base_unit_busy_stall = `ISSUE_P.issue.stage_valid & ~|(`ISSUE_P.unit_needed_issue_stage & unit_ready);
        base_operands_stall = `ISSUE_P.issue.stage_valid & ~(&`ISSUE_P.operand_ready);
        base_hold_stall = `ISSUE_P.issue.stage_valid & `ISSUE_P.issue_hold;

        stall_source_count = 4'(base_no_instruction_stall) + 4'(base_unit_busy_stall) + 4'(base_operands_stall) + 4'(base_hold_stall);
        single_source_issue_stall = (stall_source_count == 1);

        //Issue stall determination
        stats[ISSUE_NO_INSTRUCTION_STAT] = base_no_instruction_stall & single_source_issue_stall;
        stats[ISSUE_NO_ID_STAT] = base_no_instruction_stall & base_no_id_sub_stall & single_source_issue_stall;
        stats[ISSUE_FLUSH_STAT] = base_no_instruction_stall & base_flush_sub_stall & single_source_issue_stall;
        stats[ISSUE_UNIT_BUSY_STAT] = base_unit_busy_stall & single_source_issue_stall;
        stats[ISSUE_OPERANDS_NOT_READY_STAT] = base_operands_stall & single_source_issue_stall;
        stats[ISSUE_HOLD_STAT] = base_hold_stall & single_source_issue_stall;
        stats[ISSUE_MULTI_SOURCE_STAT] = (base_no_instruction_stall | base_unit_busy_stall | base_operands_stall | base_hold_stall) & ~single_source_issue_stall;

        //Misc Issue stats
        stats[ISSUE_OPERAND_STALL_FOR_BRANCH_STAT] = stats[ISSUE_OPERANDS_NOT_READY_STAT] & `ISSUE_P.unit_needed_issue_stage[BR_ID];
        stats[ISSUE_STORE_WITH_FORWARDED_DATA_STAT] = `ISSUE_P.issue_to[LS_ID] & `LS_P.issue_attr.is_store & `LS_P.rs2_inuse;
        stats[ISSUE_DIVIDER_RESULT_REUSE_STAT] = `ISSUE_P.issue_to[DIV_ID] & `DIV_P.div_op_reuse;

        //Issue Stall Source
        for (int i = 0; i < REGFILE_READ_PORTS; i++) begin // 执行循环或遍历。
            stats[ISSUE_OPERAND_STALL_ON_LOAD_STAT] |= `ISSUE_P.issue.stage_valid & rd_addr_table[`ISSUE_P.issue_rs_addr[i]][LS_ID] & ~`ISSUE_P.operand_ready[i] ;
            stats[ISSUE_OPERAND_STALL_ON_MULTIPLY_STAT] |= EXAMPLE_CONFIG.INCLUDE_UNIT.MUL & `ISSUE_P.issue.stage_valid & rd_addr_table[`ISSUE_P.issue_rs_addr[i]][MUL_ID] & ~`ISSUE_P.operand_ready[i] ;
            stats[ISSUE_OPERAND_STALL_ON_DIVIDE_STAT] |= EXAMPLE_CONFIG.INCLUDE_UNIT.DIV & `ISSUE_P.issue.stage_valid & rd_addr_table[`ISSUE_P.issue_rs_addr[i]][DIV_ID] & ~`ISSUE_P.operand_ready[i] ;
        end // 结束语句块。

        //LS Stats
        stats[LSU_LOAD_BLOCKED_BY_STORE_STAT] = `LSQ_P.lq.valid & `LSQ_P.load_blocked;
        stats[LSU_SUB_UNIT_STALL_STAT] = (`LS_P.lsq.load_valid | `LS_P.lsq.store_valid) & ~`LS_P.sub_unit_ready;
        stats[LSU_DC_HIT_STAT] = dcache_hit;
        stats[LSU_DC_MISS_STAT] = dcache_miss;
        stats[LSU_DC_ARB_STALL_STAT] = darb_stall;

        //Retire Instruction Mix
        for (int i = 0; i < RETIRE_PORTS; i++) begin // 执行循环或遍历。
            is_mul[i] = retire_ports_instruction[i][25] & ~retire_ports_instruction[i][14];
            is_div[i] = retire_ports_instruction[i][25] & retire_ports_instruction[i][14];
            instruction_mix_stats[i][ALU_STAT] = cpu.retire_port_valid[i] & (retire_ports_instruction[i][6:2] inside {ARITH_T, ARITH_IMM_T, AUIPC_T, LUI_T}) & ~(is_mul[i] | is_div[i]);
            instruction_mix_stats[i][BR_STAT] = cpu.retire_port_valid[i] & (retire_ports_instruction[i][6:2] inside {BRANCH_T, JAL_T, JALR_T});
            instruction_mix_stats[i][MUL_STAT] = cpu.retire_port_valid[i] & (retire_ports_instruction[i][6:2] inside {ARITH_T}) & is_mul[i];
            instruction_mix_stats[i][DIV_STAT] = cpu.retire_port_valid[i] & (retire_ports_instruction[i][6:2] inside {ARITH_T}) & is_div[i];
            instruction_mix_stats[i][LOAD_STAT] = cpu.retire_port_valid[i] & (retire_ports_instruction[i][6:2] inside {LOAD_T, FPU_LOAD_T, AMO_T});// & retire_ports_instruction[i][14:12] inside {LS_B_fn3, L_BU_fn3};
            instruction_mix_stats[i][STORE_STAT] = cpu.retire_port_valid[i] & (retire_ports_instruction[i][6:2] inside {STORE_T, FPU_STORE_T, AMO_T});
            instruction_mix_stats[i][FPU_STAT] = cpu.retire_port_valid[i] & (retire_ports_instruction[i][6:2] inside {FPU_MADD_T, FPU_MSUB_T, FPU_NMSUB_T, FPU_NMADD_T, FPU_OP_T});
            instruction_mix_stats[i][MISC_STAT] = cpu.retire_port_valid[i] & (retire_ports_instruction[i][6:2] inside {SYSTEM_T, FENCE_T});
        end // 结束语句块。
    end // 结束语句块。

    sim_stats #(.NUM_OF_STATS(NUM_STATS), .NUM_INSTRUCTION_MIX_STATS(NUM_INSTRUCTION_MIX_STATS)) stats_block (
        .start_collection(start_collection),
        .end_collection(end_collection),
        .stats(stats),
        .instruction_mix_stats(instruction_mix_stats),
        .retire_count(cpu.retire_count),
    .*);

    ////////////////////////////////////////////////////
    //Performs the lookups to provide the speculative architectural register file with
    //standard register names for simulation purposes
    logic [31:0][31:0] sim_registers_unamed_groups[EXAMPLE_CONFIG.NUM_WB_GROUPS]; // 声明信号、变量或生成变量。
    logic [31:0][31:0] sim_registers_unamed; // 声明信号、变量或生成变量。

    simulation_named_regfile sim_register;
// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        phys_addr_t phys_addr;
        logic [$clog2(EXAMPLE_CONFIG.NUM_WB_GROUPS)-1:0] wb_group; // 声明信号、变量或生成变量。
    } spec_table_t;
    spec_table_t translation [32];
    genvar i, j; // 声明信号、变量或生成变量。
    generate  for (i = 0; i < 32; i++) begin : gen_reg_file_sim // 开始生成块，在编译期展开硬件结构。
        for (j = 0; j < EXAMPLE_CONFIG.NUM_WB_GROUPS; j++) begin // 执行循环或遍历。
            if (FPGA_VENDOR == XILINX) begin // 执行条件判断，满足条件时进入对应分支。
                assign translation[i] = cpu.renamer_block.spec_table_ram.xilinx_gen.ram[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
                assign sim_registers_unamed_groups[j][i] = // 执行连续赋值，把组合逻辑连接到目标信号。
                cpu.register_file_block.register_file_gen[j].register_file_bank.xilinx_gen.ram[translation[i].phys_addr];
            end else if (FPGA_VENDOR == INTEL) begin // 结束语句块。
                assign translation[i] = cpu.renamer_block.spec_table_ram.intel_gen.lutrams[0].write_port.ram[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
                assign sim_registers_unamed_groups[j][i] = // 执行连续赋值，把组合逻辑连接到目标信号。
                cpu.register_file_block.register_file_gen[j].register_file_bank.intel_gen.lutrams[0].write_port.ram[translation[i].phys_addr];
            end // 结束语句块。
        end // 结束语句块。
        assign sim_registers_unamed[31-i] = sim_registers_unamed_groups[translation[i].wb_group][i]; // 执行连续赋值，把组合逻辑连接到目标信号。
    end // 结束语句块。
    endgenerate // 结束生成块。

    //FPU
    logic [31:0][FLEN-1:0] fp_sim_registers_unamed_groups[2]; // 声明信号、变量或生成变量。
    logic [31:0][FLEN-1:0] fp_sim_registers_unamed; // 声明信号、变量或生成变量。
    fp_simulation_named_regfile fp_sim_register;
// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        phys_addr_t fp_phys_addr;
        logic fp_wb_group; // 声明信号、变量或生成变量。
    } fp_spec_table_t;
    fp_spec_table_t fp_translation [32];

    generate if (EXAMPLE_CONFIG.INCLUDE_UNIT.FPU) begin : gen_fp_reg_file_sim // 开始生成块，在编译期展开硬件结构。
        for (i = 0; i < 32; i++) begin // 执行循环或遍历。
            for (j = 0; j < 2; j++) begin // 执行循环或遍历。
                if (FPGA_VENDOR == XILINX) begin // 执行条件判断，满足条件时进入对应分支。
                    assign fp_translation[i] = cpu.gen_fpu.fp_renamer_block.spec_table_ram.xilinx_gen.ram[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
                    assign fp_sim_registers_unamed_groups[j][i] = cpu.gen_fpu.fp_register_file_block.register_file_gen[j].register_file_bank.xilinx_gen.ram[fp_translation[i].fp_phys_addr]; // 执行连续赋值，把组合逻辑连接到目标信号。
                end else if (FPGA_VENDOR == INTEL) begin // 结束语句块。
                    assign fp_translation[i] = cpu.gen_fpu.fp_renamer_block.spec_table_ram.intel_gen.lutrams[0].write_port.ram[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
                    assign fp_sim_registers_unamed_groups[j][i] = cpu.gen_fpu.fp_register_file_block.register_file_gen[j].register_file_bank.intel_gen.lutrams[0].write_port.ram[fp_translation[i].fp_phys_addr]; // 执行连续赋值，把组合逻辑连接到目标信号。
                end // 结束语句块。
            end // 结束语句块。
            assign fp_sim_registers_unamed[31-i] = fp_sim_registers_unamed_groups[fp_translation[i].fp_wb_group][i]; // 执行连续赋值，把组合逻辑连接到目标信号。
        end // 结束语句块。
    end // 结束语句块。
    endgenerate // 结束生成块。

    assign NUM_RETIRE_PORTS = RETIRE_PORTS; // 执行连续赋值，把组合逻辑连接到目标信号。
    generate for (genvar i = 0; i < RETIRE_PORTS; i++) begin // 开始生成块，在编译期展开硬件结构。
        assign retire_ports_pc[i] = cpu.id_block.pc_table.ram[cpu.retire_ids[i]]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign retire_ports_instruction[i] = cpu.id_block.instruction_table.ram[cpu.retire_ids[i]]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign retire_ports_valid[i] = cpu.retire_port_valid[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

    assign store_queue_empty = ~cpu.load_store_status.outstanding_store; // 执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
