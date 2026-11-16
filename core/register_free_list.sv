// ============================================================================
// 文件：core/register_free_list.sv
// 类型：module
// 名称：register_free_list
// 作用：管理寄存器重命名所需的物理寄存器空闲列表。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2017-2020 Eric Matthews,  Lesley Shannon
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

/*
 *  FIFOs Not underflow/overflow safe.
 *  Intended for small FIFO depths.
 *  For continuous operation when full, enqueing side must inspect pop signal
 */
module register_free_list // 定义 register_free_list 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    
    #(
        parameter type DATA_TYPE = logic, // 声明可配置参数。
        parameter FIFO_DEPTH = 4 // 声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。
        fifo_interface.structure fifo,
        input logic rollback // 声明输入端口。
    );

    localparam LOG2_FIFO_DEPTH = $clog2(FIFO_DEPTH); // 声明局部常量。

    //Force FIFO depth to next power of 2
    (* ramstyle = "MLAB, no_rw_check" *) logic [$bits(DATA_TYPE)-1:0] lut_ram [(2**LOG2_FIFO_DEPTH)];
    logic [LOG2_FIFO_DEPTH-1:0] write_index; // 声明信号、变量或生成变量。
    logic [LOG2_FIFO_DEPTH-1:0] read_index; // 声明信号、变量或生成变量。
    logic [LOG2_FIFO_DEPTH:0] inflight_count; // 声明信号、变量或生成变量。
    ////////////////////////////////////////////////////
    //Implementation

    ////////////////////////////////////////////////////
    //Occupancy Tracking
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            inflight_count <= 0;
        else // 执行否则分支。
            inflight_count <= inflight_count
            + (LOG2_FIFO_DEPTH+1)'(fifo.pop)
            - (LOG2_FIFO_DEPTH+1)'(fifo.push)
            - (LOG2_FIFO_DEPTH+1)'(rollback);
    end // 结束语句块。

    assign fifo.valid = inflight_count[LOG2_FIFO_DEPTH]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign fifo.full = fifo.valid & ~|inflight_count[LOG2_FIFO_DEPTH-1:0]; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            read_index <= '0;
            write_index <= '0;
        end // 结束语句块。
        else begin // 执行否则分支。
            read_index <= read_index + LOG2_FIFO_DEPTH'(fifo.pop) - LOG2_FIFO_DEPTH'(rollback);
            write_index <= write_index + LOG2_FIFO_DEPTH'(fifo.push);
        end // 结束语句块。
    end // 结束语句块。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (fifo.potential_push) // 执行条件判断，满足条件时进入对应分支。
            lut_ram[write_index] <= fifo.data_in;
    end // 结束语句块。
    assign fifo.data_out = lut_ram[read_index]; // 执行连续赋值，把组合逻辑连接到目标信号。

    ////////////////////////////////////////////////////
    //Assertions
    fifo_overflow_assertion:
        assert property (@(posedge clk) disable iff (rst) fifo.push |-> (~fifo.full | fifo.pop)) else $error("overflow"); // 定义或检查断言、假设、覆盖或时序性质。
    fifo_underflow_assertion:
        assert property (@(posedge clk) disable iff (rst) fifo.pop |-> fifo.valid) else $error("underflow"); // 定义或检查断言、假设、覆盖或时序性质。

endmodule // 结束模块定义。
