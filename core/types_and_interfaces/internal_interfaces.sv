// ============================================================================
// 文件：core/types_and_interfaces/internal_interfaces.sv
// 类型：interface
// 名称：branch_predictor_interface
// 作用：定义模块之间的 issue、writeback、FIFO、MMU、TLB 和异常接口。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017, 2018, 2019 Eric Matthews,  Lesley Shannon
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

interface branch_predictor_interface; // 定义 branch_predictor_interface 接口。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    //Fetch signals
    logic [31:0] if_pc; // 声明信号、变量或生成变量。
    id_t if_id;
    logic new_mem_request; // 声明信号、变量或生成变量。
    logic [31:0] next_pc; // 声明信号、变量或生成变量。

    id_t pc_id;
    logic pc_id_assigned; // 声明信号、变量或生成变量。
    
    //Branch Predictor 
    logic [31:0] branch_flush_pc; // 声明信号、变量或生成变量。
    logic [31:0] predicted_pc; // 声明信号、变量或生成变量。
    logic use_prediction; // 声明信号、变量或生成变量。
    logic is_return; // 声明信号、变量或生成变量。
    logic is_call; // 声明信号、变量或生成变量。
    logic is_branch; // 声明信号、变量或生成变量。

    modport branch_predictor (
        input if_pc, if_id, new_mem_request, next_pc, pc_id, pc_id_assigned, // 声明输入端口。
        output branch_flush_pc, predicted_pc, use_prediction, is_return, is_call, is_branch // 声明输出端口。
    );
    modport fetch (
        input branch_flush_pc, predicted_pc, use_prediction, is_return, is_call, is_branch, // 声明输入端口。
        output if_pc, if_id, new_mem_request, next_pc, pc_id, pc_id_assigned // 声明输出端口。
     );

endinterface // 结束接口定义。

interface unit_issue_interface; // 定义 unit_issue_interface 接口。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    logic possible_issue; // 声明信号、变量或生成变量。
    logic new_request; // 声明信号、变量或生成变量。
    id_t id;

    logic ready; // 声明信号、变量或生成变量。

    modport decode (input ready, output possible_issue, new_request, id);
    modport unit (output ready, input possible_issue, new_request, id);
endinterface // 结束接口定义。

interface unit_writeback_interface #(parameter DATA_WIDTH = 32); // 定义 unit_writeback_interface 接口。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    //Handshaking
    logic ack; // 声明信号、变量或生成变量。
    logic done; // 声明信号、变量或生成变量。

    id_t id;
    logic [DATA_WIDTH-1:0] rd; // 声明信号、变量或生成变量。

    modport unit (input ack, output done, id, rd);
    modport wb (output ack, input done, id, rd);
endinterface // 结束接口定义。

interface ras_interface; // 定义 ras_interface 接口。
    logic push; // 声明信号、变量或生成变量。
    logic pop; // 声明信号、变量或生成变量。
    logic branch_fetched; // 声明信号、变量或生成变量。
    logic branch_retired; // 声明信号、变量或生成变量。

    logic [31:0] new_addr; // 声明信号、变量或生成变量。
    logic [31:0] addr; // 声明信号、变量或生成变量。

    modport branch_predictor (output branch_retired);
    modport self (input push, pop, new_addr, branch_fetched, branch_retired, output addr);
    modport fetch (input addr, output pop, push, new_addr, branch_fetched);
endinterface // 结束接口定义。


interface exception_interface; // 定义 exception_interface 接口。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    logic valid; // 声明信号、变量或生成变量。
    logic possible; // 声明信号、变量或生成变量。
    
    exception_code_t code;
    logic [31:0] tval; // 声明信号、变量或生成变量。
    logic [31:0] pc; // 声明信号、变量或生成变量。
    logic discard; // 声明信号、变量或生成变量。
    
    modport unit (output valid, possible, code, tval, pc, discard);
    modport econtrol (input valid, possible, code, tval, pc, discard);
