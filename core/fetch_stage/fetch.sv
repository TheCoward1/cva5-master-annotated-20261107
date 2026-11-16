// ============================================================================
// 文件：core/fetch_stage/fetch.sv
// 类型：module
// 名称：fetch
// 作用：实现 PC 生成、取指请求、指令对齐和分支预测接口。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017-2019 Eric Matthews,  Lesley Shannon
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

module fetch // 定义 fetch 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG // 声明可配置参数。
    )

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        input logic branch_flush, // 声明输入端口。
        input gc_outputs_t gc, // 声明输入端口。

        //ID Support
        input id_t pc_id, // 声明输入端口。
        input logic pc_id_available, // 声明输入端口。
        output logic pc_id_assigned, // 声明输出端口。
        output logic fetch_complete, // 声明输出端口。
        output fetch_metadata_t fetch_metadata, // 声明输出端口。

        branch_predictor_interface.fetch bp,
        ras_interface.fetch ras,

        //Instruction Metadata
        output logic early_branch_flush, // 声明输出端口。
        output logic early_branch_flush_ras_adjust, // 声明输出端口。
        output logic [31:0] if_pc, // 声明输出端口。
        output logic [31:0] fetch_instruction, // 声明输出端口。

        tlb_interface.requester tlb,
        local_memory_interface.master instruction_bram,
        wishbone_interface.master iwishbone,
        input logic icache_on, // 声明输入端口。
        mem_interface.ro_master mem
    );

    localparam NUM_SUB_UNITS = int'(CONFIG.INCLUDE_ILOCAL_MEM) + int'(CONFIG.INCLUDE_ICACHE) + int'(CONFIG.INCLUDE_IBUS); // 声明局部常量。
    localparam NUM_SUB_UNITS_W = (NUM_SUB_UNITS == 1) ? 1 : $clog2(NUM_SUB_UNITS); // 声明局部常量。

    localparam LOCAL_MEM_ID = 0; // 声明局部常量。
    localparam ICACHE_ID = int'(CONFIG.INCLUDE_ILOCAL_MEM); // 声明局部常量。
    localparam BUS_ID = ICACHE_ID + int'(CONFIG.INCLUDE_ICACHE); // 声明局部常量。

    localparam MAX_OUTSTANDING_REQUESTS = 2; // 声明局部常量。
    localparam MAX_OUTSTANDING_REQUESTS_W = $clog2(MAX_OUTSTANDING_REQUESTS); // 声明局部常量。
    //Subunit signals
    addr_utils_interface #(CONFIG.ILOCAL_MEM_ADDR.L, CONFIG.ILOCAL_MEM_ADDR.H) ilocal_mem_addr_utils ();
    addr_utils_interface #(CONFIG.ICACHE_ADDR.L, CONFIG.ICACHE_ADDR.H) icache_addr_utils ();
    addr_utils_interface #(CONFIG.IBUS_ADDR.L, CONFIG.IBUS_ADDR.H) ibus_addr_utils ();

    memory_sub_unit_interface sub_unit[NUM_SUB_UNITS-1:0]();
    amo_interface unused();

    logic [NUM_SUB_UNITS-1:0] sub_unit_address_match; // 声明信号、变量或生成变量。
    logic [NUM_SUB_UNITS-1:0] unit_ready; // 声明信号、变量或生成变量。
    logic [NUM_SUB_UNITS-1:0] unit_data_valid; // 声明信号、变量或生成变量。
    logic [31:0] unit_data_array [NUM_SUB_UNITS-1:0]; // 声明信号、变量或生成变量。

    logic units_ready; // 声明信号、变量或生成变量。
    logic address_valid; // 声明信号、变量或生成变量。

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic is_predicted_branch_or_jump; // 声明信号、变量或生成变量。
        logic is_branch; // 声明信号、变量或生成变量。
        logic [31:0] early_flush_pc; // 声明信号、变量或生成变量。
        logic address_valid; // 声明信号、变量或生成变量。
        logic mmu_fault; // 声明信号、变量或生成变量。
        logic [NUM_SUB_UNITS_W-1:0] subunit_id; // 声明信号、变量或生成变量。
    } fetch_attributes_t;
    fetch_attributes_t fetch_attr;

    logic [MAX_OUTSTANDING_REQUESTS_W:0] inflight_count; // 声明信号、变量或生成变量。
    logic [MAX_OUTSTANDING_REQUESTS_W:0] inflight_count_next; // 声明信号、变量或生成变量。
    logic [MAX_OUTSTANDING_REQUESTS_W:0] flush_count; // 声明信号、变量或生成变量。
    logic [MAX_OUTSTANDING_REQUESTS_W:0] flush_count_next; // 声明信号、变量或生成变量。


    logic [31:0] pc_plus_4; // 声明信号、变量或生成变量。
    logic [31:0] early_flush_pc; // 声明信号、变量或生成变量。
    logic [31:0] pc_mux [5]; // 声明信号、变量或生成变量。
    logic [2:0] pc_sel; // 声明信号、变量或生成变量。
    logic [31:0] next_pc; // 声明信号、变量或生成变量。
    logic [31:0] pc; // 声明信号、变量或生成变量。

    logic flush_or_rst; // 声明信号、变量或生成变量。
    fifo_interface #(.DATA_TYPE(fetch_attributes_t)) fetch_attr_fifo();

    logic update_pc; // 声明信号、变量或生成变量。
    logic new_mem_request; // 声明信号、变量或生成变量。
    logic exception_pending; // 声明信号、变量或生成变量。
    logic internal_fetch_complete; // 声明信号、变量或生成变量。

    genvar i; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation
    ////////////////////////////////////////////////////
    //Fetch PC
    assign update_pc = new_mem_request | gc.fetch_flush | early_branch_flush; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (gc.init_clear) // 执行条件判断，满足条件时进入对应分支。
            pc <= CONFIG.CSRS.RESET_VEC;
        else if (update_pc) // 执行否则如果分支的条件判断。
            pc <= {next_pc[31:2], 2'b0};
    end // 结束语句块。

    assign pc_plus_4 = pc + 4; // 执行连续赋值，把组合逻辑连接到目标信号。

    priority_encoder #(.WIDTH(5))
    pc_sel_encoder (
        .priority_vector ({1'b1, bp.use_prediction, early_branch_flush, branch_flush, gc.pc_override}),
        .encoded_result (pc_sel)
    );
    assign pc_mux[0] = gc.pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pc_mux[1] = bp.branch_flush_pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pc_mux[2] = early_flush_pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pc_mux[3] = bp.is_return ? ras.addr : bp.predicted_pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pc_mux[4] = pc_plus_4; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign next_pc = pc_mux[pc_sel]; // 执行连续赋值，把组合逻辑连接到目标信号。

    //If an exception occurs here in the fetch logic,
    //hold the fetching of data from memory until the status of the
    //exception has been resolved
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (flush_or_rst) // 执行条件判断，满足条件时进入对应分支。
            exception_pending <= 0;
        else if ((tlb.is_fault & ~fetch_attr_fifo.full) | (new_mem_request & ~address_valid)) // 执行否则如果分支的条件判断。
            exception_pending <= 1;
    end // 结束语句块。

    assign bp.new_mem_request = update_pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign bp.next_pc = next_pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign bp.if_pc = pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign bp.pc_id = pc_id; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign bp.pc_id_assigned = pc_id_assigned; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //RAS support
    logic ras_update_permitted; // 声明信号、变量或生成变量。
    assign ras_update_permitted = bp.use_prediction & new_mem_request & ~(branch_flush | gc.pc_override | early_branch_flush); // 执行连续赋值，把组合逻辑连接到目标信号。

    assign ras.pop = bp.is_return & ras_update_permitted; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ras.push = bp.is_call & ras_update_permitted; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ras.branch_fetched = bp.is_branch & ras_update_permitted; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ras.new_addr = pc_plus_4; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //TLB
    assign tlb.virtual_address = pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign tlb.rnw = 1; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign tlb.new_request = tlb.ready & pc_id_available & ~fetch_attr_fifo.full & (~exception_pending) & (~gc.fetch_hold); // 执行连续赋值，把组合逻辑连接到目标信号。

    //////////////////////////////////////////////
    //Issue Control Signals
    assign flush_or_rst = (rst | gc.fetch_flush | early_branch_flush); // 执行连续赋值，把组合逻辑连接到目标信号。

    assign new_mem_request = tlb.done & units_ready & ~gc.fetch_hold & ~fetch_attr_fifo.full; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pc_id_assigned = new_mem_request | (tlb.is_fault & ~fetch_attr_fifo.full); // 执行连续赋值，把组合逻辑连接到目标信号。

    //////////////////////////////////////////////
    //Subunit Tracking
    logic [NUM_SUB_UNITS_W-1:0] subunit_id; // 声明信号、变量或生成变量。
    one_hot_to_integer #(NUM_SUB_UNITS)
    hit_way_conv (
        .one_hot (sub_unit_address_match),
        .int_out (subunit_id)
    );
    assign fetch_attr_fifo.data_in = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        is_predicted_branch_or_jump : bp.use_prediction,
        is_branch : (bp.use_prediction & bp.is_branch),
        early_flush_pc : pc_plus_4,
        address_valid : address_valid,
        mmu_fault : tlb.is_fault,
        subunit_id : subunit_id
    };
    assign fetch_attr_fifo.push = pc_id_assigned; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fetch_attr_fifo.potential_push = pc_id_assigned; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fetch_attr_fifo.pop = internal_fetch_complete; // 执行连续赋值，把组合逻辑连接到目标信号。

    cva5_fifo #(.DATA_TYPE(fetch_attributes_t), .FIFO_DEPTH(MAX_OUTSTANDING_REQUESTS))
    attributes_fifo (
        .clk (clk),
        .rst (rst),
        .fifo (fetch_attr_fifo)
    );
    assign fetch_attr = fetch_attr_fifo.data_out; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign early_flush_pc = fetch_attr.early_flush_pc; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign inflight_count_next = inflight_count + MAX_OUTSTANDING_REQUESTS_W'(fetch_attr_fifo.push) - MAX_OUTSTANDING_REQUESTS_W'(fetch_attr_fifo.pop); // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            inflight_count <= 0;
        else // 执行否则分支。
            inflight_count <= inflight_count_next;
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            flush_count <= 0;
        else if (gc.fetch_flush | early_branch_flush) // 执行否则如果分支的条件判断。
            flush_count <= inflight_count_next;
        else if (|flush_count & fetch_attr_fifo.pop) // 执行否则如果分支的条件判断。
            flush_count <= flush_count - 1;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Subunit Interfaces
    //In the case of a gc.fetch_flush, a request may already be in progress
    //for any sub unit.  That request can either be completed or aborted.
    //In either case, data_valid must NOT be asserted.
    generate for (i=0; i < NUM_SUB_UNITS; i++) begin : gen_fetch_sources // 开始生成块，在编译期展开硬件结构。
        assign sub_unit[i].new_request = fetch_attr_fifo.push & sub_unit_address_match[i] & ~tlb.is_fault; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign sub_unit[i].addr = tlb.physical_address; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign sub_unit[i].re = 1; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign sub_unit[i].we = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign sub_unit[i].be = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign sub_unit[i].data_in = '0; // 执行连续赋值，把组合逻辑连接到目标信号。

        assign unit_ready[i] = sub_unit[i].ready; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign unit_data_valid[i] = sub_unit[i].data_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign unit_data_array[i] = sub_unit[i].data_out; // 执行连续赋值，把组合逻辑连接到目标信号。
    end // 结束语句块。
    endgenerate // 结束生成块。

    generate if (CONFIG.INCLUDE_ILOCAL_MEM) begin : gen_fetch_local_mem // 开始生成块，在编译期展开硬件结构。
        assign sub_unit_address_match[LOCAL_MEM_ID] = ilocal_mem_addr_utils.address_range_check(tlb.physical_address); // 执行连续赋值，把组合逻辑连接到目标信号。
        local_mem_sub_unit i_local_mem (
            .clk (clk),
            .rst (rst),
            .write_outstanding (),
            .amo (1'b0),
            .amo_type ('x),
            .amo_unit (unused),
            .unit (sub_unit[LOCAL_MEM_ID]),
            .local_mem (instruction_bram)
        );
    end // 结束语句块。
    endgenerate // 结束生成块。

    generate if (CONFIG.INCLUDE_IBUS) begin : gen_fetch_ibus // 开始生成块，在编译期展开硬件结构。
        assign sub_unit_address_match[BUS_ID] = ibus_addr_utils.address_range_check(tlb.physical_address); // 执行连续赋值，把组合逻辑连接到目标信号。
        wishbone_master iwishbone_bus (
            .clk (clk),
            .rst (rst),
            .write_outstanding (),
            .amo (1'b0),
            .amo_type ('x),
            .amo_unit (unused),
            .wishbone (iwishbone),
            .ls (sub_unit[BUS_ID])
        );
    end // 结束语句块。
    endgenerate // 结束生成块。

    generate if (CONFIG.INCLUDE_ICACHE) begin : gen_fetch_icache // 开始生成块，在编译期展开硬件结构。
        ////////////////////////////////////////////////////
        //Instruction fence
        //A fence first prevents any new instructions from being issued then waits for inflight fetches to complete
        //The fence signal can only be delivered to the icache once it is idle
        //This logic will be optimized away when instruction fences aren't enabled as gc.fetch_ifence will be constant 0
        logic ifence_pending; // 声明信号、变量或生成变量。
        logic ifence_start; // 声明信号、变量或生成变量。
        assign ifence_start = ifence_pending & ~|inflight_count_next; // 执行连续赋值，把组合逻辑连接到目标信号。
        
        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) // 执行条件判断，满足条件时进入对应分支。
                ifence_pending <= 0;
            else begin // 执行否则分支。
                if (gc.fetch_ifence) // 执行条件判断，满足条件时进入对应分支。
                    ifence_pending <= 1;
                else if (~|inflight_count_next) // 执行否则如果分支的条件判断。
                    ifence_pending <= 0;
            end // 结束语句块。
        end // 结束语句块。

        assign sub_unit_address_match[ICACHE_ID] = icache_addr_utils.address_range_check(tlb.physical_address); // 执行连续赋值，把组合逻辑连接到目标信号。
        icache #(.CONFIG(CONFIG))
        i_cache (
            .clk (clk),
            .rst (rst),
            .ifence (ifence_start),
            .icache_on (icache_on),
            .mem (mem),
            .fetch_sub (sub_unit[ICACHE_ID])
        );
    end endgenerate // 结束语句块。

    assign units_ready = &unit_ready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign address_valid = |sub_unit_address_match; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Instruction metada updates
    logic valid_fetch_result; // 声明信号、变量或生成变量。
    assign valid_fetch_result = CONFIG.MODES != BARE ? (fetch_attr_fifo.valid & fetch_attr.address_valid & (~fetch_attr.mmu_fault)) : 1; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign if_pc = pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fetch_metadata.ok = valid_fetch_result; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fetch_metadata.error_code = fetch_attr.mmu_fault ? INST_PAGE_FAULT : INST_ACCESS_FAULT; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign fetch_instruction = unit_data_array[fetch_attr.subunit_id]; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign internal_fetch_complete = fetch_attr_fifo.valid & (~valid_fetch_result | |unit_data_valid);//allow instruction to propagate to decode if address is invalid；执行连续赋值，把组合逻辑连接到目标信号。
    assign fetch_complete = internal_fetch_complete & ~|flush_count; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Branch Predictor corruption check
    //Needed if instruction memory is changed after any branches have been executed
    generate if (CONFIG.INCLUDE_IFENCE | CONFIG.MODES == MSU) begin : gen_branch_corruption_check // 开始生成块，在编译期展开硬件结构。
        logic is_branch_or_jump; // 声明信号、变量或生成变量。
        assign is_branch_or_jump = fetch_instruction[6:2] inside {JAL_T, JALR_T, BRANCH_T}; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign early_branch_flush = (valid_fetch_result & (|unit_data_valid)) & fetch_attr.is_predicted_branch_or_jump & (~is_branch_or_jump) & (~|flush_count); // 执行连续赋值，把组合逻辑连接到目标信号。
        assign early_branch_flush_ras_adjust = (valid_fetch_result & (|unit_data_valid)) & fetch_attr.is_branch & (~is_branch_or_jump) & (~|flush_count); // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。
    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions
    spurious_fetch_complete_assertion:
        assert property (@(posedge clk) disable iff (rst) (|unit_data_valid) |-> (fetch_attr_fifo.valid && unit_data_valid[fetch_attr.subunit_id])) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("Spurious fetch complete detected!"); // 执行否则分支。

endmodule // 结束模块定义。
