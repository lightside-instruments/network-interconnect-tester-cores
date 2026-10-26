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
        self.scratch = CSRStorage(32, name="scratch", description="Scratch register for testing purposes.")

        # AXI MMAP Bus (From CPU).
        self.mmap = axi.AXILiteInterface(address_width=12, data_width=32, name="rtclock")
        
        # # #    
        # AXI MMAP.
        # ---------
        self.ram = axi.AXILiteSRAM(0x1000)
        self.comb += self.mmap.connect(self.ram.bus)


        # assign fft wrapper ports to appropriate interfaces
        self.sec = Signal(48)
        self.nsec = Signal(30)
        self.pps = Signal()
        self.pps2 = Signal()
        self.rtclock_params = dict(
            i_clk=ClockSignal(), i_resetn=~ResetSignal(),
            i_pps=self.pps, i_pps2=self.pps2,
            o_sec=self.sec, o_nsec=self.nsec,
            i_S_AXI_ACLK=ClockSignal(), i_S_AXI_ARESETN=~ResetSignal(),
            i_S_AXI_AWADDR=0, i_S_AXI_AWVALID=0,
            i_S_AXI_WDATA=0, i_S_AXI_WSTRB=0, i_S_AXI_WVALID=0,
            i_S_AXI_BREADY=0, i_S_AXI_ARADDR=0, i_S_AXI_ARVALID=0,
            i_S_AXI_RREADY=0,
        )

        self.specials += Instance(of="rtclock", **self.rtclock_params)

#        platform.add_source("./gateware/rtclock/rtclock_cpu_regs_defines.v")
        source_dir = os.path.join(os.path.dirname(__file__), "rtclock")
        platform.add_verilog_include_path(source_dir)
        platform.add_source(os.path.join(source_dir, "rtclock.v"))
#        platform.add_source("./gateware/rtclock/rtclock_cpu_regs.v")