endinterface // 结束接口定义。

interface fifo_interface #(parameter type DATA_TYPE = logic); // 定义 fifo_interface 接口。
    logic push; // 声明信号、变量或生成变量。
    logic pop; // 声明信号、变量或生成变量。
    DATA_TYPE data_in;
    DATA_TYPE data_out;
    logic valid; // 声明信号、变量或生成变量。
    logic full; // 声明信号、变量或生成变量。
    logic potential_push; // 声明信号、变量或生成变量。
    modport enqueue (input full, output data_in, push, potential_push);
    modport dequeue (input valid, data_out, output pop);
    modport structure(input push, pop, data_in, potential_push, output data_out, valid, full);
endinterface // 结束接口定义。

interface mmu_interface; // 定义 mmu_interface 接口。
    import csr_types::*; // 导入包或命名空间：csr_types::*;。
    
    //From TLB
    logic request; // 声明信号、变量或生成变量。
    logic execute; // 声明信号、变量或生成变量。
    logic rnw; // 声明信号、变量或生成变量。
    logic [31:0] virtual_address; // 声明信号、变量或生成变量。

    //TLB response
    logic write_entry; // 声明信号、变量或生成变量。
    logic superpage; // 声明信号、变量或生成变量。
    pte_perms_t perms;
    logic [19:0] upper_physical_address; // 声明信号、变量或生成变量。
    logic is_fault; // 声明信号、变量或生成变量。

    //From CSR
    logic [21:0] satp_ppn; // 声明信号、变量或生成变量。
    logic mxr; //Make eXecutable Readable；声明信号、变量或生成变量。
    logic sum; //permit Supervisor User Memory access；声明信号、变量或生成变量。
    privilege_t privilege;

    modport mmu (input virtual_address, request, execute, rnw, satp_ppn, mxr, sum, privilege, output write_entry, superpage, perms, upper_physical_address, is_fault);
    modport tlb (input write_entry, superpage, perms, upper_physical_address, is_fault, mxr, sum, privilege, output request, virtual_address, execute, rnw);
    modport csr (output satp_ppn, mxr, sum, privilege);

endinterface // 结束接口定义。

interface tlb_interface; // 定义 tlb_interface 接口。
    //Handshaking
    logic ready; // 声明信号、变量或生成变量。
    logic new_request; // 声明信号、变量或生成变量。
    logic done; // 声明信号、变量或生成变量。

    //TLB Inputs
    logic [31:0] virtual_address; // 声明信号、变量或生成变量。
    logic rnw; // 声明信号、变量或生成变量。

    //TLB Outputs
    logic is_fault; // 声明信号、变量或生成变量。
    logic [31:0] physical_address; // 声明信号、变量或生成变量。

    modport tlb (
        input new_request, virtual_address, rnw, // 声明输入端口。
        output ready, done, is_fault, physical_address // 声明输出端口。
    );
    modport requester  (
        output new_request, virtual_address, rnw, // 声明输出端口。
        input ready, done, is_fault, physical_address // 声明输入端口。
    );
endinterface // 结束接口定义。

interface load_store_queue_interface; // 定义 load_store_queue_interface 接口。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    //Issue inputs
    lsq_entry_t data_in;
    logic potential_push; // 声明信号、变量或生成变量。
    logic push; // 声明信号、变量或生成变量。
    logic load_pop; // 声明信号、变量或生成变量。
    logic store_pop; // 声明信号、变量或生成变量。

    //Address translation
    logic addr_push; // 声明信号、变量或生成变量。
    lsq_addr_entry_t addr_data_in;

    //LSQ outputs
    data_access_shared_inputs_t load_data_out;
    data_access_shared_inputs_t store_data_out;

    logic load_valid; // 声明信号、变量或生成变量。
    logic store_valid; // 声明信号、变量或生成变量。

    logic full; // 声明信号、变量或生成变量。

    //LSQ status
    logic sq_empty; // 声明信号、变量或生成变量。
    logic empty; // 声明信号、变量或生成变量。

    modport queue (
        input data_in, potential_push, push, addr_push, addr_data_in, load_pop, store_pop, // 声明输入端口。
        output full, load_data_out, store_data_out, load_valid, store_valid, sq_empty, empty // 声明输出端口。
    );
    modport ls (
        output data_in, potential_push, push, addr_push, addr_data_in, load_pop, store_pop, // 声明输出端口。
        input full, load_data_out, store_data_out, load_valid, store_valid, sq_empty, empty // 声明输入端口。
    );
