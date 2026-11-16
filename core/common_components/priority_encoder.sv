// ============================================================================
// 文件：core/common_components/priority_encoder.sv
// 类型：module
// 名称：priority_encoder
// 作用：从输入位向量中找出最低有效置位位，并输出其索引。
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

////////////////////////////////////////////////////
//Highest Priority for: Index Zero
//Look-up Table based
//Max width of 12
////////////////////////////////////////////////////
module priority_encoder // 定义 priority_encoder 模块。
    #(
        parameter WIDTH = 4 // 声明可配置参数。
    )
    (
        input logic [WIDTH-1:0] priority_vector, // 声明输入端口。
        output logic [(WIDTH == 1) ? 0 : ($clog2(WIDTH)-1) : 0] encoded_result // 声明输出端口。
    );
    ////////////////////////////////////////////////////
    //Width Check
    if (WIDTH > 14) // 执行条件判断，满足条件时进入对应分支。
        $error("Max priority encoder width exceeded!");

    //Tool workaround
    localparam MIN_WIDTH = (WIDTH == 1) ? 2 : WIDTH; // 声明局部常量。
    localparam LOG2_WIDTH = $clog2(MIN_WIDTH); // 声明局部常量。
    //Table generation for priority encoder
    function [2**MIN_WIDTH-1:0][LOG2_WIDTH-1 : 0] table_gen (); // 开始函数定义，用于组合计算或辅助逻辑。
        for (int i = 0; i < 2**MIN_WIDTH; i++) begin //Loop through all memory addresses；执行循环或遍历。
            table_gen[i] = LOG2_WIDTH'(MIN_WIDTH - 1);//Initialize to lowest priority
            for (int j = (int'(MIN_WIDTH) - 2); j >= 0; j--) begin//Check each bit in increasing priority；执行循环或遍历。
                if (i[j])//If bit is set update table value with that bit's index；执行条件判断，满足条件时进入对应分支。
                    table_gen[i] = LOG2_WIDTH'(j);
            end // 结束语句块。
        end // 结束语句块。
    endfunction // 结束函数定义。

    //Initialize Table
    localparam logic [2**MIN_WIDTH-1:0][LOG2_WIDTH-1 : 0] ENCODER_ROM = table_gen(); // 声明局部常量。

    ////////////////////////////////////////////////////
    //Implementation
    assign encoded_result = (WIDTH == 1) ? 0 : ENCODER_ROM[priority_vector]; // 执行连续赋值，把组合逻辑连接到目标信号。

endmodule // 结束模块定义。
