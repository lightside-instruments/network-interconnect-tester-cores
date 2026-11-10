"""Shared traffic-core configuration for LiteX board targets."""

from migen import ClockSignal
from litex.build.io import DifferentialInput

from gateware.traffic_generator_gmii import traffic_generator_gmii
from gateware.traffic_analyzer_gmii import traffic_analyzer_gmii
from gateware.rtclock import rtclock
from gateware.pcs_1000basex_loopback import PCS1000BaseXLoopback


NETWORK_TESTER_MODES = ("gmii", "serial_loopback", "serial_external", "serdes", "serdes_tx", "serdes_dummy_pcs_tx", "serdes_64data_20gap_tx", "serdes_64data_20gap")


def _network_tester_rtclock_add(parent, platform, pcs):
    options = {}
    if pcs is not None and getattr(pcs, "time_source_domain", "sys") == "gmii_tx":
        options = dict(datapath_clk=pcs.tx_gmii_clk, datapath_reset=pcs.tx_reset)
    parent.rtclock = rtclock(platform, **options)


def network_tester_cores_add(parent, platform, instances=1, sys_clk_freq=None,
                             mode="serial_loopback", serial_pads=None, serdes_loopback=False,
                             serdes_refclk=None):
    """Attach numbered cores directly to parent, preserving CSR names/order.

    Instance 0 uses direct GMII, internal serial, or external serial wiring.
    External mode requires serial_pads.tx and serial_pads.rx; an optional
    serial_pads.signal_detect input can indicate incoming signal presence.
    serdes_tx and serdes_dummy_pcs_tx omit analyzers and SERDES receive logic.
    The dummy mode pads each byte with two zero bits instead of 8b/10b.
    Additional instances expose their interfaces for board-specific wiring.
    """
    if instances < 1:
        raise ValueError("At least one network tester instance is required")
    if mode not in NETWORK_TESTER_MODES:
        raise ValueError("Unknown network tester mode: {}".format(mode))
    if mode == "serial_external" and (serial_pads is None or
            not all(hasattr(serial_pads, name) for name in ("tx", "rx"))):
        raise ValueError("serial_external requires serial_pads with tx and rx signals")
    if serdes_loopback and mode != "serdes":
        raise ValueError("SERDES PMA loopback requires serdes mode")
    pcs = None
    if mode in ("serdes", "serdes_tx", "serdes_dummy_pcs_tx", "serdes_64data_20gap_tx", "serdes_64data_20gap"):
        device = getattr(platform, "device", "").upper()
        if device.startswith("CCGM1A"):
            from gateware.gatemate_1000basex import GateMate1000BaseX
            phy_class, phy_options = GateMate1000BaseX, {}
        elif device.startswith("LFE5UM"):
            from gateware.ecp5_1000basex import ECP51000BaseX
            phy_class, phy_options = ECP51000BaseX, dict(refclk=serdes_refclk)
        else:
            raise ValueError("Dedicated SERDES mode requires a GateMate or ECP5 UM platform")
        parent.pcs_1000basex_0 = pcs = phy_class(platform, loopback=serdes_loopback,
            tx_only=mode not in ("serdes", "serdes_64data_20gap"),
            dummy_pcs=mode == "serdes_dummy_pcs_tx",
            with_time=mode != "serdes_64data_20gap_tx", **phy_options)
    elif mode != "gmii":
        parent.pcs_1000basex_0 = pcs = PCS1000BaseXLoopback(
            platform, loopback=mode == "serial_loopback")
    parent.network_tester_tx_clk = pcs.tx_gmii_clk if pcs is not None else ClockSignal("sys")
    if mode in ("serdes_64data_20gap_tx", "serdes_64data_20gap"):
        from gateware.traffic_generator_64data_20gap_gmii import traffic_generator_64data_20gap_gmii
        parent.traffic_generator_64data_20gap_gmii_0 = generator = traffic_generator_64data_20gap_gmii(
            platform, datapath_clk=pcs.tx_gmii_clk, datapath_reset=pcs.tx_reset | ~pcs.ready)
        parent.comb += [pcs.tx_data.eq(generator.gmii_d), pcs.tx_en.eq(generator.gmii_en),
                        pcs.tx_er.eq(generator.gmii_er)]
        if mode == "serdes_64data_20gap_tx":
            parent.comb += pcs.control_overflow.eq(0)
            return
        parent.traffic_analyzer_gmii_0 = analyzer = traffic_analyzer_gmii(platform,
            instance_number=0, datapath_clk=pcs.rx_gmii_clk, datapath_reset=pcs.rx_reset,
            datapath_domain=pcs.rx_datapath_domain)
        _network_tester_rtclock_add(parent, platform, pcs)
        parent.comb += [
            analyzer.gmii_d.eq(pcs.rx_data), analyzer.gmii_en.eq(pcs.rx_dv),
            analyzer.gmii_er.eq(pcs.rx_er),
            pcs.control_overflow.eq(analyzer.control_cdc.overflow),
            pcs.time_sec.eq(parent.rtclock.sec), pcs.time_nsec.eq(parent.rtclock.nsec),
            analyzer.sec.eq(pcs.analyzer_sec), analyzer.nsec.eq(pcs.analyzer_nsec),
        ]
        return
    for i in range(instances):
        options = dict(datapath_clk=pcs.tx_gmii_clk, datapath_reset=pcs.tx_reset,
                       run_enable=pcs.ready, datapath_domain="gmii_tx") if i == 0 and pcs is not None else {}
        setattr(parent, "traffic_generator_gmii_{}".format(i),
                traffic_generator_gmii(platform, instance_number=i, **options))
    for i in range(0 if mode in ("serdes_tx", "serdes_dummy_pcs_tx") else instances):
        options = dict(datapath_clk=pcs.rx_gmii_clk, datapath_reset=pcs.rx_reset,
                       datapath_domain=getattr(pcs, "rx_datapath_domain", "gmii_rx")) if i == 0 and pcs is not None else {}
        setattr(parent, "traffic_analyzer_gmii_{}".format(i),
                traffic_analyzer_gmii(platform, instance_number=i, **options))
    if pcs is not None and mode not in ("serdes", "serdes_tx", "serdes_dummy_pcs_tx", "serdes_64data_20gap_tx", "serdes_64data_20gap") and sys_clk_freq is not None:
        platform.add_period_constraint(pcs.bit_clk, 4e9/sys_clk_freq)
        platform.add_period_constraint(pcs.tx_gmii_clk, 40e9/sys_clk_freq)
        platform.add_period_constraint(pcs.rx_gmii_clk, 40e9/sys_clk_freq)
    _network_tester_rtclock_add(parent, platform, pcs)
    generator = parent.traffic_generator_gmii_0
    if mode in ("serdes_tx", "serdes_dummy_pcs_tx"):
        parent.comb += [
            pcs.tx_data.eq(generator.gmii_d), pcs.tx_en.eq(generator.gmii_en),
            pcs.tx_er.eq(generator.gmii_er),
            pcs.control_overflow.eq(generator.control_cdc.overflow),
            pcs.time_sec.eq(parent.rtclock.sec), pcs.time_nsec.eq(parent.rtclock.nsec),
            generator.sec.eq(pcs.gen_sec), generator.nsec.eq(pcs.gen_nsec),
        ]
        return
    analyzer = parent.traffic_analyzer_gmii_0
    if pcs is None:
        parent.comb += [
            analyzer.gmii_d.eq(generator.gmii_d),
            analyzer.gmii_en.eq(generator.gmii_en),
            analyzer.gmii_er.eq(generator.gmii_er),
            generator.sec.eq(parent.rtclock.sec), generator.nsec.eq(parent.rtclock.nsec),
            analyzer.sec.eq(parent.rtclock.sec), analyzer.nsec.eq(parent.rtclock.nsec),
        ]
        return
    if mode == "serial_external":
        if hasattr(serial_pads.tx, "p"):
            # Complementary CMOS outputs retain the board's 3.3 V workaround.
            parent.comb += [serial_pads.tx.p.eq(pcs.serial_tx),
                            serial_pads.tx.n.eq(~pcs.serial_tx)]
        else:
            parent.comb += serial_pads.tx.eq(pcs.serial_tx)
        if hasattr(serial_pads.rx, "p") and getattr(serial_pads, "complementary_rx", False):
            # Digital complementary inputs, for banks without an LVDS receiver.
            parent.comb += pcs.serial_rx.eq(serial_pads.rx.p & ~serial_pads.rx.n)
        elif hasattr(serial_pads.rx, "p"):
            parent.specials += DifferentialInput(serial_pads.rx.p, serial_pads.rx.n, pcs.serial_rx)
        else:
            parent.comb += pcs.serial_rx.eq(serial_pads.rx)
        if hasattr(serial_pads, "signal_detect"):
            parent.comb += pcs.signal_detect.eq(serial_pads.signal_detect)
    parent.comb += [
        pcs.tx_data.eq(generator.gmii_d), pcs.tx_en.eq(generator.gmii_en), pcs.tx_er.eq(generator.gmii_er),
        analyzer.gmii_d.eq(pcs.rx_data), analyzer.gmii_en.eq(pcs.rx_dv), analyzer.gmii_er.eq(pcs.rx_er),
        pcs.control_overflow.eq(generator.control_cdc.overflow | analyzer.control_cdc.overflow),
        pcs.time_sec.eq(parent.rtclock.sec), pcs.time_nsec.eq(parent.rtclock.nsec),
        generator.sec.eq(pcs.gen_sec), generator.nsec.eq(pcs.gen_nsec),
        analyzer.sec.eq(pcs.analyzer_sec), analyzer.nsec.eq(pcs.analyzer_nsec),
    ]


