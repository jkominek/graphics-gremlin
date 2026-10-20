`timescale 1ns/1ps
`default_nettype none
module sram_bus_t;
    reg clk = 0;
    always #17.46 clk = ~clk;
    reg enable = 0;
    wire[18:0] address;
    wire[7:0] data, dout;
    wire we_l, drive, failed;
    assign data = drive ? dout : 8'hzz;
    sram_test dut (.clk(clk), .enable(enable), .ram_a(address),
        .ram_we_l(we_l), .ram_dout(dout), .ram_drive(drive),
        .ram_din(data), .failed(failed), .cycle_done());
    sram_test_model memory (.address(address), .data(data), .we_l(we_l));
    initial begin
        repeat (2) @(negedge clk);
        enable = 1;
        // Run a complete fill/read pair with delayed, resolved tristate IO.
        wait (dut.pass == 1);
        if (failed !== 0) $fatal(1, "Timed SRAM model failed");
        $display("PASS: full-capacity fill/read with SRAM access and turnaround delays");
        $finish;
    end
    always @(negedge clk) begin
        if (failed) $fatal(1, "Read mismatch in timed SRAM model at %h", address);
        if (drive && data !== dout) $fatal(1, "SRAM bus contention");
    end
    initial begin
        #200000000;
        $fatal(1, "Timed SRAM test timeout");
    end
endmodule
