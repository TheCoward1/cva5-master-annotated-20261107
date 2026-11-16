// ============================================================================
// 文件：core/common_components/toggle_memory_set.sv
// 类型：module
// 名称：toggle_memory_set
// 作用：实现带置位行为的可切换存储器模型。
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

module toggle_memory_set // 定义 toggle_memory_set 模块。

    # (
        parameter DEPTH = 64, // 声明可配置参数。
        parameter NUM_WRITE_PORTS = 3, // 声明可配置参数。
        parameter NUM_READ_PORTS = 2 // 声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        input logic init_clear, // 声明输入端口。

        input logic toggle [NUM_WRITE_PORTS], // 声明输入端口。
        input logic [$clog2(DEPTH)-1:0] toggle_addr [NUM_WRITE_PORTS], // 声明输入端口。

        input logic [$clog2(DEPTH)-1:0] read_addr [NUM_READ_PORTS], // 声明输入端口。
        output logic in_use [NUM_READ_PORTS] // 声明输出端口。
    );
    ////////////////////////////////////////////////////
    //Implementation
    logic [$clog2(DEPTH)-1:0] _toggle_addr [NUM_WRITE_PORTS+1]; // 声明信号、变量或生成变量。
    logic _toggle [NUM_WRITE_PORTS+1]; // 声明信号、变量或生成变量。
    logic [$clog2(DEPTH)-1:0] _read_addr [NUM_READ_PORTS+1]; // 声明信号、变量或生成变量。
    logic read_data [NUM_WRITE_PORTS+1][NUM_READ_PORTS+1]; // 声明信号、变量或生成变量。
    logic _in_use [NUM_READ_PORTS+1]; // 声明信号、变量或生成变量。
    logic [$clog2(DEPTH)-1:0] clear_index; // 声明信号、变量或生成变量。

    //counter for indexing through memories for post-reset clearing/initialization
    lfsr #(.WIDTH($clog2(DEPTH)), .NEEDS_RESET(0))
    lfsr_counter (
        .clk (clk), .rst (1'b0),
        .en(init_clear),
        .value(clear_index)
    );
    
    //muxing of read and write ports to support post-reset clearing/initialization
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        _toggle_addr[0:NUM_WRITE_PORTS-1] = toggle_addr;
        _toggle[0:NUM_WRITE_PORTS-1] = toggle;
        _read_addr[0:NUM_READ_PORTS-1] = read_addr;
        
        _toggle_addr[NUM_WRITE_PORTS] = clear_index;
        _toggle[NUM_WRITE_PORTS] = init_clear & _in_use[NUM_READ_PORTS];
        _read_addr[NUM_READ_PORTS] = clear_index;
    end // 结束语句块。


    //Instantiation of NUM_READ_PORTS*NUM_WRITE_PORTS dual-ported single-bit wide toggle memories
    genvar i, j; // 声明信号、变量或生成变量。
    generate // 开始生成块，在编译期展开硬件结构。
        for (j = 0; j < NUM_WRITE_PORTS+1; j++) begin : write_port_gen // 执行循环或遍历。
            toggle_memory #(.DEPTH(DEPTH), .NUM_READ_PORTS(NUM_READ_PORTS+1))
            mem (
                .clk (clk),
                .toggle(_toggle[j]),
                .toggle_id(_toggle_addr[j]),
                .read_id(_read_addr),
                .read_data(read_data[j])
            );
        end // 结束语句块。
    endgenerate // 结束生成块。

    //In-use determination.  XOR of all write blocks for each read address
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        _in_use = '{default: 0};
        for (int i = 0;  i < NUM_READ_PORTS+1; i++) begin // 执行循环或遍历。
            for (int j = 0; j < NUM_WRITE_PORTS+1; j++) begin // 执行循环或遍历。
                _in_use[i] ^= read_data[j][i];
            end // 结束语句块。
        end // 结束语句块。
        for (int i = 0;  i < NUM_READ_PORTS; i++) begin // 执行循环或遍历。
            in_use[i] = _in_use[i];
        end // 结束语句块。
    end // 结束语句块。
    
    

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions

endmodule // 结束模块定义。
