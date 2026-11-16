#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

DUT="$REPO_ROOT/core/common_components/clz.sv"
TB="$SCRIPT_DIR/tb_clz.sv"
BUILD_ROOT="${BUILD_DIR:-/tmp/clz_sweep}"
VCS="${VCS:-vcs}"

if ! command -v "$VCS" >/dev/null 2>&1; then
    echo "错误: 找不到 VCS: $VCS" >&2
    exit 1
fi

if [[ ! -f "$DUT" ]]; then
    echo "错误: 找不到 DUT: $DUT" >&2
    exit 1
fi

if [[ ! -f "$TB" ]]; then
    echo "错误: 找不到 TB: $TB" >&2
    exit 1
fi

fail=0

printf "%-8s %-8s %-10s\n" "WIDTH" "RESULT" "CHECKS"
printf "%-8s %-8s %-10s\n" "-----" "------" "------"

for w in {3..10}; do
    build="$BUILD_ROOT/w$w"
    compile_log="$build/compile.log"
    run_log="$build/run.log"

    mkdir -p "$build"

    if (
        cd "$build"

        "$VCS" -sverilog -full64 \
            -timescale=1ns/1ps \
            "-pvalue+tb_clz.width=$w" \
            "$DUT" \
            "$TB" \
            -o simv >"$compile_log" 2>&1
    ); then
        if (
            cd "$build"
            ./simv >"$run_log" 2>&1
        ); then
            checks=$(grep -oE 'CHECKS=[0-9]+' "$run_log" | tail -1 | cut -d= -f2)
            printf "%-8s %-8s %-10s\n" "$w" "PASS" "${checks:-?}"
        else
            printf "%-8s %-8s %-10s\n" "$w" "FAIL" "-"
            echo "WIDTH=$w 运行失败，日志: $run_log" >&2
            fail=1
        fi
    else
        printf "%-8s %-8s %-10s\n" "$w" "FAIL" "-"
        echo "WIDTH=$w 编译失败，日志: $compile_log" >&2
        fail=1
    fi
done

echo
if [[ "$fail" -eq 0 ]]; then
    echo "ALL WIDTHS 3..10 PASSED"
else
    echo "SOME WIDTHS FAILED"
    exit 1
fi