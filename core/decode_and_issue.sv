// ============================================================================
// 文件：core/decode_and_issue.sv
// 类型：module
// 名称：decode_and_issue
// 作用：实现译码后指令的发射、操作数选择和发射队列控制。
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

module decode_and_issue // 定义 decode_and_issue 模块。

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

        //ID Management
        input logic pc_id_available, // 声明输入端口。
        input decode_packet_t decode, // 声明输入端口。
        output logic decode_advance, // 声明输出端口。

        //Renamer
        renamer_interface.decode renamer,
        renamer_interface.decode fp_renamer,

        input logic [MAX_NUM_UNITS-1:0] unit_needed, // 声明输入端口。
        input logic [MAX_NUM_UNITS-1:0][REGFILE_READ_PORTS-1:0] unit_uses_rs, // 声明输入端口。
        input logic [1:0][2:0] fp_unit_uses_rs, // 声明输入端口。
        input logic [MAX_NUM_UNITS-1:0] unit_uses_rd, // 声明输入端口。
        input logic [1:0] fp_unit_uses_rd, // 声明输入端口。

        output logic decode_uses_rd, // 声明输出端口。
        output logic fp_decode_uses_rd, // 声明输出端口。
        output rs_addr_t decode_rd_addr, // 声明输出端口。
        output phys_addr_t decode_phys_rd_addr, // 声明输出端口。
        output phys_addr_t fp_decode_phys_rd_addr, // 声明输出端口。
        output phys_addr_t decode_phys_rs_addr [REGFILE_READ_PORTS], // 声明输出端口。
        output phys_addr_t fp_decode_phys_rs_addr [3], // 声明输出端口。
        output logic [$clog2(CONFIG.NUM_WB_GROUPS)-1:0] decode_rs_wb_group [REGFILE_READ_PORTS], // 声明输出端口。
        output logic fp_decode_rs_wb_group [3], // 声明输出端口。

        output logic instruction_issued, // 声明输出端口。
        output logic instruction_issued_with_rd, // 声明输出端口。
        output logic fp_instruction_issued_with_rd, // 声明输出端口。
        output issue_packet_t issue, // 声明输出端口。
        output rs_addr_t issue_rs_addr [REGFILE_READ_PORTS], // 声明输出端口。
        output phys_addr_t issue_phys_rs_addr [REGFILE_READ_PORTS], // 声明输出端口。
        output phys_addr_t fp_issue_phys_rs_addr [3], // 声明输出端口。
        output logic [$clog2(CONFIG.NUM_WB_GROUPS)-1:0] issue_rd_wb_group, // 声明输出端口。
        output logic fp_issue_rd_wb_group, // 声明输出端口。
        output logic issue_stage_ready, // 声明输出端口。

        //Register File
        register_file_issue_interface.issue rf,
        register_file_issue_interface.issue fp_rf,

        output logic [31:0] constant_alu, // 声明输出端口。

        unit_issue_interface.decode unit_issue [MAX_NUM_UNITS-1:0],

        input gc_outputs_t gc, // 声明输入端口。
        input logic [1:0] current_privilege, // 声明输入端口。

        exception_interface.unit exception
    );


    common_instruction_t decode_instruction;//rs1_addr, rs2_addr, fn3, fn7, rd_addr, upper/lower opcode

    logic decode_uses_rs [REGFILE_READ_PORTS]; // 声明信号、变量或生成变量。
    logic fp_decode_uses_rs [3]; // 声明信号、变量或生成变量。

    rs_addr_t decode_rs_addr [REGFILE_READ_PORTS];
    rs_addr_t fp_decode_rs_addr [3];
    logic [$clog2(CONFIG.NUM_WB_GROUPS)-1:0] decode_wb_group; // 声明信号、变量或生成变量。
    logic fp_decode_wb_group; // 声明信号、变量或生成变量。

    logic issue_hold; // 声明信号、变量或生成变量。
    logic [REGFILE_READ_PORTS-1:0] operand_ready; // 声明信号、变量或生成变量。
    logic [2:0] fp_operand_ready; // 声明信号、变量或生成变量。
    logic [MAX_NUM_UNITS-1:0] unit_needed_issue_stage; // 声明信号、变量或生成变量。
    logic [MAX_NUM_UNITS-1:0] issue_to; // 声明信号、变量或生成变量。

    logic [$clog2(CONFIG.NUM_WB_GROUPS)-1:0] issue_rs_wb_group [REGFILE_READ_PORTS]; // 声明信号、变量或生成变量。
    logic fp_issue_rs_wb_group [3]; // 声明信号、变量或生成变量。
    logic issue_uses_rs [REGFILE_READ_PORTS]; // 声明信号、变量或生成变量。
    logic fp_issue_uses_rs [3]; // 声明信号、变量或生成变量。

    logic pre_issue_exception_pending; // 声明信号、变量或生成变量。
    logic illegal_instruction_pattern; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation

    //Can move data into issue stage if:
    // there is no instruction currently in the issue stage, or
    // an instruction could issue (ignoring gc.fetch_flush)
    assign issue_stage_ready = (~issue.stage_valid) | (|issue_to); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign decode_advance = decode.valid & issue_stage_ready; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Instruction aliases
    assign decode_instruction = decode.instruction; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        decode_rs_addr = '{default: '0};
        decode_rs_addr[RS1] = decode_instruction.rs1_addr;
        decode_rs_addr[RS2] = decode_instruction.rs2_addr;
        fp_decode_rs_addr = '{default: '0};
        fp_decode_rs_addr[RS1] = decode_instruction.rs1_addr;
        fp_decode_rs_addr[RS2] = decode_instruction.rs2_addr;
        fp_decode_rs_addr[RS3] = decode_instruction.fn7[6:2];
    end // 结束语句块。
    ////////////////////////////////////////////////////
    //Register File Support
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        decode_uses_rd = |unit_uses_rd;
        fp_decode_uses_rd = |fp_unit_uses_rd;
        decode_uses_rs = '{default: 0};
        for (int i = 0; i < MAX_NUM_UNITS; i++) // 执行循环或遍历。
            for (int j = 0; j < REGFILE_READ_PORTS; j++) // 执行循环或遍历。
                decode_uses_rs[j] |= unit_uses_rs[i][j];
        fp_decode_uses_rs = '{default: 0};
        for (int i = 0; i < 2; i++) // 执行循环或遍历。
            for (int j = 0; j < 3; j++) // 执行循环或遍历。
                fp_decode_uses_rs[j] |= fp_unit_uses_rs[i][j];
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //WB Group Determination
    localparam units_t [MAX_NUM_UNITS-1:0] WB_UNITS_TYPE_REP = get_wb_units_type_representation(CONFIG.WB_GROUP); // 声明局部常量。
    logic [CONFIG.NUM_WB_GROUPS-1:0] uses_wb_group; // 声明信号、变量或生成变量。
    
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < CONFIG.NUM_WB_GROUPS; i++) // 执行循环或遍历。
            uses_wb_group[i] = |(unit_needed & WB_UNITS_TYPE_REP[i]);
    end // 结束语句块。

    one_hot_to_integer #(.C_WIDTH(CONFIG.NUM_WB_GROUPS))
    wb_group_one_hot_block (
        .one_hot (uses_wb_group),
        .int_out (decode_wb_group)
    );

    assign fp_decode_wb_group = unit_needed[FPU_ID]; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Renamer Support
    assign renamer.rd_addr = decode_instruction.rd_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_renamer.rd_addr = decode_instruction.rd_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign renamer.rs_addr = decode_rs_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_renamer.rs_addr = fp_decode_rs_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign renamer.uses_rd = decode_uses_rd; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_renamer.uses_rd = fp_decode_uses_rd; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign renamer.rd_wb_group = decode_wb_group; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_renamer.rd_wb_group = fp_decode_wb_group; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign renamer.id = decode.id; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_renamer.id = decode.id; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Decode ID Support
    assign decode_rd_addr = decode_instruction.rd_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign decode_phys_rd_addr = renamer.phys_rd_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_decode_phys_rd_addr = fp_renamer.phys_rd_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign decode_phys_rs_addr = renamer.phys_rs_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_decode_phys_rs_addr = fp_renamer.phys_rs_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign decode_rs_wb_group = renamer.rs_wb_group; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_decode_rs_wb_group = fp_renamer.rs_wb_group; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Issue
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (instruction_issued) begin // 执行条件判断，满足条件时进入对应分支。
            issue.pc_r <= issue.pc;
            issue.instruction_r <= issue.instruction;
        end // 结束语句块。
        if (issue_stage_ready) begin // 执行条件判断，满足条件时进入对应分支。
            issue.pc <= decode.pc;
            issue.instruction <= decode.instruction;
            issue.fetch_metadata <= decode.fetch_metadata;
            issue.fn3 <= decode_instruction.fn3;
            issue.opcode <= decode.instruction[6:0];
            issue_rs_addr <= decode_rs_addr;
            issue_phys_rs_addr <= renamer.phys_rs_addr;
            fp_issue_phys_rs_addr <= fp_renamer.phys_rs_addr;
            issue_rs_wb_group <= renamer.rs_wb_group;
            fp_issue_rs_wb_group <= fp_renamer.rs_wb_group;
            issue.rd_addr <= decode_instruction.rd_addr;
            issue.phys_rd_addr <= renamer.phys_rd_addr;
            issue.fp_phys_rd_addr <= fp_renamer.phys_rd_addr;
            issue_rd_wb_group <= decode_wb_group;
            fp_issue_rd_wb_group <= fp_decode_wb_group;
            issue.is_multicycle <= ~unit_needed[ALU_ID];
            issue.id <= decode.id;
            issue_uses_rs <= decode_uses_rs;
            fp_issue_uses_rs <= fp_decode_uses_rs;
            issue.uses_rd <= decode_uses_rd;
            issue.fp_uses_rd <= fp_decode_uses_rd;
        end // 结束语句块。
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue_stage_ready) // 执行条件判断，满足条件时进入对应分支。
            unit_needed_issue_stage <= unit_needed;
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst | gc.fetch_flush) // 执行条件判断，满足条件时进入对应分支。
            issue.stage_valid <= 0;
        else if (issue_stage_ready) // 执行否则如果分支的条件判断。
            issue.stage_valid <= decode.valid;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Issue Determination
    assign issue_hold = gc.issue_hold | pre_issue_exception_pending; // 执行连续赋值，把组合逻辑连接到目标信号。

    generate for (genvar i=0; i<REGFILE_READ_PORTS; i++) // 开始生成块，在编译期展开硬件结构。
        assign operand_ready[i] = ~rf.inuse[i] | (rf.inuse[i] & ~issue_uses_rs[i]); // 执行连续赋值，把组合逻辑连接到目标信号。
    endgenerate // 结束生成块。

    generate for (genvar i=0; i<3; i++) // 开始生成块，在编译期展开硬件结构。
        assign fp_operand_ready[i] = ~fp_rf.inuse[i] | (fp_rf.inuse[i] & ~fp_issue_uses_rs[i]); // 执行连续赋值，把组合逻辑连接到目标信号。
    endgenerate // 结束生成块。

    ////////////////////////////////////////////////////
    //Unit EX signals
    generate for (genvar i = 0; i < MAX_NUM_UNITS; i++) begin : gen_unit_issue_signals // 开始生成块，在编译期展开硬件结构。
        assign unit_issue[i].possible_issue = issue.stage_valid & unit_needed_issue_stage[i] & unit_issue[i].ready; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign issue_to[i] = unit_issue[i].possible_issue & (&operand_ready) & (&fp_operand_ready) & ~issue_hold; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign unit_issue[i].new_request = issue_to[i] & ~gc.fetch_flush; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign unit_issue[i].id = issue.id; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

    assign instruction_issued = |issue_to & ~gc.fetch_flush; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign instruction_issued_with_rd = instruction_issued & issue.uses_rd; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_instruction_issued_with_rd = instruction_issued & issue.fp_uses_rd; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Register File Issue Interface
    assign rf.phys_rs_addr = issue_phys_rs_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_rf.phys_rs_addr = fp_issue_phys_rs_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rf.phys_rd_addr = issue.phys_rd_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_rf.phys_rd_addr = issue.fp_phys_rd_addr; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rf.rs_wb_group = issue_rs_wb_group; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_rf.rs_wb_group = fp_issue_rs_wb_group; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    assign rf.single_cycle_or_flush = (instruction_issued_with_rd & |issue.rd_addr & ~issue.is_multicycle) | (issue.stage_valid & issue.uses_rd & |issue.rd_addr & gc.fetch_flush); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fp_rf.single_cycle_or_flush = issue.stage_valid & issue.fp_uses_rd & gc.fetch_flush; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    ////////////////////////////////////////////////////
    //Constant ALU:
    //  provides LUI, AUIPC, JAL, JALR results for ALU
    //  provides PC+4 for BRANCH unit and ifence in GC unit
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue_stage_ready) // 执行条件判断，满足条件时进入对应分支。
            constant_alu <= ((decode_instruction.upper_opcode inside {LUI_T}) ? '0 : decode.pc) + ((decode_instruction.upper_opcode inside {LUI_T, AUIPC_T}) ? {decode.instruction[31:12], 12'b0} : 4);
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Illegal Instruction check
    generate if (CONFIG.MODES != BARE) begin : gen_decode_exceptions // 开始生成块，在编译期展开硬件结构。
    logic new_exception; // 声明信号、变量或生成变量。
    exception_code_t ecode;
    exception_code_t ecall_code;
    logic [31:0] tval; // 声明信号、变量或生成变量。

    //ECALL and EBREAK captured here, but seperated out when ecode is set
    assign illegal_instruction_pattern = ~|unit_needed; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //ECALL/EBREAK
    //The type of call instruction is depedent on the current privilege level
    logic is_ecall; // 声明信号、变量或生成变量。
    logic is_ebreak; // 声明信号、变量或生成变量。
    assign is_ecall = decode.instruction inside {ECALL}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign is_ebreak = decode.instruction inside {EBREAK}; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case (current_privilege) // 开始多分支选择，根据表达式选择对应分支。
            USER_PRIVILEGE : ecall_code = ECALL_U;
            SUPERVISOR_PRIVILEGE : ecall_code = ECALL_S;
            MACHINE_PRIVILEGE : ecall_code = ECALL_M;
            default : ecall_code = ECALL_U; // 执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue_stage_ready) begin // 执行条件判断，满足条件时进入对应分支。
            if (~decode.fetch_metadata.ok) // 执行条件判断，满足条件时进入对应分支。
                ecode <= decode.fetch_metadata.error_code;
            else if (is_ecall) // 执行否则如果分支的条件判断。
                ecode <= ecall_code;
            else if (is_ebreak) // 执行否则如果分支的条件判断。
                ecode <= BREAK;
            else // 执行否则分支。
                ecode <= ILLEGAL_INST;

            if (~decode.fetch_metadata.ok | is_ebreak) // 执行条件判断，满足条件时进入对应分支。
                tval <= decode.pc;
            else if (is_ecall) // 执行否则如果分支的条件判断。
                tval <= '0;
            else // 执行否则分支。
                tval <= decode.instruction;
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Exception generation (ecall/ebreak/illegal instruction/propagated fetch error)
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            pre_issue_exception_pending <= 0;
        else if (issue_stage_ready) // 执行否则如果分支的条件判断。
            pre_issue_exception_pending <= illegal_instruction_pattern | (~decode.fetch_metadata.ok);
    end // 结束语句块。

    assign new_exception = issue.stage_valid & pre_issue_exception_pending & ~(gc.issue_hold | gc.fetch_flush) & ~exception.valid; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            exception.valid <= 0;
        else // 执行否则分支。
            exception.valid <= new_exception;
    end // 结束语句块。

    assign exception.possible = 0; //Not needed because occurs before issue；执行连续赋值，把组合逻辑连接到目标信号。
    assign exception.code = ecode; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign exception.tval = tval; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign exception.pc = issue.pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign exception.discard = 0; // 执行连续赋值，把组合逻辑连接到目标信号。

    end endgenerate // 结束语句块。
    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions

endmodule // 结束模块定义。
