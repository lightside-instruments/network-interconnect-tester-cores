#!/usr/bin/env python3

import os

from migen import *
from litex.gen import LiteXModule
from litex.soc.interconnect.csr import CSR, CSRStorage, CSRStatus


class _ReadbackStorage(CSRStorage):
    """Writable CSR whose reads return the core's live register value."""
    def __init__(self, size, **kwargs):
        super().__init__(size, **kwargs)
        self.readback = Signal(size)

    def do_finalize(self, busword, ordering):
        nwords = (self.size + busword - 1) // busword
        indices = reversed(range(nwords)) if ordering == "big" else range(nwords)
        for i in indices:
            lo = i * busword
            hi = min(lo + busword, self.size)
            sc = CSR(hi - lo, name=self.name + str(i))
            self.simple_csrs.append(sc)
            self.comb += sc.w.eq(self.readback[lo:hi])
            self.sync += If(sc.re, self.storage[lo:hi].eq(sc.r))
        self.sync += self.re.eq(sc.re)


class traffic_generator_gmii(LiteXModule):
    """Expose the generator's registers as ordinary LiteX CSRs.

    The native register connection shares the core's datapath register signals
    with its AXI implementation, without variable-latency AXI transactions.
    """
    def __init__(self, platform, instance_number=0):
        self.id = CSRStatus(32, name="id")
        self.version = CSRStatus(32, name="version")
        self.flip = _ReadbackStorage(32, name="flip",
            description="Reads return the bitwise inverse of the written value.")
        self.control = CSRStorage(32, name="control")
        self.interframe_gap = CSRStorage(32, reset=12, name="interframe_gap")
        self.interburst_gap = CSRStorage(32, reset=12, name="interburst_gap")
        self.frames_per_burst = CSRStorage(32, name="frames_per_burst")
        self.total_frames = CSRStorage(64, name="total_frames")
        self.pkts = CSRStatus(64, name="pkts")
        self.frame_size = CSRStorage(32, reset=72, name="frame_size")
        self.frame_buf = CSRStorage(32, name="frame_buf",
            description="Each write stores a frame word and advances the buffer address.")
        self.frame_buf_address = CSRStorage(32, name="frame_buf_address",
            description="Sets the frame buffer write address (low 9 bits).")

        self.gmii_d = Signal(8)
        self.gmii_en = Signal()
        self.gmii_er = Signal()
        self.cycle_start = Signal()
        self.sec = Signal(48)
        self.nsec = Signal(30)
        self.traffic_generator_gmii_params = dict(
            p_C_USE_LITEX_CSR=1,
            i_clk=ClockSignal(), i_resetn=~ResetSignal(),
            o_gmii_d=self.gmii_d, o_gmii_en=self.gmii_en, o_gmii_er=self.gmii_er,
            o_cycle_start=self.cycle_start, i_sec=self.sec, i_nsec=self.nsec,
            o_csr_id=self.id.status, o_csr_version=self.version.status,
            i_csr_flip=self.flip.storage, o_csr_flip_read=self.flip.readback,
            i_csr_control=self.control.storage,
            i_csr_interframe_gap=self.interframe_gap.storage,
            i_csr_interburst_gap=self.interburst_gap.storage,
            i_csr_frames_per_burst=self.frames_per_burst.storage,
            i_csr_total_frames=self.total_frames.storage, o_csr_pkts=self.pkts.status,
            i_csr_frame_size=self.frame_size.storage,
            i_csr_frame_size_we=self.frame_size.re,
            i_csr_frame_buf=self.frame_buf.storage, i_csr_frame_buf_we=self.frame_buf.re,
            i_csr_frame_buf_address=self.frame_buf_address.storage[:9],
            i_csr_frame_buf_address_we=self.frame_buf_address.re,
            i_S_AXI_ACLK=ClockSignal(), i_S_AXI_ARESETN=~ResetSignal(),
            i_S_AXI_AWADDR=0, i_S_AXI_AWVALID=0,
            i_S_AXI_WDATA=0, i_S_AXI_WSTRB=0, i_S_AXI_WVALID=0,
            i_S_AXI_BREADY=0, i_S_AXI_ARADDR=0, i_S_AXI_ARVALID=0,
            i_S_AXI_RREADY=0,
        )
        self.specials += Instance("traffic_generator_gmii",
            name="traffic_generator_gmii_{}".format(instance_number),
            **self.traffic_generator_gmii_params)

        source_dir = os.path.join(os.path.dirname(__file__), "traffic_generator_gmii")
        platform.add_verilog_include_path(source_dir)
        for source in ("traffic_generator_gmii.v", "ethernet_crc_8.v", "bram_io.v"):
            platform.add_source(os.path.join(source_dir, source))
