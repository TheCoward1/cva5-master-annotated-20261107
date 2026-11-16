// ============================================================================
// 文件：core/types_and_interfaces/fpu_types.sv
// 类型：package
// 名称：fpu_types
// 作用：定义浮点数据、舍入模式、异常标志和 FPU 内部类型。
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


package fpu_types; // 定义 fpu_types 包。
    import cva5_config::*; // 导入包或命名空间：cva5_config::*;。
    import cva5_types::*; // 导入包或命名空间：cva5_types::*;。

// 定义类型别名或枚举/结构类型。
    typedef logic[GRS_WIDTH-1:0] grs_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[EXPO_WIDTH-1:0] fp_shift_amt_t;

    //Constants
    localparam BIAS = 2**(EXPO_WIDTH-1) - 1; // 声明局部常量。
    localparam BIAS_F = 2**(EXPO_WIDTH_F-1)-1; // 声明局部常量。
    localparam [FLEN-1:0] CANONICAL_NAN = {1'b0, {EXPO_WIDTH{1'b1}}, 1'b1, {(FRAC_WIDTH-1){1'b0}}}; //canonical NaN；声明局部常量。

// 定义类型别名或枚举/结构类型。
    typedef logic[EXPO_WIDTH-1:0] expo_d_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[EXPO_WIDTH_F-1:0] expo_s_t;
// 定义类型别名或枚举/结构类型。
    typedef logic[FRAC_WIDTH-1:0] frac_d_t;
    
// 定义类型别名或枚举/结构类型。
    typedef union packed {
        logic[FLEN-1:0] raw; // 声明信号、变量或生成变量。
        struct packed { // 声明结构体类型。
            logic sign; // 声明信号、变量或生成变量。
            expo_d_t expo;
            frac_d_t frac;
        } d;
        struct packed { // 声明结构体类型。
            logic[FLEN-FLEN_F-1:0] box; // 声明信号、变量或生成变量。
            logic sign; // 声明信号、变量或生成变量。
            expo_s_t expo;
            logic[FRAC_WIDTH_F-1:0] frac; // 声明信号、变量或生成变量。
        } s;
    } fp_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic inf; // 声明信号、变量或生成变量。
        logic snan; // 声明信号、变量或生成变量。
        logic qnan; // 声明信号、变量或生成变量。
        logic zero; // 声明信号、变量或生成变量。
    } special_case_t;

// 定义类型别名或枚举/结构类型。
    typedef logic[2:0] rm_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic nv; // 声明信号、变量或生成变量。
        logic dz; // 声明信号、变量或生成变量。
        logic of; // 声明信号、变量或生成变量。
        logic uf; // 声明信号、变量或生成变量。
        logic nx; // 声明信号、变量或生成变量。
    } fflags_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        rm_t rm;
        logic valid; // 声明信号、变量或生成变量。
        logic[4:0] unit; // 声明信号、变量或生成变量。
        fp_t rs1;
        fp_t rs2;
        fp_t rs3;
        logic[31:0] int_rs1; // 声明信号、变量或生成变量。
        id_t id;
        logic is_single; // 声明信号、变量或生成变量。
        logic is_fma; // 声明信号、变量或生成变量。
        logic is_fadd; // 声明信号、变量或生成变量。
        logic is_i2f; // 声明信号、变量或生成变量。
        logic is_d2s; // 声明信号、变量或生成变量。
        logic is_minmax; // 声明信号、变量或生成变量。
        logic is_sign_inj; // 声明信号、变量或生成变量。
        logic is_sign_inj_single; // 声明信号、变量或生成变量。
        logic is_f2i; // 声明信号、变量或生成变量。
        logic is_mv_i2f; // 声明信号、变量或生成变量。
        logic is_fcmp; // 声明信号、变量或生成变量。
        logic is_class; // 声明信号、变量或生成变量。
        logic add; // 声明信号、变量或生成变量。
        logic neg_mul; // 声明信号、变量或生成变量。
        logic conv_signed; // 声明信号、变量或生成变量。
    } fp_preprocessing_packet_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        fp_t rs1;
        fp_t rs2;
        logic rs1_hidden; // 声明信号、变量或生成变量。
        logic rs2_hidden; // 声明信号、变量或生成变量。
        logic rs1_safe; // 声明信号、变量或生成变量。
        logic rs2_safe; // 声明信号、变量或生成变量。
        special_case_t rs1_special_case;
        special_case_t rs2_special_case;
        logic rs1_expo_overflow; // 声明信号、变量或生成变量。
        logic[EXPO_WIDTH:0] expo_diff; // 声明信号、变量或生成变量。
        logic add; // 声明信号、变量或生成变量。
        logic swap; // 声明信号、变量或生成变量。
        grs_t fp_add_grs;
        rm_t rm;
        logic single; // 声明信号、变量或生成变量。
    } fp_add_inputs_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        special_case_t rs1_special_case;
        special_case_t rs2_special_case;
        logic rs1_hidden; // 声明信号、变量或生成变量。
        logic rs2_hidden; // 声明信号、变量或生成变量。
        fp_t rs1;
        fp_t rs2;
        rm_t rm;
        logic single; // 声明信号、变量或生成变量。
        fp_shift_amt_t rs2_prenormalize_shift_amt;
    } fp_mul_inputs_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic mul_sign; // 声明信号、变量或生成变量。
        logic add_sign; // 声明信号、变量或生成变量。
        fp_t rs3;
        logic rs3_hidden; // 声明信号、变量或生成变量。
        special_case_t rs3_special_case;
    } fp_fma_inputs_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic add; // 声明信号、变量或生成变量。
        logic fma; // 声明信号、变量或生成变量。
        //mul is implicit if others unset
        fp_add_inputs_t add_args;
        fp_fma_inputs_t fma_args;
        fp_mul_inputs_t mul_args;
    } fp_madd_inputs_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        fp_t rs1;
        fp_t rs2;
        rm_t rm;
        logic rs1_hidden; // 声明信号、变量或生成变量。
        logic rs2_hidden; // 声明信号、变量或生成变量。
        fp_shift_amt_t rs1_prenormalize_shift_amt;
        fp_shift_amt_t rs2_prenormalize_shift_amt;
        logic single; // 声明信号、变量或生成变量。
        special_case_t rs1_special_case;
        special_case_t rs2_special_case;
    } fp_div_inputs_t;

    //Digit set for division
