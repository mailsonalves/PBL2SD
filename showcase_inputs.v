// Entradas da bancada: duas etapas de sincronizacao e filtro de botoes.
// Chaves sao niveis; KEY[3:1] chegam ativos em zero e saem ativos em um.
module showcase_inputs #(
    parameter integer DEBOUNCE_CYCLES = 250000
) (
    input wire clk,
    input wire rst_n,
    input wire [9:0] switches,
    input wire [2:0] keys_n,
    output wire [9:0] sw_state,
    output reg [2:0] key_state
);
    localparam integer COUNT_WIDTH = (DEBOUNCE_CYCLES > 1) ? $clog2(DEBOUNCE_CYCLES) : 1;
    reg [9:0] sw_meta, sw_sync;
    reg [2:0] key_meta, key_sync;
    reg [COUNT_WIDTH-1:0] stable_count [0:2];
    assign sw_state = sw_sync;
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sw_meta <= 0;
            sw_sync <= 0;
            key_meta <= 0;
            key_sync <= 0;
            key_state <= 0;
            for (i = 0; i < 3; i = i+1) stable_count[i] <= 0;
        end else begin
            sw_meta <= switches;
            sw_sync <= sw_meta;
            key_meta <= ~keys_n;
            key_sync <= key_meta;
            for (i = 0; i < 3; i = i+1) begin
                if (key_sync[i] == key_state[i]) stable_count[i] <= 0;
                else if (DEBOUNCE_CYCLES <= 1 || stable_count[i] == DEBOUNCE_CYCLES-1) begin
                    key_state[i] <= key_sync[i];
                    stable_count[i] <= 0;
                end else stable_count[i] <= stable_count[i] + 1'b1;
            end
        end
    end
endmodule
