`timescale 1ns/1ps

module tb_sprites_active_fetch;
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 4'hE;
    wire [9:0] leds;
    wire hs, vs, blank, sync_n, pixel_clock;
    wire [7:0] red, green, blue;

    gpu_de1_soc_top #(
        .USE_PROGRAMMABLE_CORE(0), .SHOWCASE(0),
        .USE_ACTIVE_FETCH(1),
        .PROGRAM_WORDS(12),
        .PROGRAM_FILE("programs/sprites_demo.hex")
    ) dut (
        .CLOCK_50(clock), .KEY(keys), .SW(10'd0), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green),
        .VGA_B(blue), .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n),
        .VGA_CLK(pixel_clock)
    );

    integer accepted = 0;
    integer sprite_writes = 0;
    integer clear_writes = 0;
    always @(posedge clock) begin
        if (keys[0]) begin
            if (dut.cmd_valid && dut.cmd_ready) accepted = accepted + 1;
            if (dut.sat_we) sprite_writes = sprite_writes + 1;
            if (dut.buf_we) begin
                if (dut.buf_wr_data != 0 || dut.buf_wr_addr != clear_writes)
                    $fatal(1, "Programa nao limpou a camada de poligonos em ordem");
                clear_writes = clear_writes + 1;
            end
            if (dut.rast_busy && dut.cmd_valid)
                $fatal(1, "Comando enviado antes da conclusao da limpeza");
        end
    end

    function automatic [31:0] attributes(
        input bit enabled, flip_h, flip_v,
        input integer x, y, tile
    );
        attributes = (enabled ? 32'h80000000 : 0) |
                     (flip_h ? 32'h40000000 : 0) |
                     (flip_v ? 32'h20000000 : 0) |
                     (x * 65536) | (y * 256) | tile;
    endfunction

    // Referencia geometrica independente da concatenacao usada pelo RTL.
    function automatic integer image_address(
        input integer local_x, local_y, base_tile,
        input bit flip_h, flip_v
    );
        integer image_x, image_y, tile;
        begin
            image_x = flip_h ? 15-local_x : local_x;
            image_y = flip_v ? 15-local_y : local_y;
            tile = (base_tile + (image_y/8)*2 + image_x/8) % 256;
            image_address = tile*64 + (image_y%8)*8 + image_x%8;
        end
    endfunction

    integer i, samples, active, hs_low, vs_low;
    integer sprite1_pixels, sprite31_pixels, disabled_pixels, expected_address;
    initial begin
        repeat (3) @(negedge clock);
        keys = 4'hF;
        wait (leds[3]);
        @(negedge clock);
        if (accepted != 11 || sprite_writes != 10 || clear_writes != 76800)
            $fatal(1, "Contagens incorretas: comandos=%0d sprites=%0d limpeza=%0d",
                   accepted, sprite_writes, clear_writes);
        if (dut.u_sprite_engine.sat_ram[0] !== attributes(0,0,0,150,100,0) ||
            dut.u_sprite_engine.sat_ram[1] !== attributes(1,0,0,48,64,1) ||
            dut.u_sprite_engine.sat_ram[2] !== attributes(0,1,0,80,60,5) ||
            dut.u_sprite_engine.sat_ram[31] !== attributes(1,1,1,120,60,13))
            $fatal(1, "Programa nao preservou posicoes/atributos dos sprites");
        for (i = 3; i < 31; i = i+1)
            if (dut.u_sprite_engine.sat_ram[i] !== 0)
                $fatal(1, "Programa alterou sprite nao selecionado: %0d", i);
        for (i = 0; i < 76800; i = i+1)
            if (dut.u_poly_buffer.ram[i] !== 0)
                $fatal(1, "Framebuffer nao foi limpo");

        samples = 0; active = 0; hs_low = 0; vs_low = 0;
        sprite1_pixels = 0; sprite31_pixels = 0; disabled_pixels = 0;
        while (samples < 800*525) begin
            @(posedge clock);
            #1;
            if (!leds[3] || dut.cmd_valid || accepted != 11)
                $fatal(1, "Programa nao permaneceu em HALT");
            // Segunda borda de CLOCK_50 do pixel: a VRAM ja leu seu endereco.
            if (!pixel_clock) begin
                samples = samples+1;
                if (!hs) hs_low = hs_low+1;
                if (!vs) vs_low = vs_low+1;
                if (blank) begin
                    active = active+1;
                    expected_address = 0;
                    if (dut.pixel_x >= 48 && dut.pixel_x < 64 &&
                        dut.pixel_y >= 64 && dut.pixel_y < 80) begin
                        expected_address = image_address(dut.pixel_x-48, dut.pixel_y-64, 1, 0, 0);
                        sprite1_pixels = sprite1_pixels+1;
                    end else if (dut.pixel_x >= 120 && dut.pixel_x < 136 &&
                                 dut.pixel_y >= 60 && dut.pixel_y < 76) begin
                        expected_address = image_address(dut.pixel_x-120, dut.pixel_y-60, 13, 1, 1);
                        sprite31_pixels = sprite31_pixels+1;
                    end
                    if (dut.pixel_x >= 80 && dut.pixel_x < 96 &&
                        dut.pixel_y >= 60 && dut.pixel_y < 76)
                        disabled_pixels = disabled_pixels+1;
                    if (dut.sp_vram_addr != expected_address ||
                        dut.sp_pixel !== dut.u_patterns.ram[expected_address])
                        $fatal(1, "Pixel de sprite incorreto em (%0d,%0d)",
                               dut.pixel_x, dut.pixel_y);
                end
            end
        end
        if (active != 640*480 || hs_low != 96*525 || vs_low != 2*800 ||
            sprite1_pixels != 1024 || sprite31_pixels != 1024 || disabled_pixels != 1024)
            $fatal(1, "VGA ou cobertura dos sprites incorretos");
        $display("PASS: busca ativa configurou sprites 0,1,2,31; movimento, imagem, flips, disable e um quadro VGA verificados");
        $finish;
    end

    initial begin
        #25000000;
        $fatal(1, "Timeout no programa de sprites");
    end
endmodule
