#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run focused SRAM and actual wrapper IOBUF-block simulations with XSim."""

import argparse
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

TESTS = Path(__file__).resolve().parent
FPGA = TESTS.parent
MCI = FPGA.parent / "caliptra-ss/src/mci/rtl"
CORE = FPGA.parent / "caliptra-ss/third_party/caliptra-rtl"
PRIM = CORE / "src/caliptra_prim/rtl"


def run(command, cwd):
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    output = result.stdout + result.stderr
    if result.returncode or re.search(r"(?m)^(ERROR:|Fatal:|FATAL:)", output):
        raise RuntimeError(f"Command failed: {command}\n{output}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vivado-bin", type=Path)
    args = parser.parse_args()
    if args.vivado_bin:
        binary = args.vivado_bin
    else:
        xvlog = shutil.which("xvlog")
        if not xvlog:
            parser.error("xvlog is not on PATH; supply --vivado-bin")
        binary = Path(xvlog).parent
    for tool in ("xvlog", "xelab", "xsim"):
        if not (binary / tool).is_file():
            parser.error(f"Missing simulator: {binary / tool}")
    glbl_candidates = [p / "data/verilog/src/glbl.v" for p in (binary.parent, binary.parent.parent)]
    glbl = next((p for p in glbl_candidates if p.is_file()), None)
    if glbl is None:
        parser.error(f"Cannot find glbl.v under {binary.parent}")
    wrapper = (FPGA / "src/caliptra_wrapper_top.sv").read_text()
    pads = re.search(
        r"if \(USB_ENABLE\) begin : g_usb_enabled_pads\n"
        r".*?end else begin : g_usb_disabled_pads\n.*?\nend",
        wrapper, re.DOTALL,
    )
    if pads is None:
        parser.error("Cannot find the actual wrapper ULPI IOBUF block")
    with tempfile.TemporaryDirectory(prefix="versal-usb-unit-") as directory:
        work = Path(directory)
        harness = work / "usb_ulpi_pad_harness.sv"
        harness.write_text(
            "module usb_ulpi_pad_harness #(parameter USB_ENABLE = 1)(input [7:0] usb_ulpi_txdata,\n"
            "input usb_ulpi_txenable, inout [7:0] USB_ULPI_DATA,\n"
            "output wire [7:0] usb_ulpi_rxdata);\n" + pads.group() + "\nendmodule\n"
        )
        run([str(binary / "xvlog"), "--sv", "--include", str(PRIM),
             "--include", str(CORE / "src/libs/rtl"),
             str(MCI / "mci_reg_pkg.sv"), str(MCI / "mci_reg.sv"),
             str(TESTS / "tb_usb_transport_reset.sv"),
             str(FPGA / "src/usb_packet_sram.sv"),
             str(TESTS / "tb_usb_packet_sram.sv"), str(harness),
             str(TESTS / "tb_usb_ulpi_pads.sv"), str(glbl)], work)
        for top, marker in (
            ("tb_usb_packet_sram", "USB_PACKET_SRAM_PASS:"),
            ("tb_usb_ulpi_pads", "USB_ULPI_PADS_PASS:"),
            ("tb_usb_transport_reset", "USB_TRANSPORT_RESET_PASS:"),
        ):
            run([str(binary / "xelab"), "--mt", "2", "--timescale", "1ns/1ps", "-L", "unisims_ver",
                 f"work.{top}", "work.glbl", "-s", top], work)
            output = run([str(binary / "xsim"), top, "--runall"], work)
            if marker not in output:
                raise RuntimeError(f"Missing test completion marker {marker}:\n{output}")
            print(next(line for line in output.splitlines() if marker in line))


if __name__ == "__main__":
    main()
