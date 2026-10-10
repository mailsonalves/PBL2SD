`timescale 1ns/1ps

module tb_board_demo;
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 4'hE;
    wire [9:0] leds;
    wire hs, vs, blank, sync_n, pixel_clock;
    wire [7:0] red, green, blue;
    integer accepted = 0;

<<<<<<< HEAD
    // Modo legado explicito: o caminho original por botoes deve continuar selecionado.
    gpu_de1_soc_top #(.USE_ACTIVE_FETCH(0)) dut (
=======
    // Sem parametro: o caminho original por botoes deve continuar selecionado.
    gpu_de1_soc_top dut (
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
        .CLOCK_50(clock), .KEY(keys), .SW(10'd0), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green),
        .VGA_B(blue), .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n),
        .VGA_CLK(pixel_clock)
    );

    always @(posedge clock) begin
<<<<<<< HEAD
        if (keys[0] && dut.u_core.cmd_valid && dut.u_core.cmd_ready) begin
            case (accepted)
                0: if (dut.u_core.cmd_data !== 32'h50000100)
                       $fatal(1, "Primeiro scroll da demonstracao mudou");
                1: if (dut.u_core.cmd_data !== 32'h60000064)
=======
        if (keys[0] && dut.cmd_valid && dut.cmd_ready) begin
            case (accepted)
                0: if (dut.cmd_data !== 32'h50000100)
                       $fatal(1, "Primeiro scroll da demonstracao mudou");
                1: if (dut.cmd_data !== 32'h60000064)
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
                       $fatal(1, "Atualizacao original do passaro mudou");
                default: $fatal(1, "Comando inesperado na demonstracao");
            endcase
            accepted = accepted + 1;
        end
    end

    initial begin
        repeat (3) @(negedge clock);
        keys = 4'hF;
        wait (accepted == 2);
        @(negedge clock);
<<<<<<< HEAD
        if (leds[3] || dut.u_core.scroll_x != 1)
=======
        if (leds[3] || dut.scroll_x != 1)
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
            $fatal(1, "Demonstracao original nao preservada");
        $display("PASS: demonstracao original preservada: scroll e passaro");
        $finish;
    end

    initial begin
        #20000000;
        $fatal(1, "Timeout: demonstracao original nao enviou os comandos");
    end
endmodule
