HTG940 build profiles and dual-ILA reference
==========================================

This historical directory name does not select an MCU-only design.
The supported flow is the full HTG940 system at 60 MHz core, external
60 MHz ULPI and separately generated 120 MHz I3C, with two ILAs.
Start with ../README.md for the diagram, current build command, address
map and required external firmware inputs.

Current branch: htg940_dual_mcu_shared_usb
Current dual-MCU build selection: DUAL_MCU FORCE_ULPI_MODE
Both flags must be passed explicitly; neither is enabled by default.

Dual-MCU profile
----------------
DUAL_MCU adds MCU1/MCI1 for DEV1, keeping MCU0/MCI0 for DEV0 and common
hub/PHY initialization. There is one Caliptra Core, one USB compound,
one hub/PIE, one USB3320 PHY and the existing shared OTP/lifecycle/I3C.
The dual-MCU generator changes no USB/ULPI sources or mode selection.

Generated subsystem instances:
  mcu0 / mci0
  soc_controller.mcu1 / soc_controller.mci1
MCU1 has private CPU memories, MCI SRAM, ROM-patch SRAM, mailboxes and
local reset/halt loops. It receives DEV1's USB IRQ. Its MCI observes real
shared lifecycle/OTP completion/status without driving shared control.
MCU1 JTAG is inactive. No additional MCU1 UART logging is introduced.

MCU1 IFU/LSU/system AXI managers connect to S05/S06/S07 of the common
arbitrated main fabric. That fabric has 8 inputs and 16 outputs. A 1-to-3
M15 branch serves firmware flash, MCI1 and MCU1 ROM: SmartConnect above
16 outputs forces a single-manager topology. The USB bridge is unchanged.

