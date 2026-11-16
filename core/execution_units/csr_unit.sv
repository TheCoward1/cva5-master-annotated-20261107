// ============================================================================
// 文件：core/execution_units/csr_unit.sv
// 类型：module
// 名称：csr_unit
// 作用：实现 CSR 寄存器、特权模式、异常、中断和计数器逻辑。
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

module csr_unit // 定义 csr_unit 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    import csr_types::*; // 导入包或命名空间：csr_types::*;。
    import opcodes::*; // 导入包或命名空间：opcodes::*;。

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG // 声明可配置参数。
    )

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        input decode_packet_t decode_stage, // 声明输入端口。
        output logic unit_needed, // 声明输出端口。
        output logic [REGFILE_READ_PORTS-1:0] uses_rs, // 声明输出端口。
        output logic uses_rd, // 声明输出端口。

        input issue_packet_t issue_stage, // 声明输入端口。
        input logic issue_stage_ready, // 声明输入端口。
        input rs_addr_t issue_rs_addr [REGFILE_READ_PORTS], // 声明输入端口。
        input logic [31:0] rf [REGFILE_READ_PORTS], // 声明输入端口。
        input logic instruction_issued, // 声明输入端口。
        input logic fp_instruction_issued_with_rd, // 声明输入端口。

        //Unit Interfaces
        unit_issue_interface.unit issue,
        unit_writeback_interface.unit wb,

        //Privilege
        output logic [1:0] current_privilege, // 声明输出端口。
        output envcfg_t menvcfg, // 声明输出端口。
        output envcfg_t senvcfg, // 声明输出端口。
        
        //FP
        input logic [4:0] fflag_wmask, //Always valid；声明输入端口。
        output logic [2:0] dyn_rm, // 声明输出端口。

        //GC
        input logic interrupt_taken, // 声明输入端口。
        output logic interrupt_pending, // 声明输出端口。
        output logic csr_frontend_flush, // 声明输出端口。

        //TLB and MMU
        output logic instruction_translation_on, // 声明输出端口。
        output logic data_translation_on, // 声明输出端口。
        output logic [ASIDLEN-1:0] asid, // 声明输出端口。

        //MMUs
        mmu_interface.csr immu,
        mmu_interface.csr dmmu,

        //CSR exception interface
        input exception_packet_t exception_pkt, // 声明输入端口。
        output logic [31:0] exception_target_pc, // 声明输出端口。

        //exception return
        input logic mret, // 声明输入端口。
        input logic sret, // 声明输入端口。
        output logic [31:0] mepc, // 声明输出端口。
        output logic [31:0] sepc, // 声明输出端口。
        
        //Exception generation
        exception_interface.unit exception,

        //Retire
        input id_t retire_ids [RETIRE_PORTS], // 声明输入端口。

        //External
        input logic [63:0] mtime, // 声明输入端口。
        input interrupt_t s_interrupt, // 声明输入端口。
        input interrupt_t m_interrupt // 声明输入端口。
        );

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        csr_addr_t addr;
        logic[1:0] op; // 声明信号、变量或生成变量。
        logic reads; // 声明信号、变量或生成变量。
        logic writes; // 声明信号、变量或生成变量。
        logic [31:0] data; // 声明信号、变量或生成变量。
    } csr_inputs_t;

