`timescale 1ns/1ps

module tb_instruction_memory;
    localparam integer ADDRESS_WIDTH = 8;

    reg clk = 1'b0;
    reg [ADDRESS_WIDTH-1:0] address = 0;
    wire [31:0] instruction;
    integer index;

    instruction_memory #(
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .PROGRAM_WORDS(9),
        .PROGRAM_FILE("programs/fetch_demo.hex")
    ) dut (
        .clk(clk),
        .address(address),
        .write_enable(1'b0), .write_address(9'd0), .write_data(32'd0), .write_byteenable(4'd0),
        .instruction(instruction)
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

    // An address change must affect the output only at the next rising edge.
    task automatic check_read(input reg [ADDRESS_WIDTH-1:0] next_address);
        reg [31:0] previous_instruction;
        begin
            @(negedge clk);
            previous_instruction = instruction;
            address = next_address;
            #1;
            if (instruction !== previous_instruction)
                $fatal(1, "ROM output changed before the rising edge at address %0d", address);

            @(posedge clk);
            #1;
            if (instruction !== expected_word(int'(address)))
                $fatal(1, "ROM address %0d: expected %08h, received %08h",
                    address, expected_word(int'(address)), instruction);
        end
    endtask

    initial begin
        @(posedge clk);
        #1;
        if (instruction !== expected_word(0))
            $fatal(1, "ROM did not load the first program word");

        for (index = 1; index < 9; index = index + 1)
            check_read(ADDRESS_WIDTH'(index));

        // The first invalid word and distant addresses must safely stop execution.
        check_read(8'd9);
        check_read(8'd17);
        check_read(8'hff);
        check_read(8'd3);
        check_read(8'd0);

        $display("PASS tb_instruction_memory: program contents, synchronous reads and out-of-range HALT");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "Timeout in tb_instruction_memory");
    end
endmodule
