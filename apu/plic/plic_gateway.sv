// ============================================================================
// 文件：apu/plic/plic_gateway.sv
// 类型：module
// 名称：plic_gateway
// 作用：实现 PLIC 每个中断源的网关、挂起和使能逻辑。
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

module plic_gateway // 定义 plic_gateway 模块。

    #(
        parameter int unsigned NUM_IRQS = 1 // 声明可配置参数。
    ) (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        input logic[NUM_IRQS-1:0] irq, // 声明输入端口。
        input logic[NUM_IRQS-1:0] edge_sensitive, //Both rising and falling edges, else level sensitive and active high；声明输入端口。
        input logic[NUM_IRQS-1:0] claim, // 声明输入端口。
        input logic[NUM_IRQS-1:0] complete, // 声明输入端口。
        output logic[NUM_IRQS-1:0] ip // 声明输出端口。
    );

    ////////////////////////////////////////////////////
    //PLIC Gateway
    //Registers interrupts, for them to be later claimed and completed

    //Raising
    logic[NUM_IRQS-1:0] irq_r; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) irq_r <= irq; // 开始时序逻辑块，在时钟边沿更新寄存器。

    logic[NUM_IRQS-1:0] raise; // 声明信号、变量或生成变量。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < NUM_IRQS; i++) // 执行循环或遍历。
            raise[i] = edge_sensitive[i] ? irq[i] ^ irq_r[i] : irq[i];
    end // 结束语句块。

    //Registering
    logic[NUM_IRQS-1:0] in_progress; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            ip <= '0;
            in_progress <= '0;
        end // 结束语句块。
        else begin // 执行否则分支。
            ip <= (ip | raise) & ~in_progress & ~claim;
            in_progress <= (in_progress | claim) & ~complete;
        end // 结束语句块。
    end // 结束语句块。

endmodule // 结束模块定义。
