// Apenas flags e erro sao registrados; os outros bits mostram o estado atual.
module gpu_status_register (
    input wire clk,
    input wire rst_n,
    input wire flags_we,
    input wire [3:0] flags_in,
    input wire error_set,
    input wire error_clear,
    input wire halted,
    input wire graphics_busy,
    input wire waiting_frame,
    input wire buffer_initialized,
    input wire buffer_front,
    input wire buffer_double_buffered,
    input wire cmd_ready,
    output reg [3:0] flags,
    output reg error,
    output wire [31:0] status
);
    assign status = {20'd0, cmd_ready, buffer_double_buffered, buffer_front,
                     buffer_initialized, waiting_frame, graphics_busy,
                     halted, error, flags};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flags <= 4'd0;
            error <= 1'b0;
        end else begin
            if (flags_we)
                flags <= flags_in;
            if (error_set)
                error <= 1'b1;
            else if (error_clear)
                error <= 1'b0;
        end
    end
endmodule
