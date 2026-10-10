// CPU multiciclo: busca sincrona, execucao inteira e comandos graficos com
// handshake. A memoria e os motores graficos do PBL1 sao reutilizados.
module active_fetch_controller #(
    parameter integer ADDRESS_WIDTH = 8,
    parameter integer PROGRAM_WORDS = 9,
    parameter PROGRAM_FILE = "programs/fetch_demo.hex",
    parameter integer ENABLE_PROGRAM_UPLOAD = 0
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
    input wire load_mode,
    input wire [8:0] program_length,
    input wire [8:0] program_address,
    input wire program_write,
    input wire [31:0] program_writedata,
    input wire [3:0] program_byteenable,
    output wire [31:0] program_readdata,
    output wire program_ready,
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
    localparam FALLTHROUGH_HALT = 4'd9;
    localparam UPLOAD_ENABLED = (ENABLE_PROGRAM_UPLOAD != 0);

    reg [3:0] state;
    wire [31:0] fetched_instruction;
    wire alu_instruction, graphics_instruction, flow_instruction;
    wire halt_instruction, invalid_instruction;
    wire [3:0] subop;
    wire [31:0] graphics_word;
    wire [ADDRESS_WIDTH-1:0] memory_address = (UPLOAD_ENABLED && load_mode) ?
                                                        program_address[ADDRESS_WIDTH-1:0] : pc;
    wire end_of_address_space = UPLOAD_ENABLED && (&pc);
    wire branch_taken = subop == 4'h2 || (subop == 4'h3 && flags[0]) ||
                        (subop == 4'h4 && !flags[0]);
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
        .PROGRAM_FILE(PROGRAM_FILE),
        .WRITABLE(ENABLE_PROGRAM_UPLOAD)
    ) u_instruction_memory (
        .clk(clk),
        .address(memory_address),
        .write_enable(program_write && program_ready && {23'd0, program_address} < PROGRAM_WORDS),
        .write_address(program_address),
        .write_data(program_writedata),
        .write_byteenable(program_byteenable),
        .instruction(fetched_instruction)
    );

    assign cmd_data = graphics_word;
    assign cmd_valid = rst_n && state == ISSUE && !pause && !restart &&
                       graphics_instruction && !invalid_instruction;
    // START/restart ja invalida o HALT anterior antes de a FSM consumir o pulso.
    assign halted = (state == HALTED) && !restart;
    assign program_ready = UPLOAD_ENABLED && rst_n && load_mode && pause && !restart &&
                           !execution_busy && cmd_ready && (state == ISSUE || state == HALTED);
    assign program_readdata = (UPLOAD_ENABLED && {23'd0, program_address} < PROGRAM_WORDS) ?
                             fetched_instruction : 32'hF0000000;
    assign waiting_frame = (state == WAIT_FRAME);
    assign busy = restart || (!halted && !pause) || state == SETTLE || state == WAIT_DONE ||
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
                        if (UPLOAD_ENABLED && {1'b0, pc} >= program_length)
                            ir <= 32'hF0000000;
                        else ir <= fetched_instruction;
                        state <= ISSUE;
                    end
                    ISSUE: begin
                        if (!pause) begin
                            if (invalid_instruction) begin
                                error <= 1'b1;
                                if (!end_of_address_space) pc <= pc + 1'b1;
                                done <= 1'b1;
                                state <= end_of_address_space ? FALLTHROUGH_HALT : FETCH;
                            end else if (halt_instruction) begin
                                state <= HALTED;
                                done <= 1'b1;
                            end else if (alu_instruction) begin
                                if (!end_of_address_space) pc <= pc + 1'b1;
                                done <= 1'b1;
                                state <= end_of_address_space ? FALLTHROUGH_HALT : FETCH;
                            end else if (flow_instruction) begin
                                if (subop == 4'h1) begin
                                    state <= WAIT_FRAME;
                                end else begin
                                    if (branch_taken) pc <= ir[7:0];
                                    else if (!end_of_address_space) pc <= pc + 1'b1;
                                    done <= 1'b1;
                                    state <= (!branch_taken && end_of_address_space) ? FALLTHROUGH_HALT : FETCH;
                                end
                            end else if (cmd_ready)
                                state <= SETTLE;
                        end
                    end
                    // O decoder registra start; busy so sobe na borda seguinte.
                    SETTLE: state <= WAIT_DONE;
                    WAIT_DONE: begin
                        if (cmd_ready && !execution_busy) begin
                            if (!end_of_address_space) pc <= pc + 1'b1;
                            done <= 1'b1;
                            state <= end_of_address_space ? FALLTHROUGH_HALT : FETCH;
                        end
                    end
                    HALTED: state <= HALTED;
                    WAIT_FRAME: begin
                        // Evento coincidente com ISSUE nao satisfaz WAIT_FRAME.
                        if (frame_boundary) begin
                            if (!end_of_address_space) pc <= pc + 1'b1;
                            done <= 1'b1;
                            state <= end_of_address_space ? FALLTHROUGH_HALT : FETCH;
                        end
                    end
                    RESTART_SETTLE: state <= RESTART_DRAIN;
                    RESTART_DRAIN: if (cmd_ready && !execution_busy) state <= FETCH;
                    FALLTHROUGH_HALT: begin
                        ir <= 32'hF0000000;
                        state <= ISSUE;
                    end
                    default: state <= FETCH;
                endcase
            end
        end
    end
endmodule
