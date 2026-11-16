// ============================================================================
// 文件：debug_module/jtag_module.sv
// 类型：module
// 名称：jtag_module
// 作用：实现 JTAG TAP 状态机和 DMI 扫描链路。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

import debug_cfg_types::*; // 导入包或命名空间：debug_cfg_types::*;。

module jtag_module ( // 定义 jtag_module 模块。
        input logic clk, // 声明输入端口。
        output logic reset, // 声明输出端口。
        
        dmi_interface.jtag dm
        );

    dtmcs_t dtmcs, dtmcs_jtag;
    dmi_t dmi, dmi_jtag;
    
    logic dtmcs_write; // 声明信号、变量或生成变量。
    logic dmi_write; // 声明信号、变量或生成变量。
    
    logic dmi_busy; // 声明信号、变量或生成变量。
    logic dmi_error; // 声明信号、变量或生成变量。
    
    jtag_registers jtag_regs(
            .clk(clk),
            .reset(reset),
            .current_dtmcs(dtmcs),
            .updated_dtmcs(dtmcs_jtag),
            .update_dtmcs(dtmcs_write),
                
            .current_dmi(dmi),
            .updated_dmi(dmi_jtag),
            .update_dmi(dmi_write)
        );
    
    //dtmcs register
    assign dtmcs.zero1 = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dtmcs.dmihardreset = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dtmcs.dmireset = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dtmcs.zero2 = 0; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dtmcs.idle = 20; // 执行连续赋值，把组合逻辑连接到目标信号。
    //dmistat
    assign dtmcs.abits = 7; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dtmcs.version = 1; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (reset) // 执行条件判断，满足条件时进入对应分支。
            dtmcs.dmistat <= DMI_STATUS_SUCCESS;
        else if (dtmcs_write & (dtmcs_jtag.dmireset | dtmcs_jtag.dmihardreset)) //clear error status；执行否则如果分支的条件判断。
            dtmcs.dmistat <= DMI_STATUS_SUCCESS;
        else if (dmi_write & dmi_busy) // 执行否则如果分支的条件判断。
            dtmcs.dmistat <= DMI_STATUS_BUSY;
        else if (dm.handled & ~dmi_error) // 执行否则如果分支的条件判断。
            dtmcs.dmistat <= dm.response;
    end // 结束语句块。
    ////////////////////////////////////////

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (reset) // 执行条件判断，满足条件时进入对应分支。
            dmi_busy <= 0;
        else if (dtmcs_write & (dtmcs_jtag.dmireset | dtmcs_jtag.dmihardreset)) // 执行否则如果分支的条件判断。
            dmi_busy <= 0;
        else if (dmi_write & ~dmi_busy) // 执行否则如果分支的条件判断。
            dmi_busy <= 1;
        else if (dm.handled) // 执行否则如果分支的条件判断。
            dmi_busy <= 0;
    end // 结束语句块。

    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (reset) // 执行条件判断，满足条件时进入对应分支。
            dmi_error <= 0;
        else if (dtmcs_write & (dtmcs_jtag.dmireset | dtmcs_jtag.dmihardreset)) // 执行否则如果分支的条件判断。
            dmi_error <= 0;
        else if ((dmi_write & dmi_busy) || // 执行否则如果分支的条件判断。
                (dm.handled && dm.response == DMI_STATUS_FAILED))
                dmi_error <= 1;
                //dmi_error <= 0; //Test
                 
    end // 结束语句块。
    
    //dmi reg
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (reset) // 执行条件判断，满足条件时进入对应分支。
            dmi.address <= 0;
        else if (dmi_write & ~(dmi_busy | dmi_error)) // 执行否则如果分支的条件判断。
            dmi.address <= dmi_jtag.address;
    end // 结束语句块。
    
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (reset) // 执行条件判断，满足条件时进入对应分支。
            dmi.data <= 0;
        else if (dmi_write & ~(dmi_busy | dmi_error) && (dmi_jtag.op == DMI_OP_WRITE)) // 执行否则如果分支的条件判断。
            dmi.data <= dmi_jtag.data;
        else if (dm.handled) // 执行否则如果分支的条件判断。
            dmi.data <= dm.dmi_data;
    end // 结束语句块。
    
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (reset) // 执行条件判断，满足条件时进入对应分支。
            dmi.op <= DMI_STATUS_SUCCESS;
        else if (dtmcs_write & (dtmcs_jtag.dmireset | dtmcs_jtag.dmihardreset)) // 执行否则如果分支的条件判断。
            dmi.op <= DMI_STATUS_SUCCESS;
        else if (dmi_write & ~(dmi_busy | dmi_error)) // 执行否则如果分支的条件判断。
            dmi.op <= dmi_jtag.op;
        else if (dmi_write & dmi_busy & ~dmi_error) // 执行否则如果分支的条件判断。
            dmi.op <= DMI_STATUS_BUSY;
        else if (dm.handled & ~dmi_error) // 执行否则如果分支的条件判断。
            dmi.op <= dm.response;
    end // 结束语句块。
    
    //Output logic
    assign dm.address = dmi.address; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign dm.jtag_data = dmi.data; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (dmi_write & ~(dmi_busy | dmi_error)) // 执行条件判断，满足条件时进入对应分支。
            dm.rnw <= (dmi_jtag.op == DMI_OP_READ) || (dmi_jtag.op == DMI_OP_NOP);
    end // 结束语句块。
        
    always_ff @ (posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (reset) // 执行条件判断，满足条件时进入对应分支。
            dm.new_request <= 0;
        else if (dmi_write & ~(dmi_busy | dmi_error)) // 执行否则如果分支的条件判断。
            dm.new_request <= (dmi_jtag.op == DMI_OP_READ) || (dmi_jtag.op == DMI_OP_WRITE) || (dmi_jtag.op == DMI_OP_NOP);
        else // 执行否则分支。
            dm.new_request <= 0;
    end // 结束语句块。
    
endmodule // 结束模块定义。
