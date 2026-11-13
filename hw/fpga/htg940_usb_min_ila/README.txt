HTG940 full-build and dual-ILA support scripts
============================================

This directory is NOT a separate MCU-only design or an old build output.
The historical "usb_min_ila" name is retained to preserve the working flow.
The prepared entry point selects the FULL MCU + Caliptra core/crypto + USB
profile, with two ILAs and a 60 MHz core clock.
The November 5 source update uses SS main 164dfbd6 with the same USB2/core
pins and probe layout as the SS984 baseline. The obsolete subsystem SPI
host/UART connections are removed; board entropy UART is unchanged.
The subsystem clock is now 60 MHz, matching upstream's minimum without
I3C. Board UART and debug-hub settings follow that frequency; PHY reset
still holds for 10 ms. The external ULPI clock remains 60 MHz.
The 120 MHz I3C clock is derived through a second clock wizard so the core
is exactly 60 MHz rather than a rounded-down shared-MMCM output. Both lock
signals gate reset release, and BD validation checks the generated rates.
The legacy htg940_40mhz_20260928 board copies are no longer selected.
RESUME/RESTART_SYNTH reject old profiles; use a fresh 60 MHz build name.
Timing closure, actual PHY startup and USB operation still need validation.

Forced-ULPI A/B diagnostic
-------------------------
Add FORCE_ULPI_MODE and a separate BUILD_NAME=build_full_<suffix> to the
runner arguments. Only the generated compound architecture is changed:
the hub mode output is disconnected and the shared usbreg_phy_mode is tied
to 1, including during reset. The synchronizer passes this mode directly
to phy_mode, selecting the external ULPI clock in normal (non-scan) mode.
Without the flag, the existing register-controlled behavior is preserved.
Original USB2/SS sources, reset logic, register-access handshakes, clock
frequencies and ILA layout are unchanged. The core ILA mode probe sees the
forced effective mode; hub register bit 31 readback still reflects software.
htg_phy_mode.txt records the generated profile. RESUME/RESTART_SYNTH must
use the same FORCE_ULPI_MODE selection; old projects without a marker are
treated as register-controlled. Never reuse an existing build for the A/B.
This is not a timing fix or a verified hardware recovery fix.

For source snapshots without Git metadata, invoke run_dual_ila.tcl directly
with VERSION=52a124ef and an explicit FW_IMAGE_DIR. VERSION is the frozen
FPGA identification value, not verification of the snapshot's commits.
The normal ../htg940/run_full.tcl entry retains its Git pin/patch checks.
Use identical MCU/Core ROM BINs and flash payload for both A/B images.

Prepared November 10 snapshot command (user submits; no job is launched by
source preparation):
  cd /home/furkanaydin/ws3/htg940_clean/caliptra-mcu-sw/hw/fpga
  submit --memory 168 --name htg940_force_ulpi_a5_60mhz \
    --project caliptra.fe.caliptra --licenses Synopsys_Vivado_Bundle \
    /home/cad/tools/synopsys/xilinx_vivado/2025.1_rel2/Vivado/bin/vivado \
    -mode batch -log htg940_force_ulpi_a5_60mhz.log \
    -journal htg940_force_ulpi_a5_60mhz.jou \
    -source "$PWD/htg940_usb_min_ila/run_dual_ila.tcl" \
    -tclargs VERSION=52a124ef FORCE_ULPI_MODE \
    BUILD_NAME=build_full_force_ulpi_a5_20261110 \
    FW_IMAGE_DIR="$PWD/htg940/firmware_force_ulpi_a5_20261110" IMPLEMENT

The dedicated firmware directory contains unchanged MCU/Core ROMs copied
from ws3/43_test_a5 and the previous firmware_minimal_ila_20261025 flash
payload. Generated MEM/COE files are confined to that dedicated directory.
The output BIT/LTX/MMI are under:
  build_full_force_ulpi_a5_20261110/caliptra_htg940_project.runs/impl_1/
