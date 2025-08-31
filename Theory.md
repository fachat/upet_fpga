
# Theory of Operation

This document describes some of the rationale and inner workings of 
the FPGA code.

## General Timing

The system is a synchronous system, running off of a single clock input.

The main clock is an input to the FPGA using a global clock pin.
This main clock runs at twice the pixel frequency of the desired
video output. The CPU runs at one fourth of the main clock.

So, for example, with a 54 MHz input clock, the video pixel frequency
is 27 MHz, and the CPU runs at max 13.5 MHz.

### Clock signals

* qclk - oscillator input clock
* dotclk - 1/2 of the qclk, used for pixel (dot) shift out and many other purposes
* memclk - 1/2 of dotclk, this is the main access clock for memory
* phi2 - CPU clock; usually memclk, but may be stretched and 'fixed' to accomodate slower modes or access conflicts
* cphi2 - Bus clock; 1 MHz
* c2phi2 - Bus dRAM clock; 2 MHz, can directly used as dRAM /RAS on the bus (i.e. starts with high and then goes low in each cphi2 half cycle)
* c8phi2 - Bus pixel clock; 8 MHz, used to shift out pixels on the CS/A CRTC board. (see also comments below)

### 1 MHz bus

The I/O bus is running at 1 MHz. While previous versions only approximated
the 1 MHz clock, this version calculates the 1 MHz clock by dividing
the main clock exactly. 

So, for example, a 54 MHz clock is divided by 54 to generate the 1 MHz bus 'cphi2' clock. The bus clock low phase has 27 clock ticks, as has the bus clock high phase.

#### Special bus clock signals

The bus also has 2Phi2 and 8Phi2 signals, that are in a strict phase relation to the 1 MHz bus clock. Unfortunately the 27 clock ticks are not divisible by 2 or even 4 to create these clocks. Therefore, some clock shaping needs to be done.

For the 2Phi2 clock, the 27 clock ticks for a half 1 MHz clock are divided into 13 clock ticks high and 14 clock ticks low. Note, the 2Phi2 clock is used as /ROW on dRAM chips, and has the first half high, and the second half as low.

The 8Phi2 clock is used as pixel clock on the CS/A CRTC video board. The clock is divided into 3 clock ticks low, then 4 clock ticks high - except for every fourth cycle, where the high phase is only 3 clocks ticks. This way, a (unused) 4Phi2 would have 6+7 and 7+7 ticks, resulting in the 2Phi2 timing.2 would have 6+7 and 7+7 ticks, resulting in the 2Phi2 timing, keeping them in sync.

This means, if you would use an old CRTC-based CS/A video board on the expansion bus, that the pixel width in the output is not uniform. Real effects have not been tested (yet), and it remains to be seen how far this is visible. As a fallback, 8Phi2 may at some point be created by a PLL inside the FPGA.

#### Controlling bus access

The CPU at full speed is much faster than the 1 MHz bus. So, the CPU can 'hide' fast bus accesses inside the bus Phi2 low phase. To allow for bus address setup time, however, the bus address must be stable some time before the bus Phi2 goes high. So, there is a specific intervall where in the 1 MHz clock, the CPU can actualy start a bus access, or has to wait otherwise.
The signal that determines when a CPU access on the bus can be started is 'csetup'.

At the end of a bus access cycle, 'chold' signals the last dotclk (half memclk) cycle for the bus access. This way the top level code can then prepare to release the CPU phi2 so it can go low at the end of the bus cycle.

Unfortunately, the end of the 1 MHz cycle does not always fall onto a high to low transition of the fast CPU clock, as 1 MHz cycle has 13,5 CPU cycles in it. Therefore, if chold is detected when the memclk is low (instead of high), 'is_bus_a' is asserted, and this replaces the CPU phi with the invert of 'csetup' for a full memclk cycle, so it has a falling edge on the falling edge of the bus clock. On the next memclk low phase this is reverted again.

#### Write Data Hold Time

The CPU is running at 13.5 MHz, and after finishing a bus transaction (at falling bus 'cphi2') the address (and data) lines are quickly changed. This has proven to be too fast
for slower bus devices that require some hold time after the falling bus phi2. Therefore, if the bus is used, and a write happens, then the bus clock is shortened by the 'chold' signal.
This signals the bus device to take over the data, and keeps the CPU still on hold until the following dotclk cycle.

### Slowing the CPU

The CPU can be run at full speed - 13.5 MHz - or at lower speeds of 1, 2, or 4 MHz, independent of the bus access.

As the memory access always happens at 13.5 MHz, the CPU will be held between the slower accesses with its Phi2 pin held high. In fact, this is the default, and the clock module just triggers an access by giving a pulse every 1, 2, or 4 MHz clock ticks.

The main module registers the need for a CPU cycle, and can then run it at the next convenient time - which may be delayed for example due to bus conflicts with the video or DMA access.
The goal of this is to provide an overall speed of 1, 2, or 4 MHz, even in the face of other devices that may need the bus.

Those pulse signals are called 'clk1m', 'clk2m', and 'clk4m'.

As the clock pulses are generated by the 1 MHz counter, they may be in 50% phase shift with the actual main clock ('memclk'). Therefore, to be reliably detected when memclk is high, they are a full memclk cycle long.

