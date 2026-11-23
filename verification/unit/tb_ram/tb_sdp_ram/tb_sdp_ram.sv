// ============================================================================
// sdp_ram / sdp_ram_padded 共享模块级验证平台（纯 SystemVerilog）
//
// 编译源文件：core/common_components/ram/sdp_ram.sv、本文件。
// USE_PADDED_DUT=1 时还需编译 core/common_components/ram/sdp_ram_padded.sv。
// 回归顶层：tb_sdp_ram_top；可复用的单配置测试模块：tb_sdp_ram。
// 运行选项：+SEED=<十进制种子> +RANDOM_CYCLES=<随机周期数> +VERBOSE
//           +WAVES 开启 VCD；使用 Verilator 时编译需另外添加 --trace。
// 功能覆盖：显式采样请求与返回 covergroup，使用支持功能覆盖的模拟器（如 VCS）。
// 每个测试实例独立报告覆盖率；覆盖率报告不替代记分板的通过/失败判据。
// VCS 编译沿用 -timescale=1ns/1ps，为未声明时标的 DUT 提供统一默认值。
//
// 验证约定：下降沿驱动，上升沿采集，延后 1ps 比较 NBA 更新后的输出。
// 参考模型独立保存存储内容，按请求到期周期生成预计输出，不读取 DUT 内部状态。
// CHECK_RTL_RW_COLLISION=1 检查当前 RTL 的同沿同址读旧值行为；
// 设为 0 时跳过该次读返回及随后的保持检查，直到下一次可比较的读返回。
// 后一种策略用于未保证同址读写结果的接口，不能据此宣称硬件碰撞数据正确。
// ============================================================================

