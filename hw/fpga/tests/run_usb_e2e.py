#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run the MCU single-read fixture using an explicitly supplied RTL/IP cache."""

import argparse
import hashlib
import re
import subprocess
from pathlib import Path

TESTS = Path(__file__).resolve().parent
FPGA = TESTS.parent
USB = FPGA.parent / "caliptra-ss/third_party/usb2/src"


def run(command, cache, log):
    with log.open("w") as output:
        result = subprocess.run(command, cwd=cache, stdout=output, stderr=subprocess.STDOUT)
    text = log.read_text()
    if result.returncode or re.search(r"(?m)^(ERROR:|Fatal:|FATAL:|Failure:)", text):
        raise RuntimeError(f"Simulation command failed; inspect {log}\n{text[-6000:]}")
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True,
                        help="Writable, isolated cache containing current Versal SV and USB/vendor libraries")
    parser.add_argument("--vivado-bin", type=Path, required=True)
    parser.add_argument("--mcu-rom", type=Path, required=True,
                        help="128 KiB MCU image in 64-bit XPM readmemh format")
    parser.add_argument("--core-rom", type=Path,
                        help="96 KiB core readmemh image; selects final-ROM initialization smoke test")
    parser.add_argument("--otp-image", type=Path, required=True,
                        help="8192-word simulation OTP VMEM fixture")
    parser.add_argument("--phy-model", type=Path, required=True,
                        help="Existing usb3320_register_model.sv behavioral model")
    args = parser.parse_args()
    cache = args.cache.resolve()
    binary = args.vivado_bin.resolve()
    rom = args.mcu_rom.resolve()
    otp = args.otp_image.resolve()
    phy = args.phy_model.resolve()
    for path in (rom, otp, phy, cache / "xsim.ini"):
        if not path.is_file():
            parser.error(f"Missing required input: {path}")
    for name in ("xvlog", "xvhdl", "xelab", "xsim"):
        if not (binary / name).is_file():
            parser.error(f"Missing tool: {binary / name}")
    try:
        image = b"".join(int(word, 16).to_bytes(8, "little")
                         for word in rom.read_text(encoding="ascii").split())
    except (ValueError, OverflowError, UnicodeError) as error:
        parser.error(f"Invalid 64-bit readmemh ROM image: {error}")
    if len(image) != 131072:
        parser.error(f"Expected 128 KiB ROM image, received {len(image)} bytes")
    if args.core_rom:
        core = args.core_rom.resolve()
        if not core.is_file():
            parser.error(f"Missing core ROM: {core}")
        try:
            core_image = b"".join(int(word, 16).to_bytes(8, "little")
                                  for word in core.read_text(encoding="ascii").split())
        except (ValueError, OverflowError, UnicodeError) as error:
            parser.error(f"Invalid core readmemh image: {error}")
        if len(core_image) != 98304:
            parser.error(f"Expected 96 KiB core image, received {len(core_image)} bytes")
        print(f"CORE_ROM_BINARY_SHA256: {hashlib.sha256(core_image).hexdigest()}", flush=True)
        prefix = "final_rom_init"
    else:
        for marker in (b"SIMULATION ONLY: startup wait=", b"SIMULATION ONLY: settle wait="):
            if marker not in image:
                parser.error(f"Short-delay ROM marker missing: {marker.decode()}")
        prefix = "e2e"
    print(f"MCU_ROM_BINARY_SHA256: {hashlib.sha256(image).hexdigest()}", flush=True)
    print(f"MCU_ROM_SHA256: {hashlib.sha256(rom.read_bytes()).hexdigest()}", flush=True)
    print("CACHE_REQUIREMENT: current Versal RTL compiled; existing VHDL/IP libraries reused", flush=True)
    run(["python3", str(TESTS / "prepare_usb_e2e_bindings.py"),
         str(FPGA / "src/caliptra_wrapper_top.sv"),
         str(cache / "versal_usb_e2e_bindings.svh")], cache, cache / "e2e_bindings.log")
    guarded = cache / "usb_ocp_recovery_post_sync_arb.e2e.vhdl"
    run(["python3", str(TESTS / "prepare_usb_e2e_assertions.py"),
         str(USB / "usb_hub_composite_device/RTL/RTL/usb_ocp_recovery_post_sync_arb.m.vhdl"),
         str(guarded)], cache, cache / "e2e_assertion_preparation.log")
    run([str(binary / "xvhdl"), "--2008", "--work", "rtl", str(guarded)],
        cache, cache / "e2e_vhdl.stdout")
    run([str(binary / "xvlog"), "--sv", "-i", str(cache), str(phy),
         str(TESTS / "tb_versal_usb_single_read.sv")], cache, cache / "e2e_compile.stdout")
    snapshot = f"versal_usb_{prefix}"
    run([str(binary / "xelab"), "--incr", "--relax", "--ignore_assertions",
         "--mt", "2", "--debug", "typical", "--timescale", "1ns/1ps",
         "-L", "work", "-L", "xil_defaultlib", "-L", "rtl", "-L", "unisims_ver",
         "-L", "unimacro_ver", "-L", "secureip", "-L", "xpm",
         "work.tb_versal_usb_single_read", "xil_defaultlib.glbl", "-s", snapshot],
        cache, cache / f"{prefix}_elaboration.stdout")
    extra = ["--testplusarg", "FINAL_ROM_INIT", "--testplusarg", f"CORE_ROM={core}"] if args.core_rom else []
    output = run([str(binary / "xsim"), snapshot, "--runall",
                  "--testplusarg", f"MCU_ROM={rom}", "--testplusarg", f"OTP_IMAGE={otp}",
                  *extra, "--log", str(cache / f"{prefix}_result.log")],
                 cache, cache / f"{prefix}_run.stdout")
    expected = "VERSAL_FINAL_ROM_INIT_PASS" if args.core_rom else "VERSAL_USB_E2E_PASS"
    marker = re.search(rf"(?m)^{expected}:.*$", output)
    if marker is None:
        raise RuntimeError(f"No functional PASS marker; inspect {cache / f'{prefix}_result.log'}")
    if not args.core_rom:
        for wait in ("startup", "settle"):
            if f"SIMULATION ONLY: {wait} wait=2000 cycles" not in output:
                raise RuntimeError(f"Expected 2000-cycle {wait} confirmation missing")
    print(marker.group(), flush=True)


if __name__ == "__main__":
    main()
