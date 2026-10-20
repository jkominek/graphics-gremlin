// Graphics Gremlin
//
// Copyright (c) 2021 Eric Schlaepfer
// This work is licensed under the Creative Commons Attribution-ShareAlike 4.0
// International License. To view a copy of this license, visit
// http://creativecommons.org/licenses/by-sa/4.0/ or send a letter to Creative
// Commons, PO Box 1866, Mountain View, CA 94042, USA.
//
`default_nettype none
module cga_test_top(
    // Clocks
    input clk_10m,
    input clk_14m318,
    input clk_bus,

    // Bus reset
    input busreset,

    // ISA bus
    input[19:0] bus_a,
    input bus_ior_l,
    input bus_iow_l,
    input bus_memr_l,
    input bus_memw_l,
    inout[7:0] bus_d,
    output bus_dir,
    output bus_rdy,
    output bus_0ws_l,
    input bus_aen,
    input bus_ale,

    // RAM
    output ram_we_l,
    output[18:0] ram_a,
    inout[7:0] ram_d,

    // Video outputs
    output hsync,
    output vsync,
    output vid_en_l,
    output d_r,
    output d_g,
    output d_b,
    output d_r2,
    output d_g2,
    output d_b2,
    output vga_hsync,
    output vga_vsync,
    output[5:0] red,
    output[6:0] green,
    output[5:0] blue,

    // Config switches
    input switch2,
    input switch3
    );

    // Standalone output test: no ISA transactions or host setup.
    assign bus_d = 8'hzz;
    assign bus_dir = 1'b0;
    assign bus_rdy = 1'b1;
    assign bus_0ws_l = 1'b1;
    wire[7:0] ram_dout;
    wire ram_drive;
    wire ram_failed;
    assign ram_d = ram_drive ? ram_dout : 8'hzz;
    assign vid_en_l = 1'b0;

    wire clk_main;
    wire pll_lock;
    // Same 28.636 MHz pixel clock as cga_top.
`ifdef SYNTHESIS
    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(0), .DIVF(63), .DIVQ(5), .FILTER_RANGE(1)
    ) cga_pll (
        .LOCK(pll_lock), .RESETB(1'b1), .BYPASS(1'b0),
        .PACKAGEPIN(clk_14m318), .PLLOUTGLOBAL(clk_main)
    );
`else
    // As in cga_top, simulation supplies the PLL output clock directly.
    assign clk_main = clk_14m318;
    assign pll_lock = 1'b1;
`endif

    // Release the counters only after PLL lock has crossed into clk_main.
    reg[1:0] ready = 2'b00;
    always @(posedge clk_main)
        ready <= {ready[0], pll_lock};

    sram_test memory_test (
        .clk(clk_main), .enable(ready[1]),
        .ram_a(ram_a), .ram_we_l(ram_we_l),
        .ram_dout(ram_dout), .ram_drive(ram_drive), .ram_din(ram_d),
        .failed(ram_failed), .cycle_done()
    );

    // A CGA line spans 912 pixels at 14.318 MHz (1824 master clocks).
    // Generate two VGA lines in that time, without a line buffer. Both
    // ports show 640x200 source pixels in a 262-line, ~59.92 Hz frame;
    // VGA repeats every source row, giving 640x400 within 524 lines.
    reg[10:0] hcount = 11'd0;
    reg[8:0] y = 9'd0;
    always @(posedge clk_main) begin
        if (!ready[1]) begin
            hcount <= 11'd0;
            y <= 9'd0;
        end else if (hcount == 11'd1823) begin
            hcount <= 11'd0;
            y <= (y == 9'd261) ? 9'd0 : y + 9'd1;
        end else begin
            hcount <= hcount + 11'd1;
        end
    end

    // Change the indicator only at frame boundaries. Thirty frames on,
    // thirty off (~1 Hz). A failed test stays latched until reconfiguration.
    reg[5:0] blink_frames = 6'd0;
    reg show_failure = 1'b0;
    always @(posedge clk_main) begin
        if (!ready[1]) begin
            blink_frames <= 6'd0;
            show_failure <= 1'b0;
        end else if (hcount == 1823 && y == 261) begin
            blink_frames <= (blink_frames == 59) ? 6'd0 : blink_frames + 6'd1;
            show_failure <= ram_failed && blink_frames < 30;
        end
    end

    wire[9:0] cga_x = hcount[10:1];
    wire[10:0] vga_x = (hcount >= 11'd912) ?
                                hcount - 11'd912 : hcount;

    // All 16 RGBI colors in 40-pixel bars, a white perimeter, and a
    // black/white 8x8 checkerboard in the bottom 40 source scanlines.
    function [3:0] pattern;
        input[10:0] x;
        input[8:0] row;
        begin
            if (x >= 11'd640 || row >= 9'd200)
                pattern = 4'h0;
            else if (x == 0 || x == 639 || row == 0 || row == 199)
                pattern = 4'hf;
            else if (row >= 160)
                pattern = (x[3] ^ row[3]) ? 4'hf : 4'h0;
            else
                pattern = x / 11'd40;
        end
    endfunction

    // Red 16x16 marker in the top-left black bar, on both connectors.
    wire cga_fault_pixel = show_failure && cga_x >= 16 && cga_x < 32 && y >= 16 && y < 32;
    wire vga_fault_pixel = show_failure && vga_x >= 16 && vga_x < 32 && y >= 16 && y < 32;
    wire[3:0] video = !ready[1] ? 4'h0 : cga_fault_pixel ? 4'h4 : pattern({1'b0, cga_x}, y);
    wire[3:0] vga_video = !ready[1] ? 4'h0 : vga_fault_pixel ? 4'h4 : pattern(vga_x, y);
    assign d_r = video[2];
    assign d_g = video[1];
    assign d_b = video[0];
    assign d_r2 = 1'b0;
    assign d_g2 = video[3];
    assign d_b2 = 1'b0;

    // Positive CGA sync; VGA uses positive H and negative V for 400 lines.
    assign hsync = ready[1] && cga_x >= 720 && cga_x < 880;
    assign vsync = ready[1] && y >= 224 && y < 227;
    wire vga_h = ready[1] && vga_x >= 720 && vga_x < 880;
    wire vga_v = !(ready[1] && y >= 224 && y < 227);

    wire[5:0] vga_red;
    wire[6:0] vga_green;
    wire[5:0] vga_blue;
    cga_vgaport vga (
        .clk(clk_main), .video(vga_video),
        .red(vga_red), .green(vga_green), .blue(vga_blue)
    );

    // Match the DAC's one-clock latency and force true black in blanking
    // (the shared CGA DAC normally holds the green LSB high).
    reg vga_active = 1'b0;
    reg hsync_d = 1'b0;
    reg vsync_d = 1'b1;
    always @(posedge clk_main) begin
        vga_active <= ready[1] && vga_x < 640 && y < 200;
        hsync_d <= vga_h;
        vsync_d <= vga_v;
    end
    assign vga_hsync = hsync_d;
    assign vga_vsync = vsync_d;
    assign red = vga_active ? vga_red : 6'd0;
    assign green = vga_active ? vga_green : 7'd0;
    assign blue = vga_active ? vga_blue : 6'd0;
endmodule
