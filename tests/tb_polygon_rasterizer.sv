`timescale 1ns/1ps

// Contrato funcional: operacao atomica, arestas inclusivas e area zero vazia.
module tb_polygon_rasterizer;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, start = 0, clear_screen = 0;
    reg [8:0] x0 = 0, y0 = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0;
    reg [7:0] color = 0;
    wire busy, buf_we;
    wire [16:0] buf_addr;
    wire [7:0] buf_data;

    polygon_rasterizer dut (.*);

    bit expected [0:76799];
    bit seen [0:76799];
    bit rectangle_seen [0:76799];
    bit checking = 0, checking_clear = 0;
    reg [7:0] expected_color;
    integer writes = 0, expected_writes = 0, completed = 0;
    integer total_writes = 0;

    // Amostra as saidas registradas apos a atualizacao NBA.
    always @(posedge clk) begin
        #1;
        if (rst_n && buf_we) begin
            if (!checking) $fatal(1, "Escrita fora de uma operacao aceita");
            if (buf_addr >= 76800) $fatal(1, "Endereco fora da tela: %0d", buf_addr);
            if (buf_data !== expected_color)
                $fatal(1, "Cor mudou durante busy: esperada=%02h obtida=%02h",
                       expected_color, buf_data);
            if (!expected[buf_addr]) $fatal(1, "Pixel inesperado: %0d", buf_addr);
            if (seen[buf_addr]) $fatal(1, "Pixel duplicado na mesma operacao: %0d", buf_addr);
            if (checking_clear && buf_addr != writes)
                $fatal(1, "CLEAR fora de ordem: esperado=%0d obtido=%0d", writes, buf_addr);
            seen[buf_addr] = 1;
            writes = writes + 1;
            total_writes = total_writes + 1;
        end
    end

    task automatic prepare(input bit clearing, input [7:0] pixel_color);
        integer a;
        begin
            checking = 1;
            checking_clear = clearing;
            expected_color = pixel_color;
            writes = 0;
            expected_writes = clearing ? 76800 : 0;
            for (a = 0; a < 76800; a = a + 1) begin
                expected[a] = clearing;
                seen[a] = 0;
            end
        end
    endtask

    // Modelo geometrico independente usa coordenadas e enderecamento inteiros.
    task automatic triangle_model(input integer ax, ay, bx, by, cx, cy);
        integer px, py, ab, bc, ca, area, address;
        begin
            area = (bx-ax)*(cy-ay) - (by-ay)*(cx-ax);
            for (py = 0; py < 240; py = py + 1)
                for (px = 0; px < 320; px = px + 1) begin
                    ab = (bx-ax)*(py-ay) - (by-ay)*(px-ax);
                    bc = (cx-bx)*(py-by) - (cy-by)*(px-bx);
                    ca = (ax-cx)*(py-cy) - (ay-cy)*(px-cx);
                    if (area != 0 &&
                        ((ab >= 0 && bc >= 0 && ca >= 0) ||
                         (ab <= 0 && bc <= 0 && ca <= 0))) begin
                        address = py*320+px;
                        expected[address] = 1;
                        expected_writes = expected_writes + 1;
                    end
                end
        end
    endtask

    task automatic launch(
        input integer ax, ay, bx, by, cx, cy,
        input [7:0] pixel_color, input bit clearing
    );
        begin
            @(negedge clk);
            x0 = ax[8:0]; y0 = ay[8:0];
            x1 = bx[8:0]; y1 = by[8:0];
            x2 = cx[8:0]; y2 = cy[8:0];
            color = pixel_color;
            clear_screen = clearing;
            start = 1;
            @(posedge clk);
            #2;
            if (!busy) $fatal(1, "start nao iniciou operacao");
            @(negedge clk);
            start = 0;
        end
    endtask

    task automatic finish_operation;
        integer cycles, a;
        begin
            cycles = 0;
            while (busy && cycles < 300000) begin
                @(posedge clk);
                #2;
                cycles = cycles + 1;
            end
            if (busy) $fatal(1, "Timeout com rasterizador ocupado");
            // A ultima escrita pode coincidir com busy=0; ja foi amostrada.
            @(posedge clk);
            #2;
            if (buf_we) $fatal(1, "Escrita repetida apos termino");
            if (writes != expected_writes)
                $fatal(1, "Quantidade incorreta: esperado=%0d obtido=%0d",
                       expected_writes, writes);
            for (a = 0; a < 76800; a = a + 1)
                if (seen[a] != expected[a]) $fatal(1, "Mascara incorreta no pixel %0d", a);
            checking = 0;
            completed = completed + 1;
        end
    endtask

    task automatic draw_triangle(
        input integer ax, ay, bx, by, cx, cy, input [7:0] pixel_color
    );
        begin
            prepare(0, pixel_color);
            triangle_model(ax, ay, bx, by, cx, cy);
            launch(ax, ay, bx, by, cx, cy, pixel_color, 0);
            finish_operation;
        end
    endtask

    task automatic assert_reset;
        begin
            @(negedge clk);
            rst_n = 0;
            start = 0;
            #2;
            if (busy || buf_we || buf_addr != 0 || buf_data != 0 ||
                dut.min_x != 0 || dut.max_x != 0 || dut.min_y != 0 || dut.max_y != 0 ||
                dut.curr_x != 0 || dut.curr_y != 0 || dut.vx0 != 0 || dut.vy0 != 0 ||
                dut.vx1 != 0 || dut.vy1 != 0 || dut.vx2 != 0 || dut.vy2 != 0 ||
                dut.latched_color != 0)
                $fatal(1, "Reset deixou estado nao inicializado");
            checking = 0;
            repeat (2) @(negedge clk);
            rst_n = 1;
            @(posedge clk);
            #2;
            if (busy || buf_we) $fatal(1, "Operacao ressuscitou apos reset");
        end
    endtask

    integer a, px, py, union_pixels;
    initial begin
        assert_reset;

        prepare(1, 8'h00);
        launch(0, 0, 0, 0, 0, 0, 8'hA5, 1);
        finish_operation;

        draw_triangle(10, 10, 12, 10, 10, 12, 8'h17);
        if (writes != 6 || !seen[10*320+10] || !seen[10*320+12] ||
            !seen[11*320+10] || !seen[11*320+11] || !seen[12*320+10])
            $fatal(1, "Triangulo de referencia nao produziu os seis pixels");
        draw_triangle(10, 10, 10, 12, 12, 10, 8'h29);
        if (writes != 6) $fatal(1, "Ordem inversa alterou preenchimento");

        draw_triangle(318, 238, 322, 238, 318, 242, 8'h35);
        if (writes != 4 || !seen[239*320+319])
            $fatal(1, "Recorte inferior/direito incorreto");
        draw_triangle(320, 240, 324, 240, 320, 244, 8'h45);
        if (writes != 0) $fatal(1, "Triangulo invisivel escreveu pixels");
        draw_triangle(0, 0, 511, 0, 0, 511, 8'h56);
        if (!seen[0] || !seen[239*320] || !seen[319])
            $fatal(1, "Triangulo grande nao respeitou as bordas da tela");
        draw_triangle(10, 10, 20, 20, 30, 30, 8'h67);
        if (writes != 0) $fatal(1, "Triangulo colinear deve ser vazio");
        draw_triangle(25, 25, 25, 25, 25, 25, 8'h68);

        // Muda todos os parametros apos start: operacao deve usar a captura.
        prepare(0, 8'h79);
        triangle_model(40, 40, 50, 40, 40, 50);
        launch(40, 40, 50, 40, 40, 50, 8'h79, 0);
        x0 = 300; y0 = 200; x1 = 310; y1 = 200; x2 = 300; y2 = 210;
        color = 8'hFF;
        clear_screen = 1;
        start = 1; // Um novo pedido enquanto busy nao pode substituir a operacao.
        repeat (4) @(negedge clk);
        start = 0;
        finish_operation;
        if (writes != 66) $fatal(1, "Vertices nao ficaram capturados");

        for (a = 0; a < 76800; a = a + 1) rectangle_seen[a] = 0;
        draw_triangle(20, 30, 24, 30, 20, 33, 8'h8A);
        for (a = 0; a < 76800; a = a + 1) rectangle_seen[a] = seen[a];
        draw_triangle(24, 30, 24, 33, 20, 33, 8'h8A);
        union_pixels = 0;
        for (a = 0; a < 76800; a = a + 1) begin
            rectangle_seen[a] = rectangle_seen[a] || seen[a];
            px = a % 320;
            py = a / 320;
            if (rectangle_seen[a] != (px >= 20 && px <= 24 && py >= 30 && py <= 33))
                $fatal(1, "Uniao dos triangulos nao formou retangulo no pixel %0d", a);
            if (rectangle_seen[a]) union_pixels = union_pixels + 1;
        end
        if (union_pixels != 20) $fatal(1, "Area incorreta do retangulo");

        // Reset cancela CLEAR antes do fim e uma nova operacao pode ser aceita.
        prepare(1, 8'h00);
        launch(0, 0, 0, 0, 0, 0, 8'h00, 1);
        repeat (20) @(negedge clk);
        if (!busy || writes == 0 || writes >= 76800)
            $fatal(1, "Teste de reset nao interrompeu operacao em andamento");
        assert_reset;
        draw_triangle(10, 10, 12, 10, 10, 12, 8'h9B);

        if (completed != 12) $fatal(1, "Nem todas as operacoes foram verificadas: %0d", completed);
        $display("PASS tb_polygon_rasterizer: %0d operacoes, %0d escritas; CLEAR, recorte, captura, degenerados, retangulo e reset",
                 completed, total_writes);
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1, "Timeout global: teste nao chegou ao fim");
    end
endmodule
