# SPDX-License-Identifier: BSD-2-Clause
# See the project-root COPYRIGHT for attribution and license terms.
"""Versa ECP5 SMA 1000BASE-X, raw 10-bit DCU interface at 125 MHz."""
import os
from functools import reduce
from operator import xor

from migen import *
from migen.genlib.cdc import MultiReg
from migen.genlib.resetsync import AsyncResetSynchronizer
from litex.gen import LiteXModule
from litex.gen.genlib.cdc import BusSynchronizer
from litex.soc.interconnect.csr import CSR, CSRStatus, CSRStorage, CSRField
from liteiclink.serdes.serdes_ecp5 import SerDesECP5PLL, SerDesECP5, SerDesECP5SCI


class ECP5SerdesInit(LiteXModule):
    """Release TX after PLL lock, regardless of whether an RX cable exists."""
    def __init__(self, tx_lol, rx_lol, rx_los):
        self.tx_ready = Signal()
        self.rx_ready = Signal()
        self.reset = Signal()
        tx_bad, rx_bad, los = Signal(), Signal(), Signal()
        self.specials += [MultiReg(tx_lol, tx_bad), MultiReg(rx_lol, rx_bad),
                          MultiReg(rx_los, los)]
        startup = Signal(11)
        tx_settle, rx_settle = Signal(11), Signal(11)
        self.comb += self.reset.eq(~startup[-1])
        self.sync += [
            If(~startup[-1], startup.eq(startup+1)),
            If(self.reset | tx_bad, tx_settle.eq(0)).Elif(~tx_settle[-1], tx_settle.eq(tx_settle+1)),
            If(~self.tx_ready | rx_bad | los, rx_settle.eq(0)
            ).Elif(~rx_settle[-1], rx_settle.eq(rx_settle+1)),
        ]
        self.comb += [self.tx_ready.eq(tx_settle[-1] & ~tx_bad),
                      self.rx_ready.eq(rx_settle[-1] & ~rx_bad & ~los)]


