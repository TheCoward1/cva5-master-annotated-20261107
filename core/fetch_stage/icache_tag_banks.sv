// ============================================================================
// 文件：core/fetch_stage/icache_tag_banks.sv
// 类型：module
// 名称：itag_banks
// 作用：实现指令缓存的 tag 存储、比较和替换信息。
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

module itag_banks // 定义 itag_banks 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG, // 声明可配置参数。
        parameter derived_cache_config_t SCONFIG = '{default: 0} // 声明可配置参数。
    )

    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        input logic ifence, // 声明输入端口。
        input logic[SCONFIG.LINE_ADDR_W-1:0] ifence_addr, // 声明输入端口。

        input logic[SCONFIG.LINE_ADDR_W-1:0] stage1_line_addr, // 声明输入端口。
        input logic[SCONFIG.LINE_ADDR_W-1:0] stage2_line_addr, // 声明输入端口。
        input logic[SCONFIG.TAG_W-1:0] stage2_tag, // 声明输入端口。

        input logic[CONFIG.ICACHE.WAYS-1:0] update_way, // 声明输入端口。
        input logic update, // 声明输入端口。

        input logic stage1_adv, // 声明输入端口。

        output tag_hit, // 声明输出端口。
        output logic[CONFIG.ICACHE.WAYS-1:0] tag_hit_way // 声明输出端口。
        );

    //Valid + tag
// 定义类型别名或枚举/结构类型。
    typedef logic [SCONFIG.TAG_W : 0] itag_entry_t;
    itag_entry_t[CONFIG.ICACHE.WAYS-1:0]  tag_line;

    logic hit_allowed; // 声明信号、变量或生成变量。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            hit_allowed <= 0;
        else // 执行否则分支。
            hit_allowed <= stage1_adv;
    end // 结束语句块。

    sdp_ram_padded #(
        .ADDR_WIDTH(SCONFIG.LINE_ADDR_W),
        .NUM_COL(CONFIG.ICACHE.WAYS),
        .COL_WIDTH(SCONFIG.TAG_W+1),
        .PIPELINE_DEPTH(0)
    ) itag_bank (
        .a_en(update | ifence),
        .a_wbe(update_way | {CONFIG.ICACHE.WAYS{ifence}}),
        .a_wdata({CONFIG.ICACHE.WAYS{~ifence, stage2_tag}}),
        .a_addr(ifence ? ifence_addr : stage2_line_addr),
        .b_en(stage1_adv),
        .b_addr(stage1_line_addr),
        .b_rdata(tag_line),
    .*);

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        for (int i = 0; i < CONFIG.ICACHE.WAYS; i++) // 执行循环或遍历。
            tag_hit_way[i] = ({hit_allowed, 1'b1, stage2_tag} == {1'b1, tag_line[i]});
    end // 结束语句块。

    assign tag_hit = |tag_hit_way; // 执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
