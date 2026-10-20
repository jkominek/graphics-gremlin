// Standalone destructive test of the card's 512 KiB asynchronous SRAM.
`default_nettype none
module sram_test (
    input clk,
    input enable,
    output reg[18:0] ram_a = 19'd0,
    output reg ram_we_l = 1'b1,
    output reg[7:0] ram_dout = 8'd0,
    output reg ram_drive = 1'b0,
    input[7:0] ram_din,
    output reg failed = 1'b0,
    output reg cycle_done = 1'b0
);
    // Fill the ENTIRE RAM before verifying, so aliased addresses cannot
    // pass through an immediate write/read of the same location. Three
    // byte slices collectively distinguish all 19 address bits. Each is
    // tested normally and inverted, exercising both levels of every D pin.
    reg[2:0] pass = 3'd0;
    reg reading = 1'b0;
    reg[2:0] state = 3'd0;
    wire[7:0] address_byte = (pass[2:1] == 0) ? ram_a[7:0] :
                             (pass[2:1] == 1) ? ram_a[15:8] :
                             {5'b10101, ram_a[18:16]};
    wire[7:0] expected = pass[0] ? ~address_byte : address_byte;

    // CE and OE are permanently asserted on this board. Lower WE first,
    // then wait a full clock (~35 ns) for SRAM to release D before driving.
    // Hold write data for two clocks; on WE rising release D simultaneously
    // (SRAM specifies zero data hold). Keep A stable another full clock.
    // Reads get two complete clocks of settling before sampling.
    always @(posedge clk) begin
        cycle_done <= 1'b0;
        if (!enable) begin
            ram_a <= 19'd0;
            ram_we_l <= 1'b1;
            ram_drive <= 1'b0;
            ram_dout <= 8'd0;
            pass <= 3'd0;
            reading <= 1'b0;
            state <= 3'd0;
            // Failure is sticky until FPGA reconfiguration, even if the
            // clock loses lock temporarily. ISA reset has no effect.
        end else begin
            case (state)
                0: begin
                    if (!reading) begin
                        ram_we_l <= 1'b0;
                        ram_dout <= expected;
                    end
                    state <= 1;
                end
                1: begin
                    if (!reading) ram_drive <= 1'b1;
                    state <= 2;
                end
                2: begin
                    if (reading) begin
                        if (ram_din !== expected) failed <= 1'b1;
                        state <= 4;
                    end else state <= 3;
                end
                3: begin
                    ram_we_l <= 1'b1;
                    ram_drive <= 1'b0;
                    state <= 4;
                end
                4: begin
                    if (ram_a == 19'h7ffff) begin
                        ram_a <= 19'd0;
                        reading <= ~reading;
                        if (reading) begin
                            if (pass == 3'd5) begin
                                pass <= 3'd0;
                                cycle_done <= 1'b1;
                            end else pass <= pass + 3'd1;
                        end
                    end else ram_a <= ram_a + 19'd1;
                    state <= 0;
                end
                default: begin
                    ram_we_l <= 1'b1;
                    ram_drive <= 1'b0;
                    state <= 0;
                end
            endcase
        end
    end
endmodule