endinterface // 结束接口定义。


interface store_queue_interface; // 定义 store_queue_interface 接口。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    //Issue inputs
    lsq_entry_t data_in;
    logic push; // 声明信号、变量或生成变量。
    logic pop; // 声明信号、变量或生成变量。

    sq_entry_t data_out;
    logic valid; // 声明信号、变量或生成变量。
    logic full; // 声明信号、变量或生成变量。

    //SQ status
    logic empty; // 声明信号、变量或生成变量。

    modport queue (
        input data_in, push, pop, // 声明输入端口。
        output full, data_out, valid, empty // 声明输出端口。
    );
    modport ls (
        output data_in, push, pop, // 声明输出端口。
        input full, data_out, valid, empty // 声明输入端口。
    );
endinterface // 结束接口定义。

interface cache_functions_interface #(parameter int TAG_W = 8, parameter int LINE_W = 4, parameter int SUB_LINE_W = 2); // 定义 cache_functions_interface 接口。

    function logic [LINE_W-1:0] xor_mask (int WAY); // 开始函数定义，用于组合计算或辅助逻辑。
        for (int i = 0; i < LINE_W; i++) // 执行循环或遍历。
            xor_mask[i] = ((WAY % 2) == 0) ? 1'b1 : 1'b0;
    endfunction // 结束函数定义。

    function logic [LINE_W-1:0] getHashedLineAddr (logic[31:0] addr, int WAY); // 开始函数定义，用于组合计算或辅助逻辑。
        getHashedLineAddr = addr[2 + SUB_LINE_W +: LINE_W] ^ (addr[2 + SUB_LINE_W + LINE_W +: LINE_W] & xor_mask(WAY));
    endfunction // 结束函数定义。

    function logic[TAG_W-1:0] getTag(logic[31:0] addr); // 开始函数定义，用于组合计算或辅助逻辑。
        getTag = addr[2 + LINE_W + SUB_LINE_W +: TAG_W];
    endfunction // 结束函数定义。

    function logic [LINE_W-1:0] getTagLineAddr (logic[31:0] addr); // 开始函数定义，用于组合计算或辅助逻辑。
        getTagLineAddr = addr[2 + SUB_LINE_W +: LINE_W];
    endfunction // 结束函数定义。

    function logic [LINE_W+SUB_LINE_W-1:0] getDataLineAddr (logic[31:0] addr); // 开始函数定义，用于组合计算或辅助逻辑。
        getDataLineAddr = addr[2 +: LINE_W + SUB_LINE_W];
    endfunction // 结束函数定义。

endinterface // 结束接口定义。

interface addr_utils_interface #(parameter logic [31:0] BASE_ADDR = 32'h00000000, parameter logic [31:0] UPPER_BOUND = 32'hFFFFFFFF); // 定义 addr_utils_interface 接口。
        //The range should be aligned for performance
        function address_range_check (input logic[31:0] addr); // 开始函数定义，用于组合计算或辅助逻辑。
            /* verilator lint_off UNSIGNED */
            /* verilator lint_off CMPCONST */
            return addr >= BASE_ADDR & addr <= UPPER_BOUND; // 返回函数结果。
            /* verilator lint_on UNSIGNED */
            /* verilator lint_on CMPCONST */
        endfunction // 结束函数定义。
endinterface // 结束接口定义。

