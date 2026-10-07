// Datapath combinacional especializado: funcoes de aresta para preenchimento.
// Nao e a ULA geral de instrucoes prevista para a arquitetura do PBL2.
module raster_alu (
    input  wire signed [10:0] px, py,
    input  wire signed [10:0] vx0, vy0, vx1, vy1, vx2, vy2,
    output wire signed [21:0] e01, e12, e20,
    output wire signed [21:0] triangle_area,
    output wire              is_inside
);
    assign e01 = (px - vx0) * (vy1 - vy0) - (py - vy0) * (vx1 - vx0);
    assign e12 = (px - vx1) * (vy2 - vy1) - (py - vy1) * (vx2 - vx1);
    assign e20 = (px - vx2) * (vy0 - vy2) - (py - vy2) * (vx0 - vx2);
    assign triangle_area =
        (vx1 - vx0) * (vy2 - vy0) - (vy1 - vy0) * (vx2 - vx0);

    // Arestas inclusivas e aceitas nos dois sentidos. Area nula e vazia.
    assign is_inside = (triangle_area != 0) &&
        ((e01 >= 0 && e12 >= 0 && e20 >= 0) ||
         (e01 <= 0 && e12 <= 0 && e20 <= 0));
endmodule