Existing addresses are preserved. Added windows:
  MCI1:     0xA9000000 .. 0xA9FFFFFF
  MCU1 ROM: 0xB0060000 .. 0xB007FFFF (also MCU1's reset vector)
MCU1 AXI USER is 2. MCI1 SoC-configuration USER is 1.

Shared USB ownership is a firmware contract, not an AXI permission
boundary. MCU0 must initialize common hardware and leave DEV1 available.
MCU1 must use its own MCI base/reset vector and must not repeat shared
hub/PHY initialization. Coordinated firmware is not supplied here.

MCU1 ROM is zero-filled as a patchable MMI placeholder, not a boot image.
Before programming, use ../htg940_update_roms.py with matching new BIT/MMI
and --core-rom <core.bin> --mcu-rom <mcu0.bin> --mcu1-rom <mcu1.bin>.
MCU1 uses mcu1_rom; existing Core and MCU0 MMI names are retained.

Full build entry point
---------------------
Use ../htg940/run_full.tcl after preparing the pinned dependencies.
From the repository root, with Vivado on PATH:

  vivado -mode batch -source hw/fpga/htg940/run_full.tcl \
    -tclargs DUAL_MCU FORCE_ULPI_MODE \
    BUILD_NAME=build_full_dual_mcu_shared_usb \
    FW_IMAGE_DIR=/absolute/path/to/writable/firmware IMPLEMENT

The firmware directory must contain caliptra_rom.bin (98304 bytes),
mcu_rom.bin (131072 bytes, MCU0) and flash_image.bin (at most 2 MiB).
MEM/COE generation writes into that directory. Firmware and generated
FPGA outputs are not committed.

Always use a fresh BUILD_NAME=build_full_<suffix>. DUAL_MCU is not
compatible with MCU_USB_ONLY. MCU-only preparation helpers are not part
of this source handoff. Keep the full-system profile.

Without DUAL_MCU, the existing single-MCU build is preserved.
run_dual_ila.tcl is the low-level entry point; for a Gitless source
snapshot it accepts VERSION=<1-to-8 hexadecimal digits>. The frozen
snapshot value 52a124ef identifies the old FPGA version, not the new
branch commit or provenance. Use run_full.tcl for a prepared Git clone.

Outputs are under build_full_<suffix>/caliptra_htg940_project.runs/impl_1/:
  htg940_board_top.bit
  htg940_board_top.mmi
  htg940_usb_dual_ila.ltx
The full build must be submitted by the user. Source preparation does
not submit a scheduler job or program the FPGA.

Resume/restart guards
---------------------
RESUME and RESTART_SYNTH preserve existing outputs and require matching
60 MHz clock, ULPI profile and MCU count. htg_phy_mode.txt records PHY
selection; htg_mcu_count.txt records the added pair. Missing MCU-count
markers mean one MCU. Never resume an old build as a dual-MCU project.
RESTART_SYNTH also requires the explicit HTG_SYNTH_RESTART_ARCHIVE path.
RESTART_IMPL requires RESUME IMPLEMENT.

Forced-ULPI profile (current)
----------------------------
FORCE_ULPI_MODE modifies only generated compound RTL. The hub's mode
output is disconnected and usbreg_phy_mode is tied to 1 from reset.
Existing clock/reset logic and mode-register readback remain unchanged.
The core ILA mode probe sees the forced effective mode. The hub register
bit still reports software's requested value, not that forced connection.
This profile requires a separate full BUILD_NAME.
Without either ULPI flag, the existing register-controlled mode remains.

Software-selected startup experiment (optional)
-----------------------------------------------
SOFTWARE_ULPI_STARTUP is mutually exclusive with FORCE_ULPI_MODE.
It requires ULPI-only hardware, with C_ULPI_SUPPORT enabled and UTMI off.
The hub retains software control of ULPIDEBUG.PhyMode bit 31.
PIE uses the external ULPI clock directly. Its two-edge local reset
synchronizer is held until hresetn AND (PhyMode OR testmode) is high.
Configuration/AHB register resets and physical PHY reset are unchanged.
testmode is the existing scan/DFT input, not a USB scratch-test mode.

This experiment supports selecting ULPI at boot, not mode switching
during active transfers. Clearing PhyMode reasserts local USB reset.
Firmware must retain bit 31 in subsequent ULPIDEBUG writes. The PHY
must provide the external clock for reset release and progress.
The core ILA appends htg_pie_reset_n and the synchronized PIE reset.
This does not prove a root cause, safe arbitrary clock switching,
enumeration or recovery. It is not the selected forced-ULPI profile.

Debug and optional timing tools
-------------------------------
Only two ILAs are inserted. The ULPI-clock ILA covers physical data,
DIR/NXT/STP, output enable, PHY transaction state and access completion.
The core ILA covers common hub PHY controls, synchronized readback,
clock/reset requests, external-clock heartbeat and PHY reset signals.
The heartbeat only proves activity while its subsystem reset is released.
FPGA reset-output probing does not measure voltage at the daughtercard.
Use the new LTX matching the programmed BIT; old probe indices differ.

optimize_routed_timing.tcl accepts INPUT_ROUTED_DCP NEW_OUTPUT_DIRECTORY.
It preserves the source and timing constraints, applies physical/routing
optimization and collects setup/hold/CDC/DRC/clock/I/O reports.
It generates no bitstream. Passing slack alone is not full qualification.
The output directory must not exist; failing timing retains reports and
the candidate checkpoint with a failing status.

generate_debug_candidate.tcl accepts the same two arguments. It can write
a TIMING_FAILED_DEBUG_ONLY BIT/MMI/LTX from the supplied checkpoint,
without relaxing timing constraints or DRC severities. Such output is
diagnostic only and is not a timing-qualified fix. ROM contents are
inherited and must be patched/verified separately. It does not program
hardware.

Checks
-------
  python3 -m unittest hw.fpga.htg940.test_fpga_integration
  python3 -m unittest discover -s hw/fpga/htg940_usb_min_ila -p 'test_*.py'

Dual-MCU source tests, SV elaboration and Vivado block-design/address-map
checks passed. SV elaboration treats unchanged USB VHDL as external.
Full dual-MCU synthesis, timing/resource closure, three-ROM MMI generation
and actual USB enumeration/recovery require separate validation.
