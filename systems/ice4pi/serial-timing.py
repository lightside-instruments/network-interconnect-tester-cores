# The derived clocks run at 40 MHz or less. Constrain the PLL output separately.
ctx.addClock("pll_clk", 120)
