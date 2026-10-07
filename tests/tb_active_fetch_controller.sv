`timescale 1ns/1ps

module tb_active_fetch_controller;
    localparam integer ADDRESS_WIDTH = 8;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg cmd_ready = 1'b0;
    reg execution_busy = 1'b0;
    wire [31:0] cmd_data;
    wire cmd_valid;
    wire halted;
    wire [ADDRESS_WIDTH-1:0] pc;
    wire [31:0] ir;
    integer accepted_count = 0;
    integer run_index;
    integer command_index;

    active_fetch_controller #(
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .PROGRAM_WORDS(9),
        .PROGRAM_FILE("programs/fetch_demo.hex")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_ready(cmd_ready),
        .execution_busy(execution_busy),
        .cmd_data(cmd_data),
        .cmd_valid(cmd_valid),
        .halted(halted),
        .pc(pc),
        .ir(ir)
    );

    always #5 clk = ~clk;

    function automatic [31:0] expected_word(input integer word_address);
        case (word_address)
            0: expected_word = 32'h0f000000;
            1: expected_word = 32'h10fff800;
            2: expected_word = 32'h30020305;
            3: expected_word = 32'h50000804;
            4: expected_word = 32'h60000064;
            5: expected_word = 32'h70000a0a;
            6: expected_word = 32'h8000140a;
            7: expected_word = 32'h9ff00a14;
            default: expected_word = 32'hf0000000;
        endcase
    endfunction

    // Observe accepted transactions before the DUT's nonblocking assignments.
    always @(posedge clk) begin
        if (!rst_n) begin
            accepted_count = 0;
        end else if (cmd_valid && cmd_ready) begin
            if (accepted_count >= 8)
                $fatal(1, "Unexpected extra command or HALT sent to the decoder: %08h", cmd_data);
            if (cmd_data !== expected_word(accepted_count))
                $fatal(1, "Command %0d: expected %08h, received %08h",
                    accepted_count, expected_word(accepted_count), cmd_data);
            if (pc !== ADDRESS_WIDTH'(accepted_count) || ir !== cmd_data)
                $fatal(1, "PC/IR do not identify accepted command %0d", accepted_count);
            accepted_count = accepted_count + 1;
        end
    end

    task automatic check_stalled_command(input integer index);
        begin
            if (!cmd_valid || halted || pc !== ADDRESS_WIDTH'(index) ||
                ir !== expected_word(index) || cmd_data !== expected_word(index))
                $fatal(1, "Command %0d changed while cmd_ready was low", index);
        end
    endtask

    task automatic check_execution_hold(input integer index);
        begin
            if (pc !== ADDRESS_WIDTH'(index) || ir !== expected_word(index))
                $fatal(1, "PC/IR advanced before command %0d completed", index);
            if (cmd_valid || halted || accepted_count != index + 1)
                $fatal(1, "Command %0d was reissued or execution stopped prematurely", index);
        end
    endtask

    task automatic exercise_command(input integer index);
        begin
            // All stimulus changes occur on falling edges, away from acceptance.
            cmd_ready = 1'b0;
            execution_busy = 1'b0;
            while (!cmd_valid) begin
                if (halted)
                    $fatal(1, "Premature HALT before command %0d", index);
                @(negedge clk);
            end
            check_stalled_command(index);

            repeat (3) begin
                @(posedge clk);
                #1;
                check_stalled_command(index);
                @(negedge clk);
            end

            cmd_ready = 1'b1;
            @(posedge clk);
            #1;
            check_execution_hold(index);

            if (index == 0 || index == 7) begin
                // CLEAR/TRI busy is deliberately delayed by a full clock cycle.
                // ready stays high so an early PC increment cannot be hidden.
                @(negedge clk);
                @(posedge clk);
                #1;
                check_execution_hold(index);
                @(negedge clk);
                execution_busy = 1'b1;

                repeat (4) begin
                    @(posedge clk);
                    #1;
                    check_execution_hold(index);
                    @(negedge clk);
                end
                execution_busy = 1'b0;
                cmd_ready = 1'b0;
            end else begin
                @(negedge clk);
                cmd_ready = 1'b0;
            end

            // Completion also requires ready; !busy alone must not advance PC.
            repeat (2) begin
                @(posedge clk);
                #1;
                check_execution_hold(index);
                @(negedge clk);
            end

            cmd_ready = 1'b1;
            while (pc == ADDRESS_WIDTH'(index)) begin
                @(posedge clk);
                #1;
            end
            if (pc !== ADDRESS_WIDTH'(index + 1) || accepted_count != index + 1)
                $fatal(1, "Invalid completion of command %0d", index);
            @(negedge clk);
            cmd_ready = 1'b0;
        end
    endtask

    initial begin
        // Interrompe a primeira operacao para verificar reset durante busy.
        @(negedge clk);
        rst_n = 1'b1;
        cmd_ready = 1'b1;
        while (accepted_count == 0) @(negedge clk);
        cmd_ready = 1'b0;
        execution_busy = 1'b1;
        repeat (2) @(negedge clk);
        rst_n = 1'b0;
        #1;
        if (cmd_valid || halted || pc !== 0 || ir !== 32'hf0000000)
            $fatal(1, "Reset durante busy nao restaurou PC e IR");
        execution_busy = 1'b0;

        for (run_index = 0; run_index < 2; run_index = run_index + 1) begin
            @(negedge clk);
            rst_n = 1'b0;
            cmd_ready = 1'b0;
            execution_busy = 1'b0;
            repeat (2) begin
                @(posedge clk);
                #1;
                if (cmd_valid || halted || pc !== 0)
                    $fatal(1, "Reset did not restore the fetch controller");
            end
            @(negedge clk);
            rst_n = 1'b1;

            for (command_index = 0; command_index < 8; command_index = command_index + 1)
                exercise_command(command_index);

            while (!halted)
                @(negedge clk);
            if (pc !== 8'd8 || ir !== 32'hf0000000 || accepted_count != 8 || cmd_valid)
                $fatal(1, "HALT state or final accepted-command count is incorrect");

            cmd_ready = 1'b1;
            repeat (4) begin
                @(posedge clk);
                #1;
                if (!halted || cmd_valid || pc !== 8'd8 || ir !== 32'hf0000000 || accepted_count != 8)
                    $fatal(1, "HALT did not remain stable");
                @(negedge clk);
                execution_busy = ~execution_busy;
            end
        end

        $display("PASS tb_active_fetch_controller: command order, ready/busy stalls, delayed busy, HALT, reset during busy and restart");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "Timeout in tb_active_fetch_controller");
    end
endmodule
