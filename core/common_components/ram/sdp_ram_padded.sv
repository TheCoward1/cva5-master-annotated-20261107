// ============================================================================
// 文件：core/common_components/ram/sdp_ram_padded.sv
// 模块：sdp_ram_padded（按列补齐内部位宽的简单双端口 RAM 包装层）
// 作用：保持外部逻辑列宽，将内部各列按需补齐到 8 或 9 的倍数，再连接 sdp_ram。
//       目的是便于匹配常见 FPGA 块 RAM 的列写使能粒度；实际映射取决于器件和综合工具。
// 容量：对外仍是 2**ADDR_WIDTH 个存储字，每字 NUM_COL * COL_WIDTH 位；不填充地址深度。
// 用途：项目中的 I-cache、D-cache tag bank 用一列保存一路的 tag/valid 信息，按 way 写入。
// 说明：仅补充中文注释，保持代码逻辑不变；编码为 UTF-8。
//
// 接口与时序约定：
//   1. A 口只写，B 口只读，共用 clk；a_wbe[i] 控制第 i 个逻辑列。
//   2. 包装层只做组合位重排，不增加寄存器；读写时序继承内部 sdp_ram。
//   3. B 口始终是同步读：若在上升沿 T 接受请求，数据在 T+PIPELINE_DEPTH 沿后可用。
//      PIPELINE_DEPTH=0 表示 T 沿后可用，不代表组合读；结构上仍有一个同步读级。
//   4. b_en=0 只停止接收新读请求，已进入流水线的返回仍可更新输出。
//   5. 无复位口和读有效输出。底层存储数组的仿真初值为 0，读寄存器/流水级未初始化。
//   6. 同沿同址且实际写入时，当前底层 RTL 读旧值；no_rw_check 属性不保证硬件碰撞结果。
//      本层不增加冲突旁路或仲裁，上层需遵守目标器件与系统的碰撞处理约定。
//   7. 编译顺序：先 core/common_components/ram/sdp_ram.sv，再本文件。
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

