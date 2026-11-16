// ============================================================================
// 文件：core/common_components/ram/sdp_ram.sv
// 类型：module
// 名称：sdp_ram
// 作用：实现简单双端口 RAM 行为模型，供流水线和缓存使用。
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

module sdp_ram // 定义 sdp_ram 模块。

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

    (* cascade_height = CASCADE_DEPTH, ramstyle = "no_rw_check", ram_style = "block" *) //Higher depths use less resources but are slower
    logic[DATA_WIDTH-1:0] mem[(1<<ADDR_WIDTH)-1:0]; // 声明信号、变量或生成变量。

    initial mem = '{default: '0}; // 开始初始化块，用于仿真初始化和激励。

    //A write
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        for (int i = 0; i < NUM_COL; i++) begin // 执行循环或遍历。
            if (a_en & a_wbe[i]) // 执行条件判断，满足条件时进入对应分支。
                mem[a_addr][i*COL_WIDTH +: COL_WIDTH] <= a_wdata[i*COL_WIDTH +: COL_WIDTH];
        end // 结束语句块。
    end // 结束语句块。


    //B read
    logic[DATA_WIDTH-1:0] b_ram_output; // 声明信号、变量或生成变量。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (b_en) // 执行条件判断，满足条件时进入对应分支。
            b_ram_output <= mem[b_addr];
    end // 结束语句块。

    //B pipeline
    generate if (PIPELINE_DEPTH > 0) begin : gen_b_pipeline // 开始生成块，在编译期展开硬件结构。
        logic[DATA_WIDTH-1:0] b_data_pipeline[PIPELINE_DEPTH-1:0]; // 声明信号、变量或生成变量。
        logic[PIPELINE_DEPTH-1:0] b_en_pipeline; // 声明信号、变量或生成变量。

        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            for (int i = 0; i < PIPELINE_DEPTH; i++) begin // 执行循环或遍历。
                b_en_pipeline[i] <= i == 0 ? b_en : b_en_pipeline[i-1];
                if (b_en_pipeline[i]) // 执行条件判断，满足条件时进入对应分支。
                    b_data_pipeline[i] <= i == 0 ? b_ram_output : b_data_pipeline[i-1];
            end // 结束语句块。
        end // 结束语句块。
        assign b_rdata = b_data_pipeline[PIPELINE_DEPTH-1]; // 执行连续赋值，把组合逻辑连接到目标信号。
    end // 结束语句块。
    else begin : gen_b_transparent_output // 执行否则分支。
        assign b_rdata = b_ram_output; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

endmodule // 结束模块定义。
