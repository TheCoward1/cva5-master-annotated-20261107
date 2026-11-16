#!/usr/bin/env bash
set -u

ROOT=/mnt/e/ic/cva5-master-annotated-20261107/verification/unit/priority_encoder
LOG_DIR="$ROOT/logs/all_widths"

mkdir -p "$LOG_DIR"

fail=0

printf "%-8s %-8s %-10s\n" "WIDTH" "RESULT" "CHECKS"
printf "%-8s %-8s %-10s\n" "-----" "------" "------"

for w in $(seq 1 14); do
    log="$LOG_DIR/w$w.log"

    if bash "$ROOT/scripts/run_verilator.sh" "$w" >"$log" 2>&1; then
        checks=$(grep -oE '[0-9]+ checks' "$log" | tail -1 | awk '{print $1}')
        printf "%-8s %-8s %-10s\n" "$w" "PASS" "${checks:-?}"
    else
        printf "%-8s %-8s %-10s\n" "$w" "FAIL" "-"
        fail=1
    fi
done

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL WIDTHS 1..14 PASSED"
else
    echo "SOME WIDTHS FAILED"
    echo "请检查 logs/all_widths 下的日志"
fi

exit "$fail"