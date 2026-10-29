"""1000BASE-X serial path with clocks scaled from the existing sys clock."""

import os

from migen import *
from migen.genlib.cdc import MultiReg
from litex.gen import LiteXModule


class PCS1000BaseXLoopback(LiteXModule):
    """sys=bit_clk_x4, bit_clk=sys/4, and GMII clocks approximately sys/40.

    The PCS/CDR logic is unchanged; only its supplied clock frequencies are
    scaled. MAC datapaths use generated clocks, while their CSRs stay on sys.
    """
    def __init__(self, platform, loopback=True):
        self.bit_clk_x4 = Signal()
        self.bit_clk = Signal()
        self.tx_gmii_clk = Signal()
        self.rx_gmii_clk = Signal()
        self.tx0 = self.serial_tx = Signal(name="tx0")
        self.rx0 = self.serial_rx = Signal(name="rx0")
        self.signal_detect = Signal(reset=1)
        if loopback:
            self.comb += self.serial_rx.eq(self.serial_tx)
        self.tx_data = Signal(8)
        self.tx_en = Signal()
        self.tx_er = Signal()
        self.rx_data = Signal(8)
        self.rx_dv = Signal()
        self.rx_er = Signal()
        self.cdr_locked = Signal()
        self.pcs_synced = Signal()
        self.ready = Signal()
        self.tx_error = Signal()
        self.control_overflow = Signal()
        self.rx_code_error = Signal()
        self.rx_disparity_error = Signal()
        self.rx_overflow = Signal()
        self.rx_abort = Signal()
        self.tx_reset = Signal()
        self.rx_reset = Signal()
        self.gen_sec = Signal(48)
        self.gen_nsec = Signal(30)
        self.analyzer_sec = Signal(48)
        self.analyzer_nsec = Signal(30)
        self.time_sec = Signal(48)
        self.time_nsec = Signal(30)

        divider = Signal(2)
        self.sync += divider.eq(divider+1)
        self.comb += [self.bit_clk_x4.eq(ClockSignal("sys")), self.bit_clk.eq(divider[1])]
        self.cd_pcs_bit = ClockDomain("pcs_bit")
        self.cd_gmii_tx = ClockDomain("gmii_tx")
        self.cd_gmii_rx = ClockDomain("gmii_rx")
        self.comb += [
            self.cd_pcs_bit.clk.eq(self.bit_clk),
            self.cd_gmii_tx.clk.eq(self.tx_gmii_clk),
            self.cd_gmii_rx.clk.eq(self.rx_gmii_clk),
            self.tx_reset.eq(self.cd_gmii_tx.rst),
            self.rx_reset.eq(self.cd_gmii_rx.rst),
        ]
        # Async assertion is necessary because the generated clocks stop on
        # reset/loss of sync. Deassertion is synchronized in each clock domain.
        for name, cd, reset in (
            ("bit", self.cd_pcs_bit, ResetSignal("sys")),
            ("gmii_tx", self.cd_gmii_tx, ResetSignal("sys")),
            ("gmii_rx", self.cd_gmii_rx,
             ResetSignal("sys") | ~self.cdr_locked | ~self.pcs_synced),
        ):
            self.specials += Instance("network_tester_reset_sync", name="reset_sync_"+name,
                i_clk=cd.clk, i_async_reset=reset, o_reset=cd.rst)

        ready_tx = Signal()
        if loopback:
            self.specials += MultiReg(self.cdr_locked & self.pcs_synced, ready_tx, "gmii_tx")
        else:
            # External TX must run even when no incoming link is present.
            self.comb += ready_tx.eq(1)
        settle = Signal(4)
        self.sync.gmii_tx += If(~ready_tx, settle.eq(0)).Elif(settle != 15, settle.eq(settle+1))
        # Internal loopback waits for RX; external mode only waits for local
        # TX reset to settle. Software start requests are retained.
        self.comb += self.ready.eq(settle == 15)

        # Capture the common time bus on each GMII falling edge (detected in
        # sys). The snapshot is stable well before the following rising edge.
        tx_last = Signal()
        rx_last = Signal()
        self.sync += [
            tx_last.eq(self.tx_gmii_clk), rx_last.eq(self.rx_gmii_clk),
            If(tx_last & ~self.tx_gmii_clk,
                self.gen_sec.eq(self.time_sec), self.gen_nsec.eq(self.time_nsec)),
            If(rx_last & ~self.rx_gmii_clk,
                self.analyzer_sec.eq(self.time_sec), self.analyzer_nsec.eq(self.time_nsec)),
        ]
        self.specials += Instance("gmii_to_1000basex", name="gmii_to_1000basex_0",
            i_bit_clk=self.bit_clk, i_rst=self.cd_pcs_bit.rst, o_gmii_tx_clk=self.tx_gmii_clk,
            i_gmii_txd=self.tx_data, i_gmii_tx_en=self.tx_en, i_gmii_tx_er=self.tx_er,
            i_config_enable=0, i_config_word=0, o_serial_tx=self.serial_tx,
            o_protocol_error=self.tx_error,
        )
        self.specials += Instance("basex1000_to_gmii", name="basex1000_to_gmii_0",
            p_OVERSAMPLE=4,
            i_sample_clk=self.bit_clk_x4, i_rst=ResetSignal("sys"),
            i_serial_rx=self.serial_rx, i_signal_detect=self.signal_detect,
            o_gmii_rx_clk=self.rx_gmii_clk, o_gmii_rxd=self.rx_data,
            o_gmii_rx_dv=self.rx_dv, o_gmii_rx_er=self.rx_er,
            o_cdr_locked=self.cdr_locked, o_pcs_synced=self.pcs_synced,
            o_code_error=self.rx_code_error, o_disparity_error=self.rx_disparity_error,
            o_overflow=self.rx_overflow, o_rx_abort=self.rx_abort,
        )
        gateware_dir = os.path.dirname(__file__)
        platform.add_source(os.path.join(gateware_dir, "network_tester_reset_sync.v"))
        cores_dir = os.path.abspath(os.path.join(gateware_dir, "../../../lib/hw/lsi/cores"))
        for core in ("pcs_1000basex_tx", "pcs_1000basex_rx"):
            hdl_dir = os.path.join(cores_dir, core, "hdl")
            for source in sorted(os.listdir(hdl_dir)):
                if source.endswith(".v"):
                    platform.add_source(os.path.join(hdl_dir, source))
