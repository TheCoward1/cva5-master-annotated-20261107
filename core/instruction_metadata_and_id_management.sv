// ============================================================================
// 文件：core/instruction_metadata_and_id_management.sv
// 类型：module
// 名称：instruction_metadata_and_id_management
// 作用：管理指令元数据、指令 ID、退休顺序和指令表。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2020 Eric Matthews,  Lesley Shannon
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

module instruction_metadata_and_id_management // 定义 instruction_metadata_and_id_management 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG // 声明可配置参数。
    )

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        input gc_outputs_t gc, // 声明输入端口。

        //Fetch
        output id_t pc_id, // 声明输出端口。
        output logic pc_id_available, // 声明输出端口。
        input logic [31:0] if_pc, // 声明输入端口。
        input logic pc_id_assigned, // 声明输入端口。

        output id_t fetch_id, // 声明输出端口。
        input logic early_branch_flush, // 声明输入端口。
        input logic fetch_complete, // 声明输入端口。
        input logic [31:0] fetch_instruction, // 声明输入端口。
        input fetch_metadata_t fetch_metadata, // 声明输入端口。

        //Decode ID
        output decode_packet_t decode, // 声明输出端口。
        input logic decode_advance, // 声明输入端口。
        input logic decode_uses_rd, // 声明输入端口。
        input logic fp_decode_uses_rd, // 声明输入端口。
        input rs_addr_t decode_rd_addr, // 声明输入端口。
        input logic decode_is_store, // 声明输入端口。
        //renamer
        input phys_addr_t decode_phys_rd_addr, // 声明输入端口。
        input phys_addr_t fp_decode_phys_rd_addr, // 声明输入端口。

        //Issue stage
        input issue_packet_t issue, // 声明输入端口。
        input logic instruction_issued, // 声明输入端口。
        input logic instruction_issued_with_rd, // 声明输入端口。
        input logic fp_instruction_issued_with_rd, // 声明输入端口。

        //WB
        input wb_packet_t wb_packet [CONFIG.NUM_WB_GROUPS], // 声明输入端口。
        input fp_wb_packet_t fp_wb_packet [2], // 声明输入端口。
        output phys_addr_t wb_phys_addr [CONFIG.NUM_WB_GROUPS], // 声明输出端口。
        output phys_addr_t fp_wb_phys_addr [2], // 声明输出端口。

        //Retirer
        output retire_packet_t wb_retire, // 声明输出端口。
        output retire_packet_t fp_wb_retire, // 声明输出端口。
        output retire_packet_t store_retire, // 声明输出端口。
        output id_t retire_ids [RETIRE_PORTS], // 声明输出端口。
        output logic retire_port_valid [RETIRE_PORTS], // 声明输出端口。
        output logic [LOG2_RETIRE_PORTS : 0] retire_count, // 声明输出端口。

        //CSR
        output logic [LOG2_MAX_IDS:0] post_issue_count // 声明输出端口。
    );
    //////////////////////////////////////////
    localparam NUM_WB_GROUPS = CONFIG.NUM_WB_GROUPS + 32'(CONFIG.INCLUDE_UNIT.FPU) + 32'(CONFIG.INCLUDE_UNIT.FPU); // 声明局部常量。
    logic [31:0] decode_pc; // 声明信号、变量或生成变量。
    logic [31:0] decode_instruction; // 声明信号、变量或生成变量。
    fetch_metadata_t decode_fetch_metadata;

