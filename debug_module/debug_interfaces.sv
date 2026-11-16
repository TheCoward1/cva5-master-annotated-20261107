// ============================================================================
// 文件：debug_module/debug_interfaces.sv
// 类型：interface
// 名称：dmi_interface
// 作用：定义 DMI 接口以及 CPU 调试模块与 JTAG 的连接接口。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

interface dmi_interface; // 定义 dmi_interface 接口。
    logic [6:0] address; // 声明信号、变量或生成变量。
    logic [31:0] jtag_data; // 声明信号、变量或生成变量。
    logic [31:0] dmi_data; // 声明信号、变量或生成变量。
    logic new_request; // 声明信号、变量或生成变量。
    logic rnw; // 声明信号、变量或生成变量。
    logic handled; // 声明信号、变量或生成变量。
    logic [1:0] response; // 声明信号、变量或生成变量。

    modport jtag (
            input handled, response, dmi_data, // 声明输入端口。
            output address, jtag_data, new_request, rnw); // 声明输出端口。
    modport dmi (
            output handled, response, dmi_data, // 声明输出端口。
            input address, jtag_data, new_request, rnw); // 声明输入端口。
endinterface // 结束接口定义。


interface dmi_cpu_interface; // 定义 dmi_cpu_interface 接口。
    logic halt; // 声明信号、变量或生成变量。
    logic resume; // 声明信号、变量或生成变量。
    logic reset; // 声明信号、变量或生成变量。
    logic halt_ack; // 声明信号、变量或生成变量。
    logic resume_ack; // 声明信号、变量或生成变量。
    logic reset_ack; // 声明信号、变量或生成变量。
    logic halt_ack_recv; // 声明信号、变量或生成变量。
    logic resume_ack_recv; // 声明信号、变量或生成变量。
    logic running; // 声明信号、变量或生成变量。
    logic [31:0] read_data; // 声明信号、变量或生成变量。
    logic [31:0] write_data; // 声明信号、变量或生成变量。
    logic [31:0] read_write_addr; // 声明信号、变量或生成变量。
    logic [3:0] program_buffer_addr; // 声明信号、变量或生成变量。
    logic [31:0] program_buffer_data; // 声明信号、变量或生成变量。
    logic rnw; // 声明信号、变量或生成变量。
    logic rnw_ack; // 声明信号、变量或生成变量。
    logic rnw_new_request; // 声明信号、变量或生成变量。


    modport dmi (
            input halt_ack, resume_ack,program_buffer_addr, reset_ack,running,halt_ack_recv,resume_ack_recv,read_data,rnw_ack, // 声明输入端口。
            output halt, resume,program_buffer_data,reset,write_data,rnw_new_request,rnw,read_write_addr); // 声明输出端口。
    modport cpu (
            output halt_ack, resume_ack,program_buffer_addr, reset_ack,running,halt_ack_recv,resume_ack_recv,read_data,rnw_ack, // 声明输出端口。
            input halt, resume, program_buffer_data,reset,write_data,rnw_new_request,rnw,read_write_addr); // 声明输入端口。
endinterface // 结束接口定义。
