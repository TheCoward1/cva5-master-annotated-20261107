// ============================================================================
// 文件：core/types_and_interfaces/external_interfaces.sv
// 类型：interface
// 名称：axi_interface
// 作用：定义 AXI、Avalon、Wishbone 和本地存储器等外部接口。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2019 Eric Matthews,  Lesley Shannon
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

interface axi_interface; // 定义 axi_interface 接口。
    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。

    logic arready; // 声明信号、变量或生成变量。
    logic arvalid; // 声明信号、变量或生成变量。
    logic [31:0] araddr; // 声明信号、变量或生成变量。
    logic [7:0] arlen; // 声明信号、变量或生成变量。
    logic [2:0] arsize; // 声明信号、变量或生成变量。
    logic [1:0] arburst; // 声明信号、变量或生成变量。
    logic [3:0] arcache; // 声明信号、变量或生成变量。
    logic [5:0] arid; // 声明信号、变量或生成变量。
    logic arlock; // 声明信号、变量或生成变量。

    //read data
    logic rready; // 声明信号、变量或生成变量。
    logic rvalid; // 声明信号、变量或生成变量。
    logic [31:0] rdata; // 声明信号、变量或生成变量。
    logic [1:0] rresp; // 声明信号、变量或生成变量。
    logic rlast; // 声明信号、变量或生成变量。
    logic [5:0] rid; // 声明信号、变量或生成变量。

    //Write channel
    //write address
    logic awready; // 声明信号、变量或生成变量。
    logic awvalid; // 声明信号、变量或生成变量。
    logic [31:0] awaddr; // 声明信号、变量或生成变量。
    logic [7:0] awlen; // 声明信号、变量或生成变量。
    logic [2:0] awsize; // 声明信号、变量或生成变量。
    logic [1:0] awburst; // 声明信号、变量或生成变量。
    logic [3:0] awcache; // 声明信号、变量或生成变量。
    logic [5:0] awid; // 声明信号、变量或生成变量。
    logic awlock; // 声明信号、变量或生成变量。

    //write data
    logic wready; // 声明信号、变量或生成变量。
    logic wvalid; // 声明信号、变量或生成变量。
    logic [31:0] wdata; // 声明信号、变量或生成变量。
    logic [3:0] wstrb; // 声明信号、变量或生成变量。
    logic wlast; // 声明信号、变量或生成变量。

    //write response
    logic bready; // 声明信号、变量或生成变量。
    logic bvalid; // 声明信号、变量或生成变量。
    logic [1:0] bresp; // 声明信号、变量或生成变量。
    logic [5:0] bid; // 声明信号、变量或生成变量。

    modport master (input arready, rvalid, rdata, rresp, rlast, rid, awready, wready, bvalid, bresp, bid,
            output arvalid, araddr, arlen, arsize, arburst, arcache, arlock, arid, rready, awvalid, awaddr, awlen, awsize, awburst, awcache, awid, awlock, // 声明输出端口。
            wvalid, wdata, wstrb, wlast, bready);

    modport slave (input arvalid, araddr, arlen, arsize, arburst, arcache, arlock,
            rready,
            awvalid, awaddr, awlen, awsize, awburst, awcache, awlock, arid,
            wvalid, wdata, wstrb, wlast, awid,
            bready,
            output arready, rvalid, rdata, rresp, rlast, rid, // 声明输出端口。
            awready,
            wready,
            bvalid, bresp, bid);

endinterface // 结束接口定义。

interface avalon_interface; // 定义 avalon_interface 接口。
    logic [31:0] addr; // 声明信号、变量或生成变量。
    logic read; // 声明信号、变量或生成变量。
    logic write; // 声明信号、变量或生成变量。
    logic lock; // 声明信号、变量或生成变量。
    logic [3:0] byteenable; // 声明信号、变量或生成变量。
    logic [31:0] readdata; // 声明信号、变量或生成变量。
    logic [31:0] writedata; // 声明信号、变量或生成变量。
    logic waitrequest; // 声明信号、变量或生成变量。
    logic readdatavalid; // 声明信号、变量或生成变量。
    logic writeresponsevalid; // 声明信号、变量或生成变量。

    modport master (input readdata, waitrequest, readdatavalid, writeresponsevalid,
            output addr, read, write, lock, byteenable, writedata); // 声明输出端口。
    modport slave (output readdata, waitrequest, readdatavalid, writeresponsevalid,
            input addr, read, write, lock, byteenable, writedata); // 声明输入端口。

