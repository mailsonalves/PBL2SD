module gpu_de1_soc_top #(
    // 0 preserva a demonstracao original; 1 executa o programa interno.
    parameter USE_ACTIVE_FETCH = 1'b0,
    parameter integer PROGRAM_WORDS = 9,
    parameter PROGRAM_FILE = "programs/fetch_demo.hex"
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

    wire rst_n = KEY[0];

    // 1. Clock Pixel 25 MHz
    reg clk_25m;
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) clk_25m <= 1'b0;
        else clk_25m <= ~clk_25m;
    end

    assign VGA_CLK    = clk_25m;
    assign VGA_SYNC_N = 1'b0;

    // 2. Gerador VGA
    wire video_active;
    wire [8:0] pixel_x;
    wire [7:0] pixel_y;

    vga_sync u_vga_sync (
        .clk_25m     (clk_25m),
        .rst_n       (rst_n),
        .hsync       (VGA_HS),
        .vsync       (VGA_VS),
        .video_active(video_active),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y)
    );

    assign VGA_BLANK_N = video_active;

    // 3. Fonte de comandos selecionada na compilacao
    wire [31:0] cmd_data;
    wire        cmd_valid;
    wire        cmd_ready;
    wire        rast_busy;
    wire        program_halted;

    generate
        if (USE_ACTIVE_FETCH) begin : gen_active_fetch
            active_fetch_controller #(
                .PROGRAM_WORDS(PROGRAM_WORDS),
                .PROGRAM_FILE(PROGRAM_FILE)
            ) u_fetch (
                .clk(CLOCK_50),
                .rst_n(rst_n),
                .cmd_ready(cmd_ready),
                .execution_busy(rast_busy),
                .cmd_data(cmd_data),
                .cmd_valid(cmd_valid),
                .halted(program_halted),
                .pc(),
                .ir()
            );
        end else begin : gen_board_demo
            assign program_halted = 1'b0;
            board_input_controller u_input_ctrl (
                .clk(CLOCK_50),
                .rst_n(rst_n),
                .SW(SW),
                .KEY(KEY[3:1]),
                .cmd_ready(cmd_ready),
                .cmd_data(cmd_data),
                .cmd_valid(cmd_valid)
            );
        end
    endgenerate

    // 4. Decodificador de Instrucoes
    wire        pal_we;
    wire [7:0]  pal_addr;
    wire [23:0] pal_data;
    wire        tm_we;
    wire [5:0]  tm_x;
    wire [4:0]  tm_y;
    wire [7:0]  tm_tile_id;
    wire [8:0]  scroll_x;
    wire [7:0]  scroll_y;
    wire        sat_we;
    wire [4:0]  sat_addr;
    wire [31:0] sat_data;
    wire [31:0] sat_write_mask;
    wire [8:0]  rast_x0, rast_x1, rast_x2;
    wire [7:0]  rast_y0, rast_y1, rast_y2;
    wire [7:0]  rast_color;
    wire        rast_clear_screen;
    wire        rast_start;

    cmd_decoder u_cmd_decoder (
        .clk              (CLOCK_50),
        .rst_n            (rst_n),
        .cmd_data         (cmd_data),
        .cmd_valid        (cmd_valid),
        .cmd_ready        (cmd_ready),
        .pal_we           (pal_we),
        .pal_addr         (pal_addr),
        .pal_data         (pal_data),
        .tm_we            (tm_we),
        .tm_x             (tm_x),
        .tm_y             (tm_y),
        .tm_tile_id       (tm_tile_id),
        .scroll_x         (scroll_x),
        .scroll_y         (scroll_y),
        .sat_we           (sat_we),
        .sat_addr         (sat_addr),
        .sat_data         (sat_data),
        .sat_write_mask   (sat_write_mask),
        .rast_x0          (rast_x0), .rast_y0(rast_y0),
        .rast_x1          (rast_x1), .rast_y1(rast_y1),
        .rast_x2          (rast_x2), .rast_y2(rast_y2),
        .rast_color       (rast_color),
        .rast_clear_screen(rast_clear_screen),
        .rast_start       (rast_start),
        .rast_busy        (rast_busy)
    );

    // 5. Motor de Background
    wire [13:0] bg_vram_addr;

    bg_engine u_bg_engine (
        .clk               (CLOCK_50),
        .pixel_x           (pixel_x),
        .pixel_y           (pixel_y),
        .scroll_x          (scroll_x),
        .scroll_y          (scroll_y),
        .we                (tm_we),
        .wr_x              (tm_x),
        .wr_y              (tm_y),
        .wr_tile_id        (tm_tile_id),
        .bg_vram_addr      (bg_vram_addr)
    );

    // 5.1 Motor de Sprites
    wire [13:0] sp_vram_addr;

    sprite_engine u_sprite_engine (
        .clk               (CLOCK_50),
        .rst_n             (rst_n),
        .pixel_x           (pixel_x),
        .pixel_y           (pixel_y),
        .sat_we            (sat_we),
        .sat_addr          (sat_addr),
        .sat_data          (sat_data),
        .sat_write_mask    (sat_write_mask),
        .sp_vram_addr      (sp_vram_addr)
    );

    // 5.2 VRAM Dual-Port
    wire [7:0] bg_pixel;
    wire [7:0] sp_pixel;

    pattern_vram u_patterns (
        .clk        (CLOCK_50),
        .we_a       (1'b0),
        .addr_a     (bg_vram_addr),
        .data_in_a  (8'd0),
        .data_out_a (bg_pixel),
        .addr_b     (sp_vram_addr),
        .data_out_b (sp_pixel)
    );

    // 6. Rasterizador e Framebuffer
    wire        buf_we;
    wire [16:0] buf_wr_addr;
    wire [7:0]  buf_wr_data;
    wire [7:0]  poly_pixel;

    polygon_rasterizer u_rasterizer (
        .clk         (CLOCK_50),
        .rst_n       (rst_n),
        .start       (rast_start),
        .clear_screen(rast_clear_screen),
        .busy        (rast_busy),
        .x0          (rast_x0), .y0(rast_y0),
        .x1          (rast_x1), .y1(rast_y1),
        .x2          (rast_x2), .y2(rast_y2),
        .color       (rast_color),
        .buf_we      (buf_we),
        .buf_addr    (buf_wr_addr),
        .buf_data    (buf_wr_data)
    );

    wire [16:0] buf_rd_addr = {pixel_y, 8'd0} + {pixel_y, 6'd0} + pixel_x;

    polygon_buffer u_poly_buffer (
        .clk_wr  (CLOCK_50),
        .we      (buf_we),
        .addr_wr (buf_wr_addr),
        .data_in (buf_wr_data),
        .clk_rd  (clk_25m),
        .addr_rd (buf_rd_addr),
        .data_out(poly_pixel)
    );

    // 7. Compositor
    wire [7:0] final_pixel_idx;

    compositor u_compositor (
        .bg_pixel          (bg_pixel),
        .sp_pixel          (sp_pixel),
        .poly_pixel        (poly_pixel),
        .final_pixel_index (final_pixel_idx)
    );

    // 8. Paleta de Cores e Saida VGA
    wire [23:0] rgb_24;

    color_palette u_palette (
        .clk    (CLOCK_50),
        .we     (pal_we),
        .wr_addr(pal_addr),
        .wr_data(pal_data),
        .rd_addr(final_pixel_idx),
        .rgb_out(rgb_24)
    );

    assign VGA_R = video_active ? rgb_24[23:16] : 8'd0;
    assign VGA_G = video_active ? rgb_24[15:8]  : 8'd0;
    assign VGA_B = video_active ? rgb_24[7:0]   : 8'd0;

    assign LEDR[0] = rast_busy;
    assign LEDR[1] = cmd_valid;
    assign LEDR[2] = SW[0];
    assign LEDR[3] = program_halted;
    assign LEDR[8:4] = 5'd0;
    assign LEDR[9] = rst_n;

endmodule
