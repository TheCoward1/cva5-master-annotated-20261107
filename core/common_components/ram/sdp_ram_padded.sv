// ============================================================================
// 文件：core/common_components/ram/sdp_ram_padded.sv
// 类型：module
// 名称：sdp_ram_padded
// 作用：实现带位宽/深度填充的简单双端口 RAM 模型。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2024 Chris Keilbart, Lesley Shannon
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
 */

module sdp_ram_padded // 定义 sdp_ram_padded 模块。

    #(
        parameter ADDR_WIDTH = 10, // 声明可配置参数。
        parameter NUM_COL = 4, //Number of independently writeable components；声明可配置参数。
        parameter COL_WIDTH = 16, //Width the "byte" enable controls；声明可配置参数。
        parameter PIPELINE_DEPTH = 1, //Depth of the output pipeline, is latency in clock cycles；声明可配置参数。
        parameter CASCADE_DEPTH = 4 //Maximum depth of the memory block cascade；声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        //Port A
        input logic a_en, // 声明输入端口。
        input logic[NUM_COL-1:0] a_wbe, // 声明输入端口。
        input logic[COL_WIDTH*NUM_COL-1:0] a_wdata, // 声明输入端口。
        input logic[ADDR_WIDTH-1:0] a_addr, // 声明输入端口。

        //Port B
        input logic b_en, // 声明输入端口。
        input logic[ADDR_WIDTH-1:0] b_addr, // 声明输入端口。
        output logic[COL_WIDTH*NUM_COL-1:0] b_rdata // 声明输出端口。
    );

    localparam DATA_WIDTH = COL_WIDTH*NUM_COL; // 声明局部常量。

    //Pad columns to the nearest multiple of 8 or 9 to allow the use of the byte enable
    //This results in a more compact BRAM encoding
    localparam PAD_WIDTH8 = (8 - (COL_WIDTH % 8)) % 8; // 声明局部常量。
    localparam PAD_WIDTH9 = (9 - (COL_WIDTH % 9)) % 9; // 声明局部常量。
    localparam PAD_WIDTH = PAD_WIDTH8 <= PAD_WIDTH9 ? PAD_WIDTH8 : PAD_WIDTH9; // 声明局部常量。
    localparam PADDED_WIDTH = COL_WIDTH + PAD_WIDTH; // 声明局部常量。
    localparam TOTAL_WIDTH = NUM_COL * PADDED_WIDTH; // 声明局部常量。

    generate if (PAD_WIDTH == 0 || NUM_COL == 1) begin : gen_no_padding // 开始生成块，在编译期展开硬件结构。
        sdp_ram #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .NUM_COL(NUM_COL),
            .COL_WIDTH(COL_WIDTH),
            .PIPELINE_DEPTH(PIPELINE_DEPTH),
            .CASCADE_DEPTH(CASCADE_DEPTH)
        ) mem (.*);
    end else begin : gen_padded // 结束语句块。
        logic[TOTAL_WIDTH-1:0] a_padded; // 声明信号、变量或生成变量。
        logic[TOTAL_WIDTH-1:0] b_padded; // 声明信号、变量或生成变量。

        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            a_padded = 'x;
            for (int i = 0; i < NUM_COL; i++) begin // 执行循环或遍历。
                a_padded[i*PADDED_WIDTH+:COL_WIDTH] = a_wdata[i*COL_WIDTH+:COL_WIDTH];
                b_rdata[i*COL_WIDTH+:COL_WIDTH] = b_padded[i*PADDED_WIDTH+:COL_WIDTH];
            end // 结束语句块。
        end // 结束语句块。

        sdp_ram #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .NUM_COL(NUM_COL),
            .COL_WIDTH(PADDED_WIDTH),
            .PIPELINE_DEPTH(PIPELINE_DEPTH),
            .CASCADE_DEPTH(CASCADE_DEPTH)
        ) mem (
            .a_wdata(a_padded),
            .b_rdata(b_padded),
        .*);
    end endgenerate // 结束语句块。

endmodule // 结束模块定义。
