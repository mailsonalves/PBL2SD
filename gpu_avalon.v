// Slave Avalon-MM para integrar a GPU de busca ativa no Platform Designer.
// O endereco e em bytes. Bridge HPS, clocks e pinos pertencem ao sistema externo.
module gpu_avalon #(
    parameter integer PROGRAM_WORDS = 256,
    parameter PROGRAM_FILE = "programs/background_motion.hex"
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [5:0]  address,
    input  wire        read,
    input  wire        write,
    input  wire [31:0] writedata,
    input  wire [3:0]  byteenable,
    output wire [31:0] readdata,
    output wire        waitrequest,

    input  wire [3:0]  KEY,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDR,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire        VGA_CLK
);
    // GPU combina assert assincrono com liberacao sincronizada internamente.
    wire [3:0] core_keys = {KEY[3:1], KEY[0] && reset_n};

    gpu_core #(
        .USE_ACTIVE_FETCH(1'b1),
        .PROGRAM_WORDS(PROGRAM_WORDS),
        .PROGRAM_FILE(PROGRAM_FILE)
    ) u_core (
        .CLOCK_50(clk), .KEY(core_keys), .SW(SW), .LEDR(LEDR),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_BLANK_N(VGA_BLANK_N), .VGA_SYNC_N(VGA_SYNC_N), .VGA_CLK(VGA_CLK),
        .mmio_address(address), .mmio_read(read), .mmio_write(write),
        .mmio_writedata(writedata), .mmio_byteenable(byteenable),
        .mmio_readdata(readdata), .mmio_waitrequest(waitrequest)
    );
endmodule
