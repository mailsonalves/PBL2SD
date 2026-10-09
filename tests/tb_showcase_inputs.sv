`timescale 1ns/1ps
module tb_showcase_inputs;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [9:0] switches = 0;
    reg [2:0] keys_n = 3'b111;
    wire [9:0] sw_state;
    wire [2:0] key_state;
    showcase_inputs #(.DEBOUNCE_CYCLES(4)) dut (.*);
    task tick;
        begin @(posedge clk); #1; end
    endtask
    initial begin
        tick();
        if (sw_state !== 0 || key_state !== 0) $fatal(1, "Reset das entradas");
        @(negedge clk); rst_n = 1; switches = 10'h155;
        tick(); if (sw_state !== 0) $fatal(1, "SW pulou primeiro sincronizador");
        tick(); if (sw_state !== 10'h155) $fatal(1, "SW nao sincronizada em duas etapas");
        // Um pulso de uma borda nao pode virar clique filtrado.
        @(negedge clk); keys_n = 3'b110;
        tick(); @(negedge clk); keys_n = 3'b111;
        repeat (7) tick();
        if (key_state !== 0) $fatal(1, "Bounce curto aceito");
        @(negedge clk); keys_n = 3'b100;
        repeat (5) begin tick(); if (key_state !== 0) $fatal(1, "Botoes liberados cedo"); end
        tick(); if (key_state !== 3'b011) $fatal(1, "Filtro nao aceitou KEY1/KEY2");
        // Bounce de soltura nao desfaz a pressao; soltura estavel desfaz.
        @(negedge clk); keys_n = 3'b111;
        tick(); @(negedge clk); keys_n = 3'b100;
        repeat (7) tick();
        if (key_state !== 3'b011) $fatal(1, "Bounce de soltura aceito");
        @(negedge clk); keys_n = 3'b111;
        repeat (6) tick();
        if (key_state !== 0) $fatal(1, "Soltura nao filtrada");
        @(negedge clk); keys_n = 0;
        repeat (6) tick();
        if (key_state !== 3'b111) $fatal(1, "Todos os botoes");
        @(negedge clk); rst_n = 0;
        #1;
        if (sw_state !== 0 || key_state !== 0) $fatal(1, "Reset assincrono");
        $display("PASS: entradas da galeria; sincronizacao SW, polaridade KEY, debounce de pressao/soltura e reset");
        $finish;
    end
    initial begin #10000; $fatal(1, "Timeout nas entradas"); end
endmodule