interface memory_sub_unit_interface; // 定义 memory_sub_unit_interface 接口。
    logic new_request; // 声明信号、变量或生成变量。
    logic [31:0] addr; // 声明信号、变量或生成变量。
    logic re; // 声明信号、变量或生成变量。
    logic we; // 声明信号、变量或生成变量。
    logic [3:0] be; // 声明信号、变量或生成变量。
    logic [31:0] data_in; // 声明信号、变量或生成变量。

    logic [31:0] data_out; // 声明信号、变量或生成变量。
    logic data_valid; // 声明信号、变量或生成变量。
    logic ready; // 声明信号、变量或生成变量。

    modport responder (
        input addr, re, we, be, data_in, new_request, // 声明输入端口。
        output data_out, data_valid, ready // 声明输出端口。
    );
    modport controller (
        input data_out, data_valid, ready, // 声明输入端口。
        output addr, re, we, be, data_in, new_request // 声明输出端口。
    );
endinterface // 结束接口定义。

//start and done are cycle cycle pulses
interface unsigned_division_interface #(parameter DATA_WIDTH = 32); // 定义 unsigned_division_interface 接口。
    logic start; // 声明信号、变量或生成变量。
    logic [DATA_WIDTH-1:0] dividend; // 声明信号、变量或生成变量。
    logic [$clog2(DATA_WIDTH)-1:0] dividend_CLZ; // 声明信号、变量或生成变量。
    logic [DATA_WIDTH-1:0] divisor; // 声明信号、变量或生成变量。
    logic [$clog2(DATA_WIDTH)-1:0] divisor_CLZ; // 声明信号、变量或生成变量。
    logic [DATA_WIDTH-1:0] remainder; // 声明信号、变量或生成变量。
    logic [DATA_WIDTH-1:0] quotient; // 声明信号、变量或生成变量。
    logic done; // 声明信号、变量或生成变量。
    logic divisor_is_zero; // 声明信号、变量或生成变量。
    modport requester (input remainder, quotient, done, output dividend, dividend_CLZ, divisor, divisor_CLZ, divisor_is_zero, start);
    modport divider (output remainder, quotient, done, input dividend, dividend_CLZ, divisor, divisor_CLZ, divisor_is_zero, start);
endinterface // 结束接口定义。

interface unsigned_sqrt_interface #(parameter DATA_WIDTH = 32); // 定义 unsigned_sqrt_interface 接口。
    logic start; // 声明信号、变量或生成变量。
    logic [DATA_WIDTH-1:0] radicand; // 声明信号、变量或生成变量。
    logic [DATA_WIDTH-1:0] remainder; // 声明信号、变量或生成变量。
    logic [DATA_WIDTH-1:0] result; // 声明信号、变量或生成变量。
    logic done; // 声明信号、变量或生成变量。

    modport requester (input remainder, result, done, output radicand, start);
    modport sqrt (output remainder, result, done, input radicand, start);
endinterface // 结束接口定义。

interface renamer_interface #(parameter NUM_WB_GROUPS = 3, parameter READ_PORTS = 2); // 定义 renamer_interface 接口。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    rs_addr_t rd_addr;
    rs_addr_t rs_addr [READ_PORTS];
    logic [$clog2(NUM_WB_GROUPS)-1:0] rd_wb_group; // 声明信号、变量或生成变量。
    logic uses_rd; // 声明信号、变量或生成变量。
    id_t id;

    phys_addr_t phys_rs_addr [READ_PORTS];
    phys_addr_t phys_rd_addr;

    logic [$clog2(NUM_WB_GROUPS)-1:0] rs_wb_group [READ_PORTS]; // 声明信号、变量或生成变量。

    modport renamer (
        input rd_addr, rs_addr, rd_wb_group, uses_rd, id, // 声明输入端口。
        output phys_rs_addr, rs_wb_group, phys_rd_addr // 声明输出端口。
    );
    modport decode (
        input phys_rs_addr, rs_wb_group, phys_rd_addr, // 声明输入端口。
        output rd_addr, rs_addr, rd_wb_group, uses_rd, id // 声明输出端口。
    );
