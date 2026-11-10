#!/usr/bin/env python3

#
# This file is part of LiteX-Boards.
#
# SPDX-License-Identifier: BSD-2-Clause
# See the project-root COPYRIGHT for attribution and license terms.

from migen import *
from migen.genlib.resetsync import AsyncResetSynchronizer

from litex.gen import *
from litex.build.generic_platform import Pins, IOStandard, Misc
from litex.build.io import DifferentialOutput

from litex_boards.platforms import lattice_versa_ecp5

from litex.soc.cores.clock import *
from litex.soc.integration.soc_core import *
from litex.soc.integration.builder import *
from litex.soc.cores.led import LedChaser

from litedram.modules import MT41K64M16
from litedram.phy import ECP5DDRPHY

from liteeth.phy.ecp5rgmii import LiteEthPHYRGMII

from gateware.network_tester_cores import (network_tester_cores_add, network_tester_cores_configure_csrs,
    network_tester_cores_add_arguments, network_tester_cores_options)

# CRG ----------------------------------------------------------------------------------------------

class _CRG(LiteXModule):
    def __init__(self, platform, sys_clk_freq, network_tester_options=None):
        self.rst        = Signal()
        self.cd_init    = ClockDomain()
        self.cd_por     = ClockDomain()
        self.cd_sys     = ClockDomain()
        self.cd_sys2x   = ClockDomain()
        self.cd_sys2x_i = ClockDomain()

        # # #

        self.stop  = Signal()
        self.reset = Signal()

        # Clk / Rst
        clk100 = platform.request("clk100")
        rst_n  = platform.request("rst_n")

        # Power on reset
        por_count = Signal(16, reset=2**16-1)
        por_done  = Signal()
        self.comb += self.cd_por.clk.eq(clk100)
        self.comb += por_done.eq(por_count == 0)
        self.sync.por += If(~por_done, por_count.eq(por_count - 1))

        # PLL
        self.pll = pll = ECP5PLL()
        self.comb += pll.reset.eq(~por_done | ~rst_n | self.rst)
        pll.register_clkin(clk100, 100e6)
        pll.create_clkout(self.cd_sys2x_i, 2*sys_clk_freq)
        pll.create_clkout(self.cd_init, 25e6)
        self.specials += [
            Instance("ECLKSYNCB",
                i_ECLKI = self.cd_sys2x_i.clk,
                i_STOP  = self.stop,
                o_ECLKO = self.cd_sys2x.clk),
            Instance("CLKDIVF",
                p_DIV     = "2.0",
                i_ALIGNWD = 0,
                i_CLKI    = self.cd_sys2x.clk,
                i_RST     = self.reset,
                o_CDIVX   = self.cd_sys.clk),
            AsyncResetSynchronizer(self.cd_sys, ~pll.locked | self.reset),
        ]
        network_tester_options = dict(network_tester_options or {})
        if network_tester_options.get("mode", "").startswith("serdes"):
            self.cd_serdes_ref = ClockDomain("serdes_ref")
            pll.create_clkout(self.cd_serdes_ref, 125e6)
            platform.add_period_constraint(self.cd_serdes_ref.clk, 8.0)
            network_tester_options["serdes_refclk"] = self.cd_serdes_ref.clk
        network_tester_cores_add(self, platform, instances=1, sys_clk_freq=sys_clk_freq,
                                  **(network_tester_options or {}))


# BaseSoC ------------------------------------------------------------------------------------------

