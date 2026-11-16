// ============================================================================
// 文件：core/execution_units/load_store_unit/load_store_unit.sv
// 类型：module
// 名称：load_store_unit
// 作用：实现访存流水线、地址生成、MMU 接口、缓存接口和异常处理。
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

module load_store_unit // 定义 load_store_unit 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。
    import csr_types::*; // 导入包或命名空间：csr_types::*;。
    import opcodes::*; // 导入包或命名空间：opcodes::*;。

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG // 声明可配置参数。
    )

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        input gc_outputs_t gc, // 声明输入端口。

        input decode_packet_t decode_stage, // 声明输入端口。
        output logic unit_needed, // 声明输出端口。
        output logic [REGFILE_READ_PORTS-1:0] uses_rs, // 声明输出端口。
        output logic [2:0] fp_uses_rs, // 声明输出端口。
        output logic uses_rd, // 声明输出端口。
        output logic fp_uses_rd, // 声明输出端口。
        output logic decode_is_store, // 声明输出端口。

        input issue_packet_t issue_stage, // 声明输入端口。
        input logic issue_stage_ready, // 声明输入端口。
        input logic instruction_issued_with_rd, // 声明输入端口。
        input logic fp_instruction_issued_with_rd, // 声明输入端口。
        input logic rs2_inuse, // 声明输入端口。
        input logic fp_rs2_inuse, // 声明输入端口。
        input rs_addr_t issue_rs_addr [REGFILE_READ_PORTS], // 声明输入端口。
        input logic [$clog2(CONFIG.NUM_WB_GROUPS)-1:0] issue_rd_wb_group, // 声明输入端口。
        input logic fp_issue_rd_wb_group, // 声明输入端口。
        input logic [31:0] rf [REGFILE_READ_PORTS], // 声明输入端口。
        input logic[FLEN-1:0] fp_rf[3], // 声明输入端口。

        unit_issue_interface.unit issue,

        input logic dcache_on, // 声明输入端口。
        input logic clear_reservation, // 声明输入端口。
        tlb_interface.requester tlb,

        mem_interface.rw_master mem,

        axi_interface.master m_axi,
        avalon_interface.master m_avalon,
        wishbone_interface.master dwishbone,

        local_memory_interface.master data_bram,

        //CSR
        input logic [1:0] current_privilege, // 声明输入端口。
        input envcfg_t menvcfg, // 声明输入端口。
        input envcfg_t senvcfg, // 声明输入端口。

        //Writeback-Store Interface
        input wb_packet_t wb_packet [CONFIG.NUM_WB_GROUPS], // 声明输入端口。
        input fp_wb_packet_t fp_wb_packet [2], // 声明输入端口。

        //Retire
        input id_t retire_id, // 声明输入端口。
        input retire_packet_t store_retire, // 声明输入端口。

        exception_interface.unit exception,
        output load_store_status_t load_store_status, // 声明输出端口。
        unit_writeback_interface.unit wb,
        unit_writeback_interface.unit fp_wb
    );

    localparam NUM_SUB_UNITS = int'(CONFIG.INCLUDE_DLOCAL_MEM) + int'(CONFIG.INCLUDE_PERIPHERAL_BUS) + int'(CONFIG.INCLUDE_DCACHE); // 声明局部常量。
    localparam NUM_SUB_UNITS_W = (NUM_SUB_UNITS == 1) ? 1 : $clog2(NUM_SUB_UNITS); // 声明局部常量。

    localparam LOCAL_MEM_ID = 0; // 声明局部常量。
    localparam BUS_ID = int'(CONFIG.INCLUDE_DLOCAL_MEM); // 声明局部常量。
    localparam DCACHE_ID = int'(CONFIG.INCLUDE_DLOCAL_MEM) + int'(CONFIG.INCLUDE_PERIPHERAL_BUS); // 声明局部常量。

    //Should be equal to pipeline depth of longest load/store subunit 
    localparam ATTRIBUTES_DEPTH = 1; // 声明局部常量。

    //Subunit signals
    amo_interface amo_if[NUM_SUB_UNITS]();
    addr_utils_interface #(CONFIG.DLOCAL_MEM_ADDR.L, CONFIG.DLOCAL_MEM_ADDR.H) dlocal_mem_addr_utils ();
    addr_utils_interface #(CONFIG.PERIPHERAL_BUS_ADDR.L, CONFIG.PERIPHERAL_BUS_ADDR.H) dpbus_addr_utils ();
    addr_utils_interface #(CONFIG.DCACHE_ADDR.L, CONFIG.DCACHE_ADDR.H) dcache_addr_utils ();
    memory_sub_unit_interface sub_unit[NUM_SUB_UNITS-1:0]();

    addr_utils_interface #(CONFIG.DCACHE.NON_CACHEABLE.L, CONFIG.DCACHE.NON_CACHEABLE.H) uncacheable_utils ();

    logic [NUM_SUB_UNITS-1:0] sub_unit_address_match; // 声明信号、变量或生成变量。

    data_access_shared_inputs_t shared_inputs;
    logic [31:0] unit_data_array [NUM_SUB_UNITS-1:0]; // 声明信号、变量或生成变量。
    logic [NUM_SUB_UNITS-1:0] unit_ready; // 声明信号、变量或生成变量。
    logic [NUM_SUB_UNITS-1:0] unit_write_outstanding; // 声明信号、变量或生成变量。
    logic write_outstanding; // 声明信号、变量或生成变量。
    logic [NUM_SUB_UNITS-1:0] unit_data_valid; // 声明信号、变量或生成变量。
    logic [NUM_SUB_UNITS_W-1:0] last_unit; // 声明信号、变量或生成变量。

    logic sub_unit_ready; // 声明信号、变量或生成变量。
    logic [NUM_SUB_UNITS_W-1:0] subunit_id; // 声明信号、变量或生成变量。
    ls_subunit_t padded_subunit_id;

    logic unit_switch; // 声明信号、变量或生成变量。
    logic unit_switch_in_progress; // 声明信号、变量或生成变量。
    logic unit_switch_hold; // 声明信号、变量或生成变量。

    logic sel_load; // 声明信号、变量或生成变量。
    logic sub_unit_issue; // 声明信号、变量或生成变量。
    logic sub_unit_load_issue; // 声明信号、变量或生成变量。
    logic sub_unit_store_issue; // 声明信号、变量或生成变量。

    logic load_response; // 声明信号、变量或生成变量。
    logic load_complete; // 声明信号、变量或生成变量。

    logic [31:0] virtual_address; // 声明信号、变量或生成变量。

    logic [31:0] unit_muxed_load_data; // 声明信号、变量或生成变量。
    logic [31:0] aligned_load_data; // 声明信号、变量或生成变量。
    logic [31:0] final_load_data; // 声明信号、变量或生成变量。

    logic tlb_request_r; // 声明信号、变量或生成变量。
    logic tlb_lq; // 声明信号、变量或生成变量。

    logic unaligned_addr; // 声明信号、变量或生成变量。
    logic exception_is_fp; // 声明信号、变量或生成变量。
    logic exception_is_store; // 声明信号、变量或生成变量。
    logic nontrivial_fence; // 声明信号、变量或生成变量。
    logic fence_hold; // 声明信号、变量或生成变量。
    logic illegal_cbo; // 声明信号、变量或生成变量。
    logic exception_lsq_push; // 声明信号、变量或生成变量。
    logic nomatch_fault; // 声明信号、变量或生成变量。
    logic late_exception; // 声明信号、变量或生成变量。

    id_t exception_id;

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic is_signed; // 声明信号、变量或生成变量。
        logic [1:0] byte_addr; // 声明信号、变量或生成变量。
        logic [1:0] sign_sel; // 声明信号、变量或生成变量。
        logic [1:0] final_mux_sel; // 声明信号、变量或生成变量。
        id_t id;
        logic [NUM_SUB_UNITS_W-1:0] subunit_id; // 声明信号、变量或生成变量。
        fp_ls_op_t fp_op;
    } load_attributes_t;
    load_attributes_t  wb_attr;

    common_instruction_t instruction;//rs1_addr, rs2_addr, fn3, fn7, rd_addr, upper/lower opcode

    logic [3:0] be; // 声明信号、变量或生成变量。
    //FIFOs
    fifo_interface #(.DATA_TYPE(load_attributes_t)) load_attributes();

    load_store_queue_interface lsq();
    ////////////////////////////////////////////////////
    //Implementation

    ////////////////////////////////////////////////////
    //Decode
    assign instruction = decode_stage.instruction; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign unit_needed = instruction inside {LB, LH, LW, LBU, LHU, SB, SH, SW, FENCE} | // 执行连续赋值，把组合逻辑连接到目标信号。
        (CONFIG.INCLUDE_CBO & instruction inside {CBO_INVAL, CBO_CLEAN, CBO_FLUSH}) |
        (CONFIG.INCLUDE_UNIT.FPU & instruction inside {SP_FLW, SP_FSW, DP_FLD, DP_FSD}) |
        (CONFIG.INCLUDE_AMO & instruction inside {AMO_ADD, AMO_XOR, AMO_OR, AMO_AND, AMO_MIN, AMO_MAX, AMO_MINU, AMO_MAXU, AMO_SWAP, AMO_LR, AMO_SC});
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        uses_rs = '0;
        uses_rs[RS1] = instruction inside {LB, LH, LW, LBU, LHU, SB, SH, SW} |
            (CONFIG.INCLUDE_CBO & instruction inside {CBO_INVAL, CBO_CLEAN, CBO_FLUSH}) |
            (CONFIG.INCLUDE_UNIT.FPU & instruction inside {SP_FLW, SP_FSW, DP_FLD, DP_FSD}) |
            (CONFIG.INCLUDE_AMO & instruction inside {AMO_ADD, AMO_XOR, AMO_OR, AMO_AND, AMO_MIN, AMO_MAX, AMO_MINU, AMO_MAXU, AMO_SWAP, AMO_LR, AMO_SC});
        if (CONFIG.INCLUDE_AMO) // 执行条件判断，满足条件时进入对应分支。
            uses_rs[RS2] = instruction inside {AMO_ADD, AMO_XOR, AMO_OR, AMO_AND, AMO_MIN, AMO_MAX, AMO_MINU, AMO_MAXU, AMO_SWAP, AMO_SC};
        if (~CONFIG.INCLUDE_FORWARDING_TO_STORES) // 执行条件判断，满足条件时进入对应分支。
            uses_rs[RS2] |= instruction inside {SB, SH, SW};
        uses_rd = instruction inside {LB, LH, LW, LBU, LHU} | (CONFIG.INCLUDE_AMO & instruction inside {AMO_ADD, AMO_XOR, AMO_OR, AMO_AND, AMO_MIN, AMO_MAX, AMO_MINU, AMO_MAXU, AMO_SWAP, AMO_LR, AMO_SC});
        fp_uses_rs = '0;
        fp_uses_rs[RS2] = ~CONFIG.INCLUDE_FORWARDING_TO_STORES & CONFIG.INCLUDE_UNIT.FPU & instruction inside {SP_FSW, DP_FSD};
        fp_uses_rd = CONFIG.INCLUDE_UNIT.FPU & instruction inside {SP_FLW, DP_FLD};
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //LS specific decode support
// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic is_load; // 声明信号、变量或生成变量。
        logic is_store; // 声明信号、变量或生成变量。
        logic is_fence; // 声明信号、变量或生成变量。
        logic is_cbo; // 声明信号、变量或生成变量。
        cbo_t cbo_type;
        logic is_fpu; // 声明信号、变量或生成变量。
        logic is_double; // 声明信号、变量或生成变量。
        logic nontrivial_fence; // 声明信号、变量或生成变量。
        logic is_amo; // 声明信号、变量或生成变量。
        amo_t amo_type;
        logic rd_zero; // 声明信号、变量或生成变量。
        logic [11:0] offset; // 声明信号、变量或生成变量。
    } ls_attr_t;
    ls_attr_t decode_attr;
    ls_attr_t issue_attr;

    logic [11:0] load_offset; // 声明信号、变量或生成变量。
    logic [11:0] store_offset; // 声明信号、变量或生成变量。
    assign load_offset = instruction[31:20]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign store_offset = {instruction[31:25], instruction[11:7]}; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Only a reduced subset of possible fences require stalling, because of the following guarantees:
    //The load queue does not reorder loads
    //The store queue does not reorder stores
    //Earlier loads are always selected before later stores
    //The data cache and local memory are sequentially consistent (no reordering)
    //All peripheral busses are sequentially consistent across request types
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (NUM_SUB_UNITS == 3) // 执行条件判断，满足条件时进入对应分支。
            nontrivial_fence = (
                (instruction[27] & (instruction[22] | instruction[20])) | //Peripheral read before any write
                (instruction[26] & (instruction[23] | |instruction[21:20])) | //Peripheral write before anything other than a peripheral write
                (instruction[25] & instruction[22]) | //Regular read before peripheral write
                (instruction[24]) //Regular write before anything
            );
        else if (NUM_SUB_UNITS == 2 & ~CONFIG.INCLUDE_PERIPHERAL_BUS) // 执行否则如果分支的条件判断。
            nontrivial_fence = instruction[24] & |instruction[21:20]; //Regular write before any regular
        else if (NUM_SUB_UNITS == 2) // 执行否则如果分支的条件判断。
            nontrivial_fence = (
                (instruction[27] & (instruction[22] | instruction[20])) | //Peripheral read before any write
                (instruction[26] & (instruction[23] | |instruction[21:20])) | //Peripheral write before anything other than a peripheral write
                (instruction[25] & instruction[22]) | //Memory read before peripheral write
                (instruction[24] & |instruction[23:21]) //Memory write before anything other than a memory write
            );
        else if (NUM_SUB_UNITS == 1 & ~CONFIG.INCLUDE_PERIPHERAL_BUS) // 执行否则如果分支的条件判断。
            nontrivial_fence = instruction[24] & instruction[21]; //Memory write before memory read
        else if (NUM_SUB_UNITS == 1 & CONFIG.INCLUDE_PERIPHERAL_BUS) // 执行否则如果分支的条件判断。
            nontrivial_fence = (
                (instruction[27] & instruction[22]) | //Peripheral read before peripheral write
                (instruction[26] & instruction[23]) //Peripheral write before peripheral read
            );
        else //0 subunits??；执行否则分支。
            nontrivial_fence = 0;
    end // 结束语句块。

    assign decode_attr = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        is_load : ~instruction.upper_opcode[5] & ~instruction.upper_opcode[3],
        is_store : instruction inside {SB, SH, SW} | CONFIG.INCLUDE_UNIT.FPU & instruction inside {SP_FSW, DP_FSD},
        is_fence : ~instruction.fn3[1] & instruction.upper_opcode[3],
        nontrivial_fence : nontrivial_fence,
        is_cbo : CONFIG.INCLUDE_CBO & instruction inside {CBO_INVAL, CBO_CLEAN, CBO_FLUSH},
        cbo_type : cbo_t'(instruction[21:20]),
        is_fpu : CONFIG.INCLUDE_UNIT.FPU & instruction.upper_opcode[3:2] == 2'b01,
        is_double : CONFIG.INCLUDE_UNIT.FPU & instruction.fn3[1:0] == 2'b11,
        is_amo : CONFIG.INCLUDE_AMO & instruction.upper_opcode[3] & instruction.upper_opcode[5],
        amo_type : amo_t'(instruction[31:27]),
        rd_zero : ~|instruction.rd_addr,
        offset : (CONFIG.INCLUDE_CBO | CONFIG.INCLUDE_AMO) & instruction[3] ? '0 : (instruction[5] ? store_offset : load_offset)
    };
    assign decode_is_store = decode_attr.is_store | decode_attr.is_cbo; //Must be exact；执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue_stage_ready) // 执行条件判断，满足条件时进入对应分支。
            issue_attr <= decode_attr;
    end // 结束语句块。

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        id_t id;
        logic [$clog2(CONFIG.NUM_WB_GROUPS)-1:0] wb_group; // 声明信号、变量或生成变量。
        logic fp_wb_group; // 声明信号、变量或生成变量。
    } rd_attributes_t;
    rd_attributes_t rd_attributes;

    //Store FP instructions in 32-64
    lutram_1w_1r #(.DATA_TYPE(rd_attributes_t), .DEPTH(64))
    rd_to_id_table (
        .clk(clk),
        .waddr({fp_instruction_issued_with_rd, issue_stage.rd_addr}),
        .raddr({issue_attr.is_fpu, issue_rs_addr[RS2]}),
        .ram_write(instruction_issued_with_rd | fp_instruction_issued_with_rd),
        .new_ram_data('{
            id : issue_stage.id,
            wb_group : issue_rd_wb_group,
            fp_wb_group : fp_issue_rd_wb_group
        }),
        .ram_data_out(rd_attributes)
    );
    
    ////////////////////////////////////////////////////
    //CSR Permissions
    //Can impact fences, atomic instructions, and CBO
    logic fiom; // 声明信号、变量或生成变量。
    logic fiom_amo_hold; // 声明信号、变量或生成变量。
    generate if (CONFIG.MODES inside {MU, MSU}) begin : gen_csr_env // 开始生成块，在编译期展开硬件结构。
        //Fence on IO implies memory; force all fences to be nontrivial for simplicity
        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            if (CONFIG.MODES == MU) // 执行条件判断，满足条件时进入对应分支。
                fiom = current_privilege == USER_PRIVILEGE & menvcfg.fiom;
            else // 执行否则分支。
                fiom = (current_privilege != MACHINE_PRIVILEGE & menvcfg.fiom) | (current_privilege == USER_PRIVILEGE & senvcfg.fiom);
        end // 结束语句块。

        //AMO instructions AQ-RL consider all memory regions; force write drain for simplicity
        logic fiom_amo_hold_r; // 声明信号、变量或生成变量。
        logic set_fiom_amo_hold; // 声明信号、变量或生成变量。
        assign set_fiom_amo_hold = lsq.load_valid & shared_inputs.amo & fiom & write_outstanding; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign fiom_amo_hold = set_fiom_amo_hold | fiom_amo_hold_r; // 执行连续赋值，把组合逻辑连接到目标信号。

        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst | ~write_outstanding) // 执行条件判断，满足条件时进入对应分支。
                fiom_amo_hold_r <= 0;
            else // 执行否则分支。
                fiom_amo_hold_r <= fiom_amo_hold_r | set_fiom_amo_hold;
        end // 结束语句块。
    end endgenerate // 结束语句块。

    ////////////////////////////////////////////////////
    //Exceptions
    generate if (CONFIG.MODES != BARE) begin : gen_ls_exceptions // 开始生成块，在编译期展开硬件结构。
        logic new_exception; // 声明信号、变量或生成变量。
        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            if (issue_stage.fn3 == LS_H_fn3 | issue_stage.fn3 == L_HU_fn3) // 执行条件判断，满足条件时进入对应分支。
                unaligned_addr = virtual_address[0];
            else if (issue_stage.fn3 == LS_W_fn3) // 执行否则如果分支的条件判断。
                unaligned_addr = |virtual_address[1:0];
            //Double-precision operations raise if not aligned on 8 byte boundary even though they are decomposed into 4 byte operations
            //This is because the operation might straddle two memory regions
            else if (CONFIG.INCLUDE_UNIT.FPU & issue_stage.fn3 == LS_D_fn3) // 执行否则如果分支的条件判断。
                unaligned_addr = |virtual_address[2:0];
            else // 执行否则分支。
                unaligned_addr = 0;
        end // 结束语句块。

        logic menv_illegal; // 声明信号、变量或生成变量。
        logic senv_illegal; // 声明信号、变量或生成变量。
        assign menv_illegal = CONFIG.INCLUDE_CBO & (issue_attr.is_cbo & issue_attr.cbo_type == INVAL ? menvcfg.cbie == 2'b00 : ~menvcfg.cbcfe); // 执行连续赋值，把组合逻辑连接到目标信号。
        assign senv_illegal = CONFIG.INCLUDE_CBO & (issue_attr.is_cbo & issue_attr.cbo_type == INVAL ? senvcfg.cbie == 2'b00 : ~senvcfg.cbcfe); // 执行连续赋值，把组合逻辑连接到目标信号。
        assign illegal_cbo = CONFIG.MODES == MU ? current_privilege == USER_PRIVILEGE & menv_illegal : (current_privilege != MACHINE_PRIVILEGE & menv_illegal) | (current_privilege == USER_PRIVILEGE & senv_illegal); // 执行连续赋值，把组合逻辑连接到目标信号。

        assign nomatch_fault = tlb.done & ~|sub_unit_address_match; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign late_exception = tlb.is_fault | nomatch_fault; // 执行连续赋值，把组合逻辑连接到目标信号。

        //Hold writeback exceptions until they are ready to retire
        logic rd_zero_r; // 声明信号、变量或生成变量。
        logic delay_exception; // 声明信号、变量或生成变量。
        logic delayed_exception; // 声明信号、变量或生成变量。
        assign delay_exception = ( // 执行连续赋值，把组合逻辑连接到目标信号。
            (issue.new_request & unaligned_addr & (issue_attr.is_load | issue_attr.is_amo) & issue.id != retire_id & ~issue_attr.rd_zero) |
            (late_exception & tlb_lq & exception_id != retire_id & ~rd_zero_r)
        );
        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) // 执行条件判断，满足条件时进入对应分支。
                delayed_exception <= 0;
            else if (delay_exception) // 执行否则如果分支的条件判断。
                delayed_exception <= 1;
            else if (new_exception) // 执行否则如果分支的条件判断。
                delayed_exception <= 0;
        end // 结束语句块。

        assign new_exception = ( // 执行连续赋值，把组合逻辑连接到目标信号。
            (issue.new_request & ((unaligned_addr & issue_attr.is_store) | illegal_cbo)) |
            (issue.new_request & unaligned_addr & (issue_attr.is_load | issue_attr.is_amo) & (issue.id == retire_id | issue_attr.rd_zero)) |
            (late_exception & ~tlb_lq) |
            (late_exception & tlb_lq & (exception_id == retire_id | rd_zero_r)) |
            (delayed_exception & exception_id == retire_id)
        );

        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) // 执行条件判断，满足条件时进入对应分支。
                exception.valid <= 0;
            else // 执行否则分支。
                exception.valid <= new_exception;
        end // 结束语句块。

        logic is_load; // 声明信号、变量或生成变量。
        logic is_load_r; // 声明信号、变量或生成变量。
        assign is_load = issue_attr.is_load & ~(issue_attr.is_amo & issue_attr.amo_type != AMO_LR_FN5); // 执行连续赋值，把组合逻辑连接到目标信号。

        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            exception_lsq_push <= issue.new_request & ((unaligned_addr & ~issue_attr.is_fence & ~issue_attr.is_cbo) | illegal_cbo);
            if (issue.new_request) begin // 执行条件判断，满足条件时进入对应分支。
                rd_zero_r <= issue_attr.rd_zero;
                exception_is_fp <= CONFIG.INCLUDE_UNIT.FPU & issue_attr.is_fpu;
                is_load_r <= is_load;
                if (illegal_cbo) begin // 执行条件判断，满足条件时进入对应分支。
                    exception.code <= ILLEGAL_INST;
                    exception.tval <= issue_stage.instruction;
                end else begin // 结束语句块。
                    exception.code <= is_load ? LOAD_ADDR_MISSALIGNED : STORE_AMO_ADDR_MISSALIGNED;
                    exception.tval <= virtual_address;
                end // 结束语句块。
                exception_id <= issue.id;
            end // 结束语句块。
            else if (tlb.is_fault) // 执行否则如果分支的条件判断。
                exception.code <= is_load_r ? LOAD_PAGE_FAULT : STORE_OR_AMO_PAGE_FAULT;
            else if (nomatch_fault) // 执行否则如果分支的条件判断。
                exception.code <= is_load_r ? LOAD_FAULT : STORE_AMO_FAULT;
        end // 结束语句块。
        assign exception.possible = (tlb_request_r & (~tlb.done | ~|sub_unit_address_match)) | exception.valid | delayed_exception; //Must suppress issue for issue-time exceptions too；执行连续赋值，把组合逻辑连接到目标信号。
        assign exception.pc = issue_stage.pc_r; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign exception.discard = tlb_lq & ~rd_zero_r; // 执行连续赋值，把组合逻辑连接到目标信号。

        assign exception_is_store = ~tlb_lq; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

    ////////////////////////////////////////////////////
    //Load-Store status
    assign load_store_status = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        outstanding_store : ~lsq.sq_empty | write_outstanding,
        idle : lsq.empty & (~load_attributes.valid) & (&unit_ready) & (~write_outstanding)
    };

    ////////////////////////////////////////////////////
    //Address calculation
    assign virtual_address = rf[RS1] + 32'(signed'(issue_attr.offset)); // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //TLB interface
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            tlb_request_r <= 0;
        else if (tlb.new_request) // 执行否则如果分支的条件判断。
            tlb_request_r <= 1;
        else if (tlb.done | tlb.is_fault) // 执行否则如果分支的条件判断。
            tlb_request_r <= 0;
    end // 结束语句块。

    assign tlb.rnw = issue_attr.is_load | (issue_attr.is_amo & issue_attr.amo_type == AMO_LR_FN5) | issue_attr.is_cbo; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign tlb.virtual_address = virtual_address; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign tlb.new_request = issue.new_request & ~issue_attr.is_fence & (~unaligned_addr | issue_attr.is_cbo) & ~illegal_cbo; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Byte enable generation
    //Only set on store
    //  SW: all bytes
    //  SH: upper or lower half of bytes
    //  SB: specific byte
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        be = 0;
        case(issue_stage.fn3[1:0]) // 开始多分支选择，根据表达式选择对应分支。
            LS_B_fn3[1:0] : be[virtual_address[1:0]] = 1;
            LS_H_fn3[1:0] : begin
                be[virtual_address[1:0]] = 1;
                be[{virtual_address[1], 1'b1}] = 1;
            end // 结束语句块。
            default : be = '1; // 执行默认分支。
        endcase // 结束多分支选择。
        if (issue_attr.is_cbo) //Treat CBOM as writes that don't do anything；执行条件判断，满足条件时进入对应分支。
            be = '0;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Load Store Queue
    assign lsq.data_in = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        offset : virtual_address[11:0],
        fn3 : issue_stage.fn3,
        be : be,
        data : rf[RS2],
        load : issue_attr.is_load | issue_attr.is_amo,
        store : issue_attr.is_store,
        cache_op : issue_attr.is_cbo,
        amo : issue_attr.is_amo,
        amo_type : issue_attr.amo_type,
        id : issue.id,
        id_needed : rd_attributes.id,
        fp : issue_attr.is_fpu,
        double : issue_attr.is_double,
        fp_data : fp_rf[RS2]
    };

    assign lsq.potential_push = issue.possible_issue; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign lsq.push = issue.new_request & ~issue_attr.is_fence; // 执行连续赋值，把组合逻辑连接到目标信号。

    load_store_queue  # (.CONFIG(CONFIG)) lsq_block (
        .clk (clk),
        .rst (rst),
        .gc (gc),
        .lsq (lsq),
        .store_forward_wb_group (rs2_inuse ? rd_attributes.wb_group : '0),
        .fp_store_forward_wb_group ({fp_rs2_inuse & rd_attributes.fp_wb_group, fp_rs2_inuse & ~rd_attributes.fp_wb_group}),
        .wb_packet (wb_packet),
        .fp_wb_packet (fp_wb_packet),
        .store_retire (store_retire)
    );
    assign shared_inputs = sel_load ? lsq.load_data_out : lsq.store_data_out; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign lsq.load_pop = sub_unit_load_issue; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign lsq.store_pop = sub_unit_store_issue; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Physical address passed separately
    assign lsq.addr_push = tlb.done | tlb.is_fault | exception_lsq_push; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign lsq.addr_data_in = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        addr : tlb.physical_address[31:12],
        rnw : tlb_lq,
        discard : late_exception | exception_lsq_push,
        subunit : padded_subunit_id
    };

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
            tlb_lq <= ~issue_attr.is_store & ~issue_attr.is_cbo;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Unit tracking
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (load_attributes.push) // 执行条件判断，满足条件时进入对应分支。
            last_unit <= subunit_id;
    end // 结束语句块。

    //When switching units, ensure no outstanding loads so that there can be no timing collisions with results
    assign unit_switch = lsq.load_valid & (subunit_id != last_unit) & load_attributes.valid; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        unit_switch_in_progress <= (unit_switch_in_progress | unit_switch) & ~load_attributes.valid;
    end // 结束语句块。
    assign unit_switch_hold = unit_switch | unit_switch_in_progress | fiom_amo_hold; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Primary Control Signals
    assign sel_load = lsq.load_valid; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign sub_unit_ready = unit_ready[subunit_id] & (~unit_switch_hold); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign load_response = |unit_data_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign load_complete = load_response & (~exception.valid | exception_is_store); // 执行连续赋值，把组合逻辑连接到目标信号。

    //TLB status and exceptions can be ignored because they will prevent instructions from issuing
    assign issue.ready = ~lsq.full & ~fence_hold; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign sub_unit_load_issue = sel_load & lsq.load_valid & sub_unit_ready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sub_unit_store_issue = (lsq.store_valid & ~sel_load) & sub_unit_ready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sub_unit_issue = sub_unit_load_issue | sub_unit_store_issue; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign write_outstanding = |unit_write_outstanding; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            fence_hold <= 0;
        else // 执行否则分支。
            fence_hold <= (fence_hold & ~load_store_status.idle) | (issue.new_request & issue_attr.is_fence & (issue_attr.nontrivial_fence | fiom));
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Load attributes FIFO
    logic [1:0] final_mux_sel; // 声明信号、变量或生成变量。

    assign subunit_id = shared_inputs.subunit[NUM_SUB_UNITS_W-1:0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    one_hot_to_integer #(NUM_SUB_UNITS)
    sub_unit_select (
        .one_hot (sub_unit_address_match),
        .int_out (padded_subunit_id[NUM_SUB_UNITS_W-1:0])
    );

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case(lsq.load_data_out.fn3) // 开始多分支选择，根据表达式选择对应分支。
            LS_B_fn3, L_BU_fn3 : final_mux_sel = 0;
            LS_H_fn3, L_HU_fn3 : final_mux_sel = 1;
            default : final_mux_sel = 2; //LS_W_fn3；执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。
    
    assign load_attributes.data_in = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        is_signed : ~|lsq.load_data_out.fn3[2:1],
        byte_addr : lsq.load_data_out.addr[1:0],
        sign_sel : lsq.load_data_out.addr[1:0] | {1'b0, lsq.load_data_out.fn3[0]},//halfword
        final_mux_sel : final_mux_sel,
        id : lsq.load_data_out.id,
        subunit_id : subunit_id,
        fp_op : lsq.load_data_out.fp_op
    };
    assign load_attributes.push = sub_unit_load_issue; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign load_attributes.potential_push = load_attributes.push; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    cva5_fifo #(.DATA_TYPE(load_attributes_t), .FIFO_DEPTH(ATTRIBUTES_DEPTH))
    attributes_fifo (
        .clk (clk),
        .rst (rst),
        .fifo (load_attributes)
    );

    assign load_attributes.pop = load_complete; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb_attr = load_attributes.data_out; // 执行连续赋值，把组合逻辑连接到目标信号。
    ////////////////////////////////////////////////////
    //Unit Instantiation
    generate for (genvar i=0; i < NUM_SUB_UNITS; i++) begin : gen_load_store_sources // 开始生成块，在编译期展开硬件结构。
        assign sub_unit[i].new_request = sub_unit_issue & subunit_id == i; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign sub_unit[i].addr = shared_inputs.addr; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign sub_unit[i].re = shared_inputs.load; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign sub_unit[i].we = shared_inputs.store; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign sub_unit[i].be = shared_inputs.be; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign sub_unit[i].data_in = shared_inputs.data_in; // 执行连续赋值，把组合逻辑连接到目标信号。

        assign unit_ready[i] = sub_unit[i].ready; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign unit_data_valid[i] = sub_unit[i].data_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign unit_data_array[i] = sub_unit[i].data_out; // 执行连续赋值，把组合逻辑连接到目标信号。
    end // 结束语句块。
    endgenerate // 结束生成块。

    generate if (CONFIG.INCLUDE_DLOCAL_MEM) begin : gen_ls_local_mem // 开始生成块，在编译期展开硬件结构。
        assign sub_unit_address_match[LOCAL_MEM_ID] = dlocal_mem_addr_utils.address_range_check(tlb.physical_address); // 执行连续赋值，把组合逻辑连接到目标信号。
        local_mem_sub_unit d_local_mem (
            .clk (clk),
            .rst (rst),
            .write_outstanding (unit_write_outstanding[LOCAL_MEM_ID]),
            .amo (shared_inputs.amo),
            .amo_type (shared_inputs.amo_type),
            .amo_unit (amo_if[LOCAL_MEM_ID]),
            .unit (sub_unit[LOCAL_MEM_ID]),
            .local_mem (data_bram)
        );
        end // 结束语句块。
    endgenerate // 结束生成块。

    generate if (CONFIG.INCLUDE_PERIPHERAL_BUS) begin : gen_ls_pbus // 开始生成块，在编译期展开硬件结构。
            assign sub_unit_address_match[BUS_ID] = dpbus_addr_utils.address_range_check(tlb.physical_address); // 执行连续赋值，把组合逻辑连接到目标信号。
            if(CONFIG.PERIPHERAL_BUS_TYPE == AXI_BUS) begin : gen_axi // 执行条件判断，满足条件时进入对应分支。
                axi_master axi_bus (
                    .clk (clk),
                    .rst (rst),
                    .write_outstanding (unit_write_outstanding[BUS_ID]),
                    .m_axi (m_axi),
                    .amo (shared_inputs.amo),
                    .amo_type (shared_inputs.amo_type),
                    .amo_unit (amo_if[BUS_ID]),
                    .ls (sub_unit[BUS_ID])
                ); //Lower two bits of fn3 match AXI specification for request size (byte/halfword/word)
            end else if (CONFIG.PERIPHERAL_BUS_TYPE == WISHBONE_BUS) begin : gen_wishbone // 结束语句块。
                wishbone_master #(.LR_WAIT(CONFIG.AMO_UNIT.LR_WAIT), .INCLUDE_AMO(CONFIG.INCLUDE_AMO)) wishbone_bus (
                    .clk (clk),
                    .rst (rst),
                    .write_outstanding (unit_write_outstanding[BUS_ID]),
                    .wishbone (dwishbone),
                    .amo (shared_inputs.amo),
                    .amo_type (shared_inputs.amo_type),
                    .amo_unit (amo_if[BUS_ID]),
                    .ls (sub_unit[BUS_ID])
                );
            end else if (CONFIG.PERIPHERAL_BUS_TYPE == AVALON_BUS) begin : gen_avalon // 结束语句块。
                avalon_master #(.LR_WAIT(CONFIG.AMO_UNIT.LR_WAIT), .INCLUDE_AMO(CONFIG.INCLUDE_AMO)) avalon_bus (
                    .clk (clk),
                    .rst (rst),
                    .write_outstanding (unit_write_outstanding[BUS_ID]),
                    .m_avalon (m_avalon),
                    .amo (shared_inputs.amo),
                    .amo_type (shared_inputs.amo_type),
                    .amo_unit (amo_if[BUS_ID]),
                    .ls (sub_unit[BUS_ID])
                );
            end // 结束语句块。
        end // 结束语句块。
    endgenerate // 结束生成块。

    generate if (CONFIG.INCLUDE_DCACHE) begin : gen_ls_dcache // 开始生成块，在编译期展开硬件结构。
            logic uncacheable_load; // 声明信号、变量或生成变量。
            logic uncacheable_store; // 声明信号、变量或生成变量。

            assign sub_unit_address_match[DCACHE_ID] = dcache_addr_utils.address_range_check(tlb.physical_address); // 执行连续赋值，把组合逻辑连接到目标信号。

            assign uncacheable_load = CONFIG.DCACHE.USE_NON_CACHEABLE & uncacheable_utils.address_range_check(shared_inputs.addr); // 执行连续赋值，把组合逻辑连接到目标信号。
            assign uncacheable_store = CONFIG.DCACHE.USE_NON_CACHEABLE & uncacheable_utils.address_range_check(shared_inputs.addr); // 执行连续赋值，把组合逻辑连接到目标信号。

            if (CONFIG.DCACHE.USE_EXTERNAL_INVALIDATIONS) begin : gen_full_dcache // 执行条件判断，满足条件时进入对应分支。
                dcache_inv #(.CONFIG(CONFIG)) data_cache (
                    .mem(mem),
                    .write_outstanding(unit_write_outstanding[DCACHE_ID]),
                    .amo(shared_inputs.amo),
                    .amo_type(shared_inputs.amo_type),
                    .amo_unit(amo_if[DCACHE_ID]),
                    .uncacheable(uncacheable_load | uncacheable_store),
                    .cbo(shared_inputs.cache_op),
                    .ls(sub_unit[DCACHE_ID]),
                    .load_peek(lsq.load_valid),
                    .load_addr_peek(lsq.load_data_out.addr),
                .*);
            end else begin : gen_small_dcache // 结束语句块。
                dcache_noinv #(.CONFIG(CONFIG)) data_cache (
                    .mem(mem),
                    .write_outstanding(unit_write_outstanding[DCACHE_ID]),
                    .amo(shared_inputs.amo),
                    .amo_type(shared_inputs.amo_type),
                    .amo_unit(amo_if[DCACHE_ID]),
                    .uncacheable(uncacheable_load | uncacheable_store),
                    .cbo(shared_inputs.cache_op),
                    .ls(sub_unit[DCACHE_ID]),
                    .load_peek(lsq.load_valid),
                    .load_addr_peek(lsq.load_data_out.addr),
                .*);
            end // 结束语句块。
        end // 结束语句块。
    endgenerate // 结束生成块。

    generate if (CONFIG.INCLUDE_AMO) begin : gen_amo // 开始生成块，在编译期展开硬件结构。
        amo_unit #(
            .NUM_UNITS(NUM_SUB_UNITS),
            .RESERVATION_WORDS(CONFIG.AMO_UNIT.RESERVATION_WORDS)
        ) amo_inst (
            .agents(amo_if),
        .*);
    end endgenerate // 结束语句块。

    ////////////////////////////////////////////////////
    //Output Muxing
    logic sign_bit_data [4]; // 声明信号、变量或生成变量。
    logic sign_bit; // 声明信号、变量或生成变量。
    
    assign unit_muxed_load_data = unit_data_array[wb_attr.subunit_id]; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Byte/halfword select: assumes aligned operations
    assign aligned_load_data[31:16] = unit_muxed_load_data[31:16]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign aligned_load_data[15:8] = wb_attr.byte_addr[1] ? unit_muxed_load_data[31:24] : unit_muxed_load_data[15:8]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign aligned_load_data[7:0] = unit_muxed_load_data[wb_attr.byte_addr*8 +: 8]; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign sign_bit_data = '{unit_muxed_load_data[7], unit_muxed_load_data[15], unit_muxed_load_data[23], unit_muxed_load_data[31]}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sign_bit = wb_attr.is_signed & sign_bit_data[wb_attr.sign_sel]; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Sign extending
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case(wb_attr.final_mux_sel) // 开始多分支选择，根据表达式选择对应分支。
            0 : final_load_data = {{24{sign_bit}}, aligned_load_data[7:0]};
            1 : final_load_data = {{16{sign_bit}}, aligned_load_data[15:0]};
            default : final_load_data = aligned_load_data; //LS_W_fn3；执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

    //FP buffering first load result
    logic[FLEN-1:0] fp_result; // 声明信号、变量或生成变量。
    generate if (CONFIG.INCLUDE_UNIT.FPU && FLEN > 32) begin : gen_fp_load_buffering // 开始生成块，在编译期展开硬件结构。
        logic[31:0] saved_msb; // 声明信号、变量或生成变量。
        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) // 执行条件判断，满足条件时进入对应分支。
                saved_msb <= '1;
            else begin // 执行否则分支。
                if (load_complete & wb_attr.fp_op == DOUBLE_HOLD) // 执行条件判断，满足条件时进入对应分支。
                    saved_msb <= unit_muxed_load_data;
                else if (load_complete) //Boxing；执行否则如果分支的条件判断。
                    saved_msb <= '1;
            end // 结束语句块。
        end // 结束语句块。
        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            fp_result = '1;
            fp_result[FLEN-1-:32] = saved_msb;
            if (wb_attr.fp_op == SINGLE_DONE) // 执行条件判断，满足条件时进入对应分支。
                fp_result[FLEN_F-1:0] = unit_muxed_load_data[31-:FLEN_F];
            else // 执行否则分支。
                fp_result[FLEN-33:0] = unit_muxed_load_data[31-:FLEN-32];
        end // 结束语句块。
    end else if (CONFIG.INCLUDE_UNIT.FPU) begin : gen_fpu_no_buffering // 结束语句块。
        //No buffering ever required - all results are final
        assign fp_result = wb_attr.fp_op == SINGLE_DONE ? {{(FLEN-FLEN_F){1'b1}}, unit_muxed_load_data[31-:FLEN_F]} : unit_muxed_load_data[31-:FLEN]; // 执行连续赋值，把组合逻辑连接到目标信号。
    end // 结束语句块。
    else begin : gen_no_fpu // 执行否则分支。
        assign fp_result = 'x; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

    ////////////////////////////////////////////////////
    //Output bank
    assign wb.rd = final_load_data; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.done = (load_complete & (~CONFIG.INCLUDE_UNIT.FPU | wb_attr.fp_op == INT_DONE)) | (exception.valid & ~exception_is_fp & ~exception_is_store); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.id = exception.valid & ~exception_is_store ? exception_id : wb_attr.id; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign fp_wb.rd = fp_result; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_wb.done = (load_complete & (wb_attr.fp_op == SINGLE_DONE | wb_attr.fp_op == DOUBLE_DONE)) | (exception.valid & exception_is_fp & ~exception_is_store); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_wb.id = exception.valid & ~exception_is_store ? exception_id : wb_attr.id; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions
    spurious_load_complete_assertion:
        assert property (@(posedge clk) disable iff (rst) load_complete |-> (load_attributes.valid && unit_data_valid[wb_attr.subunit_id])) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("Spurious load complete detected!"); // 执行否则分支。


endmodule // 结束模块定义。
