# CVA5 core 全部模块验证学习顺序（按现有 TB 写法）

更新日期：2026-11-17。覆盖 `core/` 全部 76 个 module 及 8 个包/接口文件；公共组件保持具体计划，第 7 节将其余 61 个模块逐项展开。

本版依据实际 RTL、`verification/unit/` 中已有 TB、脚本和保存的结果更新。**本次只更新学习与验证计划，没有重新运行仿真；“已有 TB”“历史日志 PASS”“待补验证”分别记录。**

## 1. 沿用现在的写法

继续使用参数化 SystemVerilog 自检查 TB。每次学习一个新模块，先完成它的参考模型和定向检查，再增加随机激励、覆盖率和参数配置。当前阶段无需引入新的验证框架。

沿用已有结构：

```text
tb_<module> #(...)(output logic done)
    ├── 信号、参数、参考状态或 ref_mem
    ├── 实例化真实 CVA5 DUT
    ├── function automatic：计算期望值
    ├── task automatic：驱动一次操作并比较
    ├── 定向 → 边界 → 随机 → 最终检查
    └── 统计 checks / errors，结束时 done=1

tb_<module>_top
    ├── generate 多个参数配置
    ├── wait (&done)
    └── 打印整体 PASS，再 $finish
```

- 组合模块：驱动输入，等待组合逻辑稳定，再与独立函数比较。
- 时序模块：通常在 `negedge` 驱动，`posedge` 完成操作；需要检查更新后的寄存器时，在 NBA 更新后采样，例如当前 TB 使用的 `#1`。
- 有时钟的 TB 显式设置 `` `timescale 1ns/1ps ``，不依赖编译文件顺序继承时间单位。
- RAM：参考数组保存逻辑数据；带读流水线时，再维护预期响应队列与有效标志。
- FIFO：用 SystemVerilog 队列保存逻辑顺序，不照抄 DUT 的 LFSR、指针或补码计数实现。
- 比较使用 `!==`；失败打印配置、操作、地址/输入、期望值和实际值，并用 `$fatal(1, ...)` 退出。
- 多实例顶层加总超时，避免某个实例未置 `done` 导致仿真一直运行。
- covergroup、cross、SVA 随验证点逐步加入；覆盖率与结果比较一起使用，不用覆盖率代替功能检查。

## 2. 当前实际进度

下表路径相对于工程根目录。历史结果只说明保存的那次运行，不代表当前源码已全部重新回归。

| 模块 | 已有验证内容 | 当前证据与后续工作 |
|---|---|---|
| `priority_encoder` | `unit/priority_encoder`；`WIDTH=1..14`，每种位宽穷举 | 14 份历史日志均 PASS，合计 32766 次检查；保留为组合逻辑参考工程 |
| `one_hot_to_integer` | `unit/tb_one_hot_to_integer`；默认宽度 40，逐 bit、全零、多 bit | 已有 TB；先纠正多 bit 输入被期望为 0 的假设，再补宽度扫描 |
| `clz` | `unit/tb_clz.sv`；默认 32 位，13 个定向、32 个单 bit、10000 个随机输入 | 已有 TB 和 VCS 扫描脚本；补参数化激励、`WIDTH=2` 和大位宽，统一检查次数输出 |
| `set_clr_reg_with_rst` | `unit/tb_set_clr_reg_with_rst`；7 种位宽、两种优先级、随机激励、covergroup | 已有 TB 与覆盖率产物；补每种位宽与优先级的交叉配置、非零复位值及中途复位 |
| `cycler` | `unit/tb_cycler`；11 种位宽，复位/使能四种组合，covergroup | 已有 TB 与覆盖率产物；补随机暂停恢复、长时间轮转和中途复位 |
| `lfsr` | `unit/tb_lfsr`；宽度 3..16，`NEEDS_RESET=0/1`，完整周期去重、随机控制、复位 SVA | 已有 TB；补宽度 1、2 的分支核对，特别是 FIFO 实际使用的宽度 2 |
| `round_robin` | `unit/tb_round_robin`；端口数 1..4，请求遍历、随机、交叉覆盖 | 历史 `sim.log` 记录整体 PASS；补持续竞争、公平性和 `grant=0` 的状态保持 |
| `lutram_1w_1r` | `unit/tb_ram/tb_lutram_1w_1r`；深度/字宽扫描、读写与参考数组、随机访问 | 已有 TB 与覆盖率产物；补 64 位高半部分激励、明确同址时钟沿前后读值 |
| `lutram_1w_mr` | `unit/tb_ram/tb_lutram_1w_mr`；深度/字宽扫描、多读比较、连续写与随机访问 | 已有 TB；当前回归固定 2 个读口，补 1/4 个读口及厂商分支 |
| `sdp_ram` | 未发现对应独立 TB | 推荐的下一个新模块 |
| `sdp_ram_padded` | 未发现对应独立 TB | 接在 `sdp_ram` 后面，复用逻辑存储模型 |
| `tdp_ram` | 未发现对应独立 TB | 学习双端口并发、部分写、有效读响应和预加载 |
| `toggle_memory` | 未发现对应独立 TB | 接在多读 LUTRAM 后，学习按地址翻转 |
| `toggle_memory_set` | 未发现对应独立 TB | 接在 `toggle_memory` 后，学习多写口异或合并和初始化清理 |
| `cva5_fifo` | 未发现对应独立 TB | 最后综合队列模型、边界协议、背压和已有基础组件 |

这里的 `unit/...` 均位于 `verification/unit/...`。现有目录名继续保留，整理命名不作为开始下一模块的前提。

## 3. 从当前进度继续的顺序

已有基础模块不必从零重写；先补会影响后续参考模型和依赖的项目。

```text
第 0 步：已有 TB 收尾
    one_hot_to_integer：明确 one-hot 输入约束，纠正多 bit 期望值
    clz：修正参数化激励和脚本统计
    lfsr：补 WIDTH=2（深度 3/4 FIFO 会用到）
    LUTRAM：补必要读口、数据位和厂商分支

新增模块学习主线
    1. sdp_ram
       ↓
    2. sdp_ram_padded（内部使用真实 sdp_ram）
       ↓
    3. tdp_ram
       ↓
    4. toggle_memory（内部使用真实 lutram_1w_mr）
       ↓
    5. toggle_memory_set（内部使用真实 toggle_memory 和 lfsr）
       ↓
    6. cva5_fifo（深度 1 → 2 → 3/4 → 5/8/16）
       ↓
    公共组件统一回归 → 简单执行模块 → 带握手执行单元 → 子系统 → 整核
