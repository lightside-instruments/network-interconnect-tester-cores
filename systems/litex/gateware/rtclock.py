#!/usr/bin/env python3

import os
import sys
import math

from migen import *
from migen.genlib.cdc import MultiReg
from litex.gen import *

from litex.soc.interconnect                  import stream
from litex.soc.interconnect.axi.axi_stream   import AXIStreamInterface
from litex.soc.interconnect.csr              import *
from litex.soc.interconnect.csr_eventmanager import *
from litex.soc.interconnect                  import axi  

class rtclock(LiteXModule):
    def __init__(self, platform,
        # Configuration.
        fft_pts              = 512,     #Changing FFT points requires FFT src rebuild, use rebuild_fft_rtl=True

        ):

        # CSR Registers Example.
        # ----------------------
        # Adding a simple CSR storage register for demonstration purposes.
        self.scratch = CSRStorage(32, description="Scratch register for testing purposes.")

        # AXI MMAP Bus (From CPU).
        self.mmap = axi.AXILiteInterface(address_width=12, data_width=32, name="rtclock")
        
        # # #    
        # AXI MMAP.
        # ---------
        self.ram = axi.AXILiteSRAM(0x1000)
        self.comb += self.mmap.connect(self.ram.bus)


        # assign fft wrapper ports to appropriate interfaces
        self.rtclock_params = dict()
        self.rtclock_params.update(
            i_clk = ClockSignal(),)

        self.specials += Instance(of="rtclock", **self.rtclock_params)

#        platform.add_source("./gateware/rtclock/rtclock_cpu_regs_defines.v")
        platform.add_source("./gateware/rtclock/rtclock.v")
#        platform.add_source("./gateware/rtclock/rtclock_cpu_regs.v")

