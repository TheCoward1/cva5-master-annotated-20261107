// ============================================================================
// 文件：core/execution_units/div_unit.sv
// 类型：module
// 名称：div_unit
// 作用：实现整数除法功能单元，使用 clz 对操作数归一化并处理符号、除零和余数。
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

module div_unit // 定义 div_unit 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    import opcodes::*; // 导入包或命名空间：opcodes::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        input gc_outputs_t gc, // 声明输入端口。

        input logic instruction_issued_with_rd, // 声明输入端口。

        input decode_packet_t decode_stage, // 声明输入端口。
        output logic unit_needed, // 声明输出端口。
        output logic [REGFILE_READ_PORTS-1:0] uses_rs, // 声明输出端口。
        output logic uses_rd, // 声明输出端口。
        
        input issue_packet_t issue_stage, // 声明输入端口。
        input logic issue_stage_ready, // 声明输入端口。
        input rs_addr_t issue_rs_addr [REGFILE_READ_PORTS], // 声明输入端口。
        input logic [31:0] rf [REGFILE_READ_PORTS], // 声明输入端口。

        unit_issue_interface.unit issue,
        unit_writeback_interface.unit wb
    );
    common_instruction_t instruction;//rs1_addr, rs2_addr, fn3, fn7, rd_addr, upper/lower opcode
    logic mult_div_op; // 声明信号、变量或生成变量。

    logic signed_divop; // 声明信号、变量或生成变量。
    logic negate_quotient; // 声明信号、变量或生成变量。
    logic negate_remainder; // 声明信号、变量或生成变量。
    logic negate_dividend; // 声明信号、变量或生成变量。
    logic negate_divisor; // 声明信号、变量或生成变量。
    logic remainder_op; // 声明信号、变量或生成变量。

    logic [31:0] unsigned_dividend; // 声明信号、变量或生成变量。
    logic [31:0] unsigned_divisor; // 声明信号、变量或生成变量。
    logic [$clog2(32)-1:0] dividend_CLZ; // 声明信号、变量或生成变量。
    logic [$clog2(32)-1:0] divisor_CLZ; // 声明信号、变量或生成变量。

    logic divisor_is_zero; // 声明信号、变量或生成变量。

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic remainder_op; // 声明信号、变量或生成变量。
        logic negate_result; // 声明信号、变量或生成变量。
        id_t id;
    } div_attributes_t;
    div_attributes_t wb_attr;

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic [XLEN-1:0] unsigned_dividend; // 声明信号、变量或生成变量。
        logic [XLEN-1:0] unsigned_divisor; // 声明信号、变量或生成变量。
        logic [$clog2(32)-1:0] dividend_CLZ; // 声明信号、变量或生成变量。
        logic [$clog2(32)-1:0] divisor_CLZ; // 声明信号、变量或生成变量。
        logic divisor_is_zero; // 声明信号、变量或生成变量。
        logic reuse_result; // 声明信号、变量或生成变量。
        div_attributes_t attr;
    } div_fifo_inputs_t;

    unsigned_division_interface #(.DATA_WIDTH(32)) div_core();

    logic in_progress; // 声明信号、变量或生成变量。
    logic div_done; // 声明信号、变量或生成变量。

    fifo_interface #(.DATA_TYPE(div_fifo_inputs_t)) input_fifo();

    function logic [31:0] negate_if  (input logic [31:0] a, logic b); // 开始函数定义，用于组合计算或辅助逻辑。
        return ({32{b}} ^ a) + 32'(b); // 返回函数结果。
    endfunction // 结束函数定义。
    ////////////////////////////////////////////////////
    //Implementation

    ////////////////////////////////////////////////////
    //Decode
    assign unit_needed = decode_stage.instruction inside {DIV, DIVU, REM, REMU}; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        uses_rs = '0;
        uses_rs[RS1] = unit_needed;
        uses_rs[RS2] = unit_needed;
        uses_rd = unit_needed;
    end // 结束语句块。
    ////////////////////////////////////////////////////
    //Issue

    ////////////////////////////////////////////////////
    //Result resuse (for div/rem pairs)
    rs_addr_t prev_div_rs_addr [2];
    logic [1:0] div_rd_match; // 声明信号、变量或生成变量。
    logic prev_div_result_valid; // 声明信号、变量或生成变量。
    logic div_rs_overwrite; // 声明信号、变量或生成变量。
    logic div_op_reuse; // 声明信号、变量或生成变量。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue.new_request) // 执行条件判断，满足条件时进入对应分支。
            prev_div_rs_addr <= issue_rs_addr[RS1:RS2];
    end // 结束语句块。

    assign div_op_reuse = {prev_div_result_valid, prev_div_rs_addr[RS1], prev_div_rs_addr[RS2]} == {1'b1, issue_rs_addr[RS1],issue_rs_addr[RS2]}; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Clear if prev div inputs are overwritten by another instruction
    assign div_rd_match[RS1] = (issue_stage.rd_addr == prev_div_rs_addr[RS1]); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_rd_match[RS2] = (issue_stage.rd_addr == prev_div_rs_addr[RS2]); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_rs_overwrite = |div_rd_match; // 执行连续赋值，把组合逻辑连接到目标信号。

    set_clr_reg_with_rst #(.SET_OVER_CLR(1), .WIDTH(1), .RST_VALUE(0)) prev_div_result_valid_m (
        .clk, .rst,
        .set(issue.new_request & ~((issue_stage.rd_addr == issue_rs_addr[RS1]) | (issue_stage.rd_addr == issue_rs_addr[RS2]))),
        .clr((instruction_issued_with_rd & div_rs_overwrite) | gc.init_clear), //No instructions will be issued while gc.init_clear is asserted
        .result(prev_div_result_valid)
    );

    ////////////////////////////////////////////////////
    //Input and output sign determination
    assign signed_divop = ~ issue_stage.fn3[0]; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign negate_dividend = signed_divop & rf[RS1][31]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign negate_divisor = signed_divop & rf[RS2][31]; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign negate_quotient = signed_divop & (rf[RS1][31] ^ rf[RS2][31]); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign negate_remainder = signed_divop & (rf[RS1][31]); // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Input Processing
    assign unsigned_dividend = negate_if (rf[RS1], negate_dividend); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign unsigned_divisor = negate_if (rf[RS2], negate_divisor); // 执行连续赋值，把组合逻辑连接到目标信号。

    //Note: If this becomes the critical path, we can use the one's complemented input instead.
    //It will potentially overestimate (only when the input is a negative power-of-two), and
    //the divisor width will need to be increased by one to safely handle the case where the divisor CLZ is overestimated
    clz #(.WIDTH(32)) dividend_clz_block (
        .clz_input(unsigned_dividend),
        .clz(dividend_CLZ),
        .zero()
    );
    clz #(.WIDTH(32)) divisor_clz_block (
        .clz_input(unsigned_divisor),
        .clz(divisor_CLZ),
        .zero(divisor_is_zero)
    );

    ////////////////////////////////////////////////////
    //Input FIFO
    //Currently just a register (DEPTH=1).  As one div instruction can be in-progress
    //and one in this input "fifo," we can support two in-flight div ops.
    cva5_fifo #(.DATA_TYPE(div_fifo_inputs_t), .FIFO_DEPTH(1))
    div_input_fifo (
        .clk    (clk),
        .rst    (rst),
        .fifo   (input_fifo)
    );

    logic div_ready; // 声明信号、变量或生成变量。
    assign div_ready = (~in_progress) | wb.ack; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign input_fifo.data_in = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        unsigned_dividend : unsigned_dividend,
        unsigned_divisor : unsigned_divisor,
        dividend_CLZ : divisor_is_zero ? '0 : dividend_CLZ,
        divisor_CLZ : divisor_CLZ,
        divisor_is_zero : divisor_is_zero,
        reuse_result : div_op_reuse,
        attr : '{
            remainder_op : issue_stage.fn3[1],
            negate_result : (issue_stage.fn3[1] ? negate_remainder : (negate_quotient & ~divisor_is_zero)),
            id : issue.id
        }
    };
    assign input_fifo.push = issue.new_request; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign input_fifo.potential_push = issue.possible_issue; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign issue.ready = ~input_fifo.full | (~in_progress); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign input_fifo.pop = input_fifo.valid & div_ready; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Control Signals
    assign div_core.start = input_fifo.pop & ~input_fifo.data_out.reuse_result; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_done = div_core.done | (input_fifo.pop & input_fifo.data_out.reuse_result); // 执行连续赋值，把组合逻辑连接到目标信号。

    //If more than one cycle, set in_progress so that multiple div.start signals are not sent to the div unit.
    set_clr_reg_with_rst #(.SET_OVER_CLR(1), .WIDTH(1), .RST_VALUE('0))
    in_progress_m (
      .clk, .rst,
      .set(input_fifo.pop),
      .clr(wb.ack),
      .result(in_progress)
    );
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (input_fifo.pop) // 执行条件判断，满足条件时进入对应分支。
            wb_attr <= input_fifo.data_out.attr;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Div core
    assign div_core.dividend = input_fifo.data_out.unsigned_dividend; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_core.divisor = input_fifo.data_out.unsigned_divisor; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_core.dividend_CLZ = input_fifo.data_out.dividend_CLZ; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_core.divisor_CLZ = input_fifo.data_out.divisor_CLZ; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign div_core.divisor_is_zero = input_fifo.data_out.divisor_is_zero; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    div_core #(.DIV_WIDTH(32))
    divider_block (
        .clk(clk),
        .rst(rst),
        .div(div_core)
    );

    ////////////////////////////////////////////////////
    //Output
    assign wb.rd = negate_if (wb_attr.remainder_op ? div_core.remainder : div_core.quotient, wb_attr.negate_result); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            wb.done <= 0;
        else // 执行否则分支。
            wb.done <= (wb.done & ~wb.ack) | div_done;
    end // 结束语句块。

    assign wb.id = wb_attr.id; // 执行连续赋值，把组合逻辑连接到目标信号。
    ////////////////////////////////////////////////////
    //Assertions

endmodule // 结束模块定义。
