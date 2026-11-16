// ============================================================================
// 文件：examples/xilinx/cva5_wrapper.sv
// 类型：module
// 名称：cva5_wrapper
// 作用：把 CVA5 连接到 Xilinx FPGA 的 BRAM、AXI 外设和板级接口。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2024 Chris Keilbart
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

module cva5_wrapper // 定义 cva5_wrapper 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    #(
        parameter string LOCAL_MEM = "mem.mif", // 声明可配置参数。
        parameter int unsigned WORDS = 1024 // 声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        input logic rstn, //Synchronous active low；声明输入端口。

        //Peripheral AXI bus
        //AR
        input logic m_axi_arready, // 声明输入端口。
        output logic m_axi_arvalid, // 声明输出端口。
        output logic [31:0] m_axi_araddr, // 声明输出端口。

        //R
        output logic m_axi_rready, // 声明输出端口。
        input logic m_axi_rvalid, // 声明输入端口。
        input logic [31:0] m_axi_rdata, // 声明输入端口。
        input logic [1:0] m_axi_rresp, // 声明输入端口。

        //AW
        input logic m_axi_awready, // 声明输入端口。
        output logic m_axi_awvalid, // 声明输出端口。
        output logic [31:0] m_axi_awaddr, // 声明输出端口。

        //W
        input logic m_axi_wready, // 声明输入端口。
        output logic m_axi_wvalid, // 声明输出端口。
        output logic [31:0] m_axi_wdata, // 声明输出端口。
        output logic [3:0] m_axi_wstrb, // 声明输出端口。

        //B
        output logic m_axi_bready, // 声明输出端口。
        input logic m_axi_bvalid, // 声明输入端口。
        input logic [1:0] m_axi_bresp // 声明输入端口。
    );

    //CPU connections
    local_memory_interface data_bram();
    local_memory_interface instruction_bram();
    axi_interface m_axi();
    avalon_interface m_avalon(); //Unused
    wishbone_interface dwishbone(); //Unused
    wishbone_interface iwishbone(); //Unused
    mem_interface mem();
    logic[63:0] mtime; // 声明信号、变量或生成变量。
    interrupt_t s_interrupt; //Unused
    interrupt_t m_interrupt; //Unused

    ////////////////////////////////////////////////////
    //Implementation
    //Instantiates a CVA5 processor using local memory
    //Program start address 0x8000_0000
    //Local memory space from 0x8000_0000 through 0x80FF_FFFF
    //Peripheral bus from 0x6000_0000 through 0x6FFF_FFFF

    localparam wb_group_config_t WB_CPU_CONFIG = '{ // 声明局部常量。
        0 : '{0: ALU_ID, default : NON_WRITEBACK_ID},
        1 : '{0: LS_ID, default : NON_WRITEBACK_ID},
        2 : '{0: MUL_ID, 1: DIV_ID, 2: CSR_ID, 3: FPU_ID, 4: CUSTOM_ID, default : NON_WRITEBACK_ID},
        default : '{default : NON_WRITEBACK_ID} // 执行默认分支。
    };

    localparam cpu_config_t CPU_CONFIG = '{ // 声明局部常量。
        //ISA options
        MODES : M,
        INCLUDE_UNIT : '{
            MUL : 1,
            DIV : 1,
            CSR : 1,
            FPU : 0,
            CUSTOM : 0,
            default: '0 // 执行默认分支。
        },
        INCLUDE_IFENCE : 0,
        INCLUDE_AMO : 0,
        INCLUDE_CBO : 0,
        //CSR constants
        CSRS : '{
            MACHINE_IMPLEMENTATION_ID : 0,
            CPU_ID : 0,
            RESET_VEC : 32'h80000000,
            RESET_TVEC : 32'h00000000,
            MCONFIGPTR : '0,
            INCLUDE_ZICNTR : 1,
            INCLUDE_ZIHPM : 0,
            INCLUDE_SSTC : 0,
            INCLUDE_SMSTATEEN : 0
        },
        //Memory Options
        SQ_DEPTH : 4,
        INCLUDE_FORWARDING_TO_STORES : 1,
        AMO_UNIT : '{
            LR_WAIT : 32,
            RESERVATION_WORDS : 8
        },
        INCLUDE_ICACHE : 0,
        ICACHE_ADDR : '{
            L: 32'h80000000,
            H: 32'h8FFFFFFF
        },
        ICACHE : '{
            LINES : 512,
            LINE_W : 4,
            WAYS : 2,
            USE_EXTERNAL_INVALIDATIONS : 0,
            USE_NON_CACHEABLE : 0,
            NON_CACHEABLE : '{
                L: 32'h70000000,
                H: 32'h7FFFFFFF
            }
        },
        ITLB : '{
            WAYS : 2,
            DEPTH : 64
        },
        INCLUDE_DCACHE : 0,
        DCACHE_ADDR : '{
            L: 32'h80000000,
            H: 32'h8FFFFFFF
        },
        DCACHE : '{
            LINES : 512,
            LINE_W : 4,
            WAYS : 2,
            USE_EXTERNAL_INVALIDATIONS : 0,
            USE_NON_CACHEABLE : 0,
            NON_CACHEABLE : '{
                L: 32'h70000000,
                H: 32'h7FFFFFFF
            }
        },
        DTLB : '{
            WAYS : 2,
            DEPTH : 64
        },
        INCLUDE_ILOCAL_MEM : 1,
        ILOCAL_MEM_ADDR : '{
            L : 32'h80000000,
            H : 32'h80FFFFFF
        },
        INCLUDE_DLOCAL_MEM : 1,
        DLOCAL_MEM_ADDR : '{
            L : 32'h80000000,
            H : 32'h80FFFFFF
        },
        INCLUDE_IBUS : 0,
        IBUS_ADDR : '{
            L : 32'h60000000,
            H : 32'h6FFFFFFF
        },
        INCLUDE_PERIPHERAL_BUS : 1,
        PERIPHERAL_BUS_ADDR : '{
            L : 32'h60000000,
            H : 32'h6FFFFFFF
        },
        PERIPHERAL_BUS_TYPE : AXI_BUS,
        //Branch Predictor Options
        INCLUDE_BRANCH_PREDICTOR : 1,
        BP : '{
            WAYS : 2,
            ENTRIES : 512,
            RAS_ENTRIES : 8
        },
        //Writeback Options
        NUM_WB_GROUPS : 3,
        WB_GROUP : WB_CPU_CONFIG
    };

    logic rst; // 声明信号、变量或生成变量。
    assign rst = ~rstn; // 执行连续赋值，把组合逻辑连接到目标信号。
    cva5 #(.CONFIG(CPU_CONFIG)) cpu(.*);

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            mtime <= '0;
        else // 执行否则分支。
            mtime <= mtime + 1;
    end // 结束语句块。

    assign s_interrupt = '{default: '0}; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_interrupt = '{default: '0}; // 执行连续赋值，把组合逻辑连接到目标信号。

    //AXI peripheral mapping; ID widths are missmatched but unused
    assign m_axi.arready = m_axi_arready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi_arvalid = m_axi.arvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi_araddr = m_axi.araddr; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign m_axi_rready = m_axi.rready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.rvalid = m_axi_rvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.rdata = m_axi_rdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.rresp = m_axi_rresp; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.rid = 6'b0; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign m_axi.awready = m_axi_awready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi_awvalid = m_axi.awvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi_awaddr = m_axi.awaddr; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign m_axi.wready = m_axi_wready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi_wvalid = m_axi.wvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi_wdata = m_axi.wdata; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi_wstrb = m_axi.wstrb; // 执行连续赋值，把组合逻辑连接到目标信号。

    assign m_axi_bready = m_axi.bready; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.bvalid = m_axi_bvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.bresp = m_axi_bresp; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign m_axi.bid = 6'b0; // 执行连续赋值，把组合逻辑连接到目标信号。

    //Block memory
    localparam BRAM_ADDR_W = $clog2(WORDS); // 声明局部常量。
    tdp_ram #(
        .ADDR_WIDTH(BRAM_ADDR_W),
        .NUM_COL(4),
        .COL_WIDTH(8),
        .PIPELINE_DEPTH(0),
        .CASCADE_DEPTH(8),
        .USE_PRELOAD(1),
        .PRELOAD_FILE(LOCAL_MEM)
    ) local_mem (
        .a_en(instruction_bram.en),
        .a_wbe(instruction_bram.be),
        .a_wdata(instruction_bram.data_in),
        .a_addr(instruction_bram.addr[BRAM_ADDR_W-1:0]),
        .a_rdata(instruction_bram.data_out),
        .b_en(data_bram.en),
        .b_wbe(data_bram.be),
        .b_wdata(data_bram.data_in),
        .b_addr(data_bram.addr[BRAM_ADDR_W-1:0]),
        .b_rdata(data_bram.data_out),
    .*);

endmodule // 结束模块定义。
