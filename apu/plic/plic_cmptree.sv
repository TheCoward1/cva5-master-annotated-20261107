// ============================================================================
// 文件：apu/plic/plic_cmptree.sv
// 类型：module
// 名称：plic_cmptree
// 作用：实现 PLIC 的优先级比较树，用于选择最高优先级中断。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2024 Chris Keilbart, Mohammad Shahidzadeh
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
 *             Chris Keilbart <ckeilbar@sfu.ca>
 *             Mohammad Shahidzadeh <mohammad_shahidzadeh_asadi@sfu.ca>
 */

module plic_cmptree // 定义 plic_cmptree 模块。

    #(
        parameter int unsigned NUM_IRQS = 2, // 声明可配置参数。
        parameter int unsigned PRIORITY_W = 4, // 声明可配置参数。
        parameter int unsigned REG_STAGE_W = 2 // 声明可配置参数。
    ) (
        input logic clk, // 声明输入端口。

        input logic[NUM_IRQS-1:0] irq_valid, // 声明输入端口。
        input logic[NUM_IRQS-1:0][PRIORITY_W-1:0] irq_priority, // 声明输入端口。
        output logic[$clog2(NUM_IRQS)-1:0] highest_id, // 声明输出端口。
        output logic[PRIORITY_W-1:0] highest_priority, // 声明输出端口。
        output logic highest_valid // 声明输出端口。
    );

    localparam ID_W = $clog2(NUM_IRQS); // 声明局部常量。
    localparam PADDED_W = 2**ID_W; // 声明局部常量。

    ////////////////////////////////////////////////////
    //PLIC Comparison Tree
    //The interrupt with the highest priority must be selected
    //Ties are broken by the index, with lower values taking priority
    //Implemented as a binary tree, and the outputs of a certain layer are registered

    //Pad to next power of two
    logic[PADDED_W-1:0] padded_irq_valid; // 声明信号、变量或生成变量。
    logic[PADDED_W-1:0][PRIORITY_W-1:0] padded_irq_priority; // 声明信号、变量或生成变量。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < PADDED_W; i++) begin // 执行循环或遍历。
            padded_irq_valid[i] = i < NUM_IRQS ? irq_valid[i] : 1'b0;
            padded_irq_priority[i] = i < NUM_IRQS ? irq_priority[i] : '0;
        end // 结束语句块。
    end // 结束语句块。

    //Same no matter the stage
    logic left_valid; // 声明信号、变量或生成变量。
    logic[PRIORITY_W-1:0] left_priority; // 声明信号、变量或生成变量。
    logic right_valid; // 声明信号、变量或生成变量。
    logic[PRIORITY_W-1:0] right_priority; // 声明信号、变量或生成变量。
    logic chose_valid; // 声明信号、变量或生成变量。
    logic chose_left; // 声明信号、变量或生成变量。
    logic[PRIORITY_W-1:0] chose_priority; // 声明信号、变量或生成变量。

    assign chose_valid = left_valid | right_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign chose_left = left_valid & (~right_valid | left_priority > right_priority); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign chose_priority = chose_left ? left_priority : right_priority; // 执行连续赋值，把组合逻辑连接到目标信号。


    //Recursive or base case
    generate if (NUM_IRQS == 2) begin : gen_base_case // 开始生成块，在编译期展开硬件结构。
        assign {left_valid, right_valid} = irq_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign {left_priority, right_priority} = irq_priority; // 执行连续赋值，把组合逻辑连接到目标信号。

        if (REG_STAGE_W == 2) begin : gen_ff // 执行条件判断，满足条件时进入对应分支。
            always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
                highest_id[0] <= chose_left;
                highest_priority <= chose_priority;
                highest_valid <= chose_valid;
            end // 结束语句块。
        end else begin : gen_no_ff // 结束语句块。
            assign highest_id[0] = chose_left; // 执行连续赋值，把组合逻辑连接到目标信号。
            assign highest_priority = chose_priority; // 执行连续赋值，把组合逻辑连接到目标信号。
            assign highest_valid = chose_priority; // 执行连续赋值，把组合逻辑连接到目标信号。
        end // 结束语句块。
    end else begin : gen_recursive_case // 结束语句块。
        logic[ID_W-2:0] left_id; // 声明信号、变量或生成变量。
        plic_cmptree #(.NUM_IRQS(PADDED_W/2), .PRIORITY_W(PRIORITY_W), .REG_STAGE_W(REG_STAGE_W)) left_tree (
            .irq_valid(padded_irq_valid[PADDED_W-1:PADDED_W/2]),
            .irq_priority(padded_irq_priority[PADDED_W-1:PADDED_W/2]),
            .highest_id(left_id),
            .highest_priority(left_priority),
            .highest_valid(left_valid),
        .*);

        logic[ID_W-2:0] right_id; // 声明信号、变量或生成变量。
        plic_cmptree #(.NUM_IRQS(PADDED_W/2), .PRIORITY_W(PRIORITY_W), .REG_STAGE_W(REG_STAGE_W)) right_tree (
            .irq_valid(padded_irq_valid[PADDED_W/2-1:0]),
            .irq_priority(padded_irq_priority[PADDED_W/2-1:0]),
            .highest_id(right_id),
            .highest_priority(right_priority),
            .highest_valid(right_valid),
        .*);

        if (REG_STAGE_W == NUM_IRQS) begin : gen_ff // 执行条件判断，满足条件时进入对应分支。
            always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
                highest_id[ID_W-1] <= chose_left;
                highest_id[ID_W-2:0] <= chose_left ? left_id : right_id;
                highest_priority <= chose_priority;
                highest_valid <= chose_valid;
            end // 结束语句块。
        end else begin : gen_no_ff // 结束语句块。
            assign highest_id[ID_W-1] = chose_left; // 执行连续赋值，把组合逻辑连接到目标信号。
            assign highest_id[ID_W-2:0] = chose_left ? left_id : right_id; // 执行连续赋值，把组合逻辑连接到目标信号。
            assign highest_priority = chose_priority; // 执行连续赋值，把组合逻辑连接到目标信号。
            assign highest_valid = chose_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
        end // 结束语句块。
    end endgenerate // 结束语句块。

endmodule // 结束模块定义。
