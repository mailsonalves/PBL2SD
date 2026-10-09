`timescale 1ns/1ps
module tb_gpu_register_file;
    reg clk=0, rst_n=0, we=0;
    reg [3:0] write_addr=0, read_addr_a=0, read_addr_b=0;
    reg [31:0] write_data=0;
    wire [31:0] read_data_a, read_data_b;
    reg [31:0] expected [0:15];
    integer checks=0, i, j;
    gpu_register_file dut (.*);
    always #5 clk=~clk;

    task automatic check_all;
        integer a,b;
        begin
            for(a=0;a<16;a=a+1) for(b=0;b<16;b=b+1) begin
                read_addr_a=a; read_addr_b=b; #1;
                if(read_data_a !== expected[a] || read_data_b !== expected[b])
                    $fatal(1,"RF read R%0d/R%0d got %08x/%08x expected %08x/%08x",a,b,
                           read_data_a,read_data_b,expected[a],expected[b]);
                checks=checks+1;
            end
        end
    endtask
    task automatic write_register(input integer address,input reg [31:0] data,input bit enable);
        begin
            @(negedge clk); write_addr=address; write_data=data; we=enable;
            @(posedge clk); #1;
            if(enable && address!=0) expected[address]=data;
            @(negedge clk); we=0;
        end
    endtask

    initial begin
        for(i=0;i<16;i=i+1) expected[i]=0;
        #1; rst_n=1; #1; rst_n=0; #1;
        check_all();
        @(negedge clk); rst_n=1;
        for(i=0;i<16;i=i+1) write_register(i,32'hA5F00000 ^ (32'h01020408*i),1);
        check_all();
        // Disabled writes and writes to R0 must never damage either read port.
        for(i=0;i<16;i=i+1) write_register(i,32'hFFFFFFFF,0);
        write_register(0,32'hFFFFFFFF,1);
        check_all();
        for(i=15;i>0;i=i-1) write_register(i,32'h80000000 | i,1);
        check_all();
        // Reset is asynchronous and wins over an enabled write.
        @(negedge clk); we=1; write_addr=7; write_data=32'hDEADBEEF;
        #2; rst_n=0;
        for(i=0;i<16;i=i+1) expected[i]=0;
        #1; read_addr_a=7; read_addr_b=15; #1;
        if(read_data_a !== 0 || read_data_b !== 0) $fatal(1,"RF async reset failed");
        check_all();
        @(negedge clk); we=0; rst_n=1;
        write_register(15,32'h12345678,1); check_all();
        $display("PASS tb_gpu_register_file: %0d dual-port reads; all registers, R0, write enable and asynchronous reset",checks);
        $finish;
    end
    initial begin #20000; $fatal(1,"RF timeout"); end
endmodule
