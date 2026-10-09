`timescale 1ns/1ps
// Integration of the real gallery CPU, decoder, memories, rasterizer, sprite
// caches and debounced controls. Only frame_boundary is accelerated here;
// tb_showcase_video separately checks real VGA timing and pixel composition.
module tb_showcase_commands;
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 4'hE;
    reg [9:0] switches = 0;
    wire [9:0] leds;
    wire hs, vs, blank, sync_n, pixel_clock;
    wire [7:0] red, green, blue;
    gpu_de1_soc_top #(.BUTTON_DEBOUNCE_CYCLES(2)) dut (
        .CLOCK_50(clock), .KEY(keys), .SW(switches), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green), .VGA_B(blue),
        .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n), .VGA_CLK(pixel_clock)
    );
    reg fast_frame = 0;
    integer frame_divider = 0;
    // 2048 system clocks instead of 840000, without shortening any motor work.
    always @(negedge clock) begin
        fast_frame = 0;
        if (dut.rst_n) begin
            if (frame_divider == 2047) begin
                fast_frame = 1;
                frame_divider = 0;
            end else frame_divider = frame_divider+1;
        end
    end
    always @(fast_frame) force dut.frame_boundary = fast_frame;

    integer commands = 0, errors = 0, swaps = 0;
    reg [31:0] last_command = 0;
    reg [31:0] enabled_ids = 0;
    reg previous_front = 0;
    reg previous_frame = 0;
    always @(posedge clock) if (dut.rst_n) begin
        previous_frame = fast_frame;
        if (dut.cmd_valid && dut.cmd_ready) begin
            commands = commands+1;
            last_command = dut.cmd_data;
            if (dut.cmd_data[31:28] == 4'hB && dut.cmd_data[14])
                enabled_ids[dut.cmd_data[27:23]] = 1;
        end
        if (dut.cmd_error) begin
            errors = errors+1;
            if (last_command !== 0 || dut.processor_output !== 7)
                $fatal(1,"Unexpected gallery rejection: %08x panel%0d",last_command,dut.processor_output);
        end
        #1;
        if (dut.buffer_front != previous_front) begin
            if (!previous_frame) $fatal(1,"Buffer switched outside frame boundary");
            swaps = swaps+1;
        end
        previous_front = dut.buffer_front;
        if (dut.program_halted) $fatal(1,"Gallery unexpectedly halted");
    end

    task automatic wait_idle;
        begin
            wait (dut.gen_program_core.u_core.state == 4'd6);
            @(negedge clock);
        end
    endtask
    task automatic enter_panel(input integer panel, input integer phase);
        begin
            @(negedge clock); switches=panel;
            // R12 changes before R9 is reset: observe the reset before waiting
            // for a later phase, otherwise a previous panel could satisfy it.
            wait (dut.gen_program_core.u_core.u_register_file.registers[12] == panel &&
                  dut.gen_program_core.u_core.u_register_file.registers[9] == 0);
            wait (dut.gen_program_core.u_core.u_register_file.registers[9] >= phase);
            wait_idle();
            if (dut.processor_output !== panel || leds[2:0] !== panel)
                $fatal(1,"Wrong panel indicator");
            if (!dut.buffer_initialized || !dut.buffer_double_buffered || dut.execution_busy)
                $fatal(1,"Incomplete graphical initialization");
        end
    endtask
    function automatic [7:0] front_pixel(input integer x, input integer y);
        begin
            if(dut.buffer_front) front_pixel=dut.u_poly_buffer.back_ram[y*320+x];
            else front_pixel=dut.u_poly_buffer.ram[y*320+x];
        end
    endfunction
    function automatic [7:0] hidden_pixel(input integer x, input integer y);
        begin
            if(dut.buffer_front) hidden_pixel=dut.u_poly_buffer.ram[y*320+x];
            else hidden_pixel=dut.u_poly_buffer.back_ram[y*320+x];
        end
    endfunction
    task automatic hold_cycles(input integer count);
        repeat(count) @(negedge clock);
    endtask
    integer i, phase_before, swaps_before;
    initial begin
        hold_cycles(4); keys=4'hF;
        enter_panel(0,40);
        if(dut.scroll_x!==80 || dut.scroll_y!==40 ||
           dut.u_bg_engine.u_map_buffer.map_ram[12*40+2]!==227)
            $fatal(1,"Scroll XY / dynamic tile update failed");
        $display("Panel0 PASS: scroll XY and mutable tilemap");

        enter_panel(1,40);
        if(enabled_ids!==32'hFFFFFFFF) $fatal(1,"Not all32 sprite IDs were exercised");
        for(i=0;i<32;i=i+1) begin
            if(dut.u_sprite_engine.sat_ram[i][24:16] !== 24+(i%8)*36+8 ||
               dut.u_sprite_engine.sat_ram[i][15:8] !== 64+(i/8)*32 ||
               dut.u_sprite_engine.sat_ram[i][7:0] !== ((i+1)%4)*4 ||
               dut.u_sprite_engine.sat_ram[i][31] !== (i!=31))
                $fatal(1,"Grid sprite ID%0d position/image/enable failed",i);
        end
        $display("Panel1 PASS: all32 IDs, computed position/image and enable");

        enter_panel(2,40);
        for(i=0;i<4;i=i+1)
            if(dut.u_sprite_engine.sat_ram[i][30]!==i[0] || dut.u_sprite_engine.sat_ram[i][29]!==i[1] ||
               dut.u_sprite_engine.sat_ram[i][15:8]!==96)
                $fatal(1,"Flip H/V sprite%0d",i);
        $display("Panel2 PASS: four flip combinations");

        enter_panel(3,40);
        for(i=0;i<4;i=i+1)
            if(dut.u_sprite_engine.priority_ram[i]!==((i+1)%4)) $fatal(1,"Priority update");
        if(dut.u_sprite_engine.priority_ram[4]!==2 || dut.u_sprite_engine.priority_ram[5]!==2 ||
           front_pixel(80,80)!==8'hFE || front_pixel(168,80)!==8'hFD)
            $fatal(1,"Overlap/tie backing layers");
        $display("Panel3 PASS: priorities0..3, equal-priority IDs and backing polygons");

        enter_panel(4,40);
        for(i=0;i<8;i=i+1)
            if(!dut.u_sprite_engine.palette_enable_ram[i] || dut.u_sprite_engine.palette_bank_ram[i]!==i+1)
                $fatal(1,"Palette bank%0d",i+1);
        if(dut.u_palette.clut_ram[17]!==24'h00FC00 || dut.u_palette.clut_ram[240]!==24'hF80000 ||
           dut.u_sprite_engine.palette_enable_ram[8] || !dut.u_sprite_engine.palette_enable_ram[9] ||
           dut.u_sprite_engine.palette_bank_ram[9]!==15)
            $fatal(1,"RGB mutation/direct mode/transparent-bank setup");
        $display("Panel4 PASS: CLUT banks, direct mode and RGB mutation");

        enter_panel(5,40);
        if(front_pixel(60,80)!==241 || front_pixel(168,100)!==242 ||
           front_pixel(100,180)!==243 || front_pixel(319,210)!==244 || front_pixel(240,180)!==0)
            $fatal(1,"Triangles / rectangle / clipping / empty degenerate triangle");
        $display("Panel5 PASS: filled primitives, clipping and degeneracy");

        swaps_before=swaps;
        enter_panel(6,40);
        if(swaps-swaps_before<40 || front_pixel(120,100)!==243 || hidden_pixel(120,100)!==0)
            $fatal(1,"Animation did not present complete front/back frames");
        $display("Panel6 PASS: 40 presentations, hidden and displayed frames differ");

        enter_panel(7,40);
        if(errors==0 || !dut.processor_status[4] || !leds[4] ||
           dut.u_bg_engine.u_map_buffer.map_ram[8*40+8]!==49 ||
           dut.u_bg_engine.u_map_buffer.map_ram[10*40+5]!==49 ||
           dut.u_bg_engine.u_map_buffer.map_ram[10*40+12]!==48 ||
           dut.u_bg_engine.u_map_buffer.map_ram[10*40+19]!==49 ||
           dut.u_bg_engine.u_map_buffer.map_ram[10*40+26]!==48)
            $fatal(1,"Error/status demonstration signatures");
        $display("Panel7 PASS: deliberate error and independent status flags");

        @(negedge clock); switches=10'h107;
        wait(dut.gen_program_core.u_core.u_register_file.registers[13]==0);
        wait_idle(); phase_before=dut.gen_program_core.u_core.u_register_file.registers[9];
        hold_cycles(10000);
        if(dut.gen_program_core.u_core.u_register_file.registers[9]!=phase_before)
            $fatal(1,"Pause did not freeze animation");
        keys=4'hD; // KEY1 pressed, KEY0 released.
        wait(dut.gen_program_core.u_core.u_register_file.registers[9]==phase_before+1);
        hold_cycles(12000);
        if(dut.gen_program_core.u_core.u_register_file.registers[9]!=phase_before+1)
            $fatal(1,"Held step button repeated");
        keys=4'hF; hold_cycles(10000);
        keys=4'h7; // KEY3 restarts the selected page.
        wait(dut.gen_program_core.u_core.u_register_file.registers[9]==0);
        keys=4'hF; wait_idle();
        if(dut.processor_status[4]) $fatal(1,"Restart did not clear accumulated error");

        @(negedge clock); switches=10'h307; // Automatic mode remains paused.
        hold_cycles(6000); keys=4'hB; // KEY2 selects next panel in automatic mode.
        wait(dut.processor_output==0); keys=4'hF;
        wait(dut.gen_program_core.u_core.u_register_file.registers[12]==0 &&
             dut.gen_program_core.u_core.u_register_file.registers[9]==0);
        wait_idle();
        if(dut.u_palette.clut_ram[240]!==0) $fatal(1,"Re-entering panel failed to restore CLUT");
        switches=10'h200; // Resume automatic playback.
        wait(dut.processor_output==1);
        if(dut.gen_program_core.u_core.u_register_file.registers[11]!==0)
            $fatal(1,"Automatic120-step panel change failed");
        $display("PASS: gallery eight panels, real motors/memories, %0d commands, %0d swaps, pause/step/restart/next/auto",commands,swaps);
        $finish;
    end
    initial begin #2000000000; $fatal(1,"Timeout on gallery commands/control integration"); end
endmodule
