# CVA5 模块验证目录说明

本目录存放 CVA5 的模块级和子系统级验证工程。原始 RTL 不复制到本目录，验证平台直接引用 `../core`、`../apu` 等目录中的真实 RTL。

## 目录结构

```text
verification/
├─ README.md
├─ unit/
│  └─ priority_encoder/
│     ├─ tb/
│     │  └─ tb_priority_encoder.sv
│     ├─ scripts/
│     │  └─ run_verilator.sh
│     ├─ priority_encoder.f
│     ├─ build/
│     ├─ logs/
│     ├─ waves/
│     └─ README.md
└─ CVA5新模块验证配置完整指南.docx
```

## 当前已验证模块

| 模块 | 目录 | 结果 |
|---|---|---|
| priority_encoder | `unit/priority_encoder` | 256 checks PASS |
| barrel_shifter | 独立验证工程 `E:\ic\cva5-verif-lab\barrel_shifter` | 2202 checks PASS |
| CVA5 核级 C 回归 | `E:\ic\cva5-verif-lab\cva5_core` | 10 tests PASS |

## 新建一个模块验证需要什么

以 `branch_comparator` 为例，至少需要：

```text
1. TB 中实例化真实 DUT
2. Verilator 脚本加入 DUT 源码
3. Slang filelist 加入 DUT 源码
4. 根目录 .slang/server.json 指向当前 filelist
```

### 1. 创建目录

```text
verification/unit/branch_comparator/
├─ tb/tb_branch_comparator.sv
├─ scripts/run_verilator.sh
├─ branch_comparator.f
├─ build/
├─ logs/
└─ waves/
```

被测模块：

```text
core/execution_units/branch_comparator.sv
```

### 2. TB 中实例化 DUT

```systemverilog
branch_comparator dut (
    .less_than(less_than),
    .a(a),
    .b(b),
    .xor_result(xor_result),
    .result(result)
);
```

### 3. Verilator 脚本

必须加入 CVA5 基础包、DUT 和 TB：

```bash
CVA5=/mnt/e/ic/cva5-master-annotated-20261107

"$CVA5/core/types_and_interfaces/cva5_config.sv"
"$CVA5/core/types_and_interfaces/riscv_types.sv"
"$CVA5/core/types_and_interfaces/csr_types.sv"
"$CVA5/core/types_and_interfaces/cva5_types.sv"
"$CVA5/core/types_and_interfaces/fpu_types.sv"
"$CVA5/core/types_and_interfaces/opcodes.sv"
"$CVA5/core/execution_units/branch_comparator.sv"
tb/tb_branch_comparator.sv
```

### 4. Slang filelist

创建：

```text
verification/unit/branch_comparator/branch_comparator.f
```

内容：

```text
../../../core/types_and_interfaces/cva5_config.sv
../../../core/types_and_interfaces/riscv_types.sv
../../../core/types_and_interfaces/csr_types.sv
../../../core/types_and_interfaces/cva5_types.sv
../../../core/types_and_interfaces/fpu_types.sv
../../../core/types_and_interfaces/opcodes.sv
../../../core/execution_units/branch_comparator.sv
tb/tb_branch_comparator.sv
```

### 5. 根目录 Slang 配置

文件：

```text
E:\ic\cva5-master-annotated-20261107\.slang\server.json
```

当前活动测试的配置：

```json
{
  "build": "verification/unit/branch_comparator/branch_comparator.f",
  "buildRelativePaths": true,
  "index": [
    {
      "dirs": ["verification"],
      "excludeDirs": ["build"]
    }
  ]
}
```

`.slang/server.json` 必须放在 VS Code 工作区根目录，不是放在模块目录里。

### 6. 重启 Slang

VS Code：

```text
Ctrl + Shift + P
Slang: Restart Language Server
```

或者：

```text
Developer: Reload Window
```

### 7. 运行测试

```bash
cd /mnt/e/ic/cva5-master-annotated-20261107/verification/unit/branch_comparator
bash scripts/run_verilator.sh
```

成功输出示例：

```text
BRANCH_COMPARATOR TEST PASSED: N checks
```

## 基础包文件

大多数模块至少需要：

```text
core/types_and_interfaces/cva5_config.sv
core/types_and_interfaces/riscv_types.sv
core/types_and_interfaces/csr_types.sv
core/types_and_interfaces/cva5_types.sv
core/types_and_interfaces/fpu_types.sv
core/types_and_interfaces/opcodes.sv
```

## 额外依赖示例

| 模块 | 额外依赖 |
|---|---|
| `cva5_fifo` | `internal_interfaces.sv`，深度大于等于 3 时还需要 `lfsr.sv`、`lutram_1w_1r.sv` |
| `alu_unit` | `barrel_shifter.sv` |
| `load_store_unit` | `store_queue.sv`、`load_store_queue.sv`、`addr_hash.sv` 等 |
| MMU/LSU 子系统 | 需要对应 TLB、LSU、接口和缓存依赖 |

依赖不确定时查看：

```text
tools/compile_order
```

## 三处连接必须一致

```text
1. TB：实例化真实模块
2. run_verilator.sh：加入 DUT 源文件
3. <module>.f：加入 DUT 源文件
```

如果 Verilator 运行 PASS，但 VS Code 仍显示：

```text
unknown module 'xxx'
```

说明只是 Slang 配置问题：

- 检查根目录 `.slang/server.json`；
- 检查 `<module>.f`；
- 重启 Slang 语言服务器；
- 确认 VS Code 工作区根目录是 `cva5-master-annotated-20261107`。

## 新模块检查清单

- [ ] 创建 `verification/unit/<module>` 目录
- [ ] TB 中实例化真实模块
- [ ] TB 中写参考模型和 check 任务
- [ ] `run_verilator.sh` 加入基础包、DUT、TB
- [ ] `<module>.f` 加入相同源文件
- [ ] 根目录 `.slang/server.json` 指向当前 filelist
- [ ] 重启 Slang
- [ ] 运行测试并确认 PASS
- [ ] 故意制造一次 FAIL
- [ ] 恢复后再次确认 PASS

## 推荐验证顺序

```text
priority_encoder
    ↓
barrel_shifter
    ↓
branch_comparator
    ↓
clz / one_hot_to_integer / round_robin
    ↓
cva5_fifo / register_file
    ↓
alu_unit / mul_unit / div_unit
    ↓
load_store_unit / AXI
    ↓
fetch / icache / MMU
    ↓
CVA5 核级 C/汇编回归
    ↓
UVM
```

## 已有参考项目

```text
E:\ic\cva5-master-annotated-20261107\verification\unit\priority_encoder
```

运行：

```bash
cd /mnt/e/ic/cva5-master-annotated-20261107/verification/unit/priority_encoder
bash scripts/run_verilator.sh
```

预期结果：

```text
PRIORITY_ENCODER TEST PASSED: 256 checks
```