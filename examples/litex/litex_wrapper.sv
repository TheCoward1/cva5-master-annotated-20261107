// ============================================================================
// 文件：examples/litex/litex_wrapper.sv
// 类型：module
// 名称：litex_wrapper
// 作用：把 CVA5 集成到 LiteX SoC 的包装层。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2022 Eric Matthews, Lesley Shannon
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

module litex_wrapper // 定义 litex_wrapper 模块。
    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

    #(
        parameter bit [31:0] RESET_VEC = 0, // 声明可配置参数。
        parameter bit [31:0] NON_CACHABLE_L = 32'h80000000, // 声明可配置参数。
        parameter bit [31:0] NON_CACHABLE_H = 32'hFFFFFFFF, // 声明可配置参数。
        parameter int unsigned NUM_CORES = 1, // 声明可配置参数。
        parameter logic AXI = 1'b1 //Else the wishbone bus is used；声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        input logic [NUM_CORES-1:0] meip, // 声明输入端口。
        input logic [NUM_CORES-1:0] seip, // 声明输入端口。
        input logic [NUM_CORES-1:0] mtip, // 声明输入端口。
        input logic [NUM_CORES-1:0] msip, // 声明输入端口。
        input logic [63:0] mtime, // 声明输入端口。

        //Wishbone memory port (used only if configured)
        output logic [29:0] idbus_adr, // 声明输出端口。
        output logic [31:0] idbus_dat_w, // 声明输出端口。
        output logic [3:0] idbus_sel, // 声明输出端口。
        output logic idbus_cyc, // 声明输出端口。
        output logic idbus_stb, // 声明输出端口。
        output logic idbus_we, // 声明输出端口。
        output logic idbus_cti, // 声明输出端口。
        output logic idbus_bte, // 声明输出端口。
        input logic [31:0] idbus_dat_r, // 声明输入端口。
        input logic idbus_ack, // 声明输入端口。
        input logic idbus_err, // 声明输入端口。

        //AXI memory port (used only if configured)
        //AR
        input logic m_axi_arready, // 声明输入端口。
        output logic m_axi_arvalid, // 声明输出端口。
        output logic [31:0] m_axi_araddr, // 声明输出端口。
        output logic [7:0] m_axi_arlen, // 声明输出端口。
        output logic [2:0] m_axi_arsize, //Constant, 32b；声明输出端口。
        output logic [1:0] m_axi_arburst, //Constant, incrementing；声明输出端口。
        output logic [3:0] m_axi_arcache, //Constant, normal non-cacheable bufferable；声明输出端口。
        output logic [5:0] m_axi_arid, // 声明输出端口。
        //R
        output logic m_axi_rready, // 声明输出端口。
        input logic m_axi_rvalid, // 声明输入端口。
        input logic [31:0] m_axi_rdata, // 声明输入端口。
        input logic [1:0] m_axi_rresp, // 声明输入端口。
        input logic m_axi_rlast, // 声明输入端口。
        input logic [5:0] m_axi_rid, // 声明输入端口。
        //AW
        input logic m_axi_awready, // 声明输入端口。
        output logic m_axi_awvalid, // 声明输出端口。
        output logic [31:0] m_axi_awaddr, // 声明输出端口。
        output logic [7:0] m_axi_awlen, //Constant, 0；声明输出端口。
        output logic [2:0] m_axi_awsize, //Constant, 32b；声明输出端口。
        output logic [1:0] m_axi_awburst, //Constant, incrementing；声明输出端口。
        output logic [3:0] m_axi_awcache, //Constant, normal non-cacheable bufferable；声明输出端口。
        output logic [5:0] m_axi_awid, // 声明输出端口。
        //W
        input logic m_axi_wready, // 声明输入端口。
        output logic m_axi_wvalid, // 声明输出端口。
        output logic [31:0] m_axi_wdata, // 声明输出端口。
        output logic [3:0] m_axi_wstrb, // 声明输出端口。
        output logic m_axi_wlast, // 声明输出端口。
        //B
        output logic m_axi_bready, // 声明输出端口。
        input logic m_axi_bvalid, // 声明输入端口。
        input logic [1:0] m_axi_bresp, // 声明输入端口。
        input logic [5:0] m_axi_bid // 声明输入端口。
    );

    localparam wb_group_config_t STANDARD_WB_GROUP_CONFIG = '{ // 声明局部常量。
        0 : '{0: ALU_ID, default : NON_WRITEBACK_ID},
        1 : '{0: LS_ID, default : NON_WRITEBACK_ID},
        2 : '{0: MUL_ID, 1: DIV_ID, 2: CSR_ID, 3: CUSTOM_ID, default : NON_WRITEBACK_ID},
        default : '{default : NON_WRITEBACK_ID} // 执行默认分支。
    };

    //Unused interfaces
    axi_interface axi[NUM_CORES-1:0]();
    avalon_interface avalon[NUM_CORES-1:0]();
    wishbone_interface dwishbone[NUM_CORES-1:0]();
    wishbone_interface iwishbone[NUM_CORES-1:0]();
    local_memory_interface instruction_bram[NUM_CORES-1:0]();
    local_memory_interface data_bram[NUM_CORES-1:0]();

    //Interrupts
    interrupt_t[NUM_CORES-1:0] s_interrupt;
    interrupt_t[NUM_CORES-1:0] m_interrupt;

    //Memory interfaces for each core
    mem_interface mem[NUM_CORES-1:0]();
    
    generate for (genvar i = 0; i < NUM_CORES; i++) begin : gen_cores // 开始生成块，在编译期展开硬件结构。
        localparam cpu_config_t STANDARD_CONFIG_I = '{ // 声明局部常量。
            //ISA options
            MODES : MSU,
            INCLUDE_UNIT : '{
                MUL : 1,
                DIV : 1,
                CSR : 1,
                FPU : 0,
                CUSTOM : 0,
                default: '0 // 执行默认分支。
            },
            INCLUDE_IFENCE : 1,
            INCLUDE_AMO : 1,
            INCLUDE_CBO : 0,
            //CSR constants
            CSRS : '{
                MACHINE_IMPLEMENTATION_ID : 0,
                CPU_ID : i,
                RESET_VEC : RESET_VEC,
                RESET_TVEC : 32'h00000000,
                MCONFIGPTR : '0,
                INCLUDE_ZICNTR : 1,
                INCLUDE_ZIHPM : 1,
                INCLUDE_SSTC : 1,
                INCLUDE_SMSTATEEN : 1
            },
            //Memory Options
            SQ_DEPTH : 4,
            INCLUDE_FORWARDING_TO_STORES : 1,
            AMO_UNIT : '{
                LR_WAIT : 8,
                RESERVATION_WORDS : 8
            },
            INCLUDE_ICACHE : 1,
            ICACHE_ADDR : '{
                L : 32'h00000000,
                H : 32'h7FFFFFFF
            },
            ICACHE : '{
                LINES : 512,
                LINE_W : 8,
                WAYS : 2,
                USE_EXTERNAL_INVALIDATIONS : 0,
                USE_NON_CACHEABLE : 0,
                NON_CACHEABLE : '{
                    L: NON_CACHABLE_L,
                    H: NON_CACHABLE_H
                }
            },
            ITLB : '{
                WAYS : 2,
                DEPTH : 64
            },
            INCLUDE_DCACHE : 1,
            DCACHE_ADDR : '{
                L : 32'h00000000,
                H : 32'hFFFFFFFF
            },
            DCACHE : '{
                LINES : 512,
                LINE_W : 8,
                WAYS : 2,
                USE_EXTERNAL_INVALIDATIONS : 1,
                USE_NON_CACHEABLE : 1,
                NON_CACHEABLE : '{
                    L: NON_CACHABLE_L,
                    H: NON_CACHABLE_H
                }
            },
            DTLB : '{
                WAYS : 2,
                DEPTH : 64
            },
            INCLUDE_ILOCAL_MEM : 0,
            ILOCAL_MEM_ADDR : '{
                L : 32'h80000000,
                H : 32'h8FFFFFFF
            },
            INCLUDE_DLOCAL_MEM : 0,
            DLOCAL_MEM_ADDR : '{
                L : 32'h80000000,
                H : 32'h8FFFFFFF
            },
            INCLUDE_IBUS : 0,
            IBUS_ADDR : '{
                L : 32'h00000000,
                H : 32'hFFFFFFFF
            },
            INCLUDE_PERIPHERAL_BUS : 0,
            PERIPHERAL_BUS_ADDR : '{
                L : 32'h00000000,
                H : 32'hFFFFFFFF
            },
            PERIPHERAL_BUS_TYPE : WISHBONE_BUS,
            //Branch Predictor Options
            INCLUDE_BRANCH_PREDICTOR : 1,
            BP : '{
                WAYS : 2,
                ENTRIES : 512,
                RAS_ENTRIES : 8
            },
            //Writeback Options
            NUM_WB_GROUPS : 3,
            WB_GROUP : STANDARD_WB_GROUP_CONFIG
        };

        assign m_interrupt[i].software = msip[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_interrupt[i].timer = mtip[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_interrupt[i].external = meip[i]; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign s_interrupt[i].software = 0; //Not possible；执行连续赋值，把组合逻辑连接到目标信号。
        assign s_interrupt[i].timer = 0; //Internal；执行连续赋值，把组合逻辑连接到目标信号。
        assign s_interrupt[i].external = seip[i]; // 执行连续赋值，把组合逻辑连接到目标信号。

        cva5 #(.CONFIG(STANDARD_CONFIG_I)) cpu(
            .instruction_bram(instruction_bram[i]),
            .data_bram(data_bram[i]),
            .m_axi(axi[i]),
            .m_avalon(avalon[i]),
            .dwishbone(dwishbone[i]),
            .iwishbone(iwishbone[i]),
            .mem(mem[i]),
            .mtime(mtime),
            .s_interrupt(s_interrupt[i]),
            .m_interrupt(m_interrupt[i]),
        .*);

    end endgenerate // 结束语句块。


    //Final memory interface
    generate if (AXI) begin : gen_axi_if // 开始生成块，在编译期展开硬件结构。
        axi_interface m_axi();

        //Mux requests from one or more cores onto the AXI bus
        axi_adapter #(.NUM_CORES(NUM_CORES)) axi_adapter (
            .mems(mem),
            .axi(m_axi),
        .*);

        assign m_axi.arready = m_axi_arready; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_arvalid = m_axi.arvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_araddr = m_axi.araddr; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_arlen = m_axi.arlen; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_arsize = m_axi.arsize; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_arburst = m_axi.arburst; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_arcache = m_axi.arcache; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_arid = m_axi.arid; // 执行连续赋值，把组合逻辑连接到目标信号。

        assign m_axi_rready = m_axi.rready; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi.rvalid = m_axi_rvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi.rdata  = m_axi_rdata; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi.rresp = m_axi_rresp; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi.rlast = m_axi_rlast; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi.rid  = m_axi_rid; // 执行连续赋值，把组合逻辑连接到目标信号。

        assign m_axi.awready = m_axi_awready; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_awvalid = m_axi.awvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_awaddr = m_axi.awaddr; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_awlen = m_axi.awlen; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_awsize = m_axi.awsize; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_awburst = m_axi.awburst; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_awcache = m_axi.awcache; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_awid = m_axi.awid; // 执行连续赋值，把组合逻辑连接到目标信号。

        assign m_axi.wready = m_axi_wready; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_wvalid = m_axi.wvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_wdata = m_axi.wdata; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_wstrb = m_axi.wstrb; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi_wlast = m_axi.wlast; // 执行连续赋值，把组合逻辑连接到目标信号。

        assign m_axi_bready = m_axi.bready; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi.bvalid = m_axi_bvalid; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi.bresp = m_axi_bresp; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign m_axi.bid =  m_axi_bid; // 执行连续赋值，把组合逻辑连接到目标信号。
    end else begin : gen_wishbone_if // 结束语句块。
        wishbone_interface idwishbone();

        //Mux requests from one or more cores onto the wishbone bus
        wishbone_adapter #(.NUM_CORES(NUM_CORES)) wb_adapter (
            .mems(mem),
            .wishbone(idwishbone),
        .*);

        assign idbus_adr = idwishbone.adr; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign idbus_dat_w = idwishbone.dat_w; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign idbus_sel = idwishbone.sel; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign idbus_cyc = idwishbone.cyc; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign idbus_stb = idwishbone.stb; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign idbus_we = idwishbone.we; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign idbus_cti = idwishbone.cti; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign idbus_bte = idwishbone.bte; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign idwishbone.dat_r = idbus_dat_r; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign idwishbone.ack = idbus_ack; // 执行连续赋值，把组合逻辑连接到目标信号。
        assign idwishbone.err = idbus_err; // 执行连续赋值，把组合逻辑连接到目标信号。
    end endgenerate // 结束语句块。

endmodule // 结束模块定义。
