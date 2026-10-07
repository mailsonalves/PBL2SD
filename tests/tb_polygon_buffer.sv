`timescale 1ns/1ps

// Verifica o contrato observavel da camada: reset, leitura sincrona,
// desenho oculto e apresentacao de um quadro inteiro no intervalo vertical.
module tb_polygon_buffer;
    reg clk_wr = 0;
    reg clk_rd = 0;
    always #5 clk_wr = ~clk_wr;
    always #7 clk_rd = ~clk_rd;

    reg rst_n = 0;
    reg we = 0;
    reg [16:0] addr_wr = 0;
    reg [7:0] data_in = 0;
    reg [16:0] addr_rd = 0;
    reg config_valid = 0;
    reg double_buffer_enable = 0;
    reg swap_request = 0;
    reg frame_boundary = 0;
    wire [7:0] data_out;
    wire initialized, busy, front_buffer, double_buffered, swap_done;
    integer checks = 0;
    integer index;

    polygon_buffer dut (
        .clk_wr(clk_wr), .rst_n(rst_n), .we(we),
        .addr_wr(addr_wr), .data_in(data_in),
        .clk_rd(clk_rd), .addr_rd(addr_rd), .data_out(data_out),
        .config_valid(config_valid), .double_buffer_enable(double_buffer_enable),
        .swap_request(swap_request), .frame_boundary(frame_boundary),
        .initialized(initialized), .busy(busy), .front_buffer(front_buffer),
        .double_buffered(double_buffered), .swap_done(swap_done)
    );

    task automatic await_initialization;
        integer cycles, address;
        begin
            cycles = 0;
            while (!initialized) begin
                @(posedge clk_wr);
                #1;
                cycles = cycles + 1;
                if (cycles < 76800 && (!busy || initialized))
                    $fatal(1, "Limpeza terminou antes dos 76800 enderecos");
                if (!initialized && data_out !== 8'd0)
                    $fatal(1, "Pixel indefinido/exposto durante a limpeza");
                if (cycles > 76800)
                    $fatal(1, "Limpeza excedeu 76800 ciclos");
            end
            if (cycles != 76800 || busy || front_buffer || double_buffered)
                $fatal(1, "Estado incorreto apos inicializacao (%0d ciclos)", cycles);
            for (address = 0; address < 76800; address = address + 1) begin
                if (dut.ram[address] !== 0 || dut.back_ram[address] !== 0)
                    $fatal(1, "RAM nao limpa no endereco %0d", address);
                checks = checks + 2;
            end
        end
    endtask

    task automatic sample_pixel(input integer address, expected);
        reg [7:0] previous;
        begin
            @(negedge clk_rd);
            previous = data_out;
            addr_rd = 17'(address);
            #1;
            if (data_out !== previous)
                $fatal(1, "Leitura alterou a saida antes da borda do clock");
            @(posedge clk_rd);
            #1;
            if (data_out !== 8'(expected))
                $fatal(1, "Pixel %0d: esperado=%02h recebido=%02h",
                       address, 8'(expected), data_out);
            checks = checks + 1;
        end
    endtask

    task automatic write_pixel(input integer address, value);
        begin
            @(negedge clk_wr);
            addr_wr = 17'(address);
            data_in = 8'(value);
            we = 1;
            @(posedge clk_wr);
            #1;
            @(negedge clk_wr);
            we = 0;
        end
    endtask

    task automatic configure(input bit enabled);
        reg previous_front;
        begin
            @(negedge clk_wr);
            previous_front = front_buffer;
            config_valid = 1;
            double_buffer_enable = enabled;
            @(posedge clk_wr);
            #1;
            if (double_buffered !== enabled || front_buffer !== previous_front)
                $fatal(1, "Configuracao alterou o banco visivel ou ignorou o modo");
            @(negedge clk_wr);
            config_valid = 0;
        end
    endtask

    task automatic request_swap;
        begin
            @(negedge clk_wr);
            swap_request = 1;
            @(posedge clk_wr);
            #1;
            if (!busy || swap_done)
                $fatal(1, "Troca nao aguardou o intervalo vertical");
            @(negedge clk_wr);
            swap_request = 0;
        end
    endtask

    task automatic present_frame(input bit expected_front);
        begin
            @(negedge clk_wr);
            frame_boundary = 1;
            @(posedge clk_wr);
            #1;
            if (front_buffer !== expected_front || !swap_done || busy)
                $fatal(1, "Quadro nao apresentado corretamente no intervalo vertical");
            @(negedge clk_wr);
            frame_boundary = 0;
            @(posedge clk_wr);
            #1;
            if (swap_done)
                $fatal(1, "swap_done deve durar um ciclo");
        end
    endtask

    initial begin
        repeat (3) @(posedge clk_wr);
        #1;
        if (initialized || !busy || front_buffer || double_buffered || data_out !== 0)
            $fatal(1, "Estado incorreto durante reset");
        // Escritas externas sao ignoradas ate ambos os bancos estarem limpos.
        @(negedge clk_wr);
        rst_n = 1;
        we = 1;
        addr_wr = 17'd400;
        data_in = 8'hff;
        await_initialization;
        @(negedge clk_wr);
        we = 0;
        sample_pixel(0, 0);
        sample_pixel(400, 0);
        sample_pixel(76799, 0);
        sample_pixel(76800, 0);
        sample_pixel(131071, 0);

        // No modo simples a escrita altera o banco visivel.
        write_pixel(0, 8'h19);
        write_pixel(400, 8'h2a);
        write_pixel(76799, 8'h3b);
        write_pixel(76800, 8'hff);
        write_pixel(131071, 8'hff);
        sample_pixel(0, 8'h19);
        sample_pixel(400, 8'h2a);
        sample_pixel(76799, 8'h3b);

        // Uma fronteira sem pedido e um pedido em modo simples sao inofensivos.
        @(negedge clk_wr);
        swap_request = 1;
        frame_boundary = 1;
        @(posedge clk_wr);
        #1;
        if (front_buffer || busy || swap_done)
            $fatal(1, "Pedido em modo simples alterou o banco");
        @(negedge clk_wr);
        swap_request = 0;
        frame_boundary = 0;

        configure(1);
        // Monta parte do proximo quadro; cada leitura permanece no quadro antigo.
        for (index = 0; index < 64; index = index + 1) begin
            write_pixel(1000 + index, index + 1);
            sample_pixel(1000 + index, 0);
        end
        write_pixel(0, 8'h91);
        write_pixel(400, 8'ha2);
        write_pixel(76799, 8'hb3);
        sample_pixel(0, 8'h19);
        sample_pixel(400, 8'h2a);
        sample_pixel(76799, 8'h3b);
        // Sem pedido, frame_boundary nao troca o quadro.
        @(negedge clk_wr);
        frame_boundary = 1;
        @(posedge clk_wr);
        #1;
        if (front_buffer || swap_done || busy)
            $fatal(1, "Fronteira sem pedido trocou o quadro");
        @(negedge clk_wr);
        frame_boundary = 0;

        request_swap;
        repeat (5) begin
            @(posedge clk_wr);
            #1;
            if (!busy || front_buffer || swap_done)
                $fatal(1, "Banco mudou fora do intervalo vertical");
        end
        // Depois do pedido, nao e permitido alterar o quadro aguardando exibicao.
        write_pixel(400, 8'hff);
        sample_pixel(400, 8'h2a);
        present_frame(1);
        sample_pixel(0, 8'h91);
        sample_pixel(400, 8'ha2);
        sample_pixel(76799, 8'hb3);
        for (index = 0; index < 64; index = index + 1)
            sample_pixel(1000 + index, index + 1);

        // O antigo front passa a ser o back: preserva dados que nao foram escritos.
        write_pixel(400, 8'hc4);
        sample_pixel(400, 8'ha2);
        request_swap;
        present_frame(0);
        sample_pixel(0, 8'h19);
        sample_pixel(400, 8'hc4);
        sample_pixel(76799, 8'h3b);
        sample_pixel(1000, 0);

        // Pedido na propria fronteira espera se ha uma escrita no mesmo ciclo.
        @(negedge clk_wr);
        addr_wr = 17'd400;
        data_in = 8'hd5;
        we = 1;
        swap_request = 1;
        frame_boundary = 1;
        @(posedge clk_wr);
        #1;
        if (front_buffer || !busy || swap_done)
            $fatal(1, "Troca interrompeu uma escrita em andamento");
        @(negedge clk_wr);
        we = 0;
        swap_request = 0;
        frame_boundary = 0;
        present_frame(1);
        sample_pixel(400, 8'hd5);

        // Desativar o double buffer conserva o quadro e retorna a escrita direta.
        configure(0);
        write_pixel(400, 8'he6);
        sample_pixel(400, 8'he6);

        // Reset durante uma troca pendente invalida imediatamente os pixels.
        configure(1);
        request_swap;
        @(negedge clk_wr);
        rst_n = 0;
        #1;
        if (initialized || !busy || front_buffer || double_buffered || swap_done || data_out !== 0)
            $fatal(1, "Reset nao invalidou o quadro e os controles");
        repeat (3) @(posedge clk_wr);
        @(negedge clk_wr);
        rst_n = 1;
        await_initialization;
        sample_pixel(0, 0);
        sample_pixel(400, 0);
        sample_pixel(1000, 0);
        sample_pixel(76799, 0);

        $display("PASS tb_polygon_buffer: %0d checks, two-bank initialization, synchronous safe reads, single/double modes and frame-boundary swaps", checks);
        $finish;
    end

    initial begin
        #4000000;
        $fatal(1, "Timeout em tb_polygon_buffer");
    end
endmodule
