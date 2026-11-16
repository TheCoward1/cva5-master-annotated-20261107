// ============================================================================
// 文件：core/mmu/itlb.sv
// 类型：module
// 名称：itlb
// 作用：实现指令地址 TLB、命中和重填。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017 Eric Matthews, Chris Keilbart, Lesley Shannon
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
 *             Chris Keilbart <ckeilbar@sfu.ca>
 */

module itlb // 定义 itlb 模块。

    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    #(
        parameter WAYS = 2, // 声明可配置参数。
        parameter DEPTH = 32 // 声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        input logic translation_on, // 声明输入端口。
        input tlb_packet_t sfence, // 声明输入端口。
        input logic abort_request, // 声明输入端口。
        input logic [ASIDLEN-1:0] asid, // 声明输入端口。
        mmu_interface.tlb mmu,
        tlb_interface.tlb tlb
    );
    //////////////////////////////////////////
    localparam TAG_W = 20 - $clog2(DEPTH); // 声明局部常量。
    localparam TAG_W_S = 10 - $clog2(DEPTH); // 声明局部常量。
    localparam WAY_W = WAYS == 1 ? 1 : $clog2(WAYS); // 声明局部常量。

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic valid; // 声明信号、变量或生成变量。
        logic [ASIDLEN-1:0] asid; // 声明信号、变量或生成变量。
        logic [TAG_W-1:0] tag; // 声明信号、变量或生成变量。
        //Signals from the PTE
        logic [9:0] ppn1; // 声明信号、变量或生成变量。
        logic [9:0] ppn0; // 声明信号、变量或生成变量。
        logic globe; // 声明信号、变量或生成变量。
        logic user; // 声明信号、变量或生成变量。
    } tlb_entry_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic valid; // 声明信号、变量或生成变量。
        logic [ASIDLEN-1:0] asid; // 声明信号、变量或生成变量。
        logic [TAG_W_S-1:0] tag; // 声明信号、变量或生成变量。
        //Signals from the PTE
        logic [9:0] ppn1; // 声明信号、变量或生成变量。
        logic globe; // 声明信号、变量或生成变量。
        logic user; // 声明信号、变量或生成变量。
    } tlb_entry_s_t;

    ////////////////////////////////////////////////////
    //Implementation
    //Regular and super pages stored separately
    //Regular pages are set associative and super pages are direct mapped

    //Random replacement
    logic[WAYS-1:0] replacement_way; // 声明信号、变量或生成变量。
    cycler #(.C_WIDTH(WAYS)) replacement_policy (
        .en(1'b1),
        .one_hot(replacement_way),
    .*);
    
    //LUTRAM storage
    logic [$clog2(DEPTH)-1:0] tlb_addr; // 声明信号、变量或生成变量。
    logic [$clog2(DEPTH)-1:0] tlb_addr_s; // 声明信号、变量或生成变量。
    tlb_entry_t [WAYS-1:0] rdata;
    tlb_entry_s_t rdata_s;
    logic [WAYS-1:0] write; // 声明信号、变量或生成变量。
    logic write_s; // 声明信号、变量或生成变量。
    tlb_entry_t wdata;
    tlb_entry_s_t wdata_s;

    generate for (genvar i = 0; i < WAYS; i++) begin : gen_lut_rams // 开始生成块，在编译期展开硬件结构。
        lutram_1w_1r #(.DATA_TYPE(tlb_entry_t), .DEPTH(DEPTH)) data_table (
            .waddr(tlb_addr),
            .raddr(tlb_addr),
            .ram_write(write[i]),
            .new_ram_data(wdata),
            .ram_data_out(rdata[i]),
        .*);
    end endgenerate // 结束语句块。
    lutram_1w_1r #(.DATA_TYPE(tlb_entry_s_t), .DEPTH(DEPTH)) data_table_s (
        .waddr(tlb_addr_s),
        .raddr(tlb_addr_s),
        .ram_write(write_s),
        .new_ram_data(wdata_s),
        .ram_data_out(rdata_s),
    .*);


    //Hit detection
    logic [TAG_W-1:0] cmp_tag; // 声明信号、变量或生成变量。
    logic [TAG_W_S-1:0] cmp_tag_s; // 声明信号、变量或生成变量。
    logic [ASIDLEN-1:0] cmp_asid; // 声明信号、变量或生成变量。
    logic [WAYS-1:0] tag_hit; // 声明信号、变量或生成变量。
    logic tag_hit_s; // 声明信号、变量或生成变量。
    logic [WAYS-1:0] asid_hit; // 声明信号、变量或生成变量。
    logic asid_hit_s; // 声明信号、变量或生成变量。
    logic [WAYS-1:0] perms_valid; // 声明信号、变量或生成变量。
    logic perms_valid_s; // 声明信号、变量或生成变量。
    logic [WAYS-1:0] hit_ohot; // 声明信号、变量或生成变量。
    logic hit_ohot_s; // 声明信号、变量或生成变量。
    logic [WAY_W-1:0] hit_way; // 声明信号、变量或生成变量。
    logic hit; // 声明信号、变量或生成变量。

    assign cmp_tag = sfence.valid ? sfence.addr[31-:TAG_W] : tlb.virtual_address[31-:TAG_W]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign cmp_tag_s = sfence.valid ? sfence.addr[31-:TAG_W_S] : tlb.virtual_address[31-:TAG_W_S]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign cmp_asid = sfence.valid ? sfence.asid : asid; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < WAYS; i++) begin // 执行循环或遍历。
            tag_hit[i] = rdata[i].tag == cmp_tag;
            asid_hit[i] = rdata[i].asid == cmp_asid;
            hit_ohot[i] = rdata[i].valid & tag_hit[i] & (asid_hit[i] | rdata[i].globe);
        end // 结束语句块。
        tag_hit_s = rdata_s.tag == cmp_tag_s;
        asid_hit_s = rdata_s.asid == cmp_asid;
        hit_ohot_s = rdata_s.valid & tag_hit_s & (asid_hit_s | rdata_s.globe);
    end // 结束语句块。
    assign hit = |hit_ohot | hit_ohot_s; // 执行连续赋值，把组合逻辑连接到目标信号。

    priority_encoder #(.WIDTH(WAYS)) hit_cast (
        .priority_vector(hit_ohot),
        .encoded_result(hit_way)
    );

    generate for (genvar i = 0; i < WAYS; i++) begin : gen_perms_check // 开始生成块，在编译期展开硬件结构。
        perms_check checks (
            .pte_perms('{
                x : 1'b1,
                a : 1'b1,
                u : rdata[i].user,
                default: 'x // 执行默认分支。
            }),
            .rnw(tlb.rnw),
            .execute(1'b1),
            .mxr(mmu.mxr),
            .sum(mmu.sum),
            .privilege(mmu.privilege),
            .valid(perms_valid[i])
        );
    end endgenerate // 结束语句块。
    perms_check checks_s (
        .pte_perms('{
            x : 1'b1,
            a : 1'b1,
            u : rdata_s.user,
            default: 'x // 执行默认分支。
        }),
        .rnw(tlb.rnw),
        .execute(1'b1),
        .mxr(mmu.mxr),
        .sum(mmu.sum),
        .privilege(mmu.privilege),
        .valid(perms_valid_s)
    );


    //SFENCE
    logic [$clog2(DEPTH)-1:0] flush_addr; // 声明信号、变量或生成变量。
    lfsr #(.WIDTH($clog2(DEPTH)), .NEEDS_RESET(0)) lfsr_counter (
        .en(1'b1),
        .value(flush_addr),
    .*);

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (sfence.valid) begin // 执行条件判断，满足条件时进入对应分支。
            tlb_addr = sfence.addr_only ? sfence.addr[12 +: $clog2(DEPTH)] : flush_addr;
            tlb_addr_s = sfence.addr_only ? sfence.addr[22 +: $clog2(DEPTH)] : flush_addr;
        end // 结束语句块。
        else begin // 执行否则分支。
            tlb_addr = tlb.virtual_address[12 +: $clog2(DEPTH)];
            tlb_addr_s = tlb.virtual_address[22 +: $clog2(DEPTH)];
        end // 结束语句块。
    end // 结束语句块。

    assign wdata = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        valid : ~sfence.valid,
        asid : asid,
        tag : tlb.virtual_address[31-:TAG_W],
        ppn1 : mmu.upper_physical_address[19:10],
        ppn0 : mmu.upper_physical_address[9:0],
        globe : mmu.perms.g,
        user : mmu.perms.u
    };
    assign wdata_s = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        valid : ~sfence.valid,
        asid : asid,
        tag : tlb.virtual_address[31-:TAG_W_S],
        ppn1 : mmu.upper_physical_address[19:10],
        globe : mmu.perms.g,
        user : mmu.perms.u
    };

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < WAYS; i++) begin // 执行循环或遍历。
            case ({sfence.valid, sfence.addr_only, sfence.asid_only}) // 开始多分支选择，根据表达式选择对应分支。
                3'b100: begin //Clear everything
                    write[i] = 1'b1;
                    write_s = 1'b1;
                end // 结束语句块。
                3'b101: begin //Clear non global for specified address space
                    write[i] = ~rdata[i].globe & asid_hit[i];
                    write_s = ~rdata_s.globe & asid_hit_s;
                end // 结束语句块。
                3'b110: begin //Clear matching addresses
                    write[i] = tag_hit[i];
                    write_s = tag_hit_s;
                end // 结束语句块。
                3'b111: begin //Clear if both
                    write[i] = (~rdata[i].globe & asid_hit[i]) & tag_hit[i];
                    write_s = (~rdata_s.globe & asid_hit_s) & tag_hit_s;
                end // 结束语句块。
                default: begin // 执行默认分支。
                    write[i] = mmu.write_entry & ~mmu.superpage & replacement_way[i];
                    write_s = mmu.write_entry & mmu.superpage;
                end // 结束语句块。
            endcase // 结束多分支选择。
        end // 结束语句块。
    end // 结束语句块。

    //Permission fail
    logic perm_fail; // 声明信号、变量或生成变量。
    assign perm_fail = |(hit_ohot & ~perms_valid) | (hit_ohot_s & ~perms_valid_s); // 执行连续赋值，把组合逻辑连接到目标信号。

    //MMU interface
    logic request_in_progress; // 声明信号、变量或生成变量。
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            request_in_progress <= 0;
        else if (mmu.write_entry | mmu.is_fault | abort_request) // 执行否则如果分支的条件判断。
            request_in_progress <= 0;
        else if (mmu.request) // 执行否则如果分支的条件判断。
            request_in_progress <= 1;
    end // 结束语句块。

    assign mmu.request = translation_on & tlb.new_request & ~hit & ~perm_fail; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mmu.execute = 1; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mmu.rnw = tlb.rnw; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mmu.virtual_address = tlb.virtual_address; // 执行连续赋值，把组合逻辑连接到目标信号。

    //TLB interface
    logic mmu_request_complete; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mmu_request_complete <= 0;
        else // 执行否则分支。
            mmu_request_complete <= mmu.write_entry & ~abort_request;
    end // 结束语句块。
    assign tlb.done = translation_on ? (hit & ~perm_fail & (tlb.new_request | mmu_request_complete)) : tlb.new_request; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign tlb.ready = ~request_in_progress & ~mmu_request_complete; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign tlb.is_fault = mmu.is_fault | (tlb.new_request & translation_on & perm_fail); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        tlb.physical_address[11:0] = tlb.virtual_address[11:0];
        if (~translation_on) // 执行条件判断，满足条件时进入对应分支。
            tlb.physical_address[31:12] = tlb.virtual_address[31:12];
        else if (hit_ohot_s) begin // 执行否则如果分支的条件判断。
            tlb.physical_address[21:12] = tlb.virtual_address[21:12];
            tlb.physical_address[31:22] = rdata_s.ppn1;
        end // 结束语句块。
        else begin // 执行否则分支。
            tlb.physical_address[21:12] = rdata[hit_way].ppn0;
            tlb.physical_address[31:22] = rdata[hit_way].ppn1;
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions

endmodule // 结束模块定义。
