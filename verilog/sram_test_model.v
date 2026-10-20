// Full-size asynchronous SRAM model for diagnostic simulations (CE/OE low).
`timescale 1ns/1ps
`default_nettype none
module sram_test_model (
    input[18:0] address,
    inout[7:0] data,
    input we_l
);
    reg[7:0] memory[0:524287];
    wire[18:0] settled_address;
    wire[7:0] held_data;
    wire output_enable;
    assign #10 settled_address = address;
    assign #1 held_data = data;
    // tHZWE <= 5 ns; tLZWE >= 2 ns for the fitted 10 ns SRAM.
    assign #(2,5) output_enable = we_l;
    assign data = output_enable ? memory[settled_address] : 8'hzz;
    always @(posedge we_l)
        memory[settled_address] <= held_data;
endmodule
