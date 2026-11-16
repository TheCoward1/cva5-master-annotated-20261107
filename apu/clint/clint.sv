// ============================================================================
// 文件：apu/clint/clint.sv
// 类型：module
// 名称：clint
// 作用：实现 core-local timer 和软件中断，为 RISC-V 提供定时器和 IPI。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2024 Chris Keilbart, Mohammad Shahidzadeh
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
 *             Mohammad Shahidzadeh <mohammad_shahidzadeh_asadi@sfu.ca>
 */

module clint // 定义 clint 模块。

    #(
        parameter int unsigned NUM_CORES = 1 // 声明可配置参数。
    ) (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        input logic write_mtime, // 声明输入端口。
        input logic write_mtimecmp, // 声明输入端口。
        input logic write_msip, // 声明输入端口。
        input logic write_upper, //Else lower; mtime and mtimecmp only；声明输入端口。
        input logic [(NUM_CORES == 1) ? 0 : ($clog2(NUM_CORES)-1) : 0] write_msip_core, // 声明输入端口。
        input logic [(NUM_CORES == 1) ? 0 : ($clog2(NUM_CORES)-1) : 0] write_mtimecmp_core, // 声明输入端口。
        input logic[31:0] write_data, // 声明输入端口。

        output logic[1:0][31:0] mtime, // 声明输出端口。
        output logic[NUM_CORES-1:0][1:0][31:0] mtimecmp, // 声明输出端口。
        output logic[NUM_CORES-1:0] msip, // 声明输出端口。
        output logic[NUM_CORES-1:0] mtip // 声明输出端口。
    );

    ////////////////////////////////////////////////////
    //Core Local INTerrupt unit (CLINT)
    //Implements mtime, mtimecmp, mtip, and msip from the RISC-V privileged specification
    //mtime increments at a constant frequency
    //mtip is set when mtime >= mtimecmp
    //mtimecmp and msip are registers
    logic[63:0] mtime_p_1; // 声明信号、变量或生成变量。
    assign mtime_p_1 = {mtime[1], mtime[0]} + 1; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            mtime <= '0;
            mtimecmp <= '1; //Reset to max to prevent interrupts
            msip <= '0;
        end // 结束语句块。
        else begin // 执行否则分支。
            for (int i = 0; i < NUM_CORES; i++) // 执行循环或遍历。
                mtip[i] <= {mtime[1], mtime[0]} >= {mtimecmp[i][1], mtimecmp[i][0]};
            
            mtime[1] <= write_mtime & write_upper ? write_data : mtime_p_1[63:32];
            mtime[0] <= write_mtime & ~write_upper ? write_data : mtime_p_1[31:0];
            
            for (int i = 0; i < NUM_CORES; i++) begin // 执行循环或遍历。
                mtimecmp[i][1] <= write_mtimecmp & write_upper & i == int'(write_mtimecmp_core) ? write_data : mtimecmp[i][1];
                mtimecmp[i][0] <= write_mtimecmp & ~write_upper & i == int'(write_mtimecmp_core) ? write_data : mtimecmp[i][0];
            end // 结束语句块。

            if (write_msip) // 执行条件判断，满足条件时进入对应分支。
                msip[write_msip_core] <= write_data[0]; //LSB
        end // 结束语句块。
    end // 结束语句块。

endmodule // 结束模块定义。
