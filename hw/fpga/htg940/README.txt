HTG940 dual-MCU source integration
=================================

Repository: faydn23/caliptra-mcu-sw
Branch: htg940_dual_mcu_shared_usb
Board: HiTech Global HTG-940, XCVU13P-FHGB2104-3-E

Start with ../README.md for the block diagram, build command, complete
address map, external firmware inputs and three-ROM patching instructions.
The diagram source is dual_mcu_block_diagram.svg.

Select DUAL_MCU FORCE_ULPI_MODE explicitly with a fresh
BUILD_NAME=build_full_<suffix>. Neither option is enabled by default.
MCU0/MCI0 own DEV0 and shared hub/PHY initialization. MCU1/MCI1 form the
SoC controller for DEV1. One Caliptra Core, one USB compound/hub/PIE,
one external USB3320 PHY and the existing OTP/lifecycle/I3C hardware remain.
The dual-MCU generator does not alter USB/ULPI sources or mode selection.

MCU1 has its own memories and reset/halt loops. Its MCI observes real
shared lifecycle/OTP status without driving shared initialization/reset.
Both pairs use the common AXI fabric concurrently. Ownership is a firmware
contract, not an AXI permission boundary. No coordinated MCU firmware is
provided by this RTL-only change.

New windows:
  MCI1:     0xA9000000, 16 MiB
  MCU1 ROM: 0xB0060000, 128 KiB (MCU1 reset vector)
All existing windows are preserved. MCU1 AXI USER is 2; MCI1 SoC USER is 1.

Prepare a fresh recursive clone:
  python3 hw/fpga/htg940/prepare_sources.py --apply
  python3 hw/fpga/htg940/prepare_sources.py --check

The full-build entry point run_full.tcl runs the pin/patch check.
submodule_pins.json and submodule_patches/ preserve the required source
selection without publishing changes to dependency repositories.
Do not run submodule update again after applying those patches.

Source baselines:
  Caliptra-SS: 164dfbd68c77f566e38039b34b127de26c13f8ff
  Core: f9bc5ab97b885b5e31ccb062eca16634a8e61b5a
  USB2: 97aa9616f50d6adfb17e45053d1f16feb44792d7
Recursive pins and patch hashes in submodule_pins.json are authoritative.
FPGA_VERSION remains the frozen snapshot value 52a124ef; it is not the
commit ID or proof of provenance of this new branch.

Build inputs are external, writable firmware-directory files:
  caliptra_rom.bin: 98304 bytes
  mcu_rom.bin: 131072 bytes (MCU0)
  flash_image.bin: payload fitting the 2 MiB flash memory
MEM/COE conversion occurs in that directory. Generated outputs and firmware
binaries are excluded from Git.

MCU1 ROM is initially zero-filled and is NOT bootable firmware.
Before programming, use ../htg940_update_roms.py with matching new BIT/MMI:
  --core-rom <core.bin> --mcu-rom <mcu0.bin> --mcu1-rom <mcu1.bin>
First use --dry-run. MCU1 uses the unique mcu1_rom MMI instance; the
existing Core and MCU0 instance names are retained.

Focused source/integration tests:
  python3 -m unittest hw.fpga.htg940.test_fpga_integration
  python3 -m unittest discover -s hw/fpga/htg940_usb_min_ila -p 'test_*.py'

Optional board/UART timing test, with Vivado on PATH or VIVADO_BIN set:
  python3 -m unittest hw.fpga.htg940.test_board_timing
This tests the board wrapper with a stubbed system, not dual-MCU firmware.

simulate_usb_startup.py compiles the actual USB2 VHDL startup logic using
Vivado Simulator and a limited transaction-level PHY responder. It does
not execute MCU firmware or qualify electrical behavior or routed timing.
See its --help output for simulation-only arguments.

Dual-MCU source checks, SV elaboration and Vivado block-design/address-map
validation passed. SV elaboration treats unchanged USB VHDL as external.
Full dual-MCU synthesis, timing/resource closure, three-ROM MMI generation,
firmware coordination and actual USB enumeration/recovery remain unverified.
No FPGA build is submitted and no board is programmed by source preparation.
