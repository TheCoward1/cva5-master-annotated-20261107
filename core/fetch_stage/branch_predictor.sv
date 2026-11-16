// ============================================================================
// 文件：core/fetch_stage/branch_predictor.sv
// 类型：module
// 名称：branch_predictor
// 作用：实现分支历史和目标预测，减少取指重定向开销。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017-2020 Eric Matthews,  Lesley Shannon
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

module branch_predictor // 定义 branch_predictor 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG // 声明可配置参数。
    )

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        branch_predictor_interface.branch_predictor bp,
        input branch_results_t br_results, // 声明输入端口。
        ras_interface.branch_predictor ras
    );

    //BP tag width can be reduced, based on memory size, when virtual address
    //support is not enabled
    localparam longint CACHE_RANGE = 64'(CONFIG.ICACHE_ADDR.H) - 64'(CONFIG.ICACHE_ADDR.L) + 1; // 声明局部常量。
    localparam longint SCRATCH_RANGE = 64'(CONFIG.ILOCAL_MEM_ADDR.H) - 64'(CONFIG.ILOCAL_MEM_ADDR.L) + 1; // 声明局部常量。
    localparam longint BUS_RANGE = 64'(CONFIG.IBUS_ADDR.H) - 64'(CONFIG.IBUS_ADDR.L) + 1; // 声明局部常量。

    function int get_memory_width(); // 开始函数定义，用于组合计算或辅助逻辑。
        if(CONFIG.MODES == MSU) // 执行条件判断，满足条件时进入对应分支。
            return 32; // 返回函数结果。
        else if (CONFIG.INCLUDE_ICACHE && ( // 执行否则如果分支的条件判断。
            (CONFIG.INCLUDE_ILOCAL_MEM && CACHE_RANGE > SCRATCH_RANGE) ||
            (CONFIG.INCLUDE_IBUS && CACHE_RANGE > BUS_RANGE) ||
            (!CONFIG.INCLUDE_ILOCAL_MEM && !CONFIG.INCLUDE_IBUS))
        )
            return $clog2(CACHE_RANGE); // 返回函数结果。
        else if (CONFIG.INCLUDE_IBUS && ( // 执行否则如果分支的条件判断。
            (CONFIG.INCLUDE_ILOCAL_MEM && BUS_RANGE > SCRATCH_RANGE) ||
            (!CONFIG.INCLUDE_ILOCAL_MEM))
        )
            return $clog2(BUS_RANGE); // 返回函数结果。
        else // 执行否则分支。
            return $clog2(SCRATCH_RANGE); // 返回函数结果。
    endfunction // 结束函数定义。

    localparam BRANCH_ADDR_W = $clog2(CONFIG.BP.ENTRIES); // 声明局部常量。
    localparam BTAG_W = get_memory_width() - BRANCH_ADDR_W - 2; // 声明局部常量。
    cache_functions_interface #(.TAG_W(BTAG_W), .LINE_W(BRANCH_ADDR_W), .SUB_LINE_W(0)) addr_utils();

// 定义类型别名或枚举/结构类型。
    typedef logic[1:0] branch_predictor_metadata_t;
// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic valid; // 声明信号、变量或生成变量。
        logic [BTAG_W-1:0] tag; // 声明信号、变量或生成变量。
        logic is_branch; // 声明信号、变量或生成变量。
        logic is_return; // 声明信号、变量或生成变量。
        logic is_call; // 声明信号、变量或生成变量。
        branch_predictor_metadata_t metadata;
    } branch_table_entry_t;

    branch_table_entry_t [CONFIG.BP.WAYS-1:0] if_entry;
    branch_table_entry_t ex_entry;

// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        branch_predictor_metadata_t branch_predictor_metadata;
        logic branch_prediction_used; // 声明信号、变量或生成变量。
        logic [CONFIG.BP.WAYS-1:0] branch_predictor_update_way; // 声明信号、变量或生成变量。
    } branch_metadata_t;
    branch_metadata_t branch_metadata_ex;

    logic branch_predictor_direction_changed; // 声明信号、变量或生成变量。
    logic [31:0] new_jump_addr; // 声明信号、变量或生成变量。
    logic [CONFIG.BP.WAYS-1:0][31:0] predicted_pc; // 声明信号、变量或生成变量。

    logic [CONFIG.BP.WAYS-1:0] tag_matches; // 声明信号、变量或生成变量。
    logic [CONFIG.BP.WAYS-1:0] replacement_way; // 声明信号、变量或生成变量。
    logic [CONFIG.BP.WAYS-1:0] tag_update_way; // 声明信号、变量或生成变量。
    logic [CONFIG.BP.WAYS-1:0] target_update_way; // 声明信号、变量或生成变量。
    logic [$clog2(CONFIG.BP.WAYS > 1 ? CONFIG.BP.WAYS : 2)-1:0] hit_way; // 声明信号、变量或生成变量。
    logic tag_match; // 声明信号、变量或生成变量。
    logic use_predicted_pc; // 声明信号、变量或生成变量。

    addr_utils_interface #(CONFIG.IBUS_ADDR.L, CONFIG.IBUS_ADDR.H) ibus_addr_utils ();

    /////////////////////////////////////////

    genvar i; // 声明信号、变量或生成变量。
    generate if (CONFIG.INCLUDE_BRANCH_PREDICTOR) begin : gen_bp // 开始生成块，在编译期展开硬件结构。
        for (i=0; i<CONFIG.BP.WAYS; i++) begin : gen_bp_rams // 执行循环或遍历。
            sdp_ram #(
                .ADDR_WIDTH(BRANCH_ADDR_W),
                .NUM_COL(1),
                .COL_WIDTH($bits(branch_table_entry_t)),
                .PIPELINE_DEPTH(0)
            ) tag_bank (
                .a_en(tag_update_way[i]),
                .a_wbe(tag_update_way[i]),
                .a_wdata(ex_entry),
                .a_addr(addr_utils.getHashedLineAddr(br_results.pc, i)),
                .b_en(bp.new_mem_request),
                .b_addr(addr_utils.getHashedLineAddr(bp.next_pc, i)),
                .b_rdata(if_entry[i]),
            .*);

            sdp_ram #(
                .ADDR_WIDTH(BRANCH_ADDR_W),
                .NUM_COL(1),
                .COL_WIDTH(32),
                .PIPELINE_DEPTH(0)
            ) addr_table (
                .a_en(target_update_way[i]),
                .a_wbe(target_update_way[i]),
                .a_wdata(br_results.target_pc),
                .a_addr(addr_utils.getHashedLineAddr(br_results.pc, i)),
                .b_en(bp.new_mem_request),
                .b_addr(addr_utils.getHashedLineAddr(bp.next_pc, i)),
                .b_rdata(predicted_pc[i]),
            .*);

            assign tag_matches[i] = ({if_entry[i].valid, if_entry[i].tag} == {1'b1, addr_utils.getTag(bp.if_pc)}); // 执行连续赋值，把组合逻辑连接到目标信号。
        end // 结束语句块。
    end // 结束语句块。
    endgenerate // 结束生成块。

    ////////////////////////////////////////////////////
    //Instruction Fetch Response
    one_hot_to_integer #(CONFIG.BP.WAYS)
    hit_way_conv (
        .one_hot(tag_matches),
        .int_out(hit_way)
    );

    assign tag_match = |tag_matches; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign use_predicted_pc = CONFIG.INCLUDE_BRANCH_PREDICTOR & tag_match; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Predicted PC and whether the prediction is valid
    assign bp.predicted_pc = predicted_pc[hit_way]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign bp.use_prediction = use_predicted_pc; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign bp.is_branch = if_entry[hit_way].is_branch; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign bp.is_return = if_entry[hit_way].is_return; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign bp.is_call = if_entry[hit_way].is_call; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Instruction Fetch metadata
    cycler #(CONFIG.BP.WAYS)
    replacement_policy (
        .clk (clk),
        .rst (rst),
        .en (1'b1),
        .one_hot (replacement_way)
    );

    lutram_1w_1r #(.DATA_TYPE(branch_metadata_t), .DEPTH(MAX_IDS))
    branch_metadata_table (
        .clk(clk),
        .waddr(bp.pc_id),
        .raddr(br_results.id),
        .ram_write(bp.pc_id_assigned),
        .new_ram_data('{
            branch_predictor_metadata : if_entry[hit_way].metadata,
            branch_prediction_used : use_predicted_pc,
            branch_predictor_update_way : tag_match ? tag_matches : replacement_way
        }),
        .ram_data_out(branch_metadata_ex)
    );

    ////////////////////////////////////////////////////
    //Execution stage update
    assign ex_entry.valid = 1; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ex_entry.tag = addr_utils.getTag(br_results.pc); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ex_entry.is_branch = br_results.is_branch; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ex_entry.is_return = br_results.is_return; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ex_entry.is_call = br_results.is_call; // 执行连续赋值，把组合逻辑连接到目标信号。


    //2-bit saturating counter
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case(branch_metadata_ex.branch_predictor_metadata) // 开始多分支选择，根据表达式选择对应分支。
            2'b00 : ex_entry.metadata = br_results.branch_taken ? 2'b01 : 2'b00;
            2'b01 : ex_entry.metadata = br_results.branch_taken ? 2'b10 : 2'b00;
            2'b10 : ex_entry.metadata = br_results.branch_taken ? 2'b11 : 2'b01;
            2'b11 : ex_entry.metadata = br_results.branch_taken ? 2'b11 : 2'b10;
        endcase // 结束多分支选择。
        if (~branch_metadata_ex.branch_prediction_used) // 执行条件判断，满足条件时进入对应分支。
            ex_entry.metadata = br_results.branch_taken ? 2'b11 : 2'b00;
    end // 结束语句块。
    assign branch_predictor_direction_changed = // 执行连续赋值，把组合逻辑连接到目标信号。
        (~branch_metadata_ex.branch_prediction_used) |
        (branch_metadata_ex.branch_predictor_metadata[1] ^ ex_entry.metadata[1]);

    assign tag_update_way = {CONFIG.BP.WAYS{br_results.valid}} & (branch_metadata_ex.branch_predictor_update_way); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign target_update_way = {CONFIG.BP.WAYS{branch_predictor_direction_changed}} & tag_update_way; // 执行连续赋值，把组合逻辑连接到目标信号。
    ////////////////////////////////////////////////////
    //Target PC if branch flush occured
    assign bp.branch_flush_pc = br_results.target_pc; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //RAS support
    assign ras.branch_retired = br_results.valid & br_results.is_branch & branch_metadata_ex.branch_prediction_used; // 执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
