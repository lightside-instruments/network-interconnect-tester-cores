# SPDX-License-Identifier: BSD-2-Clause
"""Select the fabric PCS transmitter and share ingress with both consumers."""

from pathlib import Path

from migen import If, Instance, Signal
from migen.genlib.cdc import MultiReg
from liteeth.common import eth_phy_description
from litex.gen import LiteXModule
from litex.soc.interconnect import stream
from litex.soc.interconnect.csr import CSRStatus, CSRStorage


class GMIIMux(LiteXModule):
    dw = 8

    def __init__(self, platform, pcs, generator, analyzer):
        self.select = CSRStorage(1, description="TX source: 0 selects LiteEth, 1 selects the traffic generator.")
        self.link = CSRStatus(2, description="Bit 0: RX clock locked. Bit 1: RX 8b/10b synchronized.")
        self.specials += [
            MultiReg(pcs.cdr_locked, self.link.status[0], "sys"),
            MultiReg(pcs.pcs_synced, self.link.status[1], "sys"),
        ]
        self.sink = sink = stream.Endpoint(eth_phy_description(self.dw))
        self.source = source = stream.Endpoint(eth_phy_description(self.dw))

        tx_request, tx_tester = Signal(), Signal()
        self.specials += MultiReg(self.select.storage, tx_request, "gmii_tx")
        mac_tx = Signal()
        self.sync.gmii_tx += If(~pcs.tx_en & ~mac_tx & ~(tx_tester & generator.gmii_en),
                               tx_tester.eq(tx_request))
        self.comb += [
            mac_tx.eq(sink.valid & sink.ready),
            sink.ready.eq(~tx_tester & pcs.ready),
            analyzer.gmii_d.eq(pcs.rx_data),
            analyzer.gmii_en.eq(pcs.rx_dv),
            analyzer.gmii_er.eq(pcs.rx_er),
        ]

        rtl = Path(__file__).resolve().parents[3] / "lib/hw/lsi/cores/gmii_mux/hdl"
        platform.add_verilog_include_path(str(rtl))
        platform.add_source(str(rtl / "gmii_mux.v"))
        ports = {
            "i_gmii_in_0_txd": sink.data,
            "i_gmii_in_0_tx_en": mac_tx,
            "i_gmii_in_0_tx_er": mac_tx & sink.error[0],
            "i_gmii_in_1_txd": generator.gmii_d,
            "i_gmii_in_1_tx_en": generator.gmii_en,
            "i_gmii_in_1_tx_er": generator.gmii_er,
        }
        for index in range(2, 6):
            for suffix in ("txd", "tx_en", "tx_er"):
                ports[f"i_gmii_in_{index}_{suffix}"] = 0
        self.specials += Instance("gmii_mux", p_C_NUM_INPUTS=2, p_C_USE_EXTERNAL_SELECT=1,
            i_gtx_clk=pcs.tx_gmii_clk, i_external_select=tx_tester,
            o_gmii_out_txd=pcs.tx_data, o_gmii_out_tx_en=pcs.tx_en,
            o_gmii_out_tx_er=pcs.tx_er, **ports)

        # GMII supplies one byte per cycle and indicates end of frame when DV
        # falls. Delay the byte so LiteEth sees last on that final valid beat.
        rx_error = Signal()
        self.sync.gmii_rx += [
            source.valid.eq(pcs.rx_dv),
            source.data.eq(pcs.rx_data),
            rx_error.eq(pcs.rx_er),
        ]
        self.comb += [
            source.last.eq(source.valid & ~pcs.rx_dv),
            source.last_be.eq(source.last),
            source.error.eq(rx_error | (source.last & pcs.rx_er)),
        ]
