// ============================================================================
// 文件：debug_module/debug_module.sv
// 类型：module
// 名称：debug_module
// 作用：实现 RISC-V Debug Module，支持 halt、resume、抽象命令和调试寄存器。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

import debug_cfg_types::*; // 导入包或命名空间：debug_cfg_types::*;。

module debug_module ( // 定义 debug_module 模块。
        input logic rst, // 声明输入端口。
        input logic clk, // 声明输入端口。

        dmi_cpu_interface.dmi debug[NUM_CPUS-1:0],
        dmi_interface.dmi jtag,
        
        //SIMULATION ONLY:
        output DM_Status_t DMS_out, // 声明输出端口。
        output DM_control_t DMC_out, // 声明输出端口。
        output abstract_control_and_status_t ACS_out // 声明输出端口。
        );

    genvar index; // 声明信号、变量或生成变量。
    DM_Status_t DMS;
    
    assign DMS.zero1 = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign DMS.zero2 = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign DMS.zero3 = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign DMS.cfgstrvalid = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign DMS.impebreak = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    //DMS Constants
    assign DMS.authenticated = 1;//no authentication；执行连续赋值，把组合逻辑连接到目标信号。
    assign DMS.authbusy = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign DMS.version = 2; //version 0.13；执行连续赋值，把组合逻辑连接到目标信号。
    assign DMS_out = DMS; // 执行连续赋值，把组合逻辑连接到目标信号。
    DM_control_t DMC;
    //assign DMC.zero1 = 0;
    //assign DMC.zero2 = 0;

    //read-only reg
    //same for all cva5 cores

    hart_info_t hart_info;
    assign hart_info.zero1 = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign hart_info.zero2 = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign hart_info.nscratch = 2; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign hart_info.dataaccess = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign hart_info.datasize = 3; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign hart_info.dataaddr = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    assign DMC_out = DMC; // 执行连续赋值，把组合逻辑连接到目标信号。
    //read-only reg
    //Only support < 32 cores
    logic [31:0] halt_summary; // 声明信号、变量或生成变量。
    assign halt_summary[31:1] = '0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign halt_summary[0] = DMS.anyhalted; // 执行连续赋值，把组合逻辑连接到目标信号。

    //read-write reg
    //Only support < 32 cores
    logic [31:0] hart_array_window_select; // 声明信号、变量或生成变量。
    //assign hart_array_window_select = 0;

    //read-write reg
    logic [31:0] hart_array_window; // 声明信号、变量或生成变量。

    //read-only and read-write reg

    abstract_control_and_status_t ABS_CS;
    assign ABS_CS.zero1 = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ABS_CS.zero2 = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ABS_CS.zero3 = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ABS_CS.zero4 = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ABS_CS.datacount = 2; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ABS_CS.progsize = 16; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign ACS_out = ABS_CS; // 执行连续赋值，把组合逻辑连接到目标信号。
    //write-only reg
