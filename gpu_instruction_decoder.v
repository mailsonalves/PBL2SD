// Valida os campos reservados da ISA nova. Comandos graficos imediatos
// continuam a ser validados pelo cmd_decoder, inclusive palavras F invalidas.
module gpu_instruction_decoder (
    input wire [31:0] instruction,
    output reg alu_instruction,
    output reg graphics_instruction,
    output reg flow_instruction,
    output reg halt_instruction,
    output reg invalid_instruction,
    output wire [3:0] subop,
    output wire [3:0] destination,
    output wire [3:0] source_a,
    output wire [3:0] source_b,
    output wire [3:0] source_c
);
    assign subop = instruction[27:24];
    assign destination = instruction[23:20];
    assign source_a = (instruction[31:28] == 4'h4) ?
                      instruction[23:20] : instruction[19:16];
    assign source_b = (instruction[31:28] == 4'h4) ?
                      instruction[19:16] : instruction[15:12];
    assign source_c = instruction[15:12];
    always @* begin
        alu_instruction = 1'b0;
        graphics_instruction = 1'b0;
        flow_instruction = 1'b0;
        halt_instruction = (instruction == 32'hF0000000);
        invalid_instruction = 1'b0;
        case (instruction[31:28])
            4'h2: begin
                alu_instruction = 1'b1;
                case (subop)
                    4'h0: invalid_instruction = (instruction[19:16] != 0);
                    4'h1: invalid_instruction = (instruction[15:0] != 0);
                    4'h2, 4'h3, 4'h4, 4'h5, 4'h6, 4'h7, 4'h8:
                        invalid_instruction = (instruction[11:0] != 0);
                    4'h9: invalid_instruction = (destination != 0 || instruction[11:0] != 0);
                    4'hA: invalid_instruction = 1'b0;
                    default: invalid_instruction = 1'b1;
                endcase
            end
            4'h4: begin
                graphics_instruction = 1'b1;
                invalid_instruction = (instruction[6:0] != 0);
                case (subop)
                    4'h0: invalid_instruction = invalid_instruction || (instruction[19:7] != 0);
                    4'h1, 4'h3, 4'h4, 4'h7:
                        invalid_instruction = invalid_instruction || (instruction[15:7] != 0);
                    4'h2, 4'h8, 4'h9:
                        invalid_instruction = invalid_instruction || (instruction[15:12] != 0);
                    4'h5, 4'h6:
                        invalid_instruction = invalid_instruction || (instruction[11:7] != 0);
                    default: invalid_instruction = 1'b1;
                endcase
            end
            4'hE: begin
                flow_instruction = 1'b1;
                case (subop)
                    4'h0, 4'h1: invalid_instruction = (instruction[23:0] != 0);
                    4'h2, 4'h3, 4'h4: invalid_instruction = (instruction[23:8] != 0);
                    4'h5: invalid_instruction = (instruction[19:0] != 0);
                    default: invalid_instruction = 1'b1;
                endcase
            end
            default: graphics_instruction = !halt_instruction;
        endcase
    end
endmodule
