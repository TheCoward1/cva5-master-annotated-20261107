// ============================================================================
// 文件：core/common_components/ram/tdp_ram.sv
// 模块：tdp_ram（true dual-port RAM，真双端口 RAM）
// A、B 两个端口均可读写同一存储数组。端口各有独立的地址、使能和数据，共用 clk。
// 存储深度为 2**ADDR_WIDTH，每字 NUM_COL * COL_WIDTH 位，可按列写入。
//
// 端口操作在上升沿确定（en 和 wbe 为已知值）：
//   en=0                 空闲，保持该端口的同步读寄存器。
//   en=1 且 wbe 全零     读取整个存储字，更新该端口的同步读寄存器。
//   en=1 且 wbe 非零     写入选中的列，保持该端口的同步读寄存器。
// 第 T 个上升沿接受的读请求，在第 T+PIPELINE_DEPTH 个上升沿后从对应 rdata 可见。
// 模块没有读有效信号。上层应按 en && (~|wbe) 跟踪读请求及其返回时刻。
//
// 同沿并发访问遵循以下 RTL 仿真行为：
//   不同地址可独立访问。两口同时读同址时，各自采样该字的当前内容。
//   同址一读一写时，读口采样写入前的整字，写数据随后在 NBA 阶段更新。
//   同址双写且掩码不重叠时，各口更新自己选中的列。
//   同址同列双写时，两条时序过程都安排写入，该列没有规定的 A/B 优先级。
// 综合后的同址访问行为取决于器件和 RAM 推断规则。上层需遵守目标 RAM 的碰撞约定。
//
// 项目中 dcache_inv 的 tagbank 将每个 way 的 tag/valid 作为一列。
// 其中 B 口在复位初始化阶段逐地址写零，运行时可读取 snoop 对应的 tag 字。
// Xilinx 示例的 local_mem 用 A 口接指令接口、B 口接数据接口，并启用文件预加载。
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

