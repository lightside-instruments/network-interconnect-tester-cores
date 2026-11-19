# ice4pi GMII serial example

This example exchanges Ethernet frames with the OrangeCrab Debian GPIO
link using the same 8b/10b PCS. GMII runs at 1 MHz and the serial link at
10 Mbit/s. The iCE40HX1K-TQ144 derives a 40 MHz receiver sampling clock
from the onboard 12 MHz oscillator.

The generator sends the RFC 2544 example frame about once per second.
The analyzer checks the preamble and FCS. D1 toggles on transmit, D2
toggles on accepted receive, D3 stays lit after the first accepted frame,
D4 stays lit after an error, and D5 shows receiver clock lock and PCS
sync. [IETF draft example](https://datatracker.ietf.org/doc/html/draft-ietf-bmwg-network-tester-cfg-17#appendix-A.2)

Run `make` with Yosys, nextpnr-ice40 with Python support, and IceStorm
on your PATH. The output is `build/ice4pi-serial.bin`. Use it in place of
`rot.bin` in the ice4pi programming procedure.
[ice4pi board and programming guide](https://www.hackster.io/lightside-instruments/the-ice4pi-ice40-raspberry-pi-hat-b24c2f)

Cross-connect the two boards. Connect ground and leave the power pins
unconnected. Each data wire is a 3.3 V CMOS signal.

| ice4pi PMOD signal | ice4pi FPGA pin | OrangeCrab header |
| --- | ---: | --- |
| P1, TX+ | 78 | GPIO 10, RX+ |
| P2, TX− | 79 | GPIO 9, RX− |
| P3, RX+ | 80 | GPIO 0, TX+ |
| P4, RX− | 81 | GPIO 1, TX− |
| GND | | GND |

## Raspberry Pi SPI registers

The design exposes a byte register map on SPI0 CE1
(`/dev/spidev0.1`). Use SPI mode 0, MSB first, at 500 kHz. Keep CE1 low
for a single two-byte transfer. Byte one is the register address, with
bit 7 set for writes. Byte two carries the write value or clocks out the
read value. The FPGA releases MISO when CE1 is high so CE0 can be used
for the configuration flash.

| Address | Access | Register |
| --- | --- | --- |
| `0x00` | R/W | Generator enable, bit 0, reset to 1 |
| `0x01` | R | Transmitted frame count, low eight bits |
| `0x10` | R/W | Analyzer enable, bit 0, reset to 1 |
| `0x11` | R | Accepted frame count, low eight bits |
| `0x12` | R | CRC or frame error count, low eight bits |
| `0x13` | R | Preamble error count, low eight bits |
| `0x14` | R | Receiver clock lock and PCS sync, bit 0 |

For example, with Python's `spidev` module on the Pi:

```python
import spidev

spi = spidev.SpiDev()
spi.open(0, 1)
try:
    spi.mode = 0
    spi.max_speed_hz = 500000
    print("TX count:", spi.xfer2([0x01, 0x00])[1])
    print("RX count:", spi.xfer2([0x11, 0x00])[1])
    spi.xfer2([0x80, 0x00])  # Stop the generator
    spi.xfer2([0x80, 0x01])  # Resume the generator
finally:
    spi.close()
```

The generator applies its enable at the next frame-period boundary. The
analyzer stops counting when disabled and retains its counts. The frame
contents and interval are fixed.
