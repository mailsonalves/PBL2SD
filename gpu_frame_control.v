// O contador continua contando quadros enquanto a CPU espera ou esta parada.
module gpu_frame_control (
    input wire clk,
    input wire rst_n,
    input wire frame_boundary,
    output reg [31:0] frame_counter
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            frame_counter <= 32'd0;
        else if (frame_boundary)
            frame_counter <= frame_counter + 1'b1;
    end
endmodule
