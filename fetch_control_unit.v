// fetch_control_unit.v - Unidade de Busca, PC, IR e Handshake com controle VGA
module fetch_control_unit (
    input  wire        clk,
    input  wire        rst_n,
    
    input  wire        rast_busy,
    input  wire        vsync,
    
    output reg  [31:0] cmd_data,
    output reg         cmd_valid,
    input  wire        cmd_ready,
    output wire [7:0]  pc_out
);

    reg  [7:0]  pc;
    assign pc_out = pc;

    wire [31:0] rom_instruction;
    
    reg vsync_d;
    wire vblank_start = (!vsync && vsync_d);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            vsync_d <= 1'b0;
        else        
            vsync_d <= vsync;
    end

    instruction_memory #( .WORDS(256) ) u_rom (
        .clk     (clk),
        .addr    (pc),
        .data_out(rom_instruction)
    );

    localparam S_FETCH   = 2'd0;
    localparam S_EXEC    = 2'd1;
    localparam S_WAIT    = 2'd2;
    localparam S_VBLANK  = 2'd3;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc        <= 8'd0;
            cmd_data  <= 32'd0;
            cmd_valid <= 1'b0;
            state     <= S_FETCH;
        end else begin
            cmd_valid <= 1'b0;

            case (state)
                S_FETCH: begin
                    cmd_data <= rom_instruction;
                    state    <= S_EXEC;
                end

                S_EXEC: begin
                    case (cmd_data[31:28])
                        4'hE: begin // WAIT_VBLANK
                            state <= S_VBLANK;
                        end

                        4'hF: begin // JUMP
                            pc    <= cmd_data[7:0];
                            state <= S_FETCH;
                        end

                        default: begin
                            if (cmd_ready) begin
                                cmd_valid <= 1'b1;
                                // Instrucoes com operacao demorada na ULA esperam o busy
                                if (cmd_data[31:28] == 4'h9 || cmd_data[31:28] == 4'h0 || cmd_data[31:28] == 4'hD)
                                    state <= S_WAIT;
                                else begin
                                    pc    <= pc + 1'b1;
                                    state <= S_FETCH;
                                end
                            end
                        end
                    endcase
                end

                S_WAIT: begin
                    if (!rast_busy) begin
                        pc    <= pc + 1'b1;
                        state <= S_FETCH;
                    end
                end

                S_VBLANK: begin
                    if (vblank_start) begin
                        pc    <= pc + 1'b1;
                        state <= S_FETCH;
                    end
                end

                default: state <= S_FETCH;
            endcase
        end
    end

endmodule