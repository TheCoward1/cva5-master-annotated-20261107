# CVA5 common_components 验证顺序

本文档给出 `core/common_components/` 下模块的建议验证顺序、依赖关系、测试重点和当前状态。目标是先验证基础原语，再验证时序和存储结构，最后验证 FIFO 与轮询仲裁，避免在复杂模块中同时排查多个未知问题。

## 1. 范围

本文覆盖：

```text
core/common_components/
├── priority_encoder.sv
├── one_hot_to_integer.sv
├── clz.sv
├── set_clr_reg_with_rst.sv
├── cycler.sv
├── lfsr.sv
├── round_robin.sv
├── toggle_memory.sv
├── toggle_memory_set.sv
├── cva5_fifo.sv
└── ram/
    ├── sdp_ram.sv
    ├── sdp_ram_padded.sv
    ├── tdp_ram.sv
    ├── lutram_1w_1r.sv
    └── lutram_1w_mr.sv
```

`barrel_shifter`、乘除法单元等执行单元位于 `core/execution_units/`，不属于本文范围。

## 2. 当前状态

| 模块 | 当前状态 | 说明 |
|---|---|---|
| `priority_encoder` | 已验证第一版 | `WIDTH=8` 穷举 256 个输入并 PASS；其他 WIDTH 仍建议补齐 |
| `clz` | TB 草稿存在 | 目前有测试草稿，尚未按标准 unit 目录和回归流程整理 |
| `cva5_fifo` | 注释完成，验证待开始 | 已说明三种深度实现，尚无标准 FIFO 回归 |
| `one_hot_to_integer` | 未开始 | 建议尽早完成，输入约束简单 |
| `set_clr_reg_with_rst` | 未开始 | 基础时序模块 |
| `cycler` | 未开始 | 基础轮转状态模块 |
| `lfsr` | 未开始 | FIFO 深度大于等于 3 时使用 |
| `round_robin` | 未开始 | 轮询仲裁，建议放在基础时序模块之后 |
| RAM 原语 | 未开始 | 先验证基础 RAM，再验证 padded/wrapper |
| `toggle_memory*` | 未开始 | 建议在简单 RAM 之后验证 |

## 3. 验证原则

1. 先组合逻辑，后时序逻辑。
2. 先无依赖原语，后有依赖的复合模块。
3. 先基础 RAM，再 RAM wrapper。
4. 先 LFSR 和 LUTRAM，再 `cva5_fifo`。
5. 每次模块验证都必须有独立参考模型、自动 PASS/FAIL、日志和波形。
6. 不只测试正常路径；同时检查复位、边界值、随机输入、背压和同周期冲突。
7. 不把“仿真没有报错”当成验证完成；必须有明确检查点和验收结果。

## 4. 推荐总顺序

```text
第一阶段：组合逻辑
priority_encoder
    -> one_hot_to_integer
    -> clz

第二阶段：基础时序模块
set_clr_reg_with_rst
    -> cycler
    -> lfsr

第三阶段：存储器原语
sdp_ram
    -> sdp_ram_padded
    -> tdp_ram
    -> lutram_1w_1r
    -> lutram_1w_mr

第四阶段：状态存储模块
toggle_memory
    -> toggle_memory_set

第五阶段：FIFO 与仲裁
cva5_fifo
    -> round_robin
```

`cva5_fifo` 放在后面的原因：

- 深度为 1 和 2 时有独立实现；
- 深度大于等于 3 时依赖 `lfsr` 和 `lutram_1w_1r`；
- 同时包含 `push/pop`、`valid/full`、`potential_push`、同周期读写和断言；
- 如果把 `cva5_fifo` 放在最前面，会把 LFSR、RAM、FIFO 协议的问题混在一起。

## 5. 分阶段模块清单

### 阶段 A：组合逻辑

#### A1. priority_encoder

源码：

```text
core/common_components/priority_encoder.sv
```

测试重点：

- `WIDTH=1,2,3,4,8,14`；
- 最低有效置位位；
- 全零输入输出 `WIDTH-1`；
- bit0 优先级最高；
- 多 bit 同时为 1；
- 穷举所有输入组合。

建议验收：

```text
每个 WIDTH 的输出与参考模型一致
所有输入组合通过
```

#### A2. one_hot_to_integer

源码：

```text
core/common_components/one_hot_to_integer.sv
```

测试重点：

- `C_WIDTH=1,2,3,4,8,40`；
- 每个合法的 one-hot 输入；
- 输出索引是否与置位位一致；
- 零输入和多 bit 同时为 1 的行为需要先明确：该模块不是通用优先级编码器，输入必须按 one-hot 使用。

建议验收：

```text
每个 one-hot 位置的输出索引正确
不合法输入的后果在报告中明确记录
```

#### A3. clz

源码：

```text
core/common_components/clz.sv
```

测试重点：

- `WIDTH=2,3,4,5,8,16,32`；
- 全零输入时 `zero=1`；
- 输入非零时 `clz` 是正确的前导零个数；
- 最高位为 1；
- 最低位为 1；
- 非 2 的幂位宽，例如 3、5、6、7；
- 与参考模型逐一比较。

建议验收：

```text
zero 标志正确
所有 WIDTH 下 clz 与参考模型一致
```

### 阶段 B：基础时序模块

#### B1. set_clr_reg_with_rst

测试重点：

- 复位优先级；
- set 和 clear 同时有效时的优先级；
- set 后保持；
- clear 后保持；
- 连续翻转和随机输入。

#### B2. cycler

测试重点：

