`timescale 1ns/1ps

module tb_memories_compositor;
    reg clk = 0;
    always #5 clk = ~clk;
    reg we_a = 0;
    reg [13:0] addr_a = 0, addr_b = 0;
    reg [7:0] data_in_a = 0;
    wire [7:0] data_out_a, data_out_b;
    reg pal_we = 0;
    reg [7:0] pal_wr_addr = 0, pal_rd_addr = 0;
    reg [23:0] pal_wr_data = 0;
    wire [23:0] rgb_out;
    reg [7:0] bg_pixel = 0, sp_pixel = 0, poly_pixel = 0;
    wire [7:0] final_pixel_index;
    reg [7:0] expected_patterns [0:16383];
    reg [23:0] expected_palette [0:255];
    integer pattern_reads = 0, palette_reads = 0, layer_checks = 0;

    pattern_vram patterns (
        .clk(clk), .we_a(we_a), .addr_a(addr_a), .data_in_a(data_in_a),
        .data_out_a(data_out_a), .addr_b(addr_b), .data_out_b(data_out_b)
    );
    color_palette palette (
        .clk(clk), .we(pal_we), .wr_addr(pal_wr_addr), .wr_data(pal_wr_data),
        .rd_addr(pal_rd_addr), .rgb_out(rgb_out)
    );
    compositor compose (
        .bg_pixel(bg_pixel), .sp_pixel(sp_pixel), .poly_pixel(poly_pixel),
        .final_pixel_index(final_pixel_index)
    );

    task automatic read_patterns(input integer a, b);
        begin
            @(negedge clk); addr_a = a[13:0]; addr_b = b[13:0];
            @(posedge clk); #1;
            if (data_out_a !== expected_patterns[a] || data_out_b !== expected_patterns[b])
                $fatal(1, "VRAM porta A/B (%0d,%0d): esperado=%02h/%02h obtido=%02h/%02h",
                       a, b, expected_patterns[a], expected_patterns[b], data_out_a, data_out_b);
            pattern_reads += 2;
        end
    endtask

    task automatic read_palette(input integer a);
        begin
            @(negedge clk); pal_rd_addr = a[7:0];
            @(posedge clk); #1;
            if (rgb_out !== expected_palette[a])
                $fatal(1, "Paleta[%0d]: esperado=%06h obtido=%06h", a, expected_palette[a], rgb_out);
            palette_reads++;
        end
    endtask

    task automatic layers(input integer bg, sp, poly);
        integer expected;
        begin
            bg_pixel = bg[7:0]; sp_pixel = sp[7:0]; poly_pixel = poly[7:0];
            expected = (sp != 0) ? sp : ((poly != 0) ? poly : bg);
            #1;
            if (final_pixel_index !== expected[7:0])
                $fatal(1, "Composicao BG/SP/POLY=%0d/%0d/%0d: esperado=%0d obtido=%0d",
                       bg, sp, poly, expected, final_pixel_index);
            layer_checks++;
        end
    endtask

    integer address, tile, index, other;
    reg [7:0] new_pixel;
    reg [23:0] new_rgb;
    initial begin
        $readmemh("tiles.hex", expected_patterns);
        $readmemh("palette.hex", expected_palette);
        // Todos os pixels dos 256 tiles pelas duas portas, em ordem inversa.
        for (address = 0; address < 16384; address++)
            read_patterns(address, 16383-address);
        // Atualiza o ultimo pixel de cada tile; outra porta le tile diferente.
        // Nao assume comportamento de colisao read-during-write na FPGA.
        for (tile = 0; tile < 256; tile++) begin
            address = tile*64+63; other = ((tile+127)%256)*64;
            new_pixel = 8'((tile*73+21)%256);
            @(negedge clk);
            we_a = 1; addr_a = address[13:0]; addr_b = other[13:0]; data_in_a = new_pixel;
            @(posedge clk); #1;
            if (data_out_b !== expected_patterns[other])
                $fatal(1, "Escrita na porta A prejudicou leitura independente da porta B");
            expected_patterns[address] = new_pixel;
            @(negedge clk); we_a = 0;
            read_patterns(address, address);
            read_patterns(tile*64, other);
        end
        // Conteudo inicial de toda a paleta e reprogramacao de todos os indices.
        for (index = 0; index < 256; index++) read_palette(index);
        for (index = 0; index < 256; index++) begin
            new_rgb = {index[7:0], (8'hFF ^ index[7:0]), (8'h55 ^ index[7:0])};
            other = (index+127)%256;
            @(negedge clk);
            pal_we = 1; pal_wr_addr = index[7:0]; pal_wr_data = new_rgb; pal_rd_addr = other[7:0];
            @(posedge clk); #1;
            if (rgb_out !== expected_palette[other])
                $fatal(1, "Escrita na paleta prejudicou leitura de outro indice");
            expected_palette[index] = new_rgb;
            @(negedge clk); pal_we = 0;
            read_palette(index);
        end
        for (index = 0; index < 256; index++) read_palette(index);
        // Zero transparente em cada camada superior e prioridade SP > POLY > BG.
        for (index = 0; index < 256; index++) begin
            layers(index, 0, 0);
            layers(index, 0, 255-index);
            layers(index, 255-index, 37);
            layers(0, index, 0);
            layers(193, index, index);
        end
        layers(0, 0, 0); layers(255, 1, 254); layers(255, 0, 1);
        $display("PASS: VRAM 256 tiles/duas portas, paleta 256 RGB/escrita, compositor; %0d leituras de padroes, %0d cores, %0d composicoes",
                 pattern_reads, palette_reads, layer_checks);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Timeout do teste de memorias e compositor");
    end
endmodule
