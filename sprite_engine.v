module sprite_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [8:0]  pixel_x,
    input  wire [7:0]  pixel_y,
    input  wire        sat_we,
    input  wire [4:0]  sat_addr,
    input  wire [31:0] sat_data,
    input  wire [31:0] sat_write_mask,
    
    output reg  [13:0] sp_vram_addr // Endereço para a VRAM
);

    reg [31:0] sat_ram [0:31];
    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 32; k = k + 1) sat_ram[k] <= 32'd0;
            // Inicia o Lulinha (Tile ID 1) no centro da tela
            sat_ram[0] <= {1'b1, 1'b0, 1'b0, 4'd0, 9'd150, 8'd100, 8'h01};
        end else if (sat_we) begin
            // Bits com mascara 1 sao atualizados; os demais sao preservados.
            // Posicao e atributos podem ser enviados em comandos separados.
            sat_ram[sat_addr] <= (sat_ram[sat_addr] & ~sat_write_mask) |
                                 (sat_data & sat_write_mask);
        end
    end

    wire [13:0] sprite_addrs [0:31];
    wire        sprite_hit [0:31];

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_sprites
            wire [31:0] attr = sat_ram[i];
            wire enable      = attr[31];
            wire flip_x      = attr[30];
            wire flip_y      = attr[29];
            wire [8:0] sp_x  = attr[24:16];
            wire [7:0] sp_y  = attr[15:8];
            wire [7:0] base_id = attr[7:0];

            // Um bit extra evita que X+16 ou Y+16 volte a zero por overflow.
            wire inside_x = (pixel_x >= sp_x) &&
                            ({1'b0, pixel_x} < {1'b0, sp_x} + 10'd16);
            wire inside_y = (pixel_y >= sp_y) &&
                            ({1'b0, pixel_y} < {1'b0, sp_y} + 9'd16);
            wire hit      = enable && inside_x && inside_y;

            wire [3:0] rel_x = pixel_x[3:0] - sp_x[3:0];
            wire [3:0] rel_y = pixel_y[3:0] - sp_y[3:0];

            wire [3:0] eff_x = flip_x ? (4'd15 - rel_x) : rel_x;
            wire [3:0] eff_y = flip_y ? (4'd15 - rel_y) : rel_y;

            wire [1:0] quadrant = {eff_y[3], eff_x[3]};
            wire [7:0] tile_offset = {6'd0, quadrant};
            wire [7:0] current_tile = base_id + tile_offset;

            assign sprite_addrs[i] = {current_tile, eff_y[2:0], eff_x[2:0]};
            assign sprite_hit[i]   = hit;
        end
    endgenerate

    integer j;
    always @(*) begin
        sp_vram_addr = 14'd0; // Tile 0 (transparente) se nao atingir nada
        // A regra de prioridade define que o ID menor sobrepoe o maior[cite: 1]
        for (j = 31; j >= 0; j = j - 1) begin
            if (sprite_hit[j]) sp_vram_addr = sprite_addrs[j];
        end
    end
endmodule
