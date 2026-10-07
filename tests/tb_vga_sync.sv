`timescale 1ns/1ps

module tb_vga_sync;
    reg clock = 0;
    always #20 clock = ~clock; // Clock real de 25 MHz usado pelo projeto.
    reg rst_n = 0;
    wire hs, vs, active, vblank;
    wire [8:0] x;
    wire [7:0] y;
    integer physical_x, physical_y;
    integer active_count = 0;
    integer horizontal_sync_count = 0;
    integer vertical_sync_count = 0;

    vga_sync dut (
        .clk_25m(clock), .rst_n(rst_n), .hsync(hs), .vsync(vs),
        .video_active(active), .pixel_x(x), .pixel_y(y), .vblank(vblank)
    );

    task automatic check_pixel(input integer px, input integer py);
        reg visible;
        begin
            visible = (px < 640 && py < 480);
            if ((^{hs, vs, active, vblank, x, y}) === 1'bx)
                $fatal(1, "VGA possui saida indefinida em (%0d,%0d)", px, py);
            if (hs !== !(px >= 656 && px < 752))
                $fatal(1, "HS desalinhado em (%0d,%0d)", px, py);
            if (vs !== !(py >= 490 && py < 492))
                $fatal(1, "VS desalinhado em (%0d,%0d)", px, py);
            if (active !== visible || vblank !== (py >= 480) ||
                x !== (visible ? px[9:1] : 9'd0) ||
                y !== (visible ? py[8:1] : 8'd0))
                $fatal(1, "Pixel logico/blank incorreto em (%0d,%0d)", px, py);
        end
    endtask

    initial begin
        repeat (3) @(negedge clock);
        rst_n = 1;
        for (physical_y = 0; physical_y < 525; physical_y = physical_y + 1) begin
            for (physical_x = 0; physical_x < 800; physical_x = physical_x + 1) begin
                check_pixel(physical_x, physical_y);
                if (active) active_count = active_count + 1;
                if (!hs) horizontal_sync_count = horizontal_sync_count + 1;
                if (!vs) vertical_sync_count = vertical_sync_count + 1;
                @(negedge clock);
            end
        end
        check_pixel(0, 0);
        if (active_count != 307200 || horizontal_sync_count != 50400 ||
            vertical_sync_count != 1600)
            $fatal(1, "Duracao do quadro ou pulsos de sincronismo incorreta");
        repeat (123) @(negedge clock);
        rst_n = 0;
        #1;
        check_pixel(0, 0);
        repeat (2) @(negedge clock);
        rst_n = 1;
        @(negedge clock);
        check_pixel(1, 0);
        $display("PASS: 420000 pixels VGA, 2x2, HS/VS, blank e reset");
        $finish;
    end

    initial begin
        #18000000;
        $fatal(1, "Timeout no quadro VGA");
    end
endmodule