def network_tester_cores_configure_csrs(kwargs):
    """Ensure all four register sets fit even with an 8-bit CSR bus."""
    kwargs["csr_paging"] = max(kwargs.get("csr_paging", 0x800), 0x1000)


def network_tester_cores_add_arguments(parser, with_serdes=False):
    """Common board CLI options; pin names use the platform Pins syntax."""
    parser.add_target_argument("--network-tester-mode",
                               choices=NETWORK_TESTER_MODES if with_serdes else tuple(m for m in NETWORK_TESTER_MODES if not m.startswith("serdes")),
                               default="serial_loopback")
    if with_serdes:
        parser.add_target_argument("--network-tester-serdes-loopback", action="store_true",
                                   help="Use dedicated SERDES near-end PMA loopback (serdes mode)")
    parser.add_target_argument("--network-tester-serial-tx-pin")
    parser.add_target_argument("--network-tester-serial-rx-pin")
    parser.add_target_argument("--network-tester-serial-io-standard", default="LVCMOS33")


def network_tester_cores_options(platform, kwargs, default_serial_resource=None):
    """Consume board options before passing remaining kwargs to SoCCore."""
    mode = kwargs.pop("network_tester_mode", "serial_loopback")
    loopback = kwargs.pop("network_tester_serdes_loopback", False)
    tx = kwargs.pop("network_tester_serial_tx_pin", None)
    rx = kwargs.pop("network_tester_serial_rx_pin", None)
    io = kwargs.pop("network_tester_serial_io_standard", "LVCMOS33")
    if mode not in NETWORK_TESTER_MODES:
        raise ValueError("Unknown network tester mode: {}".format(mode))
    if mode in ("serdes", "serdes_tx", "serdes_dummy_pcs_tx", "serdes_64data_20gap_tx", "serdes_64data_20gap"):
        if not getattr(platform, "device", "").upper().startswith(("CCGM1A", "LFE5UM")):
            raise ValueError("Dedicated SERDES mode requires a GateMate or ECP5 UM platform")
        if tx is not None or rx is not None:
            raise ValueError("serdes mode uses dedicated pins, not serial GPIO pin options")
        if loopback and mode != "serdes":
            raise ValueError("SERDES PMA loopback requires serdes mode")
        return dict(mode=mode, serdes_loopback=loopback)
    if loopback:
        raise ValueError("SERDES PMA loopback requires serdes mode")
    if mode != "serial_external":
        if tx is not None or rx is not None:
            raise ValueError("Serial pin options require serial_external mode")
        return dict(mode=mode)
    if tx is None and rx is None and default_serial_resource is not None:
        from types import SimpleNamespace
        pads = platform.request(default_serial_resource)
        if hasattr(pads, "tx0_p"):
            pads = SimpleNamespace(tx=SimpleNamespace(p=pads.tx0_p, n=pads.tx0_n),
                                   rx=SimpleNamespace(p=pads.rx0_p, n=pads.rx0_n),
                                   complementary_rx=True)
        return dict(mode=mode, serial_pads=pads)
    if not tx or not rx or tx == rx:
        raise ValueError("serial_external requires distinct TX and RX pins")
    from litex.build.generic_platform import Pins, Subsignal, IOStandard
    platform.add_extension([("network_tester_serial_custom", 0,
        Subsignal("tx", Pins(tx)), Subsignal("rx", Pins(rx)), IOStandard(io))])
    return dict(mode=mode, serial_pads=platform.request("network_tester_serial_custom"))
