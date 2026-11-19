CORES := ../../lib/hw/lsi/cores
RTL := serial.v spi_regs.v $(CORES)/common/hdl/ethernet_crc_8.v \
       $(wildcard $(CORES)/pcs_1000basex_tx/hdl/*.v $(CORES)/pcs_1000basex_rx/hdl/*.v)

build/ice4pi-serial.bin: $(RTL) draft-frame.vh serial.pcf serial-timing.py Makefile
	mkdir -p build
	yosys -Q -p 'read_verilog $(RTL); synth_ice40 -top serial_top -json build/serial.json'
	nextpnr-ice40 --hx1k --package tq144 --freq 40 --pre-pack serial-timing.py \
		--pcf serial.pcf --json build/serial.json --asc build/serial.asc
	icepack build/serial.asc $@
