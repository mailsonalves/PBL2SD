`timescale 1ns/1ps

// Valida o produtor ready/valid sem depender do tempo de um quadro real.
// Os ticks injetados aceleram somente o teste; a fisica do controlador roda.
module tb_board_handshake;
    reg clock = 0;
    always #10 clock = ~clock;
    reg rst_n = 0;
    reg [3:1] keys = 3'b111;
    reg allow_accept = 0;
    reg dispatch_pending = 0;
    integer busy_cycles = 0;
    wire ready = allow_accept && !dispatch_pending && (busy_cycles == 0);
    wire [31:0] data;
    wire valid;
    reg [31:0] expected [0:11];
    integer accepted = 0;
    integer stalled = 0;
    integer delay_cycles = 0;
    reg was_stalled = 0;
    reg [31:0] held_data = 0;
    reg pattern_enabled = 0;
    integer phase = 0;
    integer physics_ticks = 0;

    board_input_controller dut (
        .clk(clock), .rst_n(rst_n), .SW(10'd0), .KEY(keys),
        .cmd_ready(ready), .cmd_data(data), .cmd_valid(valid)
    );

    // Simula a protecao entre aceitar o comando e a unidade ficar ocupada
    // no ciclo seguinte, como o decodificador faz para o rasterizador.
    always @(posedge clock) begin
        if (!rst_n) begin
            dispatch_pending <= 0;
            busy_cycles <= 0;
            was_stalled <= 0;
        end else begin
            if ((^{valid, ready, data}) === 1'bx)
                $fatal(1, "Saida indefinida no controlador de botoes");
            if (was_stalled && (!valid || data !== held_data))
                $fatal(1, "Comando mudou enquanto aguardava ready");
            was_stalled <= valid && !ready;
            held_data <= data;
            if (valid && !ready) stalled = stalled + 1;

            dispatch_pending <= 0;
            if (dispatch_pending) begin
                busy_cycles <= 5;
                delay_cycles = delay_cycles + 1;
            end else if (busy_cycles != 0) begin
                busy_cycles <= busy_cycles - 1;
            end

            if (valid && ready) begin
                if (accepted >= 12 || data !== expected[accepted])
                    $fatal(1, "Comando %0d incorreto: %08x", accepted, data);
                accepted = accepted + 1;
                if (data[31:28] == 4'h9 || data[31:24] == 8'h0f)
                    dispatch_pending <= 1;
            end
        end
    end

    always @(negedge clock) begin
        if (pattern_enabled) begin
            phase = phase + 1;
            allow_accept = ((phase % 7) >= 3);
        end
    end

    task automatic tick_frame;
        @(negedge clock);
        dut.frame_cnt = 20'd833333;
        @(negedge clock);
    endtask

    task automatic check_physics;
        begin
            if ($signed(dut.bird_y_sub) < 0 || $signed(dut.bird_y_sub) > 3040 ||
                dut.current_bird_y > 190 || $signed(dut.velocity_y) < -60 ||
                $signed(dut.velocity_y) > 96)
                $fatal(1, "Fisica ultrapassou limites: posicao=%0d velocidade=%0d",
                       $signed(dut.bird_y_sub), $signed(dut.velocity_y));
            physics_ticks = physics_ticks + 1;
        end
    endtask

    task automatic flap;
        begin
            @(negedge clock);
            keys[1] = 0;
            repeat (5) @(negedge clock);
            keys[1] = 1;
            repeat (5) @(negedge clock);
        end
    endtask

    integer frame;

    initial begin
        expected[0] = 32'h50000100;
        expected[1] = 32'h60000064;
        expected[2] = {4'h7, 8'h00, 3'b000, 9'd160, 8'd50};
        expected[3] = {4'h8, 8'h00, 3'b000, 9'd80, 8'd190};
        expected[4] = {4'h9, 8'hff, 3'b000, 9'd240, 8'd190};
        expected[5] = {4'h7, 8'h00, 3'b000, 9'd100, 8'd100};
        expected[6] = {4'h8, 8'h00, 3'b000, 9'd100, 8'd150};
        expected[7] = {4'h9, 8'h04, 3'b000, 9'd220, 8'd100};
        expected[8] = {4'h7, 8'h00, 3'b000, 9'd220, 8'd100};
        expected[9] = {4'h8, 8'h00, 3'b000, 9'd100, 8'd150};
        expected[10] = {4'h9, 8'h04, 3'b000, 9'd220, 8'd150};
        expected[11] = 32'h0f000000;

        repeat (3) @(negedge clock);
        rst_n = 1;
        tick_frame();
        wait (valid);
        // Os dois cliques ficam pendentes durante a espera do scroll.
        @(negedge clock);
        keys[2] = 0;
        keys[3] = 0;
        repeat (5) @(negedge clock);
        keys = 3'b111;
        repeat (5) @(negedge clock);
        // Mesmo com a fisica avancando, o primeiro comando nao pode mudar.
        tick_frame();
        repeat (8) @(negedge clock);
        if (dut.bg_scroll_x != 2 || data !== expected[0] || accepted != 0)
            $fatal(1, "Captura de frame nao preservou o comando pendente");
        pattern_enabled = 1;

        // Expiracao do temporizador durante o retangulo deixa CLEAR pendente.
        wait (accepted == 8);
        @(negedge clock);
        dut.shape_timer = 8'd1;
        dut.frame_cnt = 20'd833333;
        wait (accepted == 12);
        repeat (32) @(negedge clock);
        if (valid || accepted != 12 || stalled < 20 || delay_cycles != 4)
            $fatal(1, "Perda, repeticao ou esperas nao exercitadas");

        // Reset cancela com seguranca um comando que ainda nao foi aceito.
        pattern_enabled = 0;
        allow_accept = 0;
        tick_frame();
        wait (valid);
        @(negedge clock);
        rst_n = 0;
        #1;
        if (valid || data !== 0)
            $fatal(1, "Reset deixou um comando pendente");
        @(negedge clock);
        rst_n = 1;
        // Queda longa deve chegar ao chao sem overflow da posicao signed.
        for (frame = 0; frame < 200; frame = frame + 1) begin
            tick_frame();
            check_physics();
        end
        if (dut.current_bird_y != 190 || dut.bird_y_sub != 13'sd3040)
            $fatal(1, "Passaro nao estabilizou no chao");
        // Impulso real do botao deve funcionar inclusive quando esta no chao.
        flap();
        tick_frame();
        check_physics();
        tick_frame();
        check_physics();
        if (dut.current_bird_y >= 190)
            $fatal(1, "Pulo no chao foi ignorado");
        // Impulsos repetidos alcancam o teto e nunca produzem Y negativo.
        for (frame = 0; frame < 80; frame = frame + 1) begin
            flap();
            tick_frame();
            check_physics();
        end
        if (dut.bird_y_sub != 13'sd0 || dut.current_bird_y != 0)
            $fatal(1, "Passaro nao estabilizou no teto");
        // Sem novos impulsos, a gravidade volta a leva-lo ao chao.
        for (frame = 0; frame < 200; frame = frame + 1) begin
            tick_frame();
            check_physics();
        end
        if (dut.current_bird_y != 190 || dut.bird_y_sub != 13'sd3040)
            $fatal(1, "Queda depois do teto nao chegou ao chao");
        $display("PASS: 12 comandos, stalls, busy atrasado, cliques, clear, reset e %0d ticks de fisica", physics_ticks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Timeout no protocolo dos botoes");
    end
endmodule
