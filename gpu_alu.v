// ULA da ISA programavel. Operation usa a subop do opcode 2.
// Flags: bit 0 Z, bit 1 N, bit 2 C, bit 3 V.
module gpu_alu (
    input wire [3:0] operation,
    input wire [31:0] lhs,
    input wire [31:0] rhs,
    output reg [31:0] result,
    output reg [3:0] flags
);
    reg [32:0] extended;
    reg carry;
    reg overflow;
    wire [4:0] shift_amount = rhs[4:0];

    always @* begin
        result = 32'd0;
        extended = 33'd0;
        carry = 1'b0;
        overflow = 1'b0;
        case (operation)
            4'h1, 4'hA: begin
                extended = {1'b0, lhs} + {1'b0, rhs};
                result = extended[31:0];
                carry = extended[32];
                overflow = !(lhs[31] ^ rhs[31]) && (result[31] ^ lhs[31]);
            end
            4'h2, 4'h8: begin
                result = lhs - rhs;
                // C=1 significa que a subtracao nao pediu emprestimo.
                carry = (lhs >= rhs);
                overflow = (lhs[31] ^ rhs[31]) && (result[31] ^ lhs[31]);
            end
            4'h3: result = lhs & rhs;
            4'h4, 4'hF: result = lhs | rhs;
            4'h5: result = lhs ^ rhs;
            4'h6: begin
                result = lhs << shift_amount;
                if (shift_amount != 0)
                    carry = lhs[32 - shift_amount];
            end
            4'h7: begin
                result = lhs >> shift_amount;
                if (shift_amount != 0)
                    carry = lhs[shift_amount - 1'b1];
            end
            default: result = 32'd0;
        endcase
        flags = {overflow, carry, result[31], (result == 32'd0)};
    end
endmodule
