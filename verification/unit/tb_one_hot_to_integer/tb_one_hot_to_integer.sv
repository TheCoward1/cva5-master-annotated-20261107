module tb_one_hot_to_integer #(
    parameter C_WIDTH = 40
)(
    
);
    logic [C_WIDTH-1:0] one_hot;// 输入 one-hot 向量
    logic [(C_WIDTH == 1) ? 0 : ($clog2(C_WIDTH)-1) : 0] int_out;//实际输出
    logic [(C_WIDTH == 1) ? 0 : ($clog2(C_WIDTH)-1) : 0] expected_int_out;//参考模型输出

    one_hot_to_integer #(.C_WIDTH(C_WIDTH)) one_hot_to_integer_1
    (
        .one_hot(one_hot),
        .int_out(int_out)
    );
    //参考模型
    
    function automatic logic [(C_WIDTH == 1) ? 0 : ($clog2(C_WIDTH)-1) : 0] ref_one_hot_to_integer(
        input logic [C_WIDTH-1:0] v
    );
        
        for (int i = 0; i < C_WIDTH; i++) begin
            if (v[i] == 1'b1) begin
                return $clog2(C_WIDTH)'(i);
            end
        end
        return '0;
    endfunction
    //检测一的个数 若为多个则返回0
    task automatic check(
        input logic [C_WIDTH-1:0] v
    );
        int i_num = 0;
        foreach(v[i]) begin
            if (v[i] == 1'b1) begin
                i_num++;
                if(i_num>1) begin
                    expected_int_out = '0;
                    return;
                end
            end
        end
    endtask


    initial begin
        
        // 测试所有可能的 one-hot 输入
        for (int i = 0; i < C_WIDTH; i++) begin
            one_hot = 0;
            one_hot[i] = 1'b1; // 设置第 i 位为 1，其他位为 0
            #1; // 等待组合逻辑传播稳定
            expected_int_out = ref_one_hot_to_integer(one_hot);
            check(one_hot);
            if (int_out !== expected_int_out) begin
                $fatal(1, "ERROR: input=%b expected=%b got=%b",
                       one_hot, expected_int_out, int_out);
            end else begin
                $display("PASS: input=%b output=%b", one_hot, int_out);
            end
        end

        // 测试输入全为 0 的情况
        one_hot = 0;
        #1;
        expected_int_out = ref_one_hot_to_integer(one_hot);
        check(one_hot);
        if (int_out !== expected_int_out) begin
            $fatal(1, "ERROR: input=%b expected=%b got=%b",
                   one_hot, expected_int_out, int_out);
        end else begin
            $display("PASS: input=%b output=%b", one_hot, int_out);
        end 

        //测试输入多位为 1 的情况
        one_hot = 0;
        one_hot[0] = 1'b1;
        one_hot[1] = 1'b1;
        #1;
        expected_int_out = ref_one_hot_to_integer(one_hot);
        check(one_hot);
        if (int_out !== expected_int_out) begin
            $fatal(1, "ERROR: input=%b expected=%b got=%b",
                   one_hot, expected_int_out, int_out);
        end else begin
            $display("PASS: input=%b output=%b", one_hot, int_out);
        end

        $display("All tests passed!");
        $finish;
    end
endmodule