// 定义类型别名或枚举/结构类型。
    typedef enum logic [2:0] {
        MSTATUS_UNCHANGED = 0,
        MSTATUS_WRITE = 1,
        MSTATUS_INTERRUPT = 2,
        MSTATUS_EXCEPTION = 3,
        MSTATUS_MRET = 4,
        MSTATUS_SRET = 5
    } mstatus_cases_t;
    mstatus_cases_t mstatus_case;

    logic busy; // 声明信号、变量或生成变量。
    logic commit; // 声明信号、变量或生成变量。
    logic commit_in_progress; // 声明信号、变量或生成变量。

    csr_inputs_t csr_inputs;
    csr_inputs_t csr_inputs_r;

    privilege_t privilege_level;
    privilege_t next_privilege_level;

    //write_logic
    logic swrite; // 声明信号、变量或生成变量。
    logic mwrite; // 声明信号、变量或生成变量。
    logic [255:0] sub_write_en; // 声明信号、变量或生成变量。
    logic illegal_instruction; // 声明信号、变量或生成变量。

    logic [31:0] selected_csr; // 声明信号、变量或生成变量。
    logic [31:0] selected_csr_r; // 声明信号、变量或生成变量。

    logic [31:0] updated_csr; // 声明信号、变量或生成变量。
    logic [31:0] next_csr; // 声明信号、变量或生成变量。

    logic exception_delegated; // 声明信号、变量或生成变量。
    logic interrupt_delegated; // 声明信号、变量或生成变量。
    logic [ECODE_W-1:0] interrupt_cause; // 声明信号、变量或生成变量。

    function logic mwrite_en (input csr_addr_t addr); // 开始函数定义，用于组合计算或辅助逻辑。
        return mwrite & sub_write_en[addr.sub_addr]; // 返回函数结果。
    endfunction // 结束函数定义。
    function logic swrite_en (input csr_addr_t addr); // 开始函数定义，用于组合计算或辅助逻辑。
        return swrite & sub_write_en[addr.sub_addr]; // 返回函数结果。
    endfunction // 结束函数定义。

    ////////////////////////////////////////////////////
    //Legalization Functions
    function logic [31:0] init_medeleg_mask(); // 开始函数定义，用于组合计算或辅助逻辑。
       init_medeleg_mask = 0;
        if (CONFIG.MODES == MSU) begin // 执行条件判断，满足条件时进入对应分支。
            init_medeleg_mask[INST_ADDR_MISSALIGNED] = 1;
            init_medeleg_mask[INST_ACCESS_FAULT] = 1;
            init_medeleg_mask[ILLEGAL_INST] = 1;
            init_medeleg_mask[BREAK] = 1;
            init_medeleg_mask[LOAD_ADDR_MISSALIGNED] = 1;
            init_medeleg_mask[LOAD_FAULT] = 1;
            init_medeleg_mask[STORE_AMO_ADDR_MISSALIGNED] = 1;
            init_medeleg_mask[STORE_AMO_FAULT] = 1;
            init_medeleg_mask[ECALL_U] = 1;
            init_medeleg_mask[ECALL_S] = 1;
            init_medeleg_mask[INST_PAGE_FAULT] = 1;
            init_medeleg_mask[LOAD_PAGE_FAULT] = 1;
            init_medeleg_mask[STORE_OR_AMO_PAGE_FAULT] = 1;
        end // 结束语句块。
    endfunction // 结束函数定义。


    ////////////////////////////////////////////////////
    //Implementation

    ////////////////////////////////////////////////////
    //Decode
    assign unit_needed = decode_stage.instruction inside {CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI}; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        uses_rs = '0;
        uses_rs[RS1] = decode_stage.instruction inside {CSRRW, CSRRS, CSRRC};
        uses_rd = unit_needed;
    end // 结束语句块。
    ////////////////////////////////////////////////////
    //Issue
    assign csr_inputs = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        addr : issue_stage.instruction[31:20],
        op : issue_stage.fn3[1:0],
        data : issue_stage.fn3[2] ? {27'b0, issue_rs_addr[RS1]} : rf[RS1],
        reads : ~((issue_stage.fn3[1:0] == CSR_RW) & (issue_stage.rd_addr == 0)),
        writes : ~((issue_stage.fn3[1:0] != CSR_RW) & (issue_rs_addr[RS1] == 0))
    };
    
    assign issue.ready = ~busy; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            busy <= 0;
        else // 执行否则分支。
            busy <= (busy & ~wb.ack) | issue.new_request;
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
            csr_inputs_r <= csr_inputs;
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            commit_in_progress <= 0;
        else // 执行否则分支。
            commit_in_progress <= (commit_in_progress & ~issue.new_request) | commit;
    end // 结束语句块。

    //Waits until CSR instruction is the oldest issued instruction
    assign commit = (retire_ids[0] == wb.id) & busy & (~commit_in_progress); // 执行连续赋值，把组合逻辑连接到目标信号。


    ////////////////////////////////////////////////////
    //Output

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            wb.done <= 0;
        else // 执行否则分支。
            wb.done <= (wb.done & ~wb.ack) | commit;
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
            wb.id <= issue.id;
    end // 结束语句块。

    assign wb.rd = selected_csr_r; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Shared logic 
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        sub_write_en <= (1 << csr_inputs_r.addr.sub_addr);
        mwrite <= CONFIG.MODES != BARE & commit & (csr_inputs_r.addr.rw_bits != CSR_READ_ONLY & csr_inputs_r.addr.privilege == MACHINE_PRIVILEGE) & ~illegal_instruction;
        swrite <= CONFIG.MODES == MSU & commit & (csr_inputs_r.addr.rw_bits != CSR_READ_ONLY & csr_inputs_r.addr.privilege == SUPERVISOR_PRIVILEGE) & ~illegal_instruction;
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case (csr_inputs_r.op) // 开始多分支选择，根据表达式选择对应分支。
            CSR_RW : next_csr = csr_inputs_r.data;
            CSR_RS : next_csr = selected_csr | csr_inputs_r.data;
            CSR_RC : next_csr = selected_csr & ~csr_inputs_r.data;
            default : next_csr = csr_inputs_r.data; // 执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (commit) // 执行条件判断，满足条件时进入对应分支。
            updated_csr <= next_csr;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Machine Mode Registers
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Constant Registers

    ////////////////////////////////////////////////////
    //Machine ISA register
    localparam misa_t misa = '{ // 声明局部常量。
        default:0, // 执行默认分支。
        mxlen:1,
        A:(CONFIG.INCLUDE_AMO),
        I:1,
        M:(CONFIG.INCLUDE_UNIT.MUL & CONFIG.INCLUDE_UNIT.DIV),
        S:(CONFIG.MODES == MSU),
        U:(CONFIG.MODES inside {MU, MSU}),
        F:(CONFIG.INCLUDE_UNIT.FPU),
        D:(CONFIG.INCLUDE_UNIT.FPU)
    };

    ////////////////////////////////////////////////////
    //Machine Version Registers
    localparam logic [31:0] mvendorid = 0; // 声明局部常量。
    localparam logic [31:0] marchid = 48; //https://github.com/riscv/riscv-isa-manual/pull/1897；声明局部常量。
    localparam logic [31:0] mimpid = CONFIG.CSRS.MACHINE_IMPLEMENTATION_ID; // 声明局部常量。
    localparam logic [31:0] mhartid = CONFIG.CSRS.CPU_ID; // 声明局部常量。
    localparam logic [31:0] mconfigptr = CONFIG.CSRS.MCONFIGPTR; // 声明局部常量。

    ////////////////////////////////////////////////////
    //Constants
    localparam logic [31:0] mstatush = 0; //Always little endian；声明局部常量。
    localparam logic [31:0] medelegh = 0; //Not used；声明局部常量。
    localparam logic [31:0] mstateen0 = 0; //Behaviour defined but not relevant；声明局部常量。
    localparam logic [31:0] mstateen1 = 0; //Behaviour not yet defined；声明局部常量。
    localparam logic [31:0] mstateen2 = 0; //Behaviour not yet defined；声明局部常量。
    localparam logic [31:0] mstateen3 = 0; //Behaviour not yet defined；声明局部常量。
    localparam logic [31:0] mstateen1h = 0; //Behaviour not yet defined；声明局部常量。
    localparam logic [31:0] mstateen2h = 0; //Behaviour not yet defined；声明局部常量。
    localparam logic [31:0] mstateen3h = 0; //Behaviour not yet defined；声明局部常量。

    ////////////////////////////////////////////////////
    //Non-Constant Registers
    mstatus_t mstatus;
    logic[31:0] mtvec; // 声明信号、变量或生成变量。
    logic[31:0] medeleg; // 声明信号、变量或生成变量。
    mideleg_t mideleg;
    mip_t mip;
    mie_t mie;
    cause_t mcause;
    logic[31:0] mtval; // 声明信号、变量或生成变量。
    logic[31:0] mscratch; // 声明信号、变量或生成变量。
    mcounter_t mcounteren;
    mcounter_t mcountinhibit;
    envcfgh_t menvcfgh;
    mstateen0h_t mstateen0h;

    //Virtualization support: TSR, TW, TVM unused
    //Extension context status: XS unused
    localparam mstatus_t mstatus_mask = '{ // 声明局部常量。
        default:0, // 执行默认分支。
        mprv:(CONFIG.MODES inside {MU, MSU}),
        mxr:(CONFIG.MODES == MSU),
        sum:(CONFIG.MODES == MSU),
        mpp:'1,
        spp:(CONFIG.MODES == MSU),
        mpie:1,
        spie:(CONFIG.MODES == MSU),
        mie:1,
        sie:(CONFIG.MODES == MSU),
        sd:(CONFIG.INCLUDE_UNIT.FPU),
        fs:{2{CONFIG.INCLUDE_UNIT.FPU}}
    };

    localparam mstatus_t sstatus_mask = '{default:0, mxr:1, sum:1, spp:1, spie:1, sie:1, sd:(CONFIG.INCLUDE_UNIT.FPU), fs:{2{CONFIG.INCLUDE_UNIT.FPU}}}; // 声明局部常量。
    logic stip_stimecmp; // 声明信号、变量或生成变量。

    logic[31:0] sie; // 声明信号、变量或生成变量。
    mip_t sip;
    mie_t sie_deleg_mask;
    localparam mie_t sie_mask = '{default:0, seie:CONFIG.MODES == MSU, stie:CONFIG.MODES == MSU, ssie:CONFIG.MODES == MSU}; // 声明局部常量。
    localparam mip_t sip_mask = '{default:0, seip:CONFIG.MODES == MSU, stip:CONFIG.MODES == MSU, ssip:CONFIG.MODES == MSU}; // 声明局部常量。


