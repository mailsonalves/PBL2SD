`timescale 1ns/1ps
module tb_gpu_cpu_units;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, restart = 0;
    reg [3:0] operation;
    reg [31:0] operand_a, operand_b;
    wire [31:0] result;
    wire [3:0] alu_flags;
    gpu_alu alu (.operation(operation), .operand_a(operand_a), .operand_b(operand_b),
                 .result(result), .flags(alu_flags));

    reg write_enable = 0;
    reg [3:0] write_address = 0, read_a = 0, read_b = 0, read_c = 0;
    reg [31:0] write_data = 0;
    wire [31:0] value_a, value_b, value_c;
    gpu_register_file registers (.clk(clk), .rst_n(rst_n), .restart(restart),
        .write_enable(write_enable), .write_address(write_address), .write_data(write_data),
        .read_address_a(read_a), .read_address_b(read_b), .read_address_c(read_c),
        .read_data_a(value_a), .read_data_b(value_b), .read_data_c(value_c));

    reg [31:0] instruction = 32'hF0000000;
    reg execute = 0, status_error = 0;
    wire alu_instruction, graphics_instruction, flow_instruction, halt_instruction, invalid_instruction;
    wire [3:0] subop, flags;
    wire [31:0] graphics_word;
    gpu_datapath datapath (.clk(clk), .rst_n(rst_n), .restart(restart), .execute(execute),
        .instruction(instruction), .status_error(status_error), .alu_instruction(alu_instruction),
        .graphics_instruction(graphics_instruction), .flow_instruction(flow_instruction),
        .halt_instruction(halt_instruction), .invalid_instruction(invalid_instruction),
        .subop(subop), .graphics_word(graphics_word), .flags(flags));

    task automatic check_alu(input [3:0] op, input [31:0] a, b,
                              input [31:0] expected, input [3:0] expected_flags);
        operation = op; operand_a = a; operand_b = b; #1;
        if (result !== expected || alu_flags !== expected_flags)
            $fatal(1, "ALU op=%h a=%h b=%h: result=%h flags=%h expected=%h/%h",
                   op, a, b, result, alu_flags, expected, expected_flags);
    endtask
    task automatic check_decode(input [31:0] word, input bit invalid,
                                input [31:0] expected_graphics);
        instruction = word; #1;
        if (invalid_instruction !== invalid)
            $fatal(1, "Validation of %h returned invalid=%b", word, invalid_instruction);
        if (!invalid && graphics_instruction && graphics_word !== expected_graphics)
            $fatal(1, "Graphics mapping %h returned %h expected %h", word, graphics_word, expected_graphics);
    endtask
    task automatic load_register(input [3:0] rd, input [15:0] immediate);
        @(negedge clk); instruction = {8'h20, rd, 4'd0, immediate}; execute = 1;
        @(negedge clk); execute = 0;
    endtask

    integer index, iteration;
    reg [31:0] random_a, random_b, expected;
    reg [32:0] wide_expected;
    reg [3:0] expected_flags;
    initial begin
        @(negedge clk); rst_n = 1;
        check_alu(2, 32'hFFFFFFFF, 1, 0, 4'b0101);
        check_alu(2, 32'h7FFFFFFF, 1, 32'h80000000, 4'b1010);
        check_alu(2, 32'h80000000, 32'h80000000, 0, 4'b1101);
        check_alu(3, 0, 1, 32'hFFFFFFFF, 4'b0010);
        check_alu(3, 32'h80000000, 1, 32'h7FFFFFFF, 4'b1100);
        check_alu(9, 123, 123, 0, 4'b0101);
        check_alu(7, 1, 32, 1, 0);
        check_alu(8, 32'h80000000, 31, 1, 0);
        // Vetores aleatorios confrontam soma/subtracao e sinais de overflow.
        for (iteration = 0; iteration < 200; iteration = iteration + 1) begin
            random_a = $urandom; random_b = $urandom;
            wide_expected = {1'b0, random_a} + {1'b0, random_b};
            expected = wide_expected[31:0];
            expected_flags = {((random_a[31] == random_b[31]) && (expected[31] != random_a[31])),
                              wide_expected[32], expected[31], (expected == 0)};
            check_alu(2, random_a, random_b, expected, expected_flags);
            expected = random_a - random_b;
            expected_flags = {((random_a[31] != random_b[31]) && (expected[31] != random_a[31])),
                              (random_a >= random_b), expected[31], (expected == 0)};
            check_alu(3, random_a, random_b, expected, expected_flags);
            check_alu(9, random_a, random_b, expected, expected_flags);
        end
        for (index = 0; index < 16; index = index + 1) begin
            @(negedge clk); write_enable = 1; write_address = 4'(index); write_data = 32'(index + 100);
        end
        @(negedge clk); write_enable = 0;
        for (index = 0; index < 16; index = index + 1) begin
            read_a = 4'(index); read_b = 4'((index + 1) % 16); read_c = 4'((index + 2) % 16); #1;
            if (value_a !== ((index == 0) ? 0 : index + 100) ||
                value_b !== (((index + 1) % 16 == 0) ? 0 : (index + 1) % 16 + 100) ||
                value_c !== (((index + 2) % 16 == 0) ? 0 : (index + 2) % 16 + 100))
                $fatal(1, "Register file read/reset/r0 error");
        end
        @(negedge clk); restart = 1; write_enable = 1; write_address = 1; write_data = 32'hDEADBEEF;
        @(negedge clk); restart = 0; write_enable = 0;
        for (index = 0; index < 16; index = index + 1) begin
            read_a = 4'(index); #1;
            if (value_a !== 0) $fatal(1, "Restart failed to clear r%0d", index);
        end

        load_register(1, 16'hFFFF); load_register(2, 16'hA55A); load_register(3, 16'h00E7);
        check_decode(32'h40100000, 0, 32'h0000FFFF); // EMIT preserves all bits
        check_decode(32'h41120000, 0, {4'h5,11'd0,9'h1FF,8'h5A});
        check_decode(32'h42120F80, 0, {4'hA,5'd31,9'h1FF,8'h5A,6'd0});
        check_decode(32'h43120000, 0, {4'h7,11'd0,9'h1FF,8'h5A});
        check_decode(32'h44120000, 0, {4'h8,11'd0,9'h1FF,8'h5A});
        check_decode(32'h45123000, 0, {4'h9,8'hE7,3'd0,9'h1FF,8'h5A});
        check_decode(32'h46123000, 0, {4'h3,6'd0,6'h3F,3'd0,5'h1A,8'hE7});
        check_decode(32'h47120000, 0, {4'h1,4'd0,8'hFF,16'hA55A});
        check_decode(32'h48120F80, 0, {4'hB,5'd31,8'hFF,3'd2,12'd0});
        check_decode(32'h49120F80, 0, {4'hC,5'd31,2'd3,5'h1A,16'd0});
        check_decode(32'h2F000000, 1, 0);
        check_decode(32'h20110000, 1, 0);
        check_decode(32'h21100001, 1, 0);
        check_decode(32'h22123001, 1, 0);
        check_decode(32'h29123000, 1, 0);
        check_decode(32'h40110000, 1, 0);
        check_decode(32'h41121000, 1, 0);
        check_decode(32'h42121000, 1, 0);
        check_decode(32'h45123080, 1, 0);
        check_decode(32'h4A000000, 1, 0);
        check_decode(32'hE0000001, 1, 0);
        check_decode(32'hE1000001, 1, 0);
        check_decode(32'hE2000100, 1, 0);
        check_decode(32'hE5100001, 1, 0);
        check_decode(32'hE6000000, 1, 0);
        check_decode(32'hF0000001, 0, 32'hF0000001);
        check_decode(32'hF0000000, 0, 0);
        if (!halt_instruction || graphics_instruction) $fatal(1, "Exact HALT decoding failed");
        @(negedge clk); instruction = 32'h29011000; execute = 1; // CMP r1,r1
        @(negedge clk); instruction = 32'hE5000000; status_error = 1; // STATUS r0
        @(negedge clk); instruction = 32'hE5400000; // STATUS r4
        @(negedge clk); instruction = 32'h22412001; // invalid ADD must have no effects
        @(negedge clk); execute = 0;
        if (flags != 5 || datapath.u_registers.registers[0] != 0 ||
            datapath.u_registers.registers[4] != 32'h15)
            $fatal(1, "STATUS/invalid instruction modified flags or r0/register snapshot");
        $display("PASS tb_gpu_cpu_units: ALU flags/random vectors, 3 RF ports/r0/restart, all register graphics formats and reserved-field validation");
        $finish;
    end
endmodule
