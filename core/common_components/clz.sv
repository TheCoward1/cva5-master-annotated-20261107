// ============================================================================
// 文件：core/common_components/clz.sv
// 类型：module
// 名称：clz
// 作用：统计输入向量从最高位开始的连续 0 个数，并输出全零标志。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
//
// 功能定义：
//   zero = 1：输入全为 0；此时 clz 不作为有效的前导零计数使用。
//   zero = 0：clz 表示从 clz_input[WIDTH-1] 开始连续为 0 的位数。
//
// 示例（WIDTH=8）：
//   clz_input = 8'b0001_0100 -> zero=0, clz=3
//   clz_input = 8'b0000_0000 -> zero=1, clz 无效
//
// 实现方式：
//   使用递归二分树，将输入补齐到 2 的幂后分成高低两半；
//   若高半区全为 0，则结果最高位为 1，并继续从低半区取得剩余位数。
// ============================================================================

/*
 * Copyright © 2023 Chris Keilbart, Lesley Shannon
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

module clz // 前导零计数器：Count Leading Zeros。
    #(
        parameter WIDTH = 32 // 输入位宽；正常使用时应不小于 2。
    )
    (
        input logic[WIDTH-1:0] clz_input, // 待统计的输入向量。
        output logic[$clog2(WIDTH)-1:0] clz, // 前导零个数；zero=1 时无效。
        output logic zero // 输入是否全为 0。
    );

    // 算法参考：Perri et al., "Design of Leading Zero Counters on FPGAs", 2022。
    // 该结构针对 6 输入 LUT 的 FPGA 实现进行了优化。

    // 也可以完全展开写成非递归结构，但会显著降低可读性，
    // 尤其是 clz 结果各 bit 的组合关系会很难理解。

    localparam TREE_WIDTH = 2**$clog2(WIDTH); // 大于等于 WIDTH 的最小 2 的幂。
    localparam TREE_CLZ_WIDTH = $clog2(WIDTH)-1; // 递归树内部 clz 结果位宽。
    localparam HALF_TREE_WIDTH = TREE_WIDTH/2; // 每一半的宽度。
    localparam WIDTH_DIFFERENCE = TREE_WIDTH - WIDTH; // 补齐到 TREE_WIDTH 所需位数。

    generate
        if (WIDTH == 2) begin : gen_base_case
            // 最小规模的基础情况：WIDTH=2。
            // 只有输入 2'b01 的前导零个数为 1；其余非零输入的 clz 为 0。
            assign zero = ~(clz_input[1] | clz_input[0]);
            assign clz[0] = ~clz_input[1] & clz_input[0];
        end
        else begin : gen_recursive
            logic[TREE_WIDTH-1:0] padded_input;

            // 非 2 的幂位宽时，在最低位一侧补 0。
            // 这样不会引入新的前导零，也不会改变原有的 clz 结果。
            if (WIDTH_DIFFERENCE != 0)
                assign padded_input = {clz_input, {WIDTH_DIFFERENCE{1'b0}}};
            else
                assign padded_input = clz_input;

            logic[TREE_CLZ_WIDTH-1:0] upper_clz; // 高半区的前导零结果。
            logic[TREE_CLZ_WIDTH-1:0] lower_clz; // 低半区的前导零结果。
            logic upper_zero; // 高半区是否全为 0。
            logic lower_zero; // 低半区是否全为 0。

            // 只有高低半区都全为 0，整个输入才全为 0。
            assign zero = upper_zero & lower_zero;

            // 高半区全为零时，前导零个数一定落在低半区，
            // 因此 clz 的最高位直接等于 upper_zero。
            assign clz[$clog2(WIDTH)-1] = upper_zero;

            // 高半区全为零时使用低半区结果，否则使用高半区结果。
            clz #(.WIDTH(HALF_TREE_WIDTH)) upper_tree (
                .clz_input(padded_input[TREE_WIDTH-1:HALF_TREE_WIDTH]),
                .clz(upper_clz),
                .zero(upper_zero)
            );

            clz #(.WIDTH(HALF_TREE_WIDTH)) lower_tree (
                .clz_input(padded_input[HALF_TREE_WIDTH-1:0]),
                .clz(lower_clz),
                .zero(lower_zero)
            );

            // 将上下两个子树的 clz 结果合并成当前层的结果：
            // upper_zero=0 时选择 upper_clz，否则选择 lower_clz。
            for (genvar i = 0; i < TREE_CLZ_WIDTH; i++)
                assign clz[i] = (~upper_zero & upper_clz[i]) | (upper_zero & lower_clz[i]);
        end
    endgenerate

endmodule
