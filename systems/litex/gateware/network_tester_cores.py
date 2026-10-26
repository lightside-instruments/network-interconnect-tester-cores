"""Shared traffic-core configuration for LiteX board targets."""

from gateware.traffic_generator_gmii import traffic_generator_gmii
from gateware.traffic_analyzer_gmii import traffic_analyzer_gmii
from gateware.rtclock import rtclock


def network_tester_cores_add(parent, platform, instances=1):
    """Attach numbered cores directly to parent, preserving CSR names/order.

    Instance 0 uses internal GMII loopback and the shared realtime clock.
    Additional instances expose their interfaces for board-specific wiring.
    """
    if instances < 1:
        raise ValueError("At least one network-tester-core pair is required")
    for i in range(instances):
        setattr(parent, "traffic_generator_gmii_{}".format(i),
                traffic_generator_gmii(platform, instance_number=i))
    for i in range(instances):
        setattr(parent, "traffic_analyzer_gmii_{}".format(i),
                traffic_analyzer_gmii(platform, instance_number=i))
    parent.rtclock = rtclock(platform)
    generator = parent.traffic_generator_gmii_0
    analyzer = parent.traffic_analyzer_gmii_0
    parent.comb += [
        analyzer.gmii_d.eq(generator.gmii_d),
        analyzer.gmii_en.eq(generator.gmii_en),
        analyzer.gmii_er.eq(generator.gmii_er),
        generator.sec.eq(parent.rtclock.sec),
        generator.nsec.eq(parent.rtclock.nsec),
        analyzer.sec.eq(parent.rtclock.sec),
        analyzer.nsec.eq(parent.rtclock.nsec),
    ]


def network_tester_cores_configure_csrs(kwargs):
    """Ensure all four register sets fit even with an 8-bit CSR bus."""
    kwargs["csr_paging"] = max(kwargs.get("csr_paging", 0x800), 0x1000)