generate if (CONFIG.MODES != BARE) begin : gen_csr_m_mode // 开始生成块，在编译期展开硬件结构。
    mstatus_t mstatus_new;
    mstatus_t mstatus_write_mask;
    logic[4:0] fflag_wmask_r; //Used for updating mstatus, registered for frequency reasons；声明信号、变量或生成变量。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            fflag_wmask_r <= '0;
        else if (CONFIG.INCLUDE_UNIT.FPU) // 执行否则如果分支的条件判断。
            fflag_wmask_r <= fflag_wmask;
    end // 结束语句块。

    //Interrupt and Exception Delegation
    //Can delegate to supervisor if currently in supervisor or user modes
    logic can_delegate; // 声明信号、变量或生成变量。

    assign can_delegate = CONFIG.MODES == MSU & privilege_level inside {SUPERVISOR_PRIVILEGE, USER_PRIVILEGE}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign exception_delegated = can_delegate & exception_pkt.valid & medeleg[exception_pkt.code]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign interrupt_delegated = can_delegate & interrupt_taken & mideleg[interrupt_cause]; // 执行连续赋值，把组合逻辑连接到目标信号。

    one_hot_to_integer #(6)
    mstatus_case_one_hot (
        .one_hot ({sret, mret, exception_pkt.valid, interrupt_taken, (mwrite_en(MSTATUS) | swrite_en(SSTATUS)), 1'b0}),
        .int_out (mstatus_case)
    );

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case (mstatus_case) inside // 开始多分支选择，根据表达式选择对应分支。
            MSTATUS_MRET : next_privilege_level = privilege_t'(mstatus.mpp);
            MSTATUS_SRET : next_privilege_level = privilege_t'({1'b0,mstatus.spp});
            MSTATUS_INTERRUPT : next_privilege_level = interrupt_delegated ? SUPERVISOR_PRIVILEGE : MACHINE_PRIVILEGE;
            MSTATUS_EXCEPTION : next_privilege_level = exception_delegated ? SUPERVISOR_PRIVILEGE : MACHINE_PRIVILEGE;
            default : next_privilege_level = privilege_level; // 执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

    //Current privilege level
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            privilege_level <= MACHINE_PRIVILEGE;
        else // 执行否则分支。
            privilege_level <= next_privilege_level;
    end // 结束语句块。
    assign current_privilege = privilege_level; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign mstatus_write_mask = swrite ? sstatus_mask : mstatus_mask; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        mstatus_new = mstatus;
        case (mstatus_case) inside // 开始多分支选择，根据表达式选择对应分支。
            MSTATUS_WRITE : begin
                mstatus_new = (mstatus & ~mstatus_write_mask) | (updated_csr & mstatus_write_mask);
                //Cannot write invalid privilege
                if (CONFIG.MODES == M) // 执行条件判断，满足条件时进入对应分支。
                    mstatus_new.mpp = MACHINE_PRIVILEGE;
                else if (CONFIG.MODES == MU & ^mstatus_new.mpp) // 执行否则如果分支的条件判断。
                    mstatus_new.mpp = MACHINE_PRIVILEGE;
                else if (CONFIG.MODES == MSU & mstatus_new.mpp == RESERVED_PRIVILEGE) // 执行否则如果分支的条件判断。
                    mstatus_new.mpp = MACHINE_PRIVILEGE;
            end // 结束语句块。
            MSTATUS_MRET : begin
                mstatus_new.mie = mstatus.mpie;
                mstatus_new.mpie = 1;
                mstatus_new.mpp = CONFIG.MODES inside {MU, MSU} ? USER_PRIVILEGE : MACHINE_PRIVILEGE;
                if (mstatus.mpp != MACHINE_PRIVILEGE) // 执行条件判断，满足条件时进入对应分支。
                    mstatus_new.mprv = 0;
            end // 结束语句块。
            MSTATUS_SRET : begin
                mstatus_new.sie = mstatus.spie;
                mstatus_new.spie = 1;
                mstatus_new.spp = USER_PRIVILEGE[0];
                mstatus_new.mprv = 0;
            end // 结束语句块。
            MSTATUS_INTERRUPT, MSTATUS_EXCEPTION : begin
                if (next_privilege_level == SUPERVISOR_PRIVILEGE) begin // 执行条件判断，满足条件时进入对应分支。
                    mstatus_new.spie = mstatus.sie;
                    mstatus_new.sie = 0;
                    mstatus_new.spp = privilege_level[0]; //one if from supervisor-mode, zero if from user-mode
                end // 结束语句块。
                else begin // 执行否则分支。
                    mstatus_new.mpie = (privilege_level == MACHINE_PRIVILEGE) ? mstatus.mie : ((privilege_level == SUPERVISOR_PRIVILEGE) ? mstatus.sie : 0);
                    mstatus_new.mie = 0;
                    mstatus_new.mpp = privilege_level; //machine,supervisor or user
                end // 结束语句块。
            end // 结束语句块。
            default : mstatus_new = mstatus; // 执行默认分支。
        endcase // 结束多分支选择。

        //Overwrites writes to fs and sd from above
        if (CONFIG.INCLUDE_UNIT.FPU) begin // 执行条件判断，满足条件时进入对应分支。
            if (fp_instruction_issued_with_rd | |fflag_wmask_r | (commit & csr_inputs_r.addr inside {FFLAGS, FRM, FCSR})) begin // 执行条件判断，满足条件时进入对应分支。
                mstatus_new.fs = 2'b11;
                mstatus_new.sd = 1'b1;
            end // 结束语句块。
            else if (mwrite_en(MSTATUS) | swrite_en(SSTATUS)) begin // 执行否则如果分支的条件判断。
                mstatus_new.fs = |updated_csr[14:13] ? updated_csr[14:13] : mstatus.fs; //Cannot disable by writing 00
                mstatus_new.sd = &updated_csr[14:13];
            end // 结束语句块。
            else begin // 执行否则分支。
                mstatus_new.fs = mstatus.fs;
                mstatus_new.sd = mstatus.sd;
            end // 结束语句块。
        end // 结束语句块。
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mstatus <= '{default:0, mpp:MACHINE_PRIVILEGE, fs:{1'b0, CONFIG.INCLUDE_UNIT.FPU}};
        else // 执行否则分支。
            mstatus <= mstatus_new;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MTVEC
    //No vectored mode, mode hard-coded to zero
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        mtvec[1:0] <= '0;
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mtvec[31:2] <= CONFIG.CSRS.RESET_TVEC[31:2];
        else if (mwrite_en(MTVEC)) // 执行否则如果分支的条件判断。
            mtvec[31:2] <= updated_csr[31:2];
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MEDELEG
    localparam logic [31:0] medeleg_mask = init_medeleg_mask(); // 声明局部常量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            medeleg <= '0;
        else if (mwrite_en(MEDELEG) & CONFIG.MODES == MSU) // 执行否则如果分支的条件判断。
            medeleg <= updated_csr & medeleg_mask;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MIDELEG
    localparam mideleg_t mideleg_mask = '{default:0, ssid:CONFIG.MODES == MSU, stid:CONFIG.MODES == MSU, seid:CONFIG.MODES == MSU}; // 声明局部常量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mideleg <= '0;
        else if (mwrite_en(MIDELEG) & CONFIG.MODES == MSU) // 执行否则如果分支的条件判断。
            mideleg <= updated_csr & mideleg_mask;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MIP
    //Bits tracked separately
    logic meip; // 声明信号、变量或生成变量。
    logic mtip; // 声明信号、变量或生成变量。
    logic msip; // 声明信号、变量或生成变量。

    //SIP is part of MIP
    logic seip; // 声明信号、变量或生成变量。
    logic stip; // 声明信号、变量或生成变量。
    logic ssip; // 声明信号、变量或生成变量。

    assign mip = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        meip: meip,
        mtip: mtip,
        msip: msip,
        seip: CONFIG.MODES == MSU & seip,
        stip: CONFIG.MODES == MSU & stip,
        ssip: CONFIG.MODES == MSU & ssip,
        default:0 // 执行默认分支。
    };

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        meip <= m_interrupt.external;
        mtip <= m_interrupt.timer;
        msip <= m_interrupt.software;
    end // 结束语句块。