module sdp_ram_padded

    #(
        parameter ADDR_WIDTH = 10, // 存储字地址宽度；深度为 2**ADDR_WIDTH，补齐不改变它。
        parameter NUM_COL = 4, // 每字独立写入的逻辑列数，也是 a_wbe 的位数；应为正数。
        parameter COL_WIDTH = 16, // 每列对外可见的有效数据位数；列不一定是 8 位字节，应为正数。
        parameter PIPELINE_DEPTH = 1, // 底层同步读级之后的附加输出流水级数；应为非负数。
        parameter CASCADE_DEPTH = 4 // 原样传给底层 RAM 的 cascade_height 综合提示。
    )
    (
        input logic clk, // A/B 两口及底层输出流水线共用的上升沿时钟。
        // A 口：只写。选中的所有列写入同一个 a_addr，未选中的列保持。
        input logic a_en, // 写端口总使能；为 0 时即使 a_wbe 非零也不写入。
        input logic[NUM_COL-1:0] a_wbe, // 第 i 位控制 a_wdata[i*COL_WIDTH +: COL_WIDTH]。
        input logic[COL_WIDTH*NUM_COL-1:0] a_wdata, // 紧密排列的逻辑写数据，不包含内部填充位。
        input logic[ADDR_WIDTH-1:0] a_addr, // 写存储字地址；直接传给底层，不做地址换算。

        // B 口：只读。一次请求返回该存储字的所有逻辑列。
        input logic b_en, // 在上升沿为 1 时接受新的读地址。
        input logic[ADDR_WIDTH-1:0] b_addr, // 读存储字地址，与 A 口地址相互独立。
        output logic[COL_WIDTH*NUM_COL-1:0] b_rdata // 剔除各列填充位后的逻辑读数据。
    );

    localparam DATA_WIDTH = COL_WIDTH*NUM_COL; // 对外逻辑字宽，默认 4*16=64 位。

    // 分别计算“向上补齐到 8 的倍数”和“向上补齐到 9 的倍数”所需的位数。
    // 最外层的 % 保证已经对齐时补 0 位，而不是再补完整的 8/9 位。
    // 取补位较少的方案；补位数相同时由 <= 选择 8 的倍数方案。
    // 例如 COL_WIDTH=10：补到 16 位需 6 位，补到 18 位需 8 位，最终选择 16 位。
    //      COL_WIDTH=17：补到 24 位需 7 位，补到 18 位需 1 位，最终选择 18 位。
    localparam PAD_WIDTH8 = (8 - (COL_WIDTH % 8)) % 8; // 取值 0..7，每列补到 8 的倍数。
    localparam PAD_WIDTH9 = (9 - (COL_WIDTH % 9)) % 9; // 取值 0..8，每列补到 9 的倍数。
    localparam PAD_WIDTH = PAD_WIDTH8 <= PAD_WIDTH9 ? PAD_WIDTH8 : PAD_WIDTH9; // 每列实际补位数。
    localparam PADDED_WIDTH = COL_WIDTH + PAD_WIDTH; // 补齐后的单列位宽。
    localparam TOTAL_WIDTH = NUM_COL * PADDED_WIDTH; // 采用填充分支时，底层 RAM 的总字宽。

    // generate 条件在展开时决定结构，不是在运行时切换数据通路。
    // 已按 8/9 的倍数对齐时直接使用原列宽。
    // NUM_COL=1 时只有整字写使能，不需要为多个独立写列匹配粒度，因此也直接旁路填充。
    generate if (PAD_WIDTH == 0 || NUM_COL == 1) begin : gen_no_padding
        sdp_ram #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .NUM_COL(NUM_COL),
            .COL_WIDTH(COL_WIDTH),
            .PIPELINE_DEPTH(PIPELINE_DEPTH),
            .CASCADE_DEPTH(CASCADE_DEPTH)
        ) mem (.*); // 所有端口与包装层同名，.* 自动连接 clk、使能、地址和数据。
    end else begin : gen_padded
        logic[TOTAL_WIDTH-1:0] a_padded; // 插入列间空隙后的底层写数据。
        logic[TOTAL_WIDTH-1:0] b_padded; // 底层读数据，包含各列的有效位与填充位。

        // 第 i 个物理列：[高 PAD_WIDTH 位填充 | 低 COL_WIDTH 位有效数据]。
        // 第 0 列位于整个向量的最低位；补齐不会改变列号与 a_wbe[i] 的对应关系。
        always_comb begin
            // 先把全部内部位设为 X，再逐列覆盖有效位。
            // 留下的填充位是无效数据/综合 don't-care，不是补零，也不是复位操作。
            // 它们可能被写入底层 RAM，但读出时被丢弃，上层只应检查逻辑有效位。
            a_padded = 'x;
            for (int i = 0; i < NUM_COL; i++) begin
                // [起点 +: 宽度] 是向高位选取的固定宽度切片：有效位宽不变，列间距变大。
                // 例：COL_WIDTH=10、PADDED_WIDTH=16 时，第 1 列从 a_wdata[19:10]
                //     映射到 a_padded[25:16]，其上方 a_padded[31:26] 保持 X。
                a_padded[i*PADDED_WIDTH+:COL_WIDTH] = a_wdata[i*COL_WIDTH+:COL_WIDTH];
                // 读方向执行逆映射，移除各列高位填充，恢复紧密排列的外部数据。
                // 循环覆盖 b_rdata 的全部有效位，本层不引入锁存器或流水寄存器。
                b_rdata[i*COL_WIDTH+:COL_WIDTH] = b_padded[i*PADDED_WIDTH+:COL_WIDTH];
            end
        end

        // 底层仅将 COL_WIDTH 换成 PADDED_WIDTH；列数、地址深度和读流水深度保持一致。
        // 同一个 a_wbe[i] 因而控制补齐后的整列，有效数据与该列填充位一起写入。
        sdp_ram #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .NUM_COL(NUM_COL),
            .COL_WIDTH(PADDED_WIDTH),
            .PIPELINE_DEPTH(PIPELINE_DEPTH),
            .CASCADE_DEPTH(CASCADE_DEPTH)
        ) mem (
            .a_wdata(a_padded), // 写数据显式连接补齐后的内部向量。
            .b_rdata(b_padded), // 读数据先进入内部向量，再由上面的组合逻辑剔除填充位。
        .*); // 其余同名端口自动连接；显式数据连接优先，不会重复连接外部数据端口。
    end endgenerate

endmodule