// 定义类型别名或枚举/结构类型。
    typedef struct packed{
        logic [31:24] cmdtype; // 声明信号、变量或生成变量。
        logic [23:0] control; // 声明信号、变量或生成变量。
    } abstract_command_t;
    abstract_command_t ABS_COMMAND;

    //abstract command autoexec, unused

    //read-only
    logic[31:0] cfg_addr0; // 声明信号、变量或生成变量。

    //read-write
    logic[31:0] abstract_data [2:0]; // 声明信号、变量或生成变量。

    //LUT-RAM
    logic[31:0] program_buffer [7:0]; // 声明信号、变量或生成变量。
    logic[31:0] program_buffer_output; // 声明信号、变量或生成变量。

    logic [31:0] data_out; // 声明信号、变量或生成变量。
    
    logic write_request; // 声明信号、变量或生成变量。
    logic new_DMC_req; // 声明信号、变量或生成变量。
    //Implementation
    //////////////////////////////////////////////////////////////////
    
    assign write_request = jtag.new_request & ~jtag.rnw; // 执行连续赋值，把组合逻辑连接到目标信号。

   
    //DMC
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            DMC.dmactive <= 0;
            DMC <= 0;
            new_DMC_req <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
        DMC.dmactive <= 1;
            if (write_request) begin // 执行条件判断，满足条件时进入对应分支。
                if (jtag.address == DEBUG_MODULE_CONTROL) begin // 执行条件判断，满足条件时进入对应分支。
                    DMC <= jtag.jtag_data;
                    new_DMC_req <= 1;
                end // 结束语句块。
            end // 结束语句块。
            else begin // 执行否则分支。
                new_DMC_req <= 0;
            end // 结束语句块。
        end; // 结束语句块。
     end // 结束语句块。
    //Write to registers
    //////////////////
    //HART_ARRAY_WINDOW_SELECT
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
    if (rst) // 执行条件判断，满足条件时进入对应分支。
        hart_array_window_select <= 0;
    else // 执行否则分支。
        if(write_request & jtag.address == HART_ARRAY_WINDOW_SELECT) // 执行条件判断，满足条件时进入对应分支。
            hart_array_window_select <= jtag.jtag_data;
     end // 结束语句块。
    
    //HART_ARRAY_WINDOW
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
    if (rst) // 执行条件判断，满足条件时进入对应分支。
        hart_array_window <= 0;
    else // 执行否则分支。
        if(write_request & jtag.address == HART_ARRAY_WINDOW) // 执行条件判断，满足条件时进入对应分支。
            hart_array_window <= jtag.jtag_data;
    end // 结束语句块。
    //Selected Harts (hasel,hartsel)-----------------------------------------
    logic[31:0] hartsel_mask; // 声明信号、变量或生成变量。
    logic[HARTSELLEN:0] selected_hart; // 声明信号、变量或生成变量。
    assign selected_hart = {DMC.hartselhi,DMC.hartsello}; //Index-based；执行连续赋值，把组合逻辑连接到目标信号。
    generate // 开始生成块，在编译期展开硬件结构。
    
    //for (index = 0; index < NUM_CPUS; index=index+1) begin
    for (index = 0; index < 32; index=index+1) begin // 执行循环或遍历。
        always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
            if(selected_hart == index) // 执行条件判断，满足条件时进入对应分支。
                hartsel_mask[index] <= 1; //convert index to mask
            else // 执行否则分支。
                hartsel_mask[index] <= 0;
        end // 结束语句块。
    end // 结束语句块。
    endgenerate // 结束生成块。
    
    logic[31:0] selected_harts; // 声明信号、变量或生成变量。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if(~DMC.hasel) // 执行条件判断，满足条件时进入对应分支。
            selected_harts <= hartsel_mask;
        else // 执行否则分支。
            selected_harts <= hartsel_mask | hart_array_window;
    end // 结束语句块。
    
    //ABS_COMMAND
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
    if (rst) // 执行条件判断，满足条件时进入对应分支。
        ABS_COMMAND <= 0;
    else // 执行否则分支。
        if(write_request & jtag.address == ABSTRACT_COMMAND) // 执行条件判断，满足条件时进入对应分支。
            ABS_COMMAND <= jtag.jtag_data;
    end // 结束语句块。
    //ABS_DATA0------------return data for abstract commands
    logic[31:0][NUM_CPUS-1:0] abs_cmd_return; // 声明信号、变量或生成变量。
    logic[NUM_CPUS-1:0] abs_cmd_sig; // 声明信号、变量或生成变量。
    generate // 开始生成块，在编译期展开硬件结构。
    for (index = 0; index < NUM_CPUS; index=index+1) begin // 执行循环或遍历。
        always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
            if (rst) begin // 执行条件判断，满足条件时进入对应分支。
                abs_cmd_return[index] <= 0;
                abs_cmd_sig[index] <= 0;
            end // 结束语句块。
            else begin // 执行否则分支。
                if(debug[index].rnw_ack && debug[index].rnw) begin // 执行条件判断，满足条件时进入对应分支。
                    abs_cmd_return[index] <= debug[index].read_data;
                    abs_cmd_sig[index] <= 1;
                end // 结束语句块。
                else begin // 执行否则分支。
                    abs_cmd_return[index] <= 0;
                    abs_cmd_sig[index] <= 0;
                end // 结束语句块。
            end // 结束语句块。
        end // 结束语句块。
    end // 结束语句块。
    endgenerate // 结束生成块。
    
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
    if (rst) // 执行条件判断，满足条件时进入对应分支。
        abstract_data[0] <= 0;
    else // 执行否则分支。
        if(write_request & jtag.address == ABSTRACT_DATA0) // 执行条件判断，满足条件时进入对应分支。
            abstract_data[0] <= jtag.jtag_data;
        else if(|abs_cmd_sig) // 执行否则如果分支的条件判断。
            abstract_data[0] <= abs_cmd_return[selected_hart]; //PROBLEM: THIS NEEDS TO BE OBTAINED FROM THE CORRECT PROCESSOR
    end // 结束语句块。
    //ABS_DATA1
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
    if (rst) // 执行条件判断，满足条件时进入对应分支。
        abstract_data[1] <= 0;
    else // 执行否则分支。
        if(write_request & jtag.address == ABSTRACT_DATA1) // 执行条件判断，满足条件时进入对应分支。
            abstract_data[1] <= jtag.jtag_data;
    end // 结束语句块。
    
    //ABS_DATA2
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
    if (rst) // 执行条件判断，满足条件时进入对应分支。
        abstract_data[2] <= 0;
    else // 执行否则分支。
        if(write_request & jtag.address == ABSTRACT_DATA2) // 执行条件判断，满足条件时进入对应分支。
            abstract_data[2] <= jtag.jtag_data;
    end // 结束语句块。
    //////////////////
    
    //program_buffer
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (write_request && jtag.address >= 7'h20 &&  jtag.address < 7'h30) // 执行条件判断，满足条件时进入对应分支。
            program_buffer[jtag.address[3:0]] <= jtag.jtag_data;
    end // 结束语句块。
    assign program_buffer_output = program_buffer[jtag.address[3:0]]; // 执行连续赋值，把组合逻辑连接到目标信号。

    //read mux
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        case(jtag.address) // 开始多分支选择，根据表达式选择对应分支。
            ABSTRACT_DATA0 : data_out <= abstract_data[0];
            ABSTRACT_DATA1  : data_out <= abstract_data[1];
            ABSTRACT_DATA2  : data_out <= abstract_data[2];
            DEBUG_MODULE_CONTROL : data_out <= DMC;
            DEBUG_MODULE_STATUS  : data_out <= DMS;
            HART_INFO  : data_out <= hart_info;
            HALT_SUMMARY : data_out <= halt_summary;
            HART_ARRAY_WINDOW_SELECT : data_out <= hart_array_window_select;
            HART_ARRAY_WINDOW : data_out <= hart_array_window;
            ABSTRACT_CONTROL_AND_STATUS : data_out <= ABS_CS;
            ABSTRACT_COMMAND : data_out <= ABS_COMMAND;
            ABSTRACT_COMMAND_AUTOEXEC : data_out <= '0;
            CONFIG_STRING_ADDR0 : data_out <= '0;
            CONFIG_STRING_ADDR1 : data_out <= '0;
            CONFIG_STRING_ADDR2 : data_out <= '0;
            CONFIG_STRING_ADDR3 : data_out <= '0;
            PROGRAM_BUFFER0 : data_out <= program_buffer_output;
            PROGRAM_BUFFER1 : data_out <= program_buffer_output;
            PROGRAM_BUFFER2 : data_out <= program_buffer_output;
            PROGRAM_BUFFER3 : data_out <= program_buffer_output;
            PROGRAM_BUFFER4 : data_out <= program_buffer_output;
            PROGRAM_BUFFER5 : data_out <= program_buffer_output;
            PROGRAM_BUFFER6 : data_out <= program_buffer_output;
            PROGRAM_BUFFER7 : data_out <= program_buffer_output;
            PROGRAM_BUFFER8 : data_out <= program_buffer_output;
            PROGRAM_BUFFER9 : data_out <= program_buffer_output;
            PROGRAM_BUFFER10 : data_out <= program_buffer_output;
            PROGRAM_BUFFER11 : data_out <= program_buffer_output;
            PROGRAM_BUFFER12 : data_out <= program_buffer_output;
            PROGRAM_BUFFER13 : data_out <= program_buffer_output;
            PROGRAM_BUFFER14 : data_out <= program_buffer_output;
            PROGRAM_BUFFER15 : data_out <= program_buffer_output;
            default :  data_out <= '0; // 执行默认分支。
        endcase // 结束多分支选择。
    end // 结束语句块。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        jtag.handled <= jtag.new_request;
    end // 结束语句块。

    assign jtag.response = DMI_STATUS_SUCCESS; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        jtag.dmi_data <= data_out;
    end // 结束语句块。



