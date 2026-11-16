// ============================================================================
// 文件：core/common_components/round_robin.sv
// 类型：module
// 名称：round_robin
// 作用：实现轮询仲裁（round-robin arbitration），在多个请求端口之间轮流授权，
//       避免某个端口因为固定优先级而长期得不到服务。
// 行为：state 保存最近一次被授权的端口；每次 grant 有效后，grantee 写回 state，
//       下一轮从该端口的下一个位置继续扫描，从而形成环形轮转。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017 Eric Matthews, Lesley Shannon
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

module round_robin // 定义多请求轮询仲裁器。

    #(
        parameter int unsigned NUM_PORTS = 2 // 配置参数：请求端口数量，默认为 2。
    ) (
        input logic clk, // 时钟输入：state 在上升沿更新。
        input logic rst, // 同步高有效复位：复位时清除轮转位置。
        input logic[NUM_PORTS-1:0] requests, // 请求向量：每个 bit 对应一个请求端口，允许多个 bit 同时有效。
        input logic grant, // 授权握手输入：1 表示当前 grantee 已被接受，可以推进轮转位置。
        output logic[(NUM_PORTS == 1 ? 1 : $clog2(NUM_PORTS))-1:0] grantee // 授权结果：输出被选中的端口索引；单端口时固定为 1 bit。
    );

    localparam PORT_W = $clog2(NUM_PORTS); // 计算保存端口索引所需的内部位宽，例如 4 个端口需要 2 bit。

    generate if (NUM_PORTS == 1) begin : gen_no_arb // 只有一个端口时，不需要仲裁逻辑。
        assign grantee = '0; // 唯一端口索引固定为 0。
    end else begin : gen_arb // 多个端口时，生成轮询仲裁逻辑。
        logic[PORT_W-1:0] state; // 当前轮转位置；记录上一次被授权的端口。
        logic[PORT_W-1:0] muxes [NUM_PORTS-1:0]; // 预计算表：muxes[i] 表示假设当前 state=i 时的授权结果。

        // state 是上一轮授权端口，因此本轮它拥有最低优先级；只有 grant 有效时才推进。
        always_ff @(posedge clk) begin // 同步时序逻辑：每个时钟上升沿执行。
            if (rst) // 复位优先，忽略 grant 和 requests。
                state <= 0; // 把轮转起点恢复为端口 0。
            else if (grant) // 当前授权已经被上游接收。
                state <= grantee; // 将本次授权端口保存为下一次轮转的起点。
        end // 结束时序逻辑。

        // 例：state=0 时，NUM_PORTS-1 号端口的优先级最高，随后按环形顺序轮转。
        always_comb begin // 组合逻辑：根据 requests 和 state 计算所有可能的授权结果。
            for (int i = 0; i < NUM_PORTS; i++) begin // i 表示假设当前轮转位置为 i。
                muxes[i] = PORT_W'(i); // 默认选择当前索引；当没有请求命中时保持最保守的结果。
                for (int j = 0; j < NUM_PORTS; j++) begin // j 表示从 i 开始沿环向后扫描的偏移。
                    if (requests[(i + j) % NUM_PORTS]) // 检查环形索引 (i+j) 对应的请求位是否为 1。
                        muxes[i] = PORT_W'((i + j) % NUM_PORTS); // 记录命中的端口；后续命中会覆盖前面的结果。
                end // 结束从 i 开始的所有环形扫描。
            end // 结束所有可能 state 的授权结果预计算。
        end // 结束组合逻辑。

        // 扫描时 i 最先检查、优先级最低；最后命中的端口优先级最高，相当于从 i-1 开始反向轮询。
        assign grantee = muxes[state]; // 用当前 state 从预计算表中选择最终授权端口。
    end endgenerate // 结束单端口/多端口生成结构。

endmodule // 结束 round_robin 模块定义。
