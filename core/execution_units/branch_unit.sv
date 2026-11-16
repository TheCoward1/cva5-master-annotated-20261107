// ============================================================================
// 文件：core/execution_units/branch_unit.sv
// 类型：module
// 名称：branch_unit
// 作用：解析分支和跳转条件，生成重定向和错误预测处理信号。
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

module branch_unit // 定义 branch_unit 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
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
        input logic [31:0] constant_alu, // 声明输入端口。
        input logic [31:0] rf [REGFILE_READ_PORTS], // 声明输入端口。

        unit_issue_interface.unit issue,
        output branch_results_t br_results, // 声明输出端口。
        output logic branch_flush, // 声明输出端口。

        exception_interface.unit exception
    );
    common_instruction_t instruction;//rs1_addr, rs2_addr, fn3, fn7, rd_addr, upper/lower opcode

    logic branch_issued_r; // 声明信号、变量或生成变量。
    logic result; // 声明信号、变量或生成变量。

    //Branch Predictor
    logic branch_taken; // 声明信号、变量或生成变量。
    logic branch_taken_ex; // 声明信号、变量或生成变量。

    id_t id_ex;
    logic [31:0] jump_pc; // 声明信号、变量或生成变量。
    logic [31:0] new_pc; // 声明信号、变量或生成变量。
    logic [31:0] new_pc_ex; // 声明信号、变量或生成变量。

    logic instruction_is_completing; // 声明信号、变量或生成变量。

    logic branch_complete; // 声明信号、变量或生成变量。
    logic jal_or_jalr_ex; // 声明信号、变量或生成变量。

    logic [32:0] rs1; // 声明信号、变量或生成变量。
    logic [32:0] rs2; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation

    ////////////////////////////////////////////////////
    //Decode
    assign instruction = decode_stage.instruction; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign unit_needed = decode_stage.instruction inside { // 执行连续赋值，把组合逻辑连接到目标信号。
        BEQ, BNE, BLT, BGE, BLTU, BGEU, JALR, JAL
    };
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        uses_rs = '0;
        uses_rs[RS1] = decode_stage.instruction inside {
            BEQ, BNE, BLT, BGE, BLTU, BGEU, JALR
        };
        uses_rs[RS2] = decode_stage.instruction inside {
            BEQ, BNE, BLT, BGE, BLTU, BGEU
        };
        uses_rd = 0;//JALR/JAL writeback handled by ALU
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //RAS Support
    logic rs1_link; // 声明信号、变量或生成变量。
    logic rd_link; // 声明信号、变量或生成变量。
    logic rs1_eq_rd; // 声明信号、变量或生成变量。
    logic is_return; // 声明信号、变量或生成变量。
    logic is_call; // 声明信号、变量或生成变量。

    assign rs1_link = instruction.rs1_addr inside {1,5}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rd_link = instruction.rd_addr inside {1,5}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs1_eq_rd = (instruction.rs1_addr == instruction.rd_addr); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue_stage_ready) begin // 执行条件判断，满足条件时进入对应分支。
            is_return <= (instruction.upper_opcode inside {JALR_T}) & ((rs1_link & ~rd_link) | (rs1_link & rd_link & ~rs1_eq_rd));
            is_call <= (instruction.upper_opcode inside {JAL_T, JALR_T}) & rd_link;
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //PC Offset
    logic[19:0] jal_imm; // 声明信号、变量或生成变量。
    logic[11:0] jalr_imm; // 声明信号、变量或生成变量。
    logic[11:0] br_imm; // 声明信号、变量或生成变量。

    logic [20:0] pc_offset; // 声明信号、变量或生成变量。
    logic [20:0] pc_offset_r; // 声明信号、变量或生成变量。
    assign jal_imm = {decode_stage.instruction[31], decode_stage.instruction[19:12], decode_stage.instruction[20], decode_stage.instruction[30:21]}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign jalr_imm = decode_stage.instruction[31:20]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign br_imm = {decode_stage.instruction[31], decode_stage.instruction[7], decode_stage.instruction[30:25], decode_stage.instruction[11:8]}; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case (decode_stage.instruction[3:2]) // 开始多分支选择，根据表达式选择对应分支。
            2'b11 : pc_offset = 21'(signed'({jal_imm, 1'b0}));
            2'b01 : pc_offset = 21'(signed'(jalr_imm));
            default : pc_offset = 21'(signed'({br_imm, 1'b0})); // 执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue_stage_ready) // 执行条件判断，满足条件时进入对应分支。
            pc_offset_r <= pc_offset;
    end // 结束语句块。
    ////////////////////////////////////////////////////

    logic jalr; // 声明信号、变量或生成变量。
    logic jal_or_jalr; // 声明信号、变量或生成变量。
    logic br_use_signed; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue_stage_ready) begin // 执行条件判断，满足条件时进入对应分支。
            jalr <= (~decode_stage.instruction[3] & decode_stage.instruction[2]);
            jal_or_jalr <= decode_stage.instruction[2];
            br_use_signed <= !(instruction.fn3 inside {BLTU_fn3, BGEU_fn3});
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Issue

    //Only stall condition is if the following instruction is not valid for pc comparisons.
    //If the next instruction isn't valid, no instruction can be issued anyways, so it
    //is safe to hardcode this to one.
    assign issue.ready = 1; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Branch new request is held if the following instruction hasn't arrived at decode/issue yet
    set_clr_reg_with_rst #(.SET_OVER_CLR(1), .WIDTH(1), .RST_VALUE(0)) branch_issued_m (
      .clk, .rst,
      .set(issue.new_request),
      .clr(issue_stage.stage_valid | exception.valid),
      .result(branch_issued_r)
    );

    //To determine if the branch was predicted correctly we need to wait until the
    //subsequent instruction has reached the issue stage
    assign instruction_is_completing = branch_issued_r & issue_stage.stage_valid; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Sign extend
    assign rs1 = {(rf[RS1][31] & br_use_signed), rf[RS1]}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs2 = {(rf[RS2][31] & br_use_signed), rf[RS2]}; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Branch/Jump target determination
    //Branch comparison and final address calculation
    //are performed in the issue stage
    branch_comparator bc (
        .less_than(issue_stage.fn3[2]),
        .a(rs1),
        .b(rs2),
        .xor_result(issue_stage.fn3[0]),
        .result(result)
    );
    assign branch_taken = result | jal_or_jalr; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign jump_pc = (jalr ? rs1[31:0] : issue_stage.pc) + 32'(signed'(pc_offset_r)); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign new_pc = branch_taken ? jump_pc : constant_alu; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) begin // 执行条件判断，满足条件时进入对应分支。
            branch_taken_ex <= branch_taken;
            new_pc_ex <= {new_pc[31:1], new_pc[0]  & ~jalr};
            id_ex <= issue.id;
            jal_or_jalr_ex <= jal_or_jalr;
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Exception support
    generate if (CONFIG.MODES != BARE) begin : gen_branch_exception // 开始生成块，在编译期展开硬件结构。
        logic new_exception; // 声明信号、变量或生成变量。

        assign new_exception = new_pc[1] & branch_taken & issue.new_request; // 执行连续赋值，把组合逻辑连接到目标信号。
        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) // 执行条件判断，满足条件时进入对应分支。
                exception.valid <= 0;
            else // 执行否则分支。
                exception.valid <= new_exception;
        end // 结束语句块。

        assign exception.possible = 0; //Not needed because branch_flush suppresses issue；执行连续赋值，把组合逻辑连接到目标信号。
        assign exception.code = INST_ADDR_MISSALIGNED; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign exception.tval = new_pc_ex; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign exception.pc = issue_stage.pc_r; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign exception.discard = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    end // 结束语句块。
    endgenerate // 结束生成块。

    ////////////////////////////////////////////////////
    //Predictor support
    logic is_return_ex; // 声明信号、变量或生成变量。
    logic is_call_ex; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.possible_issue) begin // 执行条件判断，满足条件时进入对应分支。
            is_return_ex <= is_return;
            is_call_ex <= is_call;
        end // 结束语句块。
    end // 结束语句块。

    assign br_results.id = id_ex; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign br_results.valid = instruction_is_completing; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign br_results.pc = issue_stage.pc_r; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign br_results.target_pc = new_pc_ex; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign br_results.branch_taken = branch_taken_ex; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign br_results.is_branch = ~jal_or_jalr_ex; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign br_results.is_return = is_return_ex; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign br_results.is_call = is_call_ex; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign branch_flush = instruction_is_completing & (issue_stage.pc[31:1] != new_pc_ex[31:1]); // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions

endmodule // 结束模块定义。
