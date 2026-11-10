# Fixed 64-octet GMII traffic generator

`traffic_generator_64data_20gap_gmii` continuously repeats a fixed minimum-size
Ethernet frame. There are no parameters, CSRs, AXI signals, timestamps, or
runtime CRC calculation. A synchronous ROM contains the complete sequence;
GMII data, enable, and cycle_start have a separate fabric output register.
All state advances on `clk` rising edges; gmii_er is tied low.
At 125 MHz it supplies a 1 Gbit/s GMII interface.

| Port | Direction | Meaning |
|---|---|---|
| `clk` | Input | GMII byte clock, nominally 125 MHz |
| `resetn` | Input | Synchronous active-low reset |
| `gmii_d[7:0]` | Output | Transmit octet; zero while idle |
| `gmii_en` | Output | High for all 72 preamble/SFD/frame cycles |
| `gmii_er` | Output | Always zero |
| `cycle_start` | Output | One-cycle pulse with the first preamble byte |

One idle startup clock after reset release primes the synchronous ROM;
transmission starts on the second rising edge. Each
period is **84 clocks**, with no pauses between periods:

- Seven `55` preamble octets and one `d5` SFD octet.
- A 64-octet frame, measured from destination MAC through FCS.
- Twelve idle clocks, the minimum Ethernet interframe gap.

The **20** in the module name includes the eight preamble/SFD cycles plus
these twelve idle cycles; it does not mean twenty idle cycles.

The frame body matches [draft-ietf-bmwg-network-tester-cfg-17, Appendix A.2](https://datatracker.ietf.org/doc/html/draft-ietf-bmwg-network-tester-cfg-17#appendix-A.2):

- Destination MAC `6c:a9:6f:00:00:02`, source MAC `6c:a9:6f:00:00:01`.
- EtherType `0800` (IPv4); source `192.0.2.1`, destination `192.0.2.2`.
- UDP source port 49184, destination port 7; UDP checksum zero.
- Eighteen payload octets `01` through `12`.
- Precomputed Ethernet FCS `6e ec f3 05` in transmission order.

The exact 60-octet frame body, before FCS, is:

```text
6c a9 6f 00 00 02 6c a9 6f 00 00 01 08 00 45 00
00 2e d4 a5 00 00 0a 11 58 16 c0 00 02 01 c0 00
02 02 c0 20 00 07 00 1a 00 00 01 02 03 04 05 06
07 08 09 0a 0b 0c 0d 0e 0f 10 11 12
```

Reset during a frame aborts it and restarts with a fresh preamble after reset
is released.
There is no backpressure or enable input.

The ROM is declared as 128x10 bits to use a power-of-two address space;
84 entries form the sequence and unused entries are zero. Each entry holds
`{cycle_start, gmii_en, gmii_d}`; all twelve idle entries are zero. The
`ram_style="block"` attribute requests block RAM rather than LUT selection.
GateMate synthesis maps it to one `CC_BRAM_20K` (one RAM half-block).
A registered modulo-84 counter directly drives the RAM address, and the
synchronous read has no reset or combinational next-address logic. Its output
feeds the fabric GMII register, splitting address, RAM-read, and PCS paths.

Compile `hdl/traffic_generator_64data_20gap_gmii.v` by itself. The module uses
the existing generator's `clk`, `resetn`, and GMII output names, but has no
register or time interface. Existing LiteX build modes are unchanged.

Run tests from this directory:

```sh
python3 -m unittest discover -s sim -v
```
