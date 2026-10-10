// ULA inteira de 32 bits. flags = {V, C, N, Z}; SUB/CMP usam C=no-borrow.
module gpu_alu (
    input wire [3:0] operation,
    input wire [31:0] operand_a,
    input wire [31:0] operand_b,
    output reg [31:0] result,
    output reg [3:0] flags
);
    reg [32:0] extended_result;
    always @* begin
        result = 32'd0;
        extended_result = 33'd0;
        flags = 4'd0;
        case (operation)
            4'h0: result = operand_b; // MOVI
            4'h1: result = operand_a; // MOV
            4'h2, 4'hA: begin // ADD/ADDI
                extended_result = {1'b0, operand_a} + {1'b0, operand_b};
                result = extended_result[31:0];
                flags[2] = extended_result[32];
                flags[3] = !(operand_a[31] ^ operand_b[31]) &&
                           (result[31] ^ operand_a[31]);
            end
            4'h3, 4'h9: begin // SUB/CMP
                extended_result = {1'b0, operand_a} + {1'b0, ~operand_b} + 33'd1;
                result = extended_result[31:0];
                flags[2] = extended_result[32];
                flags[3] = (operand_a[31] ^ operand_b[31]) &&
                           (result[31] ^ operand_a[31]);
            end
            4'h4: result = operand_a & operand_b;
            4'h5: result = operand_a | operand_b;
            4'h6: result = operand_a ^ operand_b;
            4'h7: result = operand_a << operand_b[4:0];
            4'h8: result = operand_a >> operand_b[4:0];
            default: result = 32'd0;
        endcase
        flags[0] = (result == 32'd0);
        flags[1] = result[31];
    end
endmodule
