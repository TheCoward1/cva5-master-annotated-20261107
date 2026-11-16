// ============================================================================
// 文件：core/execution_units/fp_unit/fpu_top.sv
// 类型：module
// 名称：fpu_top
// 作用：浮点单元顶层，连接加法、乘法、除法、开方、规格化和舍入模块。
// 编码：UTF-8
// 说明：本文件为中文注释备份，代码逻辑与原版保持一致。
// ============================================================================

/*
 * Copyright © 2019-2023 Yuhui Gao, Chris Keilbart, Lesley Shannon
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
 *             Yuhui Gao <yuhuig@sfu.ca>
 *             Chris Keilbart <ckeilbar@sfu.ca>
 */

 module fpu_top // 定义 fpu_top 模块。

    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。
    import fpu_types::*; // 导入包或命名空间：fpu_types::*;。
    import opcodes::*; // 导入包或命名空间：opcodes::*;。
    
    #(
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG // 声明可配置参数。
    )
    (
        input logic clk, // 声明输入端口。
        input logic rst, // 声明输入端口。

        input decode_packet_t decode_stage, // 声明输入端口。
        output logic unit_needed, // 声明输出端口。
        output logic[REGFILE_READ_PORTS-1:0] uses_rs, // 声明输出端口。
        output logic[2:0] fp_uses_rs, // 声明输出端口。
        output logic uses_rd, // 声明输出端口。
        output logic fp_uses_rd, // 声明输出端口。

        input logic issue_stage_ready, // 声明输入端口。
        input logic[2:0] dyn_rm, // 声明输入端口。
        input logic[31:0] int_rf[REGFILE_READ_PORTS], // 声明输入端口。
        input logic[FLEN-1:0] fp_rf[3], // 声明输入端口。

        unit_issue_interface.unit issue,
        unit_writeback_interface.unit int_wb,
        unit_writeback_interface.unit fp_wb,
        output fflags_t fflags // 声明输出端口。
    );

    fp_madd_inputs_t madd_inputs;
    fp_div_inputs_t div_inputs;
    fp_sqrt_inputs_t sqrt_inputs;
    fp_wb2fp_misc_inputs_t wb2fp_inputs;
    fp_wb2int_misc_inputs_t wb2int_inputs;
    fflags_t int_fflags;
    fflags_t fp_fflags;
    unit_issue_interface intermediate_issue[4:0](); //FMA, FDIV, FSQRT, WB2FP, WB2INT
    fp_intermediate_wb_interface intermediate_unit_wb[3:0](); //FMADD, FMUL, FDIV/FSQRT, WB2FP
    ////////////////////////////////////////////////////
    //Implementation
    //This unit instantiates the internal FPU components and connects them
    //It is also responsible for instruction decoding

    ////////////////////////////////////////////////////
    //Decode
    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        uses_rs = '0;
        uses_rs[RS1] = decode_stage.instruction inside {
            SP_FCVT_S_W, SP_FCVT_S_WU, SP_FMV_W_X,
            DP_FCVT_D_W, DP_FCVT_D_WU
        };

        fp_uses_rs = '0;
        fp_uses_rs[RS1] = decode_stage.instruction inside {
            SP_FMADD, SP_FMSUB, SP_FNMSUB, SP_FNMADD, SP_FADD, SP_FSUB, SP_FMUL,
            SP_FDIV, SP_FSQRT, SP_FSGNJ, SP_FSGNJN, SP_FSGNJX, SP_FMIN, SP_FMAX,
            SP_FCVT_W_S, SP_FCVT_WU_S, SP_FMV_X_W, SP_FEQ, SP_FLT, SP_FLE, SP_FCLASS,
            DP_FMADD, DP_FMSUB, DP_FNMSUB, DP_FNMADD, DP_FADD, DP_FSUB, DP_FMUL,
            DP_FDIV, DP_FSQRT, DP_FSGNJ, DP_FSGNJN, DP_FSGNJX, DP_FMIN, DP_FMAX,
            DP_FCVT_S_D, DP_FCVT_D_S, DP_FEQ, DP_FLT, DP_FLE, DP_FCLASS, DP_FCVT_W_D, DP_FCVT_WU_D
        };
        fp_uses_rs[RS2] = decode_stage.instruction inside {
            SP_FMADD, SP_FMSUB, SP_FNMSUB, SP_FNMADD, SP_FADD, SP_FSUB, SP_FMUL,
            SP_FDIV, SP_FSQRT, SP_FSGNJ, SP_FSGNJN, SP_FSGNJX, SP_FMIN, SP_FMAX,
            SP_FEQ, SP_FLT, SP_FLE,
            DP_FMADD, DP_FMSUB, DP_FNMSUB, DP_FNMADD, DP_FADD, DP_FSUB, DP_FMUL,
            DP_FDIV, DP_FSQRT, DP_FSGNJ, DP_FSGNJN, DP_FSGNJX, DP_FMIN, DP_FMAX,
            DP_FEQ, DP_FLT, DP_FLE
        };
        fp_uses_rs[RS3] = decode_stage.instruction inside {
            SP_FMADD, SP_FMSUB, SP_FNMSUB, SP_FNMADD,
            DP_FMADD, DP_FMSUB, DP_FNMSUB, DP_FNMADD
        };

        uses_rd = decode_stage.instruction inside {
            SP_FCVT_W_S, SP_FCVT_WU_S, SP_FMV_X_W, SP_FEQ, SP_FLT, SP_FLE, SP_FCLASS,
            DP_FEQ, DP_FLT, DP_FLE, DP_FCLASS, DP_FCVT_W_D, DP_FCVT_WU_D
        };
        fp_uses_rd = decode_stage.instruction inside {
            SP_FMADD, SP_FMSUB, SP_FNMSUB, SP_FNMADD, SP_FADD, SP_FSUB, SP_FMUL,
            SP_FDIV, SP_FSQRT, SP_FSGNJ, SP_FSGNJN, SP_FSGNJX, SP_FMIN, SP_FMAX,
            SP_FCVT_S_W, SP_FCVT_S_WU, SP_FMV_W_X,
            DP_FMADD, DP_FMSUB, DP_FNMSUB, DP_FNMADD, DP_FADD, DP_FSUB, DP_FMUL,
            DP_FDIV, DP_FSQRT, DP_FSGNJ, DP_FSGNJN, DP_FSGNJX, DP_FMIN, DP_FMAX,
            DP_FCVT_S_D, DP_FCVT_D_S, DP_FCVT_D_W, DP_FCVT_D_WU
        };

        unit_needed = decode_stage.instruction inside {
            SP_FMADD, SP_FMSUB, SP_FNMSUB, SP_FNMADD, SP_FADD, SP_FSUB, SP_FMUL,
            DP_FMADD, DP_FMSUB, DP_FNMSUB, DP_FNMADD, DP_FADD, DP_FSUB, DP_FMUL,
            SP_FDIV, SP_FSQRT,
            DP_FDIV, DP_FSQRT,
            SP_FSGNJ, SP_FSGNJN, SP_FSGNJX, SP_FMIN, SP_FMAX, SP_FCVT_S_W, SP_FCVT_S_WU, SP_FMV_W_X,
            DP_FSGNJ, DP_FSGNJN, DP_FSGNJX, DP_FMIN, DP_FMAX, DP_FCVT_S_D, DP_FCVT_D_S, DP_FCVT_D_W, DP_FCVT_D_WU,
            SP_FCVT_W_S, SP_FCVT_WU_S, SP_FMV_X_W, SP_FEQ, SP_FLT, SP_FLE, SP_FCLASS,
            DP_FEQ, DP_FLT, DP_FLE, DP_FCLASS, DP_FCVT_W_D, DP_FCVT_WU_D
        };
    end // 结束语句块。

    ////////////////////////////////////////////////////
    //Shared preprocessing
    logic is_single; // 声明信号、变量或生成变量。
    //Instruction families
    logic is_fma; // 声明信号、变量或生成变量。
    logic is_fmul; // 声明信号、变量或生成变量。
    logic is_fadd; // 声明信号、变量或生成变量。
    logic is_div; // 声明信号、变量或生成变量。
    logic is_sqrt; // 声明信号、变量或生成变量。
    logic is_i2f; // 声明信号、变量或生成变量。
    logic is_mv_i2f; // 声明信号、变量或生成变量。
    logic is_s2d; // 声明信号、变量或生成变量。
    logic is_d2s; // 声明信号、变量或生成变量。
    logic is_minmax; // 声明信号、变量或生成变量。
    logic is_sign_inj; // 声明信号、变量或生成变量。
    logic is_f2i; // 声明信号、变量或生成变量。
    logic is_mv_f2i; // 声明信号、变量或生成变量。
    logic is_fcmp; // 声明信号、变量或生成变量。
    logic is_class; // 声明信号、变量或生成变量。
    //Used to distinguish between instructions in a family
    logic add; // 声明信号、变量或生成变量。
    logic neg_mul; // 声明信号、变量或生成变量。
    logic conv_signed; // 声明信号、变量或生成变量。
    logic is_sign_inj_single; // 声明信号、变量或生成变量。
    rm_t rm_r;

    fp_preprocessing_packet_t pkt;
    assign pkt.valid = issue.new_request; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.unit[0] = is_fma | is_fmul | is_fadd; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.unit[1] = is_div; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.unit[2] = is_sqrt; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.unit[3] = is_i2f | is_mv_i2f | is_minmax | is_sign_inj | is_s2d | is_d2s; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.unit[4] = is_f2i | is_mv_f2i | is_fcmp | is_class; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.rs1 = fp_rf[RS1]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.rs2 = fp_rf[RS2]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.rs3 = fp_rf[RS3]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.int_rs1 = int_rf[RS1]; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.id = issue.id; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_single = is_single; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_fma = is_fma; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_fadd = is_fadd; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_i2f = is_i2f; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_d2s = is_d2s; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_minmax = is_minmax; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_sign_inj = is_sign_inj; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_sign_inj_single = is_sign_inj_single; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_f2i = is_f2i; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_mv_i2f = is_mv_i2f; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_fcmp = is_fcmp; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.is_class = is_class; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.add = add; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.neg_mul = neg_mul; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.conv_signed = conv_signed; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign pkt.rm = &rm_r ? dyn_rm : rm_r; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_ff @(posedge clk) begin // 开始时序逻辑块，在时钟边沿更新寄存器。
        if (issue_stage_ready) begin // 执行条件判断，满足条件时进入对应分支。
            //Only the instructions that convert their arguments from s->d
            is_single <= decode_stage.instruction inside {SP_FMADD, SP_FMSUB, SP_FNMSUB, SP_FNMADD, SP_FADD, SP_FSUB, SP_FMUL, SP_FDIV, SP_FSQRT, SP_FMIN, SP_FMAX, SP_FCVT_S_W, SP_FCVT_S_WU, DP_FCVT_D_S, SP_FCVT_W_S, SP_FCVT_WU_S, SP_FEQ, SP_FLT, SP_FLE, SP_FCLASS};
            //Partial decoding to distinguish instructions from each other
            is_fma <= ~decode_stage.instruction[4];
            is_fmul <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b0??10};
            is_fadd <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b0000?};
            is_div <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b00?11};
            is_sqrt <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b01?1?};
            is_i2f <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b1?01?};
            is_mv_f2i <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b1110?} & ~decode_stage.instruction[12];
            is_s2d <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b01?0?} & ~decode_stage.instruction[20];
            is_d2s <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b01?0?} & decode_stage.instruction[20];
            is_minmax <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b0?1?1};
            is_sign_inj <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b0?1?0};
            is_sign_inj_single <= ~decode_stage.instruction[25];
            is_f2i <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b1?00?};
            is_mv_i2f <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b1?11?};
            is_fcmp <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b10???};
            is_class <= decode_stage.instruction[4] & decode_stage.instruction[31:27] inside {5'b1110?} & decode_stage.instruction[12];
            //Double duty for both FADD and FMA
            add <= decode_stage.instruction[4] ? ~decode_stage.instruction[27] : decode_stage.instruction[3:2] inside {2'b00, 2'b10};
            neg_mul <= decode_stage.instruction[3];
            conv_signed <= ~decode_stage.instruction[20];
            rm_r <= decode_stage.instruction[14:12];
        end // 结束语句块。
    end // 结束语句块。

    fp_preprocessing #(.CONFIG(CONFIG), .FP_NUM_UNITS(5)) fp_preprocessing_inst (
        .unit_issue(intermediate_issue),
        .pkt(pkt),
        .ready(issue.ready),
        .madd_args(madd_inputs),
        .div_args(div_inputs),
        .sqrt_args(sqrt_inputs),
        .wb2fp_args(wb2fp_inputs),
        .wb2int_args(wb2int_inputs),
    .*);

    ////////////////////////////////////////////////////
    //Execution Units
    fp_madd_wrapper #(.CONFIG(CONFIG)) fp_madd_inst (
        .args(madd_inputs),
        .issue(intermediate_issue[0]),
        .madd_wb(intermediate_unit_wb[1]),
        .mul_wb(intermediate_unit_wb[2]),
    .*);

    fp_div_sqrt_wrapper div_sqrt_inst (
        .div_inputs(div_inputs),
        .sqrt_inputs(sqrt_inputs),
        .div_issue(intermediate_issue[1]),
        .sqrt_issue(intermediate_issue[2]),
        .wb(intermediate_unit_wb[0]),
    .*);

    fp_wb2fp_misc wb2fp_misc_inst (
        .args(wb2fp_inputs),
        .issue(intermediate_issue[3]),
        .wb(intermediate_unit_wb[3])
    );

    fp_wb2int_misc wb2int_misc_inst (
        .args(wb2int_inputs),
        .issue(intermediate_issue[4]),
        .wb(int_wb),
        .fflags(int_fflags),
    .*);

    ////////////////////////////////////////////////////
    //Normalization and rounding
    fp_normalize_rounding_top #(.NUM_WB_UNITS(4)) norm_round_inst (
        .intermediate_wb(intermediate_unit_wb),
        .wb(fp_wb),
        .fflags(fp_fflags),
    .*);

    ////////////////////////////////////////////////////
    //Updating flags
    //Combine both wb2int and wb2fp in one because they can writeback simultaneously
    logic fp_accepted; // 声明信号、变量或生成变量。
    logic int_accepted; // 声明信号、变量或生成变量。
    assign fp_accepted = fp_wb.done & fp_wb.ack; // 执行连续赋值，把组合逻辑连接到目标信号。
    assign int_accepted = int_wb.done & int_wb.ack; // 执行连续赋值，把组合逻辑连接到目标信号。

    always_comb begin // 开始组合逻辑块，根据输入组合计算输出。
        fflags = '0;
        if (fp_accepted & int_accepted) // 执行条件判断，满足条件时进入对应分支。
            fflags = fp_fflags | int_fflags;
        else if (fp_accepted) // 执行否则如果分支的条件判断。
            fflags = fp_fflags;
        else if (int_accepted) // 执行否则如果分支的条件判断。
            fflags = int_fflags;
    end // 结束语句块。

endmodule // 结束模块定义。
