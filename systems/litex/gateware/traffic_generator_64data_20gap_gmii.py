# SPDX-License-Identifier: BSD-2-Clause
# Attribution and license terms: project-root COPYRIGHT.
"""CSR-free fixed-frame GMII source."""
import os
from migen import Instance, Signal
from litex.gen import LiteXModule


class traffic_generator_64data_20gap_gmii(LiteXModule):
    def __init__(self, platform, datapath_clk, datapath_reset, instance_number=0):
        self.gmii_d = Signal(8)
        self.gmii_en = Signal()
        self.gmii_er = Signal()
        self.cycle_start = Signal()
        self.specials += Instance('traffic_generator_64data_20gap_gmii',
            name='traffic_generator_64data_20gap_gmii_{}'.format(instance_number),
            i_clk=datapath_clk, i_resetn=~datapath_reset,
            o_gmii_d=self.gmii_d, o_gmii_en=self.gmii_en, o_gmii_er=self.gmii_er,
            o_cycle_start=self.cycle_start)
        platform.add_source(os.path.abspath(os.path.join(os.path.dirname(__file__),
            '../../../lib/hw/lsi/cores/traffic_generator_64data_20gap_gmii/hdl/',
            'traffic_generator_64data_20gap_gmii.v')))
