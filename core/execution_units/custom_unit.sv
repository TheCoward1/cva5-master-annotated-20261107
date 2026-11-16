// ============================================================================
// 文件：core/execution_units/custom_unit.sv
// 类型：module
// 名称：custom_unit
// 作用：处理自定义扩展指令的执行和写回。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2022 Eric Matthews
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

module custom_unit // 定义 custom_unit 模块。

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
    logic [31:0] result; // 声明信号、变量或生成变量。
    logic done; // 声明信号、变量或生成变量。
    id_t id;
    ////////////////////////////////////////////////////
    //Implementation
    //Simple 2-cycle adder that adds rs1 and rs2
    //that has a throughput of 1 (so long as the result is accepted by the writeback stage)

    ////////////////////////////////////////////////////
    //Decode
    assign instruction = decode_stage.instruction; // 执行连续赋值，把组合逻辑连接到目标信号。

    //The following signals should be asserted when the decoded instruction
    //is handled by this execution unit.
    assign unit_needed = decode_stage.instruction inside {CUSTOM}; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        uses_rs = '0;
        uses_rs[RS1] = decode_stage.instruction inside {CUSTOM};
        uses_rs[RS2] = decode_stage.instruction inside {CUSTOM};
        uses_rd = decode_stage.instruction inside {CUSTOM};
    end // 结束语句块。
    ////////////////////////////////////////////////////
    //Issue
    assign issue.ready = ~wb.done; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
            id <=  issue.id;
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
           result <= rf[RS1] + rf[RS2];
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Write-back
    assign wb.rd = result; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            wb.done <= 0;
        else // 执行否则分支。
            wb.done <= (wb.done & ~wb.ack) | issue.new_request;
    end // 结束语句块。
    assign wb.id = id; // 执行连续赋值，把组合逻辑连接到目标信号。
endmodule // 结束模块定义。
