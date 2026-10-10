`timescale 1ns/1ps
module tb_instruction_memory_upload;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [7:0] address = 0;
    reg write_enable = 0;
    reg [8:0] write_address = 0;
    reg [31:0] write_data = 0;
    reg [3:0] write_byteenable = 0;
    wire [31:0] instruction, rom_instruction;
    instruction_memory #(.PROGRAM_WORDS(9), .WRITABLE(1)) dut (
        .clk(clk), .address(address), .write_enable(write_enable),
        .write_address(write_address), .write_data(write_data),
        .write_byteenable(write_byteenable), .instruction(instruction));
    instruction_memory #(.PROGRAM_WORDS(9)) protected_rom (
        .clk(clk), .address(8'd0), .write_enable(1'b1), .write_address(9'd0),
        .write_data(32'hDEADBEEF), .write_byteenable(4'hF), .instruction(rom_instruction));
    task automatic read_word(input [7:0] addr, input [31:0] expected);
        reg [31:0] previous;
        @(negedge clk); previous = instruction; address = addr;
        #1;
        if (instruction !== previous) $fatal(1, "RAM read changed without a rising edge");
        @(posedge clk); #1;
        if (instruction !== expected) $fatal(1, "Read %0d=%h expected %h", addr, instruction, expected);
    endtask
    task automatic write_word(input [8:0] addr, input [31:0] data, input [3:0] bytes);
        @(negedge clk); write_enable = 1; write_address = addr;
        write_data = data; write_byteenable = bytes;
        @(negedge clk); write_enable = 0;
    endtask
    initial begin
        read_word(3, 32'h50000804);
        @(negedge clk); write_enable = 1; write_address = 3;
        write_data = 32'hDEADBEEF; write_byteenable = 4'hF;
        @(posedge clk); #1;
        if (instruction !== 32'h50000804) $fatal(1, "Read/write collision did not return old data");
        @(negedge clk); write_enable = 0;
        @(posedge clk); #1;
        if (instruction !== 32'hDEADBEEF) $fatal(1, "Full-word write failed");
        write_word(3, 32'h11223344, 4'b1010);
        read_word(3, 32'h11AD33EF);
        write_word(3, 32'hFFFFFFFF, 4'd0);
        read_word(3, 32'h11AD33EF);
        write_word(8, 32'h20100007, 4'hF);
        read_word(8, 32'h20100007);
        write_word(9, 32'hDEADBEEF, 4'hF);
        write_word(256, 32'hDEADBEEF, 4'hF);
        read_word(9, 32'hF0000000);
        read_word(0, 32'h0F000000);
        read_word(8, 32'h20100007);
        if (rom_instruction !== 32'h0F000000)
            $fatal(1, "WRITABLE=0 ROM accepted a write");
        $display("PASS tb_instruction_memory_upload: synchronous RAM/old-data, byte masks, first/last bounds, 256 alias rejection and ROM write protection");
        $finish;
    end
endmodule
