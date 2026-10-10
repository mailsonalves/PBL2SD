`timescale 1ns/1ps

module tb_gpu_mmio;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 1;
    reg [5:0] address = 0;
    reg read = 0, write = 0;
    reg [31:0] writedata = 0;
    reg [3:0] byteenable = 0;
    reg [31:0] status = 32'h00002D4B;
    reg [31:0] pc = 32'h000000A6;
    reg [31:0] ir = 32'h22234000;
    reg frame_boundary = 0;
    wire [31:0] readdata;
    wire waitrequest, restart, pause, clear_error;

    gpu_mmio dut (
        .clk(clk), .rst_n(rst_n), .address(address), .read(read), .write(write),
        .writedata(writedata), .byteenable(byteenable), .status(status),
        .pc(pc), .ir(ir), .frame_boundary(frame_boundary), .readdata(readdata),
        .waitrequest(waitrequest), .restart(restart), .pause(pause),
        .clear_error(clear_error)
    );

    task automatic expect_outputs(input bit p, r, e);
        if (pause !== p || restart !== r || clear_error !== e || waitrequest !== 0)
            $fatal(1, "MMIO controle: pause/restart/clear=%b%b%b esperado=%b%b%b wait=%b",
                   pause, restart, clear_error, p, r, e, waitrequest);
    endtask

    task automatic read_register(input [5:0] offset, input [31:0] expected);
        begin
            // Sem borda de clock: confere o contrato de leitura combinacional.
            address = offset; read = 1;
            #1;
            if (readdata !== expected || waitrequest !== 0)
                $fatal(1, "MMIO leitura byte %02h: %08h esperado %08h", offset, readdata, expected);
            read = 0;
            #1;
            if (readdata !== 0)
                $fatal(1, "MMIO readdata deve ser zero quando read=0");
        end
    endtask

    task automatic write_register(
        input [5:0] offset, input [31:0] data, input [3:0] mask,
        input bit p, r, e
    );
        begin
            @(negedge clk);
            address = offset; writedata = data; byteenable = mask; write = 1;
            @(posedge clk); #1;
            expect_outputs(p, r, e);
            @(negedge clk); write = 0;
        end
    endtask

    task automatic idle(input bit expected_pause);
        begin
            @(negedge clk); write = 0; read = 0; frame_boundary = 0;
            @(posedge clk); #1;
            expect_outputs(expected_pause, 0, 0);
        end
    endtask

    task automatic reset_bus;
        begin
            @(negedge clk); rst_n = 0; write = 0; read = 0; frame_boundary = 0;
            #1;
            expect_outputs(0, 0, 0);
            read_register(6'h00, 0);
            read_register(6'h10, 0);
            @(negedge clk); rst_n = 1;
        end
    endtask

    integer offset, mask, control;
    reg [31:0] expected_read;
    initial begin
        reset_bus;
        // Todos os enderecos do span, incluindo desalinhados e indefinidos.
        for (offset = 0; offset < 64; offset++) begin
            case (offset)
                4: expected_read = status;
                8: expected_read = pc;
                12: expected_read = ir;
                20: expected_read = 32'h50424C32;
                default: expected_read = 0;
            endcase
            read_register(offset[5:0], expected_read);
        end

        // Leitura do estado externo muda sem nova transacao/borda.
        address = 4; read = 1;
        status = 32'h00003FFF; #1;
        if (readdata !== status) $fatal(1, "STATUS nao acompanha entrada");
        address = 8; pc = 32'h000000FF; #1;
        if (readdata !== pc) $fatal(1, "PC nao acompanha entrada");
        address = 12; ir = 32'hE2000008; #1;
        if (readdata !== ir) $fatal(1, "IR nao acompanha entrada");
        read = 0;

        // Cada combinacao dos tres controles e das quatro byteenables.
        for (mask = 0; mask < 16; mask++) begin
            for (control = 0; control < 8; control++) begin
                write_register(0, 32'hFFFFFFF8 | control, mask[3:0],
                               mask[0] ? control[0] : 1'b0,
                               mask[0] ? control[1] : 1'b0,
                               mask[0] ? control[2] : 1'b0);
                idle(mask[0] ? control[0] : 1'b0);
                read_register(0, mask[0] ? {31'd0, control[0]} : 32'd0);
                // Reestabelece pause=0 para a proxima transacao ignorada.
                write_register(0, 0, 4'b0001, 0, 0, 0);
            end
        end

        // Writes RO/desalinhados/indefinidos preservam pause e nunca pulsam.
        write_register(0, 1, 4'hF, 1, 0, 0);
        for (offset = 1; offset < 64; offset++)
            write_register(offset[5:0], 32'hFFFFFFFF, 4'hF, 1, 0, 0);
        read_register(0, 1);
        read_register(4, status); read_register(8, pc); read_register(12, ir);
        read_register(16, 0); read_register(20, 32'h50424C32);

        // write=0 nao aceita nem mesmo uma palavra com todos os controles.
        @(negedge clk); address = 0; writedata = 7; byteenable = 4'hF; write = 0;
        @(posedge clk); #1; expect_outputs(1, 0, 0);

        // Transacoes consecutivas sao aceitas a cada borda (waitrequest=0).
        @(negedge clk); write = 1; address = 0; writedata = 3;
        @(posedge clk); #1; expect_outputs(1, 1, 0);
        read_register(0, 1); // Os bits de pulso nunca sao lidos de volta.
        @(negedge clk); address = 0; writedata = 4;
        @(posedge clk); #1; expect_outputs(0, 0, 1);
        @(negedge clk); writedata = 6;
        @(posedge clk); #1; expect_outputs(0, 1, 1);
        idle(0);

        // Contagem independe de read, pause, restart e clear_error.
        @(negedge clk); address = 0; write = 1; writedata = 7; frame_boundary = 1;
        @(posedge clk); #1; expect_outputs(1, 1, 1);
        read_register(16, 1);
        @(negedge clk); write = 0; frame_boundary = 0;
        @(posedge clk); #1; expect_outputs(1, 0, 0);
        read_register(16, 1);
        repeat (3) begin
            @(negedge clk); frame_boundary = 1;
            @(posedge clk); #1;
        end
        @(negedge clk); frame_boundary = 0;
        read_register(16, 4);

        // Contador de 32 bits tem wrap modulo 2^32.
        // Seed dirigido evita simular quatro bilhoes de eventos de VGA.
        @(negedge clk); dut.frame_count = 32'hFFFFFFFF; frame_boundary = 1;
        @(posedge clk); #1;
        read_register(16, 0);
        @(negedge clk); frame_boundary = 0;

        // Reset assincrono cancela pulso pendente, pausa e contador.
        write_register(0, 7, 4'hF, 1, 1, 1);
        rst_n = 0; #1; expect_outputs(0, 0, 0);
        read_register(16, 0);
        reset_bus;
        idle(0);
        $display("PASS: MMIO byte-address, span/RO/alinhamento, leituras combinacionais, byteenables, controles/pulsos, frames e reset");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Timeout MMIO");
    end
endmodule
