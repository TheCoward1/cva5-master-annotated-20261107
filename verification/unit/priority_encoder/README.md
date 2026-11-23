# priority_encoder 模块验证

- 被测模块：`core/common_components/priority_encoder.sv`
- 测试平台：`verification/unit/priority_encoder/tb/tb_priority_encoder.sv`
- 运行命令：在 WSL 中执行 `bash scripts/run_verilator.sh`
- 预期结果：`PRIORITY_ENCODER TEST PASSED: 256 checks`

cd /mnt/e/ic/cva5-master-annotated-20261107/verification/unit/priority_encoder
bash run_tb_clz.sh
bash scripts/run_verilator.sh 8
head -20 tb/tb_priority_encoder.sv

cd /mnt/e/ic/cva5-master-annotated-20261107/verification/unit/tb_set_clr_reg_with_rst
vcs -sverilog -full64 \
    -timescale=1ns/1ps \
    ../../../core/common_components/set_clr_reg_with_rst.sv \
    tb_set_clr_reg_with_rst.sv \
    -o simv

./simv


cd /mnt/e/ic/cva5-master-annotated-20261107/verification/unit/tb_set_clr_reg_with_rst

vcs -full64 -sverilog -debug_access+all \
  -timescale=1ns/1ps \
  -cm line+cond+fsm+tgl+branch+assert \
  -cm_dir ./simv.vdb \
  -top tb_set_clr_reg_with_rst_top \
  ../../../core/types_and_interfaces/cva5_config.sv \
  ../../../core/types_and_interfaces/riscv_types.sv \
  ../../../core/types_and_interfaces/csr_types.sv \
  ../../../core/types_and_interfaces/cva5_types.sv \
  ../../../core/types_and_interfaces/fpu_types.sv \
  ../../../core/types_and_interfaces/opcodes.sv \
  ../../../core/common_components/set_clr_reg_with_rst.sv \
  tb_set_clr_reg_with_rst.sv \
  -o simv

cd /mnt/e/ic/cva5-master-annotated-20261107/verification/unit/tb_lfsr

vcs -full64 -sverilog -debug_access+all \
  -timescale=1ns/1ps \
  -cm line+cond+fsm+tgl+branch+assert \
  -cm_dir ./simv.vdb \
  -top tb_all \
  ../../../core/common_components/lfsr.sv \
  tb_lfsr.sv \
  -o simv
./simv
cd /mnt/e/ic/cva5-master-annotated-20261107/verification/unit/tb_ram/tb_lutram_1w_1r
vcs -full64 -sverilog -debug_access+all \
  -timescale=1ns/1ps \
  -top tb_lfsr_top \
  ../../../core/common_components/lfsr.sv \
  tb_lfsr.sv \
  -o simv
./simv

cd /mnt/e/ic/cva5-master-annotated-20261107/verification/unit/tb_ram/tb_sdp_ram

vcs -full64 -sverilog -timescale=1ns/1ps \
    -debug_access+all -kdb \
    -cm line+cond+tgl+branch+fsm+assert \
    -cm_dir ./simv.vdb \
    -top tb_lutram_1w_1r \
    ../../../../core/common_components/ram/sdp_ram.sv \
    tb_sdp_ram.sv \
    -o simv

./simv > sim.log 2>&1
grep -c "Match:" sim.log
cd /mnt/e/ic/cva5-master-annotated-20261107/verification/unit/tb_ram/tb_tdp_ram

vcs -full64 -sverilog -debug_access+all \
  -timescale=1ns/1ps \
  -cm line+cond+fsm+tgl+branch+assert \
  -cm_dir ./simv.vdb \
  -top tb_tdp_ram_top \
  ../../../../core/types_and_interfaces/cva5_config.sv \
  ../../../../core/types_and_interfaces/riscv_types.sv \
  ../../../../core/types_and_interfaces/csr_types.sv \
  ../../../../core/types_and_interfaces/cva5_types.sv \
  ../../../../core/types_and_interfaces/fpu_types.sv \
  ../../../../core/types_and_interfaces/opcodes.sv \
  ../../../../core/common_components/ram/tdp_ram.sv \
  tb_tdp_ram.sv \
  -o simv

./simv \
    -cm line+cond+tgl+branch+fsm+assert \
    -cm_dir ./simv.vdb \
    -no_save
urg -full64 \
    -dir ./simv.vdb \
    -report ./coverage_report