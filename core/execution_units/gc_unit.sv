// ============================================================================
// 文件：core/execution_units/gc_unit.sv
// 类型：module
// 名称：gc_unit
// 作用：全局控制单元，处理流水线 flush、异常、中断和指令退休控制。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2018 Eric Matthews,  Lesley Shannon
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

module gc_unit // 定义 gc_unit 模块。

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

        //Decode
        input decode_packet_t decode_stage, // 声明输入端口。
        output logic unit_needed, // 声明输出端口。
        output logic [REGFILE_READ_PORTS-1:0] uses_rs, // 声明输出端口。
        output logic uses_rd, // 声明输出端口。

        input issue_packet_t issue_stage, // 声明输入端口。
        input logic issue_stage_ready, // 声明输入端口。
        input logic instruction_issued, // 声明输入端口。
        input logic [31:0] constant_alu, // 声明输入端口。
        input logic [31:0] rf [REGFILE_READ_PORTS], // 声明输入端口。

        unit_issue_interface.unit issue,

        //Branch miss predict
        input logic branch_flush, // 声明输入端口。

        //Exception
        exception_interface.unit local_gc_exception,
        exception_interface.econtrol exception [NUM_EXCEPTION_SOURCES],
        input logic [31:0] exception_target_pc, // 声明输入端口。

        output logic mret, // 声明输出端口。
        output logic sret, // 声明输出端口。
        input logic [31:0] mepc, // 声明输入端口。
        input logic [31:0] sepc, // 声明输入端口。

        //CSR Interrupts
        input logic interrupt_pending, // 声明输入端口。
        output logic interrupt_taken, // 声明输出端口。

        //CSR signals
        input logic csr_frontend_flush, // 声明输入端口。
        input logic [1:0] current_privilege, // 声明输入端口。
        input logic tvm, // 声明输入端口。
        input logic tsr, // 声明输入端口。

        //Output controls
        output gc_outputs_t gc, // 声明输出端口。
        output tlb_packet_t sfence, // 声明输出端口。

        //Ordering support
        input load_store_status_t load_store_status // 声明输入端口。
    );

    //Largest depth for TLBs
    localparam int TLB_CLEAR_DEPTH = (CONFIG.DTLB.DEPTH > CONFIG.ITLB.DEPTH) ? CONFIG.DTLB.DEPTH : CONFIG.ITLB.DEPTH; // 声明局部常量。
    //For general reset clear, greater of TLB depth or id-flight memory blocks (MAX_IDS)
    localparam int INIT_CLEAR_DEPTH = CONFIG.MODES == MSU ? (TLB_CLEAR_DEPTH > 64 ? TLB_CLEAR_DEPTH : 64) : 64; // 声明局部常量。

    ////////////////////////////////////////////////////
    //Overview
    //All CSR instructions hold the issue stage until they are the oldest instruction and complete.
    //  As such, their values are known at issue time for any call/ret instruction.

    //FENCE.I:
    //    flush and hold fetch until L/S unit empty
    //    Local mem (nothing extra required for coherency)
    //    Caches, currently not supported.  Requires L2 monitoring.  Need to know that all previous stores from this processor
    //       have been sent out as potential invalidations and ack-ed before fetch can resume
    //SFENCE
    //    flush and hold fetch, wait until L/S input FIFO empty, hold fetch until TLB update complete
    //ECALL, EBREAK, SRET, MRET:
    //    flush fetch, hold until oldest instruction

    //Interrupt
    //wait until issue/execute exceptions are no longer possible, flush fetch, take exception

    //Fetch Exception (TLB and MMU) (fetch stage)
    //flush fetch, wait until issue/execute exceptions are no longer possible, take exception.  If decode stage or later exception occurs first, exception is overridden

    //Illegal opcode (issue stage)
    //fetch flush, take exception.  If execute or later exception occurs first, exception is overridden

    //Branch exceptions (issue/execute stage)
    //fetch flush, take exception.

    //CSR exceptions (issue/execute stage)
    //fetch flush, take exception.

    //LS exceptions (miss-aligned, TLB and MMU) (issue stage)
    //fetch flush, take exception. If execute or later exception occurs first, exception is overridden
    common_instruction_t instruction;//rs1_addr, rs2_addr, fn3, fn7, rd_addr, upper/lower opcode
