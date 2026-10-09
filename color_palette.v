module color_palette #(
    parameter PALETTE_FILE = "palette.hex"
) (
    input  wire        clk,
    input  wire        we,
    input  wire [7:0]  wr_addr,
    input  wire [23:0] wr_data,
    input  wire [7:0]  rd_addr,
    output reg  [23:0] rgb_out
);

`ifdef __ICARUS__
    // Workaround apenas do Icarus: nomes selecionados por ternario.
    // Quartus deve receber a string original, sem padding com bytes zero.
    localparam [8*256-1:0] PALETTE_FILE_BYTES = PALETTE_FILE;
`endif
    // Infere blocos de memoria M10K na FPGA
    (* ramstyle = "M10K, no_rw_check" *) reg [23:0] clut_ram [0:255];

    // Carrega a paleta gerada pelo Python
    initial begin
`ifdef __ICARUS__
        $readmemh(PALETTE_FILE_BYTES, clut_ram);
`else
        $readmemh(PALETTE_FILE, clut_ram);
`endif
    end

    always @(posedge clk) begin
        if (we)
            clut_ram[wr_addr] <= wr_data;
        
        rgb_out <= clut_ram[rd_addr];
    end

endmodule