if (CONFIG.MODES == MSU) begin : gen_supervisor_interrupts // 执行条件判断，满足条件时进入对应分支。
    logic seip_r; // 声明信号、变量或生成变量。
    logic seip_external; // 声明信号、变量或生成变量。
    logic seip_next; // 声明信号、变量或生成变量。
    mip_t seip_next_casted;
    
    //SEIP depends on an external and writable signal
    assign seip_next_casted = mip_t'(csr_inputs_r.data); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign seip = seip_r | seip_external; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        seip_external <= s_interrupt.external;
        case (csr_inputs_r.op) // 开始多分支选择，根据表达式选择对应分支。
            CSR_RW : seip_next <= seip_next_casted.seip;
            CSR_RS : seip_next <= seip_r | seip_next_casted.seip;
            CSR_RC : seip_next <= seip_r & ~seip_next_casted.seip;
            default : seip_next <= seip_next_casted.seip; // 执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

    //STIP set locally, SSIP set locally or externally
    mip_t updated_csr_mip_casted;
    assign updated_csr_mip_casted = mip_t'(updated_csr); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            seip_r <= 0;
            stip <= 0;
            ssip <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            //SEIP
            if (mwrite_en(MIP)) // 执行条件判断，满足条件时进入对应分支。
                seip_r <= seip_next;
            
            //STIP
            if (CONFIG.CSRS.INCLUDE_SSTC & menvcfgh.stce) // 执行条件判断，满足条件时进入对应分支。
                stip <= stip_stimecmp;
            else if (mwrite_en(MIP)) // 执行否则如果分支的条件判断。
                stip <= updated_csr_mip_casted.stip;
            
            //SSIP
            if (s_interrupt.software) // 执行条件判断，满足条件时进入对应分支。
                ssip <= 1;
            else if (mwrite_en(MIP) | (swrite_en(SIP) & mideleg.ssid)) // 执行否则如果分支的条件判断。
                ssip <= updated_csr_mip_casted.ssip;
        end // 结束语句块。
    end // 结束语句块。
end // 结束语句块。

    ////////////////////////////////////////////////////
    //MIE
    localparam mie_t mie_mask = '{default:0, meie:1, mtie:1, msie:1}; // 声明局部常量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mie <= '0;
        else if (mwrite_en(MIE)) // 执行否则如果分支的条件判断。
            mie <= updated_csr & (mie_mask | sie_mask);
        else if (swrite_en(SIE)) // 执行否则如果分支的条件判断。
            mie <= (mie & mie_mask) | (updated_csr & sie_deleg_mask);
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        interrupt_pending = 0;
        //M interrupts
        if (privilege_level != MACHINE_PRIVILEGE | mstatus.mie) // 执行条件判断，满足条件时进入对应分支。
            interrupt_pending |= |(mip & mie & ~mideleg);
        //S interrupts
        if (CONFIG.MODES == MSU & ((privilege_level == SUPERVISOR_PRIVILEGE & mstatus.sie) | privilege_level == USER_PRIVILEGE)) // 执行条件判断，满足条件时进入对应分支。
            interrupt_pending |= |(sip & sie);
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MEPC
    //Can be software written, written on exception with
    //exception causing PC.  Lower two bits tied to zero.
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        mepc[1:0] <= '0;
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mepc[31:2] <= '0;
        else if (mwrite_en(MEPC) | (exception_pkt.valid & ~exception_delegated) | (interrupt_taken & ~interrupt_delegated)) // 执行否则如果分支的条件判断。
            mepc[31:2] <= (exception_pkt.valid | interrupt_taken) ? exception_pkt.pc[31:2] : updated_csr[31:2];
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MCAUSE
    //Can be software written, written on exception or
    //interrupt with specific code
    logic [5:0] mip_priority_vector; // 声明信号、变量或生成变量。
    logic [2:0] mip_cause_sel; // 声明信号、变量或生成变量。

    localparam logic [ECODE_W-1:0] interrupt_code_table [7:0] = '{ 0, 0, // 声明局部常量。
        S_TIMER_INTERRUPT, S_SOFTWARE_INTERRUPT, S_EXTERNAL_INTERRUPT,
        M_TIMER_INTERRUPT, M_SOFTWARE_INTERRUPT, M_EXTERNAL_INTERRUPT
    };

    assign mip_priority_vector[0] = mip.meip & mie.meie; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mip_priority_vector[1] = mip.msip & mie.msie; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mip_priority_vector[2] = mip.mtip & mie.mtie; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mip_priority_vector[3] = mip.seip & mie.seie & ~(privilege_level == MACHINE_PRIVILEGE & mideleg.seid); //Suppressed if delegated；执行连续赋值，把组合逻辑连接到目标信号。
    assign mip_priority_vector[4] = mip.ssip & mie.ssie & ~(privilege_level == MACHINE_PRIVILEGE & mideleg.ssid); //Suppressed if delegated；执行连续赋值，把组合逻辑连接到目标信号。
    assign mip_priority_vector[5] = 1; // 执行连续赋值，把组合逻辑连接到目标信号。

    priority_encoder #(.WIDTH(6))
    interrupt_cause_encoder (
        .priority_vector (mip_priority_vector),
        .encoded_result (mip_cause_sel)
    );

    assign interrupt_cause = interrupt_code_table[mip_cause_sel]; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        mcause.zeros <= '0;
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            mcause.is_interrupt <= 0;
            mcause.code <= '0;
        end // 结束语句块。
        else if ((mwrite_en(MCAUSE) | (exception_pkt.valid & ~exception_delegated) | (interrupt_taken & ~interrupt_delegated))) begin // 执行否则如果分支的条件判断。
            mcause.is_interrupt <= interrupt_taken | (mwrite_en(MCAUSE) & updated_csr[31]);
            mcause.code <= interrupt_taken ? interrupt_cause : exception_pkt.valid ? exception_pkt.code : updated_csr[ECODE_W-1:0];
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MTVAL
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mtval <= '0;
        else if (mwrite_en(MTVAL) | (exception_pkt.valid & ~exception_delegated)) // 执行否则如果分支的条件判断。
            mtval <= exception_pkt.valid ? exception_pkt.tval : updated_csr;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MSCRATCH
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mscratch <= '0;
        else if (mwrite_en(MSCRATCH)) // 执行否则如果分支的条件判断。
            mscratch <= updated_csr;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MCOUNTINHIBIT
    localparam mcounter_t mcountinhibit_mask = '{default:0, cy:1, ir:1}; // 声明局部常量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mcountinhibit <= '0;
        else if (mwrite_en(MCOUNTINHIBIT) & CONFIG.MODES == MSU) // 执行否则如果分支的条件判断。
            mcountinhibit <= updated_csr & mcountinhibit_mask;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MCOUNTEREN
    localparam mcounter_t mcounteren_mask = '{default:0, cy:1, tm:1, ir:1}; // 声明局部常量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mcounteren <= '0;
        else if (mwrite_en(MCOUNTEREN) & CONFIG.MODES inside {MU, MSU}) // 执行否则如果分支的条件判断。
            mcounteren <= updated_csr & mcounteren_mask;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MENVCFG
    localparam envcfg_t menvcfg_mask = '{default:0, fiom: 1, cbie:{2{CONFIG.INCLUDE_CBO}}, cbcfe:CONFIG.INCLUDE_CBO}; // 声明局部常量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            menvcfg <= '0;
        else if (mwrite_en(MENVCFG) & CONFIG.MODES inside {MU, MSU}) // 执行否则如果分支的条件判断。
            menvcfg <= updated_csr & menvcfg_mask;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MENVCFGH
    localparam envcfgh_t menvcfgh_mask = '{default:0, stce:CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SSTC}; // 声明局部常量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            menvcfgh <= '0;
        else if (mwrite_en(MENVCFGH) & CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SSTC) // 执行否则如果分支的条件判断。
            menvcfgh <= updated_csr & menvcfg_mask;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //MSTATEEN0H
    localparam mstateen0h_t mstateen0h_mask = '{default:0, se0:CONFIG.MODES == MSU, envcfg:CONFIG.MODES != M}; // 声明局部常量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mstateen0h <= '0;
        else if (mwrite_en(MSTATEEN0H) & CONFIG.MODES != M) // 执行否则如果分支的条件判断。
            mstateen0h <= updated_csr & mstateen0h_mask;
    end // 结束语句块。

