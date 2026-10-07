`timescale 1ns/1ps

// Conferencia isolada da ULA de desenho; a varredura/testes ficam no controlador.
module tb_raster_alu;
    reg signed [10:0] px, py, vx0, vy0, vx1, vy1, vx2, vy2;
    wire signed [21:0] e01, e12, e20, triangle_area;
    wire is_inside;
    raster_alu dut (.*);
    integer checked = 0;

    task automatic check_point(
        input integer point_x, point_y, ax, ay, bx, by, cx, cy,
        input bit expected_inside
    );
        integer ref01, ref12, ref20, ref_area;
        begin
            px = point_x[10:0]; py = point_y[10:0];
            vx0 = ax[10:0]; vy0 = ay[10:0];
            vx1 = bx[10:0]; vy1 = by[10:0];
            vx2 = cx[10:0]; vy2 = cy[10:0];
            ref01 = (point_x-ax)*(by-ay) - (point_y-ay)*(bx-ax);
            ref12 = (point_x-bx)*(cy-by) - (point_y-by)*(cx-bx);
            ref20 = (point_x-cx)*(ay-cy) - (point_y-cy)*(ax-cx);
            ref_area = (bx-ax)*(cy-ay) - (by-ay)*(cx-ax);
            #1;
            if ($signed(e01) != ref01 || $signed(e12) != ref12 ||
                $signed(e20) != ref20 || $signed(triangle_area) != ref_area)
                $fatal(1, "Aritmetica incorreta no ponto (%0d,%0d)", point_x, point_y);
            if (is_inside !== expected_inside)
                $fatal(1, "Dentro/fora incorreto no ponto (%0d,%0d): esperado=%b obtido=%b",
                       point_x, point_y, expected_inside, is_inside);
            checked = checked + 1;
        end
    endtask

    integer x, y;
    initial begin
        // Modelo de referencia simples: primeiro quadrante e x+y <= 8.
        for (y = 0; y <= 8; y = y + 1)
            for (x = 0; x <= 8; x = x + 1) begin
                check_point(x, y, 0, 0, 8, 0, 0, 8, x+y <= 8);
                check_point(x, y, 0, 0, 0, 8, 8, 0, x+y <= 8);
            end
        check_point(-1, 0, 0, 0, 8, 0, 0, 8, 0);
        check_point(0, -1, 0, 0, 8, 0, 0, 8, 0);
        check_point(9, 0, 0, 0, 8, 0, 0, 8, 0);
        check_point(0, 9, 0, 0, 8, 0, 0, 8, 0);
        check_point(20, 20, 10, 10, 20, 20, 30, 30, 0);
        check_point(20, 21, 10, 10, 20, 20, 30, 30, 0);
        check_point(25, 25, 25, 25, 25, 25, 25, 25, 0);
        check_point(319, 239, 318, 238, 322, 238, 318, 242, 1);
        check_point(320, 240, 318, 238, 322, 238, 318, 242, 1);
        check_point(324, 242, 318, 238, 322, 238, 318, 242, 0);
        check_point(319, 192, 0, 0, 511, 0, 0, 511, 1);
        check_point(319, 193, 0, 0, 511, 0, 0, 511, 0);
        check_point(511, 0, 0, 0, 511, 0, 0, 511, 1);
        check_point(0, 511, 0, 0, 0, 511, 511, 0, 1);
        if (checked != 176) $fatal(1, "Quantidade incompleta de pontos: %0d", checked);
        $display("PASS tb_raster_alu: %0d pontos; aritmetica, arestas, dois sentidos, degenerados e limites", checked);
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "Timeout global na ULA de desenho");
    end
endmodule
