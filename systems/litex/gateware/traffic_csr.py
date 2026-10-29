"""Control-register transfer from sys CSRs to slower traffic datapaths."""

from migen import *
from migen.genlib.fifo import AsyncFIFOBuffered
from litex.gen import LiteXModule


class TrafficControlQueue(LiteXModule):
    """Retain up to sixteen ordered control writes across generated clocks.

    Both FIFO sides reset when the datapath resets. The current CSR value
    is restored after reset; ordered writes then drain one per datapath cycle.
    overflow is a sticky diagnostic in sys until the system itself resets.
    """
    def __init__(self, csr, domain, datapath_reset, reset_value=0):
        self.value = Signal(32, reset=reset_value)
        self.overflow = Signal()
        write_domain = domain+"_csr_write"
        self.cd_csr_write = ClockDomain(write_domain)
        self.comb += [self.cd_csr_write.clk.eq(ClockSignal("sys")),
                      self.cd_csr_write.rst.eq(ResetSignal("sys") | datapath_reset)]
        self.fifo = fifo = ClockDomainsRenamer({"write": write_domain, "read": domain})(
            AsyncFIFOBuffered(32, 16))
        first = Signal(reset=1)
        self.comb += [fifo.din.eq(csr.storage), fifo.we.eq(csr.re & ~datapath_reset),
                      fifo.re.eq(fifo.readable & ~first)]
        self.sync += If(csr.re & ~datapath_reset & ~fifo.writable, self.overflow.eq(1))
        sync = getattr(self.sync, domain)
        sync += If(first,
            self.value.eq(csr.storage), first.eq(0),
        ).Elif(fifo.readable, self.value.eq(fifo.dout))
