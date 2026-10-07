`timescale 1ns/1ps

// Conferencia funcional dos 32 sprites com pixels de uma ROM conhecida.
// As expectativas sao calculadas em coordenadas de imagem, sem usar o
// endereco/cor produzidos pelo DUT como oraculo.
module tb_sprite_layers;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [8:0] pixel_x = 0;
    reg [7:0] pixel_y = 0;
    reg sat_we = 0, meta_we = 0;
    reg [4:0] sat_addr = 0, meta_addr = 0;
    reg [31:0] sat_data = 0, sat_write_mask = 0;
    reg [1:0] meta_priority = 0;
    reg meta_palette_enable = 0;
    reg [3:0] meta_palette_bank = 0;
    wire [13:0] sp_vram_addr;
    wire [7:0] sp_pixel;
    wire busy;

    sprite_engine #(.PATTERN_FILE("tests/fixtures/sprite_layers.hex")) dut (
        .clk(clk), .rst_n(rst_n), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .sat_we(sat_we), .sat_addr(sat_addr), .sat_data(sat_data),
        .sat_write_mask(sat_write_mask), .meta_we(meta_we), .meta_addr(meta_addr),
        .meta_priority(meta_priority), .meta_palette_enable(meta_palette_enable),
        .meta_palette_bank(meta_palette_bank), .sp_vram_addr(sp_vram_addr),
        .sp_pixel(sp_pixel), .busy(busy)
    );

    integer pixel_checks = 0;
    integer load_writes = 0;
    integer load_count = 0;
    always @(posedge clk)
        if (rst_n && dut.load_write) load_writes = load_writes + 1;

    function automatic integer pattern(input integer tile, x, y);
        if (tile >= 1 && tile < 5) pattern = 32'h21;
        else if (tile >= 8 && tile < 12) pattern = 32'h32;
        else if (tile >= 12 && tile < 16) pattern = 32'h40;
        else if (tile >= 16 && tile < 20) pattern = 32'hF5;
        else if (tile >= 20 && tile < 24)
            pattern = (tile == 20 && x == 0 && y == 0) ? 0 :
                      (tile*7+y*8+x)%255+1;
        else pattern = (tile*17+y*8+x)%255+1;
    endfunction

    function automatic integer image_pixel(input integer base, x, y, fx, fy);
        integer ix, iy, tile;
        begin
            ix = (fx != 0) ? 15-x : x;
            iy = (fy != 0) ? 15-y : y;
            tile = (base + (iy/8)*2 + ix/8)%256;
            image_pixel = pattern(tile, ix%8, iy%8);
        end
    endfunction

    task automatic sample(input integer x, y, expected);
        begin
            @(negedge clk);
            pixel_x = x[8:0];
            pixel_y = y[7:0];
            @(posedge clk);
            #1;
            if (sp_pixel !== expected[7:0])
                $fatal(1, "Pixel (%0d,%0d): esperado=%02h obtido=%02h", x, y,
                       expected[7:0], sp_pixel);
            pixel_checks = pixel_checks + 1;
        end
    endtask

    task automatic finish_load(input integer writes_before);
        integer cycles;
        begin
            cycles = 0;
            while (busy) begin
                @(negedge clk);
                cycles = cycles + 1;
                if (cycles > 260) $fatal(1, "Carga de sprite nao terminou");
            end
            if (load_writes-writes_before != 256)
                $fatal(1, "Carga precisa escrever 256 pixels: escreveu %0d", load_writes-writes_before);
            load_count = load_count + 1;
        end
    endtask

    task automatic write_sat(input integer id, input [31:0] data, mask,
                             input bit reload);
        integer before_writes;
        begin
            if (busy) $fatal(1, "Teste tentou escrever SAT enquanto ocupado");
            before_writes = load_writes;
            @(negedge clk);
            sat_addr = id[4:0];
            sat_data = data;
            sat_write_mask = mask;
            sat_we = 1;
            @(posedge clk);
            #1;
            if (busy !== reload) $fatal(1, "busy incorreto depois de SAT[%0d]", id);
            @(negedge clk);
            sat_we = 0;
            if (reload) finish_load(before_writes);
            else if (load_writes != before_writes) $fatal(1, "Atualizacao simples recarregou imagem");
        end
    endtask

    task automatic sprite(input integer id, base, enabled, x, y, fx, fy,
                          input bit reload);
        write_sat(id, {enabled[0], fx[0], fy[0], 4'd0, x[8:0], y[7:0], base[7:0]},
                  32'hFFFFFFFF, reload);
    endtask

    task automatic metadata(input integer id, priority_value, bank_enabled, bank);
        begin
            if (busy) $fatal(1, "Metadata escrita durante carga inesperada");
            @(negedge clk);
            meta_we = 1;
            meta_addr = id[4:0];
            meta_priority = priority_value[1:0];
            meta_palette_enable = bank_enabled[0];
            meta_palette_bank = bank[3:0];
            @(negedge clk);
            meta_we = 0;
            if (busy) $fatal(1, "Metadata provocou recarga de imagem");
        end
    endtask

    task automatic complete_sprite(input integer x, y, base, fx, fy);
        integer dx, dy;
        begin
            for (dy = 0; dy < 16; dy = dy + 1)
                for (dx = 0; dx < 16; dx = dx + 1)
                    sample(x+dx, y+dy, image_pixel(base, dx, dy, fx, fy));
            sample(x-1, y, 0);
            sample(x+16, y, 0);
            sample(x, y-1, 0);
            sample(x, y+16, 0);
        end
    endtask

    integer id, flip, before_writes;
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        if (!busy) $fatal(1, "Reset precisa iniciar carga do sprite legado");
        sample(150, 100, 0);
        // Escrever durante busy e ignorado: preserva o snapshot em carregamento.
        @(negedge clk);
        sat_we = 1;
        sat_addr = 0;
        sat_data = 32'd0;
        sat_write_mask = 32'hFFFFFFFF;
        @(negedge clk);
        sat_we = 0;
        finish_load(0);
        sample(150, 100, 32'h21);
        if (dut.sat_ram[0][31] !== 1'b1)
            $fatal(1, "Escrita durante busy modificou SAT");
        sample(166, 100, 0);

        // Um pixel transparente do menor ID revela o sprite de ID maior.
        sprite(0, 20, 1, 100, 100, 0, 0, 1);
        sprite(1, 8, 1, 100, 100, 0, 0, 1);
        sample(100, 100, 32'h32);
        sample(101, 100, image_pixel(20, 1, 0, 0, 0));
        metadata(1, 3, 0, 0);
        sample(101, 100, 32'h32);
        metadata(0, 3, 0, 0);
        sample(101, 100, image_pixel(20, 1, 0, 0, 0));
        metadata(0, 0, 0, 0);
        sample(101, 100, 32'h32);
        metadata(1, 1, 0, 0);
        metadata(0, 2, 0, 0);
        sample(101, 100, image_pixel(20, 1, 0, 0, 0));
        metadata(1, 2, 0, 0);
        sample(101, 100, image_pixel(20, 1, 0, 0, 0));
        metadata(0, 1, 0, 0);
        sample(101, 100, 32'h32);
        metadata(0, 3, 1, 9);
        sample(100, 100, 32'h32); // Alpha 0 nao pode virar 0x90 ao mapear banco.
        sample(101, 100, 32'h9E);

        // Banco de paleta transforma so o indice de 4 bits; indice 0 continua alpha.
        sprite(0, 12, 1, 100, 100, 0, 0, 1);
        metadata(0, 3, 1, 9);
        sample(100, 100, 32'h32); // 0x40 tem nibble baixo zero, logo e transparente.
        metadata(0, 3, 0, 9);
        sample(100, 100, 32'h40); // Modo direto preserva todos os oito bits.
        sprite(0, 16, 1, 100, 100, 0, 0, 1);
        metadata(0, 3, 1, 10);
        sample(100, 100, 32'hA5);
        metadata(0, 3, 1, 0);
        sample(100, 100, 32'h05);
        metadata(0, 3, 0, 10);
        sample(100, 100, 32'hF5);

        // Posicao e flips preservam a imagem em cache e os metadados.
        write_sat(0, {7'd0, 9'd120, 8'd110, 8'd0}, 32'h01FFFF00, 0);
        sample(100, 100, 32'h32);
        sample(120, 110, 32'hF5);
        if (dut.priority_ram[0] != 3 || dut.palette_bank_ram[0] != 10)
            $fatal(1, "Escrita parcial apagou metadados");
        sprite(0, 16, 0, 120, 110, 0, 0, 0);
        sprite(1, 8, 0, 100, 100, 0, 0, 0);
        // Imagem alterada enquanto desabilitado nao carrega ate habilitar.
        sprite(0, 20, 0, 120, 110, 0, 0, 0);
        sprite(0, 20, 1, 120, 110, 0, 0, 1);
        for (flip = 0; flip < 4; flip = flip + 1) begin
            sprite(0, 20, 1, 120, 110, flip%2, flip/2, 0);
            complete_sprite(120, 110, 20, flip%2, flip/2);
        end
        // A atualizacao de imagem troca os quatro quadrantes, inclusive o ultimo pixel.
        sprite(0, 255, 1, 120, 110, 0, 0, 1);
        complete_sprite(120, 110, 255, 0, 0);
        sprite(0, 255, 0, 120, 110, 0, 0, 0);

        // Os 32 caches sao usados ao mesmo tempo. Com prioridades iguais, o menor
        // ID opaco vence; removendo-o, o seguinte deve aparecer sem nova carga.
        for (id = 0; id < 32; id = id + 1)
            sprite(id, 32+id*4, 1, 40, 40, 0, 0, 1);
        for (id = 0; id < 32; id = id + 1) begin
            complete_sprite(40, 40, 32+id*4, 0, 0);
            sprite(id, 32+id*4, 0, 40, 40, 0, 0, 0);
        end
        sample(40, 40, 0);

        // Recorte evita wrap de X+16/Y+16 na extremidade dos contadores.
        sprite(31, 156, 1, 508, 252, 0, 0, 0);
        sample(511, 255, image_pixel(156, 3, 3, 0, 0));
        sample(0, 0, 0);
        // Reset invalida todos os caches e restaura os metadados e sprite legado.
        @(negedge clk);
        rst_n = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        before_writes = load_writes;
        sample(150, 100, 0);
        finish_load(before_writes);
        sample(150, 100, 32'h21);
        sample(511, 255, 0);

        $display("PASS tb_sprite_layers: %0d pixels, %0d cargas de 256 pixels, 32 sprites simultaneos", pixel_checks, load_count);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "Timeout tb_sprite_layers");
    end
endmodule
