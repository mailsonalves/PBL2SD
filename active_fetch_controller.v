// Etapa 1: busca comandos existentes, conserva o IR e espera sua execucao.
// Ainda nao implementa banco de registradores, ULA ou desvios.
module active_fetch_controller #(
    parameter integer ADDRESS_WIDTH = 8,
    parameter integer PROGRAM_WORDS = 9,
    parameter PROGRAM_FILE = "programs/fetch_demo.hex"
) (
    input wire clk,
    input wire rst_n,
    input wire cmd_ready,
    input wire execution_busy,
    output wire [31:0] cmd_data,
    output wire cmd_valid,
    output wire halted,
    output reg [ADDRESS_WIDTH-1:0] pc,
    output reg [31:0] ir
);
    localparam FETCH = 3'd0;
    localparam LATCH = 3'd1;
    localparam ISSUE = 3'd2;
    localparam SETTLE = 3'd3;
    localparam WAIT_DONE = 3'd4;
    localparam HALTED = 3'd5;

    reg [2:0] state;
    wire [31:0] fetched_instruction;

    instruction_memory #(
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .PROGRAM_WORDS(PROGRAM_WORDS),
        .PROGRAM_FILE(PROGRAM_FILE)
    ) u_instruction_memory (
        .clk(clk),
        .address(pc),
        .instruction(fetched_instruction)
    );

    assign cmd_data = ir;
    assign cmd_valid = rst_n && (state == ISSUE) && (ir[31:28] != 4'hF);
    assign halted = (state == HALTED);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= FETCH;
            pc <= 0;
            ir <= 32'hF0000000;
        end else begin
            case (state)
                // A memoria recebe o endereco nesta borda.
                FETCH: state <= LATCH;
                // Captura o resultado da leitura sincrona anterior.
                LATCH: begin
                    ir <= fetched_instruction;
                    state <= ISSUE;
                end
                ISSUE: begin
                    if (ir[31:28] == 4'hF)
                        state <= HALTED;
                    else if (cmd_ready)
                        state <= SETTLE;
                end
                // O decoder registra start; busy so sobe na borda seguinte.
                SETTLE: state <= WAIT_DONE;
                WAIT_DONE: begin
                    if (cmd_ready && !execution_busy) begin
                        pc <= pc + 1'b1;
                        state <= FETCH;
                    end
                end
                HALTED: state <= HALTED;
                default: state <= FETCH;
            endcase
        end
    end
endmodule