end // 结束语句块。
endgenerate // 结束生成块。

    ////////////////////////////////////////////////////
    //END OF MACHINE REGS
    ////////////////////////////////////////////////////


    ////////////////////////////////////////////////////
    //BEGIN OF SUPERVISOR REGS
    ////////////////////////////////////////////////////
    cause_t scause;
    logic[31:0] stval; // 声明信号、变量或生成变量。
    logic[31:0] sstatus; // 声明信号、变量或生成变量。
    logic[31:0] stvec; // 声明信号、变量或生成变量。
    satp_t satp;
    logic[31:0] sscratch; // 声明信号、变量或生成变量。
    logic[31:0] scounteren; // 声明信号、变量或生成变量。
    logic[31:0] stimecmp; // 声明信号、变量或生成变量。
    logic[31:0] stimecmph; // 声明信号、变量或生成变量。
    localparam logic[31:0] sstateen0 = 0; //The defined behaviour is not used；声明局部常量。
    localparam logic[31:0] sstateen1 = 0; // 声明局部常量。
    localparam logic[31:0] sstateen2 = 0; // 声明局部常量。
    localparam logic[31:0] sstateen3 = 0; // 声明局部常量。

    //TLB status --- used to mux physical/virtual address
    assign instruction_translation_on = CONFIG.MODES == MSU & satp.mode & privilege_level != MACHINE_PRIVILEGE; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign data_translation_on = CONFIG.MODES == MSU & satp.mode & (privilege_level != MACHINE_PRIVILEGE | (mstatus.mprv & mstatus.mpp != MACHINE_PRIVILEGE)); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign asid = satp.asid; // 执行连续赋值，把组合逻辑连接到目标信号。
    //******************

generate if (CONFIG.MODES == MSU) begin : gen_csr_s_mode // 开始生成块，在编译期展开硬件结构。
    ////////////////////////////////////////////////////
    //MMU interface
    assign immu.mxr = mstatus.mxr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dmmu.mxr = mstatus.mxr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign immu.sum = mstatus.sum; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dmmu.sum = mstatus.sum; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign immu.privilege = privilege_level; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dmmu.privilege = mstatus.mprv ? privilege_t'(mstatus.mpp) : privilege_level; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign immu.satp_ppn = satp.ppn; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dmmu.satp_ppn = satp.ppn; // 执行连续赋值，把组合逻辑连接到目标信号。
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //SEPC
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        sepc[1:0] <= '0;
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            sepc[31:2] <= '0;
        else if (swrite_en(SEPC) | (exception_pkt.valid & exception_delegated) | (interrupt_taken & interrupt_delegated)) // 执行否则如果分支的条件判断。
            sepc[31:2] <= (exception_pkt.valid | interrupt_taken) ? exception_pkt.pc[31:2] : updated_csr[31:2];
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //SCAUSE
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        scause.zeros <= '0;
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            scause.is_interrupt <= 0;
            scause.code <= '0;
        end // 结束语句块。
        else if ((swrite_en(SCAUSE) | (exception_pkt.valid & exception_delegated) | (interrupt_taken & interrupt_delegated))) begin // 执行否则如果分支的条件判断。
            scause.is_interrupt <= interrupt_taken | (swrite_en(SCAUSE) & updated_csr[31]);
            scause.code <= interrupt_taken ? interrupt_cause : exception_pkt.valid ? exception_pkt.code : updated_csr[ECODE_W-1:0];
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //STVEC
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        stvec[1:0] <= '0;
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            stvec[31:2] <= CONFIG.CSRS.RESET_TVEC[31:2];
        else if (swrite_en(STVEC)) // 执行否则如果分支的条件判断。
            stvec[31:2] <= updated_csr[31:2];
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //STVAL
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            stval <= '0;
        else if (swrite_en(STVAL) | (exception_pkt.valid & exception_delegated)) // 执行否则如果分支的条件判断。
            stval <= exception_pkt.valid ? exception_pkt.tval : updated_csr;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //SATP
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            satp <= 0;
        else if (swrite_en(SATP)) // 执行否则如果分支的条件判断。
            satp <= updated_csr;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //SCOUNTEREN
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            scounteren <= 0;
        else if (swrite_en(SCOUNTEREN)) // 执行否则如果分支的条件判断。
            scounteren <= updated_csr;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //SSCRATCH
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            sscratch <= '0;
        else if (swrite_en(SSCRATCH)) // 执行否则如果分支的条件判断。
            sscratch <= updated_csr;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //SENVCFG
    localparam envcfg_t senvcfg_mask = '{default:0, fiom: 1, cbie:{2{CONFIG.INCLUDE_CBO}}, cbcfe:CONFIG.INCLUDE_CBO}; // 声明局部常量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            senvcfg <= '0;
        else if (swrite_en(SENVCFG) & CONFIG.MODES == MSU) // 执行否则如果分支的条件判断。
            senvcfg <= updated_csr & senvcfg_mask;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //STIMECMP
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            stimecmp <= '0;
            stimecmph <= '0;
        end // 结束语句块。
        else begin // 执行否则分支。
            if (swrite_en(STIMECMP) & CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SSTC) // 执行条件判断，满足条件时进入对应分支。
                stimecmp <= updated_csr;
            if (swrite_en(STIMECMPH) & CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SSTC) // 执行条件判断，满足条件时进入对应分支。
                stimecmph <= updated_csr;
        end // 结束语句块。
    end // 结束语句块。

    assign stip_stimecmp = mtime >= {stimecmph, stimecmp}; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //SIP
    assign sip = mip & mideleg; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //SIE
    assign sie_deleg_mask = sie_mask & mie_t'(mideleg); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sie = mie & sie_deleg_mask; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //SSTATUS
    assign sstatus = mstatus & sstatus_mask; // 执行连续赋值，把组合逻辑连接到目标信号。