```

这是学习顺序；`sdp_ram/tdp_ram` 不是 `cva5_fifo` 的依赖。如果想先练队列和背压，在完成 LFSR 与 LUTRAM 必要补测后，也可以把 FIFO 提前到这两条 RAM 学习线之前。

`round_robin` 已有独立验证，不再放到 FIFO 后面当作新模块。它与 FIFO 没有直接实例化依赖。

## 4. 已有 TB 先补哪些点

### 4.1 组合模块

- `priority_encoder`：保留 1..14 穷举回归；全零时结果为 `WIDTH-1`，`WIDTH=1` 时结果为 0。
- `one_hot_to_integer`：补 `C_WIDTH=1,2,3,4,8,40`。全零输出 0；多 bit 输入超出正常 one-hot 使用约束，当前 RTL 输出为所有置位索引的按位 OR，例如 bit0、bit1 同时为 1 时得到 1。可以独立观察该实现行为，或在正常激励中约束 `$onehot0`，不能把“多 bit 必须输出 0”写成模块规格。
- `clz`：用 `width` 驱动单 bit 循环、定向值和随机向量，不能只把 32 位激励截断到较小参数。小位宽 2..10 可穷举；较大位宽建议 16、32、54、157，后两项对应当前 FPU 的实际用法。全零只检查 `zero=1`；非零输入再比较 `clz`。
- `clz` 脚本当前匹配 `CHECKS=数字`，TB 输出 `数字 checks`，需要统一；脚本扫描 3..10 也不等于已做穷举测试。

### 4.2 时序模块

- `set_clr_reg_with_rst`：每个选定 WIDTH 都分别验证 `SET_OVER_CLR=0/1`；`RST_VALUE` 加入全 1、交替位。参考状态只能随实际复位或操作更新，不能仅在 TB 中重置期望值。检查操作前后保持、中途复位、复位与 set/clr 重叠。
- `cycler`：随机切换 `en`，连续旋转若干完整周期后暂停，再恢复；周期与 WIDTH 对齐；`C_WIDTH=1` 为常量 1 分支。
- `lfsr`：3..16 的全周期检查继续保留；补 1、2 分支的编译和功能核对。`NEEDS_RESET=0` 的 RTL 不保证启动为 0，四态仿真下允许明确记录的一次性 TB 初始化（沿用现有 force/release），不能把它写成硬件复位能力。全周期不重样检查比单纯复制抽头表更能发现问题。
- `round_robin`：`grant` 是输入，表示选择被接受；只有 `grant=1` 才更新轮转状态。持续所有请求且每拍接受时，每个端口在 NUM_PORTS 次接受中应被选中一次。`grant=0` 保持的是内部状态，若请求改变，组合 `grantee` 仍可能变化；无请求时不把输出索引当成有效授权。

### 4.3 已有 LUTRAM

- `lutram_1w_1r`：继续保留深度 1/2/3/5/8/32 与字宽 1/8/32/64。64 位随机数据要逐段生成，例如拼接两次 `$urandom`；walking-one 在完整 `data_t` 上移位，避免先用 32 位表达式移位后再扩展。
- 两种 LUTRAM 都是同步写、组合读。对同地址，在写时钟沿前与 NBA 更新后分别检查，不能把读口当作同步流水响应。
- `lutram_1w_mr`：补 `NUM_READ_PORTS=1,2,4`；同址、多址及持续写时各读口均检查。当前 `FPGA_VENDOR=XILINX`，Intel 分支会实例化多个 `lutram_1w_1r`，需要对应编译依赖和独立运行结果；未运行的分支明确标为未覆盖。
- `DEPTH=1` 时原 RTL 的 `$clog2(DEPTH)-1:0` 存在退化范围，TB 使用最小 1 位地址并不等于 RTL 已支持干净的单元素接口；单列记录工具诊断和地址 0 行为。

## 5. 六个新增模块的具体计划

### 5.1 sdp_ram：下一个新模块

学习目标：从现有组合读 LUTRAM 过渡到同步读、分列写使能和可配置输出流水线。

建议先跑 `ADDR_WIDTH=3, NUM_COL=4, COL_WIDTH=8, PIPELINE_DEPTH=0`；一套参考模型稳定后，再扩配置。

| 参数 | 建议配置 |
|---|---|
| `ADDR_WIDTH` | 1、2、3、5；实际深度始终是 `2**ADDR_WIDTH` |
| `NUM_COL` | 1、2、4 |
| `COL_WIDTH` | 1、8、9、16、17 |
| `PIPELINE_DEPTH` | 0、1、2 |

不必一开始跑全部笛卡尔积：先固定配置做定向，再分别扫描列数、列宽、地址位宽，重点交叉写掩码与读延迟。

必须检查：

1. 内存数组初始为 0，但读输出/流水寄存器没有复位；只在已知读请求传播到输出后比较。
2. `a_en=0` 或 `a_wbe='0` 不写；逐列写、交替掩码和全列写；未写列保持原值。
3. 地址 0、最后地址、地址独立性、连续覆盖写、随机混合访问。
4. `b_en` 为 1 时采样读地址；插空读使能，检查输出流水中的旧请求仍正确完成。
5. `PIPELINE_DEPTH=0` 仍有基础同步读寄存器。若在上升沿 k 接受读请求，输出在该沿 NBA 后可用；参数为 P>0 时再经过 P 个上升沿后可用，不是组合读。
6. 参考模型先计算该沿读取的旧存储值，再合并写掩码；同沿同址读写的当前 RTL 仿真读到更新前的数据。此结果不自动代表 FPGA 实体 RAM 的冲突保证。

参考模型由“逻辑数据数组 + 按列合并写入 + 预期读响应流水线”组成；优先补 `check_write_mask`、`check_read_latency`、`check_read_bubbles` 等小任务。

### 5.2 sdp_ram_padded：第一次自然组合验证

直接实例化 `sdp_ram_padded`，让它内部连接真实 `sdp_ram`；TB 仍只按外部逻辑列宽维护参考数组。

- 覆盖 `NUM_COL=1` 的直通分支。
- 覆盖多列、`COL_WIDTH=8,9,16,18` 的无填充分支。
- 覆盖多列、`COL_WIDTH=7,10,12,17` 的有填充分支；按 RTL 的 8/9 倍数规则计算填充量。
- 每列使用可区分模式，再逐列使能，检查数据位序、列边界和未写列保持。
- 复用 `sdp_ram` 的读延迟与插空用例；填充改变内部列宽，不改变外部地址深度或读时序。
- 内部 padding 位可为 X，TB 只比较对外有效数据位，不要求隐藏填充位为 0。

