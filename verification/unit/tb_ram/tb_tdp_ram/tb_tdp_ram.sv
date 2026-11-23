`timescale 1ns/1ps
interface tdp_ram_if #(
        parameter ADDR_WIDTH = 10, // 存储字地址宽度，默认 1024 个字。
        parameter NUM_COL = 4, // 每个存储字中可独立写入的列数，也是两口写掩码的位数。
        parameter COL_WIDTH = 16 // 每列位宽，也是单个写使能位控制的数据位数。
)(
    input logic clk // 两个端口与全部读流水级共用的上升沿时钟。
);
        // A 口读写操作共用地址 a_addr。
        logic a_en;// A 口总使能。
        logic[NUM_COL-1:0] a_wbe; // A 口写掩码，第 i 位控制第 i 列。全零表示读。
        logic[COL_WIDTH*NUM_COL-1:0] a_wdata; // 完整写数据字，只有选中的列会写入。
        logic[ADDR_WIDTH-1:0] a_addr; // A 口读或写的存储字地址。
        logic[COL_WIDTH*NUM_COL-1:0] a_rdata; // A 口的同步读数据，经可选流水线输出。

        // B 口与 A 口访问同一数组，使用自己的一组控制信号。
        logic b_en; // B 口总使能。
        logic[NUM_COL-1:0] b_wbe; // B 口写掩码，第 i 位控制第 i 列。全零表示读。
        logic[COL_WIDTH*NUM_COL-1:0] b_wdata; // B 口完整写数据字。
        logic[ADDR_WIDTH-1:0] b_addr; // B 口读或写的存储字地址。
        logic[COL_WIDTH*NUM_COL-1:0] b_rdata; // B 口的同步读数据，经可选流水线输出。
endinterface :  tdp_ram_if

module tb_tdp_ram #(
    parameter ADDR_WIDTH = 10,
    parameter NUM_COL = 4,
    parameter COL_WIDTH = 16,
    parameter PIPELINE_DEPTH = 1,
    parameter CASCADE_DEPTH = 4
)(
    output logic done
);
    timeunit 1ns;
    timeprecision 1ps;
    //数据宽度 
    localparam DATA_WIDTH = COL_WIDTH*NUM_COL; // 完整存储字的位宽，默认 64 位。
    //BRAM的深度
    localparam MEM_DEPTH = 1 << ADDR_WIDTH; // 存储字数
    //地址类型
    typedef logic [ADDR_WIDTH-1:0] addr_t;
    //数据类型
    typedef logic [DATA_WIDTH-1:0] data_t;
    //某一列更新标记 写更改
    typedef logic [NUM_COL-1:0] col_mask;

    logic clk;

    typedef enum bit[1:0] {
        TDP_IDLE = 2'b00,
        TDP_READ = 2'b01,
        TDP_WRITE = 2'b10
    } tdp_access_t;

    //返回当前访问类型，若端口未使能则返回 TDP_IDLE。
    function automatic tdp_access_t tdp_port_access(
        input bit en,
        input col_mask wbe
    );
        if (!en)
            return TDP_IDLE;
        else if (|wbe)
            return TDP_WRITE;
        else
            return TDP_READ;
    endfunction : tdp_port_access



    //判断现在的one_hot 列使能 的下标
    function automatic int tdp_onehot_column(input col_mask mask);
        int index;
        index = -1;
        for (int i = 0; i < NUM_COL; i++) begin
            if (mask[i]) begin
                if (index != -1)
                    $fatal(1, "[%m] multiple bits set in one-hot mask %b", mask);
                return i;
            end
        end
        return index;
    endfunction : tdp_onehot_column

    covergroup tdp_ram_request_cg with function sample(
        input tdp_access_t a_op,
        input tdp_access_t b_op,
        input bit same_addr,
        input col_mask a_wbe,
        input col_mask b_wbe
    );
        option.per_instance = 1;
        // A 口读写操作覆盖
        cp_a_op: coverpoint a_op{
            bins tdp_a_idle = {TDP_IDLE};
            bins tdp_a_read = {TDP_READ};
            bins tdp_a_write = {TDP_WRITE};
        }
        // B 口读写操作覆盖
        cp_b_op: coverpoint b_op{
            bins tdp_b_idle = {TDP_IDLE};
            bins tdp_b_read = {TDP_READ};
            bins tdp_b_write = {TDP_WRITE};
        }
        // A 口和 B 口读写操作 合并仓
        cp_ab_op: cross cp_a_op, cp_b_op;
        // A 口和 B 口访问同一地址的覆盖
        cp_same_addr: coverpoint {same_addr, a_op, b_op} 
            iff(a_op != TDP_IDLE && b_op != TDP_IDLE) {
            bins same_addr_r_r = {{1'b1, TDP_READ, TDP_READ}};
            bins same_addr_r_w = {{1'b1, TDP_READ, TDP_WRITE}};
            bins same_addr_w_r = {{1'b1, TDP_WRITE, TDP_READ}};
            bins same_addr_w_w_disjoint = {{1'b1, TDP_WRITE, TDP_WRITE}} 
                with (item == {{1'b1, TDP_WRITE, TDP_WRITE}} && (NUM_COL > 1));


            bins diff_addr_r_r = {{1'b0, TDP_READ, TDP_READ}};
            bins diff_addr_r_w = {{1'b0, TDP_READ, TDP_WRITE}};
            bins diff_addr_w_r = {{1'b0, TDP_WRITE, TDP_READ}};
            bins diff_addr_w_w = {{1'b0, TDP_WRITE, TDP_WRITE}};
        }
        // A 口和 B 口写入的列掩码覆盖
        cp_a_write_mask: coverpoint $countones(a_wbe) iff(a_op == TDP_WRITE){
            bins full_a_write = {NUM_COL};
            bins partial_a_write = {[1:NUM_COL-1]};
        }
        // B 口写入的列掩码覆盖
        cp_b_write_mask: coverpoint $countones(b_wbe) iff(b_op == TDP_WRITE){
            bins full_b_write = {NUM_COL};
            bins partial_b_write = {[1:NUM_COL-1]};
        }
        // A 口和 B 口 mask one-hot 列掩码覆盖
        cp_a_onehot_col: coverpoint tdp_onehot_column(a_wbe) 
            iff(a_op == TDP_WRITE && $countones(a_wbe) == 1){
            bins a_col[] = {[0:NUM_COL-1]};
            }
        cp_b_onehot_col: coverpoint tdp_onehot_column(b_wbe) 
            iff(b_op == TDP_WRITE && $countones(b_wbe) == 1){
            bins b_col[] = {[0:NUM_COL-1]};
        }
    endgroup : tdp_ram_request_cg

    //
    covergroup tdp_ram_response_cg with function sample(
        input bit new_read,
        input bit checkable,
        input bit read_now
    );
        option.per_instance = 1;
        // 检查是否有读数据
        cp_check_kind: coverpoint new_read iff(checkable) {
            bins hold_checked  = {1'b1};
            bins read_checked  = {1'b0};
        }
        // read_now 描述当前沿的输入，新返回也可能来自先前的请求。
        cp_read_at_return : coverpoint read_now iff (new_read && checkable) {
            bins with_new_read = {1'b1};

            // PD=0 时，当前沿无读请求就不可能出现新的读返回。
            bins without_new_read = {1'b0}
                with ((item == 1'b0) && (PIPELINE_DEPTH > 0));
        }

    endgroup : tdp_ram_response_cg

    tdp_ram_request_cg  request_cov;
    tdp_ram_response_cg a_response_cov, b_response_cov;  


    tdp_ram_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .NUM_COL(NUM_COL),
        .COL_WIDTH(COL_WIDTH)
    ) ram_if(clk);

    tdp_ram #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .NUM_COL(NUM_COL),
        .COL_WIDTH(COL_WIDTH),
        .PIPELINE_DEPTH(PIPELINE_DEPTH),
        .CASCADE_DEPTH(CASCADE_DEPTH)
    ) dut (
        .clk(clk),
        .a_en(ram_if.a_en),
        .a_wbe(ram_if.a_wbe),
        .a_wdata(ram_if.a_wdata),
        .a_addr(ram_if.a_addr),
        .a_rdata(ram_if.a_rdata),
        .b_en(ram_if.b_en),
        .b_wbe(ram_if.b_wbe),
        .b_wdata(ram_if.b_wdata),
        .b_addr(ram_if.b_addr),
        .b_rdata(ram_if.b_rdata)
    );



    //参考模型//计分板
    typedef struct packed {
        //哪一个检查周期 比对数据
        longint unsigned due_cycle;
        //待检查地址
        addr_t addr;
        //待检查数据
        data_t data;
        //是否检查这组数据 0：不检查 1：检查
        bit checkable;
    } expected_read_t;  

    //计分板队列 预计读出
    expected_read_t a_expected_read[$] , b_expected_read[$];
    //保留最近的一次记录 用于比较
    expected_read_t a_last_read , b_last_read;
    //参考BRAM
    data_t ref_mem [MEM_DEPTH];
    //ref_mem某一列被写入了  标记为1；
    bit [NUM_COL-1 : 0] ref_known_cols [MEM_DEPTH];
    //参考的周期点 上升沿递增
    longint unsigned ref_cycle;


    //预计的地址
    addr_t expected_addr;
    //预计数据
    data_t expected_data;
    //预计是否检查 0：不检查 1：检查
    bit expected_check_able;
    //是否处于更新阶段  拿取队列 变 0：进入更新 1：更新完毕
    bit expected_update;

    // ------------------------------------------------------------------------
    // 参考模型
    // ------------------------------------------------------------------------

    //ref_mem初始化完成标记
    bit model_ready = 1'b0;

    //ref_mem初始化
    task automatic ref_mem_init();
        foreach(ref_mem[addr]) begin
            ref_mem[addr] = 'x;
            ref_known_cols[addr] = '0;
        end
        expected_addr = '0;
        expected_data = '0;
        expected_check_able = '0;
        expected_update = '0;
        ref_cycle = '0;
        a_last_read = '0;
        b_last_read = '0;

        model_ready = 1'b1;
    endtask

    //返回预计读出的 数据  结构体
    function automatic expected_read_t expected_read(input addr_t addr);
        expected_read_t item;
        item.due_cycle = ref_cycle + PIPELINE_DEPTH ;
        item.addr = addr;
        item.data = ref_mem[addr];
        item.checkable = &ref_known_cols[addr];
        return item;
    endfunction : expected_read

    //写入数据 往ref_mem 
    task automatic apply_write(
        input addr_t addr,
        input data_t data,
        input col_mask wbe
    );
        for(int col=0 ; col<NUM_COL ;col++) begin
            if(wbe[col]) begin
                ref_mem[addr][col * COL_WIDTH +: COL_WIDTH] = 
                        data[col * COL_WIDTH +: COL_WIDTH];
                //若不是xz数据则标记此处被写过
                ref_known_cols[addr][col] = !$isunknown(data[col*COL_WIDTH +: COL_WIDTH]);
            end
        end
    endtask
//参考模型结束
//------------------------------------------------------------------------



    //检查计数 结构体
    typedef struct packed {
        //检查计数
        int unsigned check_count;
        //旧的数据保持检查计数 或者说是检查时未更新的计数
        int unsigned hold_check_count;
        //因检查失能而跳过的计数
        int unsigned skipped_check_count;
        //队列种吐出的数量
        int unsigned pop_count;
        //请求计数 
        int unsigned request_count;
    } port_stats_num_t;
    port_stats_num_t a_stats , b_stats;

    //单周期步进 信号合法性检查 → 判断读写 → 检测非法冲突写 → 先采样保存读预期快照 → 再执行参考模型内存更新。
    task automatic ref_model_step();
        
        bit a_write , b_write;

        if($isunknown({ram_if.a_en,ram_if.b_en}))
            $fatal(1,"cycle = %d port enable contains x/z" , ref_cycle);
        if(ram_if.a_en && $isunknown({ram_if.a_addr,ram_if.a_wbe}))
            $fatal(1,"cycle = %d port A address or mask contains x/z" , ref_cycle);
        if(ram_if.b_en && $isunknown({ram_if.b_addr,ram_if.b_wbe}))
            $fatal(1,"cycle = %d port B address or mask contains x/z" , ref_cycle);
        //判断b是否写入
        b_write = ram_if.b_en && (|ram_if.b_wbe);
        //判断a是否写入
        a_write = ram_if.a_en && (|ram_if.a_wbe);

        //若两个口同时写入同一地址，且写掩码有交集，则为非法冲突写
        if(a_write && b_write && (ram_if.a_addr == ram_if.b_addr)
            && (|(ram_if.a_wbe & ram_if.b_wbe))) begin
            $fatal(1,"cycle = %d illegal write conflict at address %h" , ref_cycle , ram_if.a_addr);
        end

        //若A口读取，则先采样保存A口的预期读快照
        if(ram_if.a_en && ram_if.a_wbe=='0) begin
            a_expected_read.push_back(expected_read(ram_if.a_addr));
            a_stats.request_count++;
        end
        //若B口读取，则先采样保存B口的预期读快照
        if(ram_if.b_en && ram_if.b_wbe=='0) begin
            b_expected_read.push_back(expected_read(ram_if.b_addr));
            b_stats.request_count++;
        end

        //a口写入，则更新参考模型
        if(a_write) begin
            apply_write(ram_if.a_addr,ram_if.a_wdata,ram_if.a_wbe);
        end
        //b口写入，则更新参考模型
        if(b_write) begin
            apply_write(ram_if.b_addr,ram_if.b_wdata,ram_if.b_wbe);
        end
    endtask : ref_model_step

    //

    //检查实际读出的数据是否与预计读出的数据一致
    task automatic check_expected_read(
        ref expected_read_t expected_out,
        input data_t actual_data,
        input string phase_name,
        input string port_name,
        ref expected_read_t read_list[$],
        ref port_stats_num_t stats_num
    );
        bit new_read = 1'b0;

        if (read_list.size() > 0) begin
            expected_read_t front = read_list[0];
            //队首只用于判断到期。未来的记录留在队列中。
            if (front.due_cycle < ref_cycle)
                $fatal(1, "[%m] phase=%s port=%s cycle=%0d overdue read due=%0d",
                       phase_name, port_name, ref_cycle, front.due_cycle);

            if (front.due_cycle == ref_cycle) begin
                new_read = 1'b1;
                expected_out = read_list.pop_front();
                stats_num.pop_count++;
            end
        end

        //队列空时也要检查保持。比较值始终来自最近到期的记录。
        if (expected_out.checkable) begin
            if (expected_out.data !== actual_data)
                $fatal(1, "[%m] phase=%s port=%s cycle=%0d addr=0x%0h expected=0x%0h actual=0x%0h new_read=%0b",
                       phase_name, port_name, ref_cycle, expected_out.addr,
                       expected_out.data, actual_data, new_read);
            if (new_read)
                stats_num.check_count++;
            else
                stats_num.hold_check_count++;
        end
        else if (new_read) begin
            stats_num.skipped_check_count++;
        end

        if(port_name == "A") 
            a_response_cov.sample(new_read, expected_out.checkable, ram_if.a_en && ram_if.a_wbe=='0);
        else
            b_response_cov.sample(new_read, expected_out.checkable, ram_if.b_en && ram_if.b_wbe=='0);

    endtask : check_expected_read

    //阶段名 用于打印错误时显示阶段
    string phase_name;

    //每个时钟周期上升沿，若参考模型已准备好且测试未完成，则执行参考模型步进，
    //检查A口和B口的实际读数据是否与预计读数据一致，并更新参考周期计数。
    always @(posedge clk) begin
        if(model_ready && !done) begin
            ref_model_step();
            request_cov.sample(tdp_port_access(ram_if.a_en, ram_if.a_wbe),
                               tdp_port_access(ram_if.b_en, ram_if.b_wbe),
                               (ram_if.a_addr == ram_if.b_addr),
                               ram_if.a_wbe, ram_if.b_wbe);
            #1ps;
            //日志分别标识测试阶段和 A/B 端口。
            check_expected_read(a_last_read, ram_if.a_rdata, phase_name, "A",
                                a_expected_read, a_stats);
            check_expected_read(b_last_read, ram_if.b_rdata, phase_name, "B",
                                b_expected_read, b_stats);
            ref_cycle++;
        end
    end
    // ------------------------------------------------------------------------
    //驱动driver
    // ------------------------------------------------------------------------
    task automatic driver_cycle(

        input bit a_en = '0,
        input addr_t a_addr = '0,
        input col_mask a_wbe = '0,
        input data_t a_wdata = '0,

        input bit b_en = '0,
        input addr_t b_addr = '0,
        input col_mask b_wbe = '0,
        input data_t b_wdata = '0
    );
        @(negedge clk);
        ram_if.a_en = a_en;
        ram_if.a_addr = a_addr;
        ram_if.a_wbe = a_wbe;
        ram_if.a_wdata = a_wdata;

        ram_if.b_en = b_en;
        ram_if.b_addr = b_addr;
        ram_if.b_wbe = b_wbe;
        ram_if.b_wdata = b_wdata;

        @(posedge clk);
        #2ps;

    endtask : driver_cycle

    //测试开始阶段 命名和打印（每个阶段开始调用）
    task automatic test_phase_start(input string name);
        phase_name = name;
        $display("cycle = %d start test phase: %s" , ref_cycle , phase_name);
    endtask : test_phase_start

    //排空队列
    task automatic drain_pipelinr();
        repeat(PIPELINE_DEPTH+1) driver_cycle();
        if(a_expected_read.size() > 0 || b_expected_read.size() > 0) begin
            $fatal(1,"cycle = %d drain pipeline failed, a_expected_read size = %0d, b_expected_read size = %0d" , 
                ref_cycle , a_expected_read.size() , b_expected_read.size());
        end
    endtask : drain_pipelinr

    //------------------------------------------------------------------------
    //测试用例
    //------------------------------------------------------------------------

    // 限制扫描地址数，避免小地址宽度下地址被截断后重复访问。
    localparam int CROSS_ADDR_COUNT = (MEM_DEPTH < 10) ? MEM_DEPTH : 10;

    //交叉读写测试 用于验证A口写入，B口读取，B口写入，A口读取的情况
    task automatic cross_read_write_test();
        //A 先写完这一组地址，再让 B 读回已初始化的整字。
        test_phase_start("cross_read_write_test_phase_1");
        for (int i = 0; i < CROSS_ADDR_COUNT; i++)
            driver_cycle(.a_en(1'b1), .a_addr(addr_t'(i)),
                         .a_wbe('1), .a_wdata(data_t'(i + 1)));
        for (int i = 0; i < CROSS_ADDR_COUNT; i++)
            driver_cycle(.b_en(1'b1), .b_addr(addr_t'(i)), .b_wbe('0));
        drain_pipelinr();

        //B 写入与 A 读取分拍。B 写相反的数据，确保读回能发现写入丢失。
        test_phase_start("cross_read_write_test_phase_2");
        for (int i = 0; i < CROSS_ADDR_COUNT; i++)
            driver_cycle(.b_en(1'b1), .b_addr(addr_t'(i)),
                         .b_wbe('1), .b_wdata(~data_t'(i + 1)));
        for (int i = 0; i < CROSS_ADDR_COUNT; i++)
            driver_cycle(.a_en(1'b1), .a_addr(addr_t'(i)), .a_wbe('0));
        drain_pipelinr();
    endtask : cross_read_write_test

    //测试同一地址读写
    task automatic same_address_read_write_test();
        addr_t addr;
        addr = '0;
        test_phase_start("same_address_read_write_test");
        
        driver_cycle(.a_en(1'b1), .a_addr(addr), .a_wbe('1), .a_wdata('1));

        // A 写、B 同拍读。当前 RTL 的 B 返回旧值全 1。
        driver_cycle(.a_en(1'b1), .a_addr(addr), .a_wbe('1), .a_wdata('0),
                     .b_en(1'b1), .b_addr(addr), .b_wbe('0));
        //下一拍重新读，验证 A 的新写入确实生效。
        driver_cycle(.b_en(1'b1), .b_addr(addr), .b_wbe('0));

        //换向。A 同拍读旧值全 0，再读到 B 写入的新值全 1。
        driver_cycle(.a_en(1'b1), .a_addr(addr), .a_wbe('0),
                     .b_en(1'b1), .b_addr(addr), .b_wbe('1), .b_wdata('1));
        driver_cycle(.a_en(1'b1), .a_addr(addr), .a_wbe('0));
        drain_pipelinr();
    endtask : same_address_read_write_test


    //保证列大于1时，AB选中不同的列
    task automatic different_column_read_write_test();
        addr_t addr;
        data_t initial_word;
        col_mask a_mask, b_mask;

        addr = '0;
        test_phase_start("different_column_read_write_test");

        //先写已知整字。让两笔单列写分别改变最低列和最高列。
        initial_word = '0;
        for (int col = 1; col < NUM_COL; col++)
            initial_word[col*COL_WIDTH +: COL_WIDTH] = '1;
        driver_cycle(.a_en(1'b1), .a_addr(addr),
                     .a_wbe('1), .a_wdata(initial_word));

        //分别只选中一列，避免用全 1 掩码移位造成重叠。
        a_mask = '0;
        b_mask = '0;
        a_mask[0] = 1'b1;
        b_mask[NUM_COL-1] = 1'b1;
        driver_cycle(.a_en(1'b1), .a_addr(addr), .a_wbe(a_mask), .a_wdata('1),
                     .b_en(1'b1), .b_addr(addr), .b_wbe(b_mask), .b_wdata('0));

        //两口都读整字，检查选中列合并与未选列保持。
        driver_cycle(.a_en(1'b1), .a_addr(addr), .a_wbe('0),
                     .b_en(1'b1), .b_addr(addr), .b_wbe('0));
        drain_pipelinr();
    endtask : different_column_read_write_test

    //测试用例结束
    //------------------------------------------------------------------------

    // ------------------------------------------------------------------------
    //检查计数器
    // ------------------------------------------------------------------------
    task automatic check_port_final(
        input string            port_name,
        input port_stats_num_t  stats,
        input int               pending
    );
        int expected_reads;

        //沿用现有统计字段，核对每组用例应产生的确切读请求数。
        expected_reads = CROSS_ADDR_COUNT + 2 + ((NUM_COL > 1) ? 1 : 0);
        if (pending != 0 ||
            stats.request_count != expected_reads ||
            stats.request_count != stats.pop_count ||
            stats.pop_count != (stats.check_count + stats.skipped_check_count))
            $fatal(1, "[%m] port=%s expected_reads=%0d requests=%0d popped=%0d checked=%0d skipped=%0d pending=%0d",
                   port_name, expected_reads, stats.request_count, stats.pop_count,
                   stats.check_count, stats.skipped_check_count, pending);

        //这一轮所有读地址都由用例先整字写入，因此任何跳过都应报错。
        if (stats.check_count == 0 || stats.hold_check_count == 0 ||
            stats.skipped_check_count != 0)
            $fatal(1, "[%m] port=%s checked=%0d hold=%0d skipped=%0d",
                   port_name, stats.check_count, stats.hold_check_count,
                   stats.skipped_check_count);
    endtask


    // ------------------------------------------------------------------------
    // initialization and test sequence
    // ------------------------------------------------------------------------

    //时钟周期为10ns
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    //初始化参考模型
    initial begin : run_test
        done = 1'b0;
        {ram_if.a_en, ram_if.a_addr, ram_if.a_wbe, ram_if.a_wdata} = '0;
        {ram_if.b_en, ram_if.b_addr, ram_if.b_wbe, ram_if.b_wdata} = '0;
        a_stats = '0;
        b_stats = '0;
        a_expected_read.delete();
        b_expected_read.delete();
        phase_name = "init";
        request_cov = new();
        a_response_cov = new();
        b_response_cov = new();
        ref_mem_init();

        cross_read_write_test();
        same_address_read_write_test();
        if (NUM_COL > 1) different_column_read_write_test();

        check_port_final("A", a_stats, a_expected_read.size());
        check_port_final("B", b_stats, b_expected_read.size());

        //使用 port_stats_num_t 的现有字段报告读检查和保持检查。
        $display("[%m] TDP_RAM DIRECTED PASS PD=%0d A_checked=%0d B_checked=%0d A_hold=%0d B_hold=%0d",
                 PIPELINE_DEPTH, a_stats.check_count, b_stats.check_count,
                 a_stats.hold_check_count, b_stats.hold_check_count);
        
        $display("[%m] TDP_RAM FUNCTIONAL COVERAGE PD=%0d request=%0.2f%% A_response=%0.2f%% B_response=%0.2f%%",
                 PIPELINE_DEPTH,
                 request_cov.get_inst_coverage(),
                 a_response_cov.get_inst_coverage(),
                 b_response_cov.get_inst_coverage());
        done = 1'b1;
    end
    //看门狗
    //每个配置独立超时，便于定位哪一项卡住。 
    initial begin : watchdog
        wait (model_ready);
        repeat (1000) @(posedge clk);
        // 复用现有阶段变量 phase_name。
        if (!done)
            $fatal(1, "[%m] TIMEOUT phase=%s cycle=%0d", phase_name, ref_cycle);
    end
endmodule : tb_tdp_ram
    // 放在现有 endmodule : tb_tdp_ram 之后。
module tb_tdp_ram_top;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int NUM_CONFIGS = 3;
    wire [NUM_CONFIGS-1:0] done;

    for (genvar depth = 0; depth < NUM_CONFIGS; depth++) begin : gen_depth
        tb_tdp_ram #(
            .ADDR_WIDTH     (3),
            .NUM_COL        (4),
            .COL_WIDTH      (8),
            .PIPELINE_DEPTH (depth)
        ) test_inst (.done(done[depth]));
    end

    initial begin : finish_regression
        wait (&done);
        $display("ALL TDP_RAM DIRECTED TESTS PASSED: %0d configurations",
                 NUM_CONFIGS);
        $finish;
    end
endmodule : tb_tdp_ram_top
