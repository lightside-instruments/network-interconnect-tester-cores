"""Ordered control-register transfer from sys CSRs to traffic datapaths."""

from migen import *
from migen.genlib.cdc import MultiReg
from litex.gen import LiteXModule


class TrafficControlQueue(LiteXModule):
    """Retain sixteen ordered control writes across generated clocks.

    RAM addresses come directly from registered binary pointers. Gray
    pointers cross the clock boundary; registered full/empty flags control
    pointer advancement, never combinational look-ahead RAM addresses.
    A valid bit accompanies the synchronous RAM read's one-cycle latency.

    Both sides reset when the datapath resets. The current CSR value is
    restored after reset; queued writes then drain one per datapath cycle.
    overflow is sticky in sys until the system itself resets.
    """
    def __init__(self, csr, domain, datapath_reset, reset_value=0):
        self.value = Signal(32, reset=reset_value)
        self.overflow = Signal()
        self.writable = Signal()
        write_domain = domain+"_csr_write"
        self.cd_csr_write = ClockDomain(write_domain)
        self.comb += [self.cd_csr_write.clk.eq(ClockSignal("sys")),
                      self.cd_csr_write.rst.eq(ResetSignal("sys") | datapath_reset)]

        # Four RAM address bits plus one wrap bit. Only registered Gray
        # pointers are synchronized; payload remains in dual-clock RAM.
        write_binary = Signal(5)
        read_binary = Signal(5)
        write_gray = Signal(5)
        read_gray = Signal(5)
        read_gray_sys = Signal(5)
        write_gray_datapath = Signal(5)
        self.specials += [MultiReg(read_gray, read_gray_sys, write_domain),
                          MultiReg(write_gray, write_gray_datapath, domain)]
        full = Signal()
        empty = Signal(reset=1)
        first = Signal(reset=1)
        write = Signal()
        read = Signal()
        self.comb += [self.writable.eq(~full),
                      write.eq(csr.re & ~datapath_reset & ~full),
                      read.eq(~empty & ~first)]

        write_next = Signal(5)
        read_next = Signal(5)
        write_gray_next = Signal(5)
        read_gray_next = Signal(5)
        self.comb += [
            write_next.eq(write_binary + write),
            read_next.eq(read_binary + read),
            write_gray_next.eq(write_next ^ (write_next >> 1)),
            read_gray_next.eq(read_next ^ (read_next >> 1)),
        ]
        write_sync = getattr(self.sync, write_domain)
        write_sync += [
            write_binary.eq(write_next), write_gray.eq(write_gray_next),
            full.eq(write_gray_next == Cat(read_gray_sys[:3], ~read_gray_sys[3:])),
        ]
        read_sync = getattr(self.sync, domain)
        read_sync += [
            read_binary.eq(read_next), read_gray.eq(read_gray_next),
            empty.eq(read_gray_next == write_gray_datapath),
        ]

        storage = Memory(32, 16)
        wrport = storage.get_port(write_capable=True, clock_domain=write_domain)
        rdport = storage.get_port(clock_domain=domain, mode=READ_FIRST)
        self.specials += storage, wrport, rdport
        self.comb += [wrport.adr.eq(write_binary[:4]), wrport.dat_w.eq(csr.storage),
                      wrport.we.eq(write), rdport.adr.eq(read_binary[:4])]
        pending = Signal()
        read_sync += [
            pending.eq(read),
            If(first,
                self.value.eq(csr.storage), first.eq(0),
            ).Elif(pending, self.value.eq(rdport.dat_r)),
        ]
        self.sync += If(csr.re & ~datapath_reset & full, self.overflow.eq(1))
