module gpu_de1_soc_top #(
    // A etapa 4 abre a galeria programavel por padrao, inclusive no Quartus GUI.
    // CPU=0 seleciona os caminhos historicos conforme USE_ACTIVE_FETCH.
    parameter USE_PROGRAMMABLE_CORE = 1'b1,
    parameter SHOWCASE = 1'b1,
    parameter USE_ACTIVE_FETCH = 1'b0,
    parameter integer PROGRAM_WORDS = 2626,
    parameter PROGRAM_FILE = "programs/showcase.hex",
    parameter integer BUTTON_DEBOUNCE_CYCLES = 250000
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

    // Assert assincrono; liberacao do reset sincronizada no clock do sistema.
    reg [1:0] reset_sync;
    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) reset_sync <= 2'b00;
        else reset_sync <= {reset_sync[0], 1'b1};
    end
    wire rst_n = reset_sync[1];

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
    wire raw_hsync, raw_vsync, vblank;
    wire [8:0] pixel_x;
    wire [7:0] pixel_y;

    vga_sync u_vga_sync (
        .clk_25m     (clk_25m),
        .rst_n       (rst_n),
        .hsync       (raw_hsync),
        .vsync       (raw_vsync),
        .video_active(video_active),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y),
        .vblank      (vblank)
    );

    reg previous_vblank;
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) previous_vblank <= 1'b0;
        else previous_vblank <= vblank;
    end
    wire frame_boundary = vblank && !previous_vblank;

    // 3. Fonte de comandos selecionada na compilacao
    wire [31:0] cmd_data;
    wire        cmd_valid;
    wire        cmd_ready;
    wire        rast_busy;
    wire        sprite_busy, buffer_busy;
    wire        buffer_initialized, buffer_front, buffer_double_buffered, buffer_swap_done;
    wire        execution_busy = rast_busy || sprite_busy || buffer_busy;
    wire        program_halted;
    wire [31:0] processor_status, processor_output;
    wire [11:0] processor_pc;
    wire [31:0] processor_ir;
    wire processor_retired;
    wire [9:0] processor_switches;
    wire [2:0] processor_keys;

    generate
        if (USE_PROGRAMMABLE_CORE) begin : gen_program_core
            showcase_inputs #(.DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES)) u_inputs (
                .clk(CLOCK_50), .rst_n(rst_n), .switches(SW), .keys_n(KEY[3:1]),
                .sw_state(processor_switches), .key_state(processor_keys)
            );
            gpu_program_core #(
                .ADDRESS_WIDTH(12), .PROGRAM_WORDS(PROGRAM_WORDS), .PROGRAM_FILE(PROGRAM_FILE)
            ) u_core (
                .clk(CLOCK_50), .rst_n(rst_n), .cmd_ready(cmd_ready),
                .execution_busy(execution_busy), .cmd_error(cmd_error),
                .frame_boundary(frame_boundary), .sw_state(processor_switches),
                .key_state(processor_keys), .buffer_initialized(buffer_initialized),
                .buffer_front(buffer_front), .buffer_double_buffered(buffer_double_buffered),
                .cmd_data(cmd_data), .cmd_valid(cmd_valid), .halted(program_halted),
                .pc(processor_pc), .ir(processor_ir), .status(processor_status),
                .user_output(processor_output), .retired(processor_retired)
            );
        end else if (USE_ACTIVE_FETCH) begin : gen_active_fetch
            assign processor_status = 0;
            assign processor_output = 0;
            assign processor_pc = 0;
            assign processor_ir = 0;
            assign processor_retired = 0;
            assign processor_switches = 0;
            assign processor_keys = 0;
            active_fetch_controller #(
                .PROGRAM_WORDS(PROGRAM_WORDS),
                .PROGRAM_FILE(PROGRAM_FILE)
            ) u_fetch (
                .clk(CLOCK_50),
                .rst_n(rst_n),
                .cmd_ready(cmd_ready),
                .execution_busy(execution_busy),
                .cmd_data(cmd_data),
                .cmd_valid(cmd_valid),
                .halted(program_halted),
                .pc(),
                .ir()
            );
        end else begin : gen_board_demo
            assign processor_status = 0;
            assign processor_output = 0;
            assign processor_pc = 0;
            assign processor_ir = 0;
            assign processor_retired = 0;
            assign processor_switches = 0;
            assign processor_keys = 0;
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
    wire        sprite_meta_we;
    wire [4:0]  sprite_meta_addr;
    wire [1:0]  sprite_priority;
    wire        sprite_palette_enable;
    wire [3:0]  sprite_palette_bank;
    wire        buffer_config_valid, buffer_double_enable, buffer_swap_request, cmd_error;
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
        .rast_busy        (rast_busy),
        .sprite_busy      (sprite_busy),
        .buffer_busy      (buffer_busy),
        .buffer_double_buffered(buffer_double_buffered),
        .sprite_meta_we   (sprite_meta_we),
        .sprite_meta_addr (sprite_meta_addr),
        .sprite_priority  (sprite_priority),
        .sprite_palette_enable(sprite_palette_enable),
        .sprite_palette_bank(sprite_palette_bank),
        .buffer_config_valid(buffer_config_valid),
        .buffer_double_enable(buffer_double_enable),
        .buffer_swap_request(buffer_swap_request),
        .cmd_error        (cmd_error)
    );

    // 5. Motor de Background
    wire [13:0] bg_vram_addr;

    bg_engine #(.TILEMAP_FILE(SHOWCASE ? "assets/showcase_tilemap.hex" : "tilemap_data.hex")) u_bg_engine (
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
    wire [7:0] sp_pixel;

    sprite_engine #(.PATTERN_FILE(SHOWCASE ? "assets/showcase_tiles.hex" : "tiles.hex")) u_sprite_engine (
        .clk               (CLOCK_50),
        .rst_n             (rst_n),
        .pixel_x           (pixel_x),
        .pixel_y           (pixel_y),
        .sat_we            (sat_we),
        .sat_addr          (sat_addr),
        .sat_data          (sat_data),
        .sat_write_mask    (sat_write_mask),
        .sp_vram_addr      (sp_vram_addr),
        .sp_pixel          (sp_pixel),
        .busy              (sprite_busy),
        .meta_we           (sprite_meta_we),
        .meta_addr         (sprite_meta_addr),
        .meta_priority     (sprite_priority),
        .meta_palette_enable(sprite_palette_enable),
        .meta_palette_bank (sprite_palette_bank)
    );

    // 5.2 VRAM Dual-Port
    wire [7:0] bg_pixel;
    wire [7:0] pattern_debug_pixel;

    pattern_vram #(.PATTERN_FILE(SHOWCASE ? "assets/showcase_tiles.hex" : "tiles.hex")) u_patterns (
        .clk        (CLOCK_50),
        .we_a       (1'b0),
        .addr_a     (bg_vram_addr),
        .data_in_a  (8'd0),
        .data_out_a (bg_pixel),
        .addr_b     (sp_vram_addr),
        .data_out_b (pattern_debug_pixel)
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
        .x0          (rast_x0), .y0({1'b0, rast_y0}),
        .x1          (rast_x1), .y1({1'b0, rast_y1}),
        .x2          (rast_x2), .y2({1'b0, rast_y2}),
        .color       (rast_color),
        .buf_we      (buf_we),
        .buf_addr    (buf_wr_addr),
        .buf_data    (buf_wr_data)
    );

    wire [16:0] buf_rd_addr = {pixel_y, 8'd0} + {pixel_y, 6'd0} + pixel_x;

    polygon_buffer u_poly_buffer (
        .clk_wr  (CLOCK_50),
        .rst_n   (rst_n),
        .we      (buf_we),
        .addr_wr (buf_wr_addr),
        .data_in (buf_wr_data),
        .clk_rd  (CLOCK_50),
        .addr_rd (buf_rd_addr),
        .data_out(poly_pixel),
        .config_valid(buffer_config_valid),
        .double_buffer_enable(buffer_double_enable),
        .swap_request(buffer_swap_request),
        .frame_boundary(frame_boundary),
        .initialized(buffer_initialized),
        .busy(buffer_busy),
        .front_buffer(buffer_front),
        .double_buffered(buffer_double_buffered),
        .swap_done(buffer_swap_done)
    );

    // 7. Compositor
    wire [7:0] final_pixel_idx;
    // Background: tilemap + pattern = 2 ciclos. Sprites e poligonos: RAM +
    // este registro = 2 ciclos. Paleta acrescenta o terceiro ciclo.
    reg [7:0] sp_pixel_aligned, poly_pixel_aligned;
    reg [2:0] active_pipe, hsync_pipe, vsync_pipe, initialized_pipe;
    reg error_seen;
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            sp_pixel_aligned <= 0;
            poly_pixel_aligned <= 0;
            active_pipe <= 0;
            hsync_pipe <= 3'b111;
            vsync_pipe <= 3'b111;
            initialized_pipe <= 0;
            error_seen <= 0;
        end else begin
            sp_pixel_aligned <= sp_pixel;
            poly_pixel_aligned <= poly_pixel;
            active_pipe <= {active_pipe[1:0], video_active};
            hsync_pipe <= {hsync_pipe[1:0], raw_hsync};
            vsync_pipe <= {vsync_pipe[1:0], raw_vsync};
            initialized_pipe <= {initialized_pipe[1:0], buffer_initialized};
            if (cmd_error) error_seen <= 1'b1;
        end
    end

    compositor u_compositor (
        .bg_pixel          (bg_pixel),
        .sp_pixel          (sp_pixel_aligned),
        .poly_pixel        (poly_pixel_aligned),
        .final_pixel_index (final_pixel_idx)
    );

    // 8. Paleta de Cores e Saida VGA
    wire [23:0] rgb_24;

    color_palette #(.PALETTE_FILE(SHOWCASE ? "assets/showcase_palette.hex" : "palette.hex")) u_palette (
        .clk    (CLOCK_50),
        .we     (pal_we),
        .wr_addr(pal_addr),
        .wr_data(pal_data),
        .rd_addr(final_pixel_idx),
        .rgb_out(rgb_24)
    );

    wire output_active = active_pipe[2] && initialized_pipe[2];
    assign VGA_BLANK_N = active_pipe[2];
    assign VGA_HS = hsync_pipe[2];
    assign VGA_VS = vsync_pipe[2];
    assign VGA_R = output_active ? rgb_24[23:16] : 8'd0;
    assign VGA_G = output_active ? rgb_24[15:8]  : 8'd0;
    assign VGA_B = output_active ? rgb_24[7:0]   : 8'd0;

    assign LEDR[0] = USE_PROGRAMMABLE_CORE ? processor_output[0] : execution_busy;
    assign LEDR[1] = USE_PROGRAMMABLE_CORE ? processor_output[1] : cmd_valid;
    assign LEDR[2] = USE_PROGRAMMABLE_CORE ? processor_output[2] : SW[0];
    assign LEDR[3] = program_halted;
    assign LEDR[4] = USE_PROGRAMMABLE_CORE ? processor_status[4] : error_seen;
    assign LEDR[5] = buffer_initialized;
    assign LEDR[6] = buffer_front;
    assign LEDR[7] = buffer_double_buffered;
    assign LEDR[8] = USE_PROGRAMMABLE_CORE ? execution_busy : sprite_busy;
    assign LEDR[9] = rst_n;

endmodule