//Are Cores Running Check-------------------------------------------------------------------------
logic [NUM_CPUS-1:0] all_running_array; // 声明信号、变量或生成变量。
generate // 开始生成块，在编译期展开硬件结构。
for (index = 0; index < NUM_CPUS; index=index+1) begin // 执行循环或遍历。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
         all_running_array[index] <= debug[index].running;
    end // 结束语句块。
end // 结束语句块。
endgenerate // 结束生成块。

always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
if (rst) begin // 执行条件判断，满足条件时进入对应分支。
    DMS.allrunning <= 0;
    DMS.anyrunning <= 0;
end // 结束语句块。
else // 执行否则分支。
    DMS.allrunning  <= &(all_running_array | ~selected_harts) && |selected_harts;
    DMS.anyrunning <= |(all_running_array & selected_harts);
end // 结束语句块。

//Hart Resets Requests-------------------------------------------------------------------------
//Requests & Acknowledgements-----------------
generate // 开始生成块，在编译期展开硬件结构。
for (index = 0; index < NUM_CPUS; index=index+1) begin // 执行循环或遍历。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            debug[index].reset <= 0;
        else begin // 执行否则分支。
            if(DMC.hartreset && new_DMC_req) begin //Send New Requests；执行条件判断，满足条件时进入对应分支。
                debug[index].reset <= selected_harts[index];

            end // 结束语句块。
            else if(debug[index].reset_ack == 1 || DMC.hartreset == 0) begin //Wait for Ack OR Debugger has unset the reset bit；执行否则如果分支的条件判断。
                debug[index].reset <= 0;
            end // 结束语句块。
        end // 结束语句块。
    end // 结束语句块。
