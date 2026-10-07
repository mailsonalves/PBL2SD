`timescale 1ns/1ps

// Teste da etapa 2: comandos genericos chegam a SAT e alteram a renderizacao.
// Nao depende de VRAM nem da prioridade entre sprites sobrepostos.
module tb_sprite_commands;
    reg clock = 0;
    always #10 clock = ~clock;
    reg rst_n = 0;
    reg [31:0] cmd_data = 0;
    reg cmd_valid = 0;
    reg rast_busy = 0;
    wire cmd_ready;
    wire pal_we, tm_we, sat_we, rast_start, rast_clear_screen;
    wire [7:0] pal_addr, tm_tile_id, rast_y0, rast_y1, rast_y2, rast_color;
    wire [23:0] pal_data;
    wire [5:0] tm_x;
    wire [4:0] tm_y, sat_addr;
    wire [8:0] scroll_x, rast_x0, rast_x1, rast_x2;
    wire [7:0] scroll_y;
    wire [31:0] sat_data, sat_write_mask;
    reg [8:0] pixel_x = 0;
    reg [7:0] pixel_y = 0;
    wire [13:0] sp_vram_addr;
    wire sprite_busy;
    wire sprite_meta_we, sprite_palette_enable;
    wire [4:0] sprite_meta_addr;
    wire [1:0] sprite_priority;
    wire [3:0] sprite_palette_bank;

    cmd_decoder decoder (
        .clk(clock), .rst_n(rst_n), .cmd_data(cmd_data),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .pal_we(pal_we), .pal_addr(pal_addr), .pal_data(pal_data),
        .tm_we(tm_we), .tm_x(tm_x), .tm_y(tm_y), .tm_tile_id(tm_tile_id),
        .scroll_x(scroll_x), .scroll_y(scroll_y),
        .sat_we(sat_we), .sat_addr(sat_addr), .sat_data(sat_data),
        .sat_write_mask(sat_write_mask),
        .rast_x0(rast_x0), .rast_y0(rast_y0),
        .rast_x1(rast_x1), .rast_y1(rast_y1),
        .rast_x2(rast_x2), .rast_y2(rast_y2), .rast_color(rast_color),
        .rast_clear_screen(rast_clear_screen), .rast_start(rast_start),
        .rast_busy(rast_busy), .sprite_busy(sprite_busy),
        .buffer_busy(1'b0), .buffer_double_buffered(1'b0),
        .sprite_meta_we(sprite_meta_we), .sprite_meta_addr(sprite_meta_addr),
        .sprite_priority(sprite_priority),
        .sprite_palette_enable(sprite_palette_enable),
        .sprite_palette_bank(sprite_palette_bank)
    );

    sprite_engine sprites (
        .clk(clock), .rst_n(rst_n), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .sat_we(sat_we), .sat_addr(sat_addr), .sat_data(sat_data),
        .sat_write_mask(sat_write_mask), .sp_vram_addr(sp_vram_addr),
        .meta_we(sprite_meta_we), .meta_addr(sprite_meta_addr),
        .meta_priority(sprite_priority),
        .meta_palette_enable(sprite_palette_enable),
        .meta_palette_bank(sprite_palette_bank), .busy(sprite_busy), .sp_pixel()
    );

    reg [31:0] expected_sat [0:31];
    integer accepted_writes = 0;
    integer expected_writes = 0;
    integer pixel_checks = 0;

    // Conta na borda em que o motor recebe a escrita, antes das atualizacoes NBA.
    always @(posedge clock)
        if (rst_n && sat_we) accepted_writes = accepted_writes + 1;

    function automatic [31:0] pos_command(input integer id, x, y);
        pos_command = {4'hA, id[4:0], x[8:0], y[7:0], 6'd0};
    endfunction

    function automatic [31:0] attr_command(
        input integer id, tile, enabled, flip_h, flip_v
    );
        attr_command = {4'hB, id[4:0], tile[7:0],
                        enabled[0], flip_h[0], flip_v[0], 12'd0};
    endfunction

    // Modelo por aritmetica: quadrante 0/1/2/3 e linha/coluna do tile 8x8.
    function automatic integer sprite_address(
        input integer tile, dx, dy, flip_h, flip_v
    );
        integer sx, sy, selected_tile;
        begin
            sx = flip_h ? 15-dx : dx;
            sy = flip_v ? 15-dy : dy;
            selected_tile = (tile + (sy/8)*2 + sx/8) % 256;
            sprite_address = selected_tile*64 + (sy%8)*8 + sx%8;
        end
    endfunction

    task automatic check_sat;
        integer index;
        begin
            for (index = 0; index < 32; index = index + 1)
                if (sprites.sat_ram[index] !== expected_sat[index])
                    $fatal(1, "SAT[%0d]: esperado=%08h obtido=%08h",
                           index, expected_sat[index], sprites.sat_ram[index]);
        end
    endtask

    // Conferencia do pulso e mascara, seguida de atualizacao do modelo funcional.
    task automatic check_decode(input [31:0] word, input bit accepted);
        integer id;
        reg [31:0] expected_data, expected_mask;
        begin
            if (sat_we !== accepted)
                $fatal(1, "sat_we incorreto para comando %08h: %b", word, sat_we);
            if (pal_we || tm_we || rast_start || rast_clear_screen)
                $fatal(1, "Comando de sprite alterou outra unidade funcional");
            if (accepted) begin
                id = word[27:23];
                case (word[31:28])
                    4'hA: begin
                        expected_mask = 32'h01FFFF00;
                        expected_data = {7'd0, word[22:14], word[13:6], 8'd0};
                        expected_sat[id][24:16] = word[22:14];
                        expected_sat[id][15:8] = word[13:6];
                    end
                    4'hB: begin
                        expected_mask = 32'hE00000FF;
                        expected_data = {word[14:12], 21'd0, word[22:15]};
                        expected_sat[id][31:29] = word[14:12];
                        expected_sat[id][7:0] = word[22:15];
                    end
                    4'h6: begin
                        id = 0;
                        expected_mask = 32'hFFFFFFFF;
                        expected_data = {1'b1, 1'b0, 1'b0, 4'd0,
                                         9'd152, word[7:0], 8'd1};
                        expected_sat[0] = expected_data;
                    end
                    default: $fatal(1, "Comando nao suportado pelo teste");
                endcase
                if (sat_addr !== id[4:0] || sat_write_mask !== expected_mask ||
                    (sat_data & expected_mask) !== (expected_data & expected_mask))
                    $fatal(1, "Decodificacao incorreta de %08h: ID=%0d mascara=%08h dados=%08h",
                           word, sat_addr, sat_write_mask, sat_data);
                expected_writes = expected_writes + 1;
            end
        end
    endtask

    task automatic issue(
        input [31:0] word, input bit valid, busy, accepted
    );
        begin
            wait (cmd_ready);
            @(negedge clock);
            cmd_data = word;
            cmd_valid = valid;
            rast_busy = busy;
            #1;
            if (cmd_ready !== !busy)
                $fatal(1, "cmd_ready nao respeita rast_busy antes da aceitacao");
            @(posedge clock);
            #1;
            check_decode(word, accepted);
            @(negedge clock);
            cmd_valid = 0;
            rast_busy = 0;
            @(posedge clock);
            #1;
            check_sat;
            if (sat_we)
                $fatal(1, "Pulso de escrita repetido sem cmd_valid");
            wait (!sprite_busy && cmd_ready);
        end
    endtask

    // O segundo comando e apresentado imediatamente, mas permanece estavel
    // ate ready. A etapa 3 precisa carregar o cache quando a imagem muda.
    task automatic issue_pair(input [31:0] first, second);
        begin
            wait (cmd_ready);
            @(negedge clock);
            cmd_data = first;
            cmd_valid = 1;
            @(posedge clock); #1;
            check_decode(first, 1);
            @(negedge clock);
            cmd_data = second;
            while (!cmd_ready) begin
                @(posedge clock); #1;
                check_sat;
                if (sat_we) $fatal(1, "Comando repetido enquanto ready estava baixo");
                @(negedge clock);
            end
            @(posedge clock); #1;
            check_decode(second, 1);
            @(negedge clock);
            cmd_valid = 0;
            @(posedge clock); #1;
            check_sat;
            if (sat_we) $fatal(1, "Comandos consecutivos produziram escrita extra");
            wait (!sprite_busy && cmd_ready);
        end
    endtask

    task automatic set_pos(input integer id, x, y);
        issue(pos_command(id, x, y), 1, 0, 1);
    endtask

    task automatic set_attr(input integer id, tile, enabled, flip_h, flip_v);
        issue(attr_command(id, tile, enabled, flip_h, flip_v), 1, 0, 1);
    endtask

    task automatic sample(input integer x, y, address);
        begin
            @(negedge clock);
            pixel_x = x[8:0];
            pixel_y = y[7:0];
            #1;
            if (sp_vram_addr !== address[13:0])
                $fatal(1, "Pixel (%0d,%0d): endereco esperado=%0d obtido=%0d",
                       x, y, address, sp_vram_addr);
            pixel_checks = pixel_checks + 1;
        end
    endtask

    task automatic check_complete_sprite(
        input integer x, y, tile, flip_h, flip_v
    );
        integer dx, dy;
        begin
            for (dy = 0; dy < 16; dy = dy + 1)
                for (dx = 0; dx < 16; dx = dx + 1)
                    sample(x+dx, y+dy, sprite_address(tile, dx, dy, flip_h, flip_v));
            // Ultimo pixel pertence ao sprite; a coordenada seguinte nao pertence.
            sample(x-1, y+7, 0);
            sample(x+16, y+7, 0);
            sample(x+7, y-1, 0);
            sample(x+7, y+16, 0);
        end
    endtask

    task automatic reset_system;
        integer index;
        begin
            @(negedge clock);
            rst_n = 0;
            cmd_valid = 0;
            rast_busy = 0;
            for (index = 0; index < 32; index = index + 1)
                expected_sat[index] = 0;
            expected_sat[0] = {1'b1, 1'b0, 1'b0, 4'd0, 9'd150, 8'd100, 8'd1};
            repeat (2) @(negedge clock);
            rst_n = 1;
            @(posedge clock);
            #1;
            check_sat;
            if (sat_we) $fatal(1, "Reset manteve escrita pendente");
            wait (!sprite_busy && cmd_ready);
        end
    endtask

    integer id, x, y, dx, dy, flip, tile;
    reg [31:0] first_word, second_word;
    initial begin
        reset_system;
        sample(150, 100, sprite_address(1, 0, 0, 0, 0));
        sample(166, 100, 0);

        // Retira o sprite inicial antes de construir uma grade sem sobreposicao.
        set_attr(0, 1, 0, 0, 0);
        for (id = 0; id < 32; id = id + 1) begin
            x = 20 + (id%8)*24;
            y = 10 + (id/8)*24;
            tile = 8 + id*4;
            // As duas ordens verificam que cada comando preserva os outros campos.
            if (id%2 == 0) begin
                set_pos(id, x, y);
                set_attr(id, tile, 1, 0, 0);
            end else begin
                set_attr(id, tile, 1, 0, 0);
                set_pos(id, x, y);
            end
        end
        for (id = 0; id < 32; id = id + 1)
            check_complete_sprite(20+(id%8)*24, 10+(id/8)*24, 8+id*4, 0, 0);

        // Uma escrita parcial deve preservar os outros 31 sprites tambem.
        set_pos(17, 301, 151);
        set_attr(17, 243, 1, 1, 0);
        check_complete_sprite(301, 151, 243, 1, 0);

        for (id = 0; id < 32; id = id + 1)
            set_attr(id, 8+id*4, 0, 0, 0);
        sample(20, 10, 0);
        sample(301, 151, 0);

        // Posicao desalinhada e quatro combinacoes de espelhamento.
        // Tile 255 tambem verifica o retorno modulo 256 dos tiles seguintes.
        set_pos(31, 17, 33);
        for (flip = 0; flip < 4; flip = flip + 1) begin
            set_attr(31, 255, 1, flip%2, flip/2);
            check_complete_sprite(17, 33, 255, flip%2, flip/2);
        end
        set_attr(31, 85, 1, 0, 0);
        check_complete_sprite(17, 33, 85, 0, 0);
        set_attr(31, 85, 0, 1, 1);
        sample(17, 33, 0);
        sample(32, 48, 0);
        set_attr(31, 85, 1, 1, 1);
        sample(17, 33, sprite_address(85, 0, 0, 1, 1));

        // Valid continuo: o segundo comando espera o ready sem ser perdido.
        first_word = pos_command(31, 103, 87);
        second_word = attr_command(31, 41, 1, 0, 1);
        issue_pair(first_word, second_word);
        check_complete_sprite(103, 87, 41, 0, 1);

        // Ordem inversa: os atributos novos sobrevivem a nova posicao.
        first_word = attr_command(31, 92, 1, 1, 0);
        second_word = pos_command(31, 61, 73);
        issue_pair(first_word, second_word);
        check_complete_sprite(61, 73, 92, 1, 0);

        // Comandos nao aceitos devem manter todos os registros intactos.
        issue(pos_command(31, 1, 2), 0, 0, 0);
        issue(attr_command(31, 9, 0, 1, 0), 0, 0, 0);
        issue(pos_command(31, 3, 4), 1, 1, 0);
        issue(attr_command(31, 7, 0, 0, 0), 1, 1, 0);
        sample(61, 73, sprite_address(92, 0, 0, 1, 0));

        // Limites maximos dos campos nao podem causar overflow em X+16/Y+16.
        set_pos(31, 500, 245);
        set_attr(31, 60, 1, 0, 0);
        for (dy = 0; dy < 11; dy = dy + 1)
            for (dx = 0; dx < 12; dx = dx + 1)
                sample(500+dx, 245+dy, sprite_address(60, dx, dy, 0, 0));
        sample(499, 250, 0);
        sample(505, 244, 0);
        sample(0, 250, 0);
        sample(505, 0, 0);
        set_pos(31, 511, 255);
        sample(511, 255, sprite_address(60, 0, 0, 0, 0));
        sample(0, 255, 0);
        sample(511, 0, 0);

        // O opcode legado continua redefinindo completamente o sprite 0.
        set_attr(31, 60, 0, 0, 0);
        set_pos(0, 400, 200);
        set_attr(0, 220, 0, 1, 1);
        issue(32'h6000007B, 1, 0, 1);
        check_complete_sprite(152, 123, 1, 0, 0);

        if (accepted_writes != expected_writes)
            $fatal(1, "Escritas perdidas ou duplicadas: esperado=%0d obtido=%0d",
                   expected_writes, accepted_writes);
        reset_system;
        sample(150, 100, sprite_address(1, 0, 0, 0, 0));
        sample(152, 123, 0);
        sample(511, 255, 0);
        $display("PASS: 32 sprites, escritas parciais, enable/imagem, 4 espelhamentos, bordas, rejeicao e legado; %0d pixels e %0d escritas",
                 pixel_checks, accepted_writes);
        $finish;
    end

    initial begin
        #3000000;
        $fatal(1, "Timeout no teste dos comandos genericos de sprite");
    end
endmodule
