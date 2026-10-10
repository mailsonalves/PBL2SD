`timescale 1ns/1ps

// O master pode iniciar uma transacao assim que seu reset e liberado. O slave
// deve esperar os dois clocks internos, sem aceitar e perder CONTROL.
module tb_gpu_avalon_reset;
    reg clk = 0;
    always #10 clk = ~clk;
    reg reset_n = 0;
    reg [3:0] keys = 4'hf;
    reg read = 0, write = 0;
    reg [5:0] address = 0;
    reg [31:0] writedata = 1;
    wire [31:0] readdata;
    wire waitrequest;
    integer accepted_writes = 0;

    gpu_avalon #(.PROGRAM_WORDS(1), .PROGRAM_FILE("tests/fixtures/halt.hex")) dut (
        .clk(clk), .reset_n(reset_n), .KEY(keys), .SW(10'd0), .LEDR(),
        .address(address), .read(read), .write(write), .writedata(writedata),
        .byteenable(4'hf), .readdata(readdata), .waitrequest(waitrequest),
        .VGA_HS(), .VGA_VS(), .VGA_R(), .VGA_G(), .VGA_B(),
        .VGA_BLANK_N(), .VGA_SYNC_N(), .VGA_CLK()
    );

    always @(posedge clk)
        if (write && !waitrequest) accepted_writes = accepted_writes + 1;

    task automatic release_with_pending_write(input bit key_reset);
        integer stalls, previous_writes;
        begin
            previous_writes = accepted_writes;
            @(negedge clk);
            address = 0; writedata = 1; write = 1; read = 0;
            if (key_reset) keys[0] = 1;
            else reset_n = 1;
            stalls = 0;
            @(posedge clk);
            while (waitrequest) begin
                stalls = stalls + 1;
                if (stalls > 8) $fatal(1, "Reset Avalon did not release");
                @(posedge clk);
            end
            #1;
            if (stalls != 2 || accepted_writes != previous_writes + 1)
                $fatal(1, "Expected two internal-reset stalls and exactly one accepted write: %0d/%0d",
                       stalls, accepted_writes - previous_writes);
            @(negedge clk); write = 0; read = 1;
            #1;
            if (waitrequest || readdata !== 32'd1)
                $fatal(1, "CONTROL was acknowledged but lost during reset release: %h", readdata);
            @(negedge clk); read = 0;
        end
    endtask

    integer stalls;
    initial begin
        repeat (3) @(negedge clk);
        if (waitrequest !== 1) $fatal(1, "Slave must stall while reset is active");
        release_with_pending_write(0);

        // KEY pode resetar apenas a GPU enquanto o master HPS continua ativo.
        @(negedge clk); keys[0] = 0;
        repeat (2) @(negedge clk);
        if (waitrequest !== 1) $fatal(1, "KEY reset must also stall the external bus");
        release_with_pending_write(1);

        // Uma leitura pendente tambem permanece estavel ate ser aceita.
        @(negedge clk); reset_n = 0; address = 6'h14; read = 1;
        repeat (2) @(negedge clk);
        if (!waitrequest) $fatal(1, "Read accepted while reset was active");
        reset_n = 1;
        stalls = 0;
        @(posedge clk);
        while (waitrequest) begin
            stalls = stalls + 1;
            if (stalls > 8) $fatal(1, "Pending read remained stalled after reset");
            @(posedge clk);
        end
        if (stalls != 2 || readdata !== 32'h50424c32)
            $fatal(1, "Read was acknowledged before internal reset release or lost ID");
        @(negedge clk); read = 0;
        if (accepted_writes != 2) $fatal(1, "Write duplicated during reset stall");
        $display("PASS tb_gpu_avalon_reset: pending writes/reads held through two-clock reset release and KEY reset, exactly once");
        $finish;
    end
    initial begin #10000; $fatal(1, "Timeout Avalon reset integration"); end
endmodule
