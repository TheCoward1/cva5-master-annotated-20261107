// ============================================================================
// 文件：core/common_components/ram/lutram_1w_mr.sv
// 类型：module
// 名称：lutram_1w_mr
// 作用：实现单写端口、多读端口的 LUTRAM 存储模型。
// 行为：写操作在时钟上升沿同步完成；各读端口由组合逻辑读出。
// 实现：根据 FPGA_VENDOR 选择 Xilinx 或 Intel 的 LUTRAM 推断方式。
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

module lutram_1w_mr // 定义 lutram_1w_mr 模块。

    import cva5_config::*; // 导入 FPGA_VENDOR 等配置；XILINX=0，INTEL=1。

    #(
        parameter type DATA_TYPE = logic, // 存储字的数据类型；$bits(DATA_TYPE) 决定每个存储字的位宽。
        parameter DEPTH = 32, // 存储深度；有效地址范围是 0 ~ DEPTH-1。
        parameter NUM_READ_PORTS = 2 // 读端口数量；所有读端口共享同一个写端口。
    )
    (
        input logic clk, // 时钟输入；写操作在上升沿生效。

        input logic[$clog2(DEPTH)-1:0] waddr, // 写地址。
        input logic[$clog2(DEPTH)-1:0] raddr [NUM_READ_PORTS], // 各读端口的读地址。

        input logic ram_write, // 写使能；为 1 时在时钟上升沿写入 new_ram_data。
        input DATA_TYPE new_ram_data, // 待写入的数据。
        output DATA_TYPE ram_data_out [NUM_READ_PORTS] // 各读端口的读出数据。
    );

// Xilinx：利用其较丰富的 LUTRAM 资源，尽量把整个数组推断成一个多读端口 LUTRAM。
// Intel：用多个单写单读 LUTRAM 副本组合出多读端口。
// 两种实现对外行为相同：一个同步写端口，多个组合读端口。
generate if (FPGA_VENDOR == XILINX) begin : xilinx_gen // Xilinx 直接多读实现。

    // 一个共享存储阵列：所有读端口都从同一个 ram 读取。
    logic [$bits(DATA_TYPE)-1:0] ram [DEPTH-1:0];

    // 仿真初始化：上电/仿真开始时所有存储字为 0。
    // 注意：这不是同步复位；硬件上是否生效取决于目标器件和综合工具的初始化能力。
    initial ram = '{default: 0};

    // 单写端口：写使能有效时，在时钟上升沿写入指定地址。
    //lways_ff @ (posedge clk) begin
    always @ (posedge clk) begin
        if (ram_write)
            ram[waddr] <= new_ram_data;
    end

    // 多读端口：每个读地址都组合寻址同一个存储阵列，因此是异步/组合读。
    always_comb begin
        for (int i = 0; i < NUM_READ_PORTS; i++) begin
            ram_data_out[i] = ram[raddr[i]];
        end
    end

end // 结束 Xilinx 实现。
else if (FPGA_VENDOR == INTEL) begin : intel_gen // Intel 由多个单读 RAM 组合实现。

    // 每个读端口实例化一个独立的 lutram_1w_1r。
    // 所有副本接收相同的写地址、写使能和数据，因此内容始终同步；
    // 各副本分别使用 raddr[i] 读取，从而形成多读端口。
    for (genvar i = 0; i < NUM_READ_PORTS; i++) begin : lutrams
        lutram_1w_1r #(.DATA_TYPE(DATA_TYPE), .DEPTH(DEPTH))
        write_port (
            .clk(clk), // 所有副本共享时钟。
            .waddr(waddr), // 写地址广播到所有副本。
            .raddr(raddr[i]), // 第 i 个读端口使用自己的读地址。
            .ram_write(ram_write), // 写使能广播到所有副本。
            .new_ram_data(new_ram_data), // 写数据广播到所有副本。
            .ram_data_out(ram_data_out[i]) // 第 i 个读端口输出。
        );
    end

end // 结束 Intel 实现。
endgenerate // 结束按 FPGA_VENDOR 选择的生成结构。

endmodule // 结束模块定义。