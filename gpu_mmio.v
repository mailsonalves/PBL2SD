// Interface Avalon-MM local: address em bytes, leitura sem latencia declarada.
// PROG_DATA usa waitrequest para aguardar a leitura sincrona da RAM existente.
// Clock, reset e ponte fisica HPS/FPGA sao responsabilidade da integracao.
module gpu_mmio #(
    parameter integer PROGRAM_WORDS = 256,
    parameter ENABLE_PROGRAM_UPLOAD = 1'b1
) (
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
    input  wire        program_ready,
    input  wire [31:0] program_readdata,
    output reg  [31:0] readdata,
    output wire        waitrequest,
    output reg         restart,
    output wire        pause,
    output reg         clear_error,
    output reg         load_mode,
    output reg  [8:0]  program_length,
    output reg  [8:0]  program_address,
    output wire        program_write,
    output wire [31:0] program_writedata,
    output wire [3:0]  program_byteenable
);
    localparam [8:0] CAPACITY = PROGRAM_WORDS[8:0];
    localparam [15:0] CAPACITY_STATUS = PROGRAM_WORDS[15:0];
    localparam [31:0] HALT = 32'hF0000000;
    reg stored_pause;
    reg [31:0] frame_count;
    reg load_error;
    reg [1:0] read_cooldown;

    wire load_ready = ENABLE_PROGRAM_UPLOAD && load_mode && program_ready;
    wire valid_program_address = program_address < CAPACITY;
    wire data_read = read && address == 6'h1C;
    assign pause = stored_pause || load_mode;
    // O barramento pode sair de reset antes do reset sincronizado da GPU.
    // Nao sinalizar aceitacao enquanto uma transacao seria descartada.
    assign waitrequest = !rst_n || (data_read && load_ready &&
                         valid_program_address && read_cooldown != 0);

    wire accepted_write = rst_n && write && !waitrequest;
    wire control_write = accepted_write && address == 6'h00 && byteenable[0];
    wire address_write = ENABLE_PROGRAM_UPLOAD && accepted_write &&
                         address == 6'h18 && (|byteenable[1:0]);
    wire data_write = ENABLE_PROGRAM_UPLOAD && accepted_write &&
                      address == 6'h1C && (|byteenable);
    wire length_write = ENABLE_PROGRAM_UPLOAD && accepted_write &&
                        address == 6'h20 && (|byteenable[1:0]);

    // RAM e contador veem o MESMO endereco na borda aceita. Um pulso
    // registrado escreveria na palavra seguinte apos o autoincremento.
    assign program_write = data_write && load_ready && valid_program_address;
    assign program_writedata = writedata;
    assign program_byteenable = byteenable;

    function [8:0] merge_bytes;
        input [8:0] previous;
        input [31:0] incoming;
        input [3:0] mask;
        begin
            merge_bytes = previous;
            if (mask[0]) merge_bytes[7:0] = incoming[7:0];
            if (mask[1]) merge_bytes[8] = incoming[8];
        end
    endfunction

    wire [8:0] next_address = merge_bytes(program_address, writedata, byteenable);
    wire [8:0] next_length = merge_bytes(program_length, writedata, byteenable);
    wire mode_transition = ENABLE_PROGRAM_UPLOAD && control_write &&
                           (writedata[3] != load_mode);

    // A configuracao FPGA inicializa RAM e metadados juntos. Reset da GPU
    // preserva os dois: evita perder o limite e executar uma carga parcial.
    // Quartus suporta inicializacao de registradores por initial.
    initial begin
        load_mode = 1'b0;
        program_length = CAPACITY;
    end

    always @(posedge clk) begin
        if (rst_n && ENABLE_PROGRAM_UPLOAD) begin
            if (control_write)
                load_mode <= writedata[3];
            if (length_write && load_ready && next_length != 0 && next_length <= CAPACITY)
                program_length <= next_length;
        end
    end

    always @(*) begin
        readdata = 32'd0;
        if (read) begin
            case (address)
                6'h00: readdata = {28'd0, load_mode, 2'd0, pause};
                6'h04: readdata = status;
                6'h08: readdata = pc;
                6'h0C: readdata = ir;
                6'h10: readdata = frame_count;
                6'h14: readdata = 32'h50424C32; // ASCII "PBL2".
                6'h18: if (ENABLE_PROGRAM_UPLOAD) readdata = {23'd0, program_address};
                6'h1C: if (ENABLE_PROGRAM_UPLOAD)
                            readdata = load_ready && valid_program_address ? program_readdata : HALT;
                6'h20: if (ENABLE_PROGRAM_UPLOAD) readdata = {23'd0, program_length};
                6'h24: if (ENABLE_PROGRAM_UPLOAD)
                            readdata = {CAPACITY_STATUS, 14'd0, load_error, load_ready};
                default: readdata = 32'd0;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stored_pause    <= 1'b0;
            restart         <= 1'b0;
            clear_error     <= 1'b0;
            frame_count     <= 32'd0;
            program_address <= 9'd0;
            load_error      <= 1'b0;
            read_cooldown   <= 2'd0;
        end else begin
            restart     <= 1'b0;
            clear_error <= 1'b0;
            if (frame_boundary)
                frame_count <= frame_count + 32'd1;

            if (read_cooldown != 0)
                read_cooldown <= read_cooldown - 2'd1;

            if (control_write) begin
                stored_pause <= writedata[0];
                restart <= writedata[1] || mode_transition;
                clear_error <= writedata[2];
                if (writedata[2]) load_error <= 1'b0;
                if (mode_transition) begin
                    read_cooldown <= 2'd2;
                    if (writedata[3]) begin
                        program_address <= 9'd0;
                        load_error <= 1'b0;
                    end
                end
            end

            if (address_write) begin
                if (load_ready && next_address <= CAPACITY) begin
                    program_address <= next_address;
                    read_cooldown <= 2'd2;
                end else load_error <= 1'b1;
            end
            if (data_write) begin
                if (program_write) begin
                    program_address <= program_address + 9'd1;
                    read_cooldown <= 2'd2;
                end else load_error <= 1'b1;
            end
            if (length_write && (!load_ready || next_length == 0 || next_length > CAPACITY))
                load_error <= 1'b1;
        end
    end
endmodule
