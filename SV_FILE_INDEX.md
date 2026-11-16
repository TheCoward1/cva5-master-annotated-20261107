# CVA5 SystemVerilog 文件中文索引

- 文件数：103
- 编码：UTF-8
- 每个文件顶部包含具体职责说明，代码行前包含逐行中文说明。

| 文件 | 类型 | 名称 | 具体作用 |
|---|---|---|---|
| `apu/busses/axi_adapter.sv` | module | `axi_adapter` | 把 CVA5 内部存储器请求转换为 AXI 事务，并处理读写通道握手。 |
| `apu/busses/multicore_arbiter.sv` | module | `multicore_arbiter` | 仲裁多个核心对共享存储器资源的访问，避免请求冲突。 |
| `apu/busses/wishbone_adapter.sv` | module | `wishbone_adapter` | 把 CVA5 内部存储器请求转换为 Wishbone 总线事务。 |
| `apu/clint/clint.sv` | module | `clint` | 实现 core-local timer 和软件中断，为 RISC-V 提供定时器和 IPI。 |
| `apu/clint/clint_wrapper.sv` | module | `clint_wrapper` | 为 CLINT 增加总线寄存器接口和地址译码。 |
| `apu/plic/plic.sv` | module | `plic` | 实现平台级外部中断控制器，负责中断优先级、挂起和 claim/complete。 |
| `apu/plic/plic_cmptree.sv` | module | `plic_cmptree` | 实现 PLIC 的优先级比较树，用于选择最高优先级中断。 |
| `apu/plic/plic_gateway.sv` | module | `plic_gateway` | 实现 PLIC 每个中断源的网关、挂起和使能逻辑。 |
| `apu/plic/plic_wrapper.sv` | module | `plic_wrapper` | 为 PLIC 增加总线寄存器接口和中断源连接。 |
| `core/common_components/clz.sv` | module | `clz` | 统计输入从最高位开始连续为 0 的个数；div_unit 用它估算被除数和除数位宽，做除法归一化。 |
| `core/common_components/cva5_fifo.sv` | module | `cva5_fifo` | 实现参数化 FIFO，维护 push/pop、valid、full、data 和 potential_push 语义。 |
| `core/common_components/cycler.sv` | module | `cycler` | 生成循环 one-hot 或轮转状态，用于轮询类控制。 |
| `core/common_components/lfsr.sv` | module | `lfsr` | 实现线性反馈移位寄存器，用于伪随机序列和循环索引。 |
| `core/common_components/one_hot_to_integer.sv` | module | `one_hot_to_integer` | 把 one-hot 输入编码成对应的整数索引。 |
| `core/common_components/priority_encoder.sv` | module | `priority_encoder` | 从输入位向量中找出最低有效置位位，并输出其索引。 |
| `core/common_components/ram/lutram_1w_1r.sv` | module | `lutram_1w_1r` | 实现单写端口、单读端口的 LUTRAM 存储模型。 |
| `core/common_components/ram/lutram_1w_mr.sv` | module | `lutram_1w_mr` | 实现单写端口、多读端口的 LUTRAM 存储模型。 |
| `core/common_components/ram/sdp_ram.sv` | module | `sdp_ram` | 实现简单双端口 RAM 行为模型，供流水线和缓存使用。 |
| `core/common_components/ram/sdp_ram_padded.sv` | module | `sdp_ram_padded` | 实现带位宽/深度填充的简单双端口 RAM 模型。 |
| `core/common_components/ram/tdp_ram.sv` | module | `tdp_ram` | 实现真双端口 RAM 行为模型，支持两个独立读写端口。 |
| `core/common_components/round_robin.sv` | module | `round_robin` | 实现轮询仲裁，按顺序轮流服务多个请求，避免请求饥饿。 |
| `core/common_components/set_clr_reg_with_rst.sv` | module | `set_clr_reg_with_rst` | 实现带复位、置位和清零控制的寄存器。 |
| `core/common_components/toggle_memory.sv` | module | `toggle_memory` | 实现支持写入切换/更新行为的存储器模型。 |
| `core/common_components/toggle_memory_set.sv` | module | `toggle_memory_set` | 实现带置位行为的可切换存储器模型。 |
| `core/core_arbiter.sv` | module | `core_arbiter` | 仲裁多个内部请求源对共享资源的访问。 |
| `core/cva5.sv` | module | `cva5` | CVA5 CPU 顶层，连接前端、后端、CSR、MMU、缓存和外部存储接口。 |
| `core/decode_and_issue.sv` | module | `decode_and_issue` | 实现译码后指令的发射、操作数选择和发射队列控制。 |
| `core/execution_units/alu_unit.sv` | module | `alu_unit` | 执行 RISC-V 整数算术、逻辑、移位、比较和常量运算。 |
| `core/execution_units/barrel_shifter.sv` | module | `barrel_shifter` | 实现 32 位移位器，支持左移、逻辑右移和按填充位右移。 |
| `core/execution_units/branch_comparator.sv` | module | `branch_comparator` | 比较两个 33 位操作数，生成相等、小于和大于等分支条件。 |
| `core/execution_units/branch_unit.sv` | module | `branch_unit` | 解析分支和跳转条件，生成重定向和错误预测处理信号。 |
| `core/execution_units/csr_unit.sv` | module | `csr_unit` | 实现 CSR 寄存器、特权模式、异常、中断和计数器逻辑。 |
| `core/execution_units/custom_unit.sv` | module | `custom_unit` | 处理自定义扩展指令的执行和写回。 |
| `core/execution_units/div_core.sv` | module | `div_core` | 实现整数除法的迭代数据通路和商/余数计算。 |
| `core/execution_units/div_unit.sv` | module | `div_unit` | 实现整数除法功能单元，使用 clz 对操作数归一化并处理符号、除零和余数。 |
| `core/execution_units/fp_unit/divider/carry_save_shift.sv` | module | `carry_save_shift` | 实现浮点除法中的进位保存移位步骤。 |
| `core/execution_units/fp_unit/divider/fp_div_core.sv` | module | `fp_div_core` | 实现浮点除法核心的迭代计算。 |
| `core/execution_units/fp_unit/divider/on_the_fly.sv` | module | `on_the_fly` | 在浮点除法/开方过程中在线生成商或余数。 |
| `core/execution_units/fp_unit/divider/q_lookup.sv` | module | `q_lookup` | 提供浮点除法所需的商查找表。 |
| `core/execution_units/fp_unit/fp_add.sv` | module | `fp_add` | 实现浮点加法和减法，并处理规格化、舍入和特殊值。 |
| `core/execution_units/fp_unit/fp_div.sv` | module | `fp_div` | 实现浮点除法顶层，连接预处理、迭代和舍入模块。 |
| `core/execution_units/fp_unit/fp_div_sqrt_wrapper.sv` | module | `fp_div_sqrt_wrapper` | 统一浮点除法和平方根的数据通路。 |
| `core/execution_units/fp_unit/fp_madd_wrapper.sv` | module | `fp_madd_wrapper` | 实现融合乘加（FMA）的包装与流水控制。 |
| `core/execution_units/fp_unit/fp_mul.sv` | module | `fp_mul` | 实现浮点乘法及符号、指数、尾数处理。 |
| `core/execution_units/fp_unit/fp_normalize_rounding_top.sv` | module | `fp_normalize_rounding_top` | 实现浮点结果归一化和舍入。 |
| `core/execution_units/fp_unit/fp_prenormalize.sv` | module | `fp_prenormalize` | 对浮点操作数进行运算前规格化。 |
| `core/execution_units/fp_unit/fp_preprocessing.sv` | module | `fp_preprocessing` | 拆包浮点操作数并检测类别、指数和尾数信息。 |
| `core/execution_units/fp_unit/fp_roundup.sv` | module | `fp_roundup` | 执行浮点舍入增量处理。 |
| `core/execution_units/fp_unit/fp_rs_preprocess.sv` | module | `fp_rs_preprocess` | 处理舍入前移位、粘滞位和尾数准备。 |
| `core/execution_units/fp_unit/fp_special_case_detection.sv` | module | `fp_special_case_detection` | 检测 NaN、无穷、零等浮点特殊值。 |
| `core/execution_units/fp_unit/fp_sqrt.sv` | module | `fp_sqrt` | 实现浮点平方根顶层。 |
| `core/execution_units/fp_unit/fp_sqrt_core.sv` | module | `fp_sqrt_core` | 实现浮点平方根的核心迭代算法。 |
| `core/execution_units/fp_unit/fp_sticky_tracking.sv` | module | `fp_sticky_tracking` | 跟踪浮点舍入所需的 sticky 位。 |
| `core/execution_units/fp_unit/fp_wb2fp_misc.sv` | module | `fp_wb2fp_misc` | 处理浮点结果写回和浮点相关杂项。 |
| `core/execution_units/fp_unit/fp_wb2int_misc.sv` | module | `fp_wb2int_misc` | 处理浮点结果转整数写回和杂项。 |
| `core/execution_units/fp_unit/fpu_top.sv` | module | `fpu_top` | 浮点单元顶层，连接加法、乘法、除法、开方、规格化和舍入模块。 |
| `core/execution_units/gc_unit.sv` | module | `gc_unit` | 全局控制单元，处理流水线 flush、异常、中断和指令退休控制。 |
| `core/execution_units/load_store_unit/addr_hash.sv` | module | `addr_hash` | 对访存地址做哈希，用于队列或缓存索引。 |
| `core/execution_units/load_store_unit/amo_alu.sv` | module | `amo_alu` | 执行原子内存操作所需的算术逻辑。 |
| `core/execution_units/load_store_unit/amo_unit.sv` | module | `amo_unit` | 处理 LR/SC 和 AMO 原子内存操作、保留集和响应。 |
| `core/execution_units/load_store_unit/dcache_inv.sv` | module | `dcache_inv` | 实现带外部缓存行失效接口的写回数据缓存。 |
| `core/execution_units/load_store_unit/dcache_noinv.sv` | module | `dcache_noinv` | 实现不带外部失效接口的写回数据缓存。 |
| `core/execution_units/load_store_unit/load_store_queue.sv` | module | `load_store_queue` | 管理 load/store 指令队列、依赖、转发和退休顺序。 |
| `core/execution_units/load_store_unit/load_store_unit.sv` | module | `load_store_unit` | 实现访存流水线、地址生成、MMU 接口、缓存接口和异常处理。 |
| `core/execution_units/load_store_unit/store_queue.sv` | module | `store_queue` | 管理 store 指令的入队、提交、写回和地址数据顺序。 |
| `core/execution_units/mul_unit.sv` | module | `mul_unit` | 实现整数乘法功能单元。 |
| `core/fetch_stage/branch_predictor.sv` | module | `branch_predictor` | 实现分支历史和目标预测，减少取指重定向开销。 |
| `core/fetch_stage/fetch.sv` | module | `fetch` | 实现 PC 生成、取指请求、指令对齐和分支预测接口。 |
| `core/fetch_stage/icache.sv` | module | `icache` | 实现指令缓存，处理命中、缺失、refill 和 flush。 |
| `core/fetch_stage/icache_tag_banks.sv` | module | `itag_banks` | 实现指令缓存的 tag 存储、比较和替换信息。 |
| `core/fetch_stage/ras.sv` | module | `ras` | 实现返回地址栈，用于预测函数返回地址。 |
| `core/fp_writeback.sv` | module | `fp_writeback` | 处理浮点结果的写回和异常标志。 |
| `core/instruction_metadata_and_id_management.sv` | module | `instruction_metadata_and_id_management` | 管理指令元数据、指令 ID、退休顺序和指令表。 |
| `core/memory_sub_units/avalon_master.sv` | module | `avalon_master` | 把 CVA5 内存请求转换为 Avalon 主设备事务。 |
| `core/memory_sub_units/axi_master.sv` | module | `axi_master` | 把 CVA5 内存请求转换为 AXI 主设备事务并处理读写通道握手。 |
| `core/memory_sub_units/local_mem_sub_unit.sv` | module | `local_mem_sub_unit` | 提供本地存储器子单元接口，连接本地 RAM。 |
| `core/memory_sub_units/wishbone_master.sv` | module | `wishbone_master` | 把 CVA5 内存请求转换为 Wishbone 主设备事务。 |
| `core/mmu/dtlb.sv` | module | `dtlb` | 实现数据地址 TLB、命中和重填。 |
| `core/mmu/itlb.sv` | module | `itlb` | 实现指令地址 TLB、命中和重填。 |
| `core/mmu/mmu.sv` | module | `mmu` | 实现地址翻译、页表遍历、权限检查和异常处理。 |
| `core/mmu/perms_check.sv` | module | `perms_check` | 检查页表项中的读、写、执行权限。 |
| `core/register_file.sv` | module | `register_file` | 实现整数寄存器堆，支持多读端口、写端口和 x0 恒零。 |
| `core/register_free_list.sv` | module | `register_free_list` | 管理寄存器重命名所需的物理寄存器空闲列表。 |
| `core/renamer.sv` | module | `renamer` | 实现架构寄存器到物理寄存器的重命名、映射恢复和释放。 |
| `core/types_and_interfaces/csr_types.sv` | package | `csr_types` | 定义 CSR 地址、权限、异常码、中断和特权相关类型。 |
| `core/types_and_interfaces/cva5_config.sv` | package | `cva5_config` | 定义 CVA5 配置结构体、缓存/MMU/FPU 参数和 EXAMPLE_CONFIG 默认配置。 |
| `core/types_and_interfaces/cva5_types.sv` | package | `cva5_types` | 定义 CVA5 流水线包、退休端口、写回、异常和内部数据结构。 |
| `core/types_and_interfaces/external_interfaces.sv` | interface | `axi_interface` | 定义 AXI、Avalon、Wishbone 和本地存储器等外部接口。 |
| `core/types_and_interfaces/fpu_types.sv` | package | `fpu_types` | 定义浮点数据、舍入模式、异常标志和 FPU 内部类型。 |
| `core/types_and_interfaces/internal_interfaces.sv` | interface | `branch_predictor_interface` | 定义模块之间的 issue、writeback、FIFO、MMU、TLB 和异常接口。 |
| `core/types_and_interfaces/opcodes.sv` | package | `opcodes` | 定义 RISC-V 操作码、funct3/funct7 常量和指令类型编码。 |
| `core/types_and_interfaces/riscv_types.sv` | package | `riscv_types` | 定义 RISC-V 指令格式、CSR、异常、特权级和架构类型。 |
| `core/writeback.sv` | module | `writeback` | 处理整数执行结果的写回和退休。 |
| `debug_module/debug_cfg_types.sv` | package | `debug_cfg_types` | 定义调试模块的配置参数和 DMI/调试类型。 |
| `debug_module/debug_interfaces.sv` | interface | `dmi_interface` | 定义 DMI 接口以及 CPU 调试模块与 JTAG 的连接接口。 |
| `debug_module/debug_module.sv` | module | `debug_module` | 实现 RISC-V Debug Module，支持 halt、resume、抽象命令和调试寄存器。 |
| `debug_module/jtag_module.sv` | module | `jtag_module` | 实现 JTAG TAP 状态机和 DMI 扫描链路。 |
| `debug_module/jtag_register.sv` | module | `jtag_register` | 实现 JTAG 扫描链中的单个寄存器单元。 |
| `debug_module/jtag_registers.sv` | module | `jtag_registers` | 实现 JTAG 寄存器组和扫描访问。 |
| `examples/litex/litex_wrapper.sv` | module | `litex_wrapper` | 把 CVA5 集成到 LiteX SoC 的包装层。 |
| `examples/xilinx/cva5_wrapper.sv` | module | `cva5_wrapper` | 把 CVA5 连接到 Xilinx FPGA 的 BRAM、AXI 外设和板级接口。 |
| `test_benches/verilator/cva5_sim.sv` | module | `cva5_sim` | Verilator 顶层测试平台，连接 CVA5、本地存储器、AXI、UART 和退休跟踪。 |
| `test_benches/verilator/sim_stats.sv` | module | `sim_stats` | 收集指令类型、运行周期和其他仿真统计信息。 |
