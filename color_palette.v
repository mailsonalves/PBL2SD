module color_palette (
    input  wire        clk,
    input  wire        we,
    input  wire [7:0]  wr_addr,
    input  wire [23:0] wr_data,
    input  wire [7:0]  rd_addr,
    output reg  [23:0] rgb_out
);

<<<<<<< HEAD
    // Infere blocos de memoria M10K na FPGA
    (* ramstyle = "M10K, no_rw_check" *) reg [23:0] clut_ram [0:255];

    // Carrega a paleta gerada pelo Python
    initial begin
        $readmemh("palette.hex", clut_ram);
=======
    reg [23:0] clut_ram [0:255];
    integer b, i;

    initial begin
        for (i = 0; i < 256; i = i + 1)
            clut_ram[i] = 24'h000000;

        // Preenche todos os 4 bancos (0x00, 0x40, 0x80, 0xC0) com a mesma paleta
        for (b = 0; b < 256; b = b + 64) begin
            clut_ram[b + 8'h00] = 24'h000000; // 0x00: Transparente
            clut_ram[b + 8'h01] = 24'h4EC0CA; // 0x01: Céu Azul Celeste
            clut_ram[b + 8'h02] = 24'hFFFFFF; // 0x02: Branco (Nuvens)
            clut_ram[b + 8'h03] = 24'h5EE270; // 0x03: Verde Claro (Canos)
            clut_ram[b + 8'h04] = 24'h009028; // 0x04: Verde Escuro (Sombra dos Canos)
            clut_ram[b + 8'h05] = 24'hDDE870; // 0x05: Faixa do Chão
            clut_ram[b + 8'h06] = 24'hD88038; // 0x06: Laranja/Marrom da Terra
            clut_ram[b + 8'h07] = 24'hC89820; // 0x07: Prédios ao Fundo
            clut_ram[b + 8'h08] = 24'h5EE270; // Espelho Verde Canos
            clut_ram[b + 8'h09] = 24'h009028; // Espelho Verde Sombra
            clut_ram[b + 8'h0A] = 24'h73BF2E; // Verde Médio
            clut_ram[b + 8'h0B] = 24'h558022; // Verde Oliva

            // Cores do Flappy Bird
            clut_ram[b + 8'h10] = 24'h000000; // Preto (Contorno / Pupila)
            clut_ram[b + 8'h11] = 24'hFFFFFF; // Branco (Olho / Asa)
            clut_ram[b + 8'h12] = 24'hF8D820; // Amarelo (Corpo)
            clut_ram[b + 8'h13] = 24'hC89820; // Ocre (Sombra)
            clut_ram[b + 8'h14] = 24'hF85820; // Laranja (Bico)
            clut_ram[b + 8'h15] = 24'hE83010; // Bico inferior
        end
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
    end

    always @(posedge clk) begin
        if (we)
            clut_ram[wr_addr] <= wr_data;
<<<<<<< HEAD
        
        rgb_out <= clut_ram[rd_addr];
    end

endmodule
=======
        rgb_out <= clut_ram[rd_addr];
    end

endmodule
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
