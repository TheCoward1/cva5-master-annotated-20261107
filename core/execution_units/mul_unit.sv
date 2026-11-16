// ============================================================================
// 文件：core/execution_units/mul_unit.sv
// 类型：module
// 名称：mul_unit
// 作用：实现整数乘法功能单元。
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

module mul_unit // 定义 mul_unit 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    import opcodes::*; // 导入包或命名空间：opcodes::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        input decode_packet_t decode_stage, // 声明输入端口。
        output logic unit_needed, // 声明输出端口。
        output logic [REGFILE_READ_PORTS-1:0] uses_rs, // 声明输出端口。
        output logic uses_rd, // 声明输出端口。

        input issue_packet_t issue_stage, // 声明输入端口。
        input logic issue_stage_ready, // 声明输入端口。
        input logic [31:0] rf [REGFILE_READ_PORTS], // 声明输入端口。

        unit_issue_interface.unit issue,
        unit_writeback_interface.unit wb
    );
    common_instruction_t instruction;//rs1_addr, rs2_addr, fn3, fn7, rd_addr, upper/lower opcode
    
    logic signed [63:0] result; // 声明信号、变量或生成变量。
    logic mulh [2]; // 声明信号、变量或生成变量。
    logic valid [2]; // 声明信号、变量或生成变量。
    id_t id [2];

    logic rs1_is_signed, rs2_is_signed, is_mulhx; // 声明信号、变量或生成变量。
    logic signed [32:0] rs1_ext, rs2_ext; // 声明信号、变量或生成变量。
    logic signed [32:0] rs1_r, rs2_r; // 声明信号、变量或生成变量。

    logic stage1_advance; // 声明信号、变量或生成变量。
    logic stage2_advance; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation

    ////////////////////////////////////////////////////
    //Decode
    assign unit_needed = decode_stage.instruction inside {MUL, MULH, MULHSU, MULHU}; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        uses_rs = '0;
        uses_rs[RS1] = unit_needed;
        uses_rs[RS2] = unit_needed;
        uses_rd = unit_needed;
    end // 结束语句块。

    assign instruction = decode_stage.instruction; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue_stage_ready) begin // 执行条件判断，满足条件时进入对应分支。
            rs1_is_signed <= instruction.fn3[1:0] inside {MULH_fn3[1:0], MULHSU_fn3[1:0]};
            rs2_is_signed <= instruction.fn3[1:0] inside {MULH_fn3[1:0]};
            is_mulhx <= instruction.fn3[1:0] inside {MULH_fn3[1:0], MULHSU_fn3[1:0], MULHU_fn3[1:0]};
        end // 结束语句块。
    end // 结束语句块。
    ////////////////////////////////////////////////////
    //Issue
    assign rs1_ext = signed'({rs1_is_signed & rf[RS1][31], rf[RS1]}); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign rs2_ext = signed'({rs2_is_signed & rf[RS2][31], rf[RS2]}); // 执行连续赋值，把组合逻辑连接到目标信号。

    //Pipeline advancement control signals
    assign issue.ready = stage1_advance; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign stage1_advance = ~valid[0] | stage2_advance; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign stage2_advance = ~valid[1] | wb.ack; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Input and output registered Multiply
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (stage1_advance) begin // 执行条件判断，满足条件时进入对应分支。
            rs1_r <= rs1_ext;
            rs2_r <= rs2_ext;
        end // 结束语句块。
        if (stage2_advance) begin // 执行条件判断，满足条件时进入对应分支。
            result <= 64'(rs1_r * rs2_r);
        end // 结束语句块。
    end // 结束语句块。

    //Attribute Pipeline
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (stage1_advance) begin // 执行条件判断，满足条件时进入对应分支。
            mulh[0] <= is_mulhx;
            id[0] <= issue.id;
        end // 结束语句块。
        if (stage2_advance) begin // 执行条件判断，满足条件时进入对应分支。
            mulh[1] <= mulh[0];
            id[1] <= id[0];
        end // 结束语句块。
    end // 结束语句块。

    //Valid/Done Pipeline
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            valid <= '{default: 0};
        else begin // 执行否则分支。
            valid[0] <= stage1_advance ? issue.new_request : valid[0];
            valid[1] <= stage2_advance ? valid[0] : valid[1];
        end // 结束语句块。
    end // 结束语句块。

    //WB interface
    ////////////////////////////////////////////////////
    assign wb.rd = mulh[1] ? result[63:32] : result[31:0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.done = valid[1]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb.id = id[1]; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions

endmodule // 结束模块定义。