The external PHY clock must be available for USB reset release. Do not
program an older LTX with the new BIT. Timing and actual scratch readback
remain hardware/build acceptance checks.

Software-selected ULPI startup experiment
----------------------------------------
Add SOFTWARE_ULPI_STARTUP and a new BUILD_NAME=build_full_<suffix>.
This is mutually exclusive with FORCE_ULPI_MODE. It is an ULPI-only
HTG940 experiment, not a general runtime UTMI/ULPI clock-switch controller.
The generated architecture asserts C_ULPI_SUPPORT and not C_UTMI_SUPPORT.
Original USB2/SS sources and both existing profiles are preserved.

The hub still owns ULPIDEBUG.PhyMode (bit 31); neither its output nor the
shared mode signal is forced. PIE clock is always the external ULPI clock,
so changing the software mode bit cannot switch clock sources.
The existing two-edge USB reset synchronizer is held in reset until
hresetn AND (PhyMode OR testmode) is high. Configuration/AHB registers
keep their existing subsystem resets, so firmware can select ULPI and
leave PHY_ACCESS pending while the USB clock/reset domain starts.
No new ready register, firmware changes, clock frequencies, I/O timing
exceptions, PHY pin reset changes or general clock-mux primitive are added.
The external PHY must supply its clock for USB reset release and progress.

The supported use is selecting ULPI during boot before USB transfers.
Clearing PhyMode reasserts the local USB reset; do not use it to switch
modes during active USB traffic. Firmware must retain bit 31 in subsequent
ULPIDEBUG writes. This is a proposed startup fix, not a proven root cause.
HDL simulation was explicitly skipped for this experiment at user request.
Source-generation checks do not prove scratch completion, timing closure,
enumeration or recovery; those remain build/hardware acceptance checks.

The core ILA appends htg_pie_reset_n (local reset request) and reset_n
(PIE-domain synchronized reset) after the existing schema probes.
PhyMode continues to show the software-requested mode. Use the new LTX.
htg_phy_mode.txt records SOFTWARE_ULPI_STARTUP; resume/restart must request
the same profile. Existing FORCED_ULPI builds and their outputs are not reused.

Prepared snapshot command (user submits; no job launched automatically):
  cd /home/furkanaydin/ws3/htg940_clean/caliptra-mcu-sw/hw/fpga
  submit --memory 168 --name htg940_sw_ulpi_a5_60mhz \
    --project caliptra.fe.caliptra --licenses Synopsys_Vivado_Bundle \
    /home/cad/tools/synopsys/xilinx_vivado/2025.1_rel2/Vivado/bin/vivado \
    -mode batch -log htg940_sw_ulpi_a5_60mhz.log \
    -journal htg940_sw_ulpi_a5_60mhz.jou \
    -source "$PWD/htg940_usb_min_ila/run_dual_ila.tcl" \
    -tclargs VERSION=52a124ef SOFTWARE_ULPI_STARTUP \
    BUILD_NAME=build_full_sw_ulpi_a5_20261110 \
    FW_IMAGE_DIR="$PWD/htg940/firmware_sw_ulpi_a5_20261110" IMPLEMENT

The dedicated firmware directory contains the exact MCU/Core ROM BINs
from ws3/45_test_a5_reset_disable_ulpi and the unchanged flash payload
from firmware_force_ulpi_a5_20261110. MEM/COE generation stays in this copy.
Compare against the forced-ULPI image with these same ROM BINs.
Outputs:
  build_full_sw_ulpi_a5_20261110/caliptra_htg940_project.runs/impl_1/
  htg940_board_top.bit, htg940_board_top.mmi, htg940_usb_dual_ila.ltx

Contents:
  run_dual_ila.tcl                 Project, synthesis and implementation flow
  add_dual_ila.tcl                 Dual-ILA insertion and hierarchy checks
  probe_schema.tcl                ULPI/core probe definitions
  prepare_debug_sources.tcl       Build-local RTL debug attributes
  isolate_dual_ila_constraints.tcl Build-local board/debug constraint setup
  prepare_dual_ila_constraints.py Saved-debug constraint filtering
  test_prepare_dual_ila_constraints.py Focused constraint-filter tests