class BaseSoC(SoCCore):
    def __init__(self, sys_clk_freq=75e6, device="LFE5UM5G", toolchain="trellis",
        with_ethernet   = False,
        with_etherbone  = False,
        with_led_chaser = True,
        eth_ip          = "192.168.1.50",
        remote_ip       = None,
        eth_dynamic_ip  = False,
        eth_phy         = 0,
        **kwargs):
        platform = lattice_versa_ecp5.Platform(toolchain=toolchain, device=device)

        network_tester_options = network_tester_cores_options(platform, kwargs)

        # CRG --------------------------------------------------------------------------------------
        self.crg = _CRG(platform, sys_clk_freq, network_tester_options=network_tester_options)

        # SoCCore -----------------------------------------_----------------------------------------
        network_tester_cores_configure_csrs(kwargs)
        SoCCore.__init__(self, platform, sys_clk_freq, ident="LiteX SoC on Versa ECP5", **kwargs)

        if network_tester_options.get("mode", "").startswith("serdes"):
            from gateware.ecp5_1000basex import ECP5SerdesStatus
            self.serdes = ECP5SerdesStatus(self.crg.pcs_1000basex_0, self.crg.pll.locked)

        # Generator monitor outputs on adjacent 3.3 V differential pairs.
        generator = getattr(self.crg, "traffic_generator_64data_20gap_gmii_0", None)
        if generator is None:
            generator = getattr(self.crg, "traffic_generator_gmii_0", None)
        if generator is not None:
            for name, signal, pin_p in (
                ("cycle_start", generator.cycle_start, "X3:7"),
                ("gmii_en", generator.gmii_en, "X3:9"),
            ):
                platform.add_extension([(name + "_p", 0, Pins(pin_p),
                    IOStandard("LVCMOS33D"),
                    Misc("DRIVE=12"),
                    Misc("SLEWRATE=FAST"))])
                # Trellis configures both pads from the A-pad constraint:
                # E6/PT6A -> D6/PT6B (X3:8), E7/PT9A -> D7/PT9B (X3:10).
                # Do not create a separate top-level B-pad output buffer.
                pad_p = platform.request(name + "_p")
                self.specials += DifferentialOutput(signal, pad_p, Signal())

        # DDR3 SDRAM -------------------------------------------------------------------------------
        if not self.integrated_main_ram_size:
            self.ddrphy = ECP5DDRPHY(
                platform.request("ddram"),
                sys_clk_freq=sys_clk_freq)
            self.comb += self.crg.stop.eq(self.ddrphy.init.stop)
            self.comb += self.crg.reset.eq(self.ddrphy.init.reset)
            self.add_sdram("sdram",
                phy           = self.ddrphy,
                module        = MT41K64M16(sys_clk_freq, "1:2"),
                l2_cache_size = kwargs.get("l2_size", 8192)
            )

        # Ethernet / Etherbone ---------------------------------------------------------------------
        if with_ethernet or with_etherbone:
            self.ethphy = LiteEthPHYRGMII(
                clock_pads = self.platform.request("eth_clocks", eth_phy),
                pads       = self.platform.request("eth", eth_phy),
                tx_delay   = 0e-9,
                rx_delay   = 0e-9)
            if with_etherbone:
                self.add_etherbone(phy=self.ethphy, ip_address=eth_ip, with_ethmac=with_ethernet)
            if with_ethernet:
                self.add_ethernet(phy=self.ethphy, dynamic_ip=eth_dynamic_ip, local_ip=eth_ip, remote_ip=remote_ip)

        # Leds -------------------------------------------------------------------------------------
        if with_led_chaser:
            self.leds = LedChaser(
                pads         = platform.request_all("user_led"),
                sys_clk_freq = sys_clk_freq)

        # platform.add_source_dir(path="./gateware/traffic_generator_gmii")
# Build --------------------------------------------------------------------------------------------

def main():
    from litex.build.parser import LiteXArgumentParser
    parser = LiteXArgumentParser(platform=lattice_versa_ecp5.Platform, description="LiteX SoC on Versa ECP5.")
    parser.add_target_argument("--sys-clk-freq",    default=75e6, type=float, help="System clock frequency.")
    parser.add_target_argument("--device",          default="LFE5UM5G",       help="FPGA device (LFE5UM5G or LFE5UM).")
    ethopts = parser.target_group.add_mutually_exclusive_group()
    ethopts.add_argument("--with-ethernet",  action="store_true", help="Enable Ethernet support.")
    ethopts.add_argument("--with-etherbone", action="store_true", help="Enable Etherbone support.")
    parser.add_target_argument("--eth-ip",   default="192.168.1.50", help="Ethernet/Etherbone IP address.")
    parser.add_target_argument("--eth-dynamic-ip", action="store_true",      help="Enable dynamic Ethernet IP addresses setting.")
    parser.add_target_argument("--remote-ip",      default="192.168.1.100",  help="Remote IP address of TFTP server.")
    parser.add_target_argument("--eth-phy",  default=0, type=int,    help="Ethernet PHY (0 or 1).")
    network_tester_cores_add_arguments(parser, with_serdes=True)
    args = parser.parse_args()

    soc = BaseSoC(
        sys_clk_freq   = args.sys_clk_freq,
        device         = args.device,
        with_ethernet  = args.with_ethernet,
        with_etherbone = args.with_etherbone,
        eth_ip         = args.eth_ip,
        eth_dynamic_ip = args.eth_dynamic_ip,
        remote_ip      = args.remote_ip,
        eth_phy        = args.eth_phy,
        toolchain      = args.toolchain,
        network_tester_mode = args.network_tester_mode,
        network_tester_serdes_loopback = args.network_tester_serdes_loopback,
        network_tester_serial_tx_pin = args.network_tester_serial_tx_pin,
        network_tester_serial_rx_pin = args.network_tester_serial_rx_pin,
        network_tester_serial_io_standard = args.network_tester_serial_io_standard,
        **parser.soc_argdict
    )
    builder = Builder(soc, **parser.builder_argdict)
    if args.build:
        builder.build(**parser.toolchain_argdict)

    if args.load:
        prog = soc.platform.create_programmer()
        prog.load_bitstream(builder.get_bitstream_filename(mode="sram", ext=".svf")) # FIXME

if __name__ == "__main__":
    main()