`timescale 1ns/1ps

// DUT 保持原有独立端口；接口集中管理信号，不声明未被模块端口使用的 modport。
interface sdp_ram_if #(
    parameter int ADDR_WIDTH = 10,
    parameter int NUM_COL    = 4,
    parameter int COL_WIDTH  = 16
)(
    input logic clk
);
    localparam int DATA_WIDTH = NUM_COL * COL_WIDTH;
    logic                      a_en;
    logic [NUM_COL-1:0]         a_wbe;
    logic [DATA_WIDTH-1:0]      a_wdata;
    logic [ADDR_WIDTH-1:0]      a_addr;
    logic                      b_en;
    logic [ADDR_WIDTH-1:0]      b_addr;
    logic [DATA_WIDTH-1:0]      b_rdata;
endinterface : sdp_ram_if


module tb_sdp_ram #(
    parameter int ADDR_WIDTH          = 10,
    parameter int NUM_COL             = 4,
    parameter int COL_WIDTH           = 16,
    parameter int PIPELINE_DEPTH      = 1,
    parameter int CASCADE_DEPTH       = 4,
    parameter int NUM_RANDOM_CYCLES   = 1000,
    parameter int TIMEOUT_CYCLES      = 1000000,
    parameter bit CHECK_RTL_RW_COLLISION = 1'b1,
    parameter int unsigned SEED      = 32'h5D50_524D,
    parameter bit USE_PADDED_DUT     = 1'b0
)(
    output logic done
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam int DATA_WIDTH = NUM_COL * COL_WIDTH;
    localparam int MEM_DEPTH  = 2 ** ADDR_WIDTH;
    localparam string DUT_NAME = USE_PADDED_DUT ? "SDP_RAM_PADDED" : "SDP_RAM";
    typedef logic [ADDR_WIDTH-1:0] addr_t;
    typedef logic [NUM_COL-1:0]    col_mask_t;
    typedef logic [DATA_WIDTH-1:0] data_t;
    localparam addr_t FIRST_ADDR = '0;
    localparam addr_t LAST_ADDR  = addr_t'(MEM_DEPTH - 1);
    localparam addr_t MID_ADDR   = addr_t'(MEM_DEPTH / 2);

    // ------------------------------------------------------------------------
    // 功能覆盖辅助函数：返回 onehot 掩码对应的列号。
    // 覆盖点仅在 $onehot(mask) 成立时采纳返回值。
    // ------------------------------------------------------------------------
    function automatic int coverage_onehot_column(input col_mask_t mask);
        for (int col = 0; col < NUM_COL; col++) begin
            if (mask[col]) return col;
        end
        return -1;
    endfunction : coverage_onehot_column

    // 请求覆盖：每个被 monitor 接受的时钟周期采样一次。
    // 使用显式 sample 参数保存该周期的请求快照，不依赖驱动任务调用次数。
    // 本组只说明场景已发生；返回数据是否正确由记分板和返回覆盖共同反映。
    covergroup sdp_ram_request_cg with function sample(
        input logic      wr_en,
        input col_mask_t wr_be,
        input addr_t     wr_addr,
        input logic      rd_en,
        input addr_t     rd_addr
    );
        // 各参数化测试实例分别保存统计，避免合并结果掩盖单实例缺项。
        option.per_instance = 1;

        // 原始端口使能组合；写使能有效不代表掩码非零。
        cp_port_enable : coverpoint {wr_en, rd_en} {
            bins both_disabled = {2'b00}; // A/B 口均关闭。
            bins read_enabled  = {2'b01}; // 只开启 B 口。
            bins write_enabled = {2'b10}; // 只开启 A 口，仍需检查掩码。
            bins both_enabled  = {2'b11}; // 两口同时开启，可能并发读写。
        }

        // 拼接高位是总写使能，低位是掩码是否至少选中一列。
        cp_write_gate : coverpoint {wr_en, (|wr_be)} {
            bins inactive          = {2'b00}; // 总使能关闭，掩码也为零。
            bins blocked_by_enable = {2'b01}; // 掩码非零，但被总使能屏蔽。
            bins zero_mask         = {2'b10}; // 总使能开启，但没有列被选中。
            bins actual_write      = {2'b11}; // 总使能与至少一列使能同时有效。
        }

        // iff 控制本次是否采样；with 过滤建仓集合，两者作用不同。
        // $countones 只统计掩码中 1 的数量，不为每一种掩码建立组合仓。
        cp_write_mask : coverpoint $countones(wr_be) iff (wr_en) {
            bins zero = {0};       // 所有列保持，不发生实际写入。
            bins full = {NUM_COL}; // 全部列写入。
            // NUM_COL=1 时为空集合，不生成有效的部分写覆盖目标。
            bins partial = {[1:NUM_COL]} with (item < NUM_COL);
        }

        // 每个列号建立一个仓，确认高位列也得到独立写入。
        // NUM_COL=1 时，单列写同时属于全列写，两个覆盖点均应命中。
        cp_onehot_column : coverpoint coverage_onehot_column(wr_be)
            iff (wr_en && $onehot(wr_be)) {
                bins column[] = {[0:NUM_COL-1]};
            }

        // 每个地址独立建仓；无效写周期的地址变化不算写访问。
        cp_write_address : coverpoint wr_addr iff (wr_en && (|wr_be)) {
            bins address[] = {[0:MEM_DEPTH-1]};
        }

        // 只记录被接受的读请求，读口关闭时改变地址不计入覆盖。
        cp_read_address : coverpoint rd_addr iff (rd_en) {
            bins address[] = {[0:MEM_DEPTH-1]};
        }

        // 零掩码或写口关闭时，即使地址相同也不属于读写碰撞。
        cp_rw_address_relation : coverpoint (wr_addr == rd_addr)
            iff (wr_en && (|wr_be) && rd_en) {
                bins different_address = {1'b0};
                bins same_address      = {1'b1};
            }

        cp_read_enable : coverpoint rd_en {
            bins disabled = {1'b0};
            bins enabled  = {1'b1};
        }

        // 每周期采样，不能用 rd_en 过滤，否则会丢失气泡和停止跳变。
        cp_read_sequence : coverpoint rd_en {
            bins idle         = (0 => 0); // 相邻两次采样均无读请求。
            bins start        = (0 => 1); // 空闲后开始读。
            bins back_to_back = (1 => 1); // 连续两个周期接受读请求。
            bins stop         = (1 => 0); // 有效读之后出现气泡。
        }

        // 仅交叉掩码类别与读使能，避免全地址交叉造成覆盖目标膨胀。
        cx_write_mask_read_enable :
            cross cp_write_mask, cp_read_enable iff (wr_en);
    endgroup : sdp_ram_request_cg

    // 返回覆盖：在 check_output() 正常返回后采样。
    // 检查失败会先触发 $fatal，不会被记录为检查通过。
    // new_return 对应 expected_update，与当前 b_en 不是同一个时序含义。
    // check_enabled 在碰撞忽略期间可保持为 0，直到新的可比较返回到达。
    covergroup sdp_ram_response_cg with function sample(
        input bit    new_return,
        input bit    check_enabled,
        input addr_t return_addr,
        input logic  current_rd_en
    );
        option.per_instance = 1;

        cp_check_kind : coverpoint {new_return, check_enabled} {
            bins read_checked = {2'b11}; // 新读返回已通过比较。
            bins hold_checked = {2'b01}; // 没有新返回，输出保持已通过比较。
            // 跳过只表示碰撞策略已执行，不表示碰撞数据已检查正确。
            // 严格检查碰撞的实例不把该场景计入覆盖目标。
            bins collision_skipped = {2'b10}
                with ((item == 2'b10) && (CHECK_RTL_RW_COLLISION == 1'b0));
            ignore_bins no_check = {2'b00}; // 尚无可比较值或处于屏蔽保持期。
        }

        // 与请求地址覆盖分开：只有该地址的新返回比较通过才命中。
        cp_checked_read_address : coverpoint return_addr
            iff (new_return && check_enabled) {
                bins address[] = {[0:MEM_DEPTH-1]};
            }

        // 当前没有新读请求时，先前进入附加流水级的数据仍可返回。
        cp_read_enable_at_return : coverpoint current_rd_en
            iff (new_return && check_enabled) {
                bins with_new_request = {1'b1};
                // 无附加流水级时不存在这种返回场景，建仓时过滤。
                bins during_bubble = {1'b0}
                    with ((item == 1'b0) && (PIPELINE_DEPTH > 0));
            }
    endgroup : sdp_ram_response_cg

    sdp_ram_request_cg  request_cov;
    sdp_ram_response_cg response_cov;

    logic clk = 1'b0;
    always #5ns clk = ~clk;

    sdp_ram_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .NUM_COL    (NUM_COL),
        .COL_WIDTH  (COL_WIDTH)
    ) ram_if (.clk(clk));

    // 两种 DUT 共用外部逻辑接口。参考模型始终只保存 DATA_WIDTH 位逻辑数据，
    // 不复制 padded DUT 的补位计算，也不读取内部 RAM 或填充位。
    generate
        if (USE_PADDED_DUT) begin : gen_padded_dut
            sdp_ram_padded #(
                .ADDR_WIDTH     (ADDR_WIDTH),
                .NUM_COL        (NUM_COL),
                .COL_WIDTH      (COL_WIDTH),
                .PIPELINE_DEPTH (PIPELINE_DEPTH),
                .CASCADE_DEPTH  (CASCADE_DEPTH)
            ) dut (
                .clk     (ram_if.clk),
                .a_en    (ram_if.a_en),
                .a_wbe   (ram_if.a_wbe),
                .a_wdata (ram_if.a_wdata),
                .a_addr  (ram_if.a_addr),
                .b_en    (ram_if.b_en),
                .b_addr  (ram_if.b_addr),
                .b_rdata (ram_if.b_rdata)
            );
        end
        else begin : gen_plain_dut
            sdp_ram #(
                .ADDR_WIDTH     (ADDR_WIDTH),
                .NUM_COL        (NUM_COL),
                .COL_WIDTH      (COL_WIDTH),
                .PIPELINE_DEPTH (PIPELINE_DEPTH),
                .CASCADE_DEPTH  (CASCADE_DEPTH)
            ) dut (
                .clk     (ram_if.clk),
                .a_en    (ram_if.a_en),
                .a_wbe   (ram_if.a_wbe),
                .a_wdata (ram_if.a_wdata),
                .a_addr  (ram_if.a_addr),
                .b_en    (ram_if.b_en),
                .b_addr  (ram_if.b_addr),
                .b_rdata (ram_if.b_rdata)
            );
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 参考模型与记分板状态。仅由初始化和 monitor_and_check 过程更新。
    // ------------------------------------------------------------------------
    data_t ref_mem [0:MEM_DEPTH-1];
    typedef struct packed {
        longint unsigned due_cycle;
        addr_t           addr;
        data_t           data;
        bit              checkable;
    } expected_read_t;

    expected_read_t expected_read_q[$];
    longint unsigned ref_cycle;
    data_t expected_b_rdata;
    addr_t expected_b_addr;
    bit expected_check_en;
    bit expected_update;
    bit model_ready = 1'b0;

    int unsigned read_request_count;
    int unsigned read_return_count;
    int unsigned checked_read_count;
    int unsigned skipped_read_count;
    int unsigned check_count;
    int unsigned hold_check_count;
    int unsigned write_count;
    int unsigned disabled_write_count;
    int unsigned zero_mask_count;
    int unsigned full_mask_count;
    int unsigned partial_mask_count;
    int unsigned concurrent_count;
    int unsigned collision_count;
    bit read_addr_seen [0:MEM_DEPTH-1];
    bit write_addr_seen [0:MEM_DEPTH-1];
    int unsigned onehot_column_count [0:NUM_COL-1];

    string test_phase;
    bit verbose;
    int random_cycles;
    int unsigned run_seed;
    bit [31:0] rng_state;

    // ------------------------------------------------------------------------
    // 计算函数：位掩码合并与参考存储器读取。
    // ------------------------------------------------------------------------
    function automatic data_t ref_apply_write_mask(
        input data_t old_data,
        input data_t write_data,
        input col_mask_t write_be
    );
        data_t mask;
        mask = '0;
        for (int col = 0; col < NUM_COL; col++) begin
            mask[col*COL_WIDTH +: COL_WIDTH] = {COL_WIDTH{write_be[col]}};
        end
        return (old_data & ~mask) | (write_data & mask);
    endfunction : ref_apply_write_mask

    function automatic data_t ref_read_word(input addr_t addr);
        return ref_mem[addr];
    endfunction : ref_read_word

    // 独立的每实例 PRNG，避免多个并行测试共享随机状态。
    // 超过 32 位的数据分批生成，保证数据字和写掩码的高位也得到随机化。
    function automatic bit [31:0] next_random();
        rng_state ^= rng_state << 13;
        rng_state ^= rng_state >> 17;
        rng_state ^= rng_state << 5;
        return rng_state;
    endfunction : next_random

    function automatic data_t random_data();
        data_t value;
        bit [31:0] chunk;
        chunk = '0;
        for (int index = 0; index < DATA_WIDTH; index++) begin
            if ((index % 32) == 0) chunk = next_random();
            value[index] = chunk[index % 32];
        end
        return value;
    endfunction : random_data

    function automatic col_mask_t random_mask();
        col_mask_t value;
        bit [31:0] chunk;
        chunk = '0;
        for (int col = 0; col < NUM_COL; col++) begin
            if ((col % 32) == 0) chunk = next_random();
            value[col] = chunk[col % 32];
        end
        return value;
    endfunction : random_mask

    function automatic data_t address_pattern(input addr_t addr);
        data_t value;
        for (int index = 0; index < DATA_WIDTH; index++) begin
            value[index] = addr[index % ADDR_WIDTH] ^ bit'(index % 2);
        end
        return value;
    endfunction : address_pattern

    // 仅在仿真开始调用一次，匹配 DUT 的存储器初值；不作为运行时复位。
    task automatic ref_model_init();
        foreach (ref_mem[addr]) begin
            ref_mem[addr] = '0;
            read_addr_seen[addr] = 1'b0;
            write_addr_seen[addr] = 1'b0;
        end
        expected_read_q.delete();
        ref_cycle = 0;
        expected_b_rdata = 'x;
        expected_b_addr = '0;
        expected_check_en = 1'b0;
        expected_update = 1'b0;
        foreach (onehot_column_count[col]) onehot_column_count[col] = 0;
        read_request_count = 0;
        read_return_count = 0;
        checked_read_count = 0;
        skipped_read_count = 0;
        check_count = 0;
        hold_check_count = 0;
        write_count = 0;
        disabled_write_count = 0;
        zero_mask_count = 0;
        full_mask_count = 0;
        partial_mask_count = 0;
        concurrent_count = 0;
        collision_count = 0;
    endtask : ref_model_init

    // 不消耗仿真时间。先保存读请求的旧存储内容，再应用本周期的写操作。
    task automatic ref_model_step(
        input logic wr_en,
        input col_mask_t wr_be,
        input data_t wr_data,
        input addr_t wr_addr,
        input logic rd_en,
        input addr_t rd_addr
    );
        expected_read_t item;
        bit actual_write;
        bit rw_collision;

        ref_cycle++;
        expected_update = 1'b0;
        if ($isunknown({wr_en, rd_en}))
            $fatal(1, "[%m] cycle=%0d enable contains X/Z", ref_cycle);
        if (wr_en && $isunknown(wr_be))
            $fatal(1, "[%m] cycle=%0d write mask contains X/Z", ref_cycle);
        actual_write = wr_en && (|wr_be);
        if (actual_write && $isunknown(wr_addr))
            $fatal(1, "[%m] cycle=%0d write address contains X/Z", ref_cycle);
        if (rd_en && $isunknown(rd_addr))
            $fatal(1, "[%m] cycle=%0d read address contains X/Z", ref_cycle);

        rw_collision = actual_write && rd_en && (wr_addr == rd_addr);
        if (rw_collision) collision_count++;
        if (actual_write && rd_en && !rw_collision) concurrent_count++;
        if (!wr_en && (|wr_be)) disabled_write_count++;
        if (wr_en && (wr_be == '0)) zero_mask_count++;

        if (rd_en) begin
            item.addr = rd_addr;
            item.data = ref_read_word(rd_addr);
            // K 沿接受的读请求在 K+PIPELINE_DEPTH 沿的 NBA 完成后输出。
            item.due_cycle = ref_cycle + longint'(PIPELINE_DEPTH);
            item.checkable = CHECK_RTL_RW_COLLISION || !rw_collision;
            expected_read_q.push_back(item);
            read_request_count++;
            read_addr_seen[rd_addr] = 1'b1;
        end

        if (actual_write) begin
            ref_mem[wr_addr] = ref_apply_write_mask(ref_mem[wr_addr], wr_data, wr_be);
            write_count++;
            write_addr_seen[wr_addr] = 1'b1;
            if (wr_be == '1) full_mask_count++;
            else partial_mask_count++;
            for (int col = 0; col < NUM_COL; col++) begin
                if (wr_be == (col_mask_t'(1) << col))
                    onehot_column_count[col]++;
            end
        end

        if (expected_read_q.size() != 0) begin
            if (expected_read_q[0].due_cycle == ref_cycle) begin
                item = expected_read_q.pop_front();
                expected_b_rdata = item.data;
                expected_b_addr = item.addr;
                expected_check_en = item.checkable;
                expected_update = 1'b1;
                read_return_count++;
                if (!item.checkable) skipped_read_count++;
            end
        end
    endtask : ref_model_step

    task automatic check_output();
        if (expected_check_en) begin
            check_count++;
            if (expected_update) checked_read_count++;
            else hold_check_count++;
            // 四态模拟器中，DUT 返回 X/Z 也会导致已知预计值比较失败。
            if (ram_if.b_rdata !== expected_b_rdata) begin
                $fatal(1,
                    "[%m] MISMATCH phase=%s cycle=%0d addr=0x%0h actual=0x%0h expected=0x%0h new_read=%0b",
                    test_phase, ref_cycle, expected_b_addr,
                    ram_if.b_rdata, expected_b_rdata, expected_update);
            end
            if (verbose && expected_update)
                $display("[%m] MATCH cycle=%0d addr=0x%0h data=0x%0h",
                         ref_cycle, expected_b_addr, expected_b_rdata);
        end
    endtask : check_output

    // 同一过程完成预测、请求覆盖、输出比较和返回覆盖，避免进程竞争。
    always @(posedge clk) begin : monitor_and_check
        if (model_ready && !done) begin
            ref_model_step(ram_if.a_en, ram_if.a_wbe, ram_if.a_wdata,
                           ram_if.a_addr, ram_if.b_en, ram_if.b_addr);
            // 先执行参考模型的请求合法性检查，再记录请求覆盖。
            request_cov.sample(ram_if.a_en, ram_if.a_wbe, ram_if.a_addr,
                               ram_if.b_en, ram_if.b_addr);
            #1ps;
            check_output();
            // NBA 后比较完成再采样，避免把失败返回统计为检查通过。
            response_cov.sample(expected_update, expected_check_en,
                                expected_b_addr, ram_if.b_en);
        end
    end

    // ------------------------------------------------------------------------
    // 驱动任务：只驱动 DUT 输入，不修改参考模型。
    // 每次调用产生一个周期的请求，连续调用可产生背靠背请求。
    // ------------------------------------------------------------------------
    task automatic drive_cycle(
        input bit wr_en = 1'b0,
        input addr_t wr_addr = '0,
        input data_t wr_data = '0,
        input col_mask_t wr_be = '0,
        input bit rd_en = 1'b0,
        input addr_t rd_addr = '0
    );
        @(negedge clk);
        ram_if.a_en = wr_en;
        ram_if.a_addr = wr_addr;
        ram_if.a_wdata = wr_data;
        ram_if.a_wbe = wr_be;
        ram_if.b_en = rd_en;
        ram_if.b_addr = rd_addr;
        @(posedge clk);
        #2ps; // 本周期的 monitor/check 完成后，测试流程才继续。
    endtask : drive_cycle

    task automatic write_word(
        input addr_t addr,
        input data_t data,
        input col_mask_t mask = '1
    );
        drive_cycle(.wr_en(1'b1), .wr_addr(addr), .wr_data(data), .wr_be(mask));
    endtask : write_word

    task automatic read_word(input addr_t addr);
        drive_cycle(.rd_en(1'b1), .rd_addr(addr));
    endtask : read_word

    task automatic idle_cycles(input int count);
        repeat (count) drive_cycle();
    endtask : idle_cycles

    task automatic drain_pipeline();
        idle_cycles(PIPELINE_DEPTH + 2);
        if (expected_read_q.size() != 0)
            $fatal(1, "[%m] expected read queue did not drain");
    endtask : drain_pipeline

    task automatic begin_phase(input string name);
        test_phase = name;
        $display("[%m] PHASE %s", name);
    endtask : begin_phase

    task automatic read_all(input bit reverse_order = 1'b0);
        for (int addr = 0; addr < MEM_DEPTH; addr++) begin
            read_word(addr_t'(reverse_order ? MEM_DEPTH - 1 - addr : addr));
        end
        drain_pipeline();
    endtask : read_all

    // ------------------------------------------------------------------------
    // 定向测试：每个测试结束时排空读流水线，错误信息可定位到当前阶段。
    // ------------------------------------------------------------------------
    task automatic test_initial_contents();
        begin_phase("initial zero / all addresses");
        read_all();
    endtask : test_initial_contents

    task automatic test_data_patterns();
        addr_t addr;
        data_t walking;
        begin_phase("boundary addresses / overwrite / walking data");
        for (int index = 0; index < 3; index++) begin
            case (index)
                0: addr = FIRST_ADDR;
                1: addr = MID_ADDR;
                default: addr = LAST_ADDR;
            endcase
            write_word(addr, '0);
            read_word(addr);
            write_word(addr, '1);
            read_word(addr);
            write_word(addr, address_pattern(addr));
            read_word(addr);
        end
        //中间地址诸位置1和诸位置0的交替写入，检查每个位的独立写入。
        for (int index = 0; index < DATA_WIDTH; index++) begin
            walking = '0;
            walking[index] = 1'b1;
            write_word(MID_ADDR, walking);
            read_word(MID_ADDR);
            write_word(MID_ADDR, ~walking);
            read_word(MID_ADDR);
        end
        drain_pipeline();
    endtask : test_data_patterns

    // ------------------------------------------------------------------------
    // Padded 专项：相邻列相反数据 + 单列改写 + 未使能列保持。
    // 每次把整个写数据字取反，但只使能一列，再读回整个逻辑字。
    // current_word 只用于构造激励；预计返回仍由独立参考模型计算。
    // ------------------------------------------------------------------------
    task automatic test_column_mapping();
        addr_t addr;
        data_t current_word;
        data_t write_data;
        col_mask_t mask;

        begin_phase("padded column mapping / unselected column hold");
        for (int addr_index = 0; addr_index < 3; addr_index++) begin
            case (addr_index)
                0: addr = FIRST_ADDR;
                1: addr = MID_ADDR;
                default: addr = LAST_ADDR;
            endcase

            // 两种相反的列排列，确保每列都经历 0->1 与 1->0。
            for (int pass = 0; pass < 2; pass++) begin
                current_word = '0;
                for (int col = 0; col < NUM_COL; col++) begin
                    current_word[col*COL_WIDTH +: COL_WIDTH] =
                        (((col + pass) % 2) == 0)
                            ? {COL_WIDTH{1'b0}} : {COL_WIDTH{1'b1}};
                end
                write_word(addr, current_word);
                read_word(addr);

                for (int col = 0; col < NUM_COL; col++) begin
                    mask = '0;
                    mask[col] = 1'b1;
                    // 未使能列也给出与存量相反的写数据，暴露误写邻列。
                    write_data = ~current_word;
                    write_word(addr, write_data, mask);
                    read_word(addr);
                    current_word[col*COL_WIDTH +: COL_WIDTH] =
                        write_data[col*COL_WIDTH +: COL_WIDTH];
                end
            end
        end
        drain_pipeline();
    endtask : test_column_mapping

    task automatic test_write_enables();
        col_mask_t mask;
        begin_phase("per-column mask / disabled write / zero mask");
        for (int pass = 0; pass < 2; pass++) begin
            write_word(MID_ADDR, (pass == 0) ? data_t'('0) : data_t'('1));
            for (int col = 0; col < NUM_COL; col++) begin
                mask = '0;
                mask[col] = 1'b1;
                write_word(MID_ADDR, (pass == 0) ? data_t'('1) : data_t'('0), mask);
                read_word(MID_ADDR);
            end
        end
        write_word(MID_ADDR, '0);
        drive_cycle(.wr_en(1'b0), .wr_addr(MID_ADDR), .wr_data('1), .wr_be('1));
        read_word(MID_ADDR);
        drive_cycle(.wr_en(1'b1), .wr_addr(MID_ADDR), .wr_data('1), .wr_be('0));
        read_word(MID_ADDR);
        mask = '0;
        for (int col = 0; col < NUM_COL; col++) mask[col] = bit'(col % 2);
        write_word(MID_ADDR, '1, mask);
        read_word(MID_ADDR);
        write_word(MID_ADDR, '1, ~mask);
        read_word(MID_ADDR);
        drain_pipeline();
    endtask : test_write_enables

    task automatic test_address_independence();
        begin_phase("address independence / forward and reverse sweep");
        for (int addr = 0; addr < MEM_DEPTH; addr++)
            write_word(addr_t'(addr), address_pattern(addr_t'(addr)));
        read_all();
        read_all(1'b1);
    endtask : test_address_independence

    task automatic test_read_enable_and_latency();
        begin_phase("read enable / output hold / bubbles / data snapshot");
        write_word(FIRST_ADDR, '0);
        write_word(LAST_ADDR, '1);
        read_word(FIRST_ADDR);
        drain_pipeline();
        // b_en=0 时切换读地址并写入其他地址，输出应保持。
        for (int index = 0; index < 8; index++) begin
            drive_cycle(.wr_en(1'b1), .wr_addr(LAST_ADDR),
                        .wr_data(data_t'(index)), .wr_be('1),
                        .rd_en(1'b0), .rd_addr(addr_t'(index)));
        end
        // 读请求间插入气泡，已进入流水线的数据仍需按时返回。
        for (int index = 0; index < 12; index++) begin
            read_word(((index % 2) != 0) ? FIRST_ADDR : LAST_ADDR);
            idle_cycles(index % 3);
        end
        // 读请求之后改写同址，先前请求仍应返回采样时的数据。
        write_word(FIRST_ADDR, '0);
        read_word(FIRST_ADDR);
        write_word(FIRST_ADDR, '1);
        idle_cycles(PIPELINE_DEPTH + 1);
        read_word(FIRST_ADDR);
        drain_pipeline();
    endtask : test_read_enable_and_latency

    task automatic test_concurrent_access();
        addr_t addr;
        data_t data;
        col_mask_t mask;
        begin_phase("concurrent different-address / same-address collision");
        for (int index = 0; index < 16; index++) begin
            addr = addr_t'(index);
            data = random_data();
            drive_cycle(.wr_en(1'b1), .wr_addr(addr), .wr_data(data), .wr_be('1),
                        .rd_en(1'b1), .rd_addr(addr ^ addr_t'(1)));
        end
        write_word(FIRST_ADDR, address_pattern(FIRST_ADDR));
        for (int index = 0; index < 8; index++) begin
            mask = '1;
            if ((index % 2) != 0) mask = col_mask_t'(1) << (index % NUM_COL);
            data = random_data();
            drive_cycle(.wr_en(1'b1), .wr_addr(FIRST_ADDR), .wr_data(data),
                        .wr_be(mask), .rd_en(1'b1), .rd_addr(FIRST_ADDR));
        end
        // 同址但没有实际写入，不应被误判为碰撞。
        drive_cycle(.wr_en(1'b0), .wr_addr(FIRST_ADDR), .wr_data('1),
                    .wr_be('1), .rd_en(1'b1), .rd_addr(FIRST_ADDR));
        drive_cycle(.wr_en(1'b1), .wr_addr(FIRST_ADDR), .wr_data('0),
                    .wr_be('0), .rd_en(1'b1), .rd_addr(FIRST_ADDR));
        read_word(FIRST_ADDR);
        drain_pipeline();
    endtask : test_concurrent_access

    task automatic test_random_mixed();
        bit [4:0] controls;
        addr_t wr_addr;
        addr_t rd_addr;
        data_t data;
        col_mask_t mask;
        begin_phase("reproducible random mixed access");
        repeat (random_cycles) begin
            controls = 5'(next_random());
            wr_addr = addr_t'(next_random());
            rd_addr = controls[2] ? wr_addr : addr_t'(next_random());
            data = random_data();
            mask = random_mask();
            case (controls[4:3])
                2'b00: mask = '0;
                2'b01: mask = '1;
                default: ;
            endcase
            drive_cycle(.wr_en(controls[0]), .wr_addr(wr_addr),
                        .wr_data(data), .wr_be(mask),
                        .rd_en(controls[1]), .rd_addr(rd_addr));
        end
        drain_pipeline();
    endtask : test_random_mixed

    // 检查请求守恒与场景覆盖，避免没有有效比较也报告 PASS。
    task automatic check_final_status();
        if ((expected_read_q.size() != 0) || (read_request_count != read_return_count))
            $fatal(1, "[%m] pending/lost reads requests=%0d returns=%0d pending=%0d",
                   read_request_count, read_return_count, expected_read_q.size());
        if ((checked_read_count + skipped_read_count) != read_request_count)
            $fatal(1, "[%m] read accounting mismatch");
        if ((check_count == 0) || (checked_read_count == 0) || (hold_check_count == 0))
            $fatal(1, "[%m] missing read or output-hold checks");
        if ((disabled_write_count == 0) || (zero_mask_count == 0) ||
            (full_mask_count == 0) || ((NUM_COL > 1) && (partial_mask_count == 0)))
            $fatal(1, "[%m] write-enable coverage incomplete");
        if ((concurrent_count == 0) || (collision_count == 0))
            $fatal(1, "[%m] concurrent/collision coverage incomplete");
        foreach (onehot_column_count[col]) begin
            if (onehot_column_count[col] == 0)
                $fatal(1, "[%m] column %0d did not receive an individual write", col);
        end
        foreach (read_addr_seen[addr]) begin
            if (!read_addr_seen[addr] || !write_addr_seen[addr])
                $fatal(1, "[%m] address %0d did not receive both read and write access", addr);
        end
        if (CHECK_RTL_RW_COLLISION && (skipped_read_count != 0))
            $fatal(1, "[%m] RTL collision mode unexpectedly skipped reads");
        if (!CHECK_RTL_RW_COLLISION && (skipped_read_count == 0))
            $fatal(1, "[%m] collision-ignore policy was not exercised");
        // 每实例报告功能覆盖率；PASS/FAIL 继续由上面的必要检查决定。
        $display("[%m] FUNCTIONAL COVERAGE: request=%0.2f%% response=%0.2f%%",
                 request_cov.get_inst_coverage(), response_cov.get_inst_coverage());
    endtask : check_final_status

    initial begin : run_test
        done = 1'b0;
        if ((ADDR_WIDTH < 1) || (ADDR_WIDTH > 30) || (NUM_COL < 1) ||
            (COL_WIDTH < 1) || (PIPELINE_DEPTH < 0) ||
            (NUM_RANDOM_CYCLES < 0) || (TIMEOUT_CYCLES < 1))
            $fatal(1, "[%m] illegal testbench parameters");

        verbose = $test$plusargs("VERBOSE");
        run_seed = SEED;
        random_cycles = NUM_RANDOM_CYCLES;
        if ($value$plusargs("SEED=%d", run_seed)) begin end
        if ($value$plusargs("RANDOM_CYCLES=%d", random_cycles)) begin end
        if (random_cycles < 0) $fatal(1, "[%m] RANDOM_CYCLES must be nonnegative");
        rng_state = run_seed ^ (32'(ADDR_WIDTH) << 24) ^ (32'(NUM_COL) << 12) ^
                    (32'(COL_WIDTH) << 4) ^ 32'(PIPELINE_DEPTH);
        if (rng_state == 0) rng_state = 32'h1;

        ram_if.a_en = 1'b0;
        ram_if.a_wbe = '0;
        ram_if.a_wdata = '0;
        ram_if.a_addr = '0;
        ram_if.b_en = 1'b0;
        ram_if.b_addr = '0;
        ref_model_init();
        // 必须在 model_ready 置位前创建，保证 monitor 不访问空句柄。
        request_cov = new();
        response_cov = new();
        test_phase = "startup";
        model_ready = 1'b1;

        $display("[%m] START DUT=%s AW=%0d COLS=%0d CW=%0d PD=%0d CHECK_COLLISION=%0b SEED=%0d RNG_STATE=0x%08h RANDOM_CYCLES=%0d",
                 DUT_NAME, ADDR_WIDTH, NUM_COL, COL_WIDTH, PIPELINE_DEPTH,
                 CHECK_RTL_RW_COLLISION, run_seed, rng_state, random_cycles);
        idle_cycles(PIPELINE_DEPTH + 2);
        test_initial_contents();
        test_data_patterns();
        if (USE_PADDED_DUT) test_column_mapping();
        test_write_enables();
        test_address_independence();
        test_read_enable_and_latency();
        test_concurrent_access();
        test_random_mixed();
        begin_phase("final all-address readback");
        read_all();
        check_final_status();

        $display("[%m] %s TEST PASSED: AW=%0d COLS=%0d CW=%0d PD=%0d cycles=%0d checks=%0d read_checks=%0d hold_checks=%0d skipped=%0d writes=%0d collisions=%0d",
                 DUT_NAME, ADDR_WIDTH, NUM_COL, COL_WIDTH, PIPELINE_DEPTH,
                 ref_cycle, check_count, checked_read_count, hold_check_count,
                 skipped_read_count, write_count, collision_count);
        done = 1'b1;
    end : run_test

    initial begin : watchdog
        wait (model_ready);
        repeat (TIMEOUT_CYCLES) begin
            @(posedge clk);
            if (done) break;
        end
        if (!done)
            $fatal(1, "[%m] TIMEOUT phase=%s cycle=%0d limit=%0d",
                   test_phase, ref_cycle, TIMEOUT_CYCLES);
    end : watchdog
endmodule : tb_sdp_ram


// ============================================================================
// 回归顶层：扫描流水线深度与几何配置，全部子测试完成后统一结束仿真。
// ============================================================================
module tb_sdp_ram_top;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int NUM_PIPELINE_TESTS = 4;
    localparam int NUM_TESTS = NUM_PIPELINE_TESTS + 5;
    wire [NUM_TESTS-1:0] done;

    for (genvar depth = 0; depth < NUM_PIPELINE_TESTS; depth++) begin : gen_pipeline
        tb_sdp_ram #(
            .ADDR_WIDTH (4), .NUM_COL (4), .COL_WIDTH (8),
            .PIPELINE_DEPTH (depth)
        ) test_inst (.done(done[depth]));
    end

    // 原 DUT 默认配置：1024 x 64，附加输出流水线 1 级。
    tb_sdp_ram test_default (.done(done[NUM_PIPELINE_TESTS]));

    // 最小地址、数据和列数；NUM_COL=1 时不存在部分列写。
    tb_sdp_ram #(
        .ADDR_WIDTH (1), .NUM_COL (1), .COL_WIDTH (1), .PIPELINE_DEPTH (0)
    ) test_minimal (.done(done[NUM_PIPELINE_TESTS+1]));

    // 非字节列宽及超过 64 位的数据字，检查切片边界和高位随机化。
    tb_sdp_ram #(
        .ADDR_WIDTH (3), .NUM_COL (3), .COL_WIDTH (35), .PIPELINE_DEPTH (2)
    ) test_wide (.done(done[NUM_PIPELINE_TESTS+2]));

    // 超过 32 个写使能位，检查掩码高位与单列写入。
    tb_sdp_ram #(
        .ADDR_WIDTH (2), .NUM_COL (33), .COL_WIDTH (1), .PIPELINE_DEPTH (1)
    ) test_many_columns (.done(done[NUM_PIPELINE_TESTS+3]));

    // 检查碰撞结果屏蔽及下一次有效返回后恢复比较的策略。
    tb_sdp_ram #(
        .ADDR_WIDTH (3), .NUM_COL (2), .COL_WIDTH (9), .PIPELINE_DEPTH (3),
        .CHECK_RTL_RW_COLLISION (1'b0)
    ) test_collision_ignore (.done(done[NUM_PIPELINE_TESTS+4]));

    initial begin
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_sdp_ram.vcd");
            $dumpvars(0, tb_sdp_ram_top);
        end
        wait (&done);
        $display("ALL SDP_RAM TESTS PASSED: %0d configurations", NUM_TESTS);
        $finish;
    end
endmodule : tb_sdp_ram_top
