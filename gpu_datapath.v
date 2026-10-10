// Banco, ULA, flags e conversao dos comandos por registrador para a interface
// grafica existente. execute e um pulso unico produzido pelo controlador.
module gpu_datapath (
    input wire clk,
    input wire rst_n,
    input wire restart,
    input wire execute,
    input wire [31:0] instruction,
    input wire status_error,
    output wire alu_instruction,
    output wire graphics_instruction,
    output wire flow_instruction,
    output wire halt_instruction,
    output wire invalid_instruction,
    output wire [3:0] subop,
    output reg [31:0] graphics_word,
    output reg [3:0] flags
);
    wire [3:0] destination, source_a, source_b, source_c;
    wire [31:0] value_a, value_b, value_c;
    wire [31:0] alu_operand_b = (subop == 4'h0) ? {16'd0, instruction[15:0]} :
                                (subop == 4'hA) ? {{16{instruction[15]}}, instruction[15:0]} : value_b;
    wire [31:0] alu_result;
    wire [3:0] alu_flags;
    wire status_write = flow_instruction && subop == 4'h5;
    wire register_write = execute && !invalid_instruction &&
                          ((alu_instruction && subop != 4'h9) || status_write);
    wire [31:0] register_data = status_write ? {27'd0, status_error, flags} : alu_result;

    gpu_instruction_decoder u_decoder (
        .instruction(instruction), .alu_instruction(alu_instruction),
        .graphics_instruction(graphics_instruction), .flow_instruction(flow_instruction),
        .halt_instruction(halt_instruction), .invalid_instruction(invalid_instruction),
        .subop(subop), .destination(destination), .source_a(source_a),
        .source_b(source_b), .source_c(source_c)
    );
    gpu_register_file u_registers (
        .clk(clk), .rst_n(rst_n), .restart(restart), .write_enable(register_write),
        .write_address(destination), .write_data(register_data),
        .read_address_a(source_a), .read_address_b(source_b), .read_address_c(source_c),
        .read_data_a(value_a), .read_data_b(value_b), .read_data_c(value_c)
    );
    gpu_alu u_alu (.operation(subop), .operand_a(value_a), .operand_b(alu_operand_b),
                   .result(alu_result), .flags(alu_flags));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) flags <= 4'd0;
        else if (restart) flags <= 4'd0;
        else if (execute && alu_instruction && !invalid_instruction) flags <= alu_flags;
    end

    always @* begin
        graphics_word = instruction;
        if (instruction[31:28] == 4'h4) begin
            case (subop)
                4'h0: graphics_word = value_a; // EMIT
                4'h1: graphics_word = {4'h5, 11'd0, value_a[8:0], value_b[7:0]};
                4'h2: graphics_word = {4'hA, instruction[11:7], value_a[8:0], value_b[7:0], 6'd0};
                4'h3: graphics_word = {4'h7, 11'd0, value_a[8:0], value_b[7:0]};
                4'h4: graphics_word = {4'h8, 11'd0, value_a[8:0], value_b[7:0]};
                4'h5: graphics_word = {4'h9, value_c[7:0], 3'd0, value_a[8:0], value_b[7:0]};
                4'h6: graphics_word = {4'h3, 6'd0, value_a[5:0], 3'd0, value_b[4:0], value_c[7:0]};
                4'h7: graphics_word = {4'h1, 4'd0, value_a[7:0], value_b[15:0]};
                4'h8: graphics_word = {4'hB, instruction[11:7], value_a[7:0], value_b[2:0], 12'd0};
                4'h9: graphics_word = {4'hC, instruction[11:7], value_a[1:0], value_b[4:0], 16'd0};
                default: graphics_word = 32'd0;
            endcase
        end
    end
endmodule
