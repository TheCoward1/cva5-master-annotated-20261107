// ============================================================================
// 文件：debug_module/jtag_registers.sv
// 类型：module
// 名称：jtag_registers
// 作用：实现 JTAG 寄存器组和扫描访问。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

import debug_cfg_types::*; // 导入包或命名空间：debug_cfg_types::*;。

module jtag_registers ( // 定义 jtag_registers 模块。
        input logic clk, // 声明输入端口。
        output logic reset, // 声明输出端口。
    
        input dtmcs_t current_dtmcs, // 声明输入端口。
        output dtmcs_t updated_dtmcs, // 声明输出端口。
        output update_dtmcs, // 声明输出端口。
    
        input dmi_t current_dmi, // 声明输入端口。
        output dmi_t updated_dmi, // 声明输出端口。
        output update_dmi // 声明输出端口。
        );
    
    jtag_register
        #( .C_WIDTH($bits(dtmcs_t)), .C_ID(DTMCS_USER_REG))
        dtmcs_jtag_block
        (
            .clk (clk),
            .reset_out(reset),
            .data_in(current_dtmcs),
            .data_out(updated_dtmcs),
            .new_data(update_dtmcs)
        );
    
    jtag_register
        #( .C_WIDTH($bits(dmi_t)), .C_ID(DMI_USER_REG))
        dmi_jtag_block
        (
            .clk (clk),
            .reset_out(),
            .data_in(current_dmi),
            .data_out(updated_dmi),
            .new_data(update_dmi)
        );

endmodule // 结束模块定义。