class ECP5SerdesStatus(LiteXModule):
    """System-clock readback, independent of RX clock and datapath resets."""
    def __init__(self, phy, ref_pll_locked, clock_window_bits=16):
        rx_enabled = hasattr(phy, 'cd_gmii_rx')
        signals = [
            ('ref_pll_locked', ref_pll_locked),
            ('tx_pll_locked', ~phy.tx_lol),
            ('rx_cdr_locked', ~phy.rx_lol if rx_enabled else 0),
            ('rx_signal_detected', ~phy.rx_los if rx_enabled else 0),
            ('tx_ready', phy.init.tx_ready),
            ('rx_ready', phy.init.rx_ready if rx_enabled else 0),
            ('cdr_ready', phy.cdr_locked if rx_enabled else 0),
            ('pcs_synced', phy.pcs_synced if rx_enabled else 0),
            ('tx_reset', phy.tx_reset),
            ('rx_pcs_reset', phy.cd_gmii_rx.rst if rx_enabled else 1),
            ('rx_mac_reset', phy.rx_reset if rx_enabled else 1),
            ('serdes_reset', phy.init.reset),
        ]
        self.status = CSRStatus(32, name='status', fields=[
            CSRField(name, offset=bit) for bit, (name, _) in enumerate(signals)
        ] + [
            CSRField('tx_clock_active', offset=12),
            CSRField('rx_clock_active', offset=13),
            CSRField('rx_enabled', offset=14),
            CSRField('tx_pclk_active', offset=15),
            CSRField('reserved', size=16, offset=16),
        ], description='Synchronized live SERDES state; clock flags expire after 4095 sys cycles.')
        synchronized = Signal(len(signals))
        self.specials += MultiReg(Cat(*(value for _, value in signals)), synchronized)
        self.tx_clock_count = CSRStatus(32, name='tx_clock_count',
            description='TX clock edges per 65536 sys cycles; independently sampled Gray counter.')
        self.rx_clock_count = CSRStatus(32, name='rx_clock_count',
            description='RX clock edges per 65536 sys cycles; independently sampled Gray counter.')
        self.tx_pclk_clock_count = CSRStatus(32, name='tx_pclk_clock_count',
            description='Raw DCU TX_PCLK edges per 65536 sys cycles, independent of TX interface clock.')
        window = Signal(clock_window_bits)
        self.sync += window.eq(window + 1)
        active = []
        for domain, count_csr in (('gmii_tx', self.tx_clock_count),
                                  ('gmii_rx', self.rx_clock_count),
                                  ('tx_pclk', self.tx_pclk_clock_count)):
            if ((domain == 'gmii_rx' and not rx_enabled) or
                    (domain == 'tx_pclk' and not hasattr(phy, 'cd_tx_pclk'))):
                active.append(Constant(0))
                self.comb += count_csr.status.eq(0)
                continue
            # Keep counting during datapath reset, including loss of PCS sync.
            divider = Signal(24, reset_less=True)
            gray = Signal(24, reset_less=True)
            sync = getattr(self.sync, domain)
            sync += [divider.eq(divider + 1), gray.eq(divider ^ (divider >> 1))]
            sampled_gray, sampled_count, previous_count = Signal(24), Signal(24), Signal(24)
            self.specials += MultiReg(gray, sampled_gray)
            for bit in range(24):
                self.comb += sampled_count[bit].eq(reduce(xor, sampled_gray[bit:]))
            self.sync += If(window == (1 << clock_window_bits) - 1,
                count_csr.status.eq((sampled_count - previous_count)[:24]),
                previous_count.eq(sampled_count))
            toggle = Signal()
            previous = Signal()
            age = Signal(12, reset=4095)
            self.specials += MultiReg(divider[7], toggle)
            self.sync += [previous.eq(toggle),
                If(toggle != previous, age.eq(0)).Elif(age != 4095, age.eq(age + 1))]
            active.append(age != 4095)
        for bit, (name, _) in enumerate(signals):
            self.comb += getattr(self.status.fields, name).eq(synchronized[bit])
        self.comb += [
            self.status.fields.tx_clock_active.eq(active[0]),
            self.status.fields.rx_clock_active.eq(active[1]),
            self.status.fields.rx_enabled.eq(rx_enabled),
            self.status.fields.tx_pclk_active.eq(active[2]),
            self.status.fields.reserved.eq(0),
        ]
        if hasattr(phy, 'sci'):
            self.control = CSRStorage(2, name='control', fields=[
                CSRField('tx_serdes_reset', offset=0),
                CSRField('tx_pcs_reset', offset=1),
            ], description='TX-only manual reset requests; write zero to release.')
            self.sci_dual = CSRStorage(1, name='sci_dual', description='0: selected channel; 1: shared dual.')
            self.sci_address = CSRStorage(6, name='sci_address')
            self.sci_write_data = CSRStorage(8, name='sci_write_data')
            self.sci_read = CSR(name='sci_read')
            self.sci_write = CSR(name='sci_write')
            self.sci_read_data = CSRStatus(8, name='sci_read_data')
            self.sci_busy = CSRStatus(1, name='sci_busy')
            sci = phy.sci
            self.comb += [
                phy.tx_serdes_reset.eq(self.control.fields.tx_serdes_reset),
                phy.tx_pcs_reset.eq(self.control.fields.tx_pcs_reset),
                sci.dual_sel.eq(self.sci_dual.storage),
                sci.chan_sel.eq(~self.sci_dual.storage),
                sci.adr.eq(self.sci_address.storage),
                sci.dat_w.eq(self.sci_write_data.storage),
                sci.re.eq(self.sci_read.re & sci.done),
                sci.we.eq(self.sci_write.re & sci.done),
                self.sci_read_data.status.eq(sci.dat_r),
                self.sci_busy.status.eq(~sci.done),
            ]


def dcu_profile(pll, tx_pads, rx_pads):
    """Reuse LiteICLink's electrical/analog profile, with local reset/datapaths.

    Only parameters are retained; none of the template's encoder, decoder,
    SCI or reset logic is instantiated. Every native input is explicitly
    tied off or connected below, so no template signal becomes a floating IO.
    """
    template = SerDesECP5(pll, tx_pads, rx_pads, dual=0, channel=1)
    return {k: (v if k.startswith('p_') else 0)
            for k, v in template.serdes_params.items()
            if k.startswith(('p_', 'i_'))}


