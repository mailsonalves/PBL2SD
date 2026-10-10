module color_palette (
    input  wire        clk,
    input  wire        we,
    input  wire [7:0]  wr_addr,
    input  wire [23:0] wr_data,
    input  wire [7:0]  rd_addr,
    output wire [23:0] rgb_out
);

    // A saida RAM pode ser indefinida durante colisao mixed-port M10K.
    // O bypass registrado abaixo mascara esse caso sem aumentar a latencia.
    (* ramstyle = "M10K, no_rw_check" *) reg [23:0] clut_ram [0:255];
    reg [23:0] ram_rgb;
    reg [23:0] forwarded_rgb;
    reg forward_hit;

    // Carrega a paleta gerada pelo Python
    initial begin
        $readmemh("palette.hex", clut_ram);
    end

    always @(posedge clk) begin
        if (we)
            clut_ram[wr_addr] <= wr_data;
        
        ram_rgb <= clut_ram[rd_addr];
        forward_hit <= we && wr_addr == rd_addr;
        if (we && wr_addr == rd_addr)
            forwarded_rgb <= wr_data;
    end

    // NEW_DATA deterministico, inclusive quando a RAM fisica fornece X.
    assign rgb_out = forward_hit ? forwarded_rgb : ram_rgb;

endmodule
