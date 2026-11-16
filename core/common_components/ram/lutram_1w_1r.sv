// ============================================================================
// 文件：core/common_components/ram/lutram_1w_1r.sv
// 类型：module
// 名称：lutram_1w_1r
// 作用：实现单写端口、单读端口的 LUTRAM 存储模型。
// 行为：写操作在 clk 上升沿同步完成；读操作由 raddr 组合寻址。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2021 Eric Matthews,  Lesley Shannon
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

module lutram_1w_1r // 定义 lutram_1w_1r 模块。
    #(
        parameter type DATA_TYPE = logic, // 存储字的数据类型；$bits(DATA_TYPE) 决定每个存储字的位宽。
        parameter DEPTH = 32 // 存储深度；有效地址范围是 0 ~ DEPTH-1。
    )
    (
        input logic clk, // 时钟输入；写操作在上升沿生效。

        input logic[$clog2(DEPTH)-1:0] waddr, // 写地址。
        input logic[$clog2(DEPTH)-1:0] raddr, // 读地址。

        input logic ram_write, // 写使能；为 1 时在时钟上升沿写入 new_ram_data。
        input DATA_TYPE new_ram_data, // 待写入的数据。
        output DATA_TYPE ram_data_out // 读出的数据；随 raddr 组合变化。
    );

    // 综合属性：
    // - ramstyle/ram_style 引导综合工具将该数组推断为分布式 RAM/LUTRAM；
    // - no_rw_check 关闭读写冲突检查，避免工具因同地址读写检查而无法推断 LUTRAM。
    // ram 是 DEPTH 个存储字组成的数组，每个存储字宽度为 DATA_TYPE 的位宽。
    (* ramstyle = "MLAB, no_rw_check", ram_style = "distributed" *) logic [$bits(DATA_TYPE)-1:0] ram [DEPTH-1:0];

    // 仿真初始化：仿真开始时把所有存储字初始化为 0。
    // 注意：这不是同步复位；硬件上是否生效取决于目标器件和综合工具的初始化能力。
    initial ram = '{default: 0};

    // 单写端口：仅在 ram_write 有效的时钟上升沿写入指定地址。
    //always_ff @ (posedge clk) begin
    always @ (posedge clk) begin
        if (ram_write)
            ram[waddr] <= new_ram_data;
    end

    // 单读端口：组合读，没有读使能；raddr 变化后输出对应存储字。
    // 同地址读写时，本仿真模型在时钟沿后读出刚写入的新值；
    // 实际 FPGA RAM 原语的读写冲突语义应以目标器件手册为准。
    assign ram_data_out = ram[raddr];

endmodule // 结束模块定义。