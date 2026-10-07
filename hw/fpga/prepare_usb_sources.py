#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check USB integration pins and apply the two narrowly scoped RTL patches."""

import argparse
import subprocess
from pathlib import Path

FPGA = Path(__file__).resolve().parent
ROOT = FPGA.parents[1]
PINS = {
    "hw/caliptra-ss": "4fb99b4dadc235e5989fa594dcd38894851676a1",
    "hw/caliptra-ss/third_party/caliptra-rtl": "c46bf7ca8e0b6dd1c82aa812073c02d6cd8c4fbd",
    "hw/caliptra-ss/third_party/i3c-core": "067bfe14ea8bb54470b6af9af154bee5cda6ded7",
    "hw/caliptra-ss/third_party/usb2": "87a1a3789604dd5a611693a6ba97fff871498593",
}
PATCHES = {
    "hw/caliptra-ss": FPGA / "usb_patches/caliptra-ss.patch",
    "hw/caliptra-ss/third_party/usb2": FPGA / "usb_patches/usb2.patch",
}


def git(directory, *args, check=True):
    return subprocess.run(
        ["git", "-C", str(directory), *args],
        check=check, text=True, capture_output=True,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify without changing files")
    args = parser.parse_args()
    for relative, expected in PINS.items():
        actual = git(ROOT / relative, "rev-parse", "HEAD").stdout.strip()
        if actual != expected:
            parser.error(f"{relative}: expected {expected}, found {actual}")
    pending = []
    for relative, patch in PATCHES.items():
        if not patch.is_file():
            parser.error(f"Missing patch: {patch}")
        directory = ROOT / relative
        applied = git(directory, "apply", "--reverse", "--check", str(patch), check=False)
        if applied.returncode == 0:
            continue
        forward = git(directory, "apply", "--check", str(patch), check=False)
        if forward.returncode != 0:
            parser.error(f"{relative}: patch conflicts:\n{forward.stderr}")
        pending.append((directory, patch))
    if args.check and pending:
        parser.error("USB RTL patches are not applied; run prepare_usb_sources.py without --check")
    for directory, patch in pending:
        git(directory, "apply", str(patch))
    print("USB integration pins and RTL patches: PASS")


if __name__ == "__main__":
    main()
