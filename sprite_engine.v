// SAT: enable[31], flip_x[30], flip_y[29], x[24:16], y[15:8], tile[7:0].
// Cada sprite tem um cache 16x16 de 8 bits. Uma unica ROM de padroes abastece
// esses caches; nao sao necessarias 32 replicas da VRAM de 16 KiB.
module sprite_engine #(
    parameter PATTERN_FILE = "tiles.hex"
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [8:0]  pixel_x,
    input  wire [7:0]  pixel_y,
    input  wire        sat_we,
    input  wire [4:0]  sat_addr,
    input  wire [31:0] sat_data,
    input  wire [31:0] sat_write_mask,
    input  wire        meta_we,
    input  wire [4:0]  meta_addr,
    input  wire [1:0]  meta_priority,
    input  wire        meta_palette_enable,
    input  wire [3:0]  meta_palette_bank,
    // Endereco geometrico legado, mantido para depuracao. A cor usa sp_pixel.
    output reg  [13:0] sp_vram_addr,
    output reg  [7:0]  sp_pixel,
    output reg         busy
);

    // Constante em bytes: aceita nomes selecionados por parametros no Icarus.
    localparam [8*256-1:0] PATTERN_FILE_BYTES = PATTERN_FILE;
    reg [31:0] sat_ram [0:31];
    reg [1:0] priority_ram [0:31];
    reg [3:0] palette_bank_ram [0:31];
    reg palette_enable_ram [0:31];
    reg [31:0] cache_valid;

    reg [7:0] pattern_rom [0:16383];
    initial $readmemh(PATTERN_FILE_BYTES, pattern_rom);

    // Leitura sincrona da origem, seguida da escrita no cache selecionado.
    // O ultimo pixel precisa ser escrito antes de liberar busy.
    reg [4:0] load_id;
    reg [7:0] load_base;
    reg [8:0] load_index;
    reg load_return_valid;
    reg [7:0] load_return_index;
    reg [7:0] load_return_pixel;
    wire [7:0] load_tile = load_base + {6'd0, load_index[7], load_index[3]};
    wire [13:0] load_address = {load_tile, load_index[6:4], load_index[2:0]};
    wire load_write = rst_n && busy && load_return_valid;
    wire [31:0] new_attr = (sat_ram[sat_addr] & ~sat_write_mask) |
                           (sat_data & sat_write_mask);

    always @(posedge clk) begin
        if (rst_n && busy && load_index < 9'd256)
            load_return_pixel <= pattern_rom[load_address];
    end

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 32; k = k + 1) begin
                sat_ram[k] <= 32'd0;
                priority_ram[k] <= 2'd0;
                palette_bank_ram[k] <= 4'd0;
                palette_enable_ram[k] <= 1'b0;
            end
            sat_ram[0] <= {1'b1, 1'b0, 1'b0, 4'd0, 9'd150, 8'd100, 8'd1};
            cache_valid <= 32'd0;
            busy <= 1'b1;
            load_id <= 5'd0;
            load_base <= 8'd1;
            load_index <= 9'd0;
            load_return_valid <= 1'b0;
            load_return_index <= 8'd0;
        end else begin
            load_return_valid <= 1'b0;
            if (busy) begin
                if (load_index < 9'd256) begin
                    load_index <= load_index + 9'd1;
                    load_return_valid <= 1'b1;
                    load_return_index <= load_index[7:0];
                end
                if (load_return_valid && load_return_index == 8'd255) begin
                    cache_valid[load_id] <= 1'b1;
                    busy <= 1'b0;
                end
            end else if (sat_we) begin
                sat_ram[sat_addr] <= new_attr;
                if (new_attr[7:0] != sat_ram[sat_addr][7:0])
                    cache_valid[sat_addr] <= 1'b0;
                if (new_attr[31] && (!cache_valid[sat_addr] ||
                                    new_attr[7:0] != sat_ram[sat_addr][7:0])) begin
                    cache_valid[sat_addr] <= 1'b0;
                    load_id <= sat_addr;
                    load_base <= new_attr[7:0];
                    load_index <= 9'd0;
                    busy <= 1'b1;
                end
                // O comando legado completo tambem restaura seus atributos.
                if (&sat_write_mask) begin
                    priority_ram[sat_addr] <= 2'd0;
                    palette_bank_ram[sat_addr] <= 4'd0;
                    palette_enable_ram[sat_addr] <= 1'b0;
                end
            end
            if (meta_we) begin
                priority_ram[meta_addr] <= meta_priority;
                palette_bank_ram[meta_addr] <= meta_palette_bank;
                palette_enable_ram[meta_addr] <= meta_palette_enable;
            end
        end
    end

    wire [13:0] sprite_addrs [0:31];
    wire sprite_hit [0:31];
    wire [7:0] sprite_pixels [0:31];
    reg [31:0] hit_q;
    reg [1:0] priority_q [0:31];
    reg [3:0] palette_bank_q [0:31];
    reg [31:0] palette_enable_q;

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_sprites
            wire [31:0] attr = sat_ram[i];
            wire [8:0] sp_x = attr[24:16];
            wire [7:0] sp_y = attr[15:8];
            wire inside_x = (pixel_x >= sp_x) &&
                            ({1'b0, pixel_x} < {1'b0, sp_x} + 10'd16);
            wire inside_y = (pixel_y >= sp_y) &&
                            ({1'b0, pixel_y} < {1'b0, sp_y} + 9'd16);
            wire [3:0] rel_x = pixel_x[3:0] - sp_x[3:0];
            wire [3:0] rel_y = pixel_y[3:0] - sp_y[3:0];
            wire [3:0] eff_x = attr[30] ? (4'd15 - rel_x) : rel_x;
            wire [3:0] eff_y = attr[29] ? (4'd15 - rel_y) : rel_y;
            wire [7:0] tile = attr[7:0] + {6'd0, eff_y[3], eff_x[3]};
            assign sprite_addrs[i] = {tile, eff_y[2:0], eff_x[2:0]};
            assign sprite_hit[i] = attr[31] && inside_x && inside_y;

            // Sem reset ou limpeza da RAM: cache_valid impede pixels indefinidos
            // e permite que o Quartus infira memoria de bloco para os caches.
            reg [7:0] pixels [0:255];
            reg [7:0] pixel_q;
            always @(posedge clk) begin
                if (load_write && load_id == i)
                    pixels[load_return_index] <= load_return_pixel;
                pixel_q <= pixels[{eff_y, eff_x}];
            end
            assign sprite_pixels[i] = pixel_q;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    hit_q[i] <= 1'b0;
                    priority_q[i] <= 2'd0;
                    palette_bank_q[i] <= 4'd0;
                    palette_enable_q[i] <= 1'b0;
                end else begin
                    hit_q[i] <= sprite_hit[i] && cache_valid[i];
                    priority_q[i] <= priority_ram[i];
                    palette_bank_q[i] <= palette_bank_ram[i];
                    palette_enable_q[i] <= palette_enable_ram[i];
                end
            end
        end
    endgenerate

    integer j;
    reg found;
    reg [1:0] selected_priority;
    reg opaque;
    always @(*) begin
        sp_vram_addr = 14'd0;
        sp_pixel = 8'd0;
        found = 1'b0;
        selected_priority = 2'd0;
        opaque = 1'b0;
        // Mais prioridade vence; no empate, menor ID. A transparencia e testada
        // em cada sprite, antes da escolha, para revelar sprites que estao atras.
        for (j = 31; j >= 0; j = j - 1) begin
            if (sprite_hit[j]) sp_vram_addr = sprite_addrs[j];
            opaque = palette_enable_q[j] ? (sprite_pixels[j][3:0] != 4'd0) :
                                                   (sprite_pixels[j] != 8'd0);
            if (hit_q[j] && opaque && (!found || priority_q[j] >= selected_priority)) begin
                found = 1'b1;
                selected_priority = priority_q[j];
                sp_pixel = palette_enable_q[j] ?
                    {palette_bank_q[j], sprite_pixels[j][3:0]} : sprite_pixels[j];
            end
        end
    end
endmodule