- `C_WIDTH=1,2,3,4,8`；
- 复位后的 one-hot 初值；
- `en=0` 时保持不变；
- `en=1` 时循环移位；
- 多次旋转后回到初始位置。

#### B3. lfsr

测试重点：

- `WIDTH=3..16`；
- 复位值；
- `en=0` 时保持；
- `en=1` 时按 LFSR 序列更新；
- 在完整周期内是否遍历所有预期状态；
- 不使用未定义或越界的参数。

### 阶段 C：存储器原语

RAM 模块必须先确认每个模块的实际端口和时序，再写参考模型。

#### C1. sdp_ram

建议测试：

- 单写单读；
- 写后读；
- 同周期写和读；
- 地址边界；
- 非 2 的幂深度时的实际存储深度和地址范围；
- 初始化值；
- 写使能无效时不修改存储内容。

#### C2. sdp_ram_padded

该模块依赖：

```text
sdp_ram
```

测试重点：

- 先复用 `sdp_ram` 的基础用例；
- 检查 padding 后的地址映射；
- 检查读写数据是否被错误地截断或扩展；
- 检查 wrapper 没有改变 sdp_ram 的行为。

#### C3. tdp_ram

测试重点：

- 两个端口的独立读写；
- 同地址同时写；
- 一端写、另一端读；
- 地址边界；
- 写冲突时模块规定的优先级。

#### C4. lutram_1w_1r

测试重点：

- 单写口、单读口；
- 写使能；
- 写后读；
- 同周期读写；
- RAM 深度和地址位宽；
- 初始化值。

#### C5. lutram_1w_mr

该模块依赖：

```text
lutram_1w_1r
```

测试重点：

- 多读端口的读数据一致性；
- 写端口更新后各读端口的可见性；
- 多读地址组合；
- 读端口随机地址；
- 写使能关闭时数据保持。

### 阶段 D：状态存储模块

#### D1. toggle_memory

测试重点：

- 写入、保持和读出；
- 地址切换；
- 写使能；
- 初始化值。

#### D2. toggle_memory_set

测试重点：

- set 操作；
- clear 操作；
- 同时 set/clear；
- 随机操作序列；
- 与参考数组模型比较。

### 阶段 E：FIFO 与轮询仲裁

#### E1. cva5_fifo

该模块的依赖：

```text
FIFO_DEPTH == 1：无额外依赖
FIFO_DEPTH == 2：无额外依赖
FIFO_DEPTH >= 3：lfsr + lutram_1w_1r + internal_interfaces
```

建议测试深度：

```text
1, 2, 3, 4, 5, 8
```

测试重点：

- 复位后 `valid=0`、`full=0`；
- 单次 push；
- 单次 pop；
- 连续 push 到满；
- 连续 pop 到空；
- 同周期 push 和 pop；
- 满时 push + pop；
- 空时 pop + push；
- `potential_push` 的预写行为；
- 随机 push/pop；
- 随机 pop 背压；
- 溢出和下溢断言；
- `data_out` 在 `valid=0` 时不得被消费者使用；
- 深度 1、2、3 的分支都要分别覆盖。

建议参考模型：

```text
用一个队列或数组保存 FIFO 当前内容
push 时比较 full 和写入数据
pop 时比较 valid 和读出数据
每次操作后比较队列长度、valid、full
```

#### E2. round_robin

测试重点：

- `NUM_PORTS=1`；
- `NUM_PORTS=2,3,4,8`；
- 单请求；
- 多请求；
- `grant` 后状态推进；
- 多个周期后的公平性；
- 所有请求持续有效时不出现饥饿；
- 复位状态。

## 6. 模块依赖关系

```text
priority_encoder
one_hot_to_integer
clz
set_clr_reg_with_rst
cycler
lfsr
round_robin

lutram_1w_1r
    -> lutram_1w_mr

sdp_ram
    -> sdp_ram_padded

lfsr + lutram_1w_1r
    -> cva5_fifo (FIFO_DEPTH >= 3)
```

## 7. 每个模块的固定验证流程

每个模块都按以下流程执行：

1. 阅读端口、参数、内部状态和时序假设。
2. 编写验证计划和测试矩阵。
3. 编写独立参考模型。
4. 实例化真实 CVA5 RTL，不复制 RTL 到验证目录。
5. 加入定向测试。
6. 加入边界测试和随机测试。
7. 加入必要断言。
8. 保存日志和波形。
9. 写模块验证报告。

## 8. 标准目录

```text
verification/unit/<module>/
├── tb/
│   └── tb_<module>.sv
├── scripts/
│   └── run_verilator.sh
├── <module>.f
├── build/
├── logs/
├── waves/
└── README.md
```

## 9. 每个模块的最低验收标准

- 参考模型和 DUT 的输入输出语义一致；
- 所有定向用例通过；
- 所有边界用例通过；
- 随机用例无 mismatch；
- 同周期冲突和复位行为明确；
- 失败时能打印输入、期望值和实际值；
- 同一命令可以重复运行；
- 有日志和波形；
- 有一页验证报告；
- 明确说明没有覆盖的情况。

## 10. 下一步建议

当前最推荐的下一步是：

```text
1. 完成 priority_encoder 的 WIDTH=1..14 参数化回归
2. 将 clz 的 TB 整理到 verification/unit/clz
3. 完成 one_hot_to_integer
4. 完成 lfsr 和 lutram_1w_1r
5. 最后开始 cva5_fifo
```

不要一开始就同时验证 `cva5_fifo`、RAM、LFSR 和 FIFO 协议。先把基础模块的参考模型和回归脚本固定下来，后面的复合模块才能快速定位问题。
