// ============================================================================
// 文件：core/types_and_interfaces/cva5_types.sv
// 类型：package
// 名称：cva5_types
// 作用：定义 CVA5 流水线包、退休端口、写回、异常和内部数据结构。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017-2020 Eric Matthews,  Lesley Shannon
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

package cva5_types; // 定义 cva5_types 包。
    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import csr_types::*; // 导入包或命名空间：csr_types::*;。

    localparam LOG2_RETIRE_PORTS = $clog2(RETIRE_PORTS); // 声明局部常量。
    localparam LOG2_MAX_IDS = $clog2(MAX_IDS); // 声明局部常量。
    localparam MAX_LS_SUBUNITS = 3; // 声明局部常量。

// 定义类型别名或枚举/结构类型。
    typedef logic[LOG2_MAX_IDS-1:0] id_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[$clog2(MAX_LS_SUBUNITS)-1:0] ls_subunit_t;

// 定义类型别名或枚举/结构类型。
    typedef logic [3:0] addr_hash_t;
// 定义类型别名或枚举/结构类型。
    typedef logic [5:0] phys_addr_t;

// 定义类型别名或枚举/结构类型。
    typedef enum logic [1:0] {
        ALU_CONSTANT = 2'b00,
        ALU_ADD_SUB = 2'b01,
        ALU_SLT = 2'b10,
        ALU_SHIFT = 2'b11
    } alu_op_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic valid; // 声明信号、变量或生成变量。
        logic possible; // 声明信号、变量或生成变量。
        logic [NUM_EXCEPTION_SOURCES-1:0] source; // 声明信号、变量或生成变量。
        exception_code_t code;
        logic [31:0] tval; // 声明信号、变量或生成变量。
        logic [31:0] pc; // 声明信号、变量或生成变量。
        id_t id;
    } exception_packet_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic ok; // 声明信号、变量或生成变量。
        exception_code_t error_code;
    } fetch_metadata_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        id_t id;
        logic [31:0] pc; // 声明信号、变量或生成变量。
        logic [31:0] instruction; // 声明信号、变量或生成变量。
        logic valid; // 声明信号、变量或生成变量。
        fetch_metadata_t fetch_metadata;
    } decode_packet_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic [31:0] pc; // 声明信号、变量或生成变量。
        logic [31:0] pc_r; // 声明信号、变量或生成变量。
        logic [31:0] instruction; // 声明信号、变量或生成变量。
        logic [31:0] instruction_r; // 声明信号、变量或生成变量。
        logic [2:0] fn3; // 声明信号、变量或生成变量。
        logic [6:0] opcode; // 声明信号、变量或生成变量。

        rs_addr_t rd_addr;
        phys_addr_t phys_rd_addr;
        phys_addr_t fp_phys_rd_addr;

        logic uses_rd; // 声明信号、变量或生成变量。
        logic fp_uses_rd; // 声明信号、变量或生成变量。
        logic is_multicycle; // 声明信号、变量或生成变量。
        id_t id;
        logic stage_valid; // 声明信号、变量或生成变量。
        fetch_metadata_t fetch_metadata;
    } issue_packet_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        id_t id;
        logic valid; // 声明信号、变量或生成变量。
        logic [31:0] pc; // 声明信号、变量或生成变量。
        logic [31:0] target_pc; // 声明信号、变量或生成变量。
        logic branch_taken; // 声明信号、变量或生成变量。
        logic is_branch; // 声明信号、变量或生成变量。
        logic is_return; // 声明信号、变量或生成变量。
        logic is_call; // 声明信号、变量或生成变量。
    } branch_results_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic [XLEN-1:0] rs1_load; // 声明信号、变量或生成变量。
        logic [XLEN-1:0] rs2; // 声明信号、变量或生成变量。
        logic [4:0] op; // 声明信号、变量或生成变量。
    }amo_alu_inputs_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [11:0] offset; // 声明信号、变量或生成变量。
        logic load; // 声明信号、变量或生成变量。
        logic store; // 声明信号、变量或生成变量。
        logic cache_op; // 声明信号、变量或生成变量。
        logic amo; // 声明信号、变量或生成变量。
        amo_t amo_type;
        logic [3:0] be; // 声明信号、变量或生成变量。
        logic [2:0] fn3; // 声明信号、变量或生成变量。
        logic [31:0] data; // 声明信号、变量或生成变量。
        id_t id;
        id_t id_needed;
        logic fp; // 声明信号、变量或生成变量。
        logic double; // 声明信号、变量或生成变量。
        logic [FLEN-1:0] fp_data; // 声明信号、变量或生成变量。
    } lsq_entry_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [19:0] addr; // 声明信号、变量或生成变量。
        logic rnw; // 声明信号、变量或生成变量。
        logic discard; // 声明信号、变量或生成变量。
        ls_subunit_t subunit;
    } lsq_addr_entry_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [11:0] offset; // 声明信号、变量或生成变量。
        logic [3:0] be; // 声明信号、变量或生成变量。
        logic cache_op; // 声明信号、变量或生成变量。
        logic [31:0] data; // 声明信号、变量或生成变量。
        logic fp; // 声明信号、变量或生成变量。
        logic double; // 声明信号、变量或生成变量。
        logic [FLEN-1:0] fp_data; // 声明信号、变量或生成变量。
    } sq_entry_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic outstanding_store; // 声明信号、变量或生成变量。
        logic idle; // 声明信号、变量或生成变量。
    } load_store_status_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        id_t id;
        logic valid; // 声明信号、变量或生成变量。
        logic [31:0] data; // 声明信号、变量或生成变量。
    } wb_packet_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        id_t id;
        logic valid; // 声明信号、变量或生成变量。
        logic[FLEN-1:0] data; // 声明信号、变量或生成变量。
    } fp_wb_packet_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        id_t id;
        logic valid; // 声明信号、变量或生成变量。
    } retire_packet_t;