// 定义类型别名或枚举/结构类型。
    typedef enum {RST_STATE, PRE_CLEAR_STATE, INIT_CLEAR_STATE, IDLE_STATE, TLB_CLEAR_STATE, WAIT_INTERRUPT, PRE_ISSUE_FLUSH, WAIT_WRITE} gc_state;
    gc_state state;
    gc_state next_state;

    logic init_clear_done; // 声明信号、变量或生成变量。
    logic tlb_clear_done; // 声明信号、变量或生成变量。

    //GC registered global outputs
    logic gc_init_clear; // 声明信号、变量或生成变量。
    logic gc_fetch_hold; // 声明信号、变量或生成变量。
    logic gc_issue_hold; // 声明信号、变量或生成变量。
    logic gc_rename_revert; // 声明信号、变量或生成变量。
    logic gc_fetch_flush; // 声明信号、变量或生成变量。
    logic gc_fetch_ifence; // 声明信号、变量或生成变量。
    logic gc_tlb_flush; // 声明信号、变量或生成变量。
    logic gc_pc_override; // 声明信号、变量或生成变量。
    logic [31:0] gc_pc; // 声明信号、变量或生成变量。

    logic possible_exception; // 声明信号、变量或生成变量。

    ////////////////////////////////////////////////////
    //Implementation

    ////////////////////////////////////////////////////
    //Decode
    logic [31:0] pc_p4; // 声明信号、变量或生成变量。
    logic is_ifence; // 声明信号、变量或生成变量。
    logic is_sfence; // 声明信号、变量或生成变量。
    logic trivial_sfence; // 声明信号、变量或生成变量。
    logic asid_sfence; // 声明信号、变量或生成变量。
    logic is_mret; // 声明信号、变量或生成变量。
    logic is_sret; // 声明信号、变量或生成变量。
    logic is_wfi; // 声明信号、变量或生成变量。

    assign instruction = decode_stage.instruction; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign unit_needed = // 执行连续赋值，把组合逻辑连接到目标信号。
        (CONFIG.MODES != BARE & instruction inside {MRET, WFI}) |
        (CONFIG.MODES == MSU & instruction inside {SRET, SFENCE_VMA}) |
        (CONFIG.INCLUDE_IFENCE & instruction inside {FENCE_I});
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        uses_rs = '0;
        uses_rs[RS1] = CONFIG.MODES == MSU & instruction inside {SFENCE_VMA};
        uses_rs[RS2] = CONFIG.MODES == MSU & instruction inside {SFENCE_VMA};
        uses_rd = 0;
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue_stage_ready) begin // 执行条件判断，满足条件时进入对应分支。
            is_ifence <= CONFIG.INCLUDE_IFENCE & instruction.upper_opcode[2];
            is_sfence <= CONFIG.MODES == MSU & ~instruction.upper_opcode[2] & instruction.fn7[0];
            trivial_sfence <= |instruction.rs1_addr;
            asid_sfence <= |instruction.rs2_addr;
            is_wfi <= CONFIG.MODES != BARE & ~instruction.upper_opcode[2] & ~instruction.fn7[0] & ~instruction.rs2_addr[1];
            //Ret instructions need exact decoding
            is_mret <= CONFIG.MODES != BARE & instruction inside {MRET};
            is_sret <= CONFIG.MODES == MSU & instruction inside {SRET};
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Issue
    logic is_ifence_r; // 声明信号、变量或生成变量。
    logic is_sfence_r; // 声明信号、变量或生成变量。
    logic is_sret_r; // 声明信号、变量或生成变量。
    logic trivial_sfence_r; // 声明信号、变量或生成变量。
    logic asid_sfence_r; // 声明信号、变量或生成变量。
    logic [31:0] sfence_addr_r; // 声明信号、变量或生成变量。
    logic [ASIDLEN-1:0] asid_r; // 声明信号、变量或生成变量。
    logic new_exception; // 声明信号、变量或生成变量。

    //Input registering
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            is_ifence_r <= 0;
            is_sfence_r <= 0;
            mret <= 0;
            sret <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            is_ifence_r <= issue.new_request & is_ifence & ~new_exception;
            is_sfence_r <= issue.new_request & is_sfence & ~new_exception;
            mret <= issue.new_request & is_mret & ~new_exception;
            sret <= issue.new_request & is_sret & ~new_exception;
        end // 结束语句块。
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) begin // 执行条件判断，满足条件时进入对应分支。
            trivial_sfence_r <= trivial_sfence;
            asid_sfence_r <= asid_sfence;
            sfence_addr_r <= rf[RS1];
            asid_r <= rf[RS2][ASIDLEN-1:0];
        end // 结束语句块。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            trivial_sfence_r <= 0;
            asid_sfence_r <= 0;
        end // 结束语句块。
    end // 结束语句块。

    //Exceptions treated like every other unit
    generate if (CONFIG.MODES != BARE) begin : gen_gc_exception // 开始生成块，在编译期展开硬件结构。
        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            new_exception = 0;
            if (issue.new_request) begin // 执行条件判断，满足条件时进入对应分支。
                if (current_privilege == USER_PRIVILEGE) // 执行条件判断，满足条件时进入对应分支。
                    new_exception = is_sfence | is_sret | is_mret;
                else if (current_privilege == SUPERVISOR_PRIVILEGE) // 执行否则如果分支的条件判断。
                    new_exception = (is_sfence & tvm) | (is_sret & tsr);
            end // 结束语句块。
        end // 结束语句块。

        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) // 执行条件判断，满足条件时进入对应分支。
                local_gc_exception.valid <= 0;
            else // 执行否则分支。
                local_gc_exception.valid <= new_exception;
        end // 结束语句块。

        assign local_gc_exception.possible = 0; //Not needed because appears on first cycle；执行连续赋值，把组合逻辑连接到目标信号。
        assign local_gc_exception.code = ILLEGAL_INST; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign local_gc_exception.tval = issue_stage.instruction_r; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign local_gc_exception.pc = issue_stage.pc_r; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign local_gc_exception.discard = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    end // 结束语句块。
    endgenerate // 结束生成块。

    ////////////////////////////////////////////////////
    //GC Operation
    assign gc.fetch_flush = branch_flush | gc_pc_override; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        gc_fetch_hold <= next_state inside {PRE_CLEAR_STATE, INIT_CLEAR_STATE, PRE_ISSUE_FLUSH, TLB_CLEAR_STATE, WAIT_WRITE};
        gc_issue_hold <= next_state inside {PRE_CLEAR_STATE, INIT_CLEAR_STATE, WAIT_INTERRUPT, PRE_ISSUE_FLUSH, TLB_CLEAR_STATE, WAIT_WRITE};
        gc_init_clear <= next_state inside {INIT_CLEAR_STATE};
        gc_fetch_ifence <= issue.new_request & is_ifence;
        gc_tlb_flush <= next_state inside {INIT_CLEAR_STATE, TLB_CLEAR_STATE};
    end // 结束语句块。
    //work-around for verilator BLKANDNBLK signal optimizations
    assign gc.fetch_hold = gc_fetch_hold; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign gc.issue_hold = gc_issue_hold | possible_exception; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign gc.init_clear = gc_init_clear; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign gc.fetch_ifence = CONFIG.INCLUDE_IFENCE & gc_fetch_ifence; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sfence = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        valid : CONFIG.MODES == MSU & gc_tlb_flush,
        asid_only : asid_sfence_r,
        asid : asid_r,
        addr_only : trivial_sfence_r,
        addr : sfence_addr_r
    };

    ////////////////////////////////////////////////////
    //GC State Machine
    always @(posedge clk) begin // 开始 always 逻辑块。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            state <= RST_STATE;
        else // 执行否则分支。
            state <= next_state;
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        next_state = state;
        case (state) // 开始多分支选择，根据表达式选择对应分支。
            RST_STATE : next_state = PRE_CLEAR_STATE;
            PRE_CLEAR_STATE : next_state = INIT_CLEAR_STATE;
            INIT_CLEAR_STATE : if (init_clear_done) next_state = IDLE_STATE;
            IDLE_STATE : begin
                if ((issue.new_request & ~is_wfi & ~new_exception) | gc.exception.valid | csr_frontend_flush) // 执行条件判断，满足条件时进入对应分支。
                    next_state = PRE_ISSUE_FLUSH;
                else if (interrupt_pending) // 执行否则如果分支的条件判断。
                    next_state = WAIT_INTERRUPT;
            end // 结束语句块。
            WAIT_INTERRUPT : begin
                if (gc.exception.valid | csr_frontend_flush) //Exception overrides interrupt；执行条件判断，满足条件时进入对应分支。
                    next_state = PRE_ISSUE_FLUSH;
                else if (~interrupt_pending) //Something cancelled the interrupt；执行否则如果分支的条件判断。
                    next_state = IDLE_STATE;
                else if (~possible_exception & issue_stage.stage_valid & ~branch_flush) //No more possible exceptions and issue stage has correct PC；执行否则如果分支的条件判断。
                    next_state = PRE_ISSUE_FLUSH;
            end // 结束语句块。
            PRE_ISSUE_FLUSH : begin
                if (is_sfence_r) // 执行条件判断，满足条件时进入对应分支。
                    next_state = TLB_CLEAR_STATE;
                else if (is_ifence_r) // 执行否则如果分支的条件判断。
                    next_state = WAIT_WRITE;
                else //MRET/SRET, exception, interrupt, CSR flush；执行否则分支。
                    next_state = IDLE_STATE;
            end // 结束语句块。
            //gc.exception will never be set in these states
            TLB_CLEAR_STATE : if (tlb_clear_done) next_state = (load_store_status.outstanding_store) ? WAIT_WRITE : IDLE_STATE;
            WAIT_WRITE : if (~load_store_status.outstanding_store) next_state = IDLE_STATE;
            default : next_state = RST_STATE; // 执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

    //Will never encounter an exception and can ignore interrupts -> will not have a new instruction on the transition to idle; interrupts can be ignored
    //SFENCE: PRE_ISSUE_FLUSH (Override PC) -> TLB_CLEAR -> WAIT_WRITE
    //IFENCE: PRE_ISSUE_FLUSH (Override PC) -> WAIT_WRITE
    //MRET/SRET: PRE_ISSUE_FLUSH (Override PC)

    //Branch/CSR/LS exceptions: PRE_ISSUE_FLUSH (Override PC)
    //Fetch/illegal exception: PRE_ISSUE_FLUSH (Override PC)

    //Interrupt: WAIT_UNTIL_RETIRED (capture next PC) -> PRE_ISSUE_FLUSH (Override PC) <- This can be hijacked by an exception

    //Interrupt
    //wait until issue/execute exceptions are no longer possible, flush fetch, take exception

    ////////////////////////////////////////////////////
    //State Counter
    logic [$clog2(INIT_CLEAR_DEPTH):0] state_counter; // 声明信号、变量或生成变量。
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst | next_state inside {IDLE_STATE}) // 执行条件判断，满足条件时进入对应分支。
            state_counter <= 0;
        else if (next_state inside {INIT_CLEAR_STATE, TLB_CLEAR_STATE}) // 执行否则如果分支的条件判断。
            state_counter <= state_counter + 1;
    end // 结束语句块。
    assign init_clear_done = state_counter[$clog2(INIT_CLEAR_DEPTH)]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign tlb_clear_done = state_counter[$clog2(TLB_CLEAR_DEPTH)] | trivial_sfence_r; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Exception handling
    logic [NUM_EXCEPTION_SOURCES-1:0] exception_valid; // 声明信号、变量或生成变量。
    logic [NUM_EXCEPTION_SOURCES-1:0] exception_possible; // 声明信号、变量或生成变量。

    //Separated out because possible exceptions from CSR must still stall even without M
    generate for (genvar i = 0; i < NUM_EXCEPTION_SOURCES; i++) begin : gen_possible_exceptions // 开始生成块，在编译期展开硬件结构。
        assign exception_possible[i] = exception[i].possible; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。
    assign possible_exception = |exception_possible; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign gc.exception.possible = possible_exception; // 执行连续赋值，把组合逻辑连接到目标信号。

