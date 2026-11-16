<!-- 由 CVA5新模块验证配置完整指南.docx 转换生成，保留原文结构和内容。 -->

# CVA5 新模块验证配置完整指南

> 从新建目录、实例化 DUT 到 Verilator、Slang 和运行脚本

| 项目 | 内容 |
| --- | --- |
| 目标工程 | E:\ic\cva5-master-annotated-20261107 |
| 示例模块 | branch_comparator |
| 示例验证目录 | verification\unit\branch_comparator |
| 示例 DUT | core\execution_units\branch_comparator.sv |
| 参考已有项目 | verification\unit\priority_encoder |
| 运行工具 | Verilator 5.008 |
| 编辑器解析 | Slang + .slang/server.json |

> **核心结论**
> 新建一个模块验证，必须同时配置三处：TB 中实例化 DUT、Verilator 脚本加入 DUT 源码、根目录 Slang build 文件加入 DUT 源码。三者缺一都会导致运行失败或编辑器报 unknown module。

## 1 新模块验证需要准备什么

以一个模块为例，至少要准备以下内容。

| 项目 | 作用 | 示例 |
| --- | --- | --- |
| 验证目录 | 存放 TB、脚本、日志 | verification/unit/branch_comparator |
| 被测模块路径 | 真实 CVA5 RTL | core/execution_units/branch_comparator.sv |
| TB 文件 | 实例化 DUT、产生激励、比较结果 | tb/tb_branch_comparator.sv |
| run 脚本 | 调用 Verilator 编译和运行 | scripts/run_verilator.sh |
| Slang filelist | 让编辑器知道 DUT 和 TB | branch_comparator.f |
| 根 Slang 配置 | 指向当前 filelist | .slang/server.json |

不是所有模块都需要相同的依赖文件。基础包文件通常是共享的，模块自身的依赖要额外加入。

## 2 标准目录结构

新模块验证目录

```text
E:\ic\cva5-master-annotated-20261107
└─ verification
   └─ unit
      └─ branch_comparator
         ├─ tb
         │  └─ tb_branch_comparator.sv
         ├─ scripts
         │  └─ run_verilator.sh
         ├─ build
         ├─ logs
         └─ waves
```

被测源码仍然在 CVA5 的 core 目录中，不要复制一份 RTL 到验证目录。验证平台直接引用原始 RTL。

被测模块固定路径

```text
E:\ic\cva5-master-annotated-20261107\core\execution_units\branch_comparator.sv
```

## 3 第一处配置：TB 实例化 DUT

TB 文件：

```text
verification/unit/branch_comparator/tb/tb_branch_comparator.sv
```

端口声明必须与 DUT 完全一致。branch_comparator 的端口是：

```text
input  logic        less_than
input  logic [32:0] a
input  logic [32:0] b
input  logic        xor_result
output logic        result
```

TB 模块中的实例化：

TB 与 DUT 的连接

```text
module tb_branch_comparator;

    logic        less_than;
    logic [32:0] a;
    logic [32:0] b;
    logic        xor_result;
    logic        result;

    branch_comparator dut (
        .less_than(less_than),
        .a(a),
        .b(b),
        .xor_result(xor_result),
        .result(result)
    );

endmodule
```

层次关系：

```text
tb_branch_comparator
└─ dut : branch_comparator
```

> **关键点**
> TB 中的模块名 branch_comparator 必须与 RTL 文件中的 module branch_comparator 完全一致；实例名 dut 可以自定义。

## 4 第二处配置：Verilator 运行脚本

运行脚本：

```text
verification/unit/branch_comparator/scripts/run_verilator.sh
```

完整模板：

run_verilator.sh

```text
#!/usr/bin/env bash
set -euo pipefail

ROOT=/mnt/e/ic/cva5-master-annotated-20261107/verification/unit/branch_comparator
CVA5=/mnt/e/ic/cva5-master-annotated-20261107
export PATH=/root/ic/tools/verilator-v5.008/bin:$PATH

cd "$ROOT"

verilator --binary --timing -Wall -Wno-fatal \
  --Mdir build -o tb_branch_comparator \
  --top-module tb_branch_comparator \
  "$CVA5/core/types_and_interfaces/cva5_config.sv" \
  "$CVA5/core/types_and_interfaces/riscv_types.sv" \
  "$CVA5/core/types_and_interfaces/csr_types.sv" \
  "$CVA5/core/types_and_interfaces/cva5_types.sv" \
  "$CVA5/core/types_and_interfaces/fpu_types.sv" \
  "$CVA5/core/types_and_interfaces/opcodes.sv" \
  "$CVA5/core/execution_units/branch_comparator.sv" \
  tb/tb_branch_comparator.sv

./build/tb_branch_comparator
```

脚本中必须同时有：

