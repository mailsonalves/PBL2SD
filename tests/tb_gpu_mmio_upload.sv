`timescale 1ns/1ps

module tb_gpu_mmio_upload;
    localparam integer CAPACITY = 256;
    localparam [31:0] CAPACITY_STATUS = CAPACITY << 16;
    localparam [31:0] PARTIAL_WORD = 32'h76543210;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 1;
    reg [5:0] address = 0;
    reg read = 0, write = 0;
    reg [31:0] writedata = 0;
    reg [3:0] byteenable = 0;
    reg frame_boundary = 0;
    reg program_ready = 0;
    reg [31:0] program_readdata = 0;
    wire [31:0] readdata, program_writedata;
    wire [3:0] program_byteenable;
    wire waitrequest, restart, pause, clear_error, load_mode, program_write;
    wire [8:0] program_length, program_address;

    gpu_mmio #(.PROGRAM_WORDS(CAPACITY)) dut (
        .clk(clk), .rst_n(rst_n), .address(address), .read(read), .write(write),
        .writedata(writedata), .byteenable(byteenable), .status(32'h1234),
        .pc(32'd7), .ir(32'hF0000000), .frame_boundary(frame_boundary),
        .program_ready(program_ready), .program_readdata(program_readdata),
        .readdata(readdata), .waitrequest(waitrequest), .restart(restart),
        .pause(pause), .clear_error(clear_error), .load_mode(load_mode),
        .program_length(program_length), .program_address(program_address),
        .program_write(program_write), .program_writedata(program_writedata),
        .program_byteenable(program_byteenable)
    );

    // Modelo de RAM: leitura sincrona existente e escrita na mesma borda.
    // Nao reseta RAM, como a memoria de instrucoes FPGA.
    reg [31:0] memory [0:CAPACITY-1];
    integer writes = 0;
    integer lane;
    always @(posedge clk) begin
        program_readdata <= program_address < CAPACITY[8:0] ? memory[program_address[7:0]] : 32'hF0000000;
        if (program_write) begin
            if (!rst_n || !load_mode || !program_ready || program_address >= CAPACITY[8:0])
                $fatal(1, "Write RAM inseguro");
            for (lane = 0; lane < 4; lane++)
                if (program_byteenable[lane])
                    memory[program_address[7:0]][lane*8 +: 8] <= program_writedata[lane*8 +: 8];
            writes = writes + 1;
        end
    end

    task automatic write_register(input [5:0] offset, input [31:0] word, input [3:0] mask);
        begin
            @(negedge clk);
            address = offset; writedata = word; byteenable = mask; write = 1; read = 0;
            #1;
            if (waitrequest !== 0) $fatal(1, "Write nao deve dar backpressure");
            @(posedge clk); #1;
            @(negedge clk); write = 0;
        end
    endtask

    task automatic read_register(input [5:0] offset, input [31:0] expected);
        begin
            address = offset; read = 1; write = 0;
            #1;
            if (readdata !== expected || waitrequest !== !rst_n)
                $fatal(1, "Read %02h: data=%08h wait=%b esperado=%08h",
                       offset, readdata, waitrequest, expected);
            read = 0; #1;
            if (readdata !== 0 || waitrequest !== !rst_n)
                $fatal(1, "Read=0 deve liberar barramento somente fora de reset");
        end
    endtask

    task automatic read_program(input [31:0] expected, input integer expected_stalls);
        integer stalls;
        reg [8:0] old_address;
        begin
            old_address = program_address;
            address = 6'h1C; read = 1; write = 0;
            stalls = 0; #1;
            while (waitrequest !== 0) begin
                @(posedge clk); #1;
                stalls = stalls + 1;
                if (stalls > 4) $fatal(1, "Readback nao libera waitrequest");
            end
            if (stalls != expected_stalls || readdata !== expected)
                $fatal(1, "Readback addr=%0d data=%08h esperado=%08h stalls=%0d esperado=%0d",
                       old_address, readdata, expected, stalls, expected_stalls);
            @(posedge clk); #1;
            if (readdata !== expected || program_address !== old_address)
                $fatal(1, "Leitura aceita mudou dados ou incrementou endereco");
            read = 0;
        end
    endtask

    task automatic controls(input bit expected_load, expected_pause, expected_restart, expected_clear);
        if (load_mode !== expected_load || pause !== expected_pause ||
            restart !== expected_restart || clear_error !== expected_clear)
            $fatal(1, "Controles load/pause/restart/clear=%b%b%b%b esperado=%b%b%b%b",
                   load_mode, pause, restart, clear_error,
                   expected_load, expected_pause, expected_restart, expected_clear);
    endtask

    task automatic clear_loader_error;
        begin
            write_register(0, 32'hC, 1); // Mantem load_mode e limpa erros.
            controls(1, 1, 0, 1);
            read_register(6'h24, CAPACITY_STATUS | 1);
        end
    endtask

    integer index, mask, control_word, saved_writes;
    reg [31:0] expected;
    bit expected_load, expected_stored_pause, old_load;
    initial begin
        for (index = 0; index < CAPACITY; index++) memory[index] = 32'hA5A50000 | index;
        @(negedge clk); rst_n = 0;
        #1; controls(0, 0, 0, 0);
        read_register(6'h18, 0); read_register(6'h20, CAPACITY);
        read_register(6'h24, CAPACITY_STATUS);
        @(negedge clk); rst_n = 1;
        // Upload fora do modo ou antes de drain/pronto nunca modifica a RAM.
        write_register(6'h1C, 32'hDEADBEEF, 15);
        if (writes != 0) $fatal(1, "Carga aceita fora de load_mode");
        read_register(6'h24, CAPACITY_STATUS | 2);
        write_register(0, 8, 1); // Entrada forca restart e pausa.
        controls(1, 1, 1, 0);
        read_register(0, 9);
        read_register(6'h24, CAPACITY_STATUS);
        write_register(6'h1C, 32'hDEADBEEF, 15);
        write_register(6'h18, 3, 15);
        write_register(6'h20, 3, 15);
        if (writes != 0 || program_address != 0 || program_length != CAPACITY[8:0])
            $fatal(1, "Carga ou metadata alterada antes do drain");
        read_register(6'h24, CAPACITY_STATUS | 2);
        @(negedge clk); program_ready = 1;
        clear_loader_error;

        // Todas as byteenables: zero e noop, partial preserva bytes restantes.
        for (mask = 0; mask < 16; mask++) begin
            @(negedge clk); memory[0] = 32'hFEDCBA98;
            write_register(6'h18, 0, 15);
            saved_writes = writes;
            write_register(6'h1C, PARTIAL_WORD, mask[3:0]);
            expected = 32'hFEDCBA98;
            for (index = 0; index < 4; index++)
                if (mask[index]) expected[index*8 +: 8] = PARTIAL_WORD[index*8 +: 8];
            if (writes != saved_writes + (mask != 0 ? 1 : 0) ||
                program_address != (mask != 0 ? 9'd1 : 9'd0))
                $fatal(1, "Byteenable %h alterou numero de writes/autoincremento", mask);
            if (memory[0] !== expected) $fatal(1, "Byteenable %h corrompeu bytes", mask);
            write_register(6'h18, 0, 15);
            read_program(expected, 2);
            read_program(expected, 0);
        end

        // Escritas consecutivas usam os enderecos 0 e 1 (sem deslocamento).
        write_register(6'h18, 0, 15);
        @(negedge clk); address = 6'h1C; write = 1; writedata = 32'h11223344; byteenable = 15;
        @(posedge clk); #1;
        if (memory[0] !== 32'h11223344 || program_address != 1)
            $fatal(1, "Primeira palavra escrita no endereco incorreto");
        @(negedge clk); writedata = 32'h55667788;
        @(posedge clk); #1;
        if (memory[1] !== 32'h55667788 || program_address != 2)
            $fatal(1, "Segunda palavra escrita no endereco incorreto");
        @(negedge clk); write = 0;
        read_register(6'h18, 2); // Outros registros nunca stall durante cooldown.

        // Merges9bits, sentinela 256 e rejeicao sem wrap/truncamento.
        write_register(6'h18, 255, 15);
        write_register(6'h1C, 32'hCAFEBABE, 15);
        if (memory[255] !== 32'hCAFEBABE || program_address != 256)
            $fatal(1, "Ultima palavra nao foi preservada ou ponteiro deu wrap");
        saved_writes = writes;
        read_program(32'hF0000000, 0);
        write_register(6'h1C, 0, 15);
        if (writes != saved_writes || program_address != 256)
            $fatal(1, "Sentinela modificou RAM/endereco");
        read_register(6'h24, CAPACITY_STATUS | 3);
        write_register(6'h18, 257, 15);
        read_register(6'h18, 256);
        clear_loader_error;
        write_register(6'h18, 0, 2); // Limpa somente bit8 do ponteiro.
        read_register(6'h18, 0);
        write_register(6'h18, 255, 1);
        write_register(6'h18, 256, 2); // Merge seria 511: rejeitar.
        read_register(6'h18, 255);
        read_register(6'h24, CAPACITY_STATUS | 3);
        clear_loader_error;
        write_register(6'h18, 0, 1);
        write_register(6'h18, 256, 2);
        read_register(6'h18, 256);

        // Limite de programa valida 1..capacidade e merge de bytes.
        write_register(6'h20, 17, 15);
        read_register(6'h20, 17);
        write_register(6'h20, 0, 15);
        write_register(6'h20, 257, 15);
        read_register(6'h20, 17);
        read_register(6'h24, CAPACITY_STATUS | 3);
        clear_loader_error;
        write_register(6'h20, 256, 15);
        write_register(6'h20, 1, 1); // Merge=257: rejeitar.
        read_register(6'h20, 256);
        clear_loader_error;
        write_register(6'h20, 17, 15);
        // Bytes2/3 e enderecos desalinhados nao afetam registros/programa.
        saved_writes = writes;
        write_register(6'h18, 32'hFFFFFFFF, 12);
        write_register(6'h20, 32'hFFFFFFFF, 12);
        write_register(6'h1D, 32'hFFFFFFFF, 15);
        read_register(6'h18, 256); read_register(6'h20, 17);
        if (writes != saved_writes) $fatal(1, "Write indefinido atingiu RAM");

        // Nenhum efeito pode ocorrer numa transferencia ainda em waitrequest.
        write_register(6'h18, 1, 15);
        saved_writes = writes;
        address = 6'h1C; read = 1; write = 1; writedata = 32'h01020304; byteenable = 15;
        #1; if (waitrequest !== 1 || program_write !== 0) $fatal(1, "Read cooldown nao bloqueou write conjunto");
        @(posedge clk); #1;
        if (waitrequest !== 1 || writes != saved_writes) $fatal(1, "Primeiro ciclo stall teve write");
        @(posedge clk); #1;
        if (waitrequest !== 0 || writes != saved_writes) $fatal(1, "Segundo ciclo stall teve write");
        @(posedge clk); #1;
        if (writes != saved_writes + 1 || memory[1] !== 32'h01020304 || program_address != 2)
            $fatal(1, "Transferencia liberada foi perdida ou duplicada");
        @(negedge clk); read = 0; write = 0;

        // Reset durante carga preserva modo, tamanho e RAM: continua pausado.
        @(negedge clk); frame_boundary = 1;
        @(posedge clk); #1;
        @(negedge clk); frame_boundary = 0; program_ready = 0; rst_n = 0;
        #1; controls(1, 1, 0, 0);
        read_register(0, 9); read_register(6'h18, 0); read_register(6'h20, 17);
        read_register(6'h10, 0); read_register(6'h24, CAPACITY_STATUS);
        saved_writes = writes;
        address = 6'h1C; write = 1; writedata = 32'hFFFFFFFF; byteenable = 15;
        @(posedge clk); #1;
        if (waitrequest !== 1 || program_write !== 0 || writes != saved_writes)
            $fatal(1, "Reset nao bloqueou aceitacao/escrita RAM");
        @(negedge clk); write = 0; rst_n = 1; program_ready = 1;
        @(posedge clk); #1;
        read_program(32'h11223344, 0);
        // Saida de load_mode SEM bit1 tambem forca restart para invalidar IR.
        write_register(0, 0, 1);
        controls(0, 0, 1, 0);
        read_register(0, 0); read_register(6'h20, 17);
        read_register(6'h24, CAPACITY_STATUS);
        @(negedge clk); rst_n = 0;
        #1; controls(0, 0, 0, 0);
        read_register(6'h20, 17);
        if (memory[0] !== 32'h11223344 || memory[1] !== 32'h01020304)
            $fatal(1, "Reset apagou programa carregado");
        @(negedge clk); rst_n = 1;
        // Nova carga e clear limpam erro; perda de ready proibe novas escritas.
        write_register(6'h1C, 0, 15);
        read_register(6'h24, CAPACITY_STATUS | 2);
        write_register(0, 8, 1);
        controls(1, 1, 1, 0);
        read_register(6'h24, CAPACITY_STATUS | 1);
        @(negedge clk); program_ready = 0;
        saved_writes = writes;
        write_register(6'h1C, 0, 15);
        if (writes != saved_writes) $fatal(1, "Write aceito com program_ready=0");
        read_register(6'h24, CAPACITY_STATUS | 2);

        // CONTROL continua byte-enable-aware com o novo bit3 significativo.
        @(negedge clk); program_ready = 1;
        write_register(0, 4, 1);
        expected_load = 0; expected_stored_pause = 0;
        for (mask = 0; mask < 16; mask++) begin
            for (control_word = 0; control_word < 16; control_word++) begin
                old_load = expected_load;
                if (mask[0]) begin
                    expected_load = control_word[3];
                    expected_stored_pause = control_word[0];
                end
                write_register(0, 32'hFFFFFFF0 | control_word, mask[3:0]);
                controls(expected_load, expected_stored_pause || expected_load,
                         mask[0] && (control_word[1] || old_load != expected_load),
                         mask[0] && control_word[2]);
                read_register(0, {28'd0, expected_load, 2'd0,
                                  expected_stored_pause || expected_load});
            end
        end
        $display("PASS: upload MMIO, leitura RAM sincrona/waitrequest, byteenable, limites256, ready/drain, reset persistente e controles");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Timeout upload MMIO");
    end
endmodule
