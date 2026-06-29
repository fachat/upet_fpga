# ShellUltra simulation setup (GHDL + SDL)

This folder provides a standalone simulation harness for `vhdl/ShellUltra.vhd`.

## Included

- GHDL build/elaboration for the original VHDL design
- A VHDL 65816-compatible simulation core (`vhdl/cpu65816_core.vhd`) wired to matching ShellUltra CPU pins
- FRAM/VRAM behavioral models on the external busses
- SPI flash model (`vhdl/spi_flash_model.vhd`) with 2MiB storage
- Flash initialized from `sim/spiimg` at address 0 (loads the full file, truncated at flash size)
- Frame capture to `out/frame.ppm` at 720x576
- SDL window viewer (`show_frame.py`, via pygame/SDL)

## Prerequisites

- `ghdl`
- `python3`
- `pygame` (`pip install pygame`)

## Run

```bash
cd /home/runner/work/upet_fpga/upet_fpga/sim
make run
```

Outputs:

- `out/sim.vcd`
- `out/frame.ppm`

## Open SDL window

```bash
cd /home/runner/work/upet_fpga/upet_fpga/sim
make view
```

Press `Esc` or close the window to exit.
