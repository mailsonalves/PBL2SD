`timescale 1ns/1ps

// Contrato do decodificador: campos/mascaras, validacao sem efeitos colaterais,
// pulsos de um ciclo e espera por unidades ocupadas e comandos pendentes.
module tb_cmd_decoder;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] cmd_data = 0;
    reg cmd_valid = 0;
    wire cmd_ready;
    reg rast_busy = 0, sprite_busy = 0, buffer_busy = 0;
    reg buffer_double_buffered = 0;

    typedef struct packed {
        logic pal_we;
        logic [7:0] pal_addr;
        logic [23:0] pal_data;
        logic tm_we;
        logic [5:0] tm_x;
        logic [4:0] tm_y;
        logic [7:0] tm_tile_id;
        logic [8:0] scroll_x;
        logic [7:0] scroll_y;
        logic sat_we;
        logic [4:0] sat_addr;
        logic [31:0] sat_data;
        logic [31:0] sat_write_mask;
        logic [8:0] rast_x0, rast_x1, rast_x2;
        logic [7:0] rast_y0, rast_y1, rast_y2;
        logic [7:0] rast_color;
        logic rast_clear_screen, rast_start;
        logic sprite_meta_we;
        logic [4:0] sprite_meta_addr;
        logic [1:0] sprite_priority;
        logic sprite_palette_enable;
        logic [3:0] sprite_palette_bank;
        logic buffer_config_valid, buffer_double_enable, buffer_swap_request;
        logic cmd_error;
    } state_t;
    wire state_t actual;
    state_t expected = '0;

    cmd_decoder dut (
        .clk(clk), .rst_n(rst_n), .cmd_data(cmd_data), .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready), .pal_we(actual.pal_we), .pal_addr(actual.pal_addr),
        .pal_data(actual.pal_data), .tm_we(actual.tm_we), .tm_x(actual.tm_x),
        .tm_y(actual.tm_y), .tm_tile_id(actual.tm_tile_id),
        .scroll_x(actual.scroll_x), .scroll_y(actual.scroll_y),
        .sat_we(actual.sat_we), .sat_addr(actual.sat_addr),
        .sat_data(actual.sat_data), .sat_write_mask(actual.sat_write_mask),
        .rast_x0(actual.rast_x0), .rast_x1(actual.rast_x1), .rast_x2(actual.rast_x2),
        .rast_y0(actual.rast_y0), .rast_y1(actual.rast_y1), .rast_y2(actual.rast_y2),
        .rast_color(actual.rast_color), .rast_clear_screen(actual.rast_clear_screen),
        .rast_start(actual.rast_start), .rast_busy(rast_busy),
        .sprite_busy(sprite_busy), .buffer_busy(buffer_busy),
        .buffer_double_buffered(buffer_double_buffered),
        .sprite_meta_we(actual.sprite_meta_we), .sprite_meta_addr(actual.sprite_meta_addr),
        .sprite_priority(actual.sprite_priority),
        .sprite_palette_enable(actual.sprite_palette_enable),
        .sprite_palette_bank(actual.sprite_palette_bank),
        .buffer_config_valid(actual.buffer_config_valid),
        .buffer_double_enable(actual.buffer_double_enable),
        .buffer_swap_request(actual.buffer_swap_request), .cmd_error(actual.cmd_error)
    );

    integer cycles = 0, commands = 0, errors = 0, stalls = 0;

    function automatic bit ready_for(input state_t state, input logic [2:0] busy);
        ready_for = !(busy != 0 || state.rast_start || state.sat_we ||
                      state.sprite_meta_we || state.buffer_config_valid || state.buffer_swap_request);
    endfunction

    // O modelo mantem os dados entre comandos; apenas strobes voltam a zero.
    task automatic update_expected(input [31:0] word, input bit accepted, error);
        integer red, green, blue;
        begin
            expected.pal_we = 0; expected.tm_we = 0; expected.sat_we = 0;
            expected.rast_start = 0; expected.rast_clear_screen = 0;
            expected.sprite_meta_we = 0; expected.buffer_config_valid = 0;
            expected.buffer_swap_request = 0; expected.cmd_error = error;
            if (accepted && !error) begin
                commands++;
                case (word[31:28])
                    0: begin expected.rast_start = 1; expected.rast_clear_screen = 1; end
                    1: begin
                        expected.pal_we = 1; expected.pal_addr = word[23:16];
                        red = int'(word[15:11])*8;
                        green = int'(word[10:5])*4;
                        blue = int'(word[4:0])*8;
                        expected.pal_data = {red[7:0], green[7:0], blue[7:0]};
                    end
                    3: begin
                        expected.tm_we = 1; expected.tm_x = word[21:16];
                        expected.tm_y = word[12:8]; expected.tm_tile_id = word[7:0];
                    end
                    5: begin expected.scroll_x = word[16:8]; expected.scroll_y = word[7:0]; end
                    6: begin
                        expected.sat_we = 1; expected.sat_addr = 0;
                        expected.sat_data = 32'h80980001 | (32'(word[7:0]) << 8);
                        expected.sat_write_mask = 32'hFFFFFFFF;
                    end
                    7: begin expected.rast_x0 = word[16:8]; expected.rast_y0 = word[7:0]; end
                    8: begin expected.rast_x1 = word[16:8]; expected.rast_y1 = word[7:0]; end
                    9: begin
                        expected.rast_x2 = word[16:8]; expected.rast_y2 = word[7:0];
                        expected.rast_color = word[27:20]; expected.rast_start = 1;
                    end
                    10: begin
                        expected.sat_we = 1; expected.sat_addr = word[27:23];
                        expected.sat_data = (32'(word[22:14]) << 16) | (32'(word[13:6]) << 8);
                        expected.sat_write_mask = 32'h01FFFF00;
                    end
                    11: begin
                        expected.sat_we = 1; expected.sat_addr = word[27:23];
                        expected.sat_data = (32'(word[14:12]) << 29) | 32'(word[22:15]);
                        expected.sat_write_mask = 32'hE00000FF;
                    end
                    12: begin
                        expected.sprite_meta_we = 1; expected.sprite_meta_addr = word[27:23];
                        expected.sprite_priority = word[22:21];
                        expected.sprite_palette_enable = word[20];
                        expected.sprite_palette_bank = word[19:16];
                    end
                    13: begin
                        if (word[27:24] == 0) begin
                            expected.buffer_config_valid = 1;
                            expected.buffer_double_enable = word[0];
                        end else expected.buffer_swap_request = 1;
                    end
                    default: $fatal(1, "Modelo recebeu opcode valido sem definicao");
                endcase
            end
        end
    endtask

    task automatic step(
        input [31:0] word, input bit valid, input [2:0] busy,
        input bit accepted, error
    );
        bit ready_before;
        begin
            @(negedge clk);
            cmd_data = word; cmd_valid = valid;
            rast_busy = busy[0]; sprite_busy = busy[1]; buffer_busy = busy[2];
            ready_before = ready_for(expected, busy);
            #1;
            if (cmd_ready !== ready_before || accepted != (valid && ready_before))
                $fatal(1, "Aceitacao/readiness incorreta antes de %08h, ready=%0b esperado=%0b",
                       word, cmd_ready, ready_before);
            if (error && !accepted) $fatal(1, "Teste tentou erro em comando nao aceito");
            if (valid && !ready_before) stalls++;
            @(posedge clk); #1;
            update_expected(word, accepted, error);
            if (actual !== expected)
                $fatal(1, "Decodificacao/efeito colateral no ciclo %0d comando %08h: esperado=%h obtido=%h",
                       cycles, word, expected, actual);
            if (cmd_ready !== ready_for(expected, busy))
                $fatal(1, "cmd_ready nao bloqueou/desbloqueou o pulso do comando %08h", word);
            if (error) errors++;
            cycles++;
        end
    endtask

    task automatic idle;
        step(0, 0, 0, 0, 0);
    endtask

    task automatic command(input [31:0] word);
        begin step(word, 1, 0, 1, 0); idle; end
    endtask

    task automatic reject(input [31:0] word);
        begin step(word, 1, 0, 1, 1); idle; end
    endtask

    task automatic reset_decoder;
        begin
            @(negedge clk);
            rst_n = 0; cmd_valid = 0; rast_busy = 0; sprite_busy = 0; buffer_busy = 0;
            expected = '0;
            #1;
            if (actual !== expected || cmd_ready !== 1)
                $fatal(1, "Reset nao limpou o estado e todos os pulsos");
            @(negedge clk); rst_n = 1;
            idle;
        end
    endtask

    integer id, bit_index, priority_value, bank, enabled, index, busy_mask;
    reg [31:0] word;
    initial begin
        reset_decoder;
        command(32'h0F000000);
        command(32'h1000FFFF); command(32'h10FF0000);
        command(32'h10A5F81F); command(32'h103D07E0);
        command(32'h30000000); command(32'h30271DFF);
        command(32'h5001FFFF); command(32'h50000000);
        command(32'h60000000); command(32'h600000FF);
        command(32'h7001FFFF); command(32'h80000000);
        command(32'h9FF1FFFF); command(32'h90000000);

        // Todos os IDs, coordenadas extremas, mascaras e oito combinacoes de atributos.
        for (id = 0; id < 32; id++) begin
            command({4'hA, id[4:0], 9'd511, 8'd255, 6'd0});
            command({4'hA, id[4:0], 9'd0, 8'd0, 6'd0});
            for (index = 0; index < 8; index++)
                command({4'hB, id[4:0], 8'd255, index[2:0], 12'd0});
            for (priority_value = 0; priority_value < 4; priority_value++)
                for (enabled = 0; enabled < 2; enabled++)
                    for (bank = 0; bank < 16; bank++)
                        command({4'hC, id[4:0], priority_value[1:0], enabled[0], bank[3:0], 16'd0});
        end
        command(32'hD0000000); command(32'hD0000001);
        // O estado atual vem do buffer, e nao do ultimo pedido de configuracao.
        reject(32'hD1000000);
        @(negedge clk); buffer_double_buffered = 1;
        command(32'hD1000000);

        // Campos reservados devem rejeitar o comando inteiro, sem alterar dados.
        reject(32'h00000000); reject(32'h0F000001); reject(32'h01000000);
        for (bit_index = 24; bit_index < 28; bit_index++) reject(32'h1000A55A | (32'd1 << bit_index));
        for (bit_index = 22; bit_index < 28; bit_index++) reject(32'h30271D55 | (32'd1 << bit_index));
        for (bit_index = 13; bit_index < 16; bit_index++) reject(32'h30271D55 | (32'd1 << bit_index));
        reject(32'h30280055); reject(32'h303F1D55);
        reject(32'h30001E55); reject(32'h30271F55);
        for (bit_index = 17; bit_index < 28; bit_index++) begin
            reject(32'h5001FFFF | (32'd1 << bit_index));
            reject(32'h7001FFFF | (32'd1 << bit_index));
            reject(32'h8001FFFF | (32'd1 << bit_index));
        end
        for (bit_index = 8; bit_index < 28; bit_index++) reject(32'h600000FF | (32'd1 << bit_index));
        for (bit_index = 17; bit_index < 20; bit_index++) reject(32'h9FF1FFFF | (32'd1 << bit_index));
        for (bit_index = 0; bit_index < 6; bit_index++) reject(32'hAFFffFC0 | (32'd1 << bit_index));
        for (bit_index = 0; bit_index < 12; bit_index++) reject(32'hBFFFF000 | (32'd1 << bit_index));
        for (bit_index = 0; bit_index < 16; bit_index++) reject(32'hCFFF0000 | (32'd1 << bit_index));
        for (bit_index = 1; bit_index < 24; bit_index++) reject(32'hD0000001 | (32'd1 << bit_index));
        for (bit_index = 0; bit_index < 24; bit_index++) reject(32'hD1000000 | (32'd1 << bit_index));
        for (index = 2; index < 16; index++) reject(32'hD0000000 | (32'(index) << 24));
        reject(32'h20000000); reject(32'h40000000);
        reject(32'hE0000000); reject(32'hF0000000);
        @(negedge clk); buffer_double_buffered = 0;
        reject(32'hD1000000);

        // cmd_valid=0 nunca produz erro ou atualizacao, nem para opcode desconhecido.
        step(32'hFFFFFFFF, 0, 0, 0, 0);
        step(32'h5001FFFF, 0, 0, 0, 0);

        // Cada busy e todas as combinacoes: palavra valida permanece pendente.
        for (busy_mask = 1; busy_mask < 8; busy_mask++) begin
            step(32'h5001002A, 1, busy_mask[2:0], 0, 0);
            step(32'h5001002A, 1, busy_mask[2:0], 0, 0);
            step(32'h5001002A, 1, 0, 1, 0);
            idle;
        end
        // Invalida aguardando busy: erro apenas quando efetivamente aceita.
        step(32'hF0000000, 1, 3'b111, 0, 0);
        step(32'hF0000000, 1, 0, 1, 1); idle;

        // Os pulsos anteriores bloqueiam a instrucao seguinte por um ciclo.
        for (index = 0; index < 6; index++) begin
            case (index)
                0: word = 32'h0F000000;
                1: word = 32'hA0000000;
                2: word = 32'hC0000000;
                3: word = 32'hD0000001;
                4: word = 32'hD1000000;
                default: word = 32'h90000000;
            endcase
            @(negedge clk); buffer_double_buffered = 1;
            step(word, 1, 0, 1, 0);
            step(32'h5000017B, 1, 0, 0, 0);
            step(32'h5000017B, 1, 0, 1, 0);
            idle;
        end

        // Paleta e tilemap aceitam comandos adjacentes sem perder os pulsos.
        step(32'h10011234, 1, 0, 1, 0);
        step(32'h1002ABCD, 1, 0, 1, 0);
        step(32'h30000045, 1, 0, 1, 0);
        step(32'h30271D67, 1, 0, 1, 0);
        idle;
        // Reset cancela pulsos pendentes e limpa operandos/estilos anteriores.
        step(32'hCFFF0000, 1, 0, 1, 0);
        reset_decoder;
        command(32'h50001234);
        $display("PASS: decodificador, todos os opcodes/IDs/estilos, reservas, mascaras, modo de buffers e backpressure; %0d comandos, %0d erros rejeitados, %0d esperas, %0d ciclos",
                 commands, errors, stalls, cycles);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Timeout do teste de comandos");
    end
endmodule
