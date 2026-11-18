#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Require every clock in a nextpnr JSON timing report to meet its constraint."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    clocks = json.loads(args.report.read_text()).get("fmax", {})
    if not clocks:
        raise SystemExit("No constrained-clock results found")
    failed = False
    for name, values in sorted(clocks.items()):
        achieved, required = values["achieved"], values["constraint"]
        passed = achieved >= required > 0
        failed |= not passed
        print(f"{'PASS' if passed else 'FAIL'} {name}: "
              f"{achieved:.3f} / {required:.3f} MHz")
    if failed:
        raise SystemExit("Do not package/program this timing-failing route")


if __name__ == "__main__":
    main()
