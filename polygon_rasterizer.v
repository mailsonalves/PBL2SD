// Rasterizador de Poligonos por Bounding Box e Funcoes de Aresta
module polygon_rasterizer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        clear_screen,
    output reg         busy,

    input  wire [8:0]  x0, y0,
    input  wire [8:0]  x1, y1,
    input  wire [8:0]  x2, y2,
    input  wire [7:0]  color,

    output reg         buf_we,
    output reg  [16:0] buf_addr,
    output reg  [7:0]  buf_data
);

    localparam IDLE       = 2'd0;
    localparam SETUP      = 2'd1;
    localparam RAST_TRI   = 2'd2;
    localparam RAST_CLEAR = 2'd3;

    reg [1:0] state;
    reg [8:0] min_x, max_x, min_y, max_y;
    reg [8:0] curr_x, curr_y;
    reg signed [10:0] vx0, vy0, vx1, vy1, vx2, vy2;
    reg [7:0] latched_color;

    wire signed [10:0] px = {2'b00, curr_x};
    wire signed [10:0] py = {2'b00, curr_y};

    wire signed [21:0] e01, e12, e20, triangle_area;
    wire is_inside;
    raster_alu datapath (
        .px(px), .py(py), .vx0(vx0), .vy0(vy0),
        .vx1(vx1), .vy1(vy1), .vx2(vx2), .vy2(vy2),
        .e01(e01), .e12(e12), .e20(e20),
        .triangle_area(triangle_area), .is_inside(is_inside)
    );
    // 320 = 256 + 64. Alargamento antes dos deslocamentos evita truncamento.
    wire [16:0] current_address =
        ({8'd0, curr_y} << 8) + ({8'd0, curr_y} << 6) + {8'd0, curr_x};

    function [8:0] min3(input [8:0] a, b, c);
        min3 = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
    endfunction

    function [8:0] max3(input [8:0] a, b, c);
        max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            busy     <= 1'b0;
            buf_we   <= 1'b0;
            buf_addr <= 17'd0;
            buf_data <= 8'd0;
            curr_x   <= 9'd0;
            curr_y   <= 9'd0;
            min_x    <= 9'd0;
            max_x    <= 9'd0;
            min_y    <= 9'd0;
            max_y    <= 9'd0;
            vx0      <= 11'sd0;
            vy0      <= 11'sd0;
            vx1      <= 11'sd0;
            vy1      <= 11'sd0;
            vx2      <= 11'sd0;
            vy2      <= 11'sd0;
            latched_color <= 8'd0;
        end else begin
            buf_we <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        latched_color <= color;
                        if (clear_screen) begin
                            curr_x <= 9'd0;
                            curr_y <= 9'd0;
                            state  <= RAST_CLEAR;
                        end else begin
                            vx0   <= {2'b00, x0}; vy0 <= {2'b00, y0};
                            vx1   <= {2'b00, x1}; vy1 <= {2'b00, y1};
                            vx2   <= {2'b00, x2}; vy2 <= {2'b00, y2};

                            min_x <= min3(x0, x1, x2);
                            max_x <= max3(x0, x1, x2);
                            min_y <= min3(y0, y1, y2);
                            max_y <= max3(y0, y1, y2);
                            state <= SETUP;
                        end
                    end else begin
                        busy <= 1'b0;
                    end
                end

                SETUP: begin
                    curr_x <= min_x;
                    curr_y <= min_y;
                    if (triangle_area == 0) begin
                        state <= IDLE;
                        busy <= 1'b0;
                    end else begin
                        state <= RAST_TRI;
                    end
                end

                RAST_TRI: begin
                    if (is_inside && curr_x < 320 && curr_y < 240) begin
                        buf_we   <= 1'b1;
                        buf_addr <= current_address;
                        buf_data <= latched_color;
                    end

                    if (curr_x >= max_x) begin
                        curr_x <= min_x;
                        if (curr_y >= max_y) begin
                            state <= IDLE;
                            busy  <= 1'b0;
                        end else begin
                            curr_y <= curr_y + 9'd1;
                        end
                    end else begin
                        curr_x <= curr_x + 9'd1;
                    end
                end

                RAST_CLEAR: begin
                    buf_we   <= 1'b1;
                    buf_addr <= current_address;
                    buf_data <= 8'h00;

                    if (curr_x == 9'd319) begin
                        curr_x <= 9'd0;
                        if (curr_y == 9'd239) begin
                            state <= IDLE;
                            busy  <= 1'b0;
                        end else begin
                            curr_y <= curr_y + 9'd1;
                        end
                    end else begin
                        curr_x <= curr_x + 9'd1;
                    end
                end
            endcase
        end
    end

endmodule
