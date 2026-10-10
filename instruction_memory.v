// Memoria de instrucoes com leitura sincrona e escrita opcional por byte.
// A carga inicial vem do HEX; reset da CPU nao modifica o programa carregado.
module instruction_memory #(
    parameter integer ADDRESS_WIDTH = 8,
    parameter integer PROGRAM_WORDS = 9,
    parameter PROGRAM_FILE = "programs/fetch_demo.hex",
    parameter integer WRITABLE = 0
) (
    input wire clk,
    input wire [ADDRESS_WIDTH-1:0] address,
    input wire write_enable,
    input wire [ADDRESS_WIDTH:0] write_address,
    input wire [31:0] write_data,
    input wire [3:0] write_byteenable,
    output reg [31:0] instruction
);
    localparam [31:0] HALT = 32'hF0000000;
    reg [31:0] memory [0:PROGRAM_WORDS-1];
    integer byte_index;

    initial begin
        $readmemh(PROGRAM_FILE, memory, 0, PROGRAM_WORDS-1);
    end

    always @(posedge clk) begin
        if ({{(32-ADDRESS_WIDTH){1'b0}}, address} < PROGRAM_WORDS)
            instruction <= memory[address];
        else
            instruction <= HALT;
        // O bit extra impede que o endereco 256 seja truncado para zero.
        if (WRITABLE != 0 && write_enable &&
            {{(31-ADDRESS_WIDTH){1'b0}}, write_address} < PROGRAM_WORDS) begin
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                if (write_byteenable[byte_index])
                    memory[write_address[ADDRESS_WIDTH-1:0]][byte_index*8 +: 8] <=
                        write_data[byte_index*8 +: 8];
        end
    end
endmodule