generate if (CONFIG.MODES != BARE) begin : gen_gc_m_mode // 开始生成块，在编译期展开硬件结构。

    //Re-assigning interface inputs to array types so that they can be dynamically indexed
    exception_code_t [NUM_EXCEPTION_SOURCES-1:0] exception_code;
    logic [NUM_EXCEPTION_SOURCES-1:0][31:0] exception_tval; // 声明信号、变量或生成变量。
    logic [NUM_EXCEPTION_SOURCES-1:0][31:0] exception_pc; // 声明信号、变量或生成变量。
    logic [NUM_EXCEPTION_SOURCES-1:0] exception_discard; // 声明信号、变量或生成变量。
    logic [$clog2(NUM_EXCEPTION_SOURCES > 1 ? NUM_EXCEPTION_SOURCES : 2)-1:0] exception_source; // 声明信号、变量或生成变量。
    
    for (genvar i = 0; i < NUM_EXCEPTION_SOURCES; i++) begin : gen_unpacking // 执行循环或遍历。
        assign exception_valid[i] = exception[i].valid; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign exception_code[i] = exception[i].code; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign exception_tval[i] = exception[i].tval; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign exception_discard[i] = exception[i].discard; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign exception_pc[i] = exception[i].pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    end // 结束语句块。

    one_hot_to_integer #(.C_WIDTH(NUM_EXCEPTION_SOURCES)) src_mux (
        .one_hot(exception_valid),
        .int_out(exception_source)
    );
    
    assign gc.exception.valid = |exception_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign gc.exception.code = exception_code[exception_source]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign gc.exception.tval = exception_tval[exception_source]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign gc.exception.pc = |exception_valid ? exception_pc[exception_source] : issue_stage.pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign gc.exception.source = exception_valid; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign interrupt_taken = interrupt_pending & (state == WAIT_INTERRUPT) & (next_state == PRE_ISSUE_FLUSH) & ~gc.exception.valid & ~csr_frontend_flush; // 执行连续赋值，把组合逻辑连接到目标信号。
    //Writeback and rename handling
    logic gc_writeback_suppress_r; // 声明信号、变量或生成变量。
    logic gc_rename_revert; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            gc_writeback_suppress_r <= 0;
            gc_rename_revert <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            gc_writeback_suppress_r <= gc.writeback_suppress;
            gc_rename_revert <= gc_writeback_suppress_r;
        end // 结束语句块。
    end // 结束语句块。
    assign gc.writeback_suppress = |(exception_valid & exception_discard); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign gc.rename_revert = gc_rename_revert; // 执行连续赋值，把组合逻辑连接到目标信号。