endinterface // 结束接口定义。

interface wishbone_interface; // 定义 wishbone_interface 接口。
    logic [29:0] adr; // 声明信号、变量或生成变量。
    logic [31:0] dat_w; // 声明信号、变量或生成变量。
    logic [3:0] sel; // 声明信号、变量或生成变量。
    logic cyc; // 声明信号、变量或生成变量。
    logic stb; // 声明信号、变量或生成变量。
    logic we; // 声明信号、变量或生成变量。
    logic [2:0] cti; // 声明信号、变量或生成变量。
    logic [1:0] bte; // 声明信号、变量或生成变量。
    logic [31:0] dat_r; // 声明信号、变量或生成变量。
    logic ack; // 声明信号、变量或生成变量。
    logic err; // 声明信号、变量或生成变量。

    modport master (input dat_r, ack, err,
            output adr, dat_w, sel, cyc, stb, we, cti, bte); // 声明输出端口。
    modport slave (output dat_r, ack, err,
            input adr, dat_w, sel, cyc, stb, we, cti, bte); // 声明输入端口。

endinterface // 结束接口定义。

interface mem_interface; // 定义 mem_interface 接口。
    logic request; // 声明信号、变量或生成变量。
    logic[31:2] addr; // 声明信号、变量或生成变量。
    logic[4:0] rlen; //Nobody truly needs requests > 32 words；声明信号、变量或生成变量。
    logic ack; // 声明信号、变量或生成变量。

    logic rvalid; // 声明信号、变量或生成变量。
    logic[31:0] rdata; // 声明信号、变量或生成变量。
    logic[1:0] rid; // 声明信号、变量或生成变量。
    
    logic rnw; // 声明信号、变量或生成变量。
    logic rmw; // 声明信号、变量或生成变量。
    logic[3:0] wbe; // 声明信号、变量或生成变量。
    logic[31:0] wdata; // 声明信号、变量或生成变量。

    logic inv; // 声明信号、变量或生成变量。
    logic[31:2] inv_addr; // 声明信号、变量或生成变量。
    logic write_outstanding; // 声明信号、变量或生成变量。

    logic[1:0] id; // 声明信号、变量或生成变量。

    modport ro_master (output request, addr, rlen, input ack, rvalid, rdata);
    modport ro_slave (input request, addr, rlen, output ack, rvalid, rdata);
    modport rw_master (output request, addr, rlen, rnw, rmw, wbe, wdata, input ack, rvalid, rdata, inv, inv_addr, write_outstanding);
    modport rw_slave (input request, addr, rlen, rnw, rmw, wbe, wdata, output ack, rvalid, rdata, inv, inv_addr, write_outstanding);
    modport mem_master (output request, addr, rlen, rnw, rmw, wbe, wdata, id, input ack, rvalid, rdata, rid, inv, inv_addr, write_outstanding);
    modport mem_slave (input request, addr, rlen, rnw, rmw, wbe, wdata, id, output ack, rvalid, rdata, rid, inv, inv_addr, write_outstanding);

endinterface // 结束接口定义。

interface local_memory_interface; // 定义 local_memory_interface 接口。
    logic[29:0] addr; // 声明信号、变量或生成变量。
    logic en; // 声明信号、变量或生成变量。
    logic[3:0] be; // 声明信号、变量或生成变量。
    logic[31:0] data_in; // 声明信号、变量或生成变量。
    logic[31:0] data_out; // 声明信号、变量或生成变量。

    modport slave (input addr, en, be, data_in, output data_out);
    modport master (output addr, en, be, data_in, input data_out);

endinterface // 结束接口定义。
