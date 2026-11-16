// ============================================================================
// 文件：apu/plic/plic.sv
// 类型：module
// 名称：plic
// 作用：实现平台级外部中断控制器，负责中断优先级、挂起和 claim/complete。
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

module plic // 定义 plic 模块。

    #(
        parameter int unsigned NUM_SOURCES = 1, // 声明可配置参数。
        parameter int unsigned NUM_TARGETS = 1, // 声明可配置参数。
        parameter int unsigned PRIORITY_W = 4, // 声明可配置参数。
        parameter int unsigned REG_STAGE = 1 // 声明可配置参数。
    ) (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        input logic[NUM_SOURCES:1] irq_srcs, // 声明输入端口。
        input logic[NUM_SOURCES-1:0] edge_sensitive, //Both rising and falling edges, else level sensitive and active high；声明输入端口。

        //Memory mapped port
        input logic read_reg, // 声明输入端口。
        input logic write_reg, // 声明输入端口。
        input logic[25:2] addr, // 声明输入端口。
        input logic[31:0] wdata, // 声明输入端口。
        output logic[31:0] rdata, // 声明输出端口。

        output logic[NUM_TARGETS-1:0] eip // 声明输出端口。
    );

    ////////////////////////////////////////////////////
    //RISC-V Platform-Level Interrupt Controller (PLIC)
    //Supports up to 32 interrupt sources; more would require a different design for frequency reasons anyways
    //REG_STAGE determines the location of the registers in the comparison tree
    //It might need to manually tuned depending on FPGA architecture, NUM_SOURCES, NUM_TARGETS, and PRIORITY_W
    //Reads therefore have one cycle of latency, but writes do not
    
    localparam PADDED_SOURCES = NUM_SOURCES+1; //Source 0 does not exist；声明局部常量。
    localparam IRQ_ID_W = $clog2(PADDED_SOURCES); //Will always be at least 1；声明局部常量。
    localparam TARGET_ID_W = NUM_TARGETS == 1 ? 1 : $clog2(NUM_TARGETS); // 声明局部常量。

