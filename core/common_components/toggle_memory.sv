// ============================================================================
// 文件：core/common_components/toggle_memory.sv
// 类型：module
// 名称：toggle_memory
// 作用：实现单 bit 宽、可翻转（toggle）的多读端口存储器。
// 行为：每个时钟上升沿对 toggle_id 指向的单元执行读-改-写；
//       toggle=1 时将旧值取反，toggle=0 时写回旧值（保持）。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2020 Eric Matthews,  Lesley Shannon
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

module toggle_memory // 定义 toggle_memory 模块。

    # (
        parameter DEPTH = 8, // 存储深度：有效地址范围是 0 ~ DEPTH-1。
        parameter NUM_READ_PORTS = 2 // 外部用户读端口数量；内部还会额外使用 1 个读端口。
    )
    (
        input logic clk, // 时钟输入；写操作在上升沿生效。

        input logic toggle, // 翻转使能：1 表示翻转目标位，0 表示保持原值。
        input logic [$clog2(DEPTH)-1:0] toggle_id, // 读-改-写地址，同时也是本次写的目标地址。

        input logic [$clog2(DEPTH)-1:0] read_id [NUM_READ_PORTS], // 各用户读端口的读地址。
        output logic read_data [NUM_READ_PORTS] // 各用户读端口的读出数据。
    );
    ////////////////////////////////////////////////////
    //Implementation
    // 端口0专用于读取待写单元的旧值，端口1..N对应用户外部的读端口。
    logic new_ram_data; // 写回值：new_ram_data = 旧值 XOR toggle。
    logic _read_data [NUM_READ_PORTS+1]; // 端口0为写回反馈数据，其余为用户读数据。
    logic [$clog2(DEPTH)-1:0] _read_id [NUM_READ_PORTS+1]; // 内部统一后的读地址数组。

    assign _read_id[0] = toggle_id; // 让内部读端口0读取当前待翻转地址的旧值。
    assign _read_id[1:NUM_READ_PORTS] = read_id; // 将外部读地址连接到内部读端口1..N。

    // toggle=0 时写回旧值，存储内容保持不变；
    // toggle=1 时写回旧值的反相，实现按地址翻转。
    // 注意：toggle 通常应为单周期脉冲；若连续多拍保持 1，目标位会在每个上升沿反复翻转。
    assign new_ram_data = toggle ^ _read_data[0];

    // 单写端口、多读端口 LUTRAM：
    // - 写地址由 toggle_id 给出；
    // - 端口0用于读回旧值，形成读-改-写数据通路；
    // - 端口1..N用于对外提供多路读数据；
    // - 读端口为组合读，写操作在时钟上升沿生效。
    lutram_1w_mr #(
        .DATA_TYPE(logic),
        .DEPTH(DEPTH),
        .NUM_READ_PORTS(NUM_READ_PORTS+1)
    )
    write_port (
        .clk(clk),
        .waddr(toggle_id), // 写地址：本次需要翻转或保持的存储单元。
        .raddr(_read_id), // 读地址：端口0取旧值，其余端口输出用户数据。
        .ram_write(1'b1), // 每个时钟都执行写回；toggle=0 时写回旧值。
        .new_ram_data(new_ram_data), // 下一拍写入的数据。
        .ram_data_out(_read_data) // 存储阵列当前读出的数据。
    );

    assign read_data = _read_data[1:NUM_READ_PORTS]; // 去掉内部端口0，只把用户读端口输出到外部。

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions
    // 当前模块暂未添加 SVA；翻转/保持语义由上层 toggle_memory_set 和仿真检查验证。

endmodule // 结束模块定义。