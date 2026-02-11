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

class traffic_generator_gmii(LiteXModule):
    def __init__(self, platform,
        # Configuration.
        fft_pts              = 512,     #Changing FFT points requires FFT src rebuild, use rebuild_fft_rtl=True

        ):

        # CSR Registers Example.
        # ----------------------
        # Adding a simple CSR storage register for demonstration purposes.
        self.scratch = CSRStorage(32, description="Scratch register for testing purposes.")

        # AXI MMAP Bus (From CPU).
        self.mmap = axi.AXILiteInterface(address_width=12, data_width=32, name="traffic_generator_gmii")
        
        # # #    
        # AXI MMAP.
        # ---------
        self.ram = axi.AXILiteSRAM(0x1000)
        self.comb += self.mmap.connect(self.ram.bus)


        # assign fft wrapper ports to appropriate interfaces
        self.traffic_generator_gmii_params = dict()
        self.traffic_generator_gmii_params.update(
            i_clk = ClockSignal(),
            #i_resetn=self.resetn,
            #o_gmii_d=self.gmii_d,
            #o_gmii_en=self.gmii_en,
            #o_gmii_er=self.gmii_er,
            #o_cycle_start=self.cycle_start,
            #i_sec=self.sec,
            #i_nsec=self.nsec,
            i_S_AXI_ACLK=ClockSignal(),
            #i_S_AXI_ARESETN=self.S_AXI_ARESETN,
            #i_S_AXI_AWADDR=self.S_AXI_AWADDR,
            #i_S_AXI_AWVALID=self.S_AXI_AWVALID,
            #i_S_AXI_WDATA=self.S_AXI_WDATA,
            #i_S_AXI_WSTRB=self.S_AXI_WSTRB,
            #i_S_AXI_WVALID=self.S_AXI_WVALID,
            #i_S_AXI_BREADY=self.S_AXI_BREADY,
            #i_S_AXI_ARADDR=self.S_AXI_ARADDR,
            #i_S_AXI_ARVALID=self.S_AXI_ARVALID,
            #i_S_AXI_RREADY=self.S_AXI_RREADY,
            #o_S_AXI_ARREADY=self.S_AXI_ARREADY,
            #o_S_AXI_RDATA=self.S_AXI_RDATA,
            #o_S_AXI_RRESP=self.S_AXI_RRESP,
            #o_S_AXI_RVALID=self.S_AXI_RVALID,
            #o_S_AXI_WREADY=self.S_AXI_WREADY,
            #o_S_AXI_BRESP=self.S_AXI_BRESP,
            #o_S_AXI_BVALID=self.S_AXI_BVALID,
            #o_S_AXI_AWREADY=self.S_AXI_AWREADY,
        )
#    parameter C_S_AXI_DATA_WIDTH    = 32,
#    parameter C_S_AXI_ADDR_WIDTH    = 12,
#    parameter C_BASEADDR            = 32'h00000000,
#    parameter C_FRAME_BUF_ADDRESS_WIDTH   = 9
# )
# (
#     // Global Ports
#     input clk,
#     input resetn,

#     // GMII OUT ports
#     output reg [8 - 1:0] gmii_d,
#     output reg gmii_en,
#     output reg gmii_er,
# 
#    output reg cycle_start,
#
#    input [47:0] sec,
#    input [29:0] nsec,
#
#    // Slave AXI Ports
#    input                                     S_AXI_ACLK,
#    input                                     S_AXI_ARESETN,
#    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_AWADDR,
#    input                                     S_AXI_AWVALID,
#    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_WDATA,
#    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S_AXI_WSTRB,
#    input                                     S_AXI_WVALID,
#    input                                     S_AXI_BREADY,
#    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_ARADDR,
#    input                                     S_AXI_ARVALID,
#    input                                     S_AXI_RREADY,
#    output                                    S_AXI_ARREADY,
#    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_RDATA,
#    output     [1 : 0]                        S_AXI_RRESP,
#    output                                    S_AXI_RVALID,
#    output                                    S_AXI_WREADY,
#    output     [1 :0]                         S_AXI_BRESP,
#    output                                    S_AXI_BVALID,
#    output                                    S_AXI_AWREADY

        self.specials += Instance(of="traffic_generator_gmii", **self.traffic_generator_gmii_params)

#        platform.add_source("./gateware/traffic_generator_gmii/traffic_generator_gmii_cpu_regs_defines.v")
        platform.add_source("./gateware/traffic_generator_gmii/traffic_generator_gmii.v")
#        platform.add_source("./gateware/traffic_generator_gmii/traffic_generator_gmii_cpu_regs.v")
#        platform.add_source("./gateware/traffic_generator_gmii/traffic_generator_gmii_cpu_regs_defines.v")
#        platform.add_source("./gateware/traffic_generator_gmii/ethernet_crc_8.v")
        platform.add_source("./gateware/traffic_generator_gmii/bram_io.v")