end // 结束语句块。
endgenerate // 结束生成块。
//Status Register Updates-----------------
always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
if (rst) begin // 执行条件判断，满足条件时进入对应分支。
    DMS.allhavereset <= 0;
    DMS.anyhavereset <= 0;
end // 结束语句块。
else // 执行否则分支。
    if(DMC.hartreset) begin // 执行条件判断，满足条件时进入对应分支。
       DMS.allhavereset <= 1;
       DMS.anyhavereset <= 1;
    end // 结束语句块。
    else if(DMC.ackhavereset)begin //clear only if Debugger has acknowledge the reset；执行否则如果分支的条件判断。
        DMS.allhavereset  <= 0;
        DMS.anyhavereset <= 0;
    end // 结束语句块。
end // 结束语句块。

//Halt RequestsRequests-------------------------------------------------------------------------
//Requests & Acknowledgements-----------------
generate // 开始生成块，在编译期展开硬件结构。
for (index = 0; index < NUM_CPUS; index=index+1) begin // 执行循环或遍历。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            debug[index].halt <= 0;
        else begin // 执行否则分支。
            if(DMC.haltreq && new_DMC_req) begin //Send New Requests；执行条件判断，满足条件时进入对应分支。
                debug[index].halt <= selected_harts[index];
           end // 结束语句块。
           else if(ABS_COMMAND.cmdtype == 1 && debug[index].running) //From Abstract Command；执行否则如果分支的条件判断。
                debug[index].halt <= hartsel_mask[index];
            else if(debug[index].halt_ack == 1) begin //Wait for Ack；执行否则如果分支的条件判断。
                debug[index].halt <= 0;
            end // 结束语句块。
        end // 结束语句块。
    end // 结束语句块。
