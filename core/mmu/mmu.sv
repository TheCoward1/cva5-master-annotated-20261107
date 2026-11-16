// ============================================================================
// 文件：core/mmu/mmu.sv
// 类型：module
// 名称：mmu
// 作用：实现地址翻译、页表遍历、权限检查和异常处理。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017 Eric Matthews,  Lesley Shannon
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

module mmu // 定义 mmu 模块。

    import csr_types::*; // 导入包或命名空间：csr_types::*;。

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        mmu_interface.mmu mmu,
        input logic abort_request, // 声明输入端口。
        mem_interface.ro_master mem
    );

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic [11:0] ppn1; // 声明信号、变量或生成变量。
        logic [9:0] ppn0; // 声明信号、变量或生成变量。
        logic [1:0] reserved; // 声明信号、变量或生成变量。
        pte_perms_t perms;
    } pte_t;

// 定义类型别名或枚举/结构类型。
    typedef enum  {
        IDLE = 0,
        SEND_REQUEST_1 = 1,
        WAIT_REQUEST_1 = 2,
        SEND_REQUEST_2 = 3,
        WAIT_REQUEST_2 = 4,
        COMPLETE_SUCCESS = 5,
        COMPLETE_FAULT = 6
    } mmu_state_t;
    logic [6:0] state; // 声明信号、变量或生成变量。
    logic [6:0] next_state; // 声明信号、变量或生成变量。

    pte_t pte;
    logic perms_valid; // 声明信号、变量或生成变量。

    localparam MAX_ABORTED_REQUESTS = 4; // 声明局部常量。
    logic abort_queue_full; // 声明信号、变量或生成变量。
    logic discard_data; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation

    ////////////////////////////////////////////////////
    //L1 arbiter Interfrace
    assign mem.rlen = '0; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign mem.request = (state[SEND_REQUEST_1] | state[SEND_REQUEST_2]) & ~abort_request; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Page Table addresses
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (state[IDLE] | (mem.rvalid & ~discard_data)) begin // 执行条件判断，满足条件时进入对应分支。
            if (state[IDLE]) // 执行条件判断，满足条件时进入对应分支。
                mem.addr <= {mmu.satp_ppn[19:0], mmu.virtual_address[31:22]};
            else // 执行否则分支。
                mem.addr <= {pte.ppn1[9:0], pte.ppn0, mmu.virtual_address[21:12]};
        end // 结束语句块。
    end // 结束语句块。

    assign pte = mem.rdata; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Supports unlimited tracking of aborted requests
    //Assumption: memory requests are returned in-order
    localparam COUNT_W = $clog2(MAX_ABORTED_REQUESTS); // 声明局部常量。
    logic [COUNT_W:0] abort_tracking; // 声明信号、变量或生成变量。
    logic delayed_abort; // 声明信号、变量或生成变量。
    logic delayed_abort_complete; // 声明信号、变量或生成变量。

    assign delayed_abort = abort_request & (state[WAIT_REQUEST_1] | state[WAIT_REQUEST_2]); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign delayed_abort_complete = (discard_data | abort_request) & mem.rvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            abort_tracking <= 0;
        else // 执行否则分支。
            abort_tracking <= abort_tracking - COUNT_W'(delayed_abort) + COUNT_W'(delayed_abort_complete);
    end // 结束语句块。

    assign discard_data = abort_tracking[COUNT_W]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign abort_queue_full = abort_tracking[COUNT_W] & ~|abort_tracking[COUNT_W-1:0]; // 执行连续赋值，把组合逻辑连接到目标信号。

    perms_check perm (
        .pte_perms(pte.perms),
        .rnw(mmu.rnw),
        .execute(mmu.execute),
        .mxr(mmu.mxr),
        .sum(mmu.sum),
        .privilege(mmu.privilege),
        .valid(perms_valid)
    );

    ////////////////////////////////////////////////////
    //State Machine
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        next_state = state;
        case (1'b1) // 开始多分支选择，根据表达式选择对应分支。
            state[IDLE] :
                if (mmu.request & ~abort_queue_full) // 执行条件判断，满足条件时进入对应分支。
                    next_state = 2**SEND_REQUEST_1;
            state[SEND_REQUEST_1] :
                if (mem.ack) // 执行条件判断，满足条件时进入对应分支。
                    next_state = 2**WAIT_REQUEST_1;
            state[WAIT_REQUEST_1] :
                if (mem.rvalid & ~discard_data) begin // 执行条件判断，满足条件时进入对应分支。
                    if (~pte.perms.v | (~pte.perms.r & pte.perms.w)) //page not valid OR invalid xwr pattern；执行条件判断，满足条件时进入对应分支。
                        next_state = 2**COMPLETE_FAULT;
                    else if (pte.perms.v & (pte.perms.r | pte.perms.x)) begin//superpage (all remaining xwr patterns other than all zeros)；执行否则如果分支的条件判断。
                        if (perms_valid & ~|pte.ppn0) //check for misaligned superpage；执行条件判断，满足条件时进入对应分支。
                            next_state = 2**COMPLETE_SUCCESS;
                        else // 执行否则分支。
                            next_state = 2**COMPLETE_FAULT;
                    end else //(pte.perms.v & ~pte.perms.x & ~pte.perms.w & ~pte.perms.r) pointer to next level in page table；结束语句块。
                        next_state = 2**SEND_REQUEST_2;
                end // 结束语句块。
            state[SEND_REQUEST_2] :
                if (mem.ack) // 执行条件判断，满足条件时进入对应分支。
                    next_state = 2**WAIT_REQUEST_2;
            state[WAIT_REQUEST_2] :
                if (mem.rvalid & ~discard_data) begin // 执行条件判断，满足条件时进入对应分支。
                    if (~perms_valid | ~pte.perms.v | (~pte.perms.r & pte.perms.w)) //perm fail or invalid；执行条件判断，满足条件时进入对应分支。
                        next_state = 2**COMPLETE_FAULT;
                    else // 执行否则分支。
                        next_state = 2**COMPLETE_SUCCESS;
                end // 结束语句块。
            state[COMPLETE_SUCCESS], state[COMPLETE_FAULT]  :
                next_state = 2**IDLE;
        endcase // 结束多分支选择。
        //If request is aborted, return to IDLE
        if (abort_request) // 执行条件判断，满足条件时进入对应分支。
            next_state = 2**IDLE;
    end // 结束语句块。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            state <= 2**IDLE;
        else // 执行否则分支。
            state <= next_state;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //TLB return path
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (mem.rvalid) begin // 执行条件判断，满足条件时进入对应分支。
            mmu.superpage <= state[WAIT_REQUEST_1];
            mmu.perms.d <= pte.perms.d;
            mmu.perms.a <= pte.perms.a;
            mmu.perms.g <= pte.perms.g | (state[WAIT_REQUEST_2] & mmu.perms.g);
            mmu.perms.u <= pte.perms.u;
            mmu.perms.x <= pte.perms.x;
            mmu.perms.w <= pte.perms.w;
            mmu.perms.r <= pte.perms.r;
            mmu.perms.v <= pte.perms.v;
            mmu.upper_physical_address[19:10] <= pte.ppn1[9:0];
            mmu.upper_physical_address[9:0] <= state[WAIT_REQUEST_2] ? pte.ppn0 : mmu.virtual_address[21:12];
        end // 结束语句块。
    end // 结束语句块。
    assign mmu.write_entry = state[COMPLETE_SUCCESS]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mmu.is_fault = state[COMPLETE_FAULT]; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions
    mmu_spurious_l1_response:
        assert property (@(posedge clk) disable iff (rst) (mem.rvalid) |-> (state[WAIT_REQUEST_1] | state[WAIT_REQUEST_2])) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("mmu recieved response without a request"); // 执行否则分支。

    //TLB request remains high until it recieves a response from the MMU unless
    //the transaction is aborted.  As such, if TLB request is low and we are not in the
    //IDLE state, then our current processor state has been corrupted
    mmu_tlb_state_mismatch:
        assert property (@(posedge clk) disable iff (rst) (mmu.request) |-> (state[IDLE])) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("MMU and TLB state mismatch"); // 执行否则分支。

endmodule // 结束模块定义。