### 5.3 tdp_ram：双端口并发

建议先固定 `ADDR_WIDTH=3, NUM_COL=4, COL_WIDTH=8`，再扫描 `PIPELINE_DEPTH=0,1,2` 和部分列写。

- A/B 各自读写；两端同时读、写不同地址；同址写不重叠列；一端写而另一端读。
- 同一端口只在 `en=1` 且全部写掩码为 0 时采样新读数据。该端口写入期间不产生新的内存读值；已接受的读值仍可能在输出流水中传播。
- 无预加载时，存储体没有清零；参考模型设置每地址/每列有效标志，先写后读，不能要求未写数据为 0。
- `USE_PRELOAD=1` 单独测试，DUT 与参考模型加载同一份已知文件；不要用层次读取 DUT 存储阵列作为期望值。
- 同址同列同时双写没有固定 A/B 优先级。正常功能回归避免此冲突；如做冲突观察，单独记录为未规定场景，不按某次调度结果验收。
- 跨端口同沿同址读写可核对当前 RTL 的旧值读取语义，同时记录硬件 RAM 冲突行为需要另行确认。

### 5.4 toggle_memory：翻转存储

依赖：`lutram_1w_mr`；Intel 分支还需 `lutram_1w_1r`。

用一个 bit 数组作为参考模型：每个上升沿执行 `ref_mem[toggle_id] ^= toggle`，随后检查全部读口。

- 参数先选 `DEPTH=4,8,16`、`NUM_READ_PORTS=1,2,4`，再增加合法的非 2 的幂深度。
- 检查初始零值、`toggle=0` 保持、单次翻转、同址连翻两次恢复、多拍翻转奇偶性。
- 多读口同址和异址；读地址与翻转地址相同；在不同地址间连续切换。
- 模块没有复位或普通数据写入口；`toggle=0` 的保持通过写回旧值完成。不能沿用普通 RAM 的“写一个任意数据”任务。

### 5.5 toggle_memory_set：多写口翻转合并

依赖：`toggle_memory`、`lutram_1w_mr`、`lfsr`；Intel 分支再加 `lutram_1w_1r`。

先用 `DEPTH=8`、1 写口/1 读口跑通，再扩 `DEPTH=16,64`、写口 2/3、读口 2/4。这一轮优先选择 2 的幂深度，保证内部 LFSR 清理地址合法；非 2 的幂深度先审查清理地址范围，再决定是否纳入支持矩阵。

- `set` 在模块名中不能解释为一组 set/clr 端口：实际是多个独立 toggle 存储体对读结果做 XOR。
- 正常操作时，目标地址被奇数个有效写口同时翻转则取反，偶数个则保持；参考模型按地址统计翻转奇偶性。
- 检查所有写口关闭、单写口、多写口不同地址、两写口同址抵消、三写口同址翻转。
- `init_clear` 是遍历地址逐项清理，并非一个时钟沿清空全部存储。初始化与功能操作先分阶段，清理时关闭外部 toggle。
- 内部清理 LFSR 为 `NEEDS_RESET=0`；四态仿真如需 force/release 初值，沿用现有 LFSR TB 做法并明确记录，不能归因于 DUT 的复位。
- 除初始零检查外，必须先写出多个非零状态，再连续清理至少一个完整地址周期，最后全地址读回为 0；仅对原本全零的存储执行清理不能证明清理有效。
- 与清理同拍的外部翻转属于进阶场景，按真实 XOR/清理逻辑单列检查，不假设“全局清零永远优先”。

### 5.6 cva5_fifo：最后综合队列与边界协议

先深度 1，再 2，再 3/4，最后 5/8/16。`DATA_TYPE` 先用 8 位，再测 32 位和 packed struct。三种实现均需 `fifo_interface`；深度 >=3 额外依赖 `lfsr` 和 `lutram_1w_1r`。

| 场景 | 检查内容 |
|---|---|
| 复位、运行中复位 | 复位后 `valid=0, full=0`，逻辑队列清空；不要求无效输出数据清零 |
| 单 push / pop | 数据顺序、队列长度、`valid/full` |
| 连续写满、读空 | 精确在逻辑深度达到 full；最后元素读出后变空 |
| 非空同时 push/pop | 在沿前比较待出队的旧队首，再更新参考队列，沿后检查状态和新队首 |
| 满时同时 push/pop | 接受一次出队和入队，长度保持满，顺序正确 |
| 空时同时 push/pop | RTL 断言允许此边界；沿后长度仍为 0，不把沿前 `valid=0` 的 `data_out` 当作有效读值，也不假设组合直通新输入 |
| `potential_push=1,push=0` | 可以预写候选数据，但不增加逻辑长度、不使 FIFO 从空变有效；检查后续实际入队与可见数据 |
| 随机与背压 | 随机合法 push/pop、读端暂停、长时间环回、非 2 的幂逻辑深度 |
| 协议负例 | 溢出、下溢、满且无 pop 时的 potential_push 单独运行并预期断言报错 |

正常激励先使用 `potential_push=push`，再单独增加预写用例；未确认调用协议前，不把 `push=1,potential_push=0` 当成普通数据写入。

参考模型只依据实际 push/pop 改变队列长度；`potential_push` 不入队。比较输出数据前检查有效性；空时同时 push/pop 的净变化为 0，模型不能先对空队列做无条件 `pop_front()`。

该 FIFO 不自动阻止非法操作。正常回归遵守容量规则；协议负例使用独立日志及“预期失败”结果，不混入正常 PASS。

## 6. 哪些情况适合一次带上多个模块

“多个参数实例一起跑”和“多个功能模块组合验证”分别记录。前者沿用 `generate + done`；后者优先使用 RTL 中已经存在的自然连接。

| 验证顶层 | 由顶层自然带入的真实模块 | 用途 |
|---|---|---|
| `tb_sdp_ram_padded_top` | `sdp_ram_padded + sdp_ram` | 列填充与部分写的端到端数据检查 |
| `tb_lutram_1w_mr_top`，Intel 配置 | `lutram_1w_mr + 多个 lutram_1w_1r` | 写入复制到所有读副本 |
| `tb_toggle_memory_top` | `toggle_memory + lutram_1w_mr` | 读旧值、翻转、写回和多口可见性 |
| `tb_toggle_memory_set_top` | `toggle_memory_set + 多个 toggle_memory + LUTRAM + lfsr` | 同址多写口奇偶性、初始化清理 |
| `tb_cva5_fifo_top`，深度 >=3 | `cva5_fifo + lfsr + lutram_1w_1r` | 逻辑顺序、物理索引与容量边界 |

