// ============================================================================
// 文件：core/fetch_stage/icache.sv
// 类型：module
// 名称：icache
// 作用：实现指令缓存，处理命中、缺失、refill 和 flush。
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

module icache // 定义 icache 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG // 声明可配置参数。
    )

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        input logic ifence, // 声明输入端口。
        input logic icache_on, // 声明输入端口。
        mem_interface.ro_master mem,

        memory_sub_unit_interface.responder fetch_sub
    );

    localparam derived_cache_config_t SCONFIG = get_derived_cache_params(CONFIG, CONFIG.ICACHE, CONFIG.ICACHE_ADDR); // 声明局部常量。
    localparam bit [SCONFIG.SUB_LINE_ADDR_W-1:0] END_OF_LINE_COUNT = SCONFIG.SUB_LINE_ADDR_W'(CONFIG.ICACHE.LINE_W-1); // 声明局部常量。

    cache_functions_interface #(.TAG_W(SCONFIG.TAG_W), .LINE_W(SCONFIG.LINE_ADDR_W), .SUB_LINE_W(SCONFIG.SUB_LINE_ADDR_W)) addr_utils();

    logic ifence_in_progress; // 声明信号、变量或生成变量。
    logic[SCONFIG.LINE_ADDR_W-1:0] ifence_counter; // 声明信号、变量或生成变量。

    logic tag_hit; // 声明信号、变量或生成变量。
    logic [CONFIG.ICACHE.WAYS-1:0] tag_hit_way; // 声明信号、变量或生成变量。

    logic tag_update; // 声明信号、变量或生成变量。
    logic [CONFIG.ICACHE.WAYS-1:0] replacement_way; // 声明信号、变量或生成变量。
    logic [CONFIG.ICACHE.WAYS-1:0] tag_update_way; // 声明信号、变量或生成变量。

    logic [SCONFIG.SUB_LINE_ADDR_W-1:0] word_count; // 声明信号、变量或生成变量。
    logic [SCONFIG.SUB_LINE_ADDR_W-1:0] target_word; // 声明信号、变量或生成变量。
    logic is_target_word; // 声明信号、变量或生成变量。

    logic line_complete; // 声明信号、变量或生成变量。

    logic [CONFIG.ICACHE.WAYS-1:0][31:0] data_out; // 声明信号、变量或生成变量。

    logic linefill_in_progress; // 声明信号、变量或生成变量。
    logic request_in_progress; // 声明信号、变量或生成变量。

    logic miss_data_valid; // 声明信号、变量或生成变量。
    logic second_cycle; // 声明信号、变量或生成变量。
    logic [31:0] second_cycle_addr; // 声明信号、变量或生成变量。

    fifo_interface #(.DATA_TYPE(logic[31:0])) input_fifo();

    logic new_request; // 声明信号、变量或生成变量。
    logic [31:0] new_request_addr; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation

    //On a new request, the tag and data banks are accessed
    //On the second cycle of a request hit/miss determination is performed
    //On a miss, the memory request starts on the third cycle

    assign new_request = (fetch_sub.new_request | input_fifo.valid) & ((~request_in_progress | tag_hit) & ~linefill_in_progress); // 执行连续赋值，把组合逻辑连接到目标信号。

    assign input_fifo.push = fetch_sub.new_request & (~new_request | input_fifo.valid); // 执行连续赋值，把组合逻辑连接到目标信号。
    assign input_fifo.potential_push = input_fifo.push; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign input_fifo.pop = new_request & input_fifo.valid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign input_fifo.data_in = fetch_sub.addr; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign new_request_addr = input_fifo.valid ? input_fifo.data_out : fetch_sub.addr; // 执行连续赋值，把组合逻辑连接到目标信号。

    cva5_fifo #(.DATA_TYPE(logic[31:0]), .FIFO_DEPTH(2))
    cache_input_fifo (
        .clk (clk),
        .rst (rst),
        .fifo (input_fifo)
    );

    ////////////////////////////////////////////////////
    //Instruction fence
    generate if (CONFIG.INCLUDE_IFENCE) begin : gen_ifence // 开始生成块，在编译期展开硬件结构。
        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) begin // 执行条件判断，满足条件时进入对应分支。
                ifence_counter <= '0;
                ifence_in_progress <= 0;
            end else begin // 结束语句块。
                if (ifence) // 执行条件判断，满足条件时进入对应分支。
                    ifence_in_progress <= 1;
                else if (&ifence_counter) // 执行否则如果分支的条件判断。
                    ifence_in_progress <= 0;
                if (ifence_in_progress) // 执行条件判断，满足条件时进入对应分支。
                    ifence_counter <= ifence_counter+1;
            end // 结束语句块。
        end // 结束语句块。

    end else begin : gen_no_ifence // 结束语句块。
        assign ifence_in_progress = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign ifence_counter = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

    ////////////////////////////////////////////////////
    //Ready determination
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            request_in_progress <= 0;
        else // 执行否则分支。
            request_in_progress <= (request_in_progress & ~fetch_sub.data_valid) | new_request;
    end // 结束语句块。

    assign fetch_sub.ready = ~input_fifo.full & ~ifence_in_progress; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //General Control Logic
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            second_cycle <= 0;
        else // 执行否则分支。
            second_cycle <= new_request;
    end // 结束语句块。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (new_request) // 执行条件判断，满足条件时进入对应分支。
            second_cycle_addr <= new_request_addr;
    end // 结束语句块。

    //As request can be aborted on any cycle, only update tags if memory request is in progress
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            tag_update <= 0;
        else // 执行否则分支。
            tag_update <= mem.ack;
    end // 结束语句块。

    //Replacement policy is psuedo random
    cycler #(CONFIG.ICACHE.WAYS) replacement_policy (
        .clk (clk),
        .rst (rst),
        .en (1'b1),
        .one_hot (replacement_way)
    );
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (second_cycle & ~linefill_in_progress) // 执行条件判断，满足条件时进入对应分支。
            tag_update_way <= replacement_way;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //L1 arbiter request
    logic initiate_l1_request; // 声明信号、变量或生成变量。
    logic request_r; // 声明信号、变量或生成变量。

    assign mem.addr = second_cycle_addr[31:2]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign mem.rlen = 5'(CONFIG.ICACHE.LINE_W-1); // 执行连续赋值，把组合逻辑连接到目标信号。

    assign initiate_l1_request = second_cycle & (~tag_hit | ~icache_on); // 执行连续赋值，把组合逻辑连接到目标信号。
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            request_r <= 0;
        else // 执行否则分支。
            request_r <= (initiate_l1_request | request_r) & ~mem.ack;
    end // 结束语句块。
    assign mem.request = request_r; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Miss state tracking
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            linefill_in_progress <= 0;
        else // 执行否则分支。
            linefill_in_progress <= (linefill_in_progress & ~line_complete) | mem.ack;
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Tag banks
    itag_banks #(.CONFIG(CONFIG), .SCONFIG(SCONFIG))
    icache_tag_banks (
        .clk(clk),
        .rst(rst), //clears the read_hit_allowed flag
        .ifence(ifence_in_progress),
        .ifence_addr(ifence_counter),
        .stage1_line_addr(addr_utils.getTagLineAddr(new_request_addr)),
        .stage2_line_addr(addr_utils.getTagLineAddr(second_cycle_addr)),
        .stage2_tag(addr_utils.getTag(second_cycle_addr)),
        .update_way(tag_update_way),
        .update(tag_update),
        .stage1_adv(new_request & icache_on),
        .tag_hit(tag_hit),
        .tag_hit_way(tag_hit_way)
    );

    ////////////////////////////////////////////////////
    //Data Banks
    sdp_ram #(
        .ADDR_WIDTH(SCONFIG.LINE_ADDR_W+SCONFIG.SUB_LINE_ADDR_W),
        .NUM_COL(CONFIG.ICACHE.WAYS),
        .COL_WIDTH(32),
        .PIPELINE_DEPTH(0)
    ) idata_bank (
        .a_en(mem.rvalid),
        .a_wbe(tag_update_way),
        .a_wdata({CONFIG.ICACHE.WAYS{mem.rdata}}),
        .a_addr(addr_utils.getDataLineAddr({second_cycle_addr[31:SCONFIG.SUB_LINE_ADDR_W+2], word_count, 2'b0})),
        .b_en(new_request),
        .b_addr(addr_utils.getDataLineAddr(new_request_addr)),
        .b_rdata(data_out),
    .*);

    ////////////////////////////////////////////////////
    //Miss data path
    assign target_word = second_cycle_addr[2 +: SCONFIG.SUB_LINE_ADDR_W]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign is_target_word = (target_word == word_count); // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            word_count <= 0;
        else // 执行否则分支。
            word_count <= word_count + SCONFIG.SUB_LINE_ADDR_W'(mem.rvalid);
    end // 结束语句块。

    assign miss_data_valid = request_in_progress & mem.rvalid & is_target_word; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign line_complete = mem.rvalid & (word_count == END_OF_LINE_COUNT); // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Output muxing
    localparam OMUX_W = CONFIG.ICACHE.WAYS+1; // 声明局部常量。
    logic [OMUX_W-1:0] priority_vector; // 声明信号、变量或生成变量。
    logic [$clog2(OMUX_W)-1:0] output_sel; // 声明信号、变量或生成变量。
    logic [31:0] output_array [OMUX_W]; // 声明信号、变量或生成变量。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        priority_vector[0] = miss_data_valid;
        output_array[0] = mem.rdata;
        for (int i = 0; i < CONFIG.ICACHE.WAYS; i++) begin // 执行循环或遍历。
            priority_vector[i+1] = tag_hit_way[i];
            output_array[i+1] = data_out[i];
        end // 结束语句块。
    end // 结束语句块。
    priority_encoder #(.WIDTH(OMUX_W))
    arb_encoder
    (
        .priority_vector (priority_vector),
        .encoded_result (output_sel)
    );
    assign fetch_sub.data_out = output_array[output_sel]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fetch_sub.data_valid = miss_data_valid | tag_hit; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions
    icache_l1_arb_ack_assertion:
        assert property (@(posedge clk) disable iff (rst) mem.ack |-> mem.request) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("Spurious icache ack received from arbiter!"); // 执行否则分支。

    icache_l1_arb_data_valid_assertion:
        assert property (@(posedge clk) disable iff (rst) mem.rvalid |-> linefill_in_progress) // 定义或检查断言、假设、覆盖或时序性质。
        else $error("Spurious icache data received from arbiter!"); // 执行否则分支。

endmodule // 结束模块定义。