end endgenerate // 结束语句块。

    //PC determination (trap, flush or return)
    //Two cycles: on first cycle the processor front end is flushed,
    //on the second cycle the new PC is fetched
generate if (CONFIG.MODES != BARE || CONFIG.INCLUDE_IFENCE) begin :gen_gc_pc_override // 开始生成块，在编译期展开硬件结构。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        gc_pc_override <= next_state inside {PRE_ISSUE_FLUSH, INIT_CLEAR_STATE};
        if (gc.exception.valid | interrupt_taken) // 执行条件判断，满足条件时进入对应分支。
            gc_pc <= exception_target_pc;
        else if (instruction_issued) begin // 执行否则如果分支的条件判断。
            if (is_mret) // 执行条件判断，满足条件时进入对应分支。
                gc_pc <= mepc;
            else if (is_sret) // 执行否则如果分支的条件判断。
                gc_pc <= sepc;
            else //IFENCE, SFENCE, CSR flush；执行否则分支。
                gc_pc <= constant_alu;
        end // 结束语句块。
    end // 结束语句块。
    //work-around for verilator BLKANDNBLK signal optimizations
    assign gc.pc_override = gc_pc_override; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign gc.pc = gc_pc; // 执行连续赋值，把组合逻辑连接到目标信号。

end endgenerate // 结束语句块。
    ////////////////////////////////////////////////////
    //Decode / Write-back Handshaking
    //CSR reads are passed through the Load-Store unit
    //A CSR write is only committed once it is the oldest instruction in the pipeline
    //while processing a csr operation, gc_issue_hold prevents further instructions from being issued
    assign issue.ready = 1; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions
    multiple_exceptions_assertion:
        assert property (@(posedge clk) disable iff (rst) $onehot0(exception_valid)) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("Simultaneous exceptions"); // 执行否则分支。

    multiple_possible_exceptions_assertion:
        assert property (@(posedge clk) disable iff (rst) $onehot0(exception_possible)) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("Simultaneous possible exceptions"); // 执行否则分支。

endmodule // 结束模块定义。