```text
CVA5 基础包
+ 被测模块 branch_comparator.sv
+ TB tb_branch_comparator.sv
```

如果只写 TB，Verilator 会报找不到模块。

## 5 第三处配置：Slang filelist

文件：

```text
verification/unit/branch_comparator/branch_comparator.f
```

使用相对 filelist 的路径：

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

路径层级：

```text
branch_comparator.f
    ../../../ = cva5-master-annotated-20261107
```

## 6 根目录 Slang 配置

文件必须位于 VS Code 工作区根目录：

```text
E:\ic\cva5-master-annotated-20261107\.slang\server.json
```

内容：

server.json

```text
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

它告诉 Slang：

```text
当前工作区根目录：cva5-master-annotated-20261107
当前活动的构建文件：branch_comparator.f
索引目录：verification
```

> **不要放错位置**
> .slang/server.json 必须放在整个 CVA5 工程根目录，不是放在 branch_comparator 里。只有工作区根目录的配置会被 Slang 读取。

## 7 重启 Slang 并运行

在 VS Code 中：

`Ctrl + Shift + P`

执行：

`Slang: Restart Language Server`

或者：

`Developer: Reload Window`

然后在 WSL 中运行：

```text
cd /mnt/e/ic/cva5-master-annotated-20261107/verification/unit/branch_comparator
bash scripts/run_verilator.sh
```

成功时输出：

`BRANCH_COMPARATOR TEST PASSED: N checks`

## 8 模块依赖怎么加

基础包通常需要：

```text
cva5_config.sv
riscv_types.sv
csr_types.sv
cva5_types.sv
fpu_types.sv
opcodes.sv
```

不同模块还需要额外文件：

| 模块 | 额外依赖 | 说明 |
| --- | --- | --- |
| priority_encoder | 无 | 只依赖基础包 |
| barrel_shifter | 无 | 只依赖基础包 |
| branch_comparator | 无 | 只依赖基础包 |
| cva5_fifo | internal_interfaces.sv | 使用 fifo_interface |
| cva5_fifo | lfsr.sv、lutram_1w_1r.sv | 深度大于等于 3 时 |
| alu_unit | barrel_shifter.sv | ALU 内部实例化移位器 |
| load_store_unit | store_queue、load_store_queue、addr_hash 等 | 依赖更多访存模块 |

依赖不确定时，优先查 CVA5 的编译顺序：

```text
E:\ic\cva5-master-annotated-20261107\tools\compile_order
```

## 9 第三处连接必须保持一致

同一个新测试要同步维护三处：

| 位置 | 需要写什么 |
| --- | --- |
| TB 文件 | 实例化真实模块 |
| run_verilator.sh | 把 DUT 源码加入 Verilator 编译 |
| <module>.f | 把 DUT 源码加入 Slang 编译 |

只要其中一处漏掉，就会出现：

```text
Verilator: Cannot find module
VS Code Slang: unknown module '<module>'
```

判断方法：

```text
run_verilator.sh 通过
    -> RTL 和 TB 编译正确

VS Code 仍红：
    -> Slang filelist 或 server.json 没配置好
```

## 10 完整检查清单

- 创建 verification/unit/<module> 目录。

- 在 TB 中实例化同名真实 RTL 模块。

- TB 中写参考模型和 check 任务。

- run_verilator.sh 中加入基础包、DUT 和 TB。

- 创建 <module>.f，并列出相同文件。

- 根目录 .slang/server.json 指向当前 <module>.f。

- 重启 Slang。

- 运行 run_verilator.sh。

- 确认 PASS。

- 故意制造一个错误，确认 FAIL。

- 恢复并再次确认 PASS。

## 11 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| unknown module | Slang filelist 没包含 DUT | 检查 .f 和 server.json |
| Verilator cannot find module | run 脚本没包含 DUT | 检查 run_verilator.sh |
| 找不到 package | 基础包没编译 | 加入 types_and_interfaces 下的包文件 |
| 找不到 interface | 模块依赖 interface | 加入 internal/external_interfaces.sv |
| PASS 但没有实际测试 | TB 没有 check 任务 | 增加输入、期望值和比较 |
| 红色波浪线但运行 PASS | 只是 Slang 配置问题 | 重启 Slang 或检查工作区根目录 |

## 12 当前可复用示例

已有可运行示例：

已验证示例

```text
E:\ic\cva5-master-annotated-20261107\verification\unit\priority_encoder
```

可复制的文件：

```text
tb/tb_priority_encoder.sv
scripts/run_verilator.sh
priority_encoder.f
```

复制后把：

`priority_encoder`

替换为新的模块名，并同步修改三处连接：

```text
1. TB 实例化
2. run_verilator.sh 的 DUT 文件
3. <module>.f 的 DUT 文件
```