end // 结束语句块。
endgenerate // 结束生成块。
//Status Register Updates--------------------
always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
if (rst) begin // 执行条件判断，满足条件时进入对应分支。
    DMS.allhalted <= 0;
    DMS.anyhalted <= 0;
end // 结束语句块。
else // 执行否则分支。
    DMS.allhalted  <= &(~all_running_array | ~selected_harts) && |selected_harts;
    DMS.anyhalted <= |(~all_running_array & selected_harts);
end // 结束语句块。

//Resume Requests-------------------------------------------------------------------------
//Requests & Acknowledgements-----------------
generate // 开始生成块，在编译期展开硬件结构。
for (index = 0; index < NUM_CPUS; index=index+1) begin // 执行循环或遍历。
    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) // 执行条件判断，满足条件时进入对应分支。
            debug[index].resume <= 0;
        else begin // 执行否则分支。
            if(DMC.resumereq && new_DMC_req && ~DMC.haltreq) begin //Send New Requests；执行条件判断，满足条件时进入对应分支。
                debug[index].resume <= selected_harts[index];

            end // 结束语句块。
            else if(debug[index].resume_ack == 1) begin //Wait for Ack；执行否则如果分支的条件判断。
                debug[index].resume <= 0;
            end // 结束语句块。
        end // 结束语句块。
    end // 结束语句块。
end // 结束语句块。
endgenerate // 结束生成块。
//Status Register Updates--------------------NOTE: This checks for the ACKS not the current status
logic [NUM_CPUS-1:0] all_resume_ack_array; // 声明信号、变量或生成变量。
generate // 开始生成块，在编译期展开硬件结构。
for (index = 0; index < NUM_CPUS; index=index+1) begin // 执行循环或遍历。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if(DMC.resumereq && selected_harts[index]  && ~DMC.haltreq && new_DMC_req) //if a new request is sent, reset the bit；执行条件判断，满足条件时进入对应分支。
            all_resume_ack_array[index] <= 0;
        if(debug[index].resume_ack) //only set bit if the ack has been recieved；执行条件判断，满足条件时进入对应分支。
            all_resume_ack_array[index] <= 1;
    end // 结束语句块。
end // 结束语句块。
endgenerate // 结束生成块。

always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
if (rst) begin // 执行条件判断，满足条件时进入对应分支。
    DMS.allresumeack <= 0;
    DMS.anyresumeack <= 0;
end // 结束语句块。
else // 执行否则分支。
    if(DMC.resumereq) begin // 执行条件判断，满足条件时进入对应分支。
        DMS.allresumeack  <= &(all_resume_ack_array|~selected_harts) && |selected_harts;
        DMS.anyresumeack <= |(all_resume_ack_array & selected_harts);
    end // 结束语句块。
    else begin // Do I need to set this to 0?；执行否则分支。
        DMS.allresumeack <= 0;
        DMS.anyresumeack <= 0;
    end // 结束语句块。
        
end // 结束语句块。
//ALL/ANY nonexistent,allunavailallunavail------------

logic [31:0] non_exist_array; // 声明信号、变量或生成变量。
generate // 开始生成块，在编译期展开硬件结构。
for (index = 0; index < 32; index=index+1) begin // 执行循环或遍历。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if(index > NUM_CPUS) // 执行条件判断，满足条件时进入对应分支。
            non_exist_array[index] <= 1;
        else // 执行否则分支。
            non_exist_array[index] <= 0;
    end // 结束语句块。
end // 结束语句块。
endgenerate // 结束生成块。

always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
if (rst) begin // 执行条件判断，满足条件时进入对应分支。
    DMS.allnonexistent <= 0;
    DMS.anynonexistent <= 0;
    DMS.allunavail <= 0;
    DMS.anyunavail <= 0;
end // 结束语句块。
else begin // 执行否则分支。
    DMS.allnonexistent  <= &(non_exist_array|~selected_harts) && |selected_harts;
    DMS.anynonexistent <= |(non_exist_array & selected_harts);
    //DMS.allunavail  <= &(non_exist_array|~selected_harts) && |selected_harts;
    //DMS.anyunavail <= |(non_exist_array & selected_harts);   
end // 结束语句块。
end // 结束语句块。

//Abtract Commands----------------------------------------------------------------
//TO-DO: DID WE IMPLEMENT POSTEXEC
logic new_ABSTRACT_req; // 声明信号、变量或生成变量。
always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
if (rst) begin // 执行条件判断，满足条件时进入对应分支。
    new_ABSTRACT_req <= 0;
end // 结束语句块。
else begin // 执行否则分支。
    if (write_request && jtag.address == ABSTRACT_COMMAND) begin // 执行条件判断，满足条件时进入对应分支。
        new_ABSTRACT_req <= 1;
    end // 结束语句块。
    else begin // 执行否则分支。
        new_ABSTRACT_req <= 0;
    end // 结束语句块。
end // 结束语句块。
end // 结束语句块。

logic [NUM_CPUS-1:0] abstract_ack_array; // 声明信号、变量或生成变量。
generate // 开始生成块，在编译期展开硬件结构。
for (index = 0; index < NUM_CPUS; index=index+1) begin // 执行循环或遍历。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        if(new_ABSTRACT_req && hartsel_mask[index]) //if a new request is sent, reset the bit；执行条件判断，满足条件时进入对应分支。
            abstract_ack_array[index] <= 0;
        if(debug[index].rnw_ack) //only set bit if the ack has been recieved；执行条件判断，满足条件时进入对应分支。
            abstract_ack_array[index] <= 1;
    end // 结束语句块。
end // 结束语句块。
endgenerate // 结束生成块。

//Requests-----------------
logic[31:0][NUM_CPUS-1:0] program_buffer_addr; // 声明信号、变量或生成变量。
logic execute_program_buffer; // 声明信号、变量或生成变量。
logic [NUM_CPUS-1:0]execute_program_buffer_postexec; // 声明信号、变量或生成变量。
logic [NUM_CPUS-1:0]execute_program_buffer_auto; // 声明信号、变量或生成变量。
logic [NUM_CPUS-1:0]new_execute_program_buffer_req; // 声明信号、变量或生成变量。
assign execute_program_buffer = |execute_program_buffer_postexec | |execute_program_buffer_auto; //note do we need a hartsel_mask here?；执行连续赋值，把组合逻辑连接到目标信号。

generate // 开始生成块，在编译期展开硬件结构。
for (index = 0; index < NUM_CPUS; index=index+1) begin // 执行循环或遍历。
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        program_buffer_addr[index] <= debug[index].program_buffer_addr;
    end // 结束语句块。
