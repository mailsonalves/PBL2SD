`timescale 1ns/1ps
// A CLUT mantem uma etapa de leitura e define NEW_DATA em colisao.
// Modela a falta de garantia mixed-port M10K envenenando somente a saida RAM;
// a referencia publica usa os assets e as transacoes, sem ler a memoria RTL.
module tb_palette_collision;
    reg clk = 0;
    always #5 clk = ~clk;
    reg we = 0;
    reg [7:0] wr_addr = 0, rd_addr = 0;
    reg [23:0] wr_data = 0;
    wire [23:0] rgb_out;
    color_palette dut (.*);

    reg [23:0] reference [0:255];
    reg [23:0] previous_rgb;
    bit have_previous = 0;
    integer reads = 0, collisions = 0;
    // No simulador de dois estados, um valor errado conhecido tambem deve ser
    // mascarado. Icarus verifica adicionalmente a propagacao de X real.
`ifdef VERILATOR
    localparam [23:0] RAM_POISON = 24'hA5C33A;
`else
    localparam [23:0] RAM_POISON = 24'hxxxxxx;
`endif

    task automatic cycle(input bit write_enable,
        input [7:0] write_address, read_address, input [23:0] write_data);
        reg [23:0] expected;
        begin
            @(negedge clk);
            release dut.ram_rgb;
            we = write_enable; wr_addr = write_address;
            rd_addr = read_address; wr_data = write_data;
            expected = write_enable && write_address == read_address ?
                write_data : reference[read_address];
            #1;
            if (have_previous && rgb_out !== previous_rgb)
                $fatal(1, "CLUT changed before clock: got=%h previous=%h", rgb_out, previous_rgb);
            @(posedge clk); #1;
            if (write_enable) reference[write_address] = write_data;
            if (write_enable && write_address == read_address) begin
                force dut.ram_rgb = RAM_POISON;
                #1;
`ifndef VERILATOR
                if (!$isunknown(dut.ram_rgb)) $fatal(1, "Collision model did not inject X");
`endif
                collisions = collisions + 1;
            end
            if (rgb_out !== expected)
                $fatal(1, "CLUT we=%b write=%0d read=%0d: got=%h expected=%h",
                    write_enable, write_address, read_address, rgb_out, expected);
            previous_rgb = expected; have_previous = 1;
            reads = reads + 1;
        end
    endtask

    integer address, index;
    reg [23:0] new_color;
    initial begin
        $readmemh("palette.hex", reference);
        cycle(0, 0, 0, 0);
        // Todos os indices: colisao real da interface, seguida de leitura
        // independente para conferir armazenamento e liberacao do bypass.
        for (address = 0; address < 256; address = address + 1) begin
            new_color = {8'(address), 8'(address ^ 8'hFF), 8'(address ^ 8'h55)};
            cycle(1, 8'(address), 8'(address), new_color);
            cycle(0, 0, 8'(address), 0);
            cycle(1, 8'(address), 8'((address + 127) % 256), new_color ^ 24'h003311);
            cycle(0, 0, 8'(address), 0);
        end
        // Escritas consecutivas na mesma palavra atualizam o bypass em cada
        // borda; read-only posterior deve consultar a RAM, sem dado obsoleto.
        for (index = 0; index < 16; index = index + 1)
            cycle(1, 17, 17, 24'h102030 + 24'(index));
        cycle(0, 0, 17, 0);
        // Mudanca de endereco e de we em todo clock exercita hit/data alinhados.
        for (index = 0; index < 64; index = index + 1)
            cycle(index[0], 8'(index), 8'(index), 24'hF01000 + 24'(index));
        release dut.ram_rgb;
        $display("PASS tb_palette_collision: %0d synchronous reads, %0d poisoned collisions, NEW_DATA, independent writes and consecutive/bypass release", reads, collisions);
        $finish;
    end
    initial begin #30000; $fatal(1, "Timeout tb_palette_collision"); end
endmodule
