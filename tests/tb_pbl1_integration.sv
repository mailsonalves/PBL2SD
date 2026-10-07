`timescale 1ns/1ps
module tb_pbl1_integration;
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 4'hE;
    wire [9:0] leds;
    wire hs, vs, blank, sync_n, pixel_clock;
    wire [7:0] red, green, blue;
    gpu_de1_soc_top #(.USE_ACTIVE_FETCH(1), .PROGRAM_WORDS(17),
        .PROGRAM_FILE("programs/pbl1_validation.hex")) dut (
        .CLOCK_50(clock), .KEY(keys), .SW(10'd0), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green), .VGA_B(blue),
        .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n), .VGA_CLK(pixel_clock)
    );

    reg [7:0] tiles [0:16383];
    reg [7:0] tilemap [0:1199];
    reg [23:0] palette [0:255];
    initial begin
        $readmemh("tiles.hex", tiles);
        $readmemh("tilemap_data.hex", tilemap);
        $readmemh("palette.hex", palette);
        palette[255] = 24'hF80000;
        palette[53] = 24'h00FC00;
    end

    // Modelo direto da cena, independente dos registradores do pipeline RTL.
    function automatic [23:0] reference_rgb(input integer x, y, input bit active);
        integer tile, address, raw1, raw31, color_index, lx, ly;
        begin
            tile = int'(tilemap[(y/8)*40 + x/8]);
            color_index = int'(tiles[tile*64 + (y%8)*8 + x%8]);
            if (x >= 10 && y >= 10 && x+y <= 30) color_index = 255;
            if (x >= 10 && x < 26 && y >= 10 && y < 26) begin
                lx = x-10; ly = y-10;
                // Sprite31: imagem5, flipV, prioridade1, indice direto.
                tile = 5 + ((15-ly)/8)*2 + lx/8;
                address = tile*64 + ((15-ly)%8)*8 + lx%8;
                raw31 = int'(tiles[address]);
                if (raw31 != 0) color_index = raw31;
                // Sprite1: imagem1, prioridade3, banco3. Zero e transparente
                // antes do remapeamento e deixa aparecer sprite31/poligono.
                tile = 1 + (ly/8)*2 + lx/8;
                raw1 = int'(tiles[tile*64 + (ly%8)*8 + lx%8]);
                if (raw1%16 != 0) color_index = 48 + raw1%16;
            end
            reference_rgb = active ? palette[color_index] : 24'd0;
        end
    endfunction

    integer accepted = 0, errors = 0, swaps = 0, writes = 0;
    reg previous_front = 0;
    always @(posedge clock) begin
        if (dut.rst_n) begin
            if (dut.cmd_valid && dut.cmd_ready) accepted = accepted + 1;
            if (dut.cmd_error) errors = errors + 1;
            if (dut.buffer_swap_done) swaps = swaps + 1;
            if (dut.buf_we) begin
                writes = writes + 1;
                if (!dut.buffer_double_buffered || dut.buffer_front)
                    $fatal(1, "Desenho nao foi enviado ao buffer oculto");
                if (dut.u_poly_buffer.ram[dut.buf_wr_addr] !== 0)
                    $fatal(1, "Buffer visivel alterado antes do PRESENT");
            end
            if (dut.buffer_front != previous_front && !dut.vblank)
                $fatal(1, "Troca de buffer fora do intervalo vertical");
            previous_front = dut.buffer_front;
        end
    end

    reg [23:0] expected_rgb [0:2];
    reg [2:0] expected_hs, expected_vs, expected_blank;
    integer samples, active_samples, hs_low, vs_low, i, x, y;
    initial begin
        repeat (4) @(negedge clock);
        keys = 4'hF;
        wait (leds[3]);
        @(negedge clock);
        if (accepted != 16 || errors != 1 || swaps != 1 || writes != 76866)
            $fatal(1, "Contagens: comandos=%0d erros=%0d swaps=%0d writes=%0d",
                accepted, errors, swaps, writes);
        if (!leds[4] || !leds[5] || !leds[6] || !leds[7] || dut.execution_busy)
            $fatal(1, "Status final incorreto");
        for (i = 0; i < 76800; i = i+1) begin
            x = i%320; y = i/320;
            if (dut.u_poly_buffer.ram[i] !== 0 ||
                dut.u_poly_buffer.back_ram[i] !== ((x>=10 && y>=10 && x+y<=30) ? 8'hFF : 8'd0))
                $fatal(1, "Buffers incorretos em (%0d,%0d)", x, y);
        end

        active_samples = 0; hs_low = 0; vs_low = 0;
        // Dois ciclos aquecem a fila do modelo; depois medimos um quadro inteiro
        // nos pinos VGA, em 840000 ciclos de 50 MHz.
        for (samples = 0; samples < 840002; samples = samples+1) begin
            @(posedge clock);
            expected_rgb[2] = expected_rgb[1];
            expected_rgb[1] = expected_rgb[0];
            expected_rgb[0] = reference_rgb(int'(dut.pixel_x), int'(dut.pixel_y), dut.video_active);
            expected_hs = {expected_hs[1:0], dut.raw_hsync};
            expected_vs = {expected_vs[1:0], dut.raw_vsync};
            expected_blank = {expected_blank[1:0], dut.video_active};
            #1;
            if (samples >= 2) begin
                if ({red,green,blue} !== expected_rgb[2] || hs !== expected_hs[2] ||
                    vs !== expected_vs[2] || blank !== expected_blank[2])
                    $fatal(1, "VGA ciclo %0d: RGB=%h esperado=%h HS/VS/blank=%b%b%b esperado=%b%b%b",
                        samples, {red,green,blue}, expected_rgb[2], hs,vs,blank,
                        expected_hs[2],expected_vs[2],expected_blank[2]);
                if (blank) active_samples = active_samples+1;
                if (!hs) hs_low = hs_low+1;
                if (!vs) vs_low = vs_low+1;
                if (!leds[3] || dut.cmd_valid || accepted != 16 || sync_n !== 0)
                    $fatal(1, "HALT/status nao permaneceu estavel");
            end
        end
        if (active_samples != 614400 || hs_low != 100800 || vs_low != 3200)
            $fatal(1, "Temporizacao do quadro incorreta");
        $display("PASS: PBL1 integrado; 840000 ciclos VGA/RGB, alpha/prioridade/banco, triangulo, buffer oculto/PRESENT e comando invalido");
        $finish;
    end
    initial begin
        #40000000;
        $fatal(1, "Timeout na integracao PBL1");
    end
endmodule
