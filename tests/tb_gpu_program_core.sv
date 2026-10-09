`timescale 1ns/1ps
module tb_gpu_program_core;
    reg clk=0,rst_n=0,cmd_ready=0,execution_busy=0,cmd_error=0,frame_boundary=0;
    reg [9:0] sw_state=10'h2A5;
    reg [2:0] key_state=3'b101;
    reg buffer_initialized=1,buffer_front=0,buffer_double_buffered=1;
    wire [31:0] cmd_data,ir,status,user_output;
    wire cmd_valid,halted,retired;
    wire [11:0] pc;
    integer phase=0,accepted=0,outputs=0,invalid_retired=0,held_cycles=0;
    reg [31:0] expected_outputs [0:16];
    reg [31:0] observed_ir,previous_output;
    reg [11:0] observed_pc;
    gpu_program_core #(.ADDRESS_WIDTH(12),.PROGRAM_WORDS(103),
        .PROGRAM_FILE("tests/fixtures/program_core_cases.hex")) dut (.*);
    always #5 clk=~clk;

    // Outputs are independent expected signatures, not recomputed from DUT
    // registers. A wrong branch reaches an unexpected OUT and fails immediately.
    always @(posedge clk) begin
        observed_ir=ir; observed_pc=pc; previous_output=user_output;
        if(phase==1 && rst_n && cmd_valid && cmd_ready) begin
            case(accepted)
                0: if(cmd_data !== 32'h50000A14) $fatal(1,"Indirect command wrong");
                1: if(cmd_data !== 32'h10000001) $fatal(1,"Literal command wrong");
                2: if(cmd_data !== 32'hF0000000) $fatal(1,"Indirect HALT-shaped payload wrong");
                default: $fatal(1,"Duplicated or invalid instruction sent as graphics");
            endcase
            accepted=accepted+1;
        end
        #1;
        if(phase==1 && rst_n) begin
            if(retired && observed_ir[31:24]==8'hE6 && observed_ir[19:0]==0) begin
                if(outputs>=17 || user_output !== expected_outputs[outputs])
                    $fatal(1,"OUT[%0d] PC%0d got %08x expected %08x",outputs,observed_pc,
                           user_output,expected_outputs[outputs]);
                outputs=outputs+1;
            end else if(user_output !== previous_output)
                $fatal(1,"Output changed without legal OUT at PC%0d",observed_pc);
            if(retired && observed_pc>=49 && observed_pc<=77 && observed_pc[0]) begin
                invalid_retired=invalid_retired+1;
                if(!status[4]) $fatal(1,"Invalid instruction failed to accumulate error PC%0d",observed_pc);
                if(cmd_valid) $fatal(1,"Invalid CPU instruction emitted graphic command");
            end
            if(retired && observed_pc>=50 && observed_pc<=76 && !observed_pc[0] && status[4])
                $fatal(1,"CLRE did not isolate rejection case at PC%0d",observed_pc);
            if($isunknown({pc,ir,cmd_valid,cmd_data,status,user_output,halted,retired}))
                $fatal(1,"Undefined initialized CPU signal");
        end
    end

    task automatic tick;
        begin @(posedge clk); #2; end
    endtask
    task automatic pulse_frame;
        begin
            @(negedge clk); frame_boundary=1;
            tick();
            @(negedge clk); frame_boundary=0;
        end
    endtask
    task automatic hold_graphics(input integer expected_pc,input reg [31:0] expected_ir,
                                 input reg [31:0] expected_command,input bit expected_valid);
        begin
            tick();
            if(pc !== expected_pc || ir !== expected_ir || cmd_data !== expected_command ||
               cmd_valid !== expected_valid || halted)
                $fatal(1,"PC/IR/command changed during graphics wait PC=%0d expected=%0d",pc,expected_pc);
            held_cycles=held_cycles+1;
        end
    endtask

    initial begin
        expected_outputs[0]=6; expected_outputs[1]=32'h505;
        expected_outputs[2]=32'h22; expected_outputs[3]=32'h44;
        expected_outputs[4]=32'h2A5; expected_outputs[5]=5;
        expected_outputs[6]=2; expected_outputs[7]=32'h50000A14;
        expected_outputs[8]=4; expected_outputs[9]=32'hD00;
        expected_outputs[10]=123; expected_outputs[11]=32'hD10;
        expected_outputs[12]=32'hD10; expected_outputs[13]=32'hD00;
        expected_outputs[14]=0; expected_outputs[15]=32'hD05;
        expected_outputs[16]=32'h88;
        #1; rst_n=1; #1; rst_n=0;
        repeat(2) tick();
        @(negedge clk); rst_n=1;
        // First attempt deliberately resets with a command stalled and busy.
        wait(cmd_valid);
        @(negedge clk); execution_busy=1;
        hold_graphics(38,32'h4A000000,32'h50000A14,1);
        @(negedge clk); #2; rst_n=0; #1;
        if(pc !== 0 || ir !== 32'hF0000000 || cmd_valid || halted || user_output !== 0 ||
           status[4:0] !== 0 || dut.u_frame_control.frame_counter !== 0)
            $fatal(1,"Reset failed while waiting for busy graphics");
        repeat(2) tick();
        @(negedge clk); execution_busy=0; phase=1; rst_n=1;
        // Earlier frame pulses must not satisfy a later WAIT_FRAME.
        pulse_frame(); pulse_frame();

        wait(cmd_valid);
        repeat(4) hold_graphics(38,32'h4A000000,32'h50000A14,1);
        @(negedge clk); cmd_ready=1;
        hold_graphics(38,32'h4A000000,32'h50000A14,0);
        // A registered decoder drops ready first; busy arrives one clock later.
        @(negedge clk); cmd_ready=0;
        hold_graphics(38,32'h4A000000,32'h50000A14,0);
        @(negedge clk); execution_busy=1;
        repeat(6) hold_graphics(38,32'h4A000000,32'h50000A14,0);
        if(!status[6] || status[11]) $fatal(1,"Busy/ready live status incorrect");
        @(negedge clk); execution_busy=0;
        repeat(3) hold_graphics(38,32'h4A000000,32'h50000A14,0);
        @(negedge clk); cmd_ready=1;
        tick(); if(pc !== 39) $fatal(1,"Command did not retire after busy and ready");

        wait(cmd_valid); hold_graphics(39,32'h10000001,32'h10000001,0);
        @(negedge clk); execution_busy=1;
        repeat(5) hold_graphics(39,32'h10000001,32'h10000001,0);
        @(negedge clk); execution_busy=0;
        tick(); if(pc !== 40) $fatal(1,"Literal command failed to retire");

        wait(cmd_valid);
        @(negedge clk); cmd_error=1;
        hold_graphics(42,32'h4A000000,32'hF0000000,0);
        if(!status[4] || halted) $fatal(1,"Graphic error or indirect payload HALT handling failed");
        @(negedge clk); cmd_error=0;
        tick(); tick();

        // A boundary coincident with entering WAIT is counted, but cannot
        // satisfy the new wait. The next boundary must retire the instruction.
        wait(pc==44 && ir==32'hE0000000);
        @(negedge clk); frame_boundary=1;
        tick();
        if(!status[7] || pc !== 44) $fatal(1,"WAIT consumed entry boundary");
        @(negedge clk); frame_boundary=0;
        repeat(7) begin
            tick();
            if(pc !== 44 || ir !== 32'hE0000000 || !status[7] || cmd_valid)
                $fatal(1,"WAIT_FRAME failed to hold for next frame");
        end
        pulse_frame();
        if(pc !== 45 || status[7]) $fatal(1,"WAIT_FRAME did not retire on next frame");

        wait(pc==81 && ir==32'h2D000000);
        @(negedge clk); cmd_error=1;
        tick(); if(!status[4]) $fatal(1,"CLRE defeated simultaneous error");
        @(negedge clk); cmd_error=0;
        wait(halted); #2;
        if(pc !== 102 || ir !== 32'hF0000000 || cmd_valid || !status[5] || status[4] || status[3:0] !== 4)
            $fatal(1,"Canonical HALT/status wrong");
        if(outputs!=17 || accepted!=3 || invalid_retired!=15)
            $fatal(1,"Coverage incomplete: OUT=%0d command=%0d invalid=%0d",outputs,accepted,invalid_retired);
        if(dut.u_register_file.registers[0] !== 0)
            $fatal(1,"Core corrupted R0");
        pulse_frame();
        if(dut.u_frame_control.frame_counter !== 5) $fatal(1,"Frame counter stopped at HALT");
        repeat(10) begin
            tick();
            if(!halted || pc !== 102 || ir !== 32'hF0000000 || cmd_valid || retired)
                $fatal(1,"HALT did not hold PC/IR quietly");
        end
        $display("PASS tb_gpu_program_core: %0d outputs, %0d commands, %0d invalid instructions, %0d held cycles; branches/IN/status/CLRE/WAIT/HALT/reset",
                 outputs,accepted,invalid_retired,held_cycles);
        $finish;
    end
    initial begin #30000; $fatal(1,"CPU timeout PC=%0d IR=%08x status=%08x",pc,ir,status); end
endmodule
