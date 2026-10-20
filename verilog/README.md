# The Graphics Gremlin - FPGA code

(Click here for the [main README](https://github.com/schlae/graphics-gremlin/blob/main/README.md))

The FPGA code is divided into two major sets of files, those for CGA graphics and those for MDA graphics. At some point I'll tidy up and make a nice organized directory tree, but for now they're all in the same place.

* mda\_top.v: The top level file instantiating the MDA graphics logic
* mda70\_top.v: An alternative top level file for VGA compatible MDA graphics
* mda.v: Implements MDA ISA interface, IO registers and instantiates the CRTC, SRAM interface, sequencer, and pixel engine
* crtc6845.v: This is my mostly-accurate recreation of the old Motorola 6845 CRT controller chip. It generates all the sync timings as well as the character and row addresses. There are probably slight differences between it and the real thing.
* mda\_sequencer.v: Controls timing across the entire card, deciding when to fetch SRAM data, look up character bits from the character ROM, and allow ISA bus access to the SRAM
* mda\_vram.v: Implements the state machine to arbitrate ISA bus and pixel engine access to the video ram (external SRAM)
* mda\_pixel.v: This is the pixel engine. It takes data coming from the SRAM, looks up the pixels in the character ROM, and shifts the data out one pixel at a time. 
* mda\_attrib.v: The attribute generator applies video attributes to the raw pixel data, including brightness, underline, inverse video, blinking. It also applies the blinking cursor.
* mda\_vgaport.v: This module turns the digital MDA video signals into numbers to drive the resistor ladder DAC connected to the VGA port. If you (gasp) dislike amber monochrome monitors, then you can hack this code to make it green or white.

CGA graphics logic is similar to MDA and shares the same crtc6845.v logic, but the cards are different enough that I couldn't share more.
* cga\_top.v: Instantiates top level CGA logic.
* cga.v: Implements the ISA bus interface, CGA control registers, wait state generator, and most of the other CGA modules
* cga\_sequencer.v: Generates most of the timing signals used on the card, including memory fetches and pixel engine timing.
* cga\_vram.v: Implements a very basic address MUX for the SRAM interface. This actually causes too much CGA snow, and should be improved using the MDA VRAM interface as a model.
* cga\_pixel.v: The CGA pixel engine takes data from the SRAM, does a character lookup (text mode only), and shifts the data out 1 or 2 bits at a time, depending on the video mode.
* cga\_attrib.v: The attribute generator applies video attributes to the raw pixels data, including color, brightness, and blinking.
* cga\_composite.v: Contains the flip flops used to generate NTSC composite color as well as new sync pulses. The output is a 7-bit signal passed off to the green DAC channel for the RCA jack on the card.
* cga\_scandoubler.v: A very basic scan doubler to convert 15.7KHz CGA video to 31.4KHz VGA video. To save memory, this is done using 4-bit digital RGBI signals.
* cga\_vgaport.v: This module takes RGBI digital video from the scan doubler and turns it into numbers that drive the resistor ladder DAC connected to the VGA port. It produces CGA brown instead of dark yellow.

Other miscellaneous files include:
* cga.hex and mda.hex: character ROM
* gremlin.pcf: The pin constraints file that determines what signals are tied to what pins on the FPGA
* isavideo\_t.v: A sloppy test bench that I used to validate and troubleshoot the rest of the logic.
* is61c5128\_t.v: A behavorial Verilog model of the SRAM chip.
* is61\_tester.v: A test bench I used to verify the SRAM chip behavioral model.

## Building

To build the project, you will need to install the tools from [Project IceStorm](http://www.clifford.at/icestorm/) (full instructions are available at that link). The Graphics Gremlin uses NextPNR, so make sure you install that.

Alternatively, you can install the [OSS Cad Suite](https://github.com/YosysHQ/oss-cad-suite-build) which is prebuilt and runs on a variety of platforms.

Once the tools are installed, just navigate to the Graphics Gremlin Verilog directory and run
```
mkdir build
make
```
If you have the FTDI programming cable hooked up to the card, you can also type `make prog`. As a convenience, `make reset` will not program the FPGA but will toggle its reset line which is useful if you change the red switch bank and don't want to cycle power on the host PC.

If the `make prog` command can't find the FTDI programming cable, make sure you have the udev rules set up.



## Standalone output and SRAM test

The fourth image, `cga_test_top`, starts a test pattern without BIOS setup,
ISA clocks, bus reset, or working video RAM. Select it with DIP switches 3
and 4 both closed, then power-cycle the card or use `make reset`. Switches
1 and 2 are ignored; VGA RGB output is always enabled (no composite mode).

Both ports show sixteen RGBI color bars, a white border, and an 8x8
black/white checkerboard along the bottom. The 9-pin CGA port generates
640x200 at about 15.70 kHz horizontal / 59.92 Hz vertical. The VGA port
repeats each row for 640x400 at about 31.40 kHz / 59.92 Hz, using the same
28.636 MHz clock and color DAC mapping as the CGA image, including brown.
These are CGA-derived timings, rather than standard 640x480 VGA timing.

The image never drives ISA data or requests wait states. It requires card
power and the onboard 14.318 MHz oscillator, but no host initialization.

A continuous destructive SRAM test fills all 512 KiB and then verifies it.
Six passes use address bits A0-A7, A8-A15, and A16-A18, each normally and
inverted. Filling before checking catches address aliasing; the data
patterns exercise all eight data lines at both levels. One complete cycle
takes about one second. The display does not depend on SRAM contents.

Any mismatch latches a failure until FPGA reconfiguration (power-cycle or
`make reset`). A red 16x16 square in the top-left black bar blinks at about
1 Hz on both ports. No marker means no failure detected yet; allow a full
cycle before judging the result. This checks stuck/aliased address lines,
data faults, and memory contents, rather than being an exhaustive SRAM
stress test. Consistently swapped address or data wires can still pass a
write/read test.

SRAM bus turnaround and write timing follow the fitted 10 ns part's
[ISSI datasheet](https://www.mouser.com/datasheet/2/198/61-64WV5128Axx-Bxx-258353.pdf).
`make test-sram` requires Verilator and a C++ compiler and checks a complete
healthy-memory cycle plus injected stuck-low/high faults on every address
and data line and a data-line short.

`make` includes it as the fourth entry in `build/isavideo.binm`, preserving
the original three image selections. `make test-pattern` runs the standalone
simulation checks.