class ECP51000BaseX(LiteXModule):
    rx_datapath_domain = 'gmii_rx_mac'
    time_source_domain = 'gmii_tx'

    def __init__(self, platform, refclk, tx_only=False, dummy_pcs=False,
                 with_time=True, loopback=False):
        if loopback:
            raise ValueError('ECP5 PMA loopback is not supported; connect the SMA TX/RX pairs externally')
        if refclk is None:
            raise ValueError('ECP5 SERDES requires the internally generated 125 MHz reference')
        for name, width in (("tx_data",8),("tx_en",1),("tx_er",1),
                            ("rx_data",8),("rx_dv",1),("rx_er",1),
                            ("tx_gmii_clk",1),("rx_gmii_clk",1),
                            ("tx_reset",1),("rx_reset",1),("ready",1),
                            ("cdr_locked",1),("pcs_synced",1),("tx_error",1),
                            ("rx_code_error",1),("rx_disparity_error",1),
                            ("rx_overflow",1),("rx_abort",1),("control_overflow",1),
                            ("gen_sec",48),("gen_nsec",30),
                            ("analyzer_sec",48),("analyzer_nsec",30),
                            ("time_sec",48),("time_nsec",30)):
            setattr(self,name,Signal(width,name=name))
        self.txoutclk, self.rxoutclk = Signal(), Signal()
        self.cd_tx_pclk = ClockDomain('tx_pclk', reset_less=True)
        self.comb += self.cd_tx_pclk.clk.eq(self.txoutclk)
        self.cd_gmii_tx = ClockDomain('gmii_tx')
        # The phase-buffer FIFO remains enabled. Its input clock can use the
        # common 125 MHz reference, avoiding dependence on the DCU clock output.
        self.comb += [self.cd_gmii_tx.clk.eq(refclk),
                      self.tx_gmii_clk.eq(refclk),
                      self.tx_reset.eq(self.cd_gmii_tx.rst),
                      self.ready.eq(~self.cd_gmii_tx.rst)]
        tx_lol, rx_lol, rx_los = Signal(reset=1), Signal(reset=1), Signal(reset=1)
        self.tx_lol, self.rx_lol, self.rx_los = tx_lol, rx_lol, rx_los
        self.tx_serdes_reset, self.tx_pcs_reset = Signal(), Signal()
        self.init = init = ECP5SerdesInit(tx_lol,rx_lol,rx_los)
        self.specials += AsyncResetSynchronizer(self.cd_gmii_tx,
            ResetSignal('sys') | ~init.tx_ready | tx_lol |
            self.tx_serdes_reset | self.tx_pcs_reset)
        if not tx_only:
            self.cd_gmii_rx = ClockDomain('gmii_rx')
            self.cd_gmii_rx_mac = ClockDomain('gmii_rx_mac')
            self.comb += [self.cd_gmii_rx.clk.eq(self.rxoutclk),
                          self.cd_gmii_rx_mac.clk.eq(self.rxoutclk),
                          self.rx_gmii_clk.eq(self.rxoutclk),
                          self.rx_reset.eq(self.cd_gmii_rx_mac.rst),
                          self.cdr_locked.eq(init.rx_ready & ~rx_lol & ~rx_los)]
            rx_reset = ResetSignal('sys') | ~self.cdr_locked
            self.specials += [AsyncResetSynchronizer(self.cd_gmii_rx,rx_reset),
                AsyncResetSynchronizer(self.cd_gmii_rx_mac,rx_reset | ~self.pcs_synced)]
        tx_pads, rx_pads = platform.request('sma_tx'), platform.request('sma_rx')
        self.pll = pll = SerDesECP5PLL(refclk,125e6,1.25e9)
        params = dcu_profile(pll,tx_pads,rx_pads)
        tx_code, rx_code = Signal(10), Signal(10)
        native_rx = Signal(10)
        params.update(
            # Route local synchronization to the TX serializers. Without it
            # the PLL can lock while TX_PCLK and normal serial data stay flat.
            p_D_SYNC_LOCAL_EN='0b1',
            # CH_11[6:5]=00 powers the output common-mode circuit down.
            # Set this explicitly; TXAMPLITUDE does not set it in Trellis.
            p_CHX_TX_CM_SEL='0b01',
            # The 20x reference profile uses the channel's /2 rate mode.
            # VCO divider attributes alone do not select this channel mode.
            p_CHX_RATE_MODE_TX='0b1', p_CHX_RATE_MODE_RX='0b1',
            i_CHX_FFC_RATE_MODE_TX=1, i_CHX_FFC_RATE_MODE_RX=1,
            p_CHX_TX_GEAR_MODE='0b0',p_CHX_RX_GEAR_MODE='0b0',
            p_CHX_FF_TX_H_CLK_EN='0b0',p_CHX_FF_RX_H_CLK_EN='0b0',
            p_CHX_FF_TX_F_CLK_DIS='0b0',p_CHX_FF_RX_F_CLK_DIS='0b0',
            p_CHX_RPWDNB='0b0' if tx_only else '0b1',
            p_CH0_RPWDNB='0b0',p_CH0_TPWDNB='0b0',
            i_D_REFCLKI=refclk, i_CHX_RX_REFCLK=refclk,
            i_D_FFC_MACROPDB=1,i_D_FFC_MACRO_RST=init.reset,
            i_D_FFC_DUAL_RST=init.reset,i_D_FFC_TRST=init.reset | self.tx_serdes_reset,
            i_CHX_FFC_TXPWDNB=1,i_CHX_FFC_RXPWDNB=0 if tx_only else 1,
            i_CHX_FFC_LANE_TX_RST=~init.tx_ready | self.tx_pcs_reset | self.tx_serdes_reset,
            i_CHX_FFC_RRST=1 if tx_only else ~init.tx_ready,
            i_CHX_FFC_LANE_RX_RST=1 if tx_only else ~init.rx_ready,
            i_CHX_FFC_SIGNAL_DETECT=0 if tx_only else 1,
            i_CHX_FF_TXI_CLK=refclk,
            i_CHX_FF_RXI_CLK=0 if tx_only else self.rxoutclk,
            i_CHX_HDINP=rx_pads.p,i_CHX_HDINN=rx_pads.n,
            o_CHX_HDOUTP=tx_pads.p,o_CHX_HDOUTN=tx_pads.n,
            o_CHX_FF_TX_PCLK=self.txoutclk,
            o_D_FFS_PLOL=tx_lol,o_CHX_FFS_RLOL=rx_lol,o_CHX_FFS_RLOS=rx_los)
        if not tx_only:
            params['o_CHX_FF_RX_PCLK']=self.rxoutclk
            params.update({'o_CHX_FF_RX_D_%d'%i:native_rx[i] for i in range(10)})
        # DCU raw bits are transmitted least-significant first; the project
        # PCS code groups are most-significant first.
        params.update({'i_CHX_FF_TX_D_%d'%i:tx_code[9-i] for i in range(10)})
        self.comb += rx_code.eq(native_rx[::-1])
        # The shared SCI port and selected-channel enables are independent of
        # the TX data clock, so they remain usable if TX_PCLK stops.
        self.serdes_params = params
        self.sci = SerDesECP5SCI(self)
        params={k.replace('CHX','CH1'):v for k,v in params.items()}
        self.serdes_params=params
        self.specials.dcu = Instance('DCUA',**params)
        self.dcu.attr.add(('LOC','DCU0'))
        self.dcu.attr.add(('CHAN','CH1'))
        if dummy_pcs:
            self.comb += tx_code.eq(Cat(self.tx_data,Constant(0,2))[::-1])
        else:
            self.specials += Instance('pcs_1000basex_tx',p_REGISTER_SYMBOL=1,
                i_clk=self.tx_gmii_clk,i_rst=self.tx_reset,i_symbol_ce=1,
                i_gmii_txd=self.tx_data,i_gmii_tx_en=self.tx_en,i_gmii_tx_er=self.tx_er,
                i_config_enable=0,i_config_word=0,o_code_group=tx_code,o_protocol_error=self.tx_error)
        if not tx_only:
            self.specials += Instance('network_tester_pcs_rx_parallel', p_REGISTER_DECODE=1,
                i_clk=self.rx_gmii_clk,i_rst=ResetSignal('gmii_rx'),
                i_cdr_locked=self.cdr_locked,i_code_valid=1,i_code_group=rx_code,
                o_rx_data=self.rx_data,o_rx_dv=self.rx_dv,o_rx_er=self.rx_er,
                o_pcs_synced=self.pcs_synced,o_code_error=self.rx_code_error,
                o_disparity_error=self.rx_disparity_error)
            self.comb += self.rx_abort.eq(self.rx_er)
        times=[] if (not with_time) else [('tx_time','gmii_tx',self.gen_sec,self.gen_nsec)]
        if not tx_only:
            times.append(('rx_time','gmii_rx_mac',self.analyzer_sec,self.analyzer_nsec))
        for name,domain,sec,nsec in times:
            if domain == self.time_source_domain:
                self.comb += [sec.eq(self.time_sec), nsec.eq(self.time_nsec)]
                continue
            crossing=BusSynchronizer(78,self.time_source_domain,domain)
            setattr(self.submodules,name,crossing)
            self.comb += [crossing.i.eq(Cat(self.time_nsec,self.time_sec)),
                          nsec.eq(crossing.o[:30]),sec.eq(crossing.o[30:])]
        gateware=os.path.dirname(__file__)
        cores=os.path.abspath(os.path.join(gateware,'../../../lib/hw/lsi/cores'))
        if not dummy_pcs:
            for name in ('encoder_8b10b.v','pcs_1000basex_tx.v'):
                platform.add_source(os.path.join(cores,'pcs_1000basex_tx/hdl',name))
        if not tx_only:
            platform.add_source(os.path.join(gateware,'network_tester_pcs_rx_parallel.v'))
            platform.add_source(os.path.join(gateware,'network_tester_decoder_8b10b_rom.v'))
            platform.add_source(os.path.join(cores,'pcs_1000basex_rx/hdl/decoder_8b10b.v'))
        platform.add_period_constraint(self.tx_gmii_clk,8)
        platform.add_period_constraint(self.txoutclk,8)
        if not tx_only:
            platform.add_period_constraint(self.rxoutclk,8)