// 定义类型别名或枚举/结构类型。
    typedef enum logic[1:0] {
        NONE = 2'b00,
        RD = 2'b01,
        STORE = 2'b10,
        FP_RD = 2'b11
    } instruction_type_t;
    instruction_type_t decode_type;
    instruction_type_t retire_type [RETIRE_PORTS];

    id_t decode_id;
    id_t oldest_pre_issue_id;

    localparam ID_COUNTER_W = LOG2_MAX_IDS+1; // 声明局部常量。
    logic [LOG2_MAX_IDS:0] fetched_count_neg; // 声明信号、变量或生成变量。
    logic [LOG2_MAX_IDS:0] pre_issue_count; // 声明信号、变量或生成变量。
    logic [LOG2_MAX_IDS:0] pre_issue_count_next; // 声明信号、变量或生成变量。
    logic [LOG2_MAX_IDS:0] post_issue_count_next; // 声明信号、变量或生成变量。
    logic [LOG2_MAX_IDS:0] inflight_count; // 声明信号、变量或生成变量。

    retire_packet_t wb_retire_next;
    retire_packet_t fp_wb_retire_next;
    retire_packet_t store_retire_next;

    id_t retire_ids_next [RETIRE_PORTS];
    logic retire_port_valid_next [RETIRE_PORTS]; // 声明信号、变量或生成变量。
    logic [LOG2_RETIRE_PORTS : 0] retire_count_next; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation

    ////////////////////////////////////////////////////
    //Instruction Metadata
    //PC table(s)
    lutram_1w_1r #(.DATA_TYPE(logic[31:0]), .DEPTH(MAX_IDS))
    pc_table (
        .clk(clk),
        .waddr(pc_id),
        .raddr(decode_id),
        .ram_write(pc_id_assigned),
        .new_ram_data(if_pc),
        .ram_data_out(decode_pc)
    );

    ////////////////////////////////////////////////////
    //Instruction table
    lutram_1w_1r #(.DATA_TYPE(logic[31:0]), .DEPTH(MAX_IDS))
    instruction_table (
        .clk(clk),
        .waddr(fetch_id),
        .raddr(decode_id),
        .ram_write(fetch_complete),
        .new_ram_data(fetch_instruction),
        .ram_data_out(decode_instruction)
    );

    ////////////////////////////////////////////////////
    //Valid fetched address table
    lutram_1w_1r #(.DATA_TYPE(fetch_metadata_t), .DEPTH(MAX_IDS))
    fetch_metadata_table (
        .clk(clk),
        .waddr(fetch_id),
        .raddr(decode_id),
        .ram_write(fetch_complete),
        .new_ram_data(fetch_metadata),
        .ram_data_out(decode_fetch_metadata)
    );

    ////////////////////////////////////////////////////
    //Retire Instruction Type Table
    //Number of read ports = RETIRE_PORTS
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (decode_uses_rd & |decode_rd_addr) // 执行条件判断，满足条件时进入对应分支。
            decode_type = RD;
        else if (decode_is_store) // 执行否则如果分支的条件判断。
            decode_type = STORE;
        else if (fp_decode_uses_rd) // 执行否则如果分支的条件判断。
            decode_type = FP_RD;
        else // 执行否则分支。
            decode_type = NONE;
    end // 结束语句块。
    lutram_1w_mr #(.DATA_TYPE(logic[1:0]), .DEPTH(MAX_IDS), .NUM_READ_PORTS(RETIRE_PORTS))
    retire_instruction_type_table (
        .clk(clk),
        .waddr(decode_id),
        .raddr(retire_ids_next),
        .ram_write(decode_advance),
        .new_ram_data(decode_type),
        .ram_data_out(retire_type)
    );

    ////////////////////////////////////////////////////
    //id_to_phys_rd_table
    //Number of read ports = WB_GROUPS
    id_t wb_ids [NUM_WB_GROUPS];
    phys_addr_t wb_phys_addrs [NUM_WB_GROUPS];
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        wb_ids[NUM_WB_GROUPS-2] = fp_wb_packet[0].id;
        wb_ids[NUM_WB_GROUPS-1] = fp_wb_packet[1].id;
        fp_wb_phys_addr[0] = wb_phys_addrs[NUM_WB_GROUPS-2];
        fp_wb_phys_addr[1] = wb_phys_addrs[NUM_WB_GROUPS-1];
        
        for (int i = 0; i < CONFIG.NUM_WB_GROUPS; i++) begin // 执行循环或遍历。
            //This will overwrite the FP packets if the configuration does not include it
            wb_ids[i] = wb_packet[i].id;
            wb_phys_addr[i] = wb_phys_addrs[i];
        end // 结束语句块。
    end // 结束语句块。
    
    lutram_1w_mr #(.DATA_TYPE(phys_addr_t), .DEPTH(MAX_IDS), .NUM_READ_PORTS(NUM_WB_GROUPS))
    id_to_phys_rd_table (
        .clk(clk),
        .waddr(decode_id),
        .raddr(wb_ids),
        .ram_write(decode_advance),
        .new_ram_data(fp_decode_uses_rd ? fp_decode_phys_rd_addr : decode_phys_rd_addr),
        .ram_data_out(wb_phys_addrs)
    );

    ////////////////////////////////////////////////////
    //ID Management
    
    //Next ID always increases, except on a fetch buffer flush.
    //On a fetch buffer flush, the next ID is restored to the oldest non-issued ID (decode or issue stage)
    //This prevents a stall in the case where all  IDs are either in-flight or
    //in the fetch buffer at the point of a fetch flush.
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            oldest_pre_issue_id <= 0;
        else if (instruction_issued) // 执行否则如果分支的条件判断。
            oldest_pre_issue_id <= oldest_pre_issue_id + 1;
    end // 结束语句块。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (gc.fetch_flush) begin // 执行条件判断，满足条件时进入对应分支。
            pc_id <= oldest_pre_issue_id;
            fetch_id <= oldest_pre_issue_id;
            decode_id <= oldest_pre_issue_id;
        end // 结束语句块。
        else begin // 执行否则分支。
            pc_id <= early_branch_flush ? fetch_id + LOG2_MAX_IDS'(fetch_complete) : pc_id + LOG2_MAX_IDS'(pc_id_assigned);
            fetch_id <= fetch_id + LOG2_MAX_IDS'(fetch_complete);
            decode_id <= decode_id + LOG2_MAX_IDS'(decode_advance);
        end // 结束语句块。
    end // 结束语句块。
    //Retire IDs
    //Each retire port lags behind the previous one by one index (eg. [3, 2, 1, 0])
     generate for (genvar i = 0; i < RETIRE_PORTS; i++) begin :gen_retire_ids // 开始生成块，在编译期展开硬件结构。
        always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) // 执行条件判断，满足条件时进入对应分支。
                retire_ids_next[i] <= LOG2_MAX_IDS'(i);
            else // 执行否则分支。
                retire_ids_next[i] <= retire_ids_next[i] + LOG2_MAX_IDS'(retire_count_next);
        end // 结束语句块。

        always_ff @ (posedge clk) // 开始时序逻辑块，在时钟边沿更新寄存器。
            retire_ids[i] <= retire_ids_next[i];
    end endgenerate // 结束语句块。

    //Represented as a negative value so that the MSB indicates that the decode stage is valid
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (gc.fetch_flush) // 执行条件判断，满足条件时进入对应分支。
            fetched_count_neg <= 0;
        else // 执行否则分支。
            fetched_count_neg <= fetched_count_neg + ID_COUNTER_W'(decode_advance) - ID_COUNTER_W'(fetch_complete);
    end // 结束语句块。

    //Full instruction count split into two: pre-issue and post-issue
    //pre-issue count can be cleared on a fetch flush
    //post-issue count decremented only on retire
    assign pre_issue_count_next = pre_issue_count  + ID_COUNTER_W'(pc_id_assigned) - ID_COUNTER_W'(instruction_issued); // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (gc.fetch_flush) // 执行条件判断，满足条件时进入对应分支。
            pre_issue_count <= 0;
        else // 执行否则分支。
            pre_issue_count <= pre_issue_count_next;
    end // 结束语句块。

    assign post_issue_count_next = post_issue_count + ID_COUNTER_W'(instruction_issued) - ID_COUNTER_W'(retire_count_next); // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            post_issue_count <= 0;
        else // 执行否则分支。
            post_issue_count <= post_issue_count_next;
    end // 结束语句块。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (gc.fetch_flush) // 执行条件判断，满足条件时进入对应分支。
            inflight_count <= post_issue_count_next;
        else // 执行否则分支。
            inflight_count <= pre_issue_count_next + post_issue_count_next;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //ID in-use determination
    logic id_waiting_for_writeback [RETIRE_PORTS]; // 声明信号、变量或生成变量。
    //WB group zero is not included as it completes within a single cycle
    //Non-writeback instructions not included as current instruction set
    //complete in their first cycle of the execute stage, or do not cause an
    //exception after that point

    logic id_waiting_toggle [NUM_WB_GROUPS]; // 声明信号、变量或生成变量。
    id_t id_waiting_toggle_addr [NUM_WB_GROUPS];
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        id_waiting_toggle[0] = (instruction_issued_with_rd & issue.is_multicycle) | fp_instruction_issued_with_rd;
        id_waiting_toggle_addr[0] = issue.id;

        id_waiting_toggle[NUM_WB_GROUPS-2] = fp_wb_packet[0].valid;
        id_waiting_toggle_addr[NUM_WB_GROUPS-2] = fp_wb_packet[0].id;
        id_waiting_toggle[NUM_WB_GROUPS-1] = fp_wb_packet[1].valid;
        id_waiting_toggle_addr[NUM_WB_GROUPS-1] = fp_wb_packet[1].id;

        //This will overwrite the FP packets if the configuration does not include it
        for (int i = 1; i < CONFIG.NUM_WB_GROUPS; i++) begin // 执行循环或遍历。
            id_waiting_toggle[i] = wb_packet[i].valid;
            id_waiting_toggle_addr[i] = wb_packet[i].id;
        end // 结束语句块。
    end // 结束语句块。

    toggle_memory_set # (
        .DEPTH (MAX_IDS),
        .NUM_WRITE_PORTS (NUM_WB_GROUPS),
        .NUM_READ_PORTS (RETIRE_PORTS)
    ) id_waiting_for_writeback_toggle_mem_set
    (
        .clk (clk),
        .init_clear (gc.init_clear),
        .toggle (id_waiting_toggle),
        .toggle_addr (id_waiting_toggle_addr),
        .read_addr (retire_ids_next),
        .in_use (id_waiting_for_writeback)
    );

    ////////////////////////////////////////////////////
    //Retirer
    logic contiguous_retire; // 声明信号、变量或生成变量。
    logic id_is_post_issue [RETIRE_PORTS]; // 声明信号、变量或生成变量。
    logic id_ready_to_retire [RETIRE_PORTS]; // 声明信号、变量或生成变量。
    logic [LOG2_RETIRE_PORTS-1:0] retire_with_rd_sel; // 声明信号、变量或生成变量。
    logic [LOG2_RETIRE_PORTS-1:0] retire_with_fp_rd_sel; // 声明信号、变量或生成变量。
    logic [LOG2_RETIRE_PORTS-1:0] retire_with_store_sel; // 声明信号、变量或生成变量。

    //Supports retiring up to RETIRE_PORTS instructions.  The retired block of instructions must be
    //contiguous and must start with the first retire port.  Additionally, only one register file writing 
    //instruction is supported per cycle.
    logic retire_with_rd_found; // 声明信号、变量或生成变量。
    logic retire_with_fp_rd_found; // 声明信号、变量或生成变量。
    logic retire_with_store_found; // 声明信号、变量或生成变量。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        contiguous_retire = 1;
        retire_with_rd_found = 0;
        retire_with_fp_rd_found = 0;
        retire_with_store_found = 0;

        retire_with_rd_sel = 0;
        retire_with_fp_rd_sel = 0;
        retire_with_store_sel = 0;
        for (int i = 0; i < RETIRE_PORTS; i++) begin // 执行循环或遍历。
            id_is_post_issue[i] = post_issue_count > ID_COUNTER_W'(i);

            id_ready_to_retire[i] = (id_is_post_issue[i] & contiguous_retire & ~id_waiting_for_writeback[i]);
            retire_port_valid_next[i] = id_ready_to_retire[i] & ~((retire_type[i] == RD & retire_with_rd_found) | (retire_type[i] == STORE & retire_with_store_found) | (retire_type[i] == FP_RD & retire_with_fp_rd_found));
     
            retire_with_rd_found |= retire_port_valid_next[i] & retire_type[i] == RD;
            retire_with_fp_rd_found |= retire_port_valid_next[i] & retire_type[i] == FP_RD;
            retire_with_store_found |= retire_port_valid_next[i] & retire_type[i] == STORE;
            contiguous_retire &= retire_port_valid_next[i];

            if (retire_port_valid_next[i] & retire_type[i] == RD) // 执行条件判断，满足条件时进入对应分支。
                retire_with_rd_sel = LOG2_RETIRE_PORTS'(i);
            if (retire_port_valid_next[i] & retire_type[i] == FP_RD) // 执行条件判断，满足条件时进入对应分支。
                retire_with_fp_rd_sel = LOG2_RETIRE_PORTS'(i);
            if (retire_port_valid_next[i] & retire_type[i] == STORE) // 执行条件判断，满足条件时进入对应分支。
                retire_with_store_sel = LOG2_RETIRE_PORTS'(i);
        end // 结束语句块。
    end // 结束语句块。

    //retire_next packets
    assign wb_retire_next = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        id : retire_ids_next[retire_with_rd_sel],
        valid : retire_with_rd_found
    };
    assign fp_wb_retire_next = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        id : retire_ids_next[retire_with_fp_rd_sel],
        valid : retire_with_fp_rd_found
    };
    assign store_retire_next = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        id : retire_ids_next[retire_with_store_sel],
        valid : retire_with_store_found
    };

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        retire_count_next = 0;
        for (int i = 0; i < RETIRE_PORTS; i++) begin // 执行循环或遍历。
            retire_count_next += retire_port_valid_next[i];
        end // 结束语句块。
    end // 结束语句块。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        wb_retire <= wb_retire_next;
        fp_wb_retire <= fp_wb_retire_next;
        store_retire <= store_retire_next;

        retire_count <= retire_count_next;
        for (int i = 0; i < RETIRE_PORTS; i++) // 执行循环或遍历。
            retire_port_valid[i] <= retire_port_valid_next[i];
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Outputs
    assign pc_id_available = ~inflight_count[LOG2_MAX_IDS]; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Decode
    localparam fetch_metadata_t ADDR_OK = '{ok : 1, error_code : INST_ADDR_MISSALIGNED}; // 声明局部常量。
    assign decode = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        id : decode_id,
        valid : fetched_count_neg[LOG2_MAX_IDS],
        pc : decode_pc,
        instruction : decode_instruction,
        fetch_metadata : CONFIG.MODES != BARE ? decode_fetch_metadata : ADDR_OK
    };

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions
    pc_id_assigned_without_pc_id_available_assertion:
        assert property (@(posedge clk) disable iff (rst) !(~pc_id_available & pc_id_assigned)) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("ID assigned without any ID available"); // 执行否则分支。

    decode_advanced_without_id_assertion:
        assert property (@(posedge clk) disable iff (rst) !(~decode.valid & decode_advance)) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("Decode advanced without ID"); // 执行否则分支。

endmodule // 结束模块定义。
