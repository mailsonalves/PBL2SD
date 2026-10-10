`timescale 1ns/1ps
// VGA real, sem modificar RAM, PC ou contadores. O programa e infinito.
// Default:321 eventos completos de quadro, incluindo319->0->1 no scroll.
module tb_background_motion;
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 0;
    wire [9:0] leds;
    wire hs,vs,blank,sync_n,pixel_clock;
    wire [7:0] red,green,blue;
    wire [31:0] mmio_data;
    wire mmio_waitrequest;
    gpu_core #(.PROGRAM_WORDS(256), .PROGRAM_FILE("programs/background_motion.hex")) dut (
        .CLOCK_50(clock), .KEY(keys), .SW(10'd0), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green), .VGA_B(blue),
        .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n), .VGA_CLK(pixel_clock),
        .mmio_address(6'd0), .mmio_read(1'b0), .mmio_write(1'b0),
        .mmio_writedata(32'd0), .mmio_byteenable(4'd0),
        .mmio_readdata(mmio_data), .mmio_waitrequest(mmio_waitrequest)
    );

    reg [7:0] reference_patterns [0:16383];
    reg [7:0] reference_map [0:1199];
    reg [23:0] reference_palette [0:255];
    integer limit_frames = 321;
    integer hardware_frames = 0,scroll_updates = 0;
    bit initialization_scroll = 0;
    integer palette_writes = 0,tile_writes = 0,sprite_writes = 0;

    // Modelo externo: mesmos800x525 periodos, calculados sem hierarquia VGA.
    integer model_h = 0,model_v = 0,model_frames = 0;
    integer previous_h = 0,previous_v = 0;
    integer row_samples = 0,checked_rows = 0,checked_pixels = 0;
    integer source_x,tile,address,sample_h,sample_v;
    reg [23:0] expected_color;

    function automatic [23:0] background_rgb(input integer x,y,scroll);
        integer effective_x,tile_id,pattern_address;
        reg [7:0] index;
        begin
            effective_x = (x+scroll)%320;
            tile_id = reference_map[(y/8)*40+effective_x/8];
            pattern_address = tile_id*64+(y%8)*8+effective_x%8;
            index = reference_patterns[pattern_address];
            background_rgb = reference_palette[index];
        end
    endfunction

    always @(posedge clock) begin
        if (dut.rst_n) begin
            if (leds[3] || leds[4])
                $fatal(1,"Continuous background reached HALT/error at frame%0d PC%0d IR%h",
                    hardware_frames,dut.program_pc,dut.program_ir);
            if (dut.frame_boundary) begin
                if (hardware_frames > 0 && scroll_updates != hardware_frames)
                    $fatal(1,"Missing/repeated scroll: %0d updates for%0d frames",scroll_updates,hardware_frames);
                hardware_frames = hardware_frames+1;
                if (hardware_frames != model_frames)
                    $fatal(1,"VGA frame event differs from independent clock model: hw%0d model%0d",hardware_frames,model_frames);
            end
            if (dut.cmd_valid && dut.cmd_ready && dut.cmd_data[31:28] == 4'h5) begin
                if (!initialization_scroll) begin
                    if (dut.cmd_data !== 32'h50000000 || hardware_frames != 0)
                        $fatal(1,"Initial scroll must be zero before first VGA boundary");
                    initialization_scroll = 1;
                end else begin
                    if (!dut.vblank || hardware_frames != scroll_updates+1 ||
                        dut.cmd_data[16:8] != hardware_frames%320 || dut.cmd_data[7:0] != 0)
                        $fatal(1,"Scroll frame%0d: previous%0d,word%h,vblank%0b",hardware_frames,scroll_updates,dut.cmd_data,dut.vblank);
                    scroll_updates = scroll_updates+1;
                end
            end
            if (dut.pal_we) palette_writes = palette_writes+1;
            if (dut.tm_we) tile_writes = tile_writes+1;
            if (dut.sat_we) begin
                sprite_writes = sprite_writes+1;
                if (hardware_frames != 0)
                    $fatal(1,"Sprite configuration changed during background-only animation");
            end
        end
    end

    // RGB/BLANK atravessam3 CLOCK_50 stages. Na borda SUBIDA do DAC os
    // sinais estaticos ja estao estaveis e correspondem ao pixel fisico
    // anterior no modelo de contadores (as mudancas ocorrem na descida).
    // Cada linha testada e completa:640 amostras, no Yfisico360/Ylogico180.
    always @(posedge pixel_clock or negedge keys[0]) begin
        if (!keys[0]) begin
            model_h = 0; model_v = 0; model_frames = 0;
            previous_h = 0; previous_v = 0;
            row_samples = 0; checked_rows = 0; checked_pixels = 0;
        end else begin
            sample_h = previous_h; sample_v = previous_v;
            if (sample_v == 360 && sample_h < 640) begin
                if (hardware_frames != model_frames || scroll_updates != model_frames ||
                    dut.scroll_x != model_frames%320 || dut.scroll_y != 0)
                    $fatal(1,"Background failed to settle before visible frame%0d",model_frames);
                if (sample_h != row_samples || !blank || !hs || !vs || sync_n !== 0)
                    $fatal(1,"DAC sample order/blank/sync error frame%0d x%0d expectedx%0d",model_frames,sample_h,row_samples);
                expected_color = background_rgb(sample_h/2,180,model_frames%320);
                if ({red,green,blue} !== expected_color)
                    $fatal(1,"Motion frame%0d DACpixel(%0d,360): RGB%h expected%h scroll%0d",
                        model_frames,sample_h,{red,green,blue},expected_color,model_frames%320);
                row_samples = row_samples+1; checked_pixels = checked_pixels+1;
                if (sample_h == 639) begin
                    if (row_samples != 640) $fatal(1,"Incomplete independent background row");
                    row_samples = 0; checked_rows = checked_rows+1;
                    if (model_frames<=2 || model_frames%32==0 || model_frames>=319)
                        $display("Background real frame%0d:640 DAC samples passed,scroll%0d",model_frames,model_frames%320);
                    if (model_frames == limit_frames) begin
                        if (!initialization_scroll || checked_rows != limit_frames+1 ||
                            checked_pixels != (limit_frames+1)*640 ||
                            palette_writes != 0 || tile_writes != 0 || sprite_writes != 36 ||
                            !dut.waiting_frame || dut.program_halted || leds[4])
                            $fatal(1,"Continuous-motion final state/coverage incorrect");
                        if (dut.u_sprite_engine.sat_ram[1] !== 32'h80a05001 ||
                            dut.u_sprite_engine.sat_ram[2] !== 32'h80b85001)
                            $fatal(1,"Static sprites moved/changed unexpectedly");
                        $display("PASS tb_background_motion:%0d true VGA frames,%0d complete640-pixel rows,%0d RGB samples,one scroll/frame,no HALT/error/CLUT/TILE writes",
                            hardware_frames,checked_rows,checked_pixels);
                        $finish;
                    end
                end
            end
            previous_h = model_h; previous_v = model_v;
            if (model_h == 799) begin
                model_h = 0;
                if (model_v == 524) model_v = 0;
                else begin
                    model_v = model_v+1;
                    if (model_v == 480) model_frames = model_frames+1;
                end
            end else model_h = model_h+1;
        end
    end

    initial begin
        $readmemh("tiles.hex",reference_patterns);
        $readmemh("tilemap_data.hex",reference_map);
        $readmemh("palette.hex",reference_palette);
        if ($value$plusargs("frames=%d",limit_frames)) begin
            if (limit_frames<1 || limit_frames>1024) $fatal(1,"frames must be1..1024");
        end
        repeat(3) @(negedge clock); keys = 4'hf;
    end
    initial begin #18000000000; $fatal(1,"Timeout in continuous background real-frame test"); end
endmodule
