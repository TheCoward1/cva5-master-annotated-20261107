// ============================================================================
// 文件：core/execution_units/alu_unit.sv
// 类型：module
// 名称：alu_unit
// 作用：执行 RISC-V 整数算术、逻辑、移位、比较和常量运算。
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

module alu_unit // 定义 alu_unit 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    import opcodes::*; // 导入包或命名空间：opcodes::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        input decode_packet_t decode_stage, // 声明输入端口。
        output unit_needed, // 声明输出端口。
        output logic [REGFILE_READ_PORTS-1:0] uses_rs, // 声明输出端口。
        output logic uses_rd, // 声明输出端口。
        
        input issue_packet_t issue_stage, // 声明输入端口。
        input logic issue_stage_ready, // 声明输入端口。
        input logic [31:0] constant_alu, // 声明输入端口。
        input rs_addr_t issue_rs_addr [REGFILE_READ_PORTS], // 声明输入端口。
        input logic [31:0] rf [REGFILE_READ_PORTS], // 声明输入端口。

        unit_issue_interface.unit issue,
        unit_writeback_interface.unit wb
    );
// 定义类型别名或枚举/结构类型。
    typedef enum logic [1:0] {
        LOGIC_XOR = 2'b00,
        LOGIC_OR = 2'b01,
        LOGIC_AND = 2'b10,
        LOGIC_OTHER = 2'b11
    } logic_op_t;

    common_instruction_t instruction;//rs1_addr, rs2_addr, fn3, fn7, rd_addr, upper/lower opcode

    logic [31:0] rs2_data; // 声明信号、变量或生成变量。
    logic imm_type; // 声明信号、变量或生成变量。
    alu_op_t alu_op;
    alu_op_t alu_op_r;
    logic_op_t logic_op;
    logic_op_t logic_op_r;
    logic subtract; // 声明信号、变量或生成变量。
    logic is_slt; // 声明信号、变量或生成变量。

    logic[32:0] add_sub_result; // 声明信号、变量或生成变量。
    logic add_sub_carry_in; // 声明信号、变量或生成变量。
    logic[31:0] logic_and_upper_slt; // 声明信号、变量或生成变量。
    logic[32:0] sign_ext_adder1; // 声明信号、变量或生成变量。
    logic[32:0] sign_ext_adder2; // 声明信号、变量或生成变量。
    logic[31:0] shift_result; // 声明信号、变量或生成变量。
    logic[31:0] result; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation

    ////////////////////////////////////////////////////
    //Decode
    assign instruction = decode_stage.instruction; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign unit_needed = decode_stage.instruction inside { // 执行连续赋值，把组合逻辑连接到目标信号。
        LUI, AUIPC, JAL, JALR,
        ADDI, SLLI, SLTI, SLTIU, XORI, SRLI, SRAI, ORI, ANDI,
        ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
    };
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        uses_rs = '0;
        uses_rs[RS1] = decode_stage.instruction inside {
            JALR,
            ADDI, SLLI, SLTI, SLTIU, XORI, SRLI, SRAI, ORI, ANDI,
            ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
        };
        uses_rs[RS2] = decode_stage.instruction inside {
            ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
        };
        uses_rd = decode_stage.instruction inside {
            LUI, AUIPC, JAL, JALR,
            ADDI, SLLI, SLTI, SLTIU, XORI, SRLI, SRAI, ORI, ANDI,
            ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
        };
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case (instruction.upper_opcode) inside // 开始多分支选择，根据表达式选择对应分支。
            LUI_T, AUIPC_T, JAL_T, JALR_T : alu_op = ALU_CONSTANT;
            default : // 执行默认分支。
            case (instruction.fn3) inside // 开始多分支选择，根据表达式选择对应分支。
                XOR_fn3, OR_fn3, AND_fn3, SLTU_fn3, SLT_fn3 : alu_op = ALU_SLT;
                SLL_fn3, SRA_fn3 : alu_op = ALU_SHIFT;
                default : alu_op = ALU_ADD_SUB; // 执行默认分支。
            endcase // 结束多分支选择。
        endcase // 结束多分支选择。
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case (instruction.fn3) inside // 开始多分支选择，根据表达式选择对应分支。
            XOR_fn3 : logic_op = LOGIC_XOR;
            OR_fn3 : logic_op = LOGIC_OR;
            AND_fn3 : logic_op = LOGIC_AND;
            default : logic_op = LOGIC_OTHER; // 执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

    //Constant ALU:
    //  provides LUI, AUIPC, JAL, JALR results for ALU
    //  provides PC+4 for BRANCH unit and ifence in GC unit
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue_stage_ready) begin // 执行条件判断，满足条件时进入对应分支。
            imm_type <= instruction.upper_opcode inside {ARITH_IMM_T};
            alu_op_r <= alu_op;
            logic_op_r <= logic_op;
            subtract <= decode_stage.instruction inside {SUB, SLTI, SLTIU, SLT, SLTU};
            is_slt <= instruction.fn3 inside {SLT_fn3, SLTU_fn3};
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Issue
    //Logic ops put through the adder carry chain to reduce resources
    //TODO: explore moving this mux into the regfile bypass mux
    assign rs2_data = imm_type ? 32'(signed'(issue_stage.instruction[31:20])) : rf[RS2]; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case (logic_op_r) // 开始多分支选择，根据表达式选择对应分支。
            LOGIC_XOR : logic_and_upper_slt = rf[RS1] ^ rs2_data;
            LOGIC_OR : logic_and_upper_slt = rf[RS1] | rs2_data;
            LOGIC_AND : logic_and_upper_slt = rf[RS1] & rs2_data;
            default : logic_and_upper_slt = 0; //ADD/SUB/SLT/SLTU；执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

    //Add/Sub ops
    assign sign_ext_adder1 = {(rf[RS1][31] & ~issue_stage.fn3[0]), rf[RS1]}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign sign_ext_adder2 = {(rs2_data[31] & ~issue_stage.fn3[0]) ^ subtract, rs2_data ^ {32{subtract}}}; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign {add_sub_result, add_sub_carry_in} = {sign_ext_adder1, 1'b1} + {sign_ext_adder2, subtract}; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    //Shift ops
    barrel_shifter shifter (
        .shifter_input(rf[RS1]),
        .shift_amount(imm_type ? issue_rs_addr[RS2] : rf[RS2][4:0]),
        .arith(rf[RS1][31] & issue_stage.instruction[30]),
        .lshift(~issue_stage.fn3[2]),
        .shifted_result(shift_result)
    );

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case (alu_op_r) // 开始多分支选择，根据表达式选择对应分支。
            ALU_CONSTANT : result = constant_alu;//LUI, AUIPC, JAL, JALR
            ALU_ADD_SUB : result = add_sub_result[31:0];
            ALU_SLT : result = {logic_and_upper_slt[31:1], is_slt ? add_sub_result[32] : logic_and_upper_slt[0]};
            default : result = shift_result; //ALU_SHIFT；执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Output
    assign issue.ready = 1; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.rd = result; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.done = issue.possible_issue; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.id = issue.id; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Assertions

endmodule // 结束模块定义。
