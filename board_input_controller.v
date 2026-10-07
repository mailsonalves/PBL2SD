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
    reg signed [11:0] bird_y_sub;   
    reg signed [7:0]  velocity_y;   
    reg [8:0]         bg_scroll_x;  
    reg [7:0]         shape_timer;  // Temporizador compartilhado para as formas

    localparam GRAVITY   = 8'sd3;    
    localparam JUMP_IMP  = -8'sd60;  
    localparam MAX_FALL  = 8'sd96;   
    localparam GROUND_Y  = 8'd190;   

    wire [7:0] current_bird_y = bird_y_sub[11:4];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bird_y_sub  <= {8'd100, 4'd0};
            velocity_y  <= 8'd0;
            bg_scroll_x <= 9'd0;
            shape_timer <= 8'd0;
        end else if (frame_tick) begin
            
            // Scroll do Fundo
            if (bg_scroll_x >= 9'd319) bg_scroll_x <= 9'd0;
            else bg_scroll_x <= bg_scroll_x + 9'd1;

            // Fisica do Pulo
            if (jump_request) velocity_y <= JUMP_IMP;
            else if (velocity_y < MAX_FALL) velocity_y <= velocity_y + GRAVITY;

            // Limites (Chao e Teto)
            if (current_bird_y >= GROUND_Y && velocity_y > 0) begin
                bird_y_sub <= {GROUND_Y, 4'd0};
                velocity_y <= 8'd0;
            end else if (bird_y_sub <= 12'd0 && velocity_y < 0) begin
                bird_y_sub <= 12'd0;
                velocity_y <= 8'd0;
            end else begin
                bird_y_sub <= bird_y_sub + {{4{velocity_y[7]}}, velocity_y};
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

    reg [3:0] state;
    
    reg draw_tri_pending;
    reg draw_rect_pending;
    reg clear_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            cmd_data          <= 32'd0;
            cmd_valid         <= 1'b0;
            draw_tri_pending  <= 1'b0;
            draw_rect_pending <= 1'b0;
            clear_pending     <= 1'b0;
        end else begin
            cmd_valid <= 1'b0;

            if (tri_pressed) draw_tri_pending <= 1'b1;
            if (rect_pressed) draw_rect_pending <= 1'b1;
            if (shape_timer == 8'd1 && frame_tick) clear_pending <= 1'b1;

            case (state)
                S_IDLE: begin
                    if (frame_tick) 
                        state <= S_SEND_SCR;
                    else if (draw_tri_pending) 
                        state <= S_SEND_P1;
                    else if (draw_rect_pending) 
                        state <= S_SEND_R1;
                    else if (clear_pending) 
                        state <= S_SEND_CLR;
                end
                
                S_SEND_SCR: begin
                    if (cmd_ready) begin
                        cmd_data  <= {4'h5, 11'd0, bg_scroll_x, 8'd0};
                        cmd_valid <= 1'b1;
                        state     <= S_SEND_SPR;
                    end
                end
                
                S_SEND_SPR: begin
                    if (cmd_ready) begin
                        cmd_data  <= {4'h6, 20'd0, current_bird_y};
                        cmd_valid <= 1'b1;
                        state     <= S_IDLE;
                    end
                end

                // --- Estados: Desenhando o Triangulo (KEY[2]) ---
                S_SEND_P1: begin
                    if (cmd_ready) begin
                        draw_tri_pending <= 1'b0; 
                        cmd_data  <= {4'h7, 8'h00, 3'b000, 9'd160, 8'd50}; // V0 Topo
                        cmd_valid <= 1'b1;
                        state     <= S_SEND_P2;
                    end
                end
                S_SEND_P2: begin
                    if (cmd_ready) begin
                        cmd_data  <= {4'h8, 8'h00, 3'b000, 9'd80, 8'd190}; // V1 Esq
                        cmd_valid <= 1'b1;
                        state     <= S_SEND_P3;
                    end
                end
                S_SEND_P3: begin
                    if (cmd_ready) begin
                        cmd_data  <= {4'h9, 8'hFF, 3'b000, 9'd240, 8'd190}; // V2 Dir, Cor 0xFF
                        cmd_valid <= 1'b1;
                        state     <= S_IDLE;
                    end
                end

                // --- Estados: Desenhando o Retangulo em 2 Triangulos (KEY[3]) ---
                // Triangulo Metade Esquerda
                S_SEND_R1: begin
                    if (cmd_ready) begin
                        draw_rect_pending <= 1'b0;
                        cmd_data  <= {4'h7, 8'h00, 3'b000, 9'd100, 8'd100}; // Topo-Esq
                        cmd_valid <= 1'b1;
                        state     <= S_SEND_R2;
                    end
                end
                S_SEND_R2: begin
                    if (cmd_ready) begin
                        cmd_data  <= {4'h8, 8'h00, 3'b000, 9'd100, 8'd150}; // Base-Esq
                        cmd_valid <= 1'b1;
                        state     <= S_SEND_R3;
                    end
                end
                S_SEND_R3: begin
                    if (cmd_ready) begin
                        cmd_data  <= {4'h9, 8'h04, 3'b000, 9'd220, 8'd100};
                        cmd_valid <= 1'b1;
                        state     <= S_SEND_R4;
                    end
                end
                // Triangulo Metade Direita
                S_SEND_R4: begin
                    if (cmd_ready) begin
                        cmd_data  <= {4'h7, 8'h00, 3'b000, 9'd220, 8'd100}; // Topo-Dir
                        cmd_valid <= 1'b1;
                        state     <= S_SEND_R5;
                    end
                end
                S_SEND_R5: begin
                    if (cmd_ready) begin
                        cmd_data  <= {4'h8, 8'h00, 3'b000, 9'd100, 8'd150}; // Base-Esq
                        cmd_valid <= 1'b1;
                        state     <= S_SEND_R6;
                    end
                end
                S_SEND_R6: begin
                    if (cmd_ready) begin
                        cmd_data  <= {4'h9, 8'h04, 3'b000, 9'd220, 8'd150}; 
                        cmd_valid <= 1'b1;
                        state     <= S_IDLE;
                    end
                end

                // --- Estado do Poligono (Limpando a Tela) ---
                S_SEND_CLR: begin
                    if (cmd_ready) begin
                        clear_pending <= 1'b0;
                        cmd_data  <= {4'h0, 4'hF, 24'd0}; 
                        cmd_valid <= 1'b1;
                        state     <= S_IDLE;
                    end
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
