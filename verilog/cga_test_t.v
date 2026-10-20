`timescale 1ns/1ps
`default_nettype none
module cga_test_t;
    reg clk = 0;
    always #17.46 clk = ~clk;
    reg[31:0] noise = 32'h12345678;
    always @(negedge clk)
        noise <= {noise[30:0], noise[31] ^ noise[21] ^ noise[1] ^ noise[0]};
    wire[7:0] bus_d;
    wire[7:0] ram_d;
    wire bus_dir, bus_rdy, bus_0ws_l, ram_we_l, vid_en_l;
    wire[18:0] ram_a;
    wire hs, vs, vhs, vvs, r, g, b, r2, intensity, b2;
    wire[5:0] red, blue;
    wire[6:0] green;
    cga_test_top dut (
        .clk_14m318(clk), .clk_10m(noise[0]), .clk_bus(noise[1]),
        .busreset(noise[2]), .bus_a(noise[19:0]),
        .bus_ior_l(noise[20]), .bus_iow_l(noise[21]),
        .bus_memr_l(noise[22]), .bus_memw_l(noise[23]),
        .bus_d(bus_d), .bus_dir(bus_dir), .bus_rdy(bus_rdy),
        .bus_0ws_l(bus_0ws_l), .bus_aen(noise[24]), .bus_ale(noise[25]),
        .ram_we_l(ram_we_l), .ram_a(ram_a), .ram_d(ram_d),
        .hsync(hs), .vsync(vs), .vid_en_l(vid_en_l),
        .d_r(r), .d_g(g), .d_b(b), .d_r2(r2), .d_g2(intensity), .d_b2(b2),
        .vga_hsync(vhs), .vga_vsync(vvs), .red(red), .green(green), .blue(blue),
        .switch2(noise[26]), .switch3(noise[27])
    );

    sram_test_model memory (.address(ram_a), .data(ram_d), .we_l(ram_we_l));

    function [3:0] expected_pixel;
        input integer x, y;
        begin
            if (x >= 640 || y >= 200) expected_pixel = 0;
            else if (x == 0 || x == 639 || y == 0 || y == 199) expected_pixel = 15;
            else if (y >= 160) expected_pixel = ((x/8 + y/8) % 2) ? 15 : 0;
            else expected_pixel = x/40;
        end
    endfunction

    // Independent arithmetic form of the RGBI DAC, including CGA brown.
    function [18:0] expected_rgb;
        input[3:0] color;
        integer rr, gg, bb;
        begin
            rr = (color[2] ? 42 : 0) + (color[3] ? 21 : 0);
            gg = (color[1] ? 42 : 0) + (color[3] ? 21 : 0);
            bb = (color[0] ? 42 : 0) + (color[3] ? 21 : 0);
            if (color == 6) gg = 21;
            expected_rgb = {rr[5:0], gg[5:0], 1'b1, bb[5:0]};
        end
    endfunction

    integer tick, x, y, cx, vx;
    integer cga_edges = 0, vga_edges = 0, frames = 0;
    reg prev_hs = 0, prev_vhs = 0, prev_vs = 0;
    reg delayed_hs = 0, delayed_vs = 1;
    reg[18:0] delayed_rgb = 0;
    reg[15:0] seen = 0;
    reg[3:0] color;
    initial begin
        // Two master clocks for the power-on lock synchronizer. No reset.
        repeat (2) @(posedge clk);
        #1;
        for (tick = 0; tick < 2*1824*262; tick = tick+1) begin
            x = tick % 1824;
            y = (tick / 1824) % 262;
            cx = x / 2;
            vx = x % 912;
            color = expected_pixel(cx, y);
            if ({intensity,r,g,b} !== color) $fatal(1, "CGA pixel at tick %0d", tick);
            if (hs !== (cx >= 720 && cx < 880) || vs !== (y >= 224 && y < 227))
                $fatal(1, "CGA sync at tick %0d", tick);
            if ({red,green,blue} !== delayed_rgb || vhs !== delayed_hs || vvs !== delayed_vs)
                $fatal(1, "VGA output at tick %0d", tick);
            if (bus_d !== 8'hzz || bus_dir !== 0 ||
                bus_rdy !== 1'b1 || bus_0ws_l !== 1'b1)
                $fatal(1, "ISA not idle");
            if ({r2,b2,vid_en_l} !== 3'b000) $fatal(1, "Connector control pins");
            if (cx < 640 && y > 0 && y < 160) seen[color] = 1;
            if (hs && !prev_hs) cga_edges = cga_edges + 1;
            if (vhs && !prev_vhs) vga_edges = vga_edges + 1;
            if (vs && !prev_vs) frames = frames + 1;
            prev_hs = hs; prev_vhs = vhs; prev_vs = vs;
            delayed_rgb = (vx < 640 && y < 200) ? expected_rgb(expected_pixel(vx,y)) : 19'd0;
            delayed_hs = vx >= 720 && vx < 880;
            delayed_vs = !(y >= 224 && y < 227);
            @(posedge clk);
            #1;
        end
        if (cga_edges != 524 || vga_edges != 1048 || frames != 2 || seen != 16'hffff)
            $fatal(1, "Frame timing or palette coverage");
        $display("PASS: two frames, CGA/VGA pixels and sync, all 16 colors, blanking, ISA isolation");
        // Inject a latched SRAM fault and accelerate frame counters to check
        // the visible on/off phases without simulating a full blink second.
        force dut.memory_test.failed = 1'b1;
        @(negedge clk);
        dut.hcount = 1823; dut.y = 261; dut.blink_frames = 0;
        @(posedge clk); #1;
        if (!dut.show_failure) $fatal(1, "Failure indicator did not turn on");
        @(negedge clk);
        dut.hcount = 20; dut.y = 20;
        @(posedge clk); #1;
        if ({red,green,blue} !== expected_rgb(4'h4)) $fatal(1, "VGA red indicator");
        @(negedge clk);
        dut.hcount = 40;
        #1;
        if ({intensity,r,g,b} !== 4'h4) $fatal(1, "CGA red indicator");
        @(negedge clk);
        dut.hcount = 1823; dut.y = 261; dut.blink_frames = 30;
        @(posedge clk); #1;
        if (dut.show_failure) $fatal(1, "Failure indicator did not turn off");
        @(negedge clk);
        dut.hcount = 40; dut.y = 20;
        #1;
        if ({intensity,r,g,b} !== 4'h0) $fatal(1, "CGA indicator off phase");
        @(negedge clk);
        dut.hcount = 20;
        @(posedge clk); #1;
        if ({red,green,blue} !== expected_rgb(4'h0)) $fatal(1, "VGA indicator off phase");
        $display("PASS: blinking SRAM failure marker on both connectors");
        $finish;
    end
endmodule