// 定义类型别名或枚举/结构类型。
    typedef enum logic[1:0] {
        INT_DONE,
        SINGLE_DONE,
        DOUBLE_HOLD,
        DOUBLE_DONE
    } fp_ls_op_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [31:0] addr; // 声明信号、变量或生成变量。
        logic load; // 声明信号、变量或生成变量。
        logic store; // 声明信号、变量或生成变量。
        logic cache_op; // 声明信号、变量或生成变量。
        logic amo; // 声明信号、变量或生成变量。
        amo_t amo_type;
        logic [3:0] be; // 声明信号、变量或生成变量。
        logic [2:0] fn3; // 声明信号、变量或生成变量。
        ls_subunit_t subunit;
        logic [31:0] data_in; // 声明信号、变量或生成变量。
        id_t id;
        fp_ls_op_t fp_op;
    } data_access_shared_inputs_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic valid; // 声明信号、变量或生成变量。
        logic asid_only; // 声明信号、变量或生成变量。
        logic[ASIDLEN-1:0] asid; // 声明信号、变量或生成变量。
        logic addr_only; // 声明信号、变量或生成变量。
        logic[31:0] addr; // 声明信号、变量或生成变量。
    } tlb_packet_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic init_clear; // 声明信号、变量或生成变量。
        logic fetch_hold; // 声明信号、变量或生成变量。
        logic issue_hold; // 声明信号、变量或生成变量。
        logic fetch_flush; // 声明信号、变量或生成变量。
        logic fetch_ifence; // 声明信号、变量或生成变量。
        logic writeback_suppress; // 声明信号、变量或生成变量。
        logic rename_revert; // 声明信号、变量或生成变量。
        exception_packet_t exception;
        logic pc_override; // 声明信号、变量或生成变量。
        logic [31:0] pc; // 声明信号、变量或生成变量。
    } gc_outputs_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic software; // 声明信号、变量或生成变量。
        logic timer; // 声明信号、变量或生成变量。
        logic external; // 声明信号、变量或生成变量。
    } interrupt_t;
    
// 定义类型别名或枚举/结构类型。
    typedef enum {
        FETCH_EARLY_BR_CORRECTION_STAT,
        FETCH_SUB_UNIT_STALL_STAT,
        FETCH_ID_STALL_STAT,
        FETCH_IC_HIT_STAT,
        FETCH_IC_MISS_STAT,
        FETCH_IC_ARB_STALL_STAT,

        FETCH_BP_BR_CORRECT_STAT,
        FETCH_BP_BR_MISPREDICT_STAT,
        FETCH_BP_RAS_CORRECT_STAT,
        FETCH_BP_RAS_MISPREDICT_STAT,

        ISSUE_NO_INSTRUCTION_STAT,
        ISSUE_NO_ID_STAT,
        ISSUE_FLUSH_STAT,
        ISSUE_UNIT_BUSY_STAT,
        ISSUE_OPERANDS_NOT_READY_STAT,
        ISSUE_HOLD_STAT,
        ISSUE_MULTI_SOURCE_STAT,
        ISSUE_OPERAND_STALL_ON_LOAD_STAT,
        ISSUE_OPERAND_STALL_ON_MULTIPLY_STAT,
        ISSUE_OPERAND_STALL_ON_DIVIDE_STAT,
        ISSUE_OPERAND_STALL_FOR_BRANCH_STAT,
        ISSUE_STORE_WITH_FORWARDED_DATA_STAT,
        ISSUE_DIVIDER_RESULT_REUSE_STAT,

        LSU_LOAD_BLOCKED_BY_STORE_STAT,
        LSU_SUB_UNIT_STALL_STAT,
        LSU_DC_HIT_STAT,
        LSU_DC_MISS_STAT,
        LSU_DC_ARB_STALL_STAT
    } stats_t;

// 定义类型别名或枚举/结构类型。
    typedef enum {
        ALU_STAT,
        BR_STAT,
        MUL_STAT,
        DIV_STAT,
        LOAD_STAT,
        STORE_STAT,
        FPU_STAT,
        MISC_STAT
    } instruction_mix_stats_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [31:0] pc; // 声明信号、变量或生成变量。
        logic [31:0] instruction; // 声明信号、变量或生成变量。
        logic valid; // 声明信号、变量或生成变量。
    } trace_retire_outputs_t;

endpackage // 结束包定义。
