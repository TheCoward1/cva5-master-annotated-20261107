// ============================================================================
// 文件：core/common_components/ram/sdp_ram.sv
// 模块：sdp_ram（simple dual-port RAM，简单双端口 RAM）
// 作用：实现共用 clk 的 A 口写、B 口读存储器，支持按列写入和可配置读输出流水线。
// 容量：2**ADDR_WIDTH 个存储字，每字 NUM_COL * COL_WIDTH 位。
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致；编码为 UTF-8。
//
// 接口约定：
//   1. A/B 两口地址独立，可以在同一时钟沿分别进行一次写入和一次读取。
//   2. 写入条件为 a_en && a_wbe[i]；B 口仅在 b_en 为 1 时接受新的读地址。
//   3. B 口始终是同步读；PIPELINE_DEPTH 只控制同步读寄存器之后的附加流水级。
//   4. 模块没有复位和读数据有效输出，上层需按读请求及配置的延迟判断数据有效性。
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

module sdp_ram

    #(
        parameter ADDR_WIDTH = 10, // 存储字地址宽度；默认可寻址 1024 个存储字。
        parameter NUM_COL = 4, // 每个存储字中可独立写入的列数，对应 a_wbe 的位数。
        parameter COL_WIDTH = 16, // 每列位宽；写使能粒度由此决定，不一定是 8 位字节。
        parameter PIPELINE_DEPTH = 1, // 同步读之后附加的输出流水级数；0 表示不添加。
        parameter CASCADE_DEPTH = 4 // 传给 cascade_height 的 RAM 级联高度综合提示。
    )
    (
        input logic clk, // 两个端口及输出流水线共用的时钟，均在上升沿更新。
        // A 口：只写。a_addr 为存储字地址，所有被使能的列写入同一个存储字。
        input logic a_en, // 写端口总使能；为 0 时无论 a_wbe 如何，均不修改存储器。
        input logic[NUM_COL-1:0] a_wbe, // 按列写使能；第 i 位控制第 i 个 COL_WIDTH 位切片。
        input logic[COL_WIDTH*NUM_COL-1:0] a_wdata, // 完整写数据字，只有选中的列被采纳。
        input logic[ADDR_WIDTH-1:0] a_addr, // 写地址，范围为 0 到 2**ADDR_WIDTH - 1。

        // B 口：只读。每次有效请求读取 b_addr 对应的整个存储字。
        input logic b_en, // 同步读使能；为 0 时不接受新读请求，已有流水数据仍可前进。
        input logic[ADDR_WIDTH-1:0] b_addr, // 在 b_en 为 1 的时钟上升沿采样的读地址。
        output logic[COL_WIDTH*NUM_COL-1:0] b_rdata // 同步读结果，经可选流水线后输出。
    );

    localparam DATA_WIDTH = COL_WIDTH*NUM_COL; // 完整存储字位宽，默认 4 * 16 = 64 位。

    // 综合属性：ram_style="block" 提示使用块 RAM；cascade_height 指定级联高度。
    // 较大的级联高度通常有利于资源利用，但可能增加访问路径延迟，需结合实现结果取舍。
    // ramstyle="no_rw_check" 允许工具不保证同址读写时的读出值，不在此添加冲突旁路。
    // 属性是否生效取决于综合工具和目标器件，不改变下面的 RTL 仿真语义。
    (* cascade_height = CASCADE_DEPTH, ramstyle = "no_rw_check", ram_style = "block" *)
    logic[DATA_WIDTH-1:0] mem[(1<<ADDR_WIDTH)-1:0]; // 深度为 2**ADDR_WIDTH 的存储字数组。

    // 仿真开始时将全部存储字置零；这不是运行时复位。
    // 硬件是否保留此初值取决于器件和工具；下方读寄存器及流水寄存器没有初始化。
    initial mem = '{default: '0};

    // A 口同步写：循环描述并行的列写使能，而不是分多个周期逐列写入。
    always @(posedge clk) begin
    //always_ff @(posedge clk) begin
        for (int i = 0; i < NUM_COL; i++) begin
            if (a_en & a_wbe[i]) // 总使能与该列使能均有效，才更新该列，其余列保持原值。
                // [i*COL_WIDTH +: COL_WIDTH] 从第 i 列最低位起向高位选取 COL_WIDTH 位。
                // 例如默认配置的 i=1 对应 [31:16]，写数据与存储字使用相同的列位置。
                mem[a_addr][i*COL_WIDTH +: COL_WIDTH] <= a_wdata[i*COL_WIDTH +: COL_WIDTH];
        end
    end


    // B 口同步读：先用一个寄存器锁存 RAM 输出；b_en 为 0 时该寄存器保持原值。
    // A/B 同沿访问同一地址且发生写入时，非阻塞赋值使此 RTL 仿真读取写入前的值。
    // 由于 no_rw_check，综合后的同址读写结果不能据此保证；上层应避开冲突或自行处理。
    logic[DATA_WIDTH-1:0] b_ram_output;
    always_ff @(posedge clk) begin
        if (b_en)
            b_ram_output <= mem[b_addr];
    end

    // B 口可选输出流水线：结构上共包含 1 个同步读级和 PIPELINE_DEPTH 个附加级。
    // 若在上升沿 T 接受读请求，b_ram_output 在 T 沿后更新：
    //   PIPELINE_DEPTH=0：b_rdata 在 T 沿后更新，依然是同步读，不是组合读。
    //   PIPELINE_DEPTH=1：b_rdata 在下一个上升沿 T+1 后更新；更深配置依此类推。
    // 读请求可每拍连续进入；无新请求时，已经进入流水线的数据仍按原定延迟输出。
    generate if (PIPELINE_DEPTH > 0) begin : gen_b_pipeline
        logic[DATA_WIDTH-1:0] b_data_pipeline[PIPELINE_DEPTH-1:0]; // 各附加级的数据寄存器。
        logic[PIPELINE_DEPTH-1:0] b_en_pipeline; // 将读请求逐拍延迟，用作各数据级的更新使能。

        always_ff @(posedge clk) begin
            for (int i = 0; i < PIPELINE_DEPTH; i++) begin
                // 使能每拍向后移动：第 0 级接收 b_en，其余级接收前一级使能。
                b_en_pipeline[i] <= i == 0 ? b_en : b_en_pipeline[i-1];
                // 非阻塞赋值使此处读取更新前的使能，恰好对应此前已锁存的数据。
                // 因而第 0 级在读请求的下一拍采纳 b_ram_output，各后续级再逐拍传递。
                if (b_en_pipeline[i])
                    b_data_pipeline[i] <= i == 0 ? b_ram_output : b_data_pipeline[i-1];
            end
        end
        // 最末级作为输出；该级无对应有效读数据到达时保持原值。
        // 因无复位或初始化，上电仿真初期可能为 X，直到有效读数据传到此级。
        assign b_rdata = b_data_pipeline[PIPELINE_DEPTH-1];
    end
    else begin : gen_b_transparent_output
        // 不增加附加流水级，直接连接同步读寄存器；仍需 b_en 和时钟沿才能更新。
        assign b_rdata = b_ram_output;
    end endgenerate

endmodule