每个组合仍保留一个面向外部行为的参考模型。不用子模块输出生成期望值；组合 PASS 也不能替代子模块全部参数和分支的独立覆盖。

如果只是为了缩短运行时间，多个已有 TB 可由一个回归脚本逐项调用，不必改造成共享激励的混合 TB。

## 7. core 其余 61 个模块的逐模块验证路线

本节将此前的概览展开为逐模块计划。学习顺序结合依赖与 TB 难度安排；相互独立的支线可以穿插，不把学习先后误认为 RTL 实例化依赖。下列内容是计划，未在本轮创建新 TB 或运行回归；其他目录或独立工程的历史结果需另行核对。

### 7.1 覆盖范围与总路线

当前 `core/` 共 84 个 `.sv` 文件：76 个 module 文件，以及 8 个包/接口文件。前文覆盖 15 个公共组件，本节逐项覆盖其余 61 个 module。

| 源码位置 | module 数量 | 本文安排 |
|---|---:|---|
| `core/common_components/`，含 `ram/` | 15 | 第 2～6 节 |
| `core/execution_units/` 直属文件 | 10 | 简单组合、整数执行、CSR/GC |
| `core/` 直属文件 | 9 | 后端、仲裁与 CPU 顶层 |
| `core/memory_sub_units/` | 4 | 本地存储和三类总线 master |
| `core/fetch_stage/` | 5 | RAS、预测器、tag bank、I-cache、fetch |
| `core/mmu/` | 4 | 权限检查、页表遍历、ITLB/DTLB |
| `core/execution_units/load_store_unit/` | 8 | 地址 hash、原子运算/控制、队列、D-cache、LSU |
| `core/execution_units/fp_unit/`，含 `divider/` | 21 | 浮点专项 |

```text
公共组件基础
    → 简单组合模块
    → 简单握手单元 → ALU / MUL / DIV / BRANCH
    → 写回 / 空闲表 / 寄存器堆 / 重命名 / ID与退休 / 译码发射
    → 本地存储与总线接口 / 核内仲裁
    → 前端基础（RAS、预测、tag、I-cache）
    → 地址翻译（MMU、ITLB、DTLB）
    → 原子控制 / 访存队列 / D-cache / LSU
    → fetch / CSR / GC
    → 整数最小配置的 cva5 冒烟
    → FPU 子模块与组合专项 → 开启 FPU 的整核回归
    → 按缓存、AMO、特权与总线配置逐步扩展
```

无需先把 15 个公共组件全部做完才进入其他 core 模块。`barrel_shifter`、`branch_comparator`、`addr_hash`、`amo_alu`、`perms_check` 可现在穿插学习；`writeback` 可接在已有 priority_encoder 后，`custom_unit` 可作为第一个握手单元。

FPU 支线可以在掌握握手后独立学习；不要求完成全部浮点验证才能开始整数整核冒烟。`core_arbiter` 也可以在 round_robin 通过后提前学习。

### 7.2 types_and_interfaces：先读接口，再写对应 TB

这 8 个文件提供编译环境，不作为 8 个有输入输出端口的 DUT 顺序测试。涉及计算函数时，可以用小 TB 直接调用包函数并检查结果；结构位宽、字段和枚举与相应功能模块一起验证。

| 文件 | 写 TB 前需要掌握的内容 |
|---|---|
| `cva5_config.sv` | `cpu_config_t`、功能开关、写回组、MAX_IDS/RETIRE_PORTS、缓存推导参数；配置先从实际实例使用值起步 |
| `riscv_types.sv` | 指令字段、XLEN、寄存器地址、异常/中断/原子操作类型 |
| `csr_types.sv` | CSR 地址、权限、状态位、页表权限与特权类型 |
| `cva5_types.sv` | decode/issue/wb/retire 包、指令 ID、物理寄存器地址、GC 控制结构 |
| `fpu_types.sv` | 单双精度表示、NaN-boxing、舍入模式、fflags、浮点中间结果包 |
| `opcodes.sv` | 指令编码与分类常量；参考译码要独立判断字段，不直接读取 DUT 内部译码结果 |
| `internal_interfaces.sv` | unit_issue、unit_writeback、FIFO、TLB/MMU、寄存器堆、AMO 与浮点中间写回接口的方向和接受条件 |
| `external_interfaces.sv` | 本地 RAM、内部 mem、AXI、Avalon、Wishbone 的请求/响应和各地址单位 |

包/接口编译次序参考 `tools/compile_order`，再按 DUT 需要裁剪。`possible_issue`、`new_request`、`ready`、`done`、`ack` 的含义必须按各模块源码确认，不能套一套通用时序到所有接口实例。

### 7.3 阶段 A：5 个简单组合模块

这些模块适合接在公共组件之后，继续使用 `function automatic + check + #1`。`addr_hash`、`amo_alu` 位于 LSU 子目录，`perms_check` 位于 MMU 子目录，其余位于 execution_units。

| 序号 | 模块 | 参考模型/环境 | 必查内容 |
|---:|---|---|---|
| 1 | `barrel_shifter` | 独立 32 位移位函数 | 移位量 0..31、左/右移、填充位 0/1、单 bit/边界/随机。`arith` 本身是右移填充位，符号处理由调用方产生 |
| 2 | `branch_comparator` | 按真实 33 位端口建立比较函数 | 相等/大小比较、`xor_result` 取反、低两位差异、符号/零扩展边界；不要把输入改成 32 位 |
| 3 | `addr_hash` | 独立位分组 XOR 函数 | 12 位输入可穷举，`USE_BIT_3=0/1`；该参数实际控制 `addr[2]` 是否参与；hash 相同不代表地址相同 |
| 4 | `amo_alu` | ADD/SWAP/逻辑/MIN/MAX 独立函数 | 有符号/无符号最值、相等、溢出截断；LR/SC 与保留编码不是该 ALU 的有效算术操作，默认 X 不强行期望为 0 |
| 5 | `perms_check` | 权限真值表 | R/W/X/A/D/U、M/S/U、SUM/MXR 与合法 execute/rnw 组合；PTE 的 V 位及非法 RW 编码由上层 MMU 检查 |

### 7.4 阶段 B：6 个执行单元

继续用 task 驱动，但增加请求记录与 ID 比较。先用 TB 提供 decode、寄存器操作数、GC 和写回接受信号，逐步把运算模型扩展到事务模型。

