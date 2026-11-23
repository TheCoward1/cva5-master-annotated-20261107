#!/usr/bin/env bash
# sdp_ram_padded 完整回归：bash run_vcs.sh [seed] [random_cycles]
# 例：bash run_vcs.sh 1 0        仅定向；bash run_vcs.sh 1 1000  包含随机。
# 默认输出到本目录 build；可用 BUILD_DIR=/tmp/... 指定独立构建目录。
# 请先加载本机 VCS/许可证环境。只需 VCS、URG、Python 3，无额外 Python 包。
set -euo pipefail

if (( $# > 2 )); then
    printf 'Usage: bash run_vcs.sh [seed] [random_cycles]\n' >&2
    exit 2
fi
ram_seed="${1:-1}"
ram_random_cycles="${2:-1000}"
python3 - "$ram_seed" "$ram_random_cycles" <<'PY'
import sys
try:
    seed, cycles = map(int, sys.argv[1:])
    if not (0 <= seed <= 0xFFFFFFFF and 0 <= cycles <= 0x7FFFFFFF):
        raise ValueError
except ValueError:
    raise SystemExit("seed must be an unsigned 32-bit integer; random_cycles must be 0..2147483647")
PY

ram_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ram_project_root="$(cd -- "$ram_script_dir/../../../.." && pwd)"
ram_build_dir="${BUILD_DIR:-$ram_script_dir/build}"
mkdir -p -- "$ram_build_dir"
ram_build_dir="$(cd -- "$ram_build_dir" && pwd)"
cd -- "$ram_build_dir"

# 复用构建目录时先使上一轮摘要失效，失败运行不能留下旧的 PASS/覆盖记录。
printf '{"simulation_status":"RUNNING"}\n' > verification_summary.json
printf 'instance,request_percent,response_percent\n' > coverage_summary.csv
ram_mark_failed_run() {
    local ram_runner_exit=$?
    if (( ram_runner_exit != 0 )); then
        printf '{"simulation_status":"FAIL","runner_exit_code":%d}\n' \
            "$ram_runner_exit" > "$ram_build_dir/verification_summary.json"
    fi
    return "$ram_runner_exit"
}
trap ram_mark_failed_run EXIT

# 显式选择 45 配置回归顶层；单配置模块的 done 输出不负责统一结束仿真。
# 本 testbench 已包含完整自检环境，仅依赖两个 RAM RTL 文件。
if ! vcs -full64 -sverilog -timescale=1ns/1ps \
    "$ram_project_root/core/common_components/ram/sdp_ram.sv" \
    "$ram_project_root/core/common_components/ram/sdp_ram_padded.sv" \
    "$ram_script_dir/tb_sdp_ram_padded.sv" \
    -top tb_sdp_ram_padded_top \
    -cm line+cond+tgl+branch -cm_dir simv.vdb \
    -o simv -l compile.log > compile.console.log 2>&1; then
    tail -n 80 compile.console.log >&2
    exit 1
fi

if ! ./simv -no_save "+SEED=$ram_seed" "+RANDOM_CYCLES=$ram_random_cycles" \
    -cm line+cond+tgl+branch \
    -cm_name "seed_${ram_seed}_cycles_${ram_random_cycles}" \
    -l run.log > run.console.log 2>&1; then
    tail -n 80 run.console.log >&2
    exit 1
fi

# 某些 VCS 环境在 $fatal 后仍可能返回 0，不能只依赖进程退出码。
# 同时要求没有错误、完整结束、每实例检查通过且有独立覆盖记录。
python3 - "$ram_build_dir/run.log" <<'PY'
import re
import sys
import csv
import json
from pathlib import Path
log_path = Path(sys.argv[1])
text = log_path.read_text()
for marker in ("Fatal:", "Error-[", "MISMATCH", "TIMEOUT phase="):
    if marker in text:
        raise SystemExit("FAIL: simulation log contains " + marker)
summary = re.findall(r"^ALL SDP_RAM_PADDED TESTS PASSED: (\d+) configurations$", text, re.M)
if len(summary) != 1:
    raise SystemExit("FAIL: missing or duplicated complete-regression PASS marker")
expected = int(summary[0])
# generate 实例名中也有 [0] 等下标，要匹配最外层日志方括号。
passed = re.findall(r"^\[(.+)\] SDP_RAM_PADDED TEST PASSED:", text, re.M)
coverage = re.findall(
    r"^\[(.+)\] FUNCTIONAL COVERAGE: request=([\d.]+)% response=([\d.]+)%",
    text, re.M)
passed_scopes = {name.rsplit(".", 1)[0] for name in passed}
coverage_scopes = {entry[0].rsplit(".", 1)[0] for entry in coverage}
if (expected < 1 or len(passed) != expected or len(coverage) != expected
        or len(passed_scopes) != expected or passed_scopes != coverage_scopes):
    raise SystemExit("FAIL: incomplete per-instance PASS/coverage accounting")
print(f"PASS: {expected} configurations; "
      f"minimum request coverage={min(float(x[1]) for x in coverage):.2f}%, "
      f"minimum response coverage={min(float(x[2]) for x in coverage):.2f}%")
# 无论 URG 是否可用，都保存直接来自模拟器 get_inst_coverage() 的逐实例摘要。
# 这不是覆盖仓明细报告；明细数据仍保存在 simv.vdb 中。
with (log_path.parent / "coverage_summary.csv").open("w", newline="") as output:
    writer = csv.writer(output)
    writer.writerow(("instance", "request_percent", "response_percent"))
    writer.writerows((scope.rsplit(".", 1)[0], request, response)
                     for scope, request, response in coverage)
report = {"simulation_status": "PASS", "configurations": expected,
          "coverage_source": "per-instance get_inst_coverage() in run.log",
          "minimum_request_percent": min(float(x[1]) for x in coverage),
          "minimum_response_percent": min(float(x[2]) for x in coverage)}
(log_path.parent / "verification_summary.json").write_text(json.dumps(report, indent=2))
PY

# 本机 URG 在部分合并报告上会崩溃，因此把报告状态与仿真判定分开保存。
# 报告按 seed+cycles 命名；相同参数重跑复用目录，以本轮状态字段判断是否可用。
ram_native_report="functional_coverage_seed_${ram_seed}_cycles_${ram_random_cycles}"
ram_native_status=available
if ! urg -dir simv.vdb -metric group -format text \
    -report "$ram_native_report" -log urg.log > urg.console.log 2>&1; then
    ram_native_status=unavailable
    printf 'WARNING: URG report generation failed; simulation checks passed.\n' >&2
    printf 'See %s; per-instance summary: %s\n' \
        "$ram_build_dir/urg.console.log" "$ram_build_dir/coverage_summary.csv" >&2
fi
python3 - "$ram_build_dir/verification_summary.json" "$ram_native_status" "$ram_native_report" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
report = json.loads(path.read_text())
report["native_urg_report_status"] = sys.argv[2]
report["native_urg_report_directory"] = sys.argv[3]
path.write_text(json.dumps(report, indent=2))
PY
printf 'Build and logs: %s\nCoverage summary: %s\nNative URG report: %s (%s)\n' \
    "$ram_build_dir" "$ram_build_dir/coverage_summary.csv" \
    "$ram_build_dir/$ram_native_report" "$ram_native_status"
