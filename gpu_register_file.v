// Banco de 16 registradores de 32 bits. R0 sempre devolve zero.
// Leituras combinacionais permitem executar uma operacao em uma borda.
module gpu_register_file (
    input wire clk,
    input wire rst_n,
    input wire we,
    input wire [3:0] write_addr,
    input wire [31:0] write_data,
    input wire [3:0] read_addr_a,
    input wire [3:0] read_addr_b,
    output wire [31:0] read_data_a,
    output wire [31:0] read_data_b
);
    reg [31:0] registers [0:15];
    integer i;

    assign read_data_a = (read_addr_a == 0) ? 32'd0 : registers[read_addr_a];
    assign read_data_b = (read_addr_b == 0) ? 32'd0 : registers[read_addr_b];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1)
                registers[i] <= 32'd0;
        end else if (we && write_addr != 0) begin
            registers[write_addr] <= write_data;
        end
    end
endmodule