// 定义类型别名或枚举/结构类型。
    typedef enum logic[2:0] {
        NEG_THREE = 3'b010, //Only reached by subtraction when last quotient digit is -2
        NEG_TWO = 3'b011,
        NEG_ONE = 3'b001,
        ZERO = 3'b000,
        POS_ONE = 3'b101,
        POS_TWO = 3'b111
    } q_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        fp_t rs1;
        logic rs1_hidden; // 声明信号、变量或生成变量。
        special_case_t special_case;
        fp_shift_amt_t rs1_prenormalize_shift_amt;
        rm_t rm;
        logic single; // 声明信号、变量或生成变量。
    } fp_sqrt_inputs_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic i2f; // 声明信号、变量或生成变量。
        logic fminmax; // 声明信号、变量或生成变量。
        logic fsgnj; // 声明信号、变量或生成变量。
        logic fmv; // 声明信号、变量或生成变量。
        logic d2s; // 声明信号、变量或生成变量。
        //s2d is implicit if others unset

        //Used by FMV
        logic[31:0] int_rs; // 声明信号、变量或生成变量。
        //Used by S2D, D2S
        logic rs1_hidden; // 声明信号、变量或生成变量。
        special_case_t rs1_special_case;
        //Used by S2D, D2S, FSGNJ
        fp_t rs1;
        //Used by FSGNJ
        logic fsgnj_single; // 声明信号、变量或生成变量。
        logic rs1_boxed; // 声明信号、变量或生成变量。
        logic rs2_boxed; // 声明信号、变量或生成变量。
        //Used by FSGNJ, FMINMAX
        logic swap; // 声明信号、变量或生成变量。
        fp_t rs2;
        //Used by FSGNJ, FMINMAX, I2F
        logic single; // 声明信号、变量或生成变量。
        rm_t rm;
        //Used by FMINMAX
        special_case_t rs2_special_case;
        //Used by I2F
        logic[31:0] int_rs_abs; // 声明信号、变量或生成变量。
        logic i2f_sign; // 声明信号、变量或生成变量。
    } fp_wb2fp_misc_inputs_t;

// 定义类型别名或枚举/结构类型。
    typedef struct packed {
        logic fclass; // 声明信号、变量或生成变量。
        logic fcmp; // 声明信号、变量或生成变量。
        logic f2i; // 声明信号、变量或生成变量。
        //fmv is implicit if others unset

        //Used by f2i
        logic int_less_than_1; // 声明信号、变量或生成变量。
        expo_d_t rs1_expo_unbiased;
        //Used by fclass, fcmp, f2i
        fp_t rs1;
        //Used by fclass
        logic rs1_original_hidden_bit; // 声明信号、变量或生成变量。
        //Used by fclass, fcmp
        special_case_t rs1_special_case;
        //Used by fcmp
        special_case_t rs2_special_case;
        fp_t rs2;
        logic swap; // 声明信号、变量或生成变量。
        //Used by fcmp as fn3 and f2i as rounding
        rm_t rm;
        //Used by f2i
        logic rs1_hidden; // 声明信号、变量或生成变量。
        logic is_signed; // 声明信号、变量或生成变量。
    } fp_wb2int_misc_inputs_t;

endpackage // 结束包定义。