Start the full build through ../htg940/run_full.tcl.
See ../htg940/README.txt for source preparation, firmware inputs and build command.

New build outputs are generated under build_full_<suffix>/ in this directory.
Those directories are ignored by Git and were not copied from the old workspace.
The former MCU-only preparation helpers are not included in this full-build copy;
do not invoke the MCU_USB_ONLY option.

Isolated routed timing optimization
----------------------------------
Run optimize_routed_timing.tcl with Vivado -mode batch -source and -tclargs
INPUT_ROUTED_DCP NEW_OUTPUT_DIRECTORY. The output directory must not exist.
This flow applies AggressiveExplore physical optimization followed by Explore
routing without changing clock definitions, I/O budgets or timing exceptions.
The source project, checkpoint and bitstream are preserved.

Baseline/candidate reports cover setup/hold, unconstrained paths, ULPI I/O,
clock interaction, CDC, DRC and routing. The candidate checkpoint is retained
even if setup/hold fails (exit 2, STATUS=TIMING_FAILED). Nonnegative setup/hold
only passes the slack gate: pulse width, constraints coverage, CDC, DRC and
routing still require review. No bitstream is generated by this diagnostic.
RTL simulation does not validate physical timing; board PHY identity, USB
enumeration and recovery must be checked before claiming a hardware fix.

Test the control flow with:
  python3 -m unittest discover -s hw/fpga/htg940_usb_min_ila -p 'test_*.py'

Explicitly authorized debug bitstream
------------------------------------
generate_debug_candidate.tcl accepts INPUT_ROUTED_DCP NEW_OUTPUT_DIRECTORY.
It preserves timing constraints and DRC severities, collects clock-mux fanin
and timing/CDC/DRC reports, then writes a TIMING_FAILED_DEBUG_ONLY BIT/MMI/LTX.
This is diagnostic output, NOT a timing-qualified fix. DRC errors still stop
generation. ROM contents are inherited from the checkpoint; supplied ROMs
must be patched and verified separately before comparing hardware results.
No programming is performed. Existing output directories are refused.

Minimal PHY-startup probes
-------------------------
Only two ILAs are inserted. The ULPI-clock ILA retains physical DATA RX/TX,
DIR/NXT/STP, output enable, motor state/reset, PHY request/address/direction,
readback/completion and low-power status. Internal arbitration, duplicate
synchronizer stages and unrelated register buses are no longer probed.

The core-clock ILA observes the active hub-owned PHY address/write data,
start/write/mode, synchronized completion/readback, reset and clock request.
Old DEV0 PHY registers are not used as a proxy for hub PHY transactions.
The synchronized divided external-ULPI-clock heartbeat and physical PHY
reset input/output are also probed on the core-clock ILA. The output probe
observes the FPGA drive signal, not reset voltage measured at the daughter
card. The input reset is sampled raw and may be asynchronous at an edge.
The heartbeat proves clock activity only while its subsystem reset is
released; a static heartbeat during reset does not prove a missing clock.
The ULPI ILA can stop during clock/reset startup; the core ILA is retained
specifically to observe that interval. Probe indices changed: always use
the LTX generated with the new BIT, never an older LTX.

For a persistent full build use ../htg940/run_minimal_ila_batch.sh with one
argument: an absolute shared firmware directory containing mcu_rom.bin,
caliptra_rom.bin and flash_image.bin. Submit it as a noninteractive batch job.
The script has no dependency on Copilot session paths. Logs go to
build_logs_minimal_ila_20261025/; outputs go to build_full_minimal_ila_20261025/.
Use a dedicated writable firmware copy: the standard build regenerates MEM/COE
files there. The script refuses to overwrite an existing build directory.
