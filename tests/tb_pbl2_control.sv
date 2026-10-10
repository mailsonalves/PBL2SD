`timescale 1ns/1ps

// Integra o barramento local com a CPU, rasterizador e VGA reais. Nenhum
// contador de video, sinal de quadro ou memoria interna e forcado pelo teste.
module tb_pbl2_control;
    reg clock = 0;
    always #10 clock = ~clock;
    reg [3:0] keys = 4'he;
    reg [5:0] address = 0;
    reg mmio_read = 0, mmio_write = 0;
    reg [31:0] writedata = 0;
    reg [3:0] byteenable = 4'hf;
    wire [31:0] readdata;
    wire waitrequest;
    wire [9:0] leds;
    wire hs, vs, blank, sync_n, pixel_clock;
    wire [7:0] red, green, blue;
    wire present_restart_finished;
    pbl2_present_restart_check present_restart (.clock(clock),
        .keys(keys), .finished(present_restart_finished));

    gpu_core #(.PROGRAM_WORDS(10),
               .PROGRAM_FILE("tests/fixtures/pbl2_control.hex")) dut (
        .CLOCK_50(clock), .KEY(keys), .SW(10'd0), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green),
        .VGA_B(blue), .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n),
        .VGA_CLK(pixel_clock), .mmio_address(address),
        .mmio_read(mmio_read), .mmio_write(mmio_write),
        .mmio_writedata(writedata), .mmio_byteenable(byteenable),
        .mmio_readdata(readdata), .mmio_waitrequest(waitrequest)
    );

    integer accepted = 0, sprite_writes = 0, frames = 0;
    always @(posedge clock) begin
        if (dut.rst_n) begin
            if (waitrequest !== 0) $fatal(1, "MMIO deve aceitar sem espera");
            if (dut.cmd_valid && dut.cmd_ready) accepted = accepted + 1;
            if (dut.sat_we) sprite_writes = sprite_writes + 1;
            if (dut.frame_boundary) frames = frames + 1;
        end
    end

    task automatic read_register(input [5:0] offset, output [31:0] value);
        begin
            @(negedge clock);
            address = offset; mmio_read = 1;
            #1; value = readdata;
            @(negedge clock);
            mmio_read = 0;
        end
    endtask

    task automatic write_register(input [5:0] offset, input [31:0] value,
                                  input [3:0] lanes);
        begin
            @(negedge clock);
            address = offset; writedata = value; byteenable = lanes;
            mmio_write = 1;
            @(negedge clock);
            mmio_write = 0;
        end
    endtask

    reg [31:0] value, saved_pc, saved_ir, saved_sprite;
    integer saved_commands, saved_frames, saved_h;
    initial begin
        repeat (3) @(negedge clock);
        keys = 4'hf;
        read_register(6'h14, value);
        if (value !== 32'h50424c32) $fatal(1, "Identificacao MMIO incorreta");
        read_register(6'h09, value);
        if (value !== 0) $fatal(1, "Leitura desalinhada precisa retornar zero");

        // Reinicia enquanto CLEAR ja aceito continua escrevendo. O restart
        // precisa drenar o rasterizador e conservar o clock e os graficos.
        wait (dut.rast_busy);
        saved_h = dut.u_vga_sync.h_cnt;
        write_register(0, 3, 4'h1);
        repeat (12) @(negedge clock);
        if (!dut.rast_busy || !dut.buffer_initialized ||
            dut.u_vga_sync.h_cnt == 0 || dut.u_vga_sync.h_cnt == saved_h)
            $fatal(1, "Restart interrompeu CLEAR ou resetou o VGA");
        wait (!dut.rast_busy);
        repeat (12) @(negedge clock);
        read_register(0, value);
        if (value !== 1 || accepted != 1 || sprite_writes != 0 ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[1] !== 0)
            $fatal(1, "Restart pausado repetiu comando ou nao limpou CPU");

        // byteenable[0] governa CONTROL; outras faixas nao liberam a CPU.
        write_register(0, 0, 4'he);
        repeat (12) @(negedge clock);
        if (accepted != 1) $fatal(1, "Byteenable ignorado em CONTROL");
        write_register(0, 0, 4'h1);
        wait (dut.waiting_frame);
        write_register(0, 1, 4'h1);
        repeat (12) @(negedge clock);
        saved_commands = accepted;
        saved_frames = frames;
        // Pausa atravessa uma fronteira VGA verdadeira; operacoes pendentes
        // podem aposentar, mas ADDI/SPR_POS seguintes nao podem executar.
        wait (frames > saved_frames);
        repeat (12) @(negedge clock);
        read_register(6'h08, saved_pc);
        read_register(6'h0c, saved_ir);
        repeat (100) @(negedge clock);
        read_register(6'h08, value);
        if (value !== saved_pc) $fatal(1, "PC nao estabilizou durante pausa");
        read_register(6'h0c, value);
        if (value !== saved_ir || accepted != saved_commands ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[1] !== 30 ||
            dut.u_sprite_engine.sat_ram[0][24:16] !== 30)
            $fatal(1, "Pausa executou instrucao ou perdeu estado de sprite");
        read_register(6'h10, value);
        if (value !== frames) $fatal(1, "Contador MMIO nao acompanhou VGA pausado");

        write_register(0, 0, 4'h1);
        wait (leds[3]);
        repeat (8) @(negedge clock);
        if (accepted != 5 || sprite_writes != 2 ||
            dut.u_sprite_engine.sat_ram[0][24:16] !== 31 ||
            dut.u_sprite_engine.sat_ram[0][15:8] !== 40 ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[1] !== 31 ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[3] !== 16)
            $fatal(1, "Resume pulou/duplicou instrucao ou STATUS perdeu erro");
        read_register(6'h04, value);
        if (!value[2] || !value[3] || !value[4] || value[1] || value[8])
            $fatal(1, "STATUS nao refletiu HALT, erro ou inicializacao: %h", value);
        read_register(6'h08, value);
        if (value !== 9) $fatal(1, "PC de HALT incorreto: %0d", value);
        read_register(6'h0c, value);
        if (value !== 32'hf0000000) $fatal(1, "IR de HALT incorreto");
        // Registros RO e enderecos nao implementados nao alteram a CPU.
        write_register(6'h08, 32'hffffffff, 4'hf);
        write_register(6'h3c, 32'hffffffff, 4'hf);
        read_register(6'h08, value);
        if (value !== 9) $fatal(1, "Escrita em registro RO mudou PC");
        write_register(0, 4, 4'h1);
        repeat (8) @(negedge clock);
        read_register(6'h04, value);
        if (value[3] || !value[2] || accepted != 5)
            $fatal(1, "Clear_error nao preservou HALT");

        saved_sprite = dut.u_sprite_engine.sat_ram[0];
        write_register(0, 3, 4'h1);
        repeat (12) @(negedge clock);
        read_register(6'h04, value);
        if (value[2] || value[3] || value[1] || !value[4] ||
            accepted != 5 || dut.u_sprite_engine.sat_ram[0] !== saved_sprite ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[1] !== 0 ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[3] !== 0)
            $fatal(1, "Restart pausado nao reiniciou CPU preservando graficos");
        $display("PASS: MMIO integrado: restart drenou CLEAR, pausa atravessou quadro real, resume/PC/IR/erro/HALT verificados");
        wait (present_restart_finished);
        $finish;
    end

    initial begin
        #55000000;
        $fatal(1, "Timeout na integracao de controle PBL2");
    end
endmodule

module pbl2_present_restart_check (
    input wire clock, input wire [3:0] keys, output reg finished = 0
);
    reg mmio_write = 0;
    reg [31:0] writedata = 0;
    wire [9:0] leds;
    wire pixel_clock, hs, vs, blank, sync_n;
    wire [7:0] red, green, blue;
    wire [31:0] readdata;
    wire waitrequest;
    gpu_core #(.PROGRAM_WORDS(7),
        .PROGRAM_FILE("tests/fixtures/pbl2_present_restart.hex")) dut (
        .CLOCK_50(clock), .KEY(keys), .SW(10'd0), .LEDR(leds),
        .VGA_HS(hs), .VGA_VS(vs), .VGA_R(red), .VGA_G(green),
        .VGA_B(blue), .VGA_BLANK_N(blank), .VGA_SYNC_N(sync_n),
        .VGA_CLK(pixel_clock), .mmio_address(6'd0),
        .mmio_read(1'b0), .mmio_write(mmio_write),
        .mmio_writedata(writedata), .mmio_byteenable(4'h1),
        .mmio_readdata(readdata), .mmio_waitrequest(waitrequest)
    );
    integer accepted = 0, swaps = 0;
    always @(posedge clock) begin
        if (dut.rst_n) begin
            if (dut.cmd_valid && dut.cmd_ready) accepted = accepted + 1;
            if (dut.buffer_swap_done) swaps = swaps + 1;
        end
    end
    task automatic control(input [31:0] value);
        begin
            @(negedge clock); writedata = value; mmio_write = 1;
            @(negedge clock); mmio_write = 0;
        end
    endtask
    initial begin
        wait (dut.u_poly_buffer.swap_pending);
        control(3);
        repeat (12) @(negedge clock);
        if (!dut.buffer_busy || !dut.buffer_double_buffered ||
            dut.buffer_front || accepted != 5 ||
            dut.u_poly_buffer.back_ram[10*320+10] !== 250)
            $fatal(1, "Restart perdeu apresentacao/desenho pendentes");
        wait (!dut.buffer_busy);
        repeat (12) @(negedge clock);
        if (!dut.buffer_front || swaps != 1 || accepted != 5 ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[1] !== 0)
            $fatal(1, "Restart nao drenou PRESENT mantendo pausa/registradores");
        control(0);
        wait (leds[3]);
        repeat (12) @(negedge clock);
        if (accepted != 10 || swaps != 2 || dut.buffer_front ||
            dut.gen_active_fetch.u_fetch.datapath.u_registers.registers[1] !== 123 ||
            dut.u_poly_buffer.ram[10*320+10] !== 250)
            $fatal(1, "Resume apos PRESENT reiniciado perdeu execucao");
        $display("PASS: restart durante PRESENT preservou troca pendente e drenou antes de recomecar");
        finished = 1;
    end
endmodule
