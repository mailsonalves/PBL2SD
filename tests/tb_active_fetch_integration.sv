`timescale 1ns/1ps

module tb_active_fetch_integration;
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 4'hE;
    wire [9:0] leds;
    wire hs, vs, blank, sync_n, pixel_clock;
    wire [7:0] red, green, blue;

<<<<<<< HEAD
    gpu_de1_soc_top #(.USE_ACTIVE_FETCH(1), .PROGRAM_WORDS(9), .PROGRAM_FILE("programs/fetch_demo.hex")) dut (
=======
    gpu_de1_soc_top #(.USE_ACTIVE_FETCH(1)) dut (
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
        .CLOCK_50(clock), .KEY(keys), .SW(10'd0), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green),
        .VGA_B(blue), .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n),
        .VGA_CLK(pixel_clock)
    );

    integer accepted = 0;
    integer clear_writes = 0;
    integer triangle_writes = 0;
    integer palette_writes = 0;
    integer tilemap_writes = 0;
    integer sprite_writes = 0;
    integer write_x, write_y;

    // Observa as escritas na borda em que as memorias as recebem.
    always @(posedge clock) begin
        if (keys[0]) begin
<<<<<<< HEAD
            if (dut.u_core.cmd_valid && dut.u_core.cmd_ready)
                accepted = accepted + 1;
            if (dut.u_core.rast_busy && dut.u_core.cmd_valid)
                $fatal(1, "Novo comando durante rasterizacao");
            if (dut.u_core.pal_we) palette_writes = palette_writes + 1;
            if (dut.u_core.tm_we) tilemap_writes = tilemap_writes + 1;
            if (dut.u_core.sat_we) sprite_writes = sprite_writes + 1;
            if (dut.u_core.buf_we) begin
                if (dut.u_core.buf_wr_data == 0) begin
                    if (dut.u_core.buf_wr_addr != clear_writes)
=======
            if (dut.cmd_valid && dut.cmd_ready)
                accepted = accepted + 1;
            if (dut.rast_busy && dut.cmd_valid)
                $fatal(1, "Novo comando durante rasterizacao");
            if (dut.pal_we) palette_writes = palette_writes + 1;
            if (dut.tm_we) tilemap_writes = tilemap_writes + 1;
            if (dut.sat_we) sprite_writes = sprite_writes + 1;
            if (dut.buf_we) begin
                if (dut.buf_wr_data == 0) begin
                    if (dut.buf_wr_addr != clear_writes)
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
                        $fatal(1, "Limpeza perdeu ou repetiu endereco");
                    clear_writes = clear_writes + 1;
                end else begin
                    if (clear_writes != 76800)
                        $fatal(1, "Desenho iniciado antes da limpeza completa");
<<<<<<< HEAD
                    write_x = dut.u_core.buf_wr_addr % 320;
                    write_y = dut.u_core.buf_wr_addr / 320;
                    if (dut.u_core.buf_wr_data != 8'hFF || write_x < 10 ||
=======
                    write_x = dut.buf_wr_addr % 320;
                    write_y = dut.buf_wr_addr / 320;
                    if (dut.buf_wr_data != 8'hFF || write_x < 10 ||
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
                        write_y < 10 || write_x + write_y > 30)
                        $fatal(1, "Pixel fora do triangulo esperado");
                    triangle_writes = triangle_writes + 1;
                end
            end
        end
    end

    integer x, y, samples, active, hs_low, vs_low, colored;
    reg [7:0] expected_pixel;
    initial begin
        repeat (3) @(negedge clock);
        keys = 4'hF;
        wait (leds[3]);
        @(negedge clock);

        if (accepted != 8 || clear_writes != 76800 || triangle_writes != 66)
            $fatal(1, "Contagens incorretas: comandos=%0d limpeza=%0d triangulo=%0d",
                   accepted, clear_writes, triangle_writes);
        if (palette_writes != 1 || tilemap_writes != 1 || sprite_writes != 1)
            $fatal(1, "Escritas de recursos perdidas ou duplicadas");
        // O decoder expande RGB565 acrescentando zeros: F800 -> F80000.
<<<<<<< HEAD
        if (dut.u_core.u_palette.clut_ram[255] !== 24'hF80000)
            $fatal(1, "Cor RGB565 nao chegou a paleta: %06h",
                   dut.u_core.u_palette.clut_ram[255]);
        if (dut.u_core.u_bg_engine.u_map_buffer.map_ram[3*40+2] !== 8'd5)
            $fatal(1, "Tile nao chegou ao mapa");
        if (dut.u_core.scroll_x != 8 || dut.u_core.scroll_y != 4)
            $fatal(1, "Scroll nao atualizado");
        if (dut.u_core.u_sprite_engine.sat_ram[0] !==
=======
        if (dut.u_palette.clut_ram[255] !== 24'hF80000)
            $fatal(1, "Cor RGB565 nao chegou a paleta: %06h",
                   dut.u_palette.clut_ram[255]);
        if (dut.u_bg_engine.u_map_buffer.map_ram[3*40+2] !== 8'd5)
            $fatal(1, "Tile nao chegou ao mapa");
        if (dut.scroll_x != 8 || dut.scroll_y != 4)
            $fatal(1, "Scroll nao atualizado");
        if (dut.u_sprite_engine.sat_ram[0] !==
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
            {1'b1, 1'b0, 1'b0, 4'd0, 9'd152, 8'd100, 8'h01})
            $fatal(1, "Sprite nao atualizado");

        // Conferencia completa do resultado, incluindo o ultimo pixel escrito.
        for (y = 0; y < 240; y = y + 1)
            for (x = 0; x < 320; x = x + 1) begin
                expected_pixel = (x >= 10 && y >= 10 && x+y <= 30) ? 8'hFF : 0;
<<<<<<< HEAD
                if (dut.u_core.u_poly_buffer.ram[y*320+x] !== expected_pixel)
=======
                if (dut.u_poly_buffer.ram[y*320+x] !== expected_pixel)
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
                    $fatal(1, "Framebuffer incorreto em (%0d,%0d)", x, y);
            end

        // HALT para o programa, mas nao o video. Mede dois quadros inteiros.
        samples = 0; active = 0; hs_low = 0; vs_low = 0; colored = 0;
        while (samples < 800*525*2) begin
            @(posedge clock);
            #1;
<<<<<<< HEAD
            if (!leds[3] || dut.u_core.cmd_valid || accepted != 8)
=======
            if (!leds[3] || dut.cmd_valid || accepted != 8)
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
                $fatal(1, "HALT nao conservou a parada do programa");
            if (!blank && {red,green,blue} != 0)
                $fatal(1, "RGB ativo fora da area visivel");
            if (pixel_clock) begin
                samples = samples + 1;
                if (blank) active = active + 1;
                if (!hs) hs_low = hs_low + 1;
                if (!vs) vs_low = vs_low + 1;
                if (blank && {red,green,blue} != 0) colored = colored + 1;
            end
        end
        if (active != 640*480*2 || hs_low != 96*525*2 ||
            vs_low != 2*800*2 || colored == 0 || sync_n != 0)
            $fatal(1, "VGA nao manteve os dois quadros apos HALT");
        $display("PASS: integracao: 8 comandos, 76800 pixels limpos, 66 pixels desenhados e VGA ativo apos HALT");
        $finish;
    end

    initial begin
        #40000000;
        $fatal(1, "Timeout: programa ou VGA nao concluiu o teste");
    end
endmodule
