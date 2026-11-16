// ============================================================================
// 文件：core/mmu/dtlb.sv
// 类型：module
// 名称：dtlb
// 作用：实现数据地址 TLB、命中和重填。
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

module dtlb // 定义 dtlb 模块。

    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。

    #(
        parameter WAYS = 2, // 声明可配置参数。
        parameter DEPTH = 32 // 声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        input logic translation_on, // 声明输入端口。
        input tlb_packet_t sfence, // 声明输入端口。
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
        logic dirty; // 声明信号、变量或生成变量。
        logic globe; // 声明信号、变量或生成变量。
        logic user; // 声明信号、变量或生成变量。
        logic execute; // 声明信号、变量或生成变量。
        logic write; // 声明信号、变量或生成变量。
        logic read; // 声明信号、变量或生成变量。
    } tlb_entry_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic valid; // 声明信号、变量或生成变量。
        logic [ASIDLEN-1:0] asid; // 声明信号、变量或生成变量。
        logic [TAG_W_S-1:0] tag; // 声明信号、变量或生成变量。
        //Signals from the PTE
        logic [9:0] ppn1; // 声明信号、变量或生成变量。
        logic dirty; // 声明信号、变量或生成变量。
        logic globe; // 声明信号、变量或生成变量。
        logic user; // 声明信号、变量或生成变量。
        logic execute; // 声明信号、变量或生成变量。
        logic write; // 声明信号、变量或生成变量。
        logic read; // 声明信号、变量或生成变量。
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
    logic [$clog2(DEPTH)-1:0] tlb_raddr; // 声明信号、变量或生成变量。
    logic [$clog2(DEPTH)-1:0] tlb_raddr_s; // 声明信号、变量或生成变量。
    logic [$clog2(DEPTH)-1:0] tlb_waddr; // 声明信号、变量或生成变量。
    logic [$clog2(DEPTH)-1:0] tlb_waddr_s; // 声明信号、变量或生成变量。
    tlb_entry_t [WAYS-1:0] rdata;
    tlb_entry_s_t rdata_s;
    logic [WAYS-1:0] write; // 声明信号、变量或生成变量。
    logic write_s; // 声明信号、变量或生成变量。
    tlb_entry_t wdata;
    tlb_entry_s_t wdata_s;

    generate for (genvar i = 0; i < WAYS; i++) begin : gen_lut_rams // 开始生成块，在编译期展开硬件结构。
        lutram_1w_1r #(.DATA_TYPE(tlb_entry_t), .DEPTH(DEPTH)) data_table (
            .waddr(tlb_waddr),
            .raddr(tlb_raddr),
            .ram_write(write[i]),
            .new_ram_data(wdata),
            .ram_data_out(rdata[i]),
        .*);
    end endgenerate // 结束语句块。
    lutram_1w_1r #(.DATA_TYPE(tlb_entry_s_t), .DEPTH(DEPTH)) data_table_s (
        .waddr(tlb_waddr_s),
        .raddr(tlb_raddr_s),
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
    logic [WAYS-1:0] rdata_global; // 声明信号、变量或生成变量。
    logic rdata_global_s; // 声明信号、变量或生成变量。
    logic [WAYS-1:0][9:0] ppn0; // 声明信号、变量或生成变量。
    logic [WAYS-1:0][9:0] ppn1; // 声明信号、变量或生成变量。
    logic [9:0] ppn1_s; // 声明信号、变量或生成变量。
    logic [WAYS-1:0] perms_valid_comb; // 声明信号、变量或生成变量。
    logic perms_valid_comb_s; // 声明信号、变量或生成变量。
    logic [WAYS-1:0] perms_valid; // 声明信号、变量或生成变量。
    logic perms_valid_s; // 声明信号、变量或生成变量。
    logic [WAYS-1:0] hit_ohot; // 声明信号、变量或生成变量。
    logic hit_ohot_s; // 声明信号、变量或生成变量。
    logic [WAY_W-1:0] hit_way; // 声明信号、变量或生成变量。
    logic hit; // 声明信号、变量或生成变量。

    assign cmp_tag = sfence.valid ? sfence.addr[31-:TAG_W] : tlb.virtual_address[31-:TAG_W]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign cmp_tag_s = sfence.valid ? sfence.addr[31-:TAG_W_S] : tlb.virtual_address[31-:TAG_W_S]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign cmp_asid = sfence.valid ? sfence.asid : asid; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        for (int i = 0; i < WAYS; i++) begin // 执行循环或遍历。
            tag_hit[i] <= rdata[i].tag == cmp_tag;
            rdata_global[i] <= rdata[i].globe;
            ppn0[i] <= rdata[i].ppn0;
            ppn1[i] <= rdata[i].ppn1;
            asid_hit[i] <= rdata[i].asid == cmp_asid;
            perms_valid[i] <= perms_valid_comb[i];
            hit_ohot[i] <= rdata[i].valid & (rdata[i].tag == cmp_tag) & (rdata[i].asid == cmp_asid | rdata[i].globe);
        end // 结束语句块。
        tag_hit_s <= rdata_s.tag == cmp_tag_s;
        rdata_global_s <= rdata_s.globe;
        ppn1_s <= rdata_s.ppn1;
        asid_hit_s <= rdata_s.asid == cmp_asid;
        perms_valid_s <= perms_valid_comb_s;
        hit_ohot_s <= rdata_s.valid & (rdata_s.tag == cmp_tag_s) & (rdata_s.asid == cmp_asid | rdata_s.globe);
    end // 结束语句块。

    assign hit = |hit_ohot | hit_ohot_s; // 执行连续赋值，把组合逻辑连接到目标信号。

    priority_encoder #(.WIDTH(WAYS)) hit_cast (
        .priority_vector(hit_ohot),
        .encoded_result(hit_way)
    );

    generate for (genvar i = 0; i < WAYS; i++) begin : gen_perms_check // 开始生成块，在编译期展开硬件结构。
        perms_check checks (
            .pte_perms('{
                d : rdata[i].dirty,
                a : 1'b1,
                u : rdata[i].user,
                x : rdata[i].execute,
                w : rdata[i].write,
                r : rdata[i].read,
                default: 'x // 执行默认分支。
            }),
            .rnw(tlb.rnw),
            .execute(1'b0),
            .mxr(mmu.mxr),
            .sum(mmu.sum),
            .privilege(mmu.privilege),
            .valid(perms_valid_comb[i])
        );
    end endgenerate // 结束语句块。
    perms_check checks (
        .pte_perms('{
            d : rdata_s.dirty,
            a : 1'b1,
            u : rdata_s.user,
            x : rdata_s.execute,
            w : rdata_s.write,
            r : rdata_s.read,
            default: 'x // 执行默认分支。
        }),
        .rnw(tlb.rnw),
        .execute(1'b0),
        .mxr(mmu.mxr),
        .sum(mmu.sum),
        .privilege(mmu.privilege),
        .valid(perms_valid_comb_s)
    );


    //SFENCE
    logic sfence_valid_r; // 声明信号、变量或生成变量。
    logic [$clog2(DEPTH)-1:0] flush_addr; // 声明信号、变量或生成变量。
    lfsr #(.WIDTH($clog2(DEPTH)), .NEEDS_RESET(0)) lfsr_counter (
        .en(1'b1),
        .value(flush_addr),
    .*);

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (tlb.new_request | sfence.valid) begin // 执行条件判断，满足条件时进入对应分支。
            tlb_waddr <= tlb_raddr;
            tlb_waddr_s <= tlb_raddr_s;
        end // 结束语句块。
        sfence_valid_r <= sfence.valid; //Other SFENCE signals remain registered and do not need to be saved
    end // 结束语句块。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if (sfence.valid) begin // 执行条件判断，满足条件时进入对应分支。
            tlb_raddr = sfence.addr_only ? sfence.addr[12 +: $clog2(DEPTH)] : flush_addr;
            tlb_raddr_s = sfence.addr_only ? sfence.addr[22 +: $clog2(DEPTH)] : flush_addr;
        end // 结束语句块。
        else begin // 执行否则分支。
            tlb_raddr = tlb.virtual_address[12 +: $clog2(DEPTH)];
            tlb_raddr_s = tlb.virtual_address[22 +: $clog2(DEPTH)];
        end // 结束语句块。
    end // 结束语句块。

    assign wdata = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        valid : ~sfence_valid_r,
        asid : asid,
        tag : mmu.virtual_address[31-:TAG_W],
        ppn1 : mmu.upper_physical_address[19:10],
        ppn0 : mmu.upper_physical_address[9:0],
        dirty : mmu.perms.d,
        globe : mmu.perms.g,
        user : mmu.perms.u,
        execute : mmu.perms.x,
        write : mmu.perms.w,
        read : mmu.perms.r
    };
    assign wdata_s = '{ // 执行连续赋值，把组合逻辑连接到目标信号。
        valid : ~sfence_valid_r,
        asid : asid,
        tag : mmu.virtual_address[31-:TAG_W_S],
        ppn1 : mmu.upper_physical_address[19:10],
        dirty : mmu.perms.d,
        globe : mmu.perms.g,
        user : mmu.perms.u,
        execute : mmu.perms.x,
        write : mmu.perms.w,
        read : mmu.perms.r
    };

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < WAYS; i++) begin // 执行循环或遍历。
            case ({sfence_valid_r, sfence.addr_only, sfence.asid_only}) // 开始多分支选择，根据表达式选择对应分支。
                3'b100: begin //Clear everything
                    write[i] = 1'b1;
                    write_s = 1'b1;
                end // 结束语句块。
                3'b101: begin //Clear non global for specified address space
                    write[i] = ~rdata_global[i] & asid_hit[i];
                    write_s = ~rdata_global_s & asid_hit_s;
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
    logic new_request_r; // 声明信号、变量或生成变量。
    assign mmu.request = translation_on & new_request_r & ~hit & ~perm_fail; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mmu.execute = 0; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        new_request_r <= tlb.new_request;
        if (tlb.new_request) begin // 执行条件判断，满足条件时进入对应分支。
            mmu.virtual_address <= tlb.virtual_address;
            mmu.rnw <= tlb.rnw;
        end // 结束语句块。
    end // 结束语句块。

    //TLB interface
    assign tlb.done = (new_request_r & ((hit & ~perm_fail) | ~translation_on)) | mmu.write_entry; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign tlb.ready = 1; //Not always ready, but requests will not be sent if it isn't done；执行连续赋值，把组合逻辑连接到目标信号。
    assign tlb.is_fault = mmu.is_fault | (new_request_r & translation_on & perm_fail); // 执行连续赋值，把组合逻辑连接到目标信号。


    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        tlb.physical_address[11:0] = mmu.virtual_address[11:0];
        if (~translation_on) // 执行条件判断，满足条件时进入对应分支。
            tlb.physical_address[31:12] = mmu.virtual_address[31:12];
        else if (new_request_r) begin // 执行否则如果分支的条件判断。
            tlb.physical_address[31:22] = hit_ohot_s ? ppn1_s : ppn1[hit_way];
            tlb.physical_address[21:12] = hit_ohot_s ? mmu.virtual_address[21:12] : ppn0[hit_way];
        end else begin // 结束语句块。
            tlb.physical_address[31:22] = mmu.upper_physical_address[19:10];
            tlb.physical_address[21:12] = mmu.superpage ? mmu.virtual_address[21:12] : mmu.upper_physical_address[9:0];
        end // 结束语句块。
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions
    request_on_miss:
        assert property (@(posedge clk) disable iff (rst) (mmu.request) |-> ~tlb.new_request) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("Request during miss in TLB!"); // 执行否则分支。

endmodule // 结束模块定义。
