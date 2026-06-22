GHDL ?= ghdl
GHDLFLAGS = --std=08 --ieee=synopsys -fexplicit

ROOT := ..
OUT := out
TB := tb_shellultra_sim

VHDL_SRC = \
	$(ROOT)/vhdl/ClockVGA13M.vhd \
	$(ROOT)/vhdl/MapperPET.vhd \
	$(ROOT)/vhdl/VideoVGACanvas54m.vhd \
	$(ROOT)/vhdl/VideoHBorder.vhd \
	$(ROOT)/vhdl/VideoVBorder.vhd \
	$(ROOT)/vhdl/Sprite.vhd \
	$(ROOT)/vhdl/palette_bram.vhd \
	$(ROOT)/vhdl/VideoColorVGA.vhd \
	$(ROOT)/vhdl/DAC.vhd \
	$(ROOT)/vhdl/SPI.vhd \
	$(ROOT)/vhdl/Top.vhd \
	$(ROOT)/vhdl/ShellUltra.vhd \
	vhdl/cpu65816_core.vhd \
	vhdl/spi_flash_model.vhd \
	vhdl/tb_shellultra_sim.vhd

.PHONY: all build run view clean

all: run

build:
	@mkdir -p $(OUT)
	$(GHDL) -a $(GHDLFLAGS) $(VHDL_SRC)
	$(GHDL) -e $(GHDLFLAGS) $(TB)

run: build
	@mkdir -p $(OUT)
	$(GHDL) -r $(GHDLFLAGS) $(TB) --stop-time=30ms --vcd=$(OUT)/sim.vcd
	@echo "Wrote $(OUT)/frame.ppm and $(OUT)/sim.vcd"

view:
	python3 show_frame.py $(OUT)/frame.ppm

clean:
	rm -f *.cf $(TB)
	rm -rf $(OUT)
