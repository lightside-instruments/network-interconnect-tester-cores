#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# See the project-root COPYRIGHT for attribution and license terms.
"""OrangeCrab 85F/128 MiB RV64 Linux with optional network tester cores."""

import json
from pathlib import Path

from litex_boards.targets.gsd_orangecrab import BaseSoC as DebianSoC
from litex.build.parser import LiteXArgumentParser
from litex.soc.integration.builder import Builder
from litex.tools.litex_json2dts_linux import generate_dts
from litex_boards.platforms import gsd_orangecrab
from gateware.network_tester_cores import network_tester_cores_add_arguments


def main():
    parser = LiteXArgumentParser(
        platform=gsd_orangecrab.Platform,
        description="OrangeCrab 85F/128 MiB Debian RV64 bring-up.")
    parser.set_defaults(cpu_type="vexiiriscv", cpu_variant="debian",
                        with_dma=True,
                        integrated_rom_size=0x20000,
                        integrated_sram_size=0x4000)
    parser.add_target_argument("--sys-clk-freq", type=float, default=40e6)
    parser.add_target_argument("--with-network-tester", action="store_true",
                               help="Add CSR-configurable traffic generator, analyzer and PCS")
    network_tester_cores_add_arguments(parser)
    args = parser.parse_args()
    if args.cpu_type != "vexiiriscv" or args.cpu_variant != "debian":
        parser.error("This target requires --cpu-type vexiiriscv --cpu-variant debian")
    if args.integrated_main_ram_size:
        parser.error("Use external DDR3; integrated main RAM must remain disabled")
    network_options = {}
    BaseSoC = DebianSoC
    if args.with_network_tester:
        from boards.targets.gsd_orangecrab import BaseSoC as NetworkTesterSoC

        if args.csr_paging != 0x800:
            parser.error("The Debian network tester requires 0x800-byte CSR pages")

        class BaseSoC(NetworkTesterSoC):
            network_tester_expand_csr_paging = False
            # Keep the Debian peripheral banks at their original addresses.
            # VexiiRiscv reserves UART and timer0 at slots 2 and 3.
            csr_map = {
                "ctrl": 0,
                "ddrphy": 1,
                "identifier_mem": 4,
                "leds": 5,
                "sdcard": 6,
                "sdram": 7,
                "crg": 8,
            }

        network_options = dict(
            network_tester_mode=args.network_tester_mode,
            network_tester_serial_tx_pin=args.network_tester_serial_tx_pin,
            network_tester_serial_rx_pin=args.network_tester_serial_rx_pin,
            network_tester_serial_io_standard=args.network_tester_serial_io_standard)
    soc = BaseSoC(revision="0.2", device="85F", sdram_device="MT41K64M16",
                  sys_clk_freq=args.sys_clk_freq, toolchain=args.toolchain,
                  **network_options, **parser.soc_argdict)
    soc.add_sdcard()
    builder = Builder(soc, **parser.builder_argdict)
    if args.build:
        builder.build(**parser.toolchain_argdict)
        csr_json = Path(builder.output_dir)/"csr.json"
        # An SD-root kernel must have its storage and root-filesystem drivers
        # built in. Firmware/kernel/rootfs are supplied separately.
        dts = generate_dts(json.loads(csr_json.read_text()),
                           initrd="disabled", root_device="mmcblk0p2")
        (Path(builder.output_dir)/"orangecrab-debian.dts").write_text(dts)
    if args.load:
        soc.platform.create_programmer().load_bitstream(
            builder.get_bitstream_filename(mode="sram"))


if __name__ == "__main__":
    main()
