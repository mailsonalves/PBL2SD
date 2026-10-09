`timescale 1ns/1ps
// Executar com Icarus: quatro estados para detectar X que Verilator nao modela.
module tb_initialization #(
    parameter USE_PROGRAMMABLE_CORE = 0,
    parameter SHOWCASE = 0
);
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 4'hE;
    wire [9:0] leds;
    wire hs, vs, blank, sync_n, pixel_clock;
    wire [7:0] red, green, blue;
    gpu_de1_soc_top #(.USE_PROGRAMMABLE_CORE(USE_PROGRAMMABLE_CORE), .SHOWCASE(SHOWCASE),
        .USE_ACTIVE_FETCH(1), .PROGRAM_WORDS(1),
        .PROGRAM_FILE("tests/fixtures/halt.hex")) dut (
        .CLOCK_50(clock), .KEY(keys), .SW(10'd0), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green), .VGA_B(blue),
        .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n), .VGA_CLK(pixel_clock)
    );
    integer n, i, resets, initialized_checks = 0;
    initial begin
        for (resets = 0; resets < 2; resets = resets+1) begin
            keys = 4'hE;
            repeat (4) @(negedge clock);
            keys = 4'hF;
            for (n = 0; n < 78000; n = n+1) begin
                @(posedge clock); #1;
                if (^{red,green,blue,hs,vs,blank,sync_n,pixel_clock,leds} === 1'bx)
                    $fatal(1, "Saida indefinida no ciclo %0d reset %0d", n, resets);
                if (!dut.buffer_initialized && {red,green,blue} !== 24'd0)
                    $fatal(1, "Video nao ficou preto durante inicializacao");
                if (n > 4 && ^{dut.sp_pixel, dut.poly_pixel, dut.final_pixel_idx,
                    dut.cmd_ready, dut.rast_busy, dut.sprite_busy, dut.buffer_busy} === 1'bx)
                    $fatal(1, "Estado de controle/pixel indefinido no ciclo %0d", n);
                if (dut.buffer_initialized) initialized_checks = initialized_checks+1;
            end
            if (!leds[3] || !dut.buffer_initialized || dut.sprite_busy)
                $fatal(1, "Inicializacao nao terminou");
            for (i = 0; i < 76800; i = i+1)
                if (dut.u_poly_buffer.ram[i] !== 0 || dut.u_poly_buffer.back_ram[i] !== 0)
                    $fatal(1, "RAM nao inicializada em %0d", i);
        end
        $display("PASS: Icarus quatro estados CPU=%0d SHOWCASE=%0d; dois resets, 156000 ciclos sem X nos pinos/controle e buffers inicializados",
            USE_PROGRAMMABLE_CORE, SHOWCASE);
        $finish;
    end
    initial begin
        #5000000;
        $fatal(1, "Timeout na inicializacao");
    end
endmodule
