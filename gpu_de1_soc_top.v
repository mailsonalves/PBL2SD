module gpu_de1_soc_top #(
    // Busca ativa principal; modo 0 conserva a demonstracao historica.
    parameter USE_ACTIVE_FETCH = 1'b1,
    parameter integer PROGRAM_WORDS = 256,
    parameter PROGRAM_FILE = "programs/background_motion.hex"
) (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDR,

    // Conexoes VGA DE1-SoC
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire        VGA_CLK
);

    // Mantem apenas os pinos existentes da DE1-SoC. A futura ponte HPS
    // conecta a interface MMIO de gpu_core no Platform Designer.
    gpu_core #(.USE_ACTIVE_FETCH(USE_ACTIVE_FETCH),
               .PROGRAM_WORDS(PROGRAM_WORDS), .PROGRAM_FILE(PROGRAM_FILE)) u_core (
        .CLOCK_50(CLOCK_50), .KEY(KEY), .SW(SW), .LEDR(LEDR),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_BLANK_N(VGA_BLANK_N), .VGA_SYNC_N(VGA_SYNC_N), .VGA_CLK(VGA_CLK),
        .mmio_address(6'd0), .mmio_read(1'b0), .mmio_write(1'b0),
        .mmio_writedata(32'd0), .mmio_byteenable(4'd0),
        .mmio_readdata(), .mmio_waitrequest()
    );
endmodule
