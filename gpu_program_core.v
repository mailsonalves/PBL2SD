// Busca ativa, banco de registradores, ULA e controle da ISA da etapa 4.
// Comandos graficos sao mantidos estaveis ate ready e so se aposentam
// depois de SETTLE e do termino dos motores. VGA nunca depende da CPU.
module gpu_program_core #(
    parameter integer ADDRESS_WIDTH = 12,
    parameter integer PROGRAM_WORDS = 9,
    parameter PROGRAM_FILE = "programs/fetch_demo.hex"
) (
    input wire clk,
    input wire rst_n,
    input wire cmd_ready,
    input wire execution_busy,
    input wire cmd_error,
    input wire frame_boundary,
    input wire [9:0] sw_state,
    input wire [2:0] key_state,
    input wire buffer_initialized,
    input wire buffer_front,
    input wire buffer_double_buffered,
    output wire [31:0] cmd_data,
    output wire cmd_valid,
    output wire halted,
    output reg [ADDRESS_WIDTH-1:0] pc,
    output reg [31:0] ir,
    output wire [31:0] status,
    output reg [31:0] user_output,
    output reg retired
);
    localparam FETCH = 4'd0;
    localparam LATCH = 4'd1;
    localparam EXEC = 4'd2;
    localparam ISSUE = 4'd3;
    localparam SETTLE = 4'd4;
    localparam WAIT_DONE = 4'd5;
    localparam WAIT_FRAME = 4'd6;
    localparam HALTED = 4'd7;

    reg [3:0] state;
    reg [31:0] pending_command;
    wire [31:0] fetched_instruction;
    wire [3:0] opcode = ir[31:28];
    wire [3:0] subop = ir[27:24];
    wire [3:0] rd = ir[23:20];
    wire [3:0] rs = ir[19:16];
    wire [3:0] rt = ir[15:12];
    reg [3:0] read_addr_a;
    wire [31:0] operand_a;
    wire [31:0] operand_b;
    reg [31:0] alu_rhs;
    wire [31:0] alu_result;
    wire [3:0] alu_flags;
    wire [3:0] flags;
    wire [31:0] frame_counter;

    reg instruction_valid;
    reg rf_we;
    reg [31:0] rf_write_data;
    reg flags_we;
    reg error_clear;
    wire instruction_error = (state == EXEC) && !instruction_valid;

    // Comparar os 16 bits antes de cortar evita alias de endereco de salto.
    wire jump_target_valid = ({16'd0, ir[15:0]} < PROGRAM_WORDS) &&
                             (({16'd0, ir[15:0]} >> ADDRESS_WIDTH) == 0);
    reg take_branch;

    instruction_memory #(
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .PROGRAM_WORDS(PROGRAM_WORDS),
        .PROGRAM_FILE(PROGRAM_FILE)
    ) u_instruction_memory (
        .clk(clk), .address(pc), .instruction(fetched_instruction)
    );

    gpu_register_file u_register_file (
        .clk(clk), .rst_n(rst_n),
        .we(rf_we), .write_addr(rd), .write_data(rf_write_data),
        .read_addr_a(read_addr_a), .read_addr_b(rt),
        .read_data_a(operand_a), .read_data_b(operand_b)
    );

    gpu_alu u_alu (
        .operation(subop), .lhs(operand_a), .rhs(alu_rhs),
        .result(alu_result), .flags(alu_flags)
    );

    gpu_frame_control u_frame_control (
        .clk(clk), .rst_n(rst_n), .frame_boundary(frame_boundary),
        .frame_counter(frame_counter)
    );

    gpu_status_register u_status_register (
        .clk(clk), .rst_n(rst_n), .flags_we(flags_we), .flags_in(alu_flags),
        .error_set(cmd_error || instruction_error), .error_clear(error_clear),
        .halted(halted), .graphics_busy(execution_busy),
        .waiting_frame(state == WAIT_FRAME),
        .buffer_initialized(buffer_initialized), .buffer_front(buffer_front),
        .buffer_double_buffered(buffer_double_buffered), .cmd_ready(cmd_ready),
        .flags(flags), .error(), .status(status)
    );

    assign cmd_data = pending_command;
    assign cmd_valid = rst_n && (state == ISSUE);
    assign halted = (state == HALTED);

    // A mesma leitura serve a aritmetica, ao comando indireto e a OUT.
    always @* begin
        read_addr_a = rs;
        if (opcode == 4'h4)
            read_addr_a = ir[27:24];
        else if (opcode == 4'hE && subop == 4'h6)
            read_addr_a = ir[23:20];
        alu_rhs = operand_b;
        if (subop == 4'hA)
            alu_rhs = {{16{ir[15]}}, ir[15:0]};
        else if (subop == 4'hF)
            alu_rhs = {16'd0, ir[15:0]};
    end

    // Valida primeiro os campos reservados. Instrucoes rejeitadas nunca
    // escrevem registradores, flags, saida ou o canal de comandos.
    always @* begin
        instruction_valid = 1'b1;
        case (opcode)
            4'h2: begin
                case (subop)
                    4'h0, 4'hA, 4'hF: instruction_valid = 1'b1;
                    4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6, 4'h7:
                        instruction_valid = (ir[11:0] == 0);
                    4'h8: instruction_valid = (rd == 0) && (ir[11:0] == 0);
                    4'h9: instruction_valid = (rt == 0) && (ir[11:0] == 0);
                    4'hB: instruction_valid = (rs <= 2) && (ir[15:0] == 0);
                    4'hC: instruction_valid = (ir[19:0] == 0);
                    4'hD: instruction_valid = (ir[23:0] == 0);
                    4'hE: instruction_valid = (ir[19:16] == 0);
                    default: instruction_valid = 1'b0;
                endcase
            end
            4'h4: instruction_valid = (ir[23:0] == 0);
            4'hE: begin
                case (subop)
                    4'h0: instruction_valid = (ir[23:0] == 0);
                    4'h1, 4'h2, 4'h3, 4'h4, 4'h5:
                        instruction_valid = (ir[23:16] == 0) && jump_target_valid;
                    4'h6: instruction_valid = (ir[19:0] == 0);
                    default: instruction_valid = 1'b0;
                endcase
            end
            4'hF: instruction_valid = (ir == 32'hF0000000);
            // O decoder grafico valida os payloads dos comandos diretos.
            default: instruction_valid = 1'b1;
        endcase

        rf_we = 1'b0;
        rf_write_data = alu_result;
        flags_we = 1'b0;
        error_clear = 1'b0;
        if (rst_n && state == EXEC && instruction_valid && opcode == 4'h2) begin
            case (subop)
                4'h0: begin rf_we = 1'b1; rf_write_data = {12'd0, ir[19:0]}; end
                4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6, 4'h7, 4'hA, 4'hF:
                    begin rf_we = 1'b1; flags_we = 1'b1; end
                4'h8: flags_we = 1'b1;
                4'h9: begin rf_we = 1'b1; rf_write_data = operand_a; end
                4'hB: begin
                    rf_we = 1'b1;
                    case (rs)
                        4'd0: rf_write_data = {22'd0, sw_state};
                        4'd1: rf_write_data = {29'd0, key_state};
                        4'd2: rf_write_data = frame_counter;
                        default: rf_write_data = 32'd0;
                    endcase
                end
                4'hC: begin rf_we = 1'b1; rf_write_data = status; end
                4'hD: error_clear = 1'b1;
                4'hE: begin rf_we = 1'b1; rf_write_data = {ir[15:0], 16'd0}; end
                default: begin end
            endcase
        end

        take_branch = 1'b0;
        case (subop)
            4'h1: take_branch = 1'b1;
            4'h2: take_branch = flags[0];
            4'h3: take_branch = !flags[0];
            4'h4: take_branch = flags[1] ^ flags[3];
            4'h5: take_branch = !(flags[1] ^ flags[3]);
            default: take_branch = 1'b0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= FETCH;
            pc <= 0;
            ir <= 32'hF0000000;
            pending_command <= 32'd0;
            user_output <= 32'd0;
            retired <= 1'b0;
        end else begin
            retired <= 1'b0;
            case (state)
                FETCH: state <= LATCH;
                LATCH: begin
                    ir <= fetched_instruction;
                    state <= EXEC;
                end
                EXEC: begin
                    if (!instruction_valid) begin
                        pc <= pc + 1'b1;
                        retired <= 1'b1;
                        state <= FETCH;
                    end else begin
                        case (opcode)
                            4'h2: begin
                                pc <= pc + 1'b1;
                                retired <= 1'b1;
                                state <= FETCH;
                            end
                            4'h4: begin
                                pending_command <= operand_a;
                                state <= ISSUE;
                            end
                            4'hE: begin
                                if (subop == 4'h0) begin
                                    // Uma borda coincidente com EXEC nao satisfaz
                                    // a espera: apenas a proxima, ja em WAIT_FRAME.
                                    state <= WAIT_FRAME;
                                end else begin
                                    if (subop == 4'h6) begin
                                        user_output <= operand_a;
                                        pc <= pc + 1'b1;
                                    end else if (take_branch)
                                        pc <= ir[ADDRESS_WIDTH-1:0];
                                    else
                                        pc <= pc + 1'b1;
                                    retired <= 1'b1;
                                    state <= FETCH;
                                end
                            end
                            4'hF: begin
                                retired <= 1'b1;
                                state <= HALTED;
                            end
                            default: begin
                                pending_command <= ir;
                                state <= ISSUE;
                            end
                        endcase
                    end
                end
                ISSUE: if (cmd_ready) state <= SETTLE;
                SETTLE: state <= WAIT_DONE;
                WAIT_DONE: begin
                    if (cmd_ready && !execution_busy) begin
                        pc <= pc + 1'b1;
                        retired <= 1'b1;
                        state <= FETCH;
                    end
                end
                WAIT_FRAME: begin
                    if (frame_boundary) begin
                        pc <= pc + 1'b1;
                        retired <= 1'b1;
                        state <= FETCH;
                    end
                end
                HALTED: state <= HALTED;
                default: state <= FETCH;
            endcase
        end
    end
endmodule
