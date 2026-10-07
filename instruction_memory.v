// Memoria sincrona: a instrucao aparece apos a borda de subida do clock.
// Cada linha do arquivo contem uma palavra de 32 bits em hexadecimal.
module instruction_memory #(
    parameter integer ADDRESS_WIDTH = 8,
    parameter integer PROGRAM_WORDS = 9,
    parameter PROGRAM_FILE = "programs/fetch_demo.hex"
) (
    input wire clk,
    input wire [ADDRESS_WIDTH-1:0] address,
    output reg [31:0] instruction
);
    localparam [31:0] HALT = 32'hF0000000;
    reg [31:0] memory [0:PROGRAM_WORDS-1];

    initial begin
        $readmemh(PROGRAM_FILE, memory, 0, PROGRAM_WORDS-1);
    end

    always @(posedge clk) begin
        if (address < PROGRAM_WORDS)
            instruction <= memory[address];
        else
            instruction <= HALT;
    end
endmodule
