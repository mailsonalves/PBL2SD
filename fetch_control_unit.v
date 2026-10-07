// fetch_control_unit.v - Unidade de Busca, PC, IR e Sincronismo VGA
module fetch_control_unit (
    input  wire        clk,
    input  wire        rst_n,
    
    // Status dos motores graficos e do video
    input  wire        rast_busy,     // Handshake: 1 enquanto rasterizador desenha/limpa
    input  wire        vsync,         // Sinal VGA_VS para deteccao de VBLANK
    
    // Interface de despacho para o cmd_decoder.v
    output reg  [31:0] cmd_data,      // Atua como o Registrador de Instrucao (IR)
    output reg         cmd_valid,
    input  wire        cmd_ready,
    
    // Diagnosticos
    output wire [7:0]  pc_out
);

    reg [7:0] pc;
    assign pc_out = pc;

    wire [31:0] rom_data;

    // Instancia da memoria interna de instrucoes
    instruction_memory #(.WORDS(256)) u_inst_rom (
        .clk     (clk),
        .addr    (pc),
        .data_out(rom_data)
    );

    // Detector de borda de VBLANK (borda de descida do VSYNC ativo-baixo)
    reg vsync_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) vsync_d <= 1'b1;
        else        vsync_d <= vsync;
    end
    wire vblank_start = (vsync_d && !vsync);

    // FSM do Ciclo de Busca / Decodificacao / Execucao
    localparam S_FETCH   = 3'd0;
    localparam S_LOAD_IR = 3'd1;
    localparam S_DISP    = 3'd2;
    localparam S_WAIT_OP = 3'd3;
    localparam S_VBLANK  = 3'd4;
    localparam S_HALT    = 3'd5;

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc        <= 8'd0;
            cmd_data  <= 32'd0;
            cmd_valid <= 1'b0;
            state     <= S_FETCH;
        end else begin
            cmd_valid <= 1'b0;

            case (state)
                // 1. Estabiliza leitura da ROM sincrona (1 ciclo de latencia)
                S_FETCH: begin
                    state <= S_LOAD_IR;
                end

                // 2. Trava a palavra de 32 bits no Registrador de Instrucao (IR)
                S_LOAD_IR: begin
                    cmd_data <= rom_data;
                    state    <= S_DISP;
                end

                // 3. Decodifica e despacha
                S_DISP: begin
                    case (cmd_data[31:28])
                        // Instrucao de Sincronizacao: WAIT_VBLANK (0xE)
                        4'hE: begin
                            state <= S_VBLANK;
                        end

                        // Instrucao de Controle de Fluxo: JUMP_OR_HALT (0xF)
                        4'hF: begin
                            if (cmd_data[27:24] == 4'hF) begin
                                state <= S_HALT; // HALT permanente
                            end else begin
                                pc    <= cmd_data[7:0]; // Salto para novo PC
                                state <= S_FETCH;
                            end
                        end

                        // Comandos Graficos normais para o cmd_decoder
                        default: begin
                            if (cmd_ready) begin
                                cmd_valid <= 1'b1;
                                
                                // Se for comando de ULA (CLEAR_SCREEN, DRAW_TRI_V3, DRAW_RECT_P2)
                                if (cmd_data[31:28] == 4'h0 || cmd_data[31:28] == 4'h9 || cmd_data[31:28] == 4'hD)
                                    state <= S_WAIT_OP;
                                else begin
                                    pc    <= pc + 8'd1;
                                    state <= S_FETCH;
                                end
                            end
                        end
                    endcase
                end

                // 4. Espera o rasterizador terminar de pintar/limpar o buffer (Handshake)
                S_WAIT_OP: begin
                    if (!rast_busy) begin
                        pc    <= pc + 8'd1;
                        state <= S_FETCH;
                    end
                end

                // 5. Espera a varredura VGA entrar na regiao invisivel
                S_VBLANK: begin
                    if (vblank_start) begin
                        pc    <= pc + 8'd1;
                        state <= S_FETCH;
                    end
                end

                // 6. Fim do programa
                S_HALT: begin
                    state <= S_HALT;
                end

                default: state <= S_FETCH;
            endcase
        end
    end

endmodule