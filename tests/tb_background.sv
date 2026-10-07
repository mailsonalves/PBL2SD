`timescale 1ns/1ps

// Referencia independente por modulo/divisao; as amostras percorrem bordas,
// todos os valores dos offsets e a cena inteira, com entradas consecutivas.
module tb_background;
    reg clk = 0;
    always #5 clk = ~clk;
    reg we = 0;
    reg [5:0] wr_x = 0, rd_x = 0;
    reg [4:0] wr_y = 0, rd_y = 0;
    reg [7:0] wr_tile_id = 0;
    wire [7:0] rd_tile_id;
    reg [8:0] pixel_x = 0, scroll_x = 0;
    reg [7:0] pixel_y = 0, scroll_y = 0;
    wire [13:0] bg_vram_addr;
    reg [7:0] expected_map [0:1199];
    integer reads = 0, pixels = 0, ignored_writes = 0;

    tilemap_ram map_under_test (
        .clk_wr(clk), .we(we), .wr_x(wr_x), .wr_y(wr_y),
        .wr_tile_id(wr_tile_id), .clk_rd(clk), .rd_x(rd_x),
        .rd_y(rd_y), .rd_tile_id(rd_tile_id)
    );
    bg_engine background (
        .clk(clk), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .scroll_x(scroll_x), .scroll_y(scroll_y), .we(we),
        .wr_x(wr_x), .wr_y(wr_y), .wr_tile_id(wr_tile_id),
        .bg_vram_addr(bg_vram_addr)
    );

    task automatic read_cell(input integer x, y);
        reg [7:0] expected;
        begin
            @(negedge clk);
            rd_x = x[5:0]; rd_y = y[4:0];
            expected = (x < 40 && y < 30) ? expected_map[y*40+x] : 8'd0;
            @(posedge clk); #1;
            if (rd_tile_id !== expected[7:0])
                $fatal(1, "Tilemap (%0d,%0d): esperado=%0d obtido=%0d",
                       x, y, expected, rd_tile_id);
            reads++;
        end
    endtask

    task automatic write_cell(input integer x, y, tile);
        begin
            @(negedge clk);
            we = 1; wr_x = x[5:0]; wr_y = y[4:0]; wr_tile_id = tile[7:0];
            @(posedge clk); #1;
            if (x < 40 && y < 30) expected_map[y*40+x] = tile[7:0];
            else ignored_writes++;
            @(negedge clk); we = 0;
        end
    endtask

    task automatic sample(input integer x, y, sx, sy);
        integer ex, ey, tile, expected;
        begin
            @(negedge clk);
            pixel_x = x[8:0]; pixel_y = y[7:0];
            scroll_x = sx[8:0]; scroll_y = sy[7:0];
            if (x < 320 && y < 240) begin
                ex = (x+sx)%320; ey = (y+sy)%240;
                tile = int'(expected_map[(ey/8)*40+ex/8]);
                expected = tile*64+(ey%8)*8+ex%8;
            end else expected = 0;
            @(posedge clk); #1;
            if (bg_vram_addr !== expected[13:0])
                $fatal(1, "Background pixel=(%0d,%0d) scroll=(%0d,%0d): esperado=%0d obtido=%0d",
                       x, y, sx, sy, expected, bg_vram_addr);
            pixels++;
        end
    endtask

    integer x, y, sx, sy;
    initial begin
        $readmemh("tilemap_data.hex", expected_map);
        #1;
        if (rd_tile_id !== 0 || bg_vram_addr !== 0)
            $fatal(1, "Saidas do background nao estao definidas no inicio");
        // Conteudo inicial completo e atualizacao de todas as 1200 celulas.
        for (y = 0; y < 30; y++)
            for (x = 0; x < 40; x++) read_cell(x, y);
        for (y = 0; y < 30; y++)
            for (x = 0; x < 40; x++) write_cell(x, y, (x*17+y*31+5)%256);

        // Todas as coordenadas invalidas: inclusive X=40/63 nas linhas validas.
        for (y = 0; y < 32; y++)
            for (x = 0; x < 64; x++)
                if (x >= 40 || y >= 30) begin
                    write_cell(x, y, 225);
                    read_cell(x, y);
                end
        for (y = 0; y < 30; y++)
            for (x = 0; x < 40; x++) read_cell(x, y);

        // Campos de offset completos em todas as combinacoes de cantos.
        for (sx = 0; sx < 512; sx++) begin
            sample(0, 0, sx, 0); sample(319, 239, sx, 239);
            sample(0, 239, sx, 240); sample(319, 0, sx, 255);
        end
        for (sy = 0; sy < 256; sy++) begin
            sample(0, 0, 0, sy); sample(319, 239, 319, sy);
            sample(0, 239, 320, sy); sample(319, 0, 511, sy);
        end
        // Quatro cenas completas verificam limites internos dos tiles e retorno.
        for (y = 0; y < 240; y++)
            for (x = 0; x < 320; x++) begin
                sample(x, y, 0, 0);
                sample(x, y, 319, 239);
                sample(x, y, 320, 240);
                sample(x, y, 511, 255);
            end
        sample(320, 0, 0, 0); sample(511, 239, 511, 255);
        sample(0, 240, 320, 240); sample(319, 255, 511, 255);
        sample(511, 255, 511, 255);
        sample(319, 239, 511, 255);
        $display("PASS: background/mapa, %0d leituras, %0d pixels, %0d escritas invalidas rejeitadas",
                 reads, pixels, ignored_writes);
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1, "Timeout do teste de background");
    end
endmodule
