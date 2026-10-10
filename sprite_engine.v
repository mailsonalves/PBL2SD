<<<<<<< HEAD
// SAT: enable[31], flip_x[30], flip_y[29], x[24:16], y[15:8], tile[7:0].
// Cada sprite tem um cache 16x16 de 8 bits. Uma unica ROM de padroes abastece
// esses caches; nao sao necessarias 32 replicas da VRAM de 16 KiB.
module sprite_engine #(
    parameter PATTERN_FILE = "tiles.hex"
) (
=======
module sprite_engine (
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
    input  wire        clk,
    input  wire        rst_n,
    input  wire [8:0]  pixel_x,
    input  wire [7:0]  pixel_y,
<<<<<<< HEAD
    input  wire        sat_we,
    input  wire [4:0]  sat_addr,
    input  wire [31:0] sat_data,
    input  wire [31:0] sat_write_mask,
    input  wire        meta_we,
    input  wire [4:0]  meta_addr,
    input  wire [1:0]  meta_priority,
    input  wire        meta_palette_enable,
    input  wire [3:0]  meta_palette_bank,
    // Endereco geometrico legado, mantido para depuracao. A cor usa sp_pixel.
    output reg  [13:0] sp_vram_addr,
    output reg  [7:0]  sp_pixel,
    output reg         busy
);

    reg [31:0] sat_ram [0:31];
    reg [1:0] priority_ram [0:31];
    reg [3:0] palette_bank_ram [0:31];
    reg palette_enable_ram [0:31];
    reg [31:0] cache_valid;

    reg [7:0] pattern_rom [0:16383];
    initial $readmemh(PATTERN_FILE, pattern_rom);

    // Leitura sincrona da origem, seguida da escrita no cache selecionado.
    // O ultimo pixel precisa ser escrito antes de liberar busy.
    reg [4:0] load_id;
    reg [7:0] load_base;
    reg [8:0] load_index;
    reg load_return_valid;
    reg [7:0] load_return_index;
    reg [7:0] load_return_pixel;
    wire [7:0] load_tile = load_base + {6'd0, load_index[7], load_index[3]};
    wire [13:0] load_address = {load_tile, load_index[6:4], load_index[2:0]};
    wire load_write = rst_n && busy && load_return_valid;
    wire [31:0] new_attr = (sat_ram[sat_addr] & ~sat_write_mask) |
                           (sat_data & sat_write_mask);

    always @(posedge clk) begin
        if (rst_n && busy && load_index < 9'd256)
            load_return_pixel <= pattern_rom[load_address];
    end

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 32; k = k + 1) begin
                sat_ram[k] <= 32'd0;
                priority_ram[k] <= 2'd0;
                palette_bank_ram[k] <= 4'd0;
                palette_enable_ram[k] <= 1'b0;
            end
            sat_ram[0] <= {1'b1, 1'b0, 1'b0, 4'd0, 9'd150, 8'd100, 8'd1};
            cache_valid <= 32'd0;
            busy <= 1'b1;
            load_id <= 5'd0;
            load_base <= 8'd1;
            load_index <= 9'd0;
            load_return_valid <= 1'b0;
            load_return_index <= 8'd0;
        end else begin
            load_return_valid <= 1'b0;
            if (busy) begin
                if (load_index < 9'd256) begin
                    load_index <= load_index + 9'd1;
                    load_return_valid <= 1'b1;
                    load_return_index <= load_index[7:0];
                end
                if (load_return_valid && load_return_index == 8'd255) begin
                    cache_valid[load_id] <= 1'b1;
                    busy <= 1'b0;
                end
            end else if (sat_we) begin
                sat_ram[sat_addr] <= new_attr;
                if (new_attr[7:0] != sat_ram[sat_addr][7:0])
                    cache_valid[sat_addr] <= 1'b0;
                if (new_attr[31] && (!cache_valid[sat_addr] ||
                                    new_attr[7:0] != sat_ram[sat_addr][7:0])) begin
                    cache_valid[sat_addr] <= 1'b0;
                    load_id <= sat_addr;
                    load_base <= new_attr[7:0];
                    load_index <= 9'd0;
                    busy <= 1'b1;
                end
                // O comando legado completo tambem restaura seus atributos.
                if (&sat_write_mask) begin
                    priority_ram[sat_addr] <= 2'd0;
                    palette_bank_ram[sat_addr] <= 4'd0;
                    palette_enable_ram[sat_addr] <= 1'b0;
                end
            end
            if (meta_we) begin
                priority_ram[meta_addr] <= meta_priority;
                palette_bank_ram[meta_addr] <= meta_palette_bank;
                palette_enable_ram[meta_addr] <= meta_palette_enable;
            end
        end
    end

    wire [13:0] sprite_addrs [0:31];
    wire sprite_hit [0:31];
    wire [7:0] sprite_pixels [0:31];
    reg [31:0] hit_q;
    reg [1:0] priority_q [0:31];
    reg [3:0] palette_bank_q [0:31];
    reg [31:0] palette_enable_q;

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_sprites
            wire [31:0] attr = sat_ram[i];
            wire [8:0] sp_x = attr[24:16];
            wire [7:0] sp_y = attr[15:8];
            wire inside_x = (pixel_x >= sp_x) &&
                            ({1'b0, pixel_x} < {1'b0, sp_x} + 10'd16);
            wire inside_y = (pixel_y >= sp_y) &&
                            ({1'b0, pixel_y} < {1'b0, sp_y} + 9'd16);
            wire [3:0] rel_x = pixel_x[3:0] - sp_x[3:0];
            wire [3:0] rel_y = pixel_y[3:0] - sp_y[3:0];
            wire [3:0] eff_x = attr[30] ? (4'd15 - rel_x) : rel_x;
            wire [3:0] eff_y = attr[29] ? (4'd15 - rel_y) : rel_y;
            wire [7:0] tile = attr[7:0] + {6'd0, eff_y[3], eff_x[3]};
            assign sprite_addrs[i] = {tile, eff_y[2:0], eff_x[2:0]};
            assign sprite_hit[i] = attr[31] && inside_x && inside_y;

            // Sem reset ou limpeza da RAM: cache_valid impede pixels indefinidos
            // e permite que o Quartus infira memoria de bloco para os caches.
            reg [7:0] pixels [0:255];
            reg [7:0] pixel_q;
            always @(posedge clk) begin
                if (load_write && load_id == i)
                    pixels[load_return_index] <= load_return_pixel;
                pixel_q <= pixels[{eff_y, eff_x}];
            end
            assign sprite_pixels[i] = pixel_q;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    hit_q[i] <= 1'b0;
                    priority_q[i] <= 2'd0;
                    palette_bank_q[i] <= 4'd0;
                    palette_enable_q[i] <= 1'b0;
                end else begin
                    hit_q[i] <= sprite_hit[i] && cache_valid[i];
                    priority_q[i] <= priority_ram[i];
                    palette_bank_q[i] <= palette_bank_ram[i];
                    palette_enable_q[i] <= palette_enable_ram[i];
                end
            end
        end
    endgenerate

    integer j;
    reg found;
    reg [1:0] selected_priority;
    reg opaque;
    always @(*) begin
        sp_vram_addr = 14'd0;
        sp_pixel = 8'd0;
        found = 1'b0;
        selected_priority = 2'd0;
        opaque = 1'b0;
        // Mais prioridade vence; no empate, menor ID. A transparencia e testada
        // em cada sprite, antes da escolha, para revelar sprites que estao atras.
        for (j = 31; j >= 0; j = j - 1) begin
            if (sprite_hit[j]) sp_vram_addr = sprite_addrs[j];
            opaque = palette_enable_q[j] ? (sprite_pixels[j][3:0] != 4'd0) :
                                                   (sprite_pixels[j] != 8'd0);
            if (hit_q[j] && opaque && (!found || priority_q[j] >= selected_priority)) begin
                found = 1'b1;
                selected_priority = priority_q[j];
                sp_pixel = palette_enable_q[j] ?
                    {palette_bank_q[j], sprite_pixels[j][3:0]} : sprite_pixels[j];
            end
        end
    end
endmodule
=======
    output reg  [7:0]  sp_pixel
);

    // Posição na tela do Flappy Bird
    localparam [8:0] SPR_X = 9'd70;
    localparam [7:0] SPR_Y = 8'd100;

    wire in_box = (pixel_x >= SPR_X) && (pixel_x < SPR_X + 9'd16) &&
                  (pixel_y >= SPR_Y) && (pixel_y < SPR_Y + 8'd16);

    wire [3:0] dx = pixel_x[8:0] - SPR_X;
    wire [3:0] dy = pixel_y[7:0] - SPR_Y;

    // ROM 16x16 com as cores oficiais do Flappy Bird
    reg [7:0] flappy_rom [0:255];

    initial begin
        // Linha 0
        flappy_rom[0]=8'h00; flappy_rom[1]=8'h00; flappy_rom[2]=8'h00; flappy_rom[3]=8'h00; flappy_rom[4]=8'h00; flappy_rom[5]=8'h00; flappy_rom[6]=8'h10; flappy_rom[7]=8'h10;
        flappy_rom[8]=8'h10; flappy_rom[9]=8'h10; flappy_rom[10]=8'h10; flappy_rom[11]=8'h00; flappy_rom[12]=8'h00; flappy_rom[13]=8'h00; flappy_rom[14]=8'h00; flappy_rom[15]=8'h00;
        // Linha 1
        flappy_rom[16]=8'h00; flappy_rom[17]=8'h00; flappy_rom[18]=8'h00; flappy_rom[19]=8'h00; flappy_rom[20]=8'h10; flappy_rom[21]=8'h10; flappy_rom[22]=8'h12; flappy_rom[23]=8'h12;
        flappy_rom[24]=8'h12; flappy_rom[25]=8'h10; flappy_rom[26]=8'h11; flappy_rom[27]=8'h11; flappy_rom[28]=8'h10; flappy_rom[29]=8'h00; flappy_rom[30]=8'h00; flappy_rom[31]=8'h00;
        // Linha 2
        flappy_rom[32]=8'h00; flappy_rom[33]=8'h00; flappy_rom[34]=8'h00; flappy_rom[35]=8'h10; flappy_rom[36]=8'h12; flappy_rom[37]=8'h12; flappy_rom[38]=8'h12; flappy_rom[39]=8'h12;
        flappy_rom[40]=8'h10; flappy_rom[41]=8'h11; flappy_rom[42]=8'h11; flappy_rom[43]=8'h11; flappy_rom[44]=8'h10; flappy_rom[45]=8'h00; flappy_rom[46]=8'h00; flappy_rom[47]=8'h00;
        // Linha 3
        flappy_rom[48]=8'h00; flappy_rom[49]=8'h00; flappy_rom[50]=8'h10; flappy_rom[51]=8'h12; flappy_rom[52]=8'h12; flappy_rom[53]=8'h12; flappy_rom[54]=8'h12; flappy_rom[55]=8'h10;
        flappy_rom[56]=8'h10; flappy_rom[57]=8'h11; flappy_rom[58]=8'h10; flappy_rom[59]=8'h11; flappy_rom[60]=8'h10; flappy_rom[61]=8'h00; flappy_rom[62]=8'h00; flappy_rom[63]=8'h00;
        // Linha 4
        flappy_rom[64]=8'h00; flappy_rom[65]=8'h10; flappy_rom[66]=8'h12; flappy_rom[67]=8'h12; flappy_rom[68]=8'h12; flappy_rom[69]=8'h12; flappy_rom[70]=8'h12; flappy_rom[71]=8'h10;
        flappy_rom[72]=8'h10; flappy_rom[73]=8'h11; flappy_rom[74]=8'h10; flappy_rom[75]=8'h11; flappy_rom[76]=8'h10; flappy_rom[77]=8'h00; flappy_rom[78]=8'h00; flappy_rom[79]=8'h00;
        // Linha 5
        flappy_rom[80]=8'h00; flappy_rom[81]=8'h10; flappy_rom[82]=8'h11; flappy_rom[83]=8'h11; flappy_rom[84]=8'h12; flappy_rom[85]=8'h12; flappy_rom[86]=8'h12; flappy_rom[87]=8'h12;
        flappy_rom[88]=8'h10; flappy_rom[89]=8'h11; flappy_rom[89]=8'h11; flappy_rom[90]=8'h11; flappy_rom[91]=8'h11; flappy_rom[92]=8'h10; flappy_rom[93]=8'h00; flappy_rom[94]=8'h00; flappy_rom[95]=8'h00;
        // Linha 6
        flappy_rom[96]=8'h10; flappy_rom[97]=8'h11; flappy_rom[98]=8'h11; flappy_rom[99]=8'h11; flappy_rom[100]=8'h10; flappy_rom[101]=8'h12; flappy_rom[102]=8'h12; flappy_rom[103]=8'h12;
        flappy_rom[104]=8'h12; flappy_rom[105]=8'h10; flappy_rom[106]=8'h10; flappy_rom[107]=8'h10; flappy_rom[108]=8'h10; flappy_rom[109]=8'h10; flappy_rom[110]=8'h00; flappy_rom[111]=8'h00;
        // Linha 7
        flappy_rom[112]=8'h10; flappy_rom[113]=8'h11; flappy_rom[114]=8'h11; flappy_rom[115]=8'h11; flappy_rom[116]=8'h10; flappy_rom[117]=8'h12; flappy_rom[118]=8'h12; flappy_rom[119]=8'h12;
        flappy_rom[120]=8'h10; flappy_rom[121]=8'h14; flappy_rom[122]=8'h14; flappy_rom[123]=8'h14; flappy_rom[124]=8'h14; flappy_rom[125]=8'h14; flappy_rom[126]=8'h10; flappy_rom[127]=8'h00;
        // Linha 8
        flappy_rom[128]=8'h10; flappy_rom[129]=8'h11; flappy_rom[130]=8'h11; flappy_rom[131]=8'h11; flappy_rom[132]=8'h10; flappy_rom[133]=8'h12; flappy_rom[134]=8'h12; flappy_rom[135]=8'h10;
        flappy_rom[136]=8'h14; flappy_rom[137]=8'h14; flappy_rom[138]=8'h14; flappy_rom[139]=8'h14; flappy_rom[140]=8'h14; flappy_rom[141]=8'h14; flappy_rom[142]=8'h10; flappy_rom[143]=8'h00;
        // Linha 9
        flappy_rom[144]=8'h00; flappy_rom[145]=8'h10; flappy_rom[146]=8'h11; flappy_rom[147]=8'h11; flappy_rom[148]=8'h12; flappy_rom[149]=8'h12; flappy_rom[150]=8'h12; flappy_rom[151]=8'h10;
        flappy_rom[152]=8'h10; flappy_rom[153]=8'h10; flappy_rom[154]=8'h10; flappy_rom[155]=8'h10; flappy_rom[156]=8'h10; flappy_rom[157]=8'h10; flappy_rom[158]=8'h10; flappy_rom[159]=8'h00;
        // Linha 10
        flappy_rom[160]=8'h00; flappy_rom[161]=8'h00; flappy_rom[162]=8'h10; flappy_rom[163]=8'h10; flappy_rom[164]=8'h12; flappy_rom[165]=8'h12; flappy_rom[166]=8'h12; flappy_rom[167]=8'h12;
        flappy_rom[168]=8'h14; flappy_rom[169]=8'h14; flappy_rom[170]=8'h14; flappy_rom[171]=8'h14; flappy_rom[172]=8'h14; flappy_rom[173]=8'h10; flappy_rom[174]=8'h00; flappy_rom[175]=8'h00;
        // Linha 11
        flappy_rom[176]=8'h00; flappy_rom[177]=8'h00; flappy_rom[178]=8'h00; flappy_rom[179]=8'h10; flappy_rom[180]=8'h12; flappy_rom[181]=8'h12; flappy_rom[182]=8'h12; flappy_rom[183]=8'h12;
        flappy_rom[184]=8'h10; flappy_rom[185]=8'h10; flappy_rom[186]=8'h10; flappy_rom[187]=8'h10; flappy_rom[188]=8'h10; flappy_rom[189]=8'h00; flappy_rom[190]=8'h00; flappy_rom[191]=8'h00;
        // Linha 12
        flappy_rom[192]=8'h00; flappy_rom[193]=8'h00; flappy_rom[194]=8'h00; flappy_rom[195]=8'h00; flappy_rom[196]=8'h10; flappy_rom[197]=8'h12; flappy_rom[198]=8'h12; flappy_rom[199]=8'h13;
        flappy_rom[200]=8'h13; flappy_rom[201]=8'h10; flappy_rom[202]=8'h00; flappy_rom[203]=8'h00; flappy_rom[204]=8'h00; flappy_rom[205]=8'h00; flappy_rom[206]=8'h00; flappy_rom[207]=8'h00;
        // Linha 13
        flappy_rom[208]=8'h00; flappy_rom[209]=8'h00; flappy_rom[210]=8'h00; flappy_rom[211]=8'h00; flappy_rom[212]=8'h00; flappy_rom[213]=8'h10; flappy_rom[214]=8'h13; flappy_rom[215]=8'h13;
        flappy_rom[216]=8'h10; flappy_rom[217]=8'h00; flappy_rom[218]=8'h00; flappy_rom[219]=8'h00; flappy_rom[220]=8'h00; flappy_rom[221]=8'h00; flappy_rom[222]=8'h00; flappy_rom[223]=8'h00;
        // Linha 14
        flappy_rom[224]=8'h00; flappy_rom[225]=8'h00; flappy_rom[226]=8'h00; flappy_rom[227]=8'h00; flappy_rom[228]=8'h00; flappy_rom[229]=8'h00; flappy_rom[230]=8'h10; flappy_rom[231]=8'h10;
        flappy_rom[232]=8'h00; flappy_rom[233]=8'h00; flappy_rom[234]=8'h00; flappy_rom[235]=8'h00; flappy_rom[236]=8'h00; flappy_rom[237]=8'h00; flappy_rom[238]=8'h00; flappy_rom[239]=8'h00;
        // Linha 15
        flappy_rom[240]=8'h00; flappy_rom[241]=8'h00; flappy_rom[242]=8'h00; flappy_rom[243]=8'h00; flappy_rom[244]=8'h00; flappy_rom[245]=8'h00; flappy_rom[246]=8'h00; flappy_rom[247]=8'h00;
        flappy_rom[248]=8'h00; flappy_rom[249]=8'h00; flappy_rom[250]=8'h00; flappy_rom[251]=8'h00; flappy_rom[252]=8'h00; flappy_rom[253]=8'h00; flappy_rom[254]=8'h00; flappy_rom[255]=8'h00;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sp_pixel <= 8'h00;
        else if (in_box)
            sp_pixel <= flappy_rom[{dy, dx}];
        else
            sp_pixel <= 8'h00; // Transparente
    end

endmodule
>>>>>>> 1ee5570 (busca ativa com erros de exibição)
