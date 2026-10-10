module pattern_vram (
    input  wire        clk,
<<<<<<< HEAD
    // Porta A (Background)
=======
    
    // Porta A: Background (Ligada no bg_vram_addr)
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
    input  wire        we_a,
    input  wire [13:0] addr_a,
    input  wire [7:0]  data_in_a,
    output reg  [7:0]  data_out_a,
<<<<<<< HEAD
    
    // Porta B (Sprites)
=======

    // Porta B: Auxiliar / Sprites
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
    input  wire [13:0] addr_b,
    output reg  [7:0]  data_out_b
);

    (* ramstyle = "M10K, no_rw_check" *) reg [7:0] ram [0:16383];

    initial begin
        $readmemh("tiles.hex", ram);
    end

<<<<<<< HEAD
    always @(posedge clk) begin
        if (we_a) ram[addr_a] <= data_in_a;
        data_out_a <= ram[addr_a];
    end

    always @(posedge clk) begin
        data_out_b <= ram[addr_b];
    end
endmodule
=======
    // Porta A: Leitura 100% fiel do tiles.hex
    always @(posedge clk) begin
        if (we_a)
            ram[addr_a] <= data_in_a;
        data_out_a <= ram[addr_a];
    end

    // Porta B
    always @(posedge clk) begin
        data_out_b <= ram[addr_b];
    end

endmodule
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
