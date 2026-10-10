// CPU multiciclo: busca sincrona, execucao inteira e comandos graficos com
// handshake. A memoria e os motores graficos do PBL1 sao reutilizados.
module active_fetch_controller #(
    parameter integer ADDRESS_WIDTH = 8,
    parameter integer PROGRAM_WORDS = 9,
    parameter PROGRAM_FILE = "programs/fetch_demo.hex"
) (
    input wire clk,
    input wire rst_n,
    input wire cmd_ready,
    input wire execution_busy,
    input wire frame_boundary,
    input wire restart,
    input wire pause,
    input wire clear_error,
    input wire cmd_error,
    output wire [31:0] cmd_data,
    output wire cmd_valid,
    output wire halted,
    output wire busy,
    output reg done,
    output reg error,
    output wire waiting_frame,
    output wire [3:0] flags,
    output reg [ADDRESS_WIDTH-1:0] pc,
    output reg [31:0] ir
);
    localparam FETCH = 4'd0;
    localparam LATCH = 4'd1;
    localparam ISSUE = 4'd2;
    localparam SETTLE = 4'd3;
    localparam WAIT_DONE = 4'd4;
    localparam HALTED = 4'd5;
    localparam WAIT_FRAME = 4'd6;
    localparam RESTART_SETTLE = 4'd7;
    localparam RESTART_DRAIN = 4'd8;

    reg [3:0] state;
    wire [31:0] fetched_instruction;
    wire alu_instruction, graphics_instruction, flow_instruction;
    wire halt_instruction, invalid_instruction;
    wire [3:0] subop;
    wire [31:0] graphics_word;
    wire execute = rst_n && state == ISSUE && !pause && !restart && !invalid_instruction;

    gpu_datapath datapath (
        .clk(clk), .rst_n(rst_n), .restart(restart), .execute(execute),
        .instruction(ir), .status_error(error), .alu_instruction(alu_instruction),
        .graphics_instruction(graphics_instruction), .flow_instruction(flow_instruction),
        .halt_instruction(halt_instruction), .invalid_instruction(invalid_instruction),
        .subop(subop), .graphics_word(graphics_word), .flags(flags)
    );

    instruction_memory #(
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .PROGRAM_WORDS(PROGRAM_WORDS),
        .PROGRAM_FILE(PROGRAM_FILE)
    ) u_instruction_memory (
        .clk(clk),
        .address(pc),
        .instruction(fetched_instruction)
    );

    assign cmd_data = graphics_word;
    assign cmd_valid = rst_n && state == ISSUE && !pause && !restart &&
                       graphics_instruction && !invalid_instruction;
    assign halted = (state == HALTED);
    assign waiting_frame = (state == WAIT_FRAME);
    assign busy = (!halted && !pause) || state == SETTLE || state == WAIT_DONE ||
                  state == WAIT_FRAME || state == RESTART_SETTLE || state == RESTART_DRAIN;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= FETCH;
            pc <= 0;
            ir <= 32'hF0000000;
            done <= 1'b0;
            error <= 1'b0;
        end else begin
            done <= 1'b0;
            if (clear_error) error <= 1'b0;
            if (cmd_error && state != RESTART_SETTLE && state != RESTART_DRAIN)
                error <= 1'b1;
            if (restart) begin
                pc <= 0;
                ir <= 32'hF0000000;
                error <= 1'b0;
                // Um pulso registrado do decoder pode ainda nao ter elevado busy.
                state <= RESTART_SETTLE;
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
                        if (!pause) begin
                            if (invalid_instruction) begin
                                error <= 1'b1;
                                pc <= pc + 1'b1;
                                done <= 1'b1;
                                state <= FETCH;
                            end else if (halt_instruction) begin
                                state <= HALTED;
                                done <= 1'b1;
                            end else if (alu_instruction) begin
                                pc <= pc + 1'b1;
                                done <= 1'b1;
                                state <= FETCH;
                            end else if (flow_instruction) begin
                                if (subop == 4'h1) begin
                                    state <= WAIT_FRAME;
                                end else begin
                                    if (subop == 4'h2 || (subop == 4'h3 && flags[0]) ||
                                        (subop == 4'h4 && !flags[0])) pc <= ir[7:0];
                                    else pc <= pc + 1'b1;
                                    done <= 1'b1;
                                    state <= FETCH;
                                end
                            end else if (cmd_ready)
                                state <= SETTLE;
                        end
                    end
                    // O decoder registra start; busy so sobe na borda seguinte.
                    SETTLE: state <= WAIT_DONE;
                    WAIT_DONE: begin
                        if (cmd_ready && !execution_busy) begin
                            pc <= pc + 1'b1;
                            done <= 1'b1;
                            state <= FETCH;
                        end
                    end
                    HALTED: state <= HALTED;
                    WAIT_FRAME: begin
                        // Evento coincidente com ISSUE nao satisfaz WAIT_FRAME.
                        if (frame_boundary) begin
                            pc <= pc + 1'b1;
                            done <= 1'b1;
                            state <= FETCH;
                        end
                    end
                    RESTART_SETTLE: state <= RESTART_DRAIN;
                    RESTART_DRAIN: if (cmd_ready && !execution_busy) state <= FETCH;
                    default: state <= FETCH;
                endcase
            end
        end
    end
endmodule