| 序号 | 模块 | 依赖/参考模型 | 必查内容 |
|---:|---|---|---|
| 6 | `custom_unit` | 当前示例为 32 位 RS1+RS2；无下级 RTL | 适合第一个握手 TB：CUSTOM 译码、请求/ID、结果、延迟 ack、复位；`ready=~wb.done`，结果未接受时不持续发请求。默认配置关闭不妨碍单独验证 |
| 7 | `alu_unit` | `barrel_shifter`；独立指令算术函数 | ADD/SUB/逻辑/比较/移位/LUI/AUIPC/JAL/JALR，立即数与 constant_alu、uses_rs/rd；先 decode 再 issue。`wb.done=issue.possible_issue`，不是乘除法式保持 done |
| 8 | `mul_unit` | 足够位宽的独立整数乘法＋期望队列 | MUL/MULH/MULHSU/MULHU、正负边界、高低半、两级流水连续请求、ack 反压、ID 顺序和复位清 valid |
| 9 | `div_core` | 无符号除法接口；TB 独立计算 CLZ，商余模型 | 默认 32 位，整除/非整除、被除数较小的快速路径、长迭代、复位、done；检查商余恒等式与余数范围。不假设固定 32 拍，不在忙时任意重启 |
| 10 | `div_unit` | 真实 `div_core + clz + cva5_fifo + set_clr_reg_with_rst`；RISC-V 商余函数 | DIV/DIVU/REM/REMU、除零、INT_MIN/-1、缓冲与背压、ID；DIV/REM 结果复用及源寄存器被其他写 rd 覆盖后的失效，gc.init_clear |
| 11 | `branch_unit` | `branch_comparator + set_clr_reg_with_rst`；立即数/谓词/目标地址模型 | 条件分支、JAL/JALR、bit0 清零、对齐异常、call/return、正确/错误预测。提供下一条 issue PC/stage_valid 以完成比较；链接寄存器写回由 ALU 负责 |

`div_core` 没有通用 ready/ack，`alu_unit` 的 done 语义也与 MUL/DIV 不同。先分别跑通再抽取公共 task，不为了复用任务改变 DUT 的接受/完成契约。

### 7.5 阶段 C：7 个后端模块

源码位于 `core/` 直属目录。模型从算术函数逐渐变为“值数组、空闲队列、映射表、按 ID 状态表”。

| 序号 | 模块 | 依赖/参考模型 | 必查内容 |
|---:|---|---|---|
| 12 | `writeback` | `priority_encoder`；按配置顺序独立寻找首个 done | 无结果/单结果/同时多结果、WB_INDEX、valid/id/data、唯一 ack；组合固定优先级，无下游 ready 输入；无效数据不作有效结果比较 |
| 13 | `fp_writeback` | 两路独立直通模型 | 两路同时完成、ID/数据隔离、ack[i]=done[i]；它不是整数 writeback 那样的共享端口仲裁器 |
| 14 | `register_free_list` | 自有存储阵列；空闲值队列＋分配历史 | push/pop、rollback 退回最近分配、full/valid、环回、potential_push；先实际深度 32 再 4/8。不是 cva5_fifo 包装，空时 pop 的规则不能照搬 |
| 15 | `register_file` | `toggle_memory_set + lutram_1w_mr`；分写回组的物理值数组和 in-use 状态 | decode 采样、issue 读数、多读/多写组、等操作数与旁路、writeback_suppress、single_cycle_or_flush、初始化、整数 x0；再测浮点端口/宽度配置 |
| 16 | `renamer` | free_list/LFSR/LUTRAM/编码器；架构→物理/写回组映射与每 ID 旧映射 | 连续重命名、同 rd 重复写、依赖、退休释放、fetch_flush 撤回分配、rename_revert、初始化；整数与浮点寄存器 0 的处理分别验证 |
| 17 | `instruction_metadata_and_id_management` | LUTRAM、toggle_memory_set；程序序队列＋按 ID 状态表 | 分配/取指/decode/issue/乱序完成、ID 满与回绕、flush、PC/指令/物理 rd、按序退休；同拍退休还受整数 rd、浮点 rd、store 类别限制 |
| 18 | `decode_and_issue` | 编码器；TB 提供 RF/renamer/执行单元接口模型，独立译码与单 entry issue 模型 | 字段/立即数/目标单元、操作数是否被使用、inuse 等待、unit.ready、GC hold/flush、非法指令、地址与 ID；possible_issue 与 new_request 分开检查 |

寄存器堆与重命名不是普通 32×32 RAM：按实际物理地址、写回组和端口配置建模。ID 管理的完成顺序可以打乱，但退休必须从最老的连续指令开始。

### 7.6 阶段 D：4 个内存子单元与核内仲裁

总线从设备先用 TB 行为模型实现；每个接受的请求登记一次副作用，随机延迟响应，防止 valid 保持期间重复写参考存储器。先关闭 AMO 测普通访问，阶段 G 的 `amo_unit` 通过后再组合测原子访问。

| 序号 | 模块 | 环境/参考模型 | 必查内容 |
|---:|---|---|---|
| 19 | `local_mem_sub_unit` | 同步本地 RAM 行为模型＋字节参考存储器 | 地址单位、BE、普通读写、连续请求、返回周期；再接 AMO 检查 LR/SC、RMW 停顿、返回旧值和写入新值 |
| 20 | `wishbone_master` | Wishbone 从设备 BFM、AMO 对端 | 随机 ack、等待时地址/data/sel 稳定、stb/cyc、读写完成一次、write_outstanding；再测 LR_WAIT、SC 成败与 RMW |
| 21 | `avalon_master` | Avalon 从设备 BFM、AMO 对端 | waitrequest、byteenable、锁与请求对应；此接口按 waitrequest 接受，没有 readdatavalid，不能自行增加不存在的延迟读通道 |
| 22 | `axi_master` | 五通道从设备 BFM、字节存储器、AMO 对端 | AW/W 独立反压、AR/R/B 延迟、valid 与载荷稳定、无重复写、响应配对、字节写；再补独占响应、SC、AMO 独占失败重试 |
| 23 | `core_arbiter` | 真实 round_robin；TB 模拟 D$/I$/DMMU/IMMU 与下层 mem | 接受源队列、地址/长度/属性选择、ack 只给被选源、rid 响应分发、背压/公平性、禁用端口、D$ 写数据及 invalidation 旁路 |

`axi_master` 与 APU 的 `axi_adapter` 是不同层次，不能混为一个模块。这里不要求先实例化完整缓存/MMU 才能驱动仲裁器。

### 7.7 阶段 E：4 个前端基础模块

源码位于 `fetch_stage/`。这一阶段先不连接整个 CPU；由 TB 产生 GC、分支完成、分支退休和下层存储响应。

