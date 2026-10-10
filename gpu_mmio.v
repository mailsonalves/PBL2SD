// Banco de controle/observacao, no mesmo dominio de clock da GPU.
// address e um deslocamento em BYTES; leituras combinacionais sem latencia.
// A conexao com o HPS/Platform Designer e externa a este modulo.
module gpu_mmio (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [5:0]  address,
    input  wire        read,
    input  wire        write,
    input  wire [31:0] writedata,
    input  wire [3:0]  byteenable,
    input  wire [31:0] status,
    input  wire [31:0] pc,
    input  wire [31:0] ir,
    input  wire        frame_boundary,
    output reg  [31:0] readdata,
    output wire        waitrequest,
    output reg         restart,
    output reg         pause,
    output reg         clear_error
);
    reg [31:0] frame_count;

    assign waitrequest = 1'b0;

    always @(*) begin
        readdata = 32'd0;
        if (read) begin
            case (address)
                6'h00: readdata = {31'd0, pause};
                6'h04: readdata = status;
                6'h08: readdata = pc;
                6'h0C: readdata = ir;
                6'h10: readdata = frame_count;
                6'h14: readdata = 32'h50424C32; // ASCII "PBL2".
                default: readdata = 32'd0;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pause       <= 1'b0;
            restart     <= 1'b0;
            clear_error <= 1'b0;
            frame_count <= 32'd0;
        end else begin
            restart     <= 1'b0;
            clear_error <= 1'b0;
            if (frame_boundary)
                frame_count <= frame_count + 32'd1;

            // Todos os bits gravaveis pertencem ao primeiro byte.
            // Outros enderecos/bytes e os registradores RO nao produzem efeitos.
            if (write && address == 6'h00 && byteenable[0]) begin
                pause       <= writedata[0];
                restart     <= writedata[1];
                clear_error <= writedata[2];
            end
        end
    end
endmodule