end // 结束语句块。
endgenerate // 结束生成块。

    ////////////////////////////////////////////////////
    //END OF SUPERVISOR REGS
    ////////////////////////////////////////////////////


    ////////////////////////////////////////////////////
    //Timers and Counters
    //Register increment for instructions completed
    //Can be inhbited by mcountinhibit
    localparam COUNTER_W = 64; // 声明局部常量。

    logic[COUNTER_W-1:0] mcycle; // 声明信号、变量或生成变量。
    logic[COUNTER_W-1:0] minstret; // 声明信号、变量或生成变量。

    logic[COUNTER_W-1:0] mcycle_input_next; // 声明信号、变量或生成变量。
    logic mcycle_inc; // 声明信号、变量或生成变量。
    logic pending_inst; // 声明信号、变量或生成变量。
    logic increment_minstret; // 声明信号、变量或生成变量。

    assign mcycle_input_next[31:0] = mwrite_en(MCYCLE) ? updated_csr : mcycle[31:0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mcycle_input_next[COUNTER_W-1:32] = mwrite_en(MCYCLEH) ? updated_csr[COUNTER_W-33:0] : mcycle[COUNTER_W-1:32]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mcycle_inc = (CONFIG.MODES != BARE | CONFIG.CSRS.INCLUDE_ZICNTR) & ~((mwrite_en(MCYCLE) | mwrite_en(MCYCLEH))) & ~mcountinhibit.cy; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mcycle <= 0;
        else // 执行否则分支。
            mcycle <= mcycle_input_next + COUNTER_W'(mcycle_inc);
    end // 结束语句块。


    //Branch and pre issue exceptions retire the pending
    assign increment_minstret = pending_inst & (exception_pkt.valid ? exception_pkt.source[BR_EXCEPTION] | exception_pkt.source[PRE_ISSUE_EXCEPTION] : ~exception_pkt.possible); // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            pending_inst <= 0;
        else begin // 执行否则分支。
            if (instruction_issued & ~mcountinhibit.ir) // 执行条件判断，满足条件时进入对应分支。
                pending_inst <= 1;
            else if (mwrite_en(MINSTRET) | mwrite_en(MINSTRETH) | (~exception_pkt.possible | ~exception_pkt.valid)) // 执行否则如果分支的条件判断。
                pending_inst <= 0;
        end // 结束语句块。
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            minstret <= 0;
        else if ((CONFIG.MODES != BARE | CONFIG.CSRS.INCLUDE_ZICNTR) & increment_minstret) // 执行否则如果分支的条件判断。
            minstret <= minstret + 1;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Floating-Point status register
    //Contains 5 exception flags (invalid, inexact, overflow, underflow, divide by zero)
    //Also contains dynamic rounding mode (round to zero, round to +infinity, round to -infinity, round to nearest ties to even, round to nearest ties away)
    //These fields can be accessed individually or simultaneously through different addresses
    logic[2:0] frm; // 声明信号、变量或生成变量。
    logic[4:0] fflags; // 声明信号、变量或生成变量。
    assign dyn_rm = frm; // 执行连续赋值，把组合逻辑连接到目标信号。

generate if (CONFIG.INCLUDE_UNIT.FPU) begin : gen_csr_fp // 开始生成块，在编译期展开硬件结构。
    //Older versions of the spec mandated an illegal instruction exception if an instruction
    //with the dynamic rounding mode was issued and the frm register contained an invalid 
    //rounding mode. This has since been changed to "reserved" behaviour, meaning we do not 
    //have to do anything special. In this case, fp_roundup would default to rne

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            frm <= '0;
            fflags <= '0;
        end // 结束语句块。
        else begin // 执行否则分支。
            //Explicit writes commit earlier than regular CSR writes because they are required by FP instructions
            case ({commit, csr_inputs_r.addr}) // 开始多分支选择，根据表达式选择对应分支。
                {1'b1, FFLAGS} : fflags <= next_csr[4:0];
                {1'b1, FRM} : frm <= next_csr[2:0];
                {1'b1, FCSR} : {frm, fflags} <= next_csr[7:0];
                default : fflags <= fflags | fflag_wmask; //Implicit writes (can never overlap explicit writes)；执行默认分支。
            endcase // 结束多分支选择。
        end // 结束语句块。
    end // 结束语句块。
end endgenerate // 结束语句块。


    ////////////////////////////////////////////////////
    //GC Connections
    logic will_flush; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
            will_flush <= CONFIG.MODES == MSU & csr_inputs.writes & csr_inputs.addr inside {SATP, MSTATUS, SSTATUS};
        csr_frontend_flush <= commit & will_flush;
    end // 结束语句块。

    assign exception_target_pc = exception_delegated | interrupt_delegated ? stvec : mtvec; // 执行连续赋值，把组合逻辑连接到目标信号。


    ////////////////////////////////////////////////////
    //Exceptions
    //Illegal instruction on wrong addresses, privilege
    //issues, and writing read only registers
generate if (CONFIG.MODES != BARE) begin : gen_csr_exceptions // 开始生成块，在编译期展开硬件结构。
    logic legal_access; // 声明信号、变量或生成变量。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case (csr_inputs.addr) inside // 开始多分支选择，根据表达式选择对应分支。
            FFLAGS, FRM, FCSR : legal_access = CONFIG.INCLUDE_UNIT.FPU; //FPU always accessible if present
            MVENDORID, MARCHID, MIMPID, MHARTID, MCONFIGPTR : legal_access = privilege_level == MACHINE_PRIVILEGE & ~csr_inputs.writes; //Read only
            MSTATUS, MISA, MIE, MTVEC, MSTATUSH, MSCRATCH, MEPC, MCAUSE, MTVAL, MIP, MCYCLE, MINSTRET, [MHPMCOUNTER3H:MHPMCOUNTER31], MCYCLEH, MINSTRETH, [MHPMCOUNTER3H:MHPMCOUNTER31H], MCOUNTINHIBIT, [MHPMEVENT3:MHPMEVENT31], [MHPMEVENT3H:MHPMEVENT31H] : legal_access = privilege_level == MACHINE_PRIVILEGE; //Read write
            MEDELEG, MIDELEG, MEDELEGH : legal_access = CONFIG.MODES == MSU & privilege_level == MACHINE_PRIVILEGE; //Read write, needs supervisor
            [MSTATEEN0:MSTATEEN3], [MSTATEEN0H:MSTATEEN3H] : legal_access = CONFIG.CSRS.INCLUDE_SMSTATEEN & privilege_level == MACHINE_PRIVILEGE; //Read write, needs extension
            MCOUNTEREN, MENVCFG, MENVCFGH : legal_access = CONFIG.MODES inside {MU, MSU} & privilege_level == MACHINE_PRIVILEGE; //Read write, needs user
            SSTATUS, SIE, STVEC, SCOUNTEREN, SSCRATCH, SEPC, SCAUSE, STVAL, SIP, SENVCFG : legal_access = CONFIG.MODES == MSU & privilege_level inside {MACHINE_PRIVILEGE, SUPERVISOR_PRIVILEGE}; //Read write
            SATP : legal_access = CONFIG.MODES == MSU & ((privilege_level == MACHINE_PRIVILEGE) | (privilege_level == SUPERVISOR_PRIVILEGE & ~mstatus.tvm)); //Read write, not TVM
            SENVCFG : legal_access = CONFIG.MODES == MSU & ((privilege_level == MACHINE_PRIVILEGE) | (privilege_level == SUPERVISOR_PRIVILEGE & (~CONFIG.CSRS.INCLUDE_SMSTATEEN | mstateen0h.envcfg))); //Read write, depends on mstateen0h
            SSTATEEN0 : legal_access = CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SMSTATEEN & ((privilege_level == MACHINE_PRIVILEGE) | (privilege_level == SUPERVISOR_PRIVILEGE & mstateen0h.se0)); //Read write, needs extension and mstateen0h
            [SSTATEEN1:SSTATEEN3] : legal_access = CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SMSTATEEN & privilege_level inside {MACHINE_PRIVILEGE, SUPERVISOR_PRIVILEGE}; //Read write, needs extension
            CYCLE, TIME, INSTRET, CYCLEH, TIMEH, INSTRETH : begin //Read only, depends on m/scounteren and extension
                legal_access = CONFIG.CSRS.INCLUDE_ZICNTR & ~csr_inputs.writes;
                if (privilege_level != MACHINE_PRIVILEGE) // 执行条件判断，满足条件时进入对应分支。
                    legal_access &= mcounteren[csr_inputs.addr[4:0]];
                if (CONFIG.MODES == MSU & privilege_level == USER_PRIVILEGE) // 执行条件判断，满足条件时进入对应分支。
                    legal_access &= scounteren[csr_inputs.addr[4:0]];
            end // 结束语句块。
            [HPMCOUNTER3:HPMCOUNTER31], [HPMCOUNTER3H:HPMCOUNTER31H] : begin //Read only, depends on m/scounteren and extension
                legal_access = CONFIG.CSRS.INCLUDE_ZIHPM & ~csr_inputs.writes;
                if (privilege_level != MACHINE_PRIVILEGE) // 执行条件判断，满足条件时进入对应分支。
                    legal_access &= mcounteren[csr_inputs.addr[4:0]];
                if (CONFIG.MODES == MSU & privilege_level == USER_PRIVILEGE) // 执行条件判断，满足条件时进入对应分支。
                    legal_access &= scounteren[csr_inputs.addr[4:0]];
            end // 结束语句块。
            STIMECMP, STIMECMPH : legal_access = CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SSTC & ((privilege_level == MACHINE_PRIVILEGE) | (privilege_level == SUPERVISOR_PRIVILEGE & mcounteren.tm & menvcfgh.stce)); //Read write, depends on TM + STCE
            default: legal_access = 0; // 执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。


    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            illegal_instruction <= 0;
        else if (issue.new_request) // 执行否则如果分支的条件判断。
            illegal_instruction <= ~legal_access;
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            exception.valid <= 0;
        else // 执行否则分支。
            exception.valid <= commit & illegal_instruction;
    end // 结束语句块。

    assign exception.code = ILLEGAL_INST; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign exception.pc = issue_stage.pc_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign exception.tval = issue_stage.instruction_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign exception.discard = |issue_stage.instruction_r[11:7]; //Only discard if rd != x0；执行连续赋值，把组合逻辑连接到目标信号。

end // 结束语句块。
endgenerate // 结束生成块。

    //Interrupts need to be immediately evaluated folowing MRET/SRET or writing to a CSR that
    //controls interrupts. MRET/SRET flush the fetch pipeline so nothing needs to be done,
    //but we must stall for 1 cycle after writing certain CSRs to ensure pending_interrupt
    //can be raised and detected before another instruction is issued
    logic stall_for_interrupt; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        stall_for_interrupt <= wb.done & wb.ack & csr_inputs_r.writes & (mwrite_en(MIP) | mwrite_en(MIE) | mwrite_en(MSTATUS) | mwrite_en(MIDELEG) | swrite_en(SIP) | swrite_en(SIE) | swrite_en(SSTATUS));
    end // 结束语句块。

    assign exception.possible = busy | exception.valid | stall_for_interrupt; //Block future instructions；执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //CSR mux
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case (csr_inputs_r.addr) inside // 开始多分支选择，根据表达式选择对应分支。
            //Floating point
            FFLAGS : selected_csr = CONFIG.INCLUDE_UNIT.FPU ? {27'b0, fflags} : '0;
            FRM : selected_csr = CONFIG.INCLUDE_UNIT.FPU ? {29'b0, frm} : '0;
            FCSR : selected_csr = CONFIG.INCLUDE_UNIT.FPU ? {24'b0, frm, fflags} : '0;

            //Machine info
            MVENDORID : selected_csr = CONFIG.MODES != BARE ? mvendorid : '0;
            MARCHID : selected_csr = CONFIG.MODES != BARE ? marchid : '0;
            MIMPID : selected_csr = CONFIG.MODES != BARE ? mimpid : '0;
            MHARTID : selected_csr = CONFIG.MODES != BARE ? mhartid : '0;
            MCONFIGPTR : selected_csr = CONFIG.MODES != BARE ? mconfigptr : '0;
            //Machine trap setup
            MSTATUS : selected_csr = CONFIG.MODES != BARE ? mstatus : '0;
            MISA :  selected_csr = CONFIG.MODES != BARE ? misa : '0;
            MEDELEG : selected_csr = CONFIG.MODES == MSU ? medeleg : '0;
            MIDELEG : selected_csr = CONFIG.MODES == MSU ? mideleg : '0;
            MIE : selected_csr = CONFIG.MODES != BARE ? mie : '0;
            MTVEC : selected_csr = CONFIG.MODES != BARE ? mtvec : '0;
            MCOUNTEREN : selected_csr = CONFIG.MODES inside {MU, MSU} ? mcounteren : '0;
            MSTATUSH : selected_csr = CONFIG.MODES != BARE ? mstatush : '0;
            MEDELEGH : selected_csr = CONFIG.MODES == MSU ? medelegh : '0;
            //Machine trap handling
            MSCRATCH : selected_csr = CONFIG.MODES != BARE ? mscratch : '0;
            MEPC : selected_csr = CONFIG.MODES != BARE ? mepc : '0;
            MCAUSE : selected_csr = CONFIG.MODES != BARE ? mcause : '0;
            MTVAL : selected_csr = CONFIG.MODES != BARE ? mtval : '0;
            MIP : selected_csr = CONFIG.MODES != BARE ? mip : '0;
            //Machine configuration
            MENVCFG : selected_csr = CONFIG.MODES inside {MU, MSU} ? menvcfg : '0;
            MENVCFGH : selected_csr = CONFIG.MODES inside {MU, MSU} ? menvcfgh : '0;
            //No PMP
            //MHPM COUNTER
            //Machine Timers and Counters
            MCYCLE : selected_csr = CONFIG.MODES != BARE ? mcycle[31:0] : '0;
            MINSTRET : selected_csr = CONFIG.MODES != BARE ? minstret[31:0] : '0;
            [MHPMCOUNTER3 : MHPMCOUNTER31] : selected_csr = '0;
            MCYCLEH : selected_csr = CONFIG.MODES != BARE ? 32'(mcycle[COUNTER_W-1:32]) : '0;
            MINSTRETH : selected_csr = CONFIG.MODES != BARE ? 32'(minstret[COUNTER_W-1:32]) : '0;
            [MHPMCOUNTER3H : MHPMCOUNTER31H] : selected_csr = '0;
            //Machine Counter Setup
            MCOUNTINHIBIT : selected_csr = CONFIG.MODES != BARE ? mcountinhibit : '0;
            [MHPMEVENT3 : MHPMEVENT31] : selected_csr = '0;
            [MHPMEVENT3H : MHPMEVENT31H] : selected_csr = '0;
            //Machine state enable
            MSTATEEN0 : selected_csr = CONFIG.MODES != BARE & CONFIG.CSRS.INCLUDE_SMSTATEEN ? mstateen0 : '0;
            MSTATEEN1 : selected_csr = CONFIG.MODES != BARE & CONFIG.CSRS.INCLUDE_SMSTATEEN ? mstateen1 : '0;
            MSTATEEN2 : selected_csr = CONFIG.MODES != BARE & CONFIG.CSRS.INCLUDE_SMSTATEEN ? mstateen2 : '0;
            MSTATEEN3 : selected_csr = CONFIG.MODES != BARE & CONFIG.CSRS.INCLUDE_SMSTATEEN ? mstateen3 : '0;
            MSTATEEN0H : selected_csr = CONFIG.MODES != BARE & CONFIG.CSRS.INCLUDE_SMSTATEEN ? mstateen0h : '0;
            MSTATEEN1H : selected_csr = CONFIG.MODES != BARE & CONFIG.CSRS.INCLUDE_SMSTATEEN ? mstateen1h : '0;
            MSTATEEN2H : selected_csr = CONFIG.MODES != BARE & CONFIG.CSRS.INCLUDE_SMSTATEEN ? mstateen2h : '0;
            MSTATEEN3H : selected_csr = CONFIG.MODES != BARE & CONFIG.CSRS.INCLUDE_SMSTATEEN ? mstateen3h : '0;

            //Supervisor regs
            //Supervisor Trap Setup
            SSTATUS : selected_csr = CONFIG.MODES == MSU ? sstatus : '0;
            SIE : selected_csr = CONFIG.MODES == MSU ? sie : '0;
            STVEC : selected_csr = CONFIG.MODES == MSU ? stvec : '0;
            SCOUNTEREN : selected_csr = '0;
            //Supervisor configuration
            SENVCFG : selected_csr = CONFIG.MODES == MSU ? senvcfg : '0;
            //Supervisor trap handling
            SSCRATCH : selected_csr = CONFIG.MODES == MSU ? sscratch : '0;
            SEPC : selected_csr = CONFIG.MODES == MSU ? sepc : '0;
            SCAUSE : selected_csr = CONFIG.MODES == MSU ? scause : '0;
            STVAL : selected_csr = CONFIG.MODES == MSU ? stval : '0;
            SIP : selected_csr = CONFIG.MODES == MSU ? sip : '0;
            STIMECMP : selected_csr = CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SSTC ? stimecmp : '0;
            STIMECMPH : selected_csr = CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SSTC ? stimecmph : '0;
            //Supervisor address translation and protection
            SATP : selected_csr = CONFIG.MODES == MSU ? satp : '0;
            //Supervisor state enable
            SSTATEEN0 : selected_csr = CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SMSTATEEN ? sstateen0 : '0;
            SSTATEEN1 : selected_csr = CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SMSTATEEN ? sstateen1 : '0;
            SSTATEEN2 : selected_csr = CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SMSTATEEN ? sstateen2 : '0;
            SSTATEEN3 : selected_csr = CONFIG.MODES == MSU & CONFIG.CSRS.INCLUDE_SMSTATEEN ? sstateen3 : '0;

            //Timers and counters
            CYCLE : selected_csr = CONFIG.CSRS.INCLUDE_ZICNTR ? mcycle[31:0] : '0;
            TIME : selected_csr = CONFIG.CSRS.INCLUDE_ZICNTR ? mtime[31:0] : '0;
            INSTRET : selected_csr = CONFIG.CSRS.INCLUDE_ZICNTR ? minstret[31:0] : '0;
            [HPMCOUNTER3 : HPMCOUNTER31] : selected_csr = '0;
            CYCLEH : selected_csr = CONFIG.CSRS.INCLUDE_ZICNTR ? 32'(mcycle[COUNTER_W-1:32]) : '0;
            TIMEH : selected_csr = CONFIG.CSRS.INCLUDE_ZICNTR ? mtime[63:32] : '0;
            INSTRETH : selected_csr = CONFIG.CSRS.INCLUDE_ZICNTR ? 32'(minstret[COUNTER_W-1:32]) : '0;
            [HPMCOUNTER3H : HPMCOUNTER31H] : selected_csr = '0;

            default : selected_csr = '0; // 执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (commit) // 执行条件判断，满足条件时进入对应分支。
            selected_csr_r <= selected_csr;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Assertions
    mstatus_update_assertion:
        assert property (@(posedge clk) disable iff (rst) $onehot0({mret,sret,interrupt_taken, exception_pkt.valid,(mwrite_en(MSTATUS) | swrite_en(SSTATUS))})) else $error("multiple write to mstatus"); // 定义或检查断言、假设、覆盖或时序性质。

endmodule // 结束模块定义。
