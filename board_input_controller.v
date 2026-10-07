module board_input_controller (
    input  wire        clk,          // Clock 50 MHz
    input  wire        rst_n,
    input  wire [9:0]  SW,
    input  wire [3:1]  KEY,          // KEY[1]=Pulo, KEY[2]=Triangulo, KEY[3]=Retangulo
    input  wire        cmd_ready,
    output reg  [31:0] cmd_data,
    output reg         cmd_valid
);

    // =========================================================================
    // 1. Gerador de Tick (Frame de ~60 Hz)
    // =========================================================================
    reg [19:0] frame_cnt;
    wire frame_tick = (frame_cnt == 20'd833333);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_cnt <= 20'd0;
        else if (frame_tick) frame_cnt <= 20'd0;
        else frame_cnt <= frame_cnt + 20'd1;
    end

    // =========================================================================
    // 2. Detectores de Borda dos Botoes e "Memorias de Clique"
    // =========================================================================
    reg [2:0] key1_sync, key2_sync, key3_sync;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key1_sync <= 3'b111;
            key2_sync <= 3'b111;
            key3_sync <= 3'b111;
        end else begin
            key1_sync <= {key1_sync[1:0], KEY[1]};
            key2_sync <= {key2_sync[1:0], KEY[2]};
            key3_sync <= {key3_sync[1:0], KEY[3]};
        end
    end
    
    wire flap_pressed = (key1_sync[2] && !key1_sync[1]); 
    wire tri_pressed  = (key2_sync[2] && !key2_sync[1]); 
    wire rect_pressed = (key3_sync[2] && !key3_sync[1]); 

    reg jump_request, tri_request, rect_request;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            jump_request <= 1'b0;
            tri_request  <= 1'b0;
            rect_request <= 1'b0;
        end else begin
            if (flap_pressed) jump_request <= 1'b1;
            else if (frame_tick) jump_request <= 1'b0;

            if (tri_pressed) tri_request <= 1'b1;
            else if (frame_tick) tri_request <= 1'b0;
            
            if (rect_pressed) rect_request <= 1'b1;
            else if (frame_tick) rect_request <= 1'b0;
        end
    end

    // =========================================================================
    // 3. Fisica do Passaro e Rolagem
    // =========================================================================
    // 190 * 16 = 3040 exige 13 bits quando a posicao e signed.
    reg signed [12:0] bird_y_sub;
    reg signed [7:0]  velocity_y;   
    reg [8:0]         bg_scroll_x;  
    reg [7:0]         shape_timer;  // Temporizador compartilhado para as formas

    localparam signed [7:0] GRAVITY  = 8'sd3;
    localparam signed [7:0] JUMP_IMP = -8'sd60;
    localparam signed [7:0] MAX_FALL = 8'sd96;
    localparam signed [13:0] GROUND_SUB = 14'sd3040;

    wire [7:0] current_bird_y = bird_y_sub[11:4];
    wire signed [7:0] next_velocity = jump_request ? JUMP_IMP :
        ((velocity_y < MAX_FALL) ? velocity_y + GRAVITY : velocity_y);
    // Calcula antes de truncar e limita a proxima posicao, evitando que um
    // impulso atravesse o teto ou uma queda ultrapasse o chao por um quadro.
    wire signed [13:0] moved_bird_y_sub =
        $signed({bird_y_sub[12], bird_y_sub}) +
        $signed({{6{velocity_y[7]}}, velocity_y});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bird_y_sub  <= 13'sd1600;
            velocity_y  <= 8'd0;
            bg_scroll_x <= 9'd0;
            shape_timer <= 8'd0;
        end else if (frame_tick) begin
            
            // Scroll do Fundo
            if (bg_scroll_x >= 9'd319) bg_scroll_x <= 9'd0;
            else bg_scroll_x <= bg_scroll_x + 9'd1;

            // Fisica do Pulo
            velocity_y <= next_velocity;

            // Limites (Chao e Teto)
            if (moved_bird_y_sub >= GROUND_SUB) begin
                bird_y_sub <= 13'sd3040;
                // Um novo pulo no chao continua valido.
                if (next_velocity > 8'sd0) velocity_y <= 8'sd0;
            end else if (moved_bird_y_sub <= 14'sd0) begin
                bird_y_sub <= 13'sd0;
                if (next_velocity < 8'sd0) velocity_y <= 8'sd0;
            end else begin
                bird_y_sub <= moved_bird_y_sub[12:0];
            end

            // Temporizador para limpar os polígonos
            if (tri_request || rect_request) begin
                shape_timer <= 8'd120; // Aproximadamente 2 segundos
            end else if (shape_timer > 0) begin
                shape_timer <= shape_timer - 8'd1;
            end
        end
    end

    // =========================================================================
    // 4. FSM Emissora de Comandos
    // =========================================================================
    localparam S_IDLE     = 4'd0;
    localparam S_SEND_SCR = 4'd1;
    localparam S_SEND_SPR = 4'd2;
    localparam S_SEND_P1  = 4'd3;
    localparam S_SEND_P2  = 4'd4;
    localparam S_SEND_P3  = 4'd5;
    localparam S_SEND_R1  = 4'd6;
    localparam S_SEND_R2  = 4'd7;
    localparam S_SEND_R3  = 4'd8;
    localparam S_SEND_R4  = 4'd9;
    localparam S_SEND_R5  = 4'd10;
    localparam S_SEND_R6  = 4'd11;
    localparam S_SEND_CLR = 4'd12;
    localparam S_CAPTURE_FRAME = 4'd13;

    reg [3:0] state;
    reg [8:0] frame_scroll_x;
    reg [7:0] frame_bird_y;
    
    reg draw_tri_pending;
    reg draw_rect_pending;
    reg clear_pending;

    // O comando pertence ao estado atual. Avancar somente na aceitacao
    // garante que valid e data permanecam estaveis enquanto ready estiver baixo.
    // A captura separada usa a fisica atualizada pelo tick, mas nao deixa um
    // novo tick mudar scroll/posicao de um comando que ainda esta esperando.
    always @* begin
        cmd_valid = 1'b1;
        cmd_data = 32'd0;
        case (state)
            S_SEND_SCR: cmd_data = {4'h5, 11'd0, frame_scroll_x, 8'd0};
            S_SEND_SPR: cmd_data = {4'h6, 20'd0, frame_bird_y};
            S_SEND_P1:  cmd_data = {4'h7, 8'h00, 3'b000, 9'd160, 8'd50};
            S_SEND_P2:  cmd_data = {4'h8, 8'h00, 3'b000, 9'd80, 8'd190};
            S_SEND_P3:  cmd_data = {4'h9, 8'hFF, 3'b000, 9'd240, 8'd190};
            S_SEND_R1:  cmd_data = {4'h7, 8'h00, 3'b000, 9'd100, 8'd100};
            S_SEND_R2:  cmd_data = {4'h8, 8'h00, 3'b000, 9'd100, 8'd150};
            S_SEND_R3:  cmd_data = {4'h9, 8'h04, 3'b000, 9'd220, 8'd100};
            S_SEND_R4:  cmd_data = {4'h7, 8'h00, 3'b000, 9'd220, 8'd100};
            S_SEND_R5:  cmd_data = {4'h8, 8'h00, 3'b000, 9'd100, 8'd150};
            S_SEND_R6:  cmd_data = {4'h9, 8'h04, 3'b000, 9'd220, 8'd150};
            S_SEND_CLR: cmd_data = {4'h0, 4'hF, 24'd0};
            default: cmd_valid = 1'b0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            frame_scroll_x    <= 9'd0;
            frame_bird_y      <= 8'd100;
            draw_tri_pending  <= 1'b0;
            draw_rect_pending <= 1'b0;
            clear_pending     <= 1'b0;
        end else begin
            if (tri_pressed) draw_tri_pending <= 1'b1;
            if (rect_pressed) draw_rect_pending <= 1'b1;
            if (shape_timer == 8'd1 && frame_tick) clear_pending <= 1'b1;

            case (state)
                S_IDLE: begin
                    if (frame_tick) 
                        state <= S_CAPTURE_FRAME;
                    else if (draw_tri_pending) 
                        state <= S_SEND_P1;
                    else if (draw_rect_pending) 
                        state <= S_SEND_R1;
                    else if (clear_pending) 
                        state <= S_SEND_CLR;
                end

                S_CAPTURE_FRAME: begin
                    frame_scroll_x <= bg_scroll_x;
                    frame_bird_y <= current_bird_y;
                    state <= S_SEND_SCR;
                end
                
                S_SEND_SCR: begin
                    if (cmd_ready) begin
                        state     <= S_SEND_SPR;
                    end
                end
                
                S_SEND_SPR: begin
                    if (cmd_ready) begin
                        state     <= S_IDLE;
                    end
                end

                // --- Estados: Desenhando o Triangulo (KEY[2]) ---
                S_SEND_P1: begin
                    if (cmd_ready) begin
                        draw_tri_pending <= tri_pressed;
                        state     <= S_SEND_P2;
                    end
                end
                S_SEND_P2: begin
                    if (cmd_ready) begin
                        state     <= S_SEND_P3;
                    end
                end
                S_SEND_P3: begin
                    if (cmd_ready) begin
                        state     <= S_IDLE;
                    end
                end

                // --- Estados: Desenhando o Retangulo em 2 Triangulos (KEY[3]) ---
                // Triangulo Metade Esquerda
                S_SEND_R1: begin
                    if (cmd_ready) begin
                        draw_rect_pending <= rect_pressed;
                        state     <= S_SEND_R2;
                    end
                end
                S_SEND_R2: begin
                    if (cmd_ready) begin
                        state     <= S_SEND_R3;
                    end
                end
                S_SEND_R3: begin
                    if (cmd_ready) begin
                        state     <= S_SEND_R4;
                    end
                end
                // Triangulo Metade Direita
                S_SEND_R4: begin
                    if (cmd_ready) begin
                        state     <= S_SEND_R5;
                    end
                end
                S_SEND_R5: begin
                    if (cmd_ready) begin
                        state     <= S_SEND_R6;
                    end
                end
                S_SEND_R6: begin
                    if (cmd_ready) begin
                        state     <= S_IDLE;
                    end
                end

                // --- Estado do Poligono (Limpando a Tela) ---
                S_SEND_CLR: begin
                    if (cmd_ready) begin
                        clear_pending <= 1'b0;
                        state     <= S_IDLE;
                    end
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