| 序号 | 模块 | 依赖/参考模型 | 必查内容 |
|---:|---|---|---|
| 24 | `ras` | FIFO/LUTRAM；循环栈＋投机索引快照队列 | push/pop/同时操作、深度环回、branch_fetched/retired、fetch_flush 回退与 early adjust；无普通栈 empty/full 保护，索引初始化假设要记录 |
| 25 | `branch_predictor` | RAM/编码器/cycler；PC→tag/target/状态模型＋ID 元数据 | 冷启动、taken/not-taken 训练与饱和、同索引冲突、way 替换、target/ID/call/return、关闭预测；RAS 通过接口连接，不在模块内部实例化 |
| 26 | `itag_banks`，文件 `icache_tag_banks.sv` | `sdp_ram_padded`；set/way 的 valid/tag 数组 | stage1 索引与 stage2 比较的时序、stage1_adv、按 way 更新、ifence 清除、同拍优先级；CONFIG/SCONFIG 必须匹配 |
| 27 | `icache` | 真实 tag bank/RAM/FIFO/替换器；指令存储器与请求队列 | 冷缺失/命中、冲突替换、refill 各字与关键字返回、ack/rvalid 间隙、背压、cache_on、ifence；遵守上层在访问空闲时启动 ifence 的契约 |

### 7.8 阶段 F：3 个地址翻译模块

`perms_check` 已在阶段 A。MMU 与两个 TLB 先分别验证；随后再接真实的 `TLB + MMU + 页表内存模型`。

| 序号 | 模块 | 环境/参考模型 | 必查内容 |
|---:|---|---|---|
| 28 | `mmu` | `perms_check`；物理页表 mem BFM＋独立 Sv32 遍历函数 | 两级页表地址、4KiB/4MiB 页、无效 PTE/非法 RW、权限/A/D、superpage 对齐、ack/rvalid 延迟、abort 后旧响应丢弃 |
| 29 | `itlb` | LUTRAM/替换/编码/LFSR/权限；先用 MMU 响应模型 | 映射字典、translation_off、命中/重填、普通页/superpage、ASID/global、权限、SFENCE 筛选、abort；按实际 ITLB 响应时序检查 |
| 30 | `dtlb` | 同类基础组件；独立 load/store 映射/权限模型 | 增加 SUM/MXR/D 位、命中与重填的不同返回路径、SFENCE；ready 恒 1 不代表 miss 未完成时可随意送新请求，遵守源码断言 |

TLB 内部无复位 LFSR 的四态仿真初态，承接前文 LFSR 初始化说明。不要让 DUT 的页表遍历结果直接作为参考翻译结果。

### 7.9 阶段 G：6 个原子/访存队列/数据缓存模块

`addr_hash`、`amo_alu` 已在阶段 A。源码均位于 `execution_units/load_store_unit/`。

| 序号 | 模块 | 依赖/参考模型 | 必查内容 |
|---:|---|---|---|
| 31 | `amo_unit` | `amo_alu + one_hot_to_integer`；单个全局保留地址/有效位模型 | LR 建保留、RESERVATION_WORDS 粒度、clear、同拍 set 优先、各子单元算术路由；set_reservation/rmw_valid 按 one-hot 约束，它不提供多请求仲裁 |
| 32 | `store_queue` | 多组 LUTRAM；含 ID/依赖/写回组/hash/BE/退休状态的队列 | 入队与退休分离、WB 数据到达与转发、可执行条目、字节对齐、满空、环回、同拍操作；先关闭可选浮点和向 store 转发，再开启 |
| 33 | `load_store_queue` | `store_queue + addr_hash + FIFO`；指令/翻译地址两类记录 | 地址晚到与配对、load/store 独立 pop、discard、hash 冲突阻塞/解除、store 排空；最后加浮点拆分访问，不能笼统当成 store-to-load 数据转发器 |
| 34 | `dcache_noinv` | RAM/替换/编码器；字节参考内存＋下层 mem BFM | load/store 命中与缺失、BE、uncacheable、refill、CBO、load_peek 背压、下层写事务一致；再补 LR/SC/RMW。当前 RTL 无 dirty/脏行逐出逻辑 |
| 35 | `dcache_inv` | TDP/SDP RAM、替换/编码器；增加 inv/inv_addr | 复用外部访存模型，增加启动清理、snoop 命中/未命中、失效与 load/refill/store 重叠、保留失效、RMW 遇 snoop 重试、ready 停顿 |
| 36 | `load_store_unit` | 真实 LSQ/属性 FIFO/LUTRAM，按配置接 local/bus/cache/AMO；TLB 对端先用模型 | 有效地址、BE、LB/LH 符号/零扩展、对齐异常、翻译延迟/故障、子单元选择/切换、fence、store 退休后副作用、整数/FP 写回和异常 ID |

LSU 起步配置采用 M 模式、关闭翻译、接本地 RAM，关闭 FPU/AMO/CBO。基础访问稳定后逐项开启，避免第一版 TB 同时承担缓存、页表、浮点拆分和原子协议。

缓存写行为按源码中的事务检查，不因“cache”名称就安排不存在的脏行写回。下层 mem 接口与外部 AXI 也分层建模。

### 7.10 阶段 H：取指与全局控制

| 序号 | 模块 | 环境/参考模型 | 必查内容 |
|---:|---|---|---|
| 37 | `fetch` | 真实配置选出的内存子模块；外部 TLB/BP/RAS/GC/ID 行为驱动；PC 请求队列 | 先本地存储、无翻译、无预测；PC+4/重定向、ID 不足、hold、在途请求、flush 过滤旧响应、无映射/页故障、预测修正、ifence 排空 |
| 38 | `csr_unit` | 编码器；CSR 字典/合法位掩码/副作用模型 | M 配置起步，再 MSU/计数器；CSRRW/RS/RC 与立即数、旧值返回、零源、只读/不存在/越权异常、mtime、mstatus/SATP、委派、trap/return、fflags/rm；区分请求与延迟更新 |
| 39 | `gc_unit` | 编码器；事件驱动状态模型，先提供 CSR/LSU/TLB 行为反馈 | 初始化清理、fence/ifence/sfence、等待访存排空、WFI、中断/异常、MRET/SRET、前端 flush、PC 覆盖、写回抑制和 rename_revert 延迟 |

GC 的 exception.valid/possible 向量按 onehot0 使用，不是任意多个异常的优先级仲裁器。正常回归先遵守上层互斥契约，多异常输入作为独立的预期断言失败场景。

fetch、LSU、GC 虽然都是一个顶层 DUT，内部已经包含多个模块。继续以 task 和外部参考模型检查其接口，先隔离对端，再做真实子系统连接。

### 7.11 阶段 I：全部 21 个 FPU 模块

源码位于 `execution_units/fp_unit/`，其中 4 个除法子模块位于 `divider/`。按“组合辅助 → 预/后处理 → 乘加 → 除法迭代 → 整合”学习。

浮点参考模型需要输出精确位串和异常标志。起步可用已知位模式与可手算向量；扩随机时接独立的位精确软件模型或经过核对的参考向量。普通 real/shortreal 计算不能独自覆盖全部舍入模式、NaN-boxing 和 fflags，FMA 也不能用先乘法舍入再加法来计算期望值。当前参数表达式得到 FLEN=64、FLEN_F=32，按表达式建模；修改精度后应重新核对参考模型的格式支持范围。

| 序号 | 模块 | 参考模型/自然依赖 | 必查内容 |
|---:|---|---|---|
| 40 | `fp_special_case_detection` | 指数/尾数位分类函数 | ±0、normal、subnormal、±Inf、sNaN/qNaN，SUBNORMAL 两分支 |
| 41 | `fp_roundup` | sign/rm/GRS/LSB 真值表 | 合法舍入模式、ties-even/away、进位、溢出选 Inf 或最大有限数 |
| 42 | `fp_sticky_tracking` | 逐位 OR 函数，核对截止索引/包含端点约定 | 当前 shift=0 返回 input[0]，不能机械期望 0；移位 0/1/边界/超宽、边界单 bit、不同 INPUT_WIDTH/SHIFT_WIDTH |
| 43 | `fp_prenormalize` | 扩位指数运算函数 | 左/右移、normal/subnormal、单双精度边界、指数受限与 overflow |
| 44 | `fp_rs_preprocess` | 分类、拆包/重编码与独立 CLZ；真实 clz/分类组件 | NaN-boxing、S→D、次正规预规格化、零/Inf/NaN，当前双精度相关 CLZ 宽度 54 |
| 45 | `fp_preprocessing` | 三操作数变换模型＋单项请求状态；真实 rs_preprocess | 五路分发、ID/rm、所需操作数、下级 ready 反压、连续请求与复位 |
| 46 | `fp_wb2int_misc` | 分类/比较/位搬运/浮点转整数函数 | NaN/±0、比较/classify、整数转换边界/饱和、NV/NX、ID、ack 延后与结果保持 |
| 47 | `fp_wb2fp_misc` | 位搬运/符号注入/minmax/转换的中间包模型 | I2F/S2D/D2S、NaN/±0、boxing；纯组合接口，ready=ack，不能套带寄存器的 done 保持模型 |
| 48 | `fp_normalize_rounding_top` | 真实 prenormalize/sticky/roundup；独立位精确规格化舍入模型 | 多路固定优先选择、ack 路由、流水背压、GRS、单双精度结果、舍入后 tininess 与五类 fflags |
| 49 | `fp_mul` | 宽整数尾数乘法＋指数/特殊值模型 | 普通 MUL/FMA 分流、正负/极值、add_ready 与 wb.ack、结果中间包和 ID |
| 50 | `fp_add` | 宽定点对齐加减模型 | 大小指数差、消去、零符号、GRS、CLZ 宽度 157 的调用、ID 与背压 |
| 51 | `fp_madd_wrapper` | 真实 mul/add；融合 a*b±c 的独立模型 | FMA 只做一次最终舍入、FMA 与独立 ADD/MUL 混合、add 资源竞争、顺序/ID、输出背压 |
| 52 | `q_lookup` | 独立商数字选择区间/表参考 | d/ws/wc 边界、合法区间与 not_in_table；17 位输入可穷举，表外不比较 X 商数字，不直接复制 DUT case 当唯一参考 |
| 53 | `on_the_fly` | radix-4 商数字到 Q/QM 的算术模型 | ±2/±1/0、末步特殊商数字、商数字切换与组合输出、非法数字检查；没有 clk/rst |
| 54 | `carry_save_shift` | 真实 q_lookup；扩位整数残差模型 | 4w−q*d 的模运算、sum/carry 重构、符号/进位、选择表有效区 |
| 55 | `fp_div_core` | 上述三个除法组件；归一化定点除法模型 | 商缩放、余数、负残差修正、start/done、复位、内部不变量与断言 |
| 56 | `fp_sqrt_core` | 按输入定点缩放建立整数开方模型 | 完全平方/相邻值、余数、迭代、start/done；不能直接按普通无缩放整数 sqrt 比较 |
| 57 | `fp_div` | 真实 div_core；浮点除法/中间 GRS 模型 | 0/0、Inf/Inf、除零 DZ、次正规、指数；特殊值 early_exit 和普通路径都延迟 ack，检查 done/ID/数据/flags 保持 |
| 58 | `fp_sqrt` | 真实 sqrt_core；浮点开方/中间 GRS 模型 | 负数 NV、±0、Inf/NaN、指数奇偶、次正规；early_exit/普通路径均测背压 |
| 59 | `fp_div_sqrt_wrapper` | 真实 div/sqrt；两路请求与结果模型 | 并行完成、sqrt 完成优先、ack 路由、ID、GRS 压缩和背压 |
| 60 | `fpu_top` | 真实预处理、各算术/杂项单元与后处理；指令级位精确模型＋按 ID 记分板 | 全部 S/D 指令、静态/动态 rm、三操作数、boxing、int/fp 双写回、同拍结果与按接受事件汇总的 flags、随机混合及复位 |

`fp_add/fp_mul/fp_div/fp_sqrt/fp_wb2fp_misc` 的浮点输出是中间包，尚未最终规格化/舍入。单模块可以比较中间字段；如果使用最终浮点结果的参考值，应再连接 `fp_normalize_rounding_top`。不要把中间包直接当 IEEE 最终结果验收。

### 7.12 阶段 J：cva5 整核

| 序号 | 模块 | 参考模型/环境 | 验证顺序与重点 |
|---:|---|---|---|
| 61 | `cva5` | 真实核内模块＋存储/外设响应；C/汇编程序与退休/签名检查 | 先整数、M 模式、本地存储、关闭缓存/预测/FPU/AMO 的合法小配置，跑启动、算术、分支、load/store；再开乘除、CSR异常/中断、预测/缓存、MSU翻译、AMO、FPU和总线组合 |

配置从已有 wrapper/EXAMPLE_CONFIG 的合法约束推导，不只关闭一个开关就假定所有生成分支成立。例如保留至少一个取指和数据访问通路，写回组与启用执行单元保持一致。

