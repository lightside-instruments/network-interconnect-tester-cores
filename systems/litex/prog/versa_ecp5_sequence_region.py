# SPDX-License-Identifier: BSD-2-Clause
# See the project-root COPYRIGHT for attribution and license terms.
# Versa ECP5 45K: keep sequence comparison and error counters close together.
# Run with nextpnr-ecp5 --pre-place. No clocks or timing exceptions are changed.
ctx.createRectangularRegion('sequence_stats', 20, 35, 45, 70)
selected = []
for name, cell in ctx.cells:
    if str(cell.type) in ('TRELLIS_SLICE', 'TRELLIS_COMB', 'TRELLIS_FF') and 'traffic_analyzer_gmii_0.' in name:
        if 'expected_sequence_num' in name or 'sequence_errors' in name:
            ctx.constrainCellToRegion(name, 'sequence_stats')
            selected.append(name)
print('SEQUENCE_REGION_CELLS', len(selected))
if len(selected) < 20:
    raise RuntimeError('Expected sequence comparison and counter cells after packing')
