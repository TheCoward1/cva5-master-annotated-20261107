# #!/usr/bin/env bash
# set -euo pipefail

# ROOT=/mnt/e/ic/cva5-master-annotated-20261107/verification/unit/priority_encoder
# CVA5=/mnt/e/ic/cva5-master-annotated-20261107
# export PATH=/root/ic/tools/verilator-v5.008/bin:$PATH

# cd "$ROOT"
# verilator --binary --timing -Wall -Wno-fatal \
#   --Mdir build -o tb_priority_encoder \
#   --top-module tb_priority_encoder \
#   "$CVA5/core/types_and_interfaces/cva5_config.sv" \
#   "$CVA5/core/types_and_interfaces/riscv_types.sv" \
#   "$CVA5/core/types_and_interfaces/csr_types.sv" \
#   "$CVA5/core/types_and_interfaces/cva5_types.sv" \
#   "$CVA5/core/types_and_interfaces/fpu_types.sv" \
#   "$CVA5/core/types_and_interfaces/opcodes.sv" \
#   "$CVA5/core/common_components/priority_encoder.sv" \
#   tb/tb_priority_encoder.sv

# ./build/tb_priority_encoder

#!/usr/bin/env bash
set -euo pipefail

ROOT=/mnt/e/ic/cva5-master-annotated-20261107/verification/unit/priority_encoder
CVA5=/mnt/e/ic/cva5-master-annotated-20261107

export PATH=/root/ic/tools/verilator-v5.008/bin:$PATH

cd "$ROOT"

# 不带参数时，自动测试 WIDTH=1..14
if [ "$#" -eq 0 ]; then
    for w in $(seq 1 14); do
        bash "$ROOT/scripts/run_verilator.sh" "$w"
    done
    echo "========================================"
    echo "ALL WIDTHS 1..14 PASSED"
    echo "========================================"
    exit 0
fi

WIDTH="$1"

# 检查 WIDTH 参数
if ! [[ "$WIDTH" =~ ^[0-9]+$ ]]; then
    echo "ERROR: WIDTH must be an integer"
    exit 1
fi

if [ "$WIDTH" -lt 1 ] || [ "$WIDTH" -gt 14 ]; then
    echo "ERROR: WIDTH must be between 1 and 14"
    exit 1
fi

BUILD="$ROOT/build/w$WIDTH"
mkdir -p "$BUILD"

echo "========================================"
echo "Testing WIDTH=$WIDTH"
echo "========================================"

verilator --binary --timing -Wall -Wno-fatal \
    -GWIDTH="$WIDTH" \
    --Mdir "$BUILD" \
    -o tb_priority_encoder \
    --top-module tb_priority_encoder \
    -f "$ROOT/priority_encoder.f"

"$BUILD/tb_priority_encoder"