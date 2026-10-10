`timescale 1ns/1ps
module tb_gpu_cpu_control;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, pause = 0, restart = 0, clear_error = 0, frame_boundary = 0;
    reg hold_ready = 0, execution_busy = 0, model_error = 0, manual_error = 0;
    wire cmd_ready = !hold_ready && !execution_busy;
    wire [31:0] cmd_data, ir;
    wire cmd_valid, halted, busy, done, error, waiting_frame;
    wire [7:0] pc;
    wire [3:0] flags;
    active_fetch_controller #(.PROGRAM_WORDS(64),
        .PROGRAM_FILE("tests/fixtures/cpu_control.hex")) dut (
        .clk(clk), .rst_n(rst_n), .cmd_ready(cmd_ready), .execution_busy(execution_busy),
        .frame_boundary(frame_boundary), .restart(restart), .pause(pause),
        .clear_error(clear_error), .cmd_error(model_error || manual_error),
        .load_mode(1'b0), .program_length(9'd64), .program_address(9'd0),
        .program_write(1'b0), .program_writedata(32'd0), .program_byteenable(4'd0),
        .cmd_data(cmd_data), .cmd_valid(cmd_valid), .halted(halted),
        .busy(busy), .done(done), .error(error), .waiting_frame(waiting_frame), .flags(flags),
        .pc(pc), .ir(ir)
    );
    integer accepted = 0, retired = 0, phase = 0, busy_cycles = 0, index;
    reg [31:0] received [0:15];
    // O motor eleva busy uma borda depois da aceitacao, como o rasterizador.
    always @(posedge clk) begin
        if (!rst_n) begin
            execution_busy <= 0; model_error <= 0; phase <= 0; busy_cycles <= 0;
            accepted = 0;
        end else begin
            model_error <= 0;
            if (phase == 1) begin
                execution_busy <= 1; busy_cycles <= 4; phase <= 2;
            end else if (phase == 2) begin
                if (busy_cycles == 0) begin execution_busy <= 0; phase <= 0; end
                else busy_cycles <= busy_cycles - 1;
            end
            if (cmd_valid && cmd_ready) begin
                if (phase != 0) $fatal(1, "Duplicate command during delayed busy");
                received[accepted] = cmd_data;
                accepted = accepted + 1;
                phase <= 1;
                model_error <= cmd_data[31:28] == 4'hF;
            end
        end
    end
    always @(posedge clk) begin
        #1;
        if (!rst_n) retired = 0;
        else if (done) retired = retired + 1;
    end
    task automatic blank_program;
        for (index = 0; index < 64; index = index + 1)
            dut.u_instruction_memory.memory[index] = 32'hF0000000;
    endtask
    task automatic expect_register(input integer number, input [31:0] value);
        if (dut.datapath.u_registers.registers[number] !== value)
            $fatal(1, "r%0d=%h expected %h", number, dut.datapath.u_registers.registers[number], value);
    endtask
    task automatic expect_pc_hold(input [7:0] value, input integer cycles);
        repeat (cycles) begin
            @(negedge clk);
            if (pc !== value) $fatal(1, "PC %0d advanced while held at %0d", pc, value);
        end
    endtask
    initial begin
        repeat (2) @(negedge clk);
        blank_program;
        dut.u_instruction_memory.memory[0] = 32'h20100005;
        dut.u_instruction_memory.memory[1] = 32'h20200003;
        dut.u_instruction_memory.memory[2] = 32'h22312000;
        dut.u_instruction_memory.memory[3] = 32'h23412000;
        dut.u_instruction_memory.memory[4] = 32'h24512000;
        dut.u_instruction_memory.memory[5] = 32'h25612000;
        dut.u_instruction_memory.memory[6] = 32'h26712000;
        dut.u_instruction_memory.memory[7] = 32'h27812000;
        dut.u_instruction_memory.memory[8] = 32'h28982000;
        dut.u_instruction_memory.memory[9] = 32'h21A90000;
        dut.u_instruction_memory.memory[10] = 32'h2AB2FFFC;
        dut.u_instruction_memory.memory[11] = 32'h29011000;
        dut.u_instruction_memory.memory[12] = 32'hE300000F;
        dut.u_instruction_memory.memory[13] = 32'h20C0DEAD;
        dut.u_instruction_memory.memory[14] = 32'hE6000000;
        dut.u_instruction_memory.memory[15] = 32'hE4000012;
        dut.u_instruction_memory.memory[16] = 32'hE5C00000;
        dut.u_instruction_memory.memory[17] = 32'h2000FFFF;
        dut.u_instruction_memory.memory[18] = 32'h2AD0FFFF;
        dut.u_instruction_memory.memory[19] = 32'hE4000016;
        dut.u_instruction_memory.memory[20] = 32'h20D0BEEF;
        dut.u_instruction_memory.memory[21] = 32'h0F000000;
        dut.u_instruction_memory.memory[22] = 32'h22D12001;
        dut.u_instruction_memory.memory[23] = 32'hE2FF0010;
        dut.u_instruction_memory.memory[24] = 32'h41120001;
        dut.u_instruction_memory.memory[25] = 32'hE5E00000;
        dut.u_instruction_memory.memory[26] = 32'h41120000;
        dut.u_instruction_memory.memory[27] = 32'hF0000001;
        dut.u_instruction_memory.memory[28] = 32'hE1000000;
        dut.u_instruction_memory.memory[29] = 32'h20F0002A;
        dut.u_instruction_memory.memory[30] = 32'hE2000064;
        rst_n = 1;
        wait (pc == 28 && dut.state == 2);
        @(negedge clk); frame_boundary = 1;
        @(negedge clk); frame_boundary = 0;
        if (!waiting_frame || done || pc != 28) $fatal(1, "Issue-edge frame satisfied WAIT_FRAME");
        expect_register(0, 0); expect_register(1, 5); expect_register(2, 3);
        expect_register(3, 8); expect_register(4, 2); expect_register(5, 1);
        expect_register(6, 7); expect_register(7, 6); expect_register(8, 40);
        expect_register(9, 5); expect_register(10, 5); expect_register(11, 32'hFFFFFFFF);
        expect_register(12, 5); expect_register(13, 32'hFFFFFFFF); expect_register(14, 32'h12);
        expect_register(15, 0);
        if (!error || flags != 2 || accepted != 2 || received[0] != 32'h50000503 ||
            received[1] != 32'hF0000001 || retired != 24)
            $fatal(1, "ISA/branch/invalid/graphics/retirement result incorrect retired=%0d", retired);
        pause = 1;
        expect_pc_hold(28, 3);
        if (!waiting_frame || !busy) $fatal(1, "Paused in-flight WAIT_FRAME lost busy");
        frame_boundary = 1;
        @(negedge clk); frame_boundary = 0;
        wait (pc == 29 && dut.state == 2);
        expect_pc_hold(29, 3);
        expect_register(15, 0);
        if (busy || cmd_valid) $fatal(1, "Pause did not inhibit next ISSUE");
        clear_error = 1;
        @(negedge clk); clear_error = 0;
        if (error) $fatal(1, "Error clear failed");
        pause = 0;
        wait (halted); @(negedge clk);
        expect_register(15, 42);
        if (pc != 100 || ir != 32'hF0000000 || error || flags != 0 || retired != 28)
            $fatal(1, "Out-of-ROM branch HALT or retirement incorrect pc=%0d retired=%0d", pc, retired);

        // Pausa anterior a ISSUE, prioridade de novo erro e reinicio durante
        // o pulso grafico aceito cujo busy ainda esta atrasado.
        rst_n = 0; pause = 1;
        repeat (2) @(negedge clk);
        blank_program;
        dut.u_instruction_memory.memory[0] = 32'h20100007;
        dut.u_instruction_memory.memory[1] = 32'h0F000000;
        dut.u_instruction_memory.memory[2] = 32'h20200009;
        dut.u_instruction_memory.memory[3] = 32'hE0000000;
        rst_n = 1;
        wait (dut.state == 2); expect_pc_hold(0, 3);
        expect_register(1, 0);
        if (busy || done || accepted != 0) $fatal(1, "Pause allowed instruction side effects");
        clear_error = 1; manual_error = 1;
        @(negedge clk); clear_error = 0; manual_error = 0;
        if (!error) $fatal(1, "New error must override simultaneous clear");
        clear_error = 1;
        @(negedge clk); clear_error = 0; pause = 0;
        wait (accepted == 1);
        @(negedge clk); pause = 1; restart = 1;
        @(negedge clk); restart = 0;
        if (pc != 0 || ir != 32'hF0000000 || flags != 0 || error || !busy || !execution_busy)
            $fatal(1, "Restart did not reset architecture and drain delayed busy");
        expect_register(1, 0); expect_register(2, 0);
        repeat (3) begin
            @(negedge clk);
            if (pc != 0 || cmd_valid || !busy || accepted != 1)
                $fatal(1, "Restart issued or advanced while previous graphics was active");
        end
        wait (!execution_busy);
        wait (dut.state == 2); expect_pc_hold(0, 3);
        expect_register(1, 0);
        pause = 0;
        wait (halted); @(negedge clk);
        expect_register(1, 7); expect_register(2, 9);
        if (accepted != 2 || pc != 4 || error || busy)
            $fatal(1, "Resume/restart skipped or duplicated instruction");
        // Stall grafico na fase ISSUE seguido de pausa: ready pode subir sem
        // aceitar o comando; ao retomar deve ocorrer exatamente uma aceitacao.
        rst_n = 0; pause = 0; hold_ready = 1;
        repeat (2) @(negedge clk);
        blank_program;
        dut.u_instruction_memory.memory[0] = 32'h50000A0B;
        dut.u_instruction_memory.memory[1] = 32'hE5000000;
        rst_n = 1;
        wait (dut.state == 2); expect_pc_hold(0, 3);
        if (!cmd_valid || accepted != 0 || ir != 32'h50000A0B)
            $fatal(1, "Graphics command did not remain stable under ready stall");
        pause = 1; hold_ready = 0;
        expect_pc_hold(0, 3);
        if (cmd_valid || accepted != 0 || busy) $fatal(1, "Paused graphics ISSUE accepted a command");
        pause = 0;
        wait (accepted == 1);
        @(negedge clk); pause = 1;
        if (!busy) $fatal(1, "Paused accepted graphics operation lost busy before settle");
        wait (pc == 1 && dut.state == 2); expect_pc_hold(1, 3);
        if (accepted != 1 || retired != 1 || busy) $fatal(1, "Paused graphics did not finish exactly once");
        pause = 0;
        wait (halted); @(negedge clk);
        expect_register(0, 0);
        if (accepted != 1 || retired != 3 || pc != 2)
            $fatal(1, "Graphics pause/resume or STATUS r0 failed");
        $display("PASS tb_gpu_cpu_control: full ALU program, conditional/absolute branches, invalid isolation, STATUS, WAIT_FRAME edge, pause, error priority, restart drain and ROM bounds");
        $finish;
    end
    initial begin #50000; $fatal(1, "Timeout tb_gpu_cpu_control"); end
endmodule
