// ============================================================================
// 文件：core/common_components/lfsr.sv
// 类型：module
// 名称：lfsr
// 作用：实现 3 到 16 位线性反馈移位寄存器，可为 FIFO 索引、轮询和测试平台
//       产生伪随机循环状态。
// 行为：en=1 时每个时钟沿左移一位，并把反馈位写入 value[0]；
//       needs_reset=1 时，rst=1 会同步把状态清零；
//       额外的反馈项使序列覆盖完整的 2^WIDTH 状态空间。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2021 Eric Matthews

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

//3-16 bit LFSRs with additional feedback to support full 2^N range
module lfsr

    #(
        parameter int unsigned WIDTH = 3, // LFSR 状态位宽，支持 3~16
        parameter NEEDS_RESET = 1 // 是否需要同步复位清零
    )
    (
        input logic clk, // 时钟
        input logic rst, // 同步复位，高有效
        input logic en, // 移位使能，高有效
        output logic [WIDTH-1:0] value // 当前 LFSR 状态
    );

// TAPS 保存 LFSR 的反馈抽头：NUM 是抽头数量，INDICIES 是抽头位置列表。
    typedef struct packed {
        int unsigned NUM; // 抽头数量
        bit [3:0][31:0] INDICIES; // 最多 4 个反馈抽头的位置
    } tap_t;

    // 3~16 位 LFSR 的反馈抽头表；每个表项对应一种 WIDTH。
    localparam tap_t LFSR_TAPS [17] = '{ // 索引 0~16；0~2 项只是占位
        //Dummy entries for widths 0-2
        '{NUM : 1,    INDICIES : '{0,0,0,0}},
        '{NUM : 1,    INDICIES : '{0,0,0,0}},
        '{NUM : 1,    INDICIES : '{0,0,0,0}},
        //Number of taps and indicies[3:0] for LFSRs width 3 to 16
        '{NUM : 2,    INDICIES : '{0,0,1,2}}, //3
        '{NUM : 2,    INDICIES : '{0,0,2,3}}, //4
        '{NUM : 2,    INDICIES : '{0,0,2,4}},
        '{NUM : 2,    INDICIES : '{0,0,4,5}},
        '{NUM : 2,    INDICIES : '{0,0,5,6}},
        '{NUM : 4,    INDICIES : '{3,4,5,7}}, //8
        '{NUM : 2,    INDICIES : '{0,0,4,8}},
        '{NUM : 2,    INDICIES : '{0,0,6,9}},
        '{NUM : 2,    INDICIES : '{0,0,8,10}},
        '{NUM : 4,    INDICIES : '{0,3,5,11}}, //12
        '{NUM : 4,    INDICIES : '{0,2,3,12}},
        '{NUM : 4,    INDICIES : '{0,2,4,13}},
        '{NUM : 2,    INDICIES : '{0,0,13,14}}, //15
        '{NUM : 4,    INDICIES : '{3,12,14,15}} //16
    };

    localparam tap_t TAPS = LFSR_TAPS[WIDTH]; // 根据当前 WIDTH 选择对应抽头

    logic [TAPS.NUM-1:0] feedback_input; // 各反馈抽头当前取出的值
    logic feedback; // 计算出的下一位反馈值
    ////////////////////////////////////////////////////
    //Implementation
    // WIDTH 小于等于 2 时结构简单，反馈直接取当前最高位的反相。
    generate if (WIDTH <= 2) begin : gen_width_one_or_two
        assign feedback = ~value[WIDTH-1];
    end // 结束语句块。
    // WIDTH 大于等于 3 时，按抽头表组合反馈网络。
    else begin : gen_width_three_plus
        for (genvar i = 0; i < TAPS.NUM; i++) begin : gen_taps
            assign feedback_input[i] = value[int'(TAPS.INDICIES[i])]; // 取出第 i 个抽头位
        end // 结束语句块。
        // 抽头先做 XNOR；再与低 WIDTH-1 位的 OR 异或，扩大序列覆盖范围。
        assign feedback = (~^feedback_input) ^ |value[WIDTH-2:0];
    end // 结束语句块。
    endgenerate // 结束生成块。

    //initial value = 0; // 仿真初值；综合后的实际初值应由复位建立
    always_ff @ (posedge clk) begin // 同步时序逻辑
        if (NEEDS_RESET & rst) // 复位优先，将 LFSR 清零
            value <= '0;
        else if (en) begin // 执行否则如果分支的条件判断。
            value <= value << 1; // 状态整体左移一位
            value[0] <= feedback; // 新反馈位进入最低位
        end // 结束语句块。
    end // 结束语句块。

endmodule // 结束模块定义。
