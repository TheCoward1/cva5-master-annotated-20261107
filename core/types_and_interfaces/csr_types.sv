// ============================================================================
// 文件：core/types_and_interfaces/csr_types.sv
// 类型：package
// 名称：csr_types
// 作用：定义 CSR 地址、权限、异常码、中断和特权相关类型。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2018 Eric Matthews,  Lesley Shannon
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

package csr_types; // 定义 csr_types 包。
    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import riscv_types::*; // 导入包或命名空间：riscv_types::*;。

    const logic [1:0] CSR_READ_ONLY = 2'b11;

// 定义类型别名或枚举/结构类型。
    typedef enum logic [1:0] {
        USER_PRIVILEGE = 2'b00,
        SUPERVISOR_PRIVILEGE = 2'b01,
        RESERVED_PRIVILEGE = 2'b10,
        MACHINE_PRIVILEGE = 2'b11
    } privilege_t;


// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [1:0] rw_bits; // 声明信号、变量或生成变量。
        logic [1:0] privilege; // 声明信号、变量或生成变量。
        logic [7:0] sub_addr; // 声明信号、变量或生成变量。
    } csr_addr_t;

    //Constant registers
// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic[1:0] mxlen; //RV32I；声明信号、变量或生成变量。
        logic[3:0] reserved; // 声明信号、变量或生成变量。
        logic Z; // 声明信号、变量或生成变量。
        logic Y; // 声明信号、变量或生成变量。
        logic X; // 声明信号、变量或生成变量。
        logic W; // 声明信号、变量或生成变量。
        logic V; // 声明信号、变量或生成变量。
        logic U; // 声明信号、变量或生成变量。
        logic T; // 声明信号、变量或生成变量。
        logic S; //Supervisor mode；声明信号、变量或生成变量。
        logic R; // 声明信号、变量或生成变量。
        logic Q; // 声明信号、变量或生成变量。
        logic P; // 声明信号、变量或生成变量。
        logic O; // 声明信号、变量或生成变量。
        logic N; // 声明信号、变量或生成变量。
        logic M; //multiply divide；声明信号、变量或生成变量。
        logic L; // 声明信号、变量或生成变量。
        logic K; // 声明信号、变量或生成变量。
        logic J; // 声明信号、变量或生成变量。
        logic I; //Base；声明信号、变量或生成变量。
        logic H; // 声明信号、变量或生成变量。
        logic G; // 声明信号、变量或生成变量。
        logic F; //Single precision；声明信号、变量或生成变量。
        logic E; // 声明信号、变量或生成变量。
        logic D; //Double precision；声明信号、变量或生成变量。
        logic C; // 声明信号、变量或生成变量。
        logic B; // 声明信号、变量或生成变量。
        logic A; //Atomic；声明信号、变量或生成变量。
    } misa_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic sd; // 声明信号、变量或生成变量。
        logic [7:0] zeros; // 声明信号、变量或生成变量。
        logic tsr; // 声明信号、变量或生成变量。
        logic tw; // 声明信号、变量或生成变量。
        logic tvm; // 声明信号、变量或生成变量。
        logic mxr; // 声明信号、变量或生成变量。
        logic sum; // 声明信号、变量或生成变量。
        logic mprv; // 声明信号、变量或生成变量。
        logic [1:0] xs; // 声明信号、变量或生成变量。
        logic [1:0] fs; // 声明信号、变量或生成变量。
        logic [1:0] mpp; // 声明信号、变量或生成变量。
        logic [1:0] vs; // 声明信号、变量或生成变量。
        logic spp; // 声明信号、变量或生成变量。
        logic mpie; // 声明信号、变量或生成变量。
        logic ube; // 声明信号、变量或生成变量。
        logic spie; // 声明信号、变量或生成变量。
        logic zero2; // 声明信号、变量或生成变量。
        logic mie; // 声明信号、变量或生成变量。
        logic zero3; // 声明信号、变量或生成变量。
        logic sie; // 声明信号、变量或生成变量。
        logic zero4; // 声明信号、变量或生成变量。
    } mstatus_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [7:0] custom; // 声明信号、变量或生成变量。
        logic [7:0] zeros; // 声明信号、变量或生成变量。
        logic store_amo_page_fault; // 声明信号、变量或生成变量。
        logic zero1; // 声明信号、变量或生成变量。
        logic load_page_fault; // 声明信号、变量或生成变量。
        logic instruction_page_fault; // 声明信号、变量或生成变量。
        logic m_ecall; // 声明信号、变量或生成变量。
        logic zero2; // 声明信号、变量或生成变量。
        logic s_ecall; // 声明信号、变量或生成变量。
        logic u_ecall; // 声明信号、变量或生成变量。
        logic store_amo_access_fault; // 声明信号、变量或生成变量。
        logic store_amo_misaligned; // 声明信号、变量或生成变量。
        logic load_fault; // 声明信号、变量或生成变量。
        logic load_misaligned; // 声明信号、变量或生成变量。
        logic breakpoint; // 声明信号、变量或生成变量。
        logic illegal_instruction; // 声明信号、变量或生成变量。
        logic instruction_access_fault; // 声明信号、变量或生成变量。
        logic instruction_misaligned; // 声明信号、变量或生成变量。
    } medeleg_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [31:16] custom; // 声明信号、变量或生成变量。
        logic [15:14] zeros; // 声明信号、变量或生成变量。
        logic lcofip; // 声明信号、变量或生成变量。
        logic zero0; // 声明信号、变量或生成变量。
        logic meip; // 声明信号、变量或生成变量。
        logic zero1; // 声明信号、变量或生成变量。
        logic seip; // 声明信号、变量或生成变量。
        logic zero2; // 声明信号、变量或生成变量。
        logic mtip; // 声明信号、变量或生成变量。
        logic zero3; // 声明信号、变量或生成变量。
        logic stip; // 声明信号、变量或生成变量。
        logic zero4; // 声明信号、变量或生成变量。
        logic msip; // 声明信号、变量或生成变量。
        logic zero5; // 声明信号、变量或生成变量。
        logic ssip; // 声明信号、变量或生成变量。
        logic zero6; // 声明信号、变量或生成变量。
    } mip_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [31:16] custom; // 声明信号、变量或生成变量。
        logic [15:14] zeros; // 声明信号、变量或生成变量。
        logic lcofie; // 声明信号、变量或生成变量。
        logic zero0; // 声明信号、变量或生成变量。
        logic meie; // 声明信号、变量或生成变量。
        logic zero1; // 声明信号、变量或生成变量。
        logic seie; // 声明信号、变量或生成变量。
        logic zero2; // 声明信号、变量或生成变量。
        logic mtie; // 声明信号、变量或生成变量。
        logic zero3; // 声明信号、变量或生成变量。
        logic stie; // 声明信号、变量或生成变量。
        logic zero4; // 声明信号、变量或生成变量。
        logic msie; // 声明信号、变量或生成变量。
        logic zero5; // 声明信号、变量或生成变量。
        logic ssie; // 声明信号、变量或生成变量。
        logic zero6; // 声明信号、变量或生成变量。
    } mie_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [31:16] custom; // 声明信号、变量或生成变量。
        logic [15:14] zeros; // 声明信号、变量或生成变量。
        logic lcofipd; // 声明信号、变量或生成变量。
        logic [12:10] zero1; // 声明信号、变量或生成变量。
        logic seid; // 声明信号、变量或生成变量。
        logic [8:6] zero2; // 声明信号、变量或生成变量。
        logic stid; // 声明信号、变量或生成变量。
        logic [4:2] zero3; // 声明信号、变量或生成变量。
        logic ssid; // 声明信号、变量或生成变量。
        logic zero4; // 声明信号、变量或生成变量。
    } mideleg_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic is_interrupt; // 声明信号、变量或生成变量。
        logic [XLEN-1-1-ECODE_W:0] zeros; // 声明信号、变量或生成变量。
        logic [ECODE_W-1:0] code; // 声明信号、变量或生成变量。
    } cause_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [28:0] hpm; // 声明信号、变量或生成变量。
        logic ir; // 声明信号、变量或生成变量。
        logic tm; // 声明信号、变量或生成变量。
        logic cy; // 声明信号、变量或生成变量。
    } mcounter_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [24:0] zeros_high; // 声明信号、变量或生成变量。
        logic cbze; // 声明信号、变量或生成变量。
        logic cbcfe; // 声明信号、变量或生成变量。
        logic [1:0] cbie; // 声明信号、变量或生成变量。
        logic [1:0] zeros_low; // 声明信号、变量或生成变量。
        logic fiom; // 声明信号、变量或生成变量。
    } envcfg_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic stce; // 声明信号、变量或生成变量。
        logic pbmte; // 声明信号、变量或生成变量。
        logic adue; // 声明信号、变量或生成变量。
        logic cde; // 声明信号、变量或生成变量。
        logic [27:0] zeros; // 声明信号、变量或生成变量。
    } envcfgh_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic [28:0] zeros; // 声明信号、变量或生成变量。
        logic jvt; // 声明信号、变量或生成变量。
        logic fcsr; // 声明信号、变量或生成变量。
        logic c; // 声明信号、变量或生成变量。
    } stateen0_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic se0; // 声明信号、变量或生成变量。
        logic envcfg; // 声明信号、变量或生成变量。
        logic zero; // 声明信号、变量或生成变量。
        logic csrind; // 声明信号、变量或生成变量。
        logic aia; // 声明信号、变量或生成变量。
        logic imsic; // 声明信号、变量或生成变量。
        logic contex; // 声明信号、变量或生成变量。
        logic [24:0] zeros; // 声明信号、变量或生成变量。
    } mstateen0h_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic mode; // 声明信号、变量或生成变量。
        logic [ASIDLEN-1:0] asid; // 声明信号、变量或生成变量。
        logic [21:0] ppn; // 声明信号、变量或生成变量。
    } satp_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic d; // 声明信号、变量或生成变量。
        logic a; // 声明信号、变量或生成变量。
        logic g; // 声明信号、变量或生成变量。
        logic u; // 声明信号、变量或生成变量。
        logic x; // 声明信号、变量或生成变量。
        logic w; // 声明信号、变量或生成变量。
        logic r; // 声明信号、变量或生成变量。
        logic v; // 声明信号、变量或生成变量。
    } pte_perms_t;

endpackage // 结束包定义。
