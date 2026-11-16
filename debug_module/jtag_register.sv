// ============================================================================
// 文件：debug_module/jtag_register.sv
// 类型：module
// 名称：jtag_register
// 作用：实现 JTAG 扫描链中的单个寄存器单元。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================


module jtag_register // 定义 jtag_register 模块。
        #(
        parameter C_WIDTH = 32, // 声明可配置参数。
        parameter C_ID = 3 // 声明可配置参数。
        )
        (
        input logic clk, // 声明输入端口。
        output logic reset_out, // 声明输出端口。
        input logic [C_WIDTH-1:0] data_in, // 声明输入端口。
        output logic [C_WIDTH-1:0] data_out, // 声明输出端口。
        output logic new_data // 声明输出端口。
        );

    logic capture, drck_i, tck, drck, reset, sel, shift, tdi, update, tdo; // 声明信号、变量或生成变量。
    logic [C_WIDTH-1:0] captured_data; // 声明信号、变量或生成变量。
    logic [C_WIDTH-1:0] jtag_data; // 声明信号、变量或生成变量。
    logic ack; // 声明信号、变量或生成变量。

    localparam SYNC_STAGES = 3; // 声明局部常量。
    logic new_data_sync [SYNC_STAGES-1:0]; // 声明信号、变量或生成变量。
    ///////////////////////////////////////////////////////////////////
    
    BUFG drck_bufg (.O(drck), .I(drck_i));
    
    BSCANE2 #( .JTAG_CHAIN(C_ID))
        bscan  (
            .CAPTURE    (capture),
            .DRCK       (drck_i),
            .RESET      (reset),
            .RUNTEST    (),
            .SEL        (sel),
            .SHIFT      (shift),
            .TCK        (tck),
            .TDI        (tdi),
            .TMS        (),
            .UPDATE     (update),
            .TDO        (tdo)
        );
    
    assign reset_out = reset; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    //X stage Synchronizers for handshaking
    always_ff @(posedge update or posedge reset or posedge ack) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (reset | ack) // 执行条件判断，满足条件时进入对应分支。
            new_data_sync[0] <= 0;
        else begin // 执行否则分支。
            if (sel) // 执行条件判断，满足条件时进入对应分支。
                new_data_sync[0] <= 1;
        end // 结束语句块。
    end // 结束语句块。
   
    genvar i; // 声明信号、变量或生成变量。
    generate // 开始生成块，在编译期展开硬件结构。
        for (i=1; i < SYNC_STAGES; i++) begin // 执行循环或遍历。
            always_ff @(posedge clk or posedge reset) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
                if (reset) // 执行条件判断，满足条件时进入对应分支。
                    new_data_sync[i] <= 0;
                else begin // 执行否则分支。
                    new_data_sync[i] <= new_data_sync[i-1];
                end // 结束语句块。
            end // 结束语句块。
        end // 结束语句块。
    endgenerate // 结束生成块。
        
    always_ff @(posedge clk or posedge reset) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (reset) // 执行条件判断，满足条件时进入对应分支。
            ack <= 0;
        else begin // 执行否则分支。
            ack <= new_data_sync[SYNC_STAGES-1];
        end // 结束语句块。
    end // 结束语句块。
    
    assign new_data = ack & ~new_data_sync[SYNC_STAGES-1]; // 执行连续赋值，把组合逻辑连接到目标信号。
    
    //JTAG Data Register logic as per XAPP139
    always_ff @(posedge drck or posedge reset) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (reset) // 执行条件判断，满足条件时进入对应分支。
            captured_data <= '0;
        else begin // 执行否则分支。
            if (capture & sel) // 执行条件判断，满足条件时进入对应分支。
                captured_data <= data_in;
            else if (shift & sel) // 执行否则如果分支的条件判断。
                captured_data <= {tdi, captured_data[C_WIDTH-1:1]};
        end // 结束语句块。
    end // 结束语句块。
    
    always @(posedge update or posedge reset) begin // 开始 always 逻辑块。
        if (reset) // 执行条件判断，满足条件时进入对应分支。
            jtag_data <= 0;
        else begin // 执行否则分支。
            if (sel) // 执行条件判断，满足条件时进入对应分支。
                jtag_data <= captured_data;
        end // 结束语句块。
    end // 结束语句块。
    assign data_out = jtag_data; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign tdo = captured_data[0]; // 执行连续赋值，把组合逻辑连接到目标信号。

    
endmodule // 结束模块定义。
