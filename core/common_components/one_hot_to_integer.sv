// ============================================================================
// 文件：core/common_components/one_hot_to_integer.sv
// 类型：module
// 名称：one_hot_to_integer
// 作用：把一个 one-hot 位向量转换成对应置位位的整数索引。
// 示例（C_WIDTH=4）：
//   one_hot = 4'b0001 -> int_out = 0
//   one_hot = 4'b0010 -> int_out = 1
//   one_hot = 4'b0100 -> int_out = 2
//   one_hot = 4'b1000 -> int_out = 3
// 约束：输入必须满足 one-hot 语义；如果多个 bit 同时为 1，输出是多个索引按位
//       OR 的结果，没有“最低有效位优先”的含义。零输入输出 0。
// 实现：纯组合逻辑；因为每个合法输入中只有一个 bit 为 1，所以可以直接把该 bit
//       对应的索引 OR 到输出上。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017-2019 Eric Matthews,  Lesley Shannon
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

// 该模块要求输入始终是 one-hot；也就是说，最多只有一位为 1。
// 由于实现使用 OR 把所有可能置位位的索引组合起来，如果出现多位同时为 1，
// 输出会是多个索引的按位 OR，而不是一个合法的单值索引。
module one_hot_to_integer
    #(
        parameter C_WIDTH = 40 // 输入位宽；默认值 40 是 CVA5 中常见的配置
    )
    (
        input logic [C_WIDTH-1:0] one_hot, // 输入 one-hot 向量
        // 输出索引的位宽：
        // C_WIDTH=1 时输出 1 bit [0:0]；
        // C_WIDTH>1 时需要能表示 0..C_WIDTH-1，因此使用 clog2(C_WIDTH) bit。
        output logic [(C_WIDTH == 1) ? 0 : ($clog2(C_WIDTH)-1) : 0] int_out
    );

    ////////////////////////////////////////////////////
    // Implementation
    generate if (C_WIDTH == 1) begin : gen_width_one
        // 宽度为 1 时只有输入 0 或 1，索引固定为 0。
        assign int_out = 0;
    end else begin : gen_width_two_plus
        // C_WIDTH 大于 1 时，使用组合逻辑计算索引。
        // 由于输入是 one-hot，正常情况下只有一个 one_hot[i] 为 1，
        // 因此下面的 OR 只会把对应的 i 写入 int_out。
        always_comb begin
            int_out = 0; // 零输入和未选中位的默认结果

            // foreach 会遍历 one_hot 的每个 bit；i 是当前 bit 的整数索引。
            foreach(one_hot[i])
                // 如果第 i 位为 1，就把索引 i 转换成输出位宽后 OR 到结果。
                // 这里使用 $clog2(C_WIDTH)'(i) 做位宽转换，避免隐式扩展产生警告。
                int_out |= one_hot[i] ? $clog2(C_WIDTH)'(i) : 0;
        end
    end
    endgenerate

    ////////////////////////////////////////////////////
    // Assertions
    // 下面这段断言被注释掉了，因为本模块没有 clk/rst 端口。
    // 如果以后在带时钟的验证环境中使用，可以恢复用于检查“最多一位为 1”。
    // always_ff @ (posedge clk) begin
    //    assert (rst || (~rst && $onehot0(one_hot))) else $error("One-hot signal has multiple bits set!");
    //end

endmodule
