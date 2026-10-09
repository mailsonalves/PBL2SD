`timescale 1ns/1ps
module tb_programmable_gpu;
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 4'hE;
    wire [9:0] leds;
    wire hs, vs, blank, sync_n, pixel_clock;
    wire [7:0] red, green, blue;
    gpu_de1_soc_top #(.USE_PROGRAMMABLE_CORE(1), .SHOWCASE(0),
        .PROGRAM_WORDS(54), .PROGRAM_FILE("programs/core_validation.hex"),
        .BUTTON_DEBOUNCE_CYCLES(1)) dut (
        .CLOCK_50(clock), .KEY(keys), .SW(10'h155), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green), .VGA_B(blue),
        .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n), .VGA_CLK(pixel_clock)
    );
    integer commands = 0, errors = 0, frames = 0;
    always @(posedge clock) if (dut.rst_n) begin
        if (dut.cmd_ready && dut.cmd_valid) begin
            case (commands)
                0: if (dut.cmd_data !== 32'h10FFF800) $fatal(1, "Comando Assembly direto");
                1: if (dut.cmd_data !== 32'h50000A14) $fatal(1, "Comando calculado em registrador");
                default: $fatal(1, "Comando extra");
            endcase
            commands = commands+1;
        end
        if (dut.cmd_error) errors = errors+1;
        if (dut.frame_boundary) frames = frames+1;
    end
    initial begin
        repeat (4) @(negedge clock);
        keys = 4'hF;
        wait (leds[3]);
        @(negedge clock);
        if (dut.processor_output !== 32'h12345678 || commands != 2 || errors != 0 || frames < 1)
            $fatal(1, "Programa Assembly nao integrou CPU/motores/quadro");
        if (dut.scroll_x !== 10 || dut.scroll_y !== 20 || dut.u_palette.clut_ram[255] !== 24'hF80000)
            $fatal(1, "Efeitos graficos do programa incorretos");
        if (dut.processor_status[4] || !dut.processor_status[5] || dut.execution_busy)
            $fatal(1, "Status final");
        if (dut.gen_program_core.u_core.u_register_file.registers[3] !== 32'h155 ||
            dut.gen_program_core.u_core.u_register_file.registers[4] !== 0 ||
            dut.gen_program_core.u_core.u_register_file.registers[13][4] !== 1 ||
            dut.gen_program_core.u_core.u_register_file.registers[14][4] !== 0)
            $fatal(1, "IN/STATUS/CLRE nao integrados");
        // HALT nao para a varredura nem o contador de quadros.
        wait (dut.frame_boundary);
        @(posedge clock); #1;
        if (dut.gen_program_core.u_core.u_frame_control.frame_counter < 2 || !leds[3])
            $fatal(1, "Contador de quadros parou com CPU");
        $display("PASS: GPU programavel; Assembly54 palavras, RF/ULA/branches/status, comandos direto/indireto, WAIT_FRAME e VGA apos HALT");
        $finish;
    end
    initial begin #50000000; $fatal(1, "Timeout na GPU programavel"); end
endmodule
