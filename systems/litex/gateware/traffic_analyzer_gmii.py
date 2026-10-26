#!/usr/bin/env python3

import os

from migen import *
from litex.gen import LiteXModule
from litex.soc.interconnect.csr import CSRStorage, CSRStatus
from gateware.traffic_generator_gmii import _ReadbackStorage


class traffic_analyzer_gmii(LiteXModule):
    """Expose analyzer configuration, statistics and capture as native CSRs."""
    def __init__(self, platform, instance_number=0):
        self.id = CSRStatus(32, name="id")
        self.version = CSRStatus(32, name="version")
        self.flip = _ReadbackStorage(32, name="flip")
        self.control = CSRStorage(32, reset=1, name="control",
            description="Bit 0 enables analysis; bit 1 freezes statistics and capture.")
        self.pkts = CSRStatus(64, name="pkts")
        self.octets = CSRStatus(64, name="octets")
        self.octets_idle = CSRStatus(64, name="octets_idle")
        self.timestamp_sec = CSRStatus(64, name="timestamp_sec")
        self.timestamp_nsec = CSRStatus(32, name="timestamp_nsec")
        self.frame_size = CSRStatus(32, name="frame_size")
        self.frame_buf = CSRStatus(32, name="frame_buf")
        self.bad_crc_pkts = CSRStatus(64, name="bad_crc_pkts")
        self.bad_crc_octets = CSRStatus(64, name="bad_crc_octets")
        self.bad_preamble_pkts = CSRStatus(64, name="bad_preamble_pkts")
        self.bad_preamble_octets = CSRStatus(64, name="bad_preamble_octets")
        self.octets_total = CSRStatus(64, name="octets_total")
        self.testframe_pkts = CSRStatus(64, name="testframe_pkts")
        self.sequence_errors = CSRStatus(64, name="sequence_errors")
        self.latency_min_sec = CSRStatus(64, name="latency_min_sec")
        self.latency_min_nsec = CSRStatus(32, name="latency_min_nsec")
        self.latency_max_sec = CSRStatus(64, name="latency_max_sec")
        self.latency_max_nsec = CSRStatus(32, name="latency_max_nsec")
        self.latency_sec = CSRStatus(64, name="latency_sec")
        self.latency_nsec = CSRStatus(32, name="latency_nsec")
        self.last_sequence_error_expected = CSRStatus(64, name="last_sequence_error_expected")
        self.last_sequence_error_received = CSRStatus(64, name="last_sequence_error_received")
        self.last_sequence_error_timestamp_sec = CSRStatus(64, name="last_sequence_error_timestamp_sec")
        self.last_sequence_error_timestamp_nsec = CSRStatus(32, name="last_sequence_error_timestamp_nsec")
        self.frame_buf_address = CSRStorage(32, name="frame_buf_address",
            description="Captured frame word address. Set before reading frame_buf.")
        self.testframe_filter_data = CSRStorage(320, name="testframe_filter_data")
        self.testframe_filter_mask = CSRStorage(320, name="testframe_filter_mask")

        self.gmii_d = Signal(8)
        self.gmii_en = Signal()
        self.gmii_er = Signal()
        self.sec = Signal(48)
        self.nsec = Signal(30)
        self.traffic_analyzer_gmii_params = dict(
            p_C_USE_LITEX_CSR=1,
            i_clk=ClockSignal(), i_resetn=~ResetSignal(),
            i_gmii_d=self.gmii_d, i_gmii_en=self.gmii_en, i_gmii_er=self.gmii_er,
            i_sec=self.sec, i_nsec=self.nsec,
            i_csr_flip=self.flip.storage, o_csr_flip_read=self.flip.readback,
            i_csr_control=self.control.storage,
            i_csr_testframe_filter_data=self.testframe_filter_data.storage,
            i_csr_testframe_filter_mask=self.testframe_filter_mask.storage,
            i_csr_frame_buf_address=self.frame_buf_address.storage[:9],
            o_csr_frame_buf=self.frame_buf.status,
            o_csr_id=self.id.status,
            o_csr_version=self.version.status,
            o_csr_pkts=self.pkts.status,
            o_csr_octets=self.octets.status,
            o_csr_octets_idle=self.octets_idle.status,
            o_csr_timestamp_sec=self.timestamp_sec.status,
            o_csr_timestamp_nsec=self.timestamp_nsec.status,
            o_csr_frame_size=self.frame_size.status,
            o_csr_bad_crc_pkts=self.bad_crc_pkts.status,
            o_csr_bad_crc_octets=self.bad_crc_octets.status,
            o_csr_bad_preamble_pkts=self.bad_preamble_pkts.status,
            o_csr_bad_preamble_octets=self.bad_preamble_octets.status,
            o_csr_octets_total=self.octets_total.status,
            o_csr_testframe_pkts=self.testframe_pkts.status,
            o_csr_sequence_errors=self.sequence_errors.status,
            o_csr_latency_min_sec=self.latency_min_sec.status,
            o_csr_latency_min_nsec=self.latency_min_nsec.status,
            o_csr_latency_max_sec=self.latency_max_sec.status,
            o_csr_latency_max_nsec=self.latency_max_nsec.status,
            o_csr_latency_sec=self.latency_sec.status,
            o_csr_latency_nsec=self.latency_nsec.status,
            o_csr_last_sequence_error_expected=self.last_sequence_error_expected.status,
            o_csr_last_sequence_error_received=self.last_sequence_error_received.status,
            o_csr_last_sequence_error_timestamp_sec=self.last_sequence_error_timestamp_sec.status,
            o_csr_last_sequence_error_timestamp_nsec=self.last_sequence_error_timestamp_nsec.status,
            i_S_AXI_ACLK=ClockSignal(), i_S_AXI_ARESETN=~ResetSignal(),
            i_S_AXI_AWADDR=0, i_S_AXI_AWVALID=0,
            i_S_AXI_WDATA=0, i_S_AXI_WSTRB=0, i_S_AXI_WVALID=0,
            i_S_AXI_BREADY=0, i_S_AXI_ARADDR=0, i_S_AXI_ARVALID=0,
            i_S_AXI_RREADY=0,
        )
        self.specials += Instance("traffic_analyzer_gmii",
            name="traffic_analyzer_gmii_{}".format(instance_number),
            **self.traffic_analyzer_gmii_params)

        source_dir = os.path.join(os.path.dirname(__file__), "traffic_analyzer_gmii")
        platform.add_verilog_include_path(source_dir)
        for source in ("traffic_analyzer_gmii_cpu_regs.v", "traffic_analyzer_gmii.v",
                       "ethernet_crc_8_check.v", "testframe_parser.v"):
            platform.add_source(os.path.join(source_dir, source))
        # Share the BRAM and CRC sources with the generator (no duplicate modules).
        for source in ("bram_io.v", "ethernet_crc_8.v"):
            platform.add_source(os.path.join(os.path.dirname(__file__),
                "traffic_generator_gmii", source))
