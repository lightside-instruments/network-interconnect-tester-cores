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


def add_liteeth_dts(dts, csr):
    # The fabric PCS has no MDIO bus. The Linux driver uses the MAC and buffer.
    address = csr["csr_bases"]["ethmac"]
    memory = csr["memories"]["ethmac"]
    link = csr["csr_registers"]["ethphy_link"]["addr"]
    constants = csr["constants"]
    return dts + f"""
&{{/chosen}} {{
    bootargs = "console=liteuart earlycon=liteuart,0xf0001000 rootwait root=/dev/mmcblk0p2 net.ifnames=0";
}};

&{{/soc}} {{
    ethernet@{address:x} {{
        compatible = "litex,liteeth";
        reg = <0x{address:x} 0x7c>, <0x{memory["base"]:x} 0x{memory["size"]:x}>,
              <0x{link:x} 0x4>;
        reg-names = "mac", "buffer", "link";
        interrupts = <{constants["ethmac_interrupt"]}>;
        litex,rx-slots = <{constants["ethmac_rx_slots"]}>;
        litex,tx-slots = <{constants["ethmac_tx_slots"]}>;
        litex,slot-size = <{constants["ethmac_slot_size"]}>;
        status = "okay";
    }};
}};
"""


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
                               help="Share external serial GPIO between Debian Ethernet and the tester")
    network_tester_cores_add_arguments(parser)
    parser.set_defaults(network_tester_mode="serial_external")
    args = parser.parse_args()
    if args.cpu_type != "vexiiriscv" or args.cpu_variant != "debian":
        parser.error("This target requires --cpu-type vexiiriscv --cpu-variant debian")
    if args.integrated_main_ram_size:
        parser.error("Use external DDR3; integrated main RAM must remain disabled")
    network_options = {}
    shared_gmii = args.with_network_tester and args.network_tester_mode == "serial_external"
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
                **({"ethmac": 9, "ethphy": 10} if shared_gmii else {}),
            }

        network_options = dict(
            shared_gmii=shared_gmii,
            network_tester_mode=args.network_tester_mode,
            network_tester_serial_tx_pin=args.network_tester_serial_tx_pin,
            network_tester_serial_rx_pin=args.network_tester_serial_rx_pin,
            network_tester_serial_io_standard=args.network_tester_serial_io_standard)
    soc = BaseSoC(revision="0.2", device="85F", sdram_device="MT41K64M16",
                  sys_clk_freq=args.sys_clk_freq, toolchain=args.toolchain,
                  **network_options, **parser.soc_argdict)
    soc.add_sdcard()
    if shared_gmii:
        from gateware.gmii_mux import GMIIMux

        crg = soc.crg
        soc.ethphy = GMIIMux(soc.platform, crg.pcs_1000basex_0,
                            crg.traffic_generator_gmii_0, crg.traffic_analyzer_gmii_0)
        soc.add_ethernet(phy=soc.ethphy, phy_cd="gmii", with_timing_constraints=False)
    builder = Builder(soc, **parser.builder_argdict)
    if args.build:
        builder.build(**parser.toolchain_argdict)
        csr_json = Path(builder.output_dir)/"csr.json"
        # An SD-root kernel must have its storage and root-filesystem drivers
        # built in. Firmware/kernel/rootfs are supplied separately.
        csr = json.loads(csr_json.read_text())
        # The stock DTS generator assumes any ethphy CSR bank provides MDIO.
        dts_csr = {**csr, "csr_bases": {name: address for name, address in csr["csr_bases"].items()
                                      if not shared_gmii or name != "ethphy"}}
        dts = generate_dts(dts_csr, initrd="disabled", root_device="mmcblk0p2")
        if shared_gmii:
            dts = add_liteeth_dts(dts, csr)
        (Path(builder.output_dir)/"orangecrab-debian.dts").write_text(dts)
    if args.load:
        soc.platform.create_programmer().load_bitstream(
            builder.get_bitstream_filename(mode="sram"))


if __name__ == "__main__":
    main()
