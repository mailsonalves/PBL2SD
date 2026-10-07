module cmd_decoder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] cmd_data,
    input  wire        cmd_valid,
    output wire        cmd_ready,

    output reg         pal_we,
    output reg  [7:0]  pal_addr,
    output reg  [23:0] pal_data,
    output reg         tm_we,
    output reg  [5:0]  tm_x,
    output reg  [4:0]  tm_y,
    output reg  [7:0]  tm_tile_id,
    output reg  [8:0]  scroll_x,
    output reg  [7:0]  scroll_y,
    output reg         sat_we,
    output reg  [4:0]  sat_addr,
    output reg  [31:0] sat_data,
    output reg  [31:0] sat_write_mask,
    output reg  [8:0]  rast_x0, rast_x1, rast_x2,
    output reg  [7:0]  rast_y0, rast_y1, rast_y2,
    output reg  [7:0]  rast_color,
    output reg         rast_clear_screen,
    output reg         rast_start,
    input  wire        rast_busy,
    input  wire        sprite_busy,
    input  wire        buffer_busy,
    input  wire        buffer_double_buffered,
    output reg         sprite_meta_we,
    output reg  [4:0]  sprite_meta_addr,
    output reg  [1:0]  sprite_priority,
    output reg         sprite_palette_enable,
    output reg  [3:0]  sprite_palette_bank,
    output reg         buffer_config_valid,
    output reg         buffer_double_enable,
    output reg         buffer_swap_request,
    output reg         cmd_error
);

    wire [3:0] opcode = cmd_data[31:28];
    wire [3:0] sub_op = cmd_data[27:24];

    // Impede aceitar outro comando antes que o pulso registrado seja consumido.
    assign cmd_ready = !(rast_busy || sprite_busy || buffer_busy || rast_start ||
                         sat_we || sprite_meta_we || buffer_config_valid || buffer_swap_request);

    function valid_command;
        input [31:0] word;
        input double_mode;
        begin
            case (word[31:28])
                4'h0: valid_command = (word == 32'h0F000000);
                4'h1: valid_command = (word[27:24] == 0);
                4'h3: valid_command = (word[27:22] == 0 && word[15:13] == 0 &&
                                      word[21:16] < 40 && word[12:8] < 30);
                4'h5: valid_command = (word[27:17] == 0);
                4'h6: valid_command = (word[27:8] == 0);
                4'h7, 4'h8: valid_command = (word[27:17] == 0);
                4'h9: valid_command = (word[19:17] == 0);
                4'hA: valid_command = (word[5:0] == 0);
                4'hB: valid_command = (word[11:0] == 0);
                4'hC: valid_command = (word[15:0] == 0);
                4'hD: valid_command = ((word[27:24] == 0 && word[23:1] == 0) ||
                                      (word[27:24] == 1 && word[23:0] == 0 && double_mode));
                default: valid_command = 1'b0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pal_we            <= 1'b0;
            pal_addr          <= 8'd0;
            pal_data          <= 24'd0;
            tm_we             <= 1'b0;
            tm_x              <= 6'd0;
            tm_y              <= 5'd0;
            tm_tile_id        <= 8'd0;
            scroll_x          <= 9'd0;
            scroll_y          <= 8'd0;
            sat_we            <= 1'b0;
            sat_addr          <= 5'd0;
            sat_data          <= 32'd0;
            sat_write_mask    <= 32'd0;
            rast_x0           <= 9'd0; rast_y0 <= 8'd0;
            rast_x1           <= 9'd0; rast_y1 <= 8'd0;
            rast_x2           <= 9'd0; rast_y2 <= 8'd0;
            rast_color        <= 8'd0;
            rast_clear_screen <= 1'b0;
            rast_start        <= 1'b0;
            sprite_meta_we <= 1'b0;
            sprite_meta_addr <= 0;
            sprite_priority <= 0;
            sprite_palette_enable <= 0;
            sprite_palette_bank <= 0;
            buffer_config_valid <= 0;
            buffer_double_enable <= 0;
            buffer_swap_request <= 0;
            cmd_error <= 0;
        end else begin
            pal_we            <= 1'b0;
            tm_we             <= 1'b0;
            sat_we            <= 1'b0;
            rast_start        <= 1'b0;
            rast_clear_screen <= 1'b0;
            sprite_meta_we <= 0;
            buffer_config_valid <= 0;
            buffer_swap_request <= 0;
            cmd_error <= 0;

            if (cmd_valid && cmd_ready) begin
                if (!valid_command(cmd_data, buffer_double_buffered)) begin
                    cmd_error <= 1'b1;
                end else case (opcode)
                    4'h0: begin // Clear Screen
                        if (sub_op == 4'hF) begin
                            rast_clear_screen <= 1'b1;
                            rast_start        <= 1'b1;
                        end
                    end
                    4'h1: begin // SET_PALETTE
                        pal_we   <= 1'b1;
                        pal_addr <= cmd_data[23:16];
                        pal_data <= {cmd_data[15:11], 3'b000, cmd_data[10:5], 2'b00, cmd_data[4:0], 3'b000};
                    end
                    4'h3: begin // WRITE_TILEMAP
                        tm_we      <= 1'b1;
                        tm_x       <= cmd_data[21:16];
                        tm_y       <= cmd_data[12:8];
                        tm_tile_id <= cmd_data[7:0];
                    end
                    4'h5: begin // SET_SCROLL
                        scroll_x <= cmd_data[16:8];
                        scroll_y <= cmd_data[7:0];
                    end
                    4'h6: begin // UPDATE_BIRD_Y
                        sat_we   <= 1'b1;
                        sat_addr <= 5'd0;
                        // Compatibilidade com a demonstracao original por botoes.
                        sat_data <= {1'b1, 1'b0, 1'b0, 4'd0, 9'd152, cmd_data[7:0], 8'h01};
                        sat_write_mask <= 32'hFFFFFFFF;
                    end
                    4'h7: begin // DRAW_TRI_V1
                        rast_x0 <= cmd_data[16:8];
                        rast_y0 <= cmd_data[7:0];
                    end
                    4'h8: begin // DRAW_TRI_V2
                        rast_x1 <= cmd_data[16:8];
                        rast_y1 <= cmd_data[7:0];
                    end
                    4'h9: begin // DRAW_TRI_V3
                        rast_color <= cmd_data[27:20];
                        rast_x2    <= cmd_data[16:8];
                        rast_y2    <= cmd_data[7:0];
                        rast_start <= 1'b1;
                    end
                    4'hA: begin // SET_SPRITE_POS: altera apenas X e Y.
                        sat_we <= 1'b1;
                        sat_addr <= cmd_data[27:23];
                        sat_data <= {7'd0, cmd_data[22:14], cmd_data[13:6], 8'd0};
                        sat_write_mask <= 32'h01FFFF00;
                    end
                    4'hB: begin // SET_SPRITE_ATTR: imagem, enable e espelhamentos.
                        sat_we <= 1'b1;
                        sat_addr <= cmd_data[27:23];
                        sat_data <= {cmd_data[14], cmd_data[13], cmd_data[12],
                                     4'd0, 9'd0, 8'd0, cmd_data[22:15]};
                        sat_write_mask <= 32'hE00000FF;
                    end
                    4'hC: begin // SET_SPRITE_STYLE: prioridade e banco opcional.
                        sprite_meta_we <= 1'b1;
                        sprite_meta_addr <= cmd_data[27:23];
                        sprite_priority <= cmd_data[22:21];
                        sprite_palette_enable <= cmd_data[20];
                        sprite_palette_bank <= cmd_data[19:16];
                    end
                    4'hD: begin
                        if (sub_op == 0) begin
                            buffer_config_valid <= 1'b1;
                            buffer_double_enable <= cmd_data[0];
                        end else begin
                            buffer_swap_request <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