现有 `test_benches/verilator/cva5_sim.sv` 直接实例化 EXAMPLE_CONFIG，统计还使用配置相关的层次路径。开始最小配置冒烟时，先提供匹配配置的仿真 wrapper，并核对统计引用；不能只在命令行关闭若干功能就假定现有仿真顶层已适配。

整核检查包含退休指令/PC/有效性、程序签名、超时和结束标记。现有 Verilator 环境识别 `0x00A00013` 成功标记、`0x00F00013` 失败标记；只看到进程退出不等于程序通过。先沿用现有整核环境，再扩指令随机与配置回归。

### 7.13 适合在单模块之后做的组合验证

| 组合 | 接入真实模块 | 保留的 TB 行为对端 | 验证目标 |
|---|---|---|---|
| 整数除法 | div_unit 及其真实下级 | decode/RF/GC、写回接受 | 符号与迭代、缓冲、复用、ID 和背压共同工作 |
| 后端短流水 | renamer + register_file + metadata + decode_and_issue + writeback，按 cva5 连接 | 起初用简化执行结果模型，再换真实 ALU/MUL/DIV | 相关指令等待、不同完成顺序、按序退休、恢复与物理寄存器释放 |
| 地址翻译 | itlb 或 dtlb + mmu | 页表 mem BFM、CSR/SFENCE 事件 | 缺失触发遍历、重填、权限故障、ASID/global 与 abort/flush |
| 前端 | fetch（含按配置实例化的 I-cache/本地通路）+ TLB + branch_predictor + ras | GC/ID/分支完成驱动、指令/页表内存 | PC/ID/预测/取指响应对应与 flush 恢复 |
| 访存 | load_store_unit（按配置启用内部 amo_unit），再逐步接入 dtlb/mmu | issue/RF/WB/退休、存储与总线从设备 | 退休前后副作用、翻译/缓存/原子、写回与异常关联 |
| 精确异常控制 | csr_unit + gc_unit + metadata 起步，再接 renamer/RF、真实 LSU/前端 | 先提供受控指令与异常/中断事件 | 先检查 trap/return、PC 恢复、抑制/回退控制；接 renamer 后再验真实映射恢复 |
| 浮点数值链 | preprocessing + 选定 add/mul/madd/div_sqrt/wb2fp_misc + normalize_rounding；wb2int_misc 另走整数写回 | 输入指令包、下游 ack、位精确参考模型 | 最终结果和 flags 与中间时序共同正确，再上 fpu_top |

按源码真实连线组合；例如 LSU 开启 AMO 时已内部实例化 amo_unit，不要在同一条接口上重复添加第二个所有者。表中的前端/后端组合是逐步集成目标，并非要求第一版就同时接完。

### 7.14 沿用当前写法时新增的三种 TB 能力

1. **按事务保存期望值。** 由 DUT 的实际接受事件登记操作/ID/期望值；在有效完成事件检查结果，按实际 ack/消费规则释放记录。部分模块可能同拍完成，或根本没有 ack，分别建模。
2. **用小型行为模型隔离外部环境。** 总线从设备、页表、CSR/GC反馈、写回接受先由 task/always 驱动，不需要先建一个完整 SoC；之后逐个替换为真实模块。
3. **逐项扩功能和配置。** 先单请求、无反压的定向用例，再连续请求、背压、随机延迟、复位/flush、参数扫描；保留种子、超时、接受次数、完成次数和副作用次数。

这样可以继续保持现有 TB 的可读性，同时逐渐覆盖有流水线、多个在途事务和复杂恢复控制的模块。

APU 总线适配、CLINT/PLIC 和 debug_module 位于 `core` 之外，可在整核或 SoC 集成阶段另外安排，不混入本节 61 个模块计数。

## 8. 新 TB 的目录与运行方式

沿用现有布局即可，例如下一个模块：

```text
verification/unit/tb_ram/tb_sdp_ram/
    tb_sdp_ram.sv          # 参数化子测试 + tb_sdp_ram_top
    run_tb_sdp_ram.sh      # 编译、固定随机种子、结果汇总
    sdp_ram.f             # DUT/TB 及实际依赖
    logs/
    waves/                # 需要定位时保存波形
```

下面是新建 TB 后可采用的 VCS 命令模板；本版未创建该 TB 或脚本：

```bash
cd /mnt/e/ic/cva5-master-annotated-20261107/verification/unit/tb_ram/tb_sdp_ram

vcs -full64 -sverilog -timescale=1ns/1ps \
  -debug_access+all -kdb \
  -cm line+cond+tgl+branch+fsm+assert \
  -cm_dir ./simv.vdb \
  -top tb_sdp_ram_top \
  ../../../../core/common_components/ram/sdp_ram.sv \
  tb_sdp_ram.sv \
  -o simv

./simv +ntb_random_seed=1 \
  -cm line+cond+tgl+branch+fsm+assert \
  -cm_dir ./simv.vdb

urg -full64 -dir ./simv.vdb -report ./coverage_report
```

`sdp_ram` 本身没有包导入；需要其他包/接口的模块，按 `tools/compile_order` 补齐编译依赖。例如 FIFO 的 filelist 要包括其接口及接口文件导入的包，不能只放 DUT 和 TB。厂商配置运行使用隔离的配置/构建目录并记录参数，不为了扫分支而覆盖公共包。

Slang 的根配置当前仍指向 `verification/unit/priority_encoder/priority_encoder.f`。开始新模块时，把活动 build 指向对应 filelist，保持编辑器与仿真使用的 DUT、参数和依赖一致；编辑器无报错不能替代仿真。

## 9. 每个模块的收尾标准

- [ ] 端口、参数、时序、合法输入和未规定场景已经写明。
- [ ] 定向与边界用例通过；期望值来自独立函数/数组/队列。
- [ ] 参数矩阵中的每个目标配置都有对应实例或运行记录。
- [ ] 随机测试记录种子；大于 32 位的激励覆盖全部数据位。
- [ ] 检查复位、使能暂停、并发操作；没有复位的模块不虚构复位行为。
- [ ] 组合读、同步读和输出流水线按各自时序检查；未知/无效数据有明确比较条件。
- [ ] 覆盖率只统计实际运行结果，并说明未覆盖配置、厂商分支和冲突场景。
- [ ] 失败能定位配置及操作，脚本传递失败退出码，顶层有超时。
- [ ] 保存一条可复现命令、PASS/FAIL、检查次数与简短结果说明。

下一次实际动手建议：先纠正 `one_hot_to_integer` 的多 bit 预期，再按 `sdp_ram` 的固定小配置写出第一版 `ref_mem + 读响应流水线 + check task`，通过后再扩参数。已有其他模块的补测可逐项穿插进行。