module tdp_ram

    #(
        parameter ADDR_WIDTH = 10, // 存储字地址宽度，默认 1024 个字。
        parameter NUM_COL = 4, // 每个存储字中可独立写入的列数，也是两口写掩码的位数。
        parameter COL_WIDTH = 16, // 每列位宽，也是单个写使能位控制的数据位数。
        parameter PIPELINE_DEPTH = 1, // 两口同步读寄存器之后的附加流水级数。
        parameter CASCADE_DEPTH = 4, // 传给 cascade_height 的块 RAM 级联综合提示。
        parameter USE_PRELOAD = 0, // 非零时在仿真初始化阶段执行 $readmemh。
        parameter PRELOAD_FILE = "" // 十六进制预加载文件路径，启用预加载时使用。
    )
    (
        input logic clk, // 两个端口与全部读流水级共用的上升沿时钟。
        // A 口读写操作共用地址 a_addr。
        input logic a_en, // A 口总使能。
        input logic[NUM_COL-1:0] a_wbe, // A 口写掩码，第 i 位控制第 i 列。全零表示读。
        input logic[COL_WIDTH*NUM_COL-1:0] a_wdata, // 完整写数据字，只有选中的列会写入。
        input logic[ADDR_WIDTH-1:0] a_addr, // A 口读或写的存储字地址。
        output logic[COL_WIDTH*NUM_COL-1:0] a_rdata, // A 口的同步读数据，经可选流水线输出。

        // B 口与 A 口访问同一数组，使用自己的一组控制信号。
        input logic b_en, // B 口总使能。
        input logic[NUM_COL-1:0] b_wbe, // B 口写掩码，第 i 位控制第 i 列。全零表示读。
        input logic[COL_WIDTH*NUM_COL-1:0] b_wdata, // B 口完整写数据字。
        input logic[ADDR_WIDTH-1:0] b_addr, // B 口读或写的存储字地址。
        output logic[COL_WIDTH*NUM_COL-1:0] b_rdata // B 口的同步读数据，经可选流水线输出。
    );

    localparam DATA_WIDTH = COL_WIDTH*NUM_COL; // 完整存储字的位宽，默认 64 位。

    // 综合属性用于提示块 RAM 推断、级联高度与读写冲突处理。
    // 属性的具体效果由目标工具和器件决定。no_rw_check 不改变下面的 RTL 仿真行为。
    //给vivado提示 分为4级，cascade_height=4   不使用读写同时发生的检查 综合为Block RAM（BRAM）
    (* cascade_height = CASCADE_DEPTH, ramstyle = "no_rw_check", ram_style = "block" *)
    logic[DATA_WIDTH-1:0] mem[(1<<ADDR_WIDTH)-1:0]; // A、B 共用的存储数组，索引为字地址。

    // 启用时从地址 0 开始装入十六进制存储字。未加载或写入的位置在四态仿真中为 X。
    // 模块没有复位端口。预加载只初始化 mem，读寄存器和流水寄存器仍未初始化。
    //预加载文件到BRAM中，仿真时使用$readmemh函数读取文件内容到mem数组中
    initial begin
        if (USE_PRELOAD)
            $readmemh(PRELOAD_FILE, mem, 0);
    end

    // A 口的同步读寄存器仅在 a_en=1 且 a_wbe 全零时采样存储字。
    logic[DATA_WIDTH-1:0] a_ram_output;
    //always_ff @(posedge clk) begin
    always @(posedge clk) begin
        if (a_en) begin
            // 循环描述同一个上升沿的并行列写。未选中的列保持原值。
            // [i*COL_WIDTH +: COL_WIDTH] 从第 i 列的最低位起向高位选取该列。
            for (int i = 0; i < NUM_COL; i++) begin
                if (a_wbe[i])
                    mem[a_addr][i*COL_WIDTH +: COL_WIDTH] <= a_wdata[i*COL_WIDTH +: COL_WIDTH];
            end
            if (~|a_wbe) // 归约或取反，仅全零掩码触发一次新的同步读。
                a_ram_output <= mem[a_addr];
        end
    end

    // A 口可选输出流水线。各级使用 NBA 更新前的使能和数据，读结果逐拍前推。
    // 流水使能延迟的是 a_en，读和写都会进入使能链。
    // A 口写入时 a_ram_output 保留原值，对应流水槽可传播该旧值。读有效由上层另行跟踪。
    generate if (PIPELINE_DEPTH > 0) begin : gen_a_pipeline
        logic[DATA_WIDTH-1:0] a_data_pipeline[PIPELINE_DEPTH-1:0]; // 各附加级的数据寄存器。
        logic[PIPELINE_DEPTH-1:0] a_en_pipeline; // 各级对应的延迟端口使能。

        always_ff @(posedge clk) begin
            for (int i = 0; i < PIPELINE_DEPTH; i++) begin
                a_en_pipeline[i] <= i == 0 ? a_en : a_en_pipeline[i-1];
                if (a_en_pipeline[i]) // 取本级更新前的使能，和更新前的源数据对齐。
                    a_data_pipeline[i] <= i == 0 ? a_ram_output : a_data_pipeline[i-1];
            end
        end
        // 即使当前 a_en=0，已进入流水线的读数据也可在到期时更新输出。
        assign a_rdata = a_data_pipeline[PIPELINE_DEPTH-1];
    end
    else begin : gen_a_transparent_output
        assign a_rdata = a_ram_output; // 省去附加流水级，读请求仍在上升沿采样。
    end endgenerate


    // B 口与 A 口对称。两段时序过程独立调度，没有内建的端口仲裁。
    logic[DATA_WIDTH-1:0] b_ram_output;
    //always_ff @(posedge clk) begin
    always @(posedge clk) begin
        if (b_en) begin
            for (int i = 0; i < NUM_COL; i++) begin
                if (b_wbe[i])
                    mem[b_addr][i*COL_WIDTH +: COL_WIDTH] <= b_wdata[i*COL_WIDTH +: COL_WIDTH];
            end
            if (~|b_wbe) // 有效读请求采样整个存储字，写入周期保持读寄存器。
                b_ram_output <= mem[b_addr];
        end
    end

    // B 口维护自己的数据和端口使能流水线，延迟与 A 口相同。
    generate if (PIPELINE_DEPTH > 0) begin : gen_b_pipeline
        logic[DATA_WIDTH-1:0] b_data_pipeline[PIPELINE_DEPTH-1:0];
        logic[PIPELINE_DEPTH-1:0] b_en_pipeline;

        always_ff @(posedge clk) begin
            for (int i = 0; i < PIPELINE_DEPTH; i++) begin
                b_en_pipeline[i] <= i == 0 ? b_en : b_en_pipeline[i-1];
                if (b_en_pipeline[i])
                    b_data_pipeline[i] <= i == 0 ? b_ram_output : b_data_pipeline[i-1];
            end
        end
        assign b_rdata = b_data_pipeline[PIPELINE_DEPTH-1];
    end
    else begin : gen_b_transparent_output
        assign b_rdata = b_ram_output;
    end endgenerate

endmodule
