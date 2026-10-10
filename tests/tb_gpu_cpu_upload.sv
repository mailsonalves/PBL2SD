`timescale 1ns/1ps
module tb_gpu_cpu_upload;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, restart = 0, pause = 1, load_mode = 1, frame_boundary = 0;
    reg cmd_ready = 1, execution_busy = 0;
    reg [8:0] program_length = 256, program_address = 0;
    reg program_write = 0;
    reg [31:0] program_writedata = 0;
    reg [3:0] program_byteenable = 4'hF;
    wire [31:0] program_readdata, cmd_data, ir;
    wire program_ready, cmd_valid, halted, busy, done, error, waiting_frame;
    wire [7:0] pc;
    wire [3:0] flags;
    active_fetch_controller #(.PROGRAM_WORDS(256), .ENABLE_PROGRAM_UPLOAD(1),
        .PROGRAM_FILE("programs/background_sprites.hex")) dut (
        .clk(clk), .rst_n(rst_n), .cmd_ready(cmd_ready), .execution_busy(execution_busy),
        .frame_boundary(frame_boundary), .restart(restart), .pause(pause),
        .clear_error(1'b0), .cmd_error(1'b0), .load_mode(load_mode),
        .program_length(program_length), .program_address(program_address),
        .program_write(program_write), .program_writedata(program_writedata),
        .program_byteenable(program_byteenable), .program_readdata(program_readdata),
        .program_ready(program_ready), .cmd_data(cmd_data), .cmd_valid(cmd_valid),
        .halted(halted), .busy(busy), .done(done), .error(error), .waiting_frame(waiting_frame),
        .flags(flags), .pc(pc), .ir(ir));
    integer accepted = 0, retired = 0, phase = 0, delay_cycles = 0, index;
    reg model_enable = 0;
    always @(posedge clk) begin
        if (!rst_n) begin accepted = 0; phase <= 0; execution_busy <= 0; end
        else if (model_enable) begin
            if (phase == 1) begin execution_busy <= 1; delay_cycles <= 4; phase <= 2; end
            else if (phase == 2) begin
                if (halted) $fatal(1, "Last graphic halted before execution completed");
                if (delay_cycles == 0) begin execution_busy <= 0; phase <= 0; end
                else delay_cycles <= delay_cycles - 1;
            end
            if (cmd_valid && cmd_ready) begin
                if (phase != 0 || pc != 255 || cmd_data != 32'h50000304)
                    $fatal(1, "Unexpected graphics transaction at PC %0d: %h", pc, cmd_data);
                accepted = accepted + 1; phase <= 1;
            end
        end
    end
    always @(posedge clk) begin
        #1;
        if (!rst_n || restart) retired = 0;
        else if (done) retired = retired + 1;
    end
    task automatic upload(input [8:0] addr, input [31:0] data, input [3:0] bytes);
        @(negedge clk);
        if (!program_ready) $fatal(1, "Upload attempted while CPU not ready");
        program_address = addr; program_writedata = data; program_byteenable = bytes; program_write = 1;
        @(negedge clk); program_write = 0;
    endtask
    task automatic readback(input [8:0] addr, input [31:0] expected);
        @(negedge clk); program_address = addr;
        @(posedge clk); #1;
        if (program_readdata !== expected)
            $fatal(1, "Readback %0d=%h expected %h", addr, program_readdata, expected);
    endtask
    task automatic enter_upload;
        @(negedge clk); pause = 1; load_mode = 1; restart = 1;
        @(negedge clk); restart = 0;
        wait (program_ready);
    endtask
    task automatic run_program;
        @(negedge clk); load_mode = 0; pause = 0; restart = 1;
        @(negedge clk); restart = 0;
    endtask
    task automatic rejected_write;
        program_address = 0; program_writedata = 32'hDEADBEEF;
        program_byteenable = 4'hF; program_write = 1;
        @(negedge clk); program_write = 0;
        if (dut.u_instruction_memory.memory[0] == 32'hDEADBEEF)
            $fatal(1, "Write accepted while program_ready=0");
    endtask
    initial begin
        @(negedge clk); rejected_write;
        rst_n = 1;
        wait (program_ready);
        @(negedge clk); cmd_ready = 0; #1;
        if (program_ready) $fatal(1, "Upload ready while cmd_ready=0");
        rejected_write;
        cmd_ready = 1; execution_busy = 1; #1;
        if (program_ready) $fatal(1, "Upload ready while execution busy");
        rejected_write;
        execution_busy = 0; restart = 1; #1;
        if (program_ready) $fatal(1, "Upload ready during restart");
        rejected_write;
        restart = 0;
        wait (program_ready);
        upload(0, 32'h20100007, 4'hF);
        upload(0, 32'h00001200, 4'b0010);
        upload(1, 32'h2A110001, 4'hF);
        upload(2, 32'h2020BEEF, 4'hF);
        upload(255, 32'h50000304, 4'hF);
        program_length = 2;
        readback(0, 32'h20101207);
        readback(255, 32'h50000304); // length nao limita inspeccao da RAM.
        upload(256, 32'hDEADBEEF, 4'hF);
        readback(256, 32'hF0000000);
        readback(0, 32'h20101207);
        run_program;
        wait (halted); @(negedge clk);
        if (pc != 2 || ir != 32'hF0000000 || error || retired != 3 ||
            dut.datapath.u_registers.registers[1] != 32'h1208 ||
            dut.datapath.u_registers.registers[2] != 0)
            $fatal(1, "Short length executed stale tail or wrong loaded program");
        // Reset conserva a RAM e o comprimento recebido; apenas arquitetura zera.
        rst_n = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        wait (halted); @(negedge clk);
        if (pc != 2 || dut.datapath.u_registers.registers[1] != 32'h1208 ||
            dut.u_instruction_memory.memory[2] != 32'h2020BEEF)
            $fatal(1, "Reset changed RAM or short-length behavior");

        enter_upload;
        for (index = 0; index < 256; index = index + 1)
            upload(9'(index), (index == 0) ? 32'h2A550001 :
                   (index == 255) ? 32'h50000304 : 32'hE0000000, 4'hF);
        program_length = 256; model_enable = 1;
        run_program;
        wait (halted); @(negedge clk);
        if (pc != 255 || ir != 32'hF0000000 || accepted != 1 || retired != 257 ||
            dut.datapath.u_registers.registers[5] != 1 || error || execution_busy)
            $fatal(1, "Full 256-word fallthrough wrapped or lost final graphics retired=%0d", retired);

        // JMP explicito na ultima palavra ainda pode voltar ao inicio.
        model_enable = 0; enter_upload;
        upload(255, 32'hE2000000, 4'hF);
        run_program;
        wait (dut.datapath.u_registers.registers[5] == 2);
        @(negedge clk); pause = 1;
        if (halted) $fatal(1, "Explicit branch at PC255 was replaced by HALT");
        enter_upload;
        upload(0, 32'hE20000FF, 4'hF);
        upload(255, 32'h20700063, 4'hF);
        run_program;
        wait (halted); @(negedge clk);
        if (pc != 255 || retired != 3 || dut.datapath.u_registers.registers[7] != 99)
            $fatal(1, "Last-address ALU retirement or branch target failed");
        $display("PASS tb_gpu_cpu_upload: ready gating, byte upload/readback bounds, short length, reset persistence, 256-word graphics drain/no wrap and last-word explicit branch/ALU");
        $finish;
    end
    initial begin #100000; $fatal(1, "Timeout tb_gpu_cpu_upload"); end
endmodule
