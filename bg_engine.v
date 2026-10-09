module bg_engine #(
    parameter TILEMAP_FILE = "tilemap_data.hex"
) (
    input  wire        clk,
    input  wire [8:0]  pixel_x,     // 0 a 319
    input  wire [7:0]  pixel_y,     // 0 a 239
    input  wire [8:0]  scroll_x,    // Offset horizontal
    input  wire [7:0]  scroll_y,    // Offset vertical

    // Interface de escrita no buffer (Tilemap)
    input  wire        we,
    input  wire [5:0]  wr_x,
    input  wire [4:0]  wr_y,
    input  wire [7:0]  wr_tile_id,

    // Endereço de leitura para a VRAM de Padrões (Dual-Port no top_level)
    output wire [13:0] bg_vram_addr
);

    // Soma usando bits extras para evitar overflow antes de checar o limite
    wire [9:0] sum_x = {1'b0, pixel_x} + {1'b0, scroll_x};
    wire [8:0] sum_y = {1'b0, pixel_y} + {1'b0, scroll_y};

    // Subtração condicional (substitui o operador matemático de módulo %)
    // Mantém a rolagem restrita a 320x240 sem gastar blocos DSP
    // Para pixels visiveis, os campos completos de scroll podem produzir
    // somas de ate 830/494. Duas voltas precisam ser tratadas antes de
    // reduzir a largura; uma unica subtracao causava alias nas bordas.
    wire [9:0] wrapped_x = (sum_x >= 10'd640) ? sum_x - 10'd640 :
                           (sum_x >= 10'd320) ? sum_x - 10'd320 : sum_x;
    wire [8:0] wrapped_y = (sum_y >= 9'd480) ? sum_y - 9'd480 :
                           (sum_y >= 9'd240) ? sum_y - 9'd240 : sum_y;
    wire [8:0] eff_x = wrapped_x[8:0];
    wire [7:0] eff_y = wrapped_y[7:0];
    wire pixel_valid = (pixel_x < 9'd320) && (pixel_y < 8'd240);

    // Endereço do tile (divisão por 8 ignorando os 3 bits menos significativos)
    wire [5:0] tile_x = eff_x[8:3];
    wire [4:0] tile_y = eff_y[7:3];
    
    wire [7:0] current_tile_id;
    
    // Pipelining: Atrasamos o sub_x e sub_y em 1 ciclo para sincronizar 
    // com a latência de leitura da memória tilemap_ram.
    reg [2:0] sub_x_delay;
    reg [2:0] sub_y_delay;
    reg pixel_valid_delay;

    initial begin
        sub_x_delay = 3'd0;
        sub_y_delay = 3'd0;
        pixel_valid_delay = 1'b0;
    end

    always @(posedge clk) begin
        sub_x_delay <= eff_x[2:0];
        sub_y_delay <= eff_y[2:0];
        pixel_valid_delay <= pixel_valid;
    end

    // Buffer de Tilemap
    tilemap_ram #(.TILEMAP_FILE(TILEMAP_FILE)) u_map_buffer (
        .clk_wr    (clk),
        .we        (we),
        .wr_x      (wr_x),
        .wr_y      (wr_y),
        .wr_tile_id(wr_tile_id),
        
        .clk_rd    (clk),
        .rd_x      (tile_x),
        .rd_y      (tile_y),
        .rd_tile_id(current_tile_id)
    );

    // O endereço final (14 bits) aponta para a VRAM externa
    // Composto pela ID do Tile (8 bits) + Coordenada Y interna (3 bits) + Coordenada X interna (3 bits)
    assign bg_vram_addr = pixel_valid_delay ?
                          {current_tile_id, sub_y_delay, sub_x_delay} : 14'd0;

endmodule
