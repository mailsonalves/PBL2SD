`timescale 1ns/1ps
module tb_gpu_frame_control;
    reg clk=0,rst_n=0,frame_boundary=0;
    wire [31:0] frame_counter;
    integer count=0,i;
    gpu_frame_control dut (.*);
    always #5 clk=~clk;
    task automatic cycle(input bit pulse);
        begin
            @(negedge clk); frame_boundary=pulse;
            @(posedge clk); #1;
            if(pulse) count=count+1;
            if(frame_counter !== count) $fatal(1,"Frame count got %0d expected %0d",frame_counter,count);
        end
    endtask
    initial begin
        #1; rst_n=1; #1; rst_n=0; #1;
        if(frame_counter !== 0) $fatal(1,"Frame reset");
        @(negedge clk); rst_n=1;
        for(i=0;i<150;i=i+1) cycle(i%7==0);
        @(negedge clk); #2; rst_n=0; #1;
        if(frame_counter !== 0) $fatal(1,"Frame async reset");
        frame_boundary=0; count=0;
        @(negedge clk); rst_n=1;
        cycle(0); cycle(1); cycle(0);
        $display("PASS tb_gpu_frame_control: counted frame pulses and asynchronous restart");
        $finish;
    end
    initial begin #5000; $fatal(1,"Frame timeout"); end
endmodule
