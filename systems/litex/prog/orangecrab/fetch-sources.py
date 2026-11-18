#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Fetch the pinned inputs documented in ORANGECRAB_DEBIAN.md."""
import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--list-python", action="store_true",
                        help="Only list Python source directories; do not fetch")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    entries = json.loads(Path(__file__).with_name("sources.json").read_text())
    destination = args.destination.resolve()
    for entry in entries:
        path = destination / entry["directory"]
        if args.list_python:
            if entry["python"]:
                print(path)
            continue
        print(f"{path}: {entry['revision']}", flush=True)
        if args.dry_run:
            continue
        if path.exists():
            revision = subprocess.check_output(
                ["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
            if revision != entry["revision"]:
                raise SystemExit(f"Refusing to change existing checkout: {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["git", "init", str(path)], check=True)
            subprocess.run(["git", "-C", str(path), "remote", "add", "origin",
                            entry["url"]], check=True)
            subprocess.run(["git", "-C", str(path), "fetch", "--depth", "1",
                            "origin", entry["revision"]], check=True)
            subprocess.run(["git", "-C", str(path), "checkout", "--detach",
                            entry["revision"]], check=True)
        if entry["submodules"]:
            subprocess.run(["git", "-C", str(path), "submodule", "update",
                            "--init", "--recursive"], check=True)


if __name__ == "__main__":
    main()
