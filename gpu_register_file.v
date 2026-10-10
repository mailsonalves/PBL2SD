// Tres leituras combinacionais e uma escrita sincrona; r0 permanece zero.
module gpu_register_file (
    input wire clk,
    input wire rst_n,
    input wire restart,
    input wire write_enable,
    input wire [3:0] write_address,
    input wire [31:0] write_data,
    input wire [3:0] read_address_a,
    input wire [3:0] read_address_b,
    input wire [3:0] read_address_c,
    output wire [31:0] read_data_a,
    output wire [31:0] read_data_b,
    output wire [31:0] read_data_c
);
    reg [31:0] registers [0:15];
    integer index;
    assign read_data_a = (read_address_a == 0) ? 32'd0 : registers[read_address_a];
    assign read_data_b = (read_address_b == 0) ? 32'd0 : registers[read_address_b];
    assign read_data_c = (read_address_c == 0) ? 32'd0 : registers[read_address_c];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (index = 0; index < 16; index = index + 1)
                registers[index] <= 32'd0;
        end else if (restart) begin
            for (index = 0; index < 16; index = index + 1)
                registers[index] <= 32'd0;
        end else if (write_enable && write_address != 0) begin
            registers[write_address] <= write_data;
        end
    end
endmodule