endinterface // 结束接口定义。

interface register_file_issue_interface #(parameter NUM_WB_GROUPS = 3, parameter DATA_WIDTH = 32, parameter READ_PORTS = 2); // 定义 register_file_issue_interface 接口。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    //read interface
    phys_addr_t phys_rs_addr [READ_PORTS];
    logic [$clog2(NUM_WB_GROUPS)-1:0] rs_wb_group [READ_PORTS]; // 声明信号、变量或生成变量。
    logic [DATA_WIDTH-1:0] data [READ_PORTS]; // 声明信号、变量或生成变量。
    logic inuse [READ_PORTS]; // 声明信号、变量或生成变量。

    //issue write interface
    phys_addr_t phys_rd_addr;
    logic single_cycle_or_flush; // 声明信号、变量或生成变量。

    modport register_file (
        input phys_rs_addr, phys_rd_addr, single_cycle_or_flush, rs_wb_group, // 声明输入端口。
        output data, inuse // 声明输出端口。
    );
    modport issue (
        output phys_rs_addr, phys_rd_addr, single_cycle_or_flush, rs_wb_group, // 声明输出端口。
        input data, inuse // 声明输入端口。
    );
endinterface // 结束接口定义。

interface fp_intermediate_wb_interface; // 定义 fp_intermediate_wb_interface 接口。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。

    logic ack; // 声明信号、变量或生成变量。

    id_t id;
    logic done; // 声明信号、变量或生成变量。
    fp_t rd;
    logic expo_overflow; // 声明信号、变量或生成变量。
    fflags_t fflags;
    rm_t rm;
    logic carry; // 声明信号、变量或生成变量。
    logic safe; // 声明信号、变量或生成变量。
    logic hidden; // 声明信号、变量或生成变量。
    grs_t grs;
    fp_shift_amt_t clz;
    logic right_shift; // 声明信号、变量或生成变量。
    fp_shift_amt_t right_shift_amt;
    logic subnormal; // 声明信号、变量或生成变量。
    logic ignore_max_expo; // 声明信号、变量或生成变量。
    logic d2s; // 声明信号、变量或生成变量。

    modport unit (
        input ack, // 声明输入端口。
        output id, done, rd, expo_overflow, fflags, rm, hidden, grs, clz, carry, safe, subnormal, right_shift, right_shift_amt, ignore_max_expo, d2s // 声明输出端口。
    );
    modport wb (
        output ack, // 声明输出端口。
        input id, done, rd, expo_overflow, fflags, rm, hidden, grs, clz, carry, safe, subnormal, right_shift, right_shift_amt, ignore_max_expo, d2s // 声明输入端口。
    );
endinterface // 结束接口定义。

interface amo_interface; // 定义 amo_interface 接口。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。

    //Atomic Load Reserved and Store Conditional
    logic set_reservation; // 声明信号、变量或生成变量。
    logic clear_reservation; // 声明信号、变量或生成变量。
    logic[31:0] reservation; // 声明信号、变量或生成变量。
    logic reservation_valid; // 声明信号、变量或生成变量。

    //Atomic Read-Modify-Write
    logic rmw_valid; // 声明信号、变量或生成变量。
    amo_t op;
    logic[31:0] rs1; // 声明信号、变量或生成变量。
    logic[31:0] rs2; // 声明信号、变量或生成变量。
    logic[31:0] rd; // 声明信号、变量或生成变量。

    modport subunit (
        input reservation_valid, rd, // 声明输入端口。
        output set_reservation, clear_reservation, reservation, rmw_valid, op, rs1, rs2 // 声明输出端口。
    );
    modport amo_unit (
        output reservation_valid, rd, // 声明输出端口。
        input set_reservation, clear_reservation, reservation, rmw_valid, op, rs1, rs2 // 声明输入端口。
    );

endinterface // 结束接口定义。
