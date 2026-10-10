`timescale 1ns/1ps
// Um unico hardware executa A e B carregados somente pela interface MMIO.
// Hierarquia e usada apenas para observar comandos/memorias, nunca para escreve-los.
module tb_pbl2_upload;
    localparam [31:0] HALT = 32'hf0000000;
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 0;
    reg [5:0] mmio_address = 0;
    reg mmio_read = 0, mmio_write = 0;
    reg [31:0] mmio_writedata = 0;
    reg [3:0] mmio_byteenable = 4'hf;
    wire [31:0] mmio_readdata;
    wire mmio_waitrequest;
    wire [9:0] leds;
    wire hs, vs, blank, sync_n, pixel_clock;
    wire [7:0] red, green, blue;
    gpu_core #(.PROGRAM_WORDS(256), .PROGRAM_FILE("programs/background_sprites.hex")) dut (
        .CLOCK_50(clock), .KEY(keys), .SW(10'd0), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green), .VGA_B(blue),
        .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n), .VGA_CLK(pixel_clock),
        .mmio_address(mmio_address), .mmio_read(mmio_read), .mmio_write(mmio_write),
        .mmio_writedata(mmio_writedata), .mmio_byteenable(mmio_byteenable),
        .mmio_readdata(mmio_readdata), .mmio_waitrequest(mmio_waitrequest)
    );

    reg [31:0] image_a [0:255], image_b [0:255], original_program [0:255];
    reg [31:0] expected_ram [0:255];
    reg [7:0] reference_patterns [0:16383], reference_map [0:1199];
    reg [23:0] reference_palette [0:255];
    integer bus_wait_cycles = 0, readback_words = 0;

    task automatic write_mmio(input [5:0] address, input [31:0] value,
        input [3:0] byteenable = 4'hf);
        integer waited;
        begin
            @(negedge clock);
            mmio_address = address; mmio_writedata = value;
            mmio_byteenable = byteenable; mmio_read = 0; mmio_write = 1;
            waited = 0;
            while (1) begin
                @(posedge clock);
                if (!mmio_waitrequest) break;
                waited = waited+1;
                if (waited > 4096) $fatal(1, "MMIO write timeout at byte address%h", address);
            end
            @(negedge clock);
            mmio_write = 0; mmio_byteenable = 4'hf;
        end
    endtask

    task automatic read_mmio(input [5:0] address, output [31:0] value);
        integer waited;
        begin
            @(negedge clock);
            mmio_address = address; mmio_read = 1; mmio_write = 0;
            waited = 0;
            while (1) begin
                @(posedge clock);
                if (!mmio_waitrequest) begin
                    value = mmio_readdata;
                    break;
                end
                waited = waited+1; bus_wait_cycles = bus_wait_cycles+1;
                if (waited > 4096) $fatal(1, "MMIO read timeout at byte address%h", address);
            end
            @(negedge clock);
            mmio_read = 0;
        end
    endtask

    task automatic await_load_ready;
        reg [31:0] status;
        integer polls;
        begin
            polls = 0;
            while (1) begin
                read_mmio(6'h24, status);
                if (status[31:16] !== 16'd256 || status[1])
                    $fatal(1, "Invalid capacity/error in PROG_STATUS: %h", status);
                if (status[0]) break;
                polls = polls+1;
                if (polls > 100000) $fatal(1, "Timeout draining graphics before LOAD_READY");
            end
            read_mmio(6'h00, status);
            if ((status & 32'h9) != 32'h9)
                $fatal(1, "LOAD mode must pause the CPU: CONTROL=%h", status);
        end
    endtask

    task automatic await_halt(input integer expected_pc);
        reg [31:0] status, pc, ir;
        integer polls;
        begin
            polls = 0;
            while (1) begin
                read_mmio(6'h04, status);
                if (status[3]) $fatal(1, "CPU error while executing uploaded program: %h", status);
                if (status[2]) break;
                polls = polls+1;
                if (polls > 100000) $fatal(1, "Uploaded program failed to HALT");
            end
            repeat (6) @(negedge clock);
            read_mmio(6'h04, status);
            read_mmio(6'h08, pc);
            read_mmio(6'h0c, ir);
            if (status[1] || !status[2] || status[3] || !status[4] ||
                pc != expected_pc || ir !== HALT)
                $fatal(1, "HALT state: status%h pc%0d (expected%0d) ir%h", status,pc,expected_pc,ir);
        end
    endtask

    task automatic verify_uploaded_ram;
        integer address;
        reg [31:0] data, next_address;
        begin
            for (address = 0; address < 256; address = address+1) begin
                write_mmio(6'h18, address);
                read_mmio(6'h1c, data);
                if (data !== expected_ram[address])
                    $fatal(1, "RAM readback address%0d: got%h expected%h", address,data,expected_ram[address]);
                read_mmio(6'h18, next_address);
                if (next_address != address)
                    $fatal(1, "PROG_DATA read unexpectedly incremented address");
                readback_words = readback_words+1;
            end
        end
    endtask

    task automatic upload_program(input bit program_b);
        integer address, length;
        reg [31:0] data;
        begin
            length = program_b ? 48 : 45;
            write_mmio(6'h18, 0);
            for (address = 0; address < length; address = address+1) begin
                expected_ram[address] = program_b ? image_b[address] : image_a[address];
                write_mmio(6'h1c, expected_ram[address]);
            end
            read_mmio(6'h18, data);
            if (data != length) $fatal(1, "PROG_DATA did not auto-increment after accepted writes");
            write_mmio(6'h20, length);
            read_mmio(6'h20, data);
            if (data != length) $fatal(1, "Uploaded LENGTH incorrect");
            verify_uploaded_ram(); // includes the untouched tail of the previous image
        end
    endtask

    bit watch_program = 0, scene_b = 0;
    integer expected_commands = 0;
    integer accepted = 0, clears = 0, draws = 0, configurations = 0;
    integer clear_writes = 0, polygon_writes = 0, sat_writes = 0, style_writes = 0;
    integer palette_writes = 0, tile_writes = 0, boot_accepted = 0, boot_clear_writes = 0;
    task automatic start_command_watch(input bit program_b, input integer commands);
        begin
            scene_b = program_b; expected_commands = commands;
            accepted = 0; clears = 0; draws = 0; configurations = 0;
            clear_writes = 0; polygon_writes = 0; sat_writes = 0; style_writes = 0;
            palette_writes = 0; tile_writes = 0; watch_program = 1;
        end
    endtask

    always @(posedge clock) begin
        if (dut.rst_n) begin
            if (dut.load_mode && dut.cmd_valid)
                $fatal(1, "CPU issued a graphics command in LOAD mode");
            if (dut.program_write && (!dut.load_mode || !dut.program_ready))
                $fatal(1, "Instruction RAM write escaped LOAD_READY guard");
            if (dut.cmd_valid && dut.cmd_ready) begin
                if (watch_program) begin
                    if (accepted >= expected_commands ||
                        dut.cmd_data !== (scene_b ? image_b[accepted] : image_a[accepted]))
                        $fatal(1, "Repeated/skipped/incorrect command%0d: %h", accepted,dut.cmd_data);
                    accepted = accepted+1;
                end else boot_accepted = boot_accepted+1;
            end
            if (watch_program) begin
                if (dut.rast_start) begin
                    if (dut.rast_clear_screen) clears = clears+1;
                    else draws = draws+1;
                end
                if (dut.buffer_config_valid) configurations = configurations+1;
                if (dut.buf_we) begin
                    if (dut.buf_wr_data == 0) clear_writes = clear_writes+1;
                    else polygon_writes = polygon_writes+1;
                end
                if (dut.sat_we) sat_writes = sat_writes+1;
                if (dut.sprite_meta_we) style_writes = style_writes+1;
                if (dut.pal_we) palette_writes = palette_writes+1;
                if (dut.tm_we) tile_writes = tile_writes+1;
            end else if (dut.buf_we && dut.buf_wr_data == 0)
                boot_clear_writes = boot_clear_writes+1;
        end
    end

    function automatic bit inside_triangle(input integer x,y,
        input integer ax,ay,bx,by,cx,cy);
        integer a,b,c;
        begin
            a = (x-ax)*(by-ay)-(y-ay)*(bx-ax);
            b = (x-bx)*(cy-by)-(y-by)*(cx-bx);
            c = (x-cx)*(ay-cy)-(y-cy)*(ax-cx);
            inside_triangle = (a>=0 && b>=0 && c>=0) || (a<=0 && b<=0 && c<=0);
        end
    endfunction

    function automatic [7:0] expected_polygon(input integer x,y);
        begin
            expected_polygon = 0;
            if (scene_b) begin
                if (x>=40 && x<=120 && y>=136 && y<=184) expected_polygon = 2;
            end else if (inside_triangle(x,y,40,40,120,40,80,100)) expected_polygon = 18;
        end
    endfunction

    function automatic [31:0] expected_attributes(input integer id);
        integer x,y;
        begin
            x = id == 1 ? 160 : 184; y = scene_b ? 144 : 80;
            expected_attributes = 32'h80000001 | (x*65536) | (y*256) |
                ((scene_b && id == 1) ? 32'h40000000 : 0) |
                ((scene_b && id == 2) ? 32'h20000000 : 0);
        end
    endfunction

    function automatic [7:0] expected_sprite(input integer x,y);
        integer id,sx,sy,rx,ry,tile,address;
        reg [7:0] source;
        begin
            expected_sprite = 0;
            for (id = 1; id <= 2; id = id+1) begin
                sx = id == 1 ? 160 : 184; sy = scene_b ? 144 : 80;
                rx = x-sx; ry = y-sy;
                if (rx>=0 && rx<16 && ry>=0 && ry<16) begin
                    if (scene_b && id == 1) rx = 15-rx;
                    if (scene_b && id == 2) ry = 15-ry;
                    tile = 1+2*(ry/8)+rx/8;
                    address = tile*64+(ry%8)*8+rx%8;
                    source = reference_patterns[address];
                    if (source != 0) expected_sprite = source;
                end
            end
        end
    endfunction

    function automatic [23:0] expected_rgb(input integer x,y);
        integer tile,address;
        reg [7:0] index,polygon,sprite;
        begin
            tile = reference_map[(y/8)*40+x/8];
            address = tile*64+(y%8)*8+x%8;
            index = reference_patterns[address];
            polygon = expected_polygon(x,y); sprite = expected_sprite(x,y);
            if (polygon != 0) index = polygon;
            if (sprite != 0) index = sprite;
            expected_rgb = reference_palette[index];
        end
    endfunction

    task automatic verify_scene;
        integer i,x,y,colored;
        reg [7:0] polygon;
        begin
            if (accepted != (scene_b ? 47 : 44) || clears != 1 ||
                draws != (scene_b ? 2 : 1) || configurations != 1 ||
                clear_writes != 76800 || polygon_writes != (scene_b ? 3986 : 2461) ||
                sat_writes != 36 || style_writes != 2 || palette_writes != 0 || tile_writes != 0)
                $fatal(1, "Scene%0d counts:cmd%0d clear%0d draw%0d config%0d clearpixels%0d drawpixels%0d sat%0d style%0d palette%0d tile%0d",
                    scene_b,accepted,clears,draws,configurations,clear_writes,polygon_writes,
                    sat_writes,style_writes,palette_writes,tile_writes);
            if (dut.scroll_x != 0 || dut.scroll_y != 0 || dut.buffer_double_buffered || dut.buffer_front)
                $fatal(1, "Static scene retained scroll/double/front configuration");
            for (i = 0; i < 32; i = i+1) begin
                if (i == 1 || i == 2) begin
                    if (dut.u_sprite_engine.sat_ram[i] !== expected_attributes(i) ||
                        dut.u_sprite_engine.priority_ram[i] !== i[1:0] ||
                        dut.u_sprite_engine.palette_enable_ram[i] ||
                        dut.u_sprite_engine.palette_bank_ram[i] != 0)
                        $fatal(1, "Uploaded scene SAT/flip/style sprite%0d incorrect", i);
                end else if (dut.u_sprite_engine.sat_ram[i][31:29] != 0 ||
                             dut.u_sprite_engine.sat_ram[i][7:0] != 0)
                    $fatal(1, "Unused sprite%0d was not disabled explicitly", i);
            end
            for (i = 0; i < 256; i = i+1)
                if (dut.u_palette.clut_ram[i] !== reference_palette[i])
                    $fatal(1, "Upload/program recolored shared CLUT at%0d", i);
            for (i = 0; i < 1200; i = i+1)
                if (dut.u_bg_engine.u_map_buffer.map_ram[i] !== reference_map[i])
                    $fatal(1, "Upload/program changed tilemap at%0d", i);
            colored = 0;
            for (y = 0; y < 240; y = y+1) for (x = 0; x < 320; x = x+1) begin
                polygon = expected_polygon(x,y);
                if (dut.u_poly_buffer.ram[y*320+x] !== polygon)
                    $fatal(1, "Scene%0d foreground(%0d,%0d): %h expected%h",scene_b,x,y,
                        dut.u_poly_buffer.ram[y*320+x],polygon);
                if (polygon != 0) colored = colored+1;
            end
            if (colored != (scene_b ? 3969 : 2461)) $fatal(1, "Independent polygon area incorrect");
        end
    endtask

    // Modelo de temporizacao independente: conta o clock encaminhado e nao
    // consulta contadores ou coordenadas internas do gerador VGA.
    integer model_h = 0, model_v = 0;
    always @(posedge pixel_clock or negedge keys[0]) begin
        if (!keys[0]) begin model_h = 0; model_v = 0; end
        else if (model_h == 799) begin
            model_h = 0;
            model_v = model_v == 524 ? 0 : model_v+1;
        end else model_h = model_h+1;
    end

    bit verify_video = 0;
    integer pipeline_valid = 0;
    reg [23:0] rgb_pipeline [0:2];
    reg [2:0] hs_pipeline = 7,vs_pipeline = 7,blank_pipeline = 0;
    integer h_pipeline [0:2],v_pipeline [0:2];
    always @(posedge clock) begin
        if (verify_video) begin
            rgb_pipeline[2] = rgb_pipeline[1]; rgb_pipeline[1] = rgb_pipeline[0];
            h_pipeline[2] = h_pipeline[1]; h_pipeline[1] = h_pipeline[0];
            v_pipeline[2] = v_pipeline[1]; v_pipeline[1] = v_pipeline[0];
            h_pipeline[0] = model_h; v_pipeline[0] = model_v;
            rgb_pipeline[0] = model_h<640 && model_v<480 ? expected_rgb(model_h/2,model_v/2) : 0;
            hs_pipeline = {hs_pipeline[1:0], !(model_h>=656 && model_h<752)};
            vs_pipeline = {vs_pipeline[1:0], !(model_v>=490 && model_v<492)};
            blank_pipeline = {blank_pipeline[1:0], model_h<640 && model_v<480};
            pipeline_valid = pipeline_valid+1;
            #1;
            if (pipeline_valid > 3 &&
                ({red,green,blue} !== rgb_pipeline[2] || hs !== hs_pipeline[2] ||
                 vs !== vs_pipeline[2] || blank !== blank_pipeline[2] || sync_n !== 0))
                $fatal(1, "Scene%0d physicalVGA(%0d,%0d): RGB%h expected%h, HS/VS/blank%0b%0b%0b expected%0b%0b%0b",
                    scene_b,h_pipeline[2],v_pipeline[2],{red,green,blue},rgb_pipeline[2],
                    hs,vs,blank,hs_pipeline[2],vs_pipeline[2],blank_pipeline[2]);
        end
    end

    reg [23:0] captured_pixels [0:307199];
    bit captured_valid [0:307199];
    task automatic verify_full_vga_frame;
        integer cycles,pixels,active,hs_low,vs_low,address,captured,fd,i;
        reg last_pixel_clock;
        begin
            pipeline_valid = 0; verify_video = 1;
            for (i = 0; i < 307200; i = i+1) captured_valid[i] = 0;
            repeat (8) @(negedge clock);
            pixels = 0; active = 0; hs_low = 0; vs_low = 0; captured = 0;
            last_pixel_clock = pixel_clock;
            for (cycles = 0; cycles < 840000; cycles = cycles+1) begin
                @(posedge clock); #2;
                if (!leds[3] || dut.cmd_valid || dut.execution_busy || pixel_clock === last_pixel_clock)
                    $fatal(1, "HALT/VGA clock stability failure during frame");
                last_pixel_clock = pixel_clock;
                if (pixel_clock) begin
                    pixels = pixels+1;
                    if (!hs) hs_low = hs_low+1;
                    if (!vs) vs_low = vs_low+1;
                    if (blank) begin
                        active = active+1;
                        address = v_pipeline[2]*640+h_pipeline[2];
                        if (address<0 || address>=307200 || captured_valid[address])
                            $fatal(1, "Duplicate/missing physical pixel in captured frame: %0d", address);
                        captured_valid[address] = 1;
                        captured_pixels[address] = {red,green,blue};
                        captured = captured+1;
                    end
                end
            end
            verify_video = 0;
            if (pixels != 420000 || active != 307200 || hs_low != 50400 ||
                vs_low != 1600 || captured != 307200)
                $fatal(1, "Frame counts pixels%0d active%0d HS%0d VS%0d captured%0d",
                    pixels,active,hs_low,vs_low,captured);
            if ($test$plusargs("dump_vga")) begin
                fd = $fopen(scene_b ? ".build/pbl2/program_b_vga.ppm" : ".build/pbl2/program_a_vga.ppm", "wb");
                if (!fd) $fatal(1, "Create .build/pbl2 before running +dump_vga");
                $fwrite(fd,"P6\n640 480\n255\n");
                for (i = 0; i < 307200; i = i+1)
                    $fwrite(fd,"%c%c%c",captured_pixels[i][23:16],captured_pixels[i][15:8],captured_pixels[i][7:0]);
                $fclose(fd);
            end
            $display("PASS uploaded program%0s: %0d commands, independent framebuffer,32 SAT entries,CLUT/tilemap unchanged,840000-clock full VGA frame",
                scene_b ? "B" : "A",accepted);
        end
    endtask

    reg [31:0] data,original_word;
    integer address,cycles;
    initial begin
        $readmemh("programs/program_a.hex",image_a);
        $readmemh("programs/program_b.hex",image_b);
        $readmemh("programs/background_sprites.hex",original_program);
        $readmemh("tiles.hex",reference_patterns);
        $readmemh("tilemap_data.hex",reference_map);
        $readmemh("palette.hex",reference_palette);
        for (address = 0; address < 256; address = address+1) expected_ram[address] = original_program[address];
        repeat (3) @(negedge clock); keys = 4'hf;
        cycles = 0;
        while (!(dut.cmd_valid && dut.cmd_ready && dut.cmd_data == 32'h0f000000)) begin
            @(negedge clock); cycles = cycles+1;
            if (cycles > 100000) $fatal(1, "Boot CLEAR was never accepted");
        end
        @(posedge clock); #1;
        // O primeiro CLEAR ja foi aceito. Escrita DATA fora de LOAD deve ser rejeitada.
        write_mmio(6'h1c,HALT);
        read_mmio(6'h24,data);
        if (!data[1] || data[0]) $fatal(1, "DATA outside LOAD failed to report rejection");
        write_mmio(6'h00,32'h8);
        read_mmio(6'h24,data);
        if (data[0] || data[1] || !dut.rast_busy)
            $fatal(1, "LOAD_READY exposed before accepted CLEAR drained");
        await_load_ready();
        if (boot_accepted != 1 || boot_clear_writes != 76800 || dut.execution_busy)
            $fatal(1, "LOAD failed to drain exactly one complete boot CLEAR: commands%0d writes%0d",boot_accepted,boot_clear_writes);
        write_mmio(6'h18,0); read_mmio(6'h1c,original_word);
        if (original_word !== original_program[0]) $fatal(1, "Rejected DATA write corrupted boot instruction RAM");
        upload_program(0);
        start_command_watch(0,44);
        write_mmio(6'h00,32'h2);
        await_halt(44);
        verify_scene(); verify_full_vga_frame();
        watch_program = 0;

        // Cauda antiga ainda contem instrucoes validas: LENGTH=1 deve injetar
        // HALT em PC1 mesmo com CLEAR real presente na RAM nessa posicao.
        write_mmio(6'h00,32'h8); await_load_ready();
        write_mmio(6'h20,1);
        start_command_watch(0,1);
        write_mmio(6'h00,32'h2); await_halt(1);
        if (accepted != 1 || configurations != 1 || clears != 0 || draws != 0 ||
            sat_writes != 0 || style_writes != 0 || clear_writes != 0 || polygon_writes != 0)
            $fatal(1, "Uploaded LENGTH guard executed stale RAM tail");
        watch_program = 0;
        $display("PASS upload LENGTH guard: RAM[1]=CLEAR remained stored but PC1 executed HALT");

        write_mmio(6'h00,32'h8); await_load_ready();
        upload_program(1);
        start_command_watch(1,47);
        write_mmio(6'h00,32'h2); await_halt(47);
        verify_scene(); verify_full_vga_frame();
        watch_program = 0;

        // Reset KEY preserva RAM, comprimento e LOAD: nao volta ao boot A/B antigo.
        write_mmio(6'h00,32'h8); await_load_ready();
        @(negedge clock); keys[0] = 0;
        repeat (4) @(negedge clock); keys[0] = 1;
        repeat (5) @(negedge clock);
        read_mmio(6'h00,data);
        if ((data & 32'h9) != 32'h9) $fatal(1, "KEY reset lost LOAD mode/pause");
        read_mmio(6'h20,data);
        if (data != 48) $fatal(1, "KEY reset lost uploaded LENGTH");
        await_load_ready(); verify_uploaded_ram();
        start_command_watch(1,47);
        write_mmio(6'h00,32'h2); await_halt(47); verify_scene();
        watch_program = 0;
        if (bus_wait_cycles == 0 || readback_words != 768)
            $fatal(1, "PROG_DATA synchronous waitrequest/readback coverage missing");
        $display("PASS upload KEY persistence: B RAM/LENGTH/LOAD preserved, restarted B; %0d RAM readbacks, %0d wait cycles",readback_words,bus_wait_cycles);
        $display("PASS tb_pbl2_upload: one GPU,A-to-B MMIO upload,drain,guards,readback,VGA and reset persistence");
        $finish;
    end
    initial begin #200000000; $fatal(1,"Timeout in MMIO upload/full-frame integration"); end
endmodule