end // 结束语句块。
endgenerate // 结束生成块。
logic halted_hartsel; // 声明信号、变量或生成变量。
assign halted_hartsel = |(hartsel_mask && ~all_running_array); // 执行连续赋值，把组合逻辑连接到目标信号。
always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
    if (rst) begin // 执行条件判断，满足条件时进入对应分支。
        ABS_CS.busy <= 0;
        ABS_CS.cmderr <= 0;
    end // 结束语句块。
    else begin // 执行否则分支。
        if(ABS_COMMAND.cmdtype == 0 && ABS_COMMAND[22:20] != 2 && new_ABSTRACT_req) begin //If the size of the command is > 32；执行条件判断，满足条件时进入对应分支。
            ABS_CS.busy <= 0;
            ABS_CS.cmderr <= 2;
        end // 结束语句块。
        else if(ABS_COMMAND.cmdtype == 0 &&  (ABS_COMMAND[15:0] !=  DEBUG_CSR && ABS_COMMAND[15:0] != DEBUG_PC && ABS_COMMAND[15:0] != DEBUG_SCRATCH1 && ABS_COMMAND[15:0] != DEBUG_SCRATCH2) && new_ABSTRACT_req) begin //Address not readable；执行否则如果分支的条件判断。
            ABS_CS.busy <= 0;
            ABS_CS.cmderr <= 2;
        end // 结束语句块。
        else if(ABS_COMMAND.cmdtype == 1 && halted_hartsel) begin //If quick access is the abstract command, but the core is already halted；执行否则如果分支的条件判断。
            ABS_CS.busy <= 0;
            ABS_CS.cmderr <= 2;
        end // 结束语句块。
        else if(ABS_COMMAND.cmdtype == 0 && ABS_COMMAND[17] && ~ABS_COMMAND[16] && new_ABSTRACT_req) begin //Transfer；执行否则如果分支的条件判断。
            ABS_CS.busy <= 1;
            ABS_CS.cmderr <= 0;
        end // 结束语句块。
        else if(ABS_COMMAND.cmdtype == 0 && ABS_COMMAND[17] && ABS_COMMAND[16] && new_ABSTRACT_req) begin //Write；执行否则如果分支的条件判断。
            ABS_CS.busy <= 1;
            ABS_CS.cmderr <= 0;
        end // 结束语句块。
        else if(ABS_COMMAND.cmdtype == 1 && ABS_COMMAND[17] && ABS_COMMAND[16] && new_ABSTRACT_req) begin //Write；执行否则如果分支的条件判断。
            ABS_CS.busy <= 1;
            ABS_CS.cmderr <= 0;
        end // 结束语句块。
        else if(|abstract_ack_array && ~ABS_COMMAND[18]) begin //CASE 1: no execution of program buffer；执行否则如果分支的条件判断。
            ABS_CS.busy <= 0;
            ABS_CS.cmderr <= 0;
        end // 结束语句块。
        else if(|abstract_ack_array && ABS_COMMAND[18] && program_buffer_addr[selected_hart] == 31'h2F) begin //CASE 2: execution of program buffer. WE have finished the Program Buffer；执行否则如果分支的条件判断。
            ABS_CS.busy <= 0;
            ABS_CS.cmderr <= 0;
        end // 结束语句块。
    end // 结束语句块。
end // 结束语句块。


generate // 开始生成块，在编译期展开硬件结构。
for (index = 0; index < NUM_CPUS; index=index+1) begin // 执行循环或遍历。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            debug[index].rnw <= 0;
            debug[index].rnw_new_request <= 0;
            execute_program_buffer_postexec[index] <= 0;
            execute_program_buffer_auto [index] <= 0;
            debug[index].write_data <= 0;
            debug[index].read_write_addr <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            execute_program_buffer_postexec[index] <= 0; //Only 1 when rnw_ack has been recieved for the first time and postexec is true
            if(execute_program_buffer) begin //happens in the next cycle after directly above code；执行条件判断，满足条件时进入对应分支。
                debug[index].write_data <= 31'h20; //write data always comes from data0 register for 32-bits
                debug[index].read_write_addr <= 16'h7b1;
                debug[index].rnw <= 0;
                debug[index].rnw_new_request <= hartsel_mask[index];
                new_execute_program_buffer_req[index] <= 0;
            end // 结束语句块。
            else if(ABS_COMMAND.cmdtype == 0 && ABS_COMMAND[17] && ~ABS_COMMAND[16] && new_ABSTRACT_req) begin //Read/Transfer；执行否则如果分支的条件判断。
                debug[index].rnw <= 1;
                debug[index].rnw_new_request <= hartsel_mask[index]; //WE HAVE TO USE ONLY THE HARTSEL MASK AND NOT THE ARRAY MASK
                debug[index].write_data <= abstract_data[0]; //write data always comes from data0 register for 32-bits
                debug[index].read_write_addr <= ABS_COMMAND[15:0];
                if(ABS_COMMAND[18]) // 执行条件判断，满足条件时进入对应分支。
                   new_execute_program_buffer_req[index] <= 1;
            end // 结束语句块。
            else if(ABS_COMMAND.cmdtype == 0 && ABS_COMMAND[17] && ABS_COMMAND[16] && new_ABSTRACT_req) begin //Write；执行否则如果分支的条件判断。
                debug[index].rnw <= 0;
                debug[index].rnw_new_request <= hartsel_mask[index]; //WE HAVE TO USE ONLY THE HARTSEL MASK AND NOT THE ARRAY MASK
                debug[index].write_data <= abstract_data[0]; //write data always comes from data0 register for 32-bits
                debug[index].read_write_addr <= ABS_COMMAND[15:0];
                if(ABS_COMMAND[18]) // 执行条件判断，满足条件时进入对应分支。
                   new_execute_program_buffer_req[index] <= 1;
            end // 结束语句块。
            else if(debug[index].rnw_ack) begin // 执行否则如果分支的条件判断。
                debug[index].rnw_new_request <= 0;
                if(ABS_COMMAND[18]) begin //postexec；执行条件判断，满足条件时进入对应分支。
                    if(execute_program_buffer_postexec[index] == 0 && execute_program_buffer_auto [index]== 0 && new_execute_program_buffer_req[index]) begin // 执行条件判断，满足条件时进入对应分支。
                        execute_program_buffer_postexec[index] <= 1; // activation signal
                        new_execute_program_buffer_req[index] <= 0;
                        //execute_program_buffer <= 1; //CANT DO THIS SINCE IT'S A FOR LOOP
                    end // 结束语句块。
                    else begin // 执行否则分支。
                        //execute_program_buffer <= 1; //CAN'T DO THIS SINCE IT'S A FOR LOOP
                        execute_program_buffer_postexec[index]<= 0; //program bufer execution started
                    end // 结束语句块。
                end // 结束语句块。
                else if(ABS_COMMAND.cmdtype == 1) begin //Quick access；执行否则如果分支的条件判断。
                    execute_program_buffer_auto[index]<= 0; //program bufer execution started //ERROR ITS IN A FOR LOOP
                    //execute_program_buffer <= 1;
                end // 结束语句块。
            end // 结束语句块。
            else if(ABS_COMMAND.cmdtype == 1 && ~debug[index].running && new_ABSTRACT_req) begin // 执行否则如果分支的条件判断。
                execute_program_buffer_auto[index] <= 1;
            end // 结束语句块。
        end // 结束语句块。
    end // 结束语句块。
end // 结束语句块。
endgenerate // 结束生成块。

//Program Buffer - Processor Interface
generate // 开始生成块，在编译期展开硬件结构。
for (index = 0; index < NUM_CPUS; index=index+1) begin // 执行循环或遍历。
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (rst) begin // 执行条件判断，满足条件时进入对应分支。
            debug[index].program_buffer_data <= 0;
        end // 结束语句块。
        else begin // 执行否则分支。
            case(debug[index].program_buffer_addr) // 开始多分支选择，根据表达式选择对应分支。
                31'h20 : debug[index].program_buffer_data <= PROGRAM_BUFFER0;
                31'h21 : debug[index].program_buffer_data <= PROGRAM_BUFFER1;
                31'h22 : debug[index].program_buffer_data <= PROGRAM_BUFFER2;
                31'h23 : debug[index].program_buffer_data <= PROGRAM_BUFFER3;
                31'h24 : debug[index].program_buffer_data <= PROGRAM_BUFFER4;
                31'h25 : debug[index].program_buffer_data <= PROGRAM_BUFFER5;
                31'h26 : debug[index].program_buffer_data <= PROGRAM_BUFFER6;
                31'h27 : debug[index].program_buffer_data <= PROGRAM_BUFFER7;
                31'h28 : debug[index].program_buffer_data <= PROGRAM_BUFFER8;
                31'h29 : debug[index].program_buffer_data <= PROGRAM_BUFFER9;
                31'h2A : debug[index].program_buffer_data <= PROGRAM_BUFFER10;
                31'h2B : debug[index].program_buffer_data <= PROGRAM_BUFFER11;
                31'h2C : debug[index].program_buffer_data <= PROGRAM_BUFFER12;
                31'h2D : debug[index].program_buffer_data <= PROGRAM_BUFFER13;
                31'h2E : debug[index].program_buffer_data <= PROGRAM_BUFFER14;
                31'h2F : debug[index].program_buffer_data <= PROGRAM_BUFFER15;
                default : debug[index].program_buffer_data <= 0; // 执行默认分支。
            endcase // 结束多分支选择。
            
        end // 结束语句块。
    end // 结束语句块。
end // 结束语句块。
endgenerate // 结束生成块。
endmodule // 结束模块定义。
