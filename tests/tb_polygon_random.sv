`timescale 1ns/1ps

// Modelo inteiro independente: compara a mascara inteira da tela, sem consultar
// estados, coordenadas de varredura ou resultados internos do rasterizador.
module tb_polygon_random;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, start = 0, clear_screen = 0;
    reg [8:0] x0 = 0, y0 = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0;
    reg [7:0] color = 0;
    wire busy, buf_we;
    wire [16:0] buf_addr;
    wire [7:0] buf_data;
    polygon_rasterizer rasterizer (.*);

    reg signed [10:0] px, py, vx0, vy0, vx1, vy1, vx2, vy2;
    wire signed [21:0] e01, e12, e20, triangle_area;
    wire is_inside;
    raster_alu alu (.*);

    bit expected [0:76799];
    bit seen [0:76799];
    bit checking = 0;
    integer cases = 0, writes = 0, expected_writes = 0, total_writes = 0;
    integer alu_checks = 0;
    reg [7:0] expected_color;
    reg [31:0] random_state = 32'h9E3779B9;

    // A mesma sequencia em Icarus/Verilator, sem depender de $urandom.
    function automatic integer coordinate;
        begin
            random_state = random_state ^ (random_state << 13);
            random_state = random_state ^ (random_state >> 17);
            random_state = random_state ^ (random_state << 5);
            coordinate = int'(random_state & 32'h000001FF);
        end
    endfunction

    // Todas as coordenadas sao inteiros 0..511; produtos cabem em signed32.
    function automatic integer edge_value(input integer point_x, point_y,
        input integer ax, ay, bx, by);
        edge_value = (point_x-ax)*(by-ay) - (point_y-ay)*(bx-ax);
    endfunction

    function automatic bit reference_inside(input integer point_x, point_y,
        input integer ax, ay, bx, by, cx, cy);
        integer ab, bc, ca, area;
        begin
            ab = edge_value(point_x, point_y, ax, ay, bx, by);
            bc = edge_value(point_x, point_y, bx, by, cx, cy);
            ca = edge_value(point_x, point_y, cx, cy, ax, ay);
            area = (bx-ax)*(cy-ay) - (by-ay)*(cx-ax);
            reference_inside = area != 0 &&
                ((ab >= 0 && bc >= 0 && ca >= 0) ||
                 (ab <= 0 && bc <= 0 && ca <= 0));
        end
    endfunction

    task automatic check_alu(input integer point_x, point_y,
        input integer ax, ay, bx, by, cx, cy);
        integer ab, bc, ca, area;
        begin
            px = 11'(point_x); py = 11'(point_y);
            vx0 = 11'(ax); vy0 = 11'(ay);
            vx1 = 11'(bx); vy1 = 11'(by);
            vx2 = 11'(cx); vy2 = 11'(cy);
            ab = edge_value(point_x, point_y, ax, ay, bx, by);
            bc = edge_value(point_x, point_y, bx, by, cx, cy);
            ca = edge_value(point_x, point_y, cx, cy, ax, ay);
            area = (bx-ax)*(cy-ay) - (by-ay)*(cx-ax);
            #1;
            if ($signed(e01) != ab || $signed(e12) != bc || $signed(e20) != ca ||
                $signed(triangle_area) != area ||
                is_inside !== reference_inside(point_x, point_y, ax, ay, bx, by, cx, cy))
                $fatal(1, "ULA: P(%0d,%0d) A(%0d,%0d) B(%0d,%0d) C(%0d,%0d): e=%0d,%0d,%0d area=%0d",
                    point_x,point_y,ax,ay,bx,by,cx,cy,e01,e12,e20,triangle_area);
            alu_checks = alu_checks + 1;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (rst_n && buf_we) begin
            if (!checking) $fatal(1, "Escrita fora de operacao aceita");
            if (buf_addr >= 76800) $fatal(1, "Escrita fora da tela: %0d", buf_addr);
            if (buf_data !== expected_color)
                $fatal(1, "Cor alterada durante busy no caso %0d", cases);
            if (!expected[buf_addr] || seen[buf_addr])
                $fatal(1, "Pixel inesperado/duplicado no caso %0d: %0d", cases, buf_addr);
            seen[buf_addr] = 1;
            writes = writes + 1;
            total_writes = total_writes + 1;
            if (total_writes >= 1000000) $fatal(1, "Orcamento do teste excedeu um milhao de pixels");
        end
    end

    task automatic draw(input integer ax, ay, bx, by, cx, cy);
        integer address, point_x, point_y, cycles;
        begin
            cases = cases + 1;
            writes = 0; expected_writes = 0;
            expected_color = 8'(cases);
            for (point_y = 0; point_y < 240; point_y = point_y + 1)
                for (point_x = 0; point_x < 320; point_x = point_x + 1) begin
                    address = point_y*320 + point_x;
                    expected[address] = reference_inside(point_x, point_y, ax, ay, bx, by, cx, cy);
                    seen[address] = 0;
                    if (expected[address]) expected_writes = expected_writes + 1;
                end
            checking = 1;
            @(negedge clk);
            x0 = 9'(ax); y0 = 9'(ay); x1 = 9'(bx); y1 = 9'(by);
            x2 = 9'(cx); y2 = 9'(cy); color = expected_color;
            clear_screen = 0; start = 1;
            @(posedge clk); #2;
            if (!busy) $fatal(1, "start nao foi aceito no caso %0d", cases);
            @(negedge clk);
            start = 0;
            // Muda todos os inputs durante busy. A operacao deve usar a captura.
            x0 = ~x0; y0 = ~y0; x1 = ~x1; y1 = ~y1; x2 = ~x2; y2 = ~y2;
            color = ~expected_color; clear_screen = 1;
            cycles = 0;
            while (busy && cycles < 262150) begin
                @(posedge clk); #2;
                cycles = cycles + 1;
            end
            if (busy) $fatal(1, "Timeout de varredura no caso %0d", cases);
            // busy pode cair junto da ultima escrita registrada.
            @(posedge clk); #2;
            if (buf_we) $fatal(1, "Escrita depois da conclusao no caso %0d", cases);
            if (writes != expected_writes)
                $fatal(1, "Caso %0d: pixels=%0d esperado=%0d", cases, writes, expected_writes);
            for (address = 0; address < 76800; address = address + 1)
                if (seen[address] != expected[address])
                    $fatal(1, "Mascara incorreta no caso %0d: endereco %0d", cases, address);
            checking = 0;
        end
    endtask

    task automatic permutations(input integer ax, ay, bx, by, cx, cy);
        begin
            draw(ax,ay,bx,by,cx,cy); draw(ax,ay,cx,cy,bx,by);
            draw(bx,by,ax,ay,cx,cy); draw(bx,by,cx,cy,ax,ay);
            draw(cx,cy,ax,ay,bx,by); draw(cx,cy,bx,by,ax,ay);
        end
    endtask

    task automatic both_windings(input integer ax, ay, bx, by, cx, cy);
        begin draw(ax,ay,bx,by,cx,cy); draw(ax,ay,cx,cy,bx,by); end
    endtask

    integer index, ax, ay, bx, by, cx, cy, point_x, point_y;
    initial begin
        // Todos os extremos das oito coordenadas da ULA, incluindo area maxima.
        for (index = 0; index < 256; index = index + 1)
            check_alu(index[6] ? 511 : 0, index[7] ? 511 : 0,
                      index[0] ? 511 : 0, index[1] ? 511 : 0,
                      index[2] ? 511 : 0, index[3] ? 511 : 0,
                      index[4] ? 511 : 0, index[5] ? 511 : 0);
        for (index = 0; index < 4096; index = index + 1) begin
            point_x = coordinate(); point_y = coordinate();
            ax = coordinate(); ay = coordinate(); bx = coordinate(); by = coordinate();
            cx = coordinate(); cy = coordinate();
            check_alu(point_x,point_y,ax,ay,bx,by,cx,cy);
        end
        // Reinicia a seed para manter a geometria independente dos testes da ULA.
        random_state = 32'h9E3779B9;
        @(negedge clk); rst_n = 1;
        for (index = 0; index < 64; index = index + 1) begin
            ax = coordinate(); ay = coordinate(); bx = coordinate(); by = coordinate();
            cx = coordinate(); cy = coordinate();
            draw(ax,ay,bx,by,cx,cy);
        end
        permutations(10,10,30,10,17,25);
        permutations(318,238,511,238,318,511);
        both_windings(318,238,320,238,318,240);
        both_windings(319,239,511,239,319,511);
        both_windings(320,0,511,0,320,239);
        both_windings(0,240,319,240,0,511);
        both_windings(319,0,320,239,318,239);
        both_windings(0,0,511,1,1,239);
        both_windings(0,0,319,0,319,239);
        both_windings(255,255,256,255,255,256);
        draw(10,10,11,10,10,11);
        draw(0,0,511,510,510,509);
        draw(511,511,511,511,511,511);
        draw(0,0,255,255,511,511);
        draw(319,239,319,239,0,0);
        draw(0,0,511,0,0,511);
        draw(400,300,511,300,400,511);
        draw(0,239,319,239,511,239);
        if (cases != 100 || alu_checks != 4352)
            $fatal(1, "Cobertura incompleta: %0d triangulos e %0d pontos ULA", cases, alu_checks);
        $display("PASS tb_polygon_random: seed=9E3779B9, %0d triangulos/%0d escritas, %0d pontos ULA; extremos, winding, clipping, degenerados e captura",
                 cases, total_writes, alu_checks);
        $finish;
    end
    initial begin #300000000; $fatal(1, "Timeout tb_polygon_random"); end
endmodule
