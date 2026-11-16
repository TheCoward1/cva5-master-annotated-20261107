// ============================================================================
// 文件：core/fp_writeback.sv
// 类型：module
// 名称：fp_writeback
// 作用：处理浮点结果的写回和异常标志。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2023 Chris Keilbart, Lesley Shannon
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

module fp_writeback // 定义 fp_writeback 模块。

    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    (
        //Unit writeback
        unit_writeback_interface.wb unit_wb[2],
        //WB output
        output fp_wb_packet_t wb_packet[2] // 声明输出端口。
    );

    //Because there are two writeback ports for the FP register file, no arbitration is needed
    assign wb_packet[0].id = unit_wb[0].id; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb_packet[0].valid = unit_wb[0].done; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb_packet[0].data = unit_wb[0].rd; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign unit_wb[0].ack = unit_wb[0].done; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign wb_packet[1].id = unit_wb[1].id; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb_packet[1].valid = unit_wb[1].done; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign wb_packet[1].data = unit_wb[1].rd; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign unit_wb[1].ack = unit_wb[1].done; // 执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
