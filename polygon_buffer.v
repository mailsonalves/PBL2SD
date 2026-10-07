// Camada de poligonos 320x240. Dois bancos permitem desenhar fora da tela
// e apresentar o quadro pronto apenas no intervalo vertical do VGA.
// No top-level os dois clocks usam CLOCK_50; os acessos RAM continuam separados.
module polygon_buffer (
    input  wire        clk_wr,
    input  wire        rst_n,
    input  wire        we,
    input  wire [16:0] addr_wr,
    input  wire [7:0]  data_in,

    input  wire        clk_rd,
    input  wire [16:0] addr_rd,
    output reg  [7:0]  data_out,

    input  wire        config_valid,
    input  wire        double_buffer_enable,
    input  wire        swap_request,
    input  wire        frame_boundary,
    output wire        initialized,
    output wire        busy,
    output reg         front_buffer,
    output reg         double_buffered,
    output reg         swap_done
);

    (* ramstyle = "M10K, no_rw_check" *) reg [7:0] ram [0:76799];
    (* ramstyle = "M10K, no_rw_check" *) reg [7:0] back_ram [0:76799];
    reg [16:0] clear_address;
    reg init_done;
    reg swap_pending;
    wire [16:0] safe_read_address = addr_rd < 17'd76800 ? addr_rd : 17'd0;
    reg [7:0] raw_front_data;
    reg [7:0] raw_back_data;
    reg read_valid;
    reg read_front_buffer;

    assign initialized = init_done;
    assign busy = !init_done || swap_pending;

    // O reset altera apenas o controle. A limpeza sequencial permite inferir
    // memorias M10K e define todos os pixels sem um reset em cada celula RAM.
    always @(posedge clk_wr or negedge rst_n) begin
        if (!rst_n) begin
            clear_address <= 17'd0;
            init_done <= 1'b0;
            front_buffer <= 1'b0;
            double_buffered <= 1'b0;
            swap_pending <= 1'b0;
            swap_done <= 1'b0;
        end else begin
            swap_done <= 1'b0;
            if (!init_done) begin
                if (clear_address == 17'd76799) begin
                    init_done <= 1'b1;
                end else begin
                    clear_address <= clear_address + 17'd1;
                end
            end else if (config_valid) begin
                double_buffered <= double_buffer_enable;
                swap_pending <= 1'b0;
            end else if (double_buffered && (swap_pending || swap_request)) begin
                // Uma escrita em andamento deve terminar antes da apresentacao.
                if (frame_boundary && !we) begin
                    front_buffer <= !front_buffer;
                    swap_pending <= 1'b0;
                    swap_done <= 1'b1;
                end else begin
                    swap_pending <= 1'b1;
                end
            end
        end
    end

    // Separado do reset de controle para manter a inferencia das RAMs.
    always @(posedge clk_wr) begin
        if (rst_n) begin
            if (!init_done) begin
                ram[clear_address] <= 8'd0;
                back_ram[clear_address] <= 8'd0;
            end else if (we && !swap_pending && addr_wr < 17'd76800) begin
                if (front_buffer ^ double_buffered)
                    back_ram[addr_wr] <= data_in;
                else
                    ram[addr_wr] <= data_in;
            end
        end
    end

    // Registros de saida de RAM sem reset/enable permitem inferir M10K.
    // Metadados separados alinham a selecao do banco a essa unica latencia.
    always @(posedge clk_rd) begin
        raw_front_data <= ram[safe_read_address];
        raw_back_data <= back_ram[safe_read_address];
    end

    always @(posedge clk_rd or negedge rst_n) begin
        if (!rst_n) begin
            read_valid <= 1'b0;
            read_front_buffer <= 1'b0;
        end else begin
            read_valid <= init_done && addr_rd < 17'd76800;
            read_front_buffer <= front_buffer;
        end
    end

    always @(*) begin
        if (!rst_n || !init_done || !read_valid)
            data_out = 8'd0;
        else if (read_front_buffer)
            data_out = raw_back_data;
        else
            data_out = raw_front_data;
    end

endmodule
