module tilemap_ram #(
    parameter TILEMAP_FILE = "tilemap_data.hex"
) (
    input  wire        clk_wr,
    input  wire        we,
    input  wire [5:0]  wr_x,       // 0 a 39
    input  wire [4:0]  wr_y,       // 0 a 29
    input  wire [7:0]  wr_tile_id,

    input  wire        clk_rd,
    input  wire [5:0]  rd_x,       // 0 a 39
    input  wire [4:0]  rd_y,       // 0 a 29
    output reg  [7:0]  rd_tile_id
);

`ifdef __ICARUS__
    // Workaround apenas do Icarus: nomes selecionados por ternario.
    // Quartus deve receber a string original, sem padding com bytes zero.
    localparam [8*256-1:0] TILEMAP_FILE_BYTES = TILEMAP_FILE;
`endif
    (* ramstyle = "M10K, no_rw_check" *) reg [7:0] map_ram [0:1199];

    // Carrega o cenario 40x30 gerado pelo Python
    initial begin
        rd_tile_id = 8'h00;
        // O arquivo completo e a unica fonte de inicializacao da RAM.
        // Uma segunda inicializacao por loop pode sobrescrever o HEX na sintese.
`ifdef __ICARUS__
        $readmemh(TILEMAP_FILE_BYTES, map_ram);
`else
        $readmemh(TILEMAP_FILE, map_ram);
`endif
    end

    wire [10:0] addr_wr = {1'b0, wr_y, 5'd0} + {3'd0, wr_y, 3'd0} + {5'd0, wr_x};
    wire [10:0] addr_rd = {1'b0, rd_y, 5'd0} + {3'd0, rd_y, 3'd0} + {5'd0, rd_x};

    always @(posedge clk_wr) begin
        // Validar cada eixo impede X=40 de escrever em X=0 da linha seguinte.
        if (we && wr_x < 6'd40 && wr_y < 5'd30)
            map_ram[addr_wr] <= wr_tile_id;
    end

    always @(posedge clk_rd) begin
        if (rd_x < 6'd40 && rd_y < 5'd30)
            rd_tile_id <= map_ram[addr_rd];
        else
            rd_tile_id <= 8'h00; 
    end

endmodule
