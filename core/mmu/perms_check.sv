// ============================================================================
// 文件：core/mmu/perms_check.sv
// 类型：module
// 名称：perms_check
// 作用：检查页表项中的读、写、执行权限。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2024 Liam Feng, Chris Keilbart, Eric Matthews
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
 *             Liam Feng <lfa32@sfu.ca>
 *             Chris Keilbart <ckeilbar@sfu.ca>
 *             Eric Matthews <ematthew@sfu.ca>
 */

module perms_check // 定义 perms_check 模块。

    import csr_types::*; // 导入包或命名空间：csr_types::*;。

    (
        input pte_perms_t pte_perms, // 声明输入端口。

        input logic rnw, //LS type；声明输入端口。
        input logic execute, //Fetch；声明输入端口。
        input logic mxr, //Make eXecutable Readable；声明输入端口。
        input logic sum, //permit Supervisor User Memory access；声明输入端口。
        input privilege_t privilege, //Effective operatinf privilege；声明输入端口。

        output logic valid // 声明输出端口。
    );

    logic access_valid; // 声明信号、变量或生成变量。
    logic privilege_valid; // 声明信号、变量或生成变量。

    //Access and permission checks
    //A and D bits are software managed; this implementation corresponds to the Svade extension
    assign access_valid = // 执行连续赋值，把组合逻辑连接到目标信号。
        (execute & pte_perms.x & pte_perms.a) | //fetch
        (rnw & (pte_perms.r | (pte_perms.x & mxr)) & pte_perms.a) | //load
        ((~rnw & ~execute) & pte_perms.w & pte_perms.a & pte_perms.d); //store

    assign privilege_valid = // 执行连续赋值，把组合逻辑连接到目标信号。
        (privilege == MACHINE_PRIVILEGE) |
        ((privilege == SUPERVISOR_PRIVILEGE) & (~pte_perms.u | (pte_perms.u & sum))) |
        ((privilege == USER_PRIVILEGE) & pte_perms.u);
    
    assign valid = access_valid & privilege_valid; // 执行连续赋值，把组合逻辑连接到目标信号。
    
endmodule // 结束模块定义。