// 定义类型别名或枚举/结构类型。
    typedef logic[PRIORITY_W-1:0] priority_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[PADDED_SOURCES-1:0] irq_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[IRQ_ID_W-1:0] irq_id_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[TARGET_ID_W-1:0] target_id_t;

    irq_t interrupt_pending;
    irq_t[NUM_TARGETS-1:0] interrupt_enable;
    priority_t[NUM_TARGETS-1:0] target_threshold;
    priority_t[PADDED_SOURCES-1:0] interrupt_priority;
    logic[PADDED_SOURCES-1:0] claim_ohot; // 声明信号、变量或生成变量。
    logic[PADDED_SOURCES-1:0] complete_ohot; // 声明信号、变量或生成变量。
    irq_id_t irq_claim_id;
    logic is_complete_claim; // 声明信号、变量或生成变量。
    logic is_priority; // 声明信号、变量或生成变量。
    logic is_target_threshold; // 声明信号、变量或生成变量。
    logic is_interrupt_enable; // 声明信号、变量或生成变量。


    ////////////////////////////////////////////////////
    //Implementation

    //Gateway registers external interrupts
    logic claim; // 声明信号、变量或生成变量。
    logic complete; // 声明信号、变量或生成变量。
    assign claim = read_reg & is_complete_claim; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign claim_ohot = {{NUM_SOURCES{1'b0}}, claim} << irq_claim_id; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign complete = write_reg & is_complete_claim; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign complete_ohot = {{NUM_SOURCES{1'b0}}, complete} << wdata; // 执行连续赋值，把组合逻辑连接到目标信号。

    plic_gateway #(.NUM_IRQS(PADDED_SOURCES)) gateway (
        .irq({irq_srcs, 1'b0}),
        .edge_sensitive({edge_sensitive, 1'b0}),
        .claim(claim_ohot),
        .complete(complete_ohot),
        .ip(interrupt_pending),
    .*);

    //Interrupts must meet the minimum priority for a target and can be individually suppressed
    irq_t[NUM_TARGETS-1:0] filtered_interrupts;
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < NUM_TARGETS; i++) begin // 执行循环或遍历。
            for (int j = 0; j < PADDED_SOURCES; j++) // 执行循环或遍历。
                filtered_interrupts[i][j] = interrupt_pending[j] & interrupt_enable[i][j] & interrupt_priority[j] > target_threshold[i];
            eip[i] = |filtered_interrupts[i];
        end // 结束语句块。
    end // 结束语句块。

    //ID Priority
    irq_t possible_irqs;
    target_id_t addr_rid;
    assign addr_rid = addr[12+:TARGET_ID_W]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign possible_irqs = NUM_TARGETS > 1 ? filtered_interrupts[addr_rid] : filtered_interrupts[0]; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    plic_cmptree #(
        .NUM_IRQS(PADDED_SOURCES),
        .PRIORITY_W(PRIORITY_W),
        .REG_STAGE_W(2**REG_STAGE)
    ) tree (
        .irq_valid(possible_irqs),
        .irq_priority(interrupt_priority),
        .highest_id(irq_claim_id),
        .highest_priority(),
        .highest_valid(),
    .*);

    ////////////////////////////////////////////////////
    //Read and address decoding
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        rdata = '0;
        is_priority = 0;
        is_target_threshold = 0;
        is_interrupt_enable = 0;
        is_complete_claim = 0;

        //Interrupt priority
        for (int i = 0; i < PADDED_SOURCES; i++) begin // 执行循环或遍历。
            if (addr == 24'(i)) begin // 执行条件判断，满足条件时进入对应分支。
                is_priority = 1;
                rdata[PRIORITY_W-1:0] = interrupt_priority[i];
            end // 结束语句块。
        end // 结束语句块。

        //Interrupt pending
        if (addr == 24'h400) // 执行条件判断，满足条件时进入对应分支。
            rdata[PADDED_SOURCES-1:0] = interrupt_pending;

        //Enable bits
        for (int i = 0; i < NUM_TARGETS; i++) begin // 执行循环或遍历。
            if (addr == 24'h800+24'h20*24'(i)) begin // 执行条件判断，满足条件时进入对应分支。
                is_interrupt_enable = 1;
                rdata[PADDED_SOURCES-1:0] = interrupt_enable[i];
            end // 结束语句块。
        end // 结束语句块。

        //Target threshold
        for (int i = 0; i < NUM_TARGETS; i++) begin // 执行循环或遍历。
            if (addr == 24'h80000+24'h400*24'(i)) begin // 执行条件判断，满足条件时进入对应分支。
                is_target_threshold = 1;
                rdata[PRIORITY_W-1:0] = target_threshold[i];
            end // 结束语句块。
        end // 结束语句块。

        //Complete/Claim
        for (int i = 0; i < NUM_TARGETS; i++) begin // 执行循环或遍历。
            if (addr == 24'h80001+24'h400*24'(i)) begin // 执行条件判断，满足条件时进入对应分支。
                is_complete_claim = 1;
                rdata[IRQ_ID_W-1:0] = irq_claim_id;
            end // 结束语句块。
        end // 结束语句块。
    end // 结束语句块。

    //Write logic
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            interrupt_priority <= '0;
        else begin // 执行否则分支。
            if (write_reg & is_priority) // 执行条件判断，满足条件时进入对应分支。
                interrupt_priority[addr[2+:IRQ_ID_W]] <= wdata[PRIORITY_W-1:0];
            
            interrupt_priority[0] <= '0; //IRQ 0 hard coded to 0
        end // 结束语句块。
    end // 结束语句块。

    target_id_t threshold_index;
    assign threshold_index = NUM_TARGETS > 1 ? addr[12+:TARGET_ID_W] : 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            target_threshold <= '0;
        else begin // 执行否则分支。
            if (write_reg & is_target_threshold) // 执行条件判断，满足条件时进入对应分支。
                target_threshold[threshold_index] <= wdata[PRIORITY_W-1:0];
        end // 结束语句块。
    end // 结束语句块。

    target_id_t enable_index;
    assign enable_index = NUM_TARGETS > 1 ? addr[7+:TARGET_ID_W] : 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            interrupt_enable <= '0;
        else begin // 执行否则分支。
            if (write_reg & is_interrupt_enable) // 执行条件判断，满足条件时进入对应分支。
                interrupt_enable[enable_index] <= {wdata[PADDED_SOURCES-1:1], 1'b0}; //IRQ 0 hard coded to 0
        end // 结束语句块。
    end // 结束语句块。

endmodule // 结束模块定义。
