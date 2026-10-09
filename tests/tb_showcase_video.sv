`timescale 1ns/1ps
// Percorre a galeria com clocks VGA reais e compara os pinos com uma
// referencia direta da cena. Snapshot do estado + ROM independente da cache.
module tb_showcase_video;
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 4'hE;
    reg [9:0] switches = 10'h100; // manual, pausado
    wire [9:0] leds;
    wire hs, vs, blank, sync_n, pixel_clock;
    wire [7:0] red, green, blue;
    gpu_de1_soc_top #(.BUTTON_DEBOUNCE_CYCLES(1)) dut (
        .CLOCK_50(clock), .KEY(keys), .SW(switches), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green), .VGA_B(blue),
        .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n), .VGA_CLK(pixel_clock)
    );
    reg [7:0] patterns [0:16383];
    reg [7:0] map_snapshot [0:1199];
    reg [7:0] polygons [0:76799];
    reg [23:0] palette_snapshot [0:255];
    reg [31:0] sprites [0:31];
    integer priorities [0:31], banks [0:31];
    bit bank_enabled [0:31];
    integer scroll_x, scroll_y;
    reg [23:0] pixels [0:76799];
    initial $readmemh("assets/showcase_tiles.hex", patterns);

    function automatic [23:0] reference_pixel(input integer x, y, input bit active);
        integer ex, ey, tile, idx, sp_idx, best, k, sx, sy, lx, ly, raw;
        bit chosen;
        begin
            reference_pixel = 0;
            if (active) begin
                ex = (x+scroll_x)%320;
                ey = (y+scroll_y)%240;
                tile = int'(map_snapshot[(ey/8)*40 + ex/8]);
                idx = int'(patterns[tile*64 + (ey%8)*8 + ex%8]);
                if (polygons[y*320+x] != 0) idx = int'(polygons[y*320+x]);
                chosen = 0; best = 0; sp_idx = 0;
                for (k = 0; k < 32; k = k+1) begin
                    sx = int'(sprites[k][24:16]); sy = int'(sprites[k][15:8]);
                    if (sprites[k][31] && x >= sx && x < sx+16 && y >= sy && y < sy+16) begin
                        lx = sprites[k][30] ? 15-(x-sx) : x-sx;
                        ly = sprites[k][29] ? 15-(y-sy) : y-sy;
                        tile = (int'(sprites[k][7:0]) + (ly/8)*2 + lx/8)%256;
                        raw = int'(patterns[tile*64+(ly%8)*8+lx%8]);
                        if (bank_enabled[k]) raw = (raw%16 == 0) ? 0 : banks[k]*16+raw%16;
                        if (raw != 0 && (!chosen || priorities[k] > best)) begin
                            chosen = 1; best = priorities[k]; sp_idx = raw;
                        end
                    end
                end
                if (chosen) idx = sp_idx;
                reference_pixel = palette_snapshot[idx];
            end
        end
    endfunction

    integer page, i, n, active_samples, hs_low, vs_low, file_handle;
    integer enabled_count;
    reg [23:0] expected_rgb [0:2];
    reg [2:0] expected_hs, expected_vs, expected_active;
    integer expected_x [0:2], expected_y [0:2];
    string frame_path;
    initial begin
        repeat (4) @(negedge clock); keys = 4'hF;
        for (page = 0; page < 8; page = page+1) begin
            @(negedge clock); switches = 10'h100 | 10'(page);
            // R12 mostra que o painel entrou no setup; WAIT_FRAME mostra que
            // terminou todos os comandos, incluindo PRESENT/cache/rasterizador.
            wait (dut.processor_output == 32'(page) &&
                dut.gen_program_core.u_core.u_register_file.registers[12] == 32'(page) &&
                dut.processor_status[7] && !dut.execution_busy);
            @(negedge clock);
            scroll_x = int'(dut.scroll_x); scroll_y = int'(dut.scroll_y);
            enabled_count = 0;
            for (i = 0; i < 1200; i=i+1) map_snapshot[i] = dut.u_bg_engine.u_map_buffer.map_ram[i];
            for (i = 0; i < 256; i=i+1) palette_snapshot[i] = dut.u_palette.clut_ram[i];
            for (i = 0; i < 76800; i=i+1)
                polygons[i] = dut.buffer_front ? dut.u_poly_buffer.back_ram[i] : dut.u_poly_buffer.ram[i];
            for (i = 0; i < 32; i=i+1) begin
                sprites[i] = dut.u_sprite_engine.sat_ram[i];
                priorities[i] = int'(dut.u_sprite_engine.priority_ram[i]);
                banks[i] = int'(dut.u_sprite_engine.palette_bank_ram[i]);
                bank_enabled[i] = dut.u_sprite_engine.palette_enable_ram[i];
                if (sprites[i][31]) enabled_count = enabled_count+1;
            end
            if (page == 1 && enabled_count != 32) $fatal(1, "Painel1 nao mostra 32 sprites");
            if (page == 2 && (sprites[0][30:29] != 0 || sprites[1][30:29] != 2 ||
                sprites[2][30:29] != 1 || sprites[3][30:29] != 3)) $fatal(1, "Painel2 flips");
            if (leds[3] || leds[2:0] !== 3'(page) || !leds[5] || !leds[7])
                $fatal(1, "Status da galeria no painel %0d", page);
            active_samples=0; hs_low=0; vs_low=0;
            for (n = 0; n < 840002; n=n+1) begin
                @(posedge clock);
                expected_rgb[2]=expected_rgb[1]; expected_rgb[1]=expected_rgb[0];
                expected_rgb[0]=reference_pixel(int'(dut.pixel_x), int'(dut.pixel_y), dut.video_active);
                expected_hs={expected_hs[1:0],dut.raw_hsync};
                expected_vs={expected_vs[1:0],dut.raw_vsync};
                expected_active={expected_active[1:0],dut.video_active};
                expected_x[2]=expected_x[1]; expected_x[1]=expected_x[0]; expected_x[0]=int'(dut.pixel_x);
                expected_y[2]=expected_y[1]; expected_y[1]=expected_y[0]; expected_y[0]=int'(dut.pixel_y);
                #1;
                if (n >= 2) begin
                    if ({red,green,blue} !== expected_rgb[2] || hs !== expected_hs[2] ||
                        vs !== expected_vs[2] || blank !== expected_active[2] || sync_n !== 0)
                        $fatal(1, "Painel%0d ciclo%0d xy%0d,%0d RGB=%h esperado=%h", page,n,
                            expected_x[2],expected_y[2],{red,green,blue},expected_rgb[2]);
                    if (blank) begin
                        active_samples=active_samples+1;
                        pixels[expected_y[2]*320+expected_x[2]]={red,green,blue};
                    end
                    if (!hs) hs_low=hs_low+1;
                    if (!vs) vs_low=vs_low+1;
                end
            end
            if (active_samples != 614400 || hs_low != 100800 || vs_low != 3200)
                $fatal(1, "Temporizacao painel%0d", page);
            // Captura opcional: pasta criada pelo runner; nao depende de SDL.
            frame_path=$sformatf(".build/showcase/painel%0d.ppm",page);
            file_handle=$fopen(frame_path,"w");
            if (file_handle) begin
                $fwrite(file_handle,"P3\n320 240\n255\n");
                for (i=0;i<76800;i=i+1)
                    $fwrite(file_handle,"%0d %0d %0d\n",pixels[i][23:16],pixels[i][15:8],pixels[i][7:0]);
                $fclose(file_handle);
            end
            $display("PASS: galeria painel%0d, 840000 ciclos VGA/RGB e %0d sprites habilitados",page,enabled_count);
        end
        $display("PASS: galeria completa, oito paineis e 6720000 ciclos VGA/RGB com clocks reais");
        $finish;
    end
    initial begin #700000000; $fatal(1, "Timeout na galeria VGA"); end
endmodule
