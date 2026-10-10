`timescale 1ns/1ps

module tb_pbl2_programs;
    wire background_finished, polygons_finished;
    pbl2_program_checker #(.POLYGONS(0),
        .PROGRAM_FILE("programs/background_sprites.hex")) background (
        .finished(background_finished));
    pbl2_program_checker #(.POLYGONS(1),
        .PROGRAM_FILE("programs/polygons_motion.hex")) polygons (
        .finished(polygons_finished));
    initial begin
        wait (background_finished && polygons_finished);
        $display("PASS: ambos os programas PBL2 concluiram com quadros VGA conferidos pixel a pixel");
        $finish;
    end
    initial begin
        #200000000;
        $fatal(1, "Timeout nas demonstracoes PBL2 com temporizacao VGA real");
    end
endmodule

module pbl2_program_checker #(
    parameter POLYGONS = 0,
    parameter PROGRAM_FILE = "programs/background_sprites.hex"
) (output reg finished = 0);
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 4'he;
    wire [9:0] leds;
    wire hs, vs, blank, sync_n, pixel_clock;
    wire [7:0] red, green, blue;
    wire [31:0] mmio_frames;
    wire mmio_waitrequest;
    gpu_core #(.PROGRAM_FILE(PROGRAM_FILE)) dut (
        .CLOCK_50(clock), .KEY(keys), .SW(10'd0), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green),
        .VGA_B(blue), .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n),
        .VGA_CLK(pixel_clock), .mmio_address(6'h10), .mmio_read(1'b1),
        .mmio_write(1'b0), .mmio_writedata(32'd0), .mmio_byteenable(4'hf),
        .mmio_readdata(mmio_frames), .mmio_waitrequest(mmio_waitrequest)
    );

    integer accepted = 0, frames = 0, waits = 0, swaps = 0;
    integer clears = 0, draws = 0, clear_pixels = 0;
    integer palette_writes = 0, tile_writes = 0, sprite_writes = 0;
    integer style_writes = 0, sprite1_positions = 0, sprite2_positions = 0;
    reg waiting_last = 0;
    always @(posedge clock) begin
        if (dut.rst_n) begin
            if (dut.cmd_valid && dut.cmd_ready) begin
                if (dut.execution_busy)
                    $fatal(1, "Programa%0d aceitou comando durante operacao pendente", POLYGONS);
                accepted = accepted + 1;
            end
            if (dut.frame_boundary) frames = frames + 1;
            if (dut.waiting_frame && !waiting_last) waits = waits + 1;
            waiting_last = dut.waiting_frame;
            if (dut.buffer_swap_done) swaps = swaps + 1;
            if (dut.rast_start) begin
                if (dut.rast_clear_screen) clears = clears + 1;
                else draws = draws + 1;
            end
            if (dut.buf_we && dut.buf_wr_data == 0) begin
                if (dut.buf_wr_addr != clear_pixels % 76800)
                    $fatal(1, "CLEAR perdeu ou repetiu endereco no programa%0d", POLYGONS);
                clear_pixels = clear_pixels + 1;
            end
            if (dut.pal_we) palette_writes = palette_writes + 1;
            if (dut.tm_we) tile_writes = tile_writes + 1;
            if (dut.sprite_meta_we) style_writes = style_writes + 1;
            if (dut.sat_we) begin
                sprite_writes = sprite_writes + 1;
                if (dut.sat_write_mask == 32'h01ffff00 && dut.sat_addr == 1) begin
                    if (POLYGONS) begin
                        if (dut.sat_data[24:16] != 232 ||
                            dut.sat_data[15:8] != 64 + 8*sprite1_positions)
                            $fatal(1, "Sprite poligonos nao seguiu movimento calculado pela ULA");
                    end else if (dut.sat_data[24:16] != 40 + 16*sprite1_positions ||
                                 dut.sat_data[15:8] != 72)
                        $fatal(1, "Sprite background nao seguiu movimento calculado pela ULA");
                    sprite1_positions = sprite1_positions + 1;
                end
                if (!POLYGONS && dut.sat_write_mask == 32'h01ffff00 && dut.sat_addr == 2) begin
                    if (dut.sat_data[24:16] != 46 + 16*sprite2_positions ||
                        dut.sat_data[15:8] != 76)
                        $fatal(1, "Segundo sprite perdeu movimento relativo calculado pela ULA");
                    sprite2_positions = sprite2_positions + 1;
                end
            end
        end
    end

    // Referencia carregada dos arquivos de recurso, sem usar pixels, caches,
    // indices compostos ou framebuffer produzido pelo RTL como resultado esperado.
    reg [7:0] reference_patterns [0:16383];
    reg [7:0] reference_map [0:1199];
    reg [23:0] reference_palette [0:255];
    reg [31:0] reference_sat [0:31];
    integer reference_priority [0:31];
    integer reference_bank [0:31];
    reg reference_bank_enabled [0:31];

    function automatic [31:0] attributes(input integer x, y,
        input bit flip_h, flip_v);
        attributes = 32'h80000001 | (x * 65536) | (y * 256) |
                     (flip_h ? 32'h40000000 : 0) | (flip_v ? 32'h20000000 : 0);
    endfunction

    function automatic bit inside_triangle(input integer x, y,
        input integer ax, ay, bx, by, cx, cy);
        integer edge_a, edge_b, edge_c;
        begin
            edge_a = (x-ax)*(by-ay) - (y-ay)*(bx-ax);
            edge_b = (x-bx)*(cy-by) - (y-by)*(cx-bx);
            edge_c = (x-cx)*(ay-cy) - (y-cy)*(ax-cx);
            inside_triangle = (edge_a >= 0 && edge_b >= 0 && edge_c >= 0) ||
                              (edge_a <= 0 && edge_b <= 0 && edge_c <= 0);
        end
    endfunction

    function automatic [7:0] reference_polygon(input integer x, y);
        reg [7:0] color;
        begin
            color = 0;
            if (POLYGONS) begin
                if (inside_triangle(x,y,56,48,120,48,88,100)) color = 250;
                if (inside_triangle(x,y,140,40,184,104,120,104)) color = 251;
                if (x >= 120 && x <= 208 && y >= 140 && y <= 176) color = 252;
            end
            reference_polygon = color;
        end
    endfunction

    function automatic [7:0] reference_sprite(input integer x, y);
        integer id, local_x, local_y, source_x, source_y, tile, address;
        integer selected_priority;
        reg [7:0] source_pixel, selected_pixel;
        bit opaque;
        begin
            selected_pixel = 0; selected_priority = -1;
            // Menor ID ganha empates; a transparencia e verificada antes da
            // prioridade. Coordenadas de padrao usam div/mod para independencia
            // da concatenacao e dos caches implementados no hardware.
            for (id = 0; id < 32; id = id+1) begin
                local_x = x - reference_sat[id][24:16];
                local_y = y - reference_sat[id][15:8];
                if (reference_sat[id][31] && local_x >= 0 && local_x < 16 &&
                    local_y >= 0 && local_y < 16) begin
                    source_x = reference_sat[id][30] ? 15-local_x : local_x;
                    source_y = reference_sat[id][29] ? 15-local_y : local_y;
                    tile = (reference_sat[id][7:0] + 2*(source_y/8) + source_x/8) % 256;
                    address = tile*64 + (source_y%8)*8 + source_x%8;
                    source_pixel = reference_patterns[address];
                    opaque = reference_bank_enabled[id] ? (source_pixel % 16 != 0) :
                                                          (source_pixel != 0);
                    if (opaque && reference_priority[id] > selected_priority) begin
                        selected_priority = reference_priority[id];
                        selected_pixel = reference_bank_enabled[id] ?
                            reference_bank[id]*16 + source_pixel%16 : source_pixel;
                    end
                end
            end
            reference_sprite = selected_pixel;
        end
    endfunction

    function automatic [23:0] reference_rgb(input integer x, y);
        integer effective_x, tile, pattern_address;
        reg [7:0] index;
        begin
            effective_x = (x + (POLYGONS ? 0 : 32)) % 320;
            tile = reference_map[(y/8)*40 + effective_x/8];
            pattern_address = tile*64 + (y%8)*8 + effective_x%8;
            index = reference_patterns[pattern_address];
            if (reference_polygon(x,y) != 0) index = reference_polygon(x,y);
            if (reference_sprite(x,y) != 0) index = reference_sprite(x,y);
            reference_rgb = reference_palette[index];
        end
    endfunction

    reg verify_video = 0;
    reg [23:0] rgb_pipeline [0:2];
    integer x_pipeline [0:2], y_pipeline [0:2];
    integer pipeline_valid = 0;
    // As tres etapas sao tilemap/padrao, composicao e CLUT; o resultado
    // independente segue a mesma latencia declarada na interface VGA.
    always @(posedge clock) begin
        if (verify_video) begin
            rgb_pipeline[2] = rgb_pipeline[1];
            rgb_pipeline[1] = rgb_pipeline[0];
            x_pipeline[2] = x_pipeline[1]; x_pipeline[1] = x_pipeline[0];
            y_pipeline[2] = y_pipeline[1]; y_pipeline[1] = y_pipeline[0];
            x_pipeline[0] = dut.pixel_x; y_pipeline[0] = dut.pixel_y;
            rgb_pipeline[0] = dut.video_active ? reference_rgb(dut.pixel_x,dut.pixel_y) : 0;
            pipeline_valid = pipeline_valid + 1;
            #1;
            if (pipeline_valid > 3 && {red,green,blue} !== rgb_pipeline[2])
                $fatal(1, "Programa%0d VGA (%0d,%0d): RGB=%h esperado=%h",
                    POLYGONS, x_pipeline[2], y_pipeline[2], {red,green,blue}, rgb_pipeline[2]);
        end
    end

    integer i, x, y, samples, active, hs_low, vs_low, colored;
    reg [7:0] expected_polygon;
    initial begin
        $readmemh("tiles.hex", reference_patterns);
        $readmemh("tilemap_data.hex", reference_map);
        $readmemh("palette.hex", reference_palette);
        for (i = 0; i < 32; i = i+1) begin
            reference_sat[i] = 0; reference_priority[i] = 0;
            reference_bank[i] = 0; reference_bank_enabled[i] = 0;
        end
        if (POLYGONS) begin
            reference_sat[1] = attributes(232,96,0,0); reference_priority[1] = 1;
            reference_sat[2] = attributes(238,100,1,0); reference_priority[2] = 3;
            reference_palette[250] = 24'hf80000;
            reference_palette[251] = 24'h00fcf8;
            reference_palette[252] = 24'hf8fc00;
        end else begin
            reference_sat[1] = attributes(104,72,0,0); reference_priority[1] = 1;
            reference_sat[2] = attributes(110,76,1,0); reference_priority[2] = 3;
            reference_sat[3] = attributes(140,72,0,1); reference_priority[3] = 2;
            reference_sat[31] = attributes(180,72,1,1);
            reference_bank[2] = 3; reference_bank_enabled[2] = 1;
            reference_map[3*40+2] = 5; reference_map[3*40+3] = 6;
            reference_map[29*40+39] = 5;
            for (i = 49; i <= 63; i = i+1)
                reference_palette[i] = i%2 ? 24'hf800f8 : 24'h00fc00;
        end
        repeat (3) @(negedge clock);
        keys = 4'hf;
        wait (leds[3]);
        repeat (8) @(negedge clock);
        if (leds[4] || !leds[5] || waits != 4 || sprite1_positions != 5 ||
            frames != (POLYGONS ? 8 : 4) || mmio_frames !== frames ||
            accepted != (POLYGONS ? 71 : 46) ||
            clears != (POLYGONS ? 4 : 1) || draws != (POLYGONS ? 16 : 0) ||
            clear_pixels != (POLYGONS ? 4*76800 : 76800) ||
            palette_writes != (POLYGONS ? 3 : 15) || tile_writes != (POLYGONS ? 0 : 3) ||
            sprite_writes != (POLYGONS ? 9 : 17) || style_writes != (POLYGONS ? 2 : 4) ||
            swaps != (POLYGONS ? 4 : 0) || dut.buffer_front ||
            dut.buffer_double_buffered != POLYGONS)
            $fatal(1, "Programa%0d contagens/estado: aceitos%0d clear%0d draw%0d sprites%0d style%0d frames%0d wait%0d swap%0d",
                POLYGONS,accepted,clears,draws,sprite_writes,style_writes,frames,waits,swaps);
        if (dut.program_pc != (POLYGONS ? 43 : 54) || dut.program_ir !== 32'hf0000000)
            $fatal(1, "PC/IR final incorreto no programa%0d", POLYGONS);
        if (dut.scroll_x != (POLYGONS ? 0 : 32) || dut.scroll_y != 0 ||
            dut.u_sprite_engine.sat_ram[0][31])
            $fatal(1, "Scroll final ou desabilitacao do sprite legado incorretos");
        for (i = 1; i < 32; i = i+1)
            if (dut.u_sprite_engine.sat_ram[i] !== reference_sat[i] ||
                dut.u_sprite_engine.priority_ram[i] !== reference_priority[i][1:0] ||
                dut.u_sprite_engine.palette_bank_ram[i] !== reference_bank[i][3:0] ||
                dut.u_sprite_engine.palette_enable_ram[i] !== reference_bank_enabled[i])
                $fatal(1, "SAT/estilo final do sprite%0d incorreto no programa%0d", i, POLYGONS);
        for (i = 0; i < 256; i = i+1)
            if (dut.u_palette.clut_ram[i] !== reference_palette[i])
                $fatal(1, "Paleta final incorreta em indice%0d", i);
        for (i = 0; i < 1200; i = i+1)
            if (dut.u_bg_engine.u_map_buffer.map_ram[i] !== reference_map[i])
                $fatal(1, "Tilemap final incorreto em endereco%0d", i);
        for (y = 0; y < 240; y = y+1)
            for (x = 0; x < 320; x = x+1) begin
                expected_polygon = reference_polygon(x,y);
                if (dut.u_poly_buffer.ram[y*320+x] !== expected_polygon)
                    $fatal(1, "Framebuffer final programa%0d em (%0d,%0d): esperado%0d atual%0d",
                        POLYGONS,x,y,expected_polygon,dut.u_poly_buffer.ram[y*320+x]);
            end
        if (POLYGONS) begin
            if (dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[1] !== 56 ||
                dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[3] !== 120 ||
                dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[5] !== 88 ||
                dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[8] !== 0 ||
                dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[9] !== 96)
                $fatal(1, "Registradores finais da animacao poligonal incorretos");
        end else if (sprite2_positions != 5 ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[1] !== 32 ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[3] !== 104 ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[5] !== 0 ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[6] !== 110)
            $fatal(1, "Registradores finais da animacao background incorretos");

        verify_video = 1;
        repeat (8) @(negedge clock);
        samples = 0; active = 0; hs_low = 0; vs_low = 0; colored = 0;
        while (samples < 800*525) begin
            @(posedge clock); #2;
            if (!leds[3] || dut.cmd_valid || dut.execution_busy)
                $fatal(1, "HALT nao manteve a CPU parada durante VGA");
            if (pixel_clock) begin
                samples = samples+1;
                if (blank) active = active+1;
                if (!hs) hs_low = hs_low+1;
                if (!vs) vs_low = vs_low+1;
                if (blank && {red,green,blue} != 0) colored = colored+1;
            end
        end
        if (active != 640*480 || hs_low != 96*525 || vs_low != 2*800 ||
            colored == 0 || sync_n != 0 || mmio_waitrequest)
            $fatal(1, "Temporizacao VGA incorreta apos HALT programa%0d", POLYGONS);
        verify_video = 0;
        $display("PASS: programa%0d: movimento ULA,4 waits reais,%0d comandos,%0d swaps, framebuffer e quadro VGA completo independentes",
            POLYGONS, accepted, swaps);
        finished = 1;
    end
endmodule
