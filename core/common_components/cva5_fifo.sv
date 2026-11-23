// ============================================================================
// 文件：core/common_components/cva5_fifo.sv
// 类型：module
// 名称：cva5_fifo
// 作用：实现参数化同步 FIFO，支持 push/pop、valid/full、data_in/data_out 和
//       potential_push 预写语义，并为不同深度选择不同的小面积实现。
// 实现：
//   FIFO_DEPTH == 1：单寄存器 FIFO；
//   FIFO_DEPTH == 2：两个寄存器构成移位寄存器；
//   FIFO_DEPTH >= 3：LFSR 循环索引 + 单写单读 LUTRAM。
// 协议：
//   push 表示实际入队，pop 表示实际出队；
//   同一周期同时 push 和 pop 时，FIFO 可以保持满/空状态继续流动；
//   potential_push 允许上游提前把可能写入的数据送到存储体，但只有 push 才推进
//   写指针并改变有效计数；
//   data_out 在 valid=0 时可能仍保留旧数据或预写数据，消费者必须先检查 valid。
// 注意：该 FIFO 不做自动溢出/下溢保护，上下游必须遵守 full/valid 与同周期 pop/push
//       的协议；文件末尾的断言用于在仿真中检查这些使用约束。
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

module cva5_fifo
    #(
        parameter type DATA_TYPE = logic, // FIFO 中保存的数据类型
        parameter FIFO_DEPTH = 4          // FIFO 的逻辑深度，必须至少为 1
    )
    (
        input logic clk,                 // FIFO 时钟
        input logic rst,                 // 同步复位，高有效
        fifo_interface.structure fifo    // FIFO 接口，包含 push/pop/data/valid/full 等信号
    );

    // 深度对应的索引位宽；例如 DEPTH=4 时为 2 bit。
    localparam LOG2_FIFO_DEPTH = $clog2(FIFO_DEPTH);

    ////////////////////////////////////////////////////
    // Implementation
    // 根据 FIFO_DEPTH 在 elaboration 阶段选择面积和时序更合适的实现。
    generate if (FIFO_DEPTH == 1) begin : gen_width_one
        // 深度为 1 时，只需要一个 valid 寄存器保存“是否有一个元素”。
        // full 与 valid 等价；同周期 push+pop 时 valid 保持不变。
        always_ff @ (posedge clk) begin
            if (rst)
                fifo.valid <= 0;
            else if (fifo.push & ~fifo.pop)
                fifo.valid <= 1;             // 只有入队：从空变为非空
            else if (fifo.pop & ~fifo.push)
                fifo.valid <= 0;             // 只有出队：从非空变为空
        end
        assign fifo.full = fifo.valid;        // 单深度 FIFO 满时也就是 valid=1

        // 数据寄存器在 potential_push 时预写；最终是否有效仍由 valid 决定。
        // 这样允许上游提前把候选数据送入 FIFO，实际入队时无需额外的数据路径延迟。
        always_ff @ (posedge clk) begin
            if (fifo.potential_push)
                fifo.data_out <= fifo.data_in;
        end
    end
    // 深度为 2 时，用两个寄存器构成移位寄存器；
    // 这样与 LUTRAM FIFO 的资源量接近，但通常有更好的时序。
    else if (FIFO_DEPTH == 2) begin : gen_width_two
        DATA_TYPE shift_reg [FIFO_DEPTH]; // shift_reg[0] 最新，shift_reg[1] 较旧
        // 用二进制补码形式记录“信用/在途计数”：
        // 复位为 0，push 使其减 1，pop 使其加 1。
        // 例如已有 1 个元素时，值为 -1（全 1）；已有 2 个元素时为 -2（10）。
        logic [LOG2_FIFO_DEPTH:0] inflight_count;

        ////////////////////////////////////////////////////
        // Occupancy Tracking
        // 记录当前已有多少个元素；push/pop 同周期时净变化为 0。
        always_ff @ (posedge clk) begin
            if (rst)
                inflight_count <= 0;
            else
                inflight_count <= inflight_count + (LOG2_FIFO_DEPTH+1)'(fifo.pop)
                                                     - (LOG2_FIFO_DEPTH+1)'(fifo.push);
        end

        // 最高位相当于负号位：非空时 inflight_count 为负数，因此最高位为 1。
        assign fifo.valid = inflight_count[LOG2_FIFO_DEPTH];
        // 深度为 2 时，满条件是 inflight_count == -2：
        // 最高位为 1，且低位全为 0。
        assign fifo.full = fifo.valid & ~|inflight_count[LOG2_FIFO_DEPTH-1:0];

        // 每次实际 push 时把旧数据后移，并把新数据写入最前面的寄存器。
        always_ff @ (posedge clk) begin
            if (fifo.push) begin
                shift_reg[0] <= fifo.data_in;
                shift_reg[1] <= shift_reg[0];
            end
        end

        // inflight_count 为 -1 时最低位为 1，选择 shift_reg[0]；
        // 为 -2 时最低位为 0，选择 shift_reg[1]。
        assign fifo.data_out = shift_reg[~inflight_count[0]];
    end
    else begin : gen_width_3_plus
        // 深度大于等于 3 时，用 LFSR 生成循环读写索引，
        // 再用单写单读 LUTRAM 保存数据，避免使用大量触发器。
        logic [LOG2_FIFO_DEPTH-1:0] write_index; // 下一个实际写入位置
        logic [LOG2_FIFO_DEPTH-1:0] read_index;  // 下一个实际读取位置
        // 同样使用二进制补码信用计数：0 - push 数量 + pop 数量。
        logic [LOG2_FIFO_DEPTH:0] inflight_count;

        ////////////////////////////////////////////////////
        // Occupancy Tracking
        // 每个实际 push 使计数减 1，每个实际 pop 使计数加 1。
        always_ff @ (posedge clk) begin
            if (rst)
                inflight_count <= 0;
            else
                inflight_count <= inflight_count + (LOG2_FIFO_DEPTH+1)'(fifo.pop)
                                                     - (LOG2_FIFO_DEPTH+1)'(fifo.push);
        end

        // 非空时 inflight_count 为负，最高位为 1。
        assign fifo.valid = inflight_count[LOG2_FIFO_DEPTH];
        // 满条件是 inflight_count == -FIFO_DEPTH；这里显式转换为计数器位宽，
        // 以保留负数的补码表示。
        assign fifo.full = inflight_count == (LOG2_FIFO_DEPTH+1)'(-FIFO_DEPTH);

        // 读索引在每次实际 pop 时沿 LFSR 序列前进一步。
        lfsr #(.WIDTH(LOG2_FIFO_DEPTH), .NEEDS_RESET(1))
        lfsr_read_index (
            .clk (clk), .rst (rst),
            .en(fifo.pop),
            .value(read_index)
        );

        // 写索引只在实际 push 时前进一步；potential_push 不会推进写指针，
        // 因此它写入的是“如果本周期真的 push 将使用的槽位”。
        lfsr #(.WIDTH(LOG2_FIFO_DEPTH), .NEEDS_RESET(1))
        lfsr_write_index (
            .clk (clk), .rst (rst),
            .en(fifo.push),
            .value(write_index)
        );

        // 物理 RAM 深度强制为下一个 2 的幂；逻辑深度由 inflight_count/full 限制。
        // ram_write 使用 potential_push，允许上游提前写入候选数据；
        // 只要实际 push 未发生，下一次写会覆盖同一个槽位。
        lutram_1w_1r #(.DATA_TYPE(DATA_TYPE), .DEPTH(2**LOG2_FIFO_DEPTH))
        write_port (
            .clk(clk),
            .waddr(write_index),
            .raddr(read_index),
            .ram_write(fifo.potential_push),
            .new_ram_data(fifo.data_in),
            .ram_data_out(fifo.data_out)
        );
    end
    endgenerate

    ////////////////////////////////////////////////////
    // Assertions
    // 满时只有在同周期执行 pop 才能继续 push，否则会发生溢出。
    fifo_overflow_assertion:
        assert property (@(posedge clk) disable iff (rst)
            fifo.push |-> (~fifo.full | fifo.pop))
        else $error("overflow");

    // potential_push 也必须遵守相同的容量约束；它可以预写数据，
    // 但不能在 FIFO 已满且没有同周期 pop 的情况下继续请求写入。
    fifo_potenial_push_overflow_assertion:
        assert property (@(posedge clk) disable iff (rst)
            fifo.potential_push |-> (~fifo.full | fifo.pop))
        else $error("potential push overflow");

    // 空时只有在同周期执行 push 才能继续 pop，否则会发生下溢。
    fifo_underflow_assertion:
        assert property (@(posedge clk) disable iff (rst)
            fifo.pop |-> (fifo.valid | fifo.push))
        else $error("underflow");

endmodule
