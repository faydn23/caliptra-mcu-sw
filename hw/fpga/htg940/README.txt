HTG940 full-system FPGA build snapshot
======================================

This folder supplements the normal caliptra-mcu-sw repository structure.
Existing software, documentation, and recursive Git submodules are preserved.
Only the required untracked HTG940 sources/scripts were added; previous test
directories, build products, logs, backup files and waveform dumps were not.

Profile:
  XCVU13P, 60 MHz core, full Caliptra core/crypto, MCU, USB and dual ILAs.
  Caliptra-SS commit: 164dfbd68c77f566e38039b34b127de26c13f8ff (upstream main,
  resolved 2026-11-05). MCU baseline remains faydn23/caliptra-mcu-sw branch
  htg940-caliptra-usb-recovery at 1d79b4a636438d3bdfcf7b273e81ea4a93ae739a.
  Caliptra core commit: f9bc5ab97b885b5e31ccb062eca16634a8e61b5a.
  Nested submodules follow their parent's gitlinks, not individual main heads.
  Existing HTG940 patches are retained; the fuse workaround uses upstream's
  current fuse_addr semantics. Old BITs/ROM simulations predate this update
  and do not validate the new source baseline.
  The November update removes integrated SPI host/UART ports and parameters.
  Their previously disabled FPGA interfaces and AXI tie-offs are removed;
  the board entropy UART is a separate block and remains unchanged.
  Core/USB2 and all nested dependency pins are unchanged from October 28.
  The full profile now requests 60 MHz from the clock wizard, matching
  upstream's minimum subsystem frequency without I3C. The external ULPI
  clock remains 60 MHz. The dedicated FPGA I3C clock remains 120 MHz;
  this does not qualify operation at upstream's 333 MHz I3C requirement.
  The board UART clock parameter and debug-hub frequency follow the core.
  A second clock wizard derives 120 MHz I3C from the exact 60 MHz core;
  subsystem/controller reset waits for both clock generators to lock.
  BD validation rejects rounded output frequencies before synthesis.
  The PHY reset hold remains 10 ms (600000 cycles with a 20-bit counter).
  Firmware binaries are unchanged; cycle-counted ROM delays run 1.5 times
  faster than on the previous 40 MHz build. No RXCMD startup fix or timing
  closure is claimed until the new implementation and hardware are tested.
  Adams Bridge commit: 1d85b8e0df62cbb2f91228f68815f02295ac668a.
  I3C commit: 9a8a322582444fed63ae3fe9a86230f32b478375.
  USB2 commit: 97aa9616f50d6adfb17e45053d1f16feb44792d7 (requested upstream revision).
  This USB2 release requires USB_C_HUB_FIFO_SIZE=196 in the FPGA wrapper.
  Removed USB2 OTG/session ports are now removed from the upstream SS interface
  and FPGA instance. Upstream owns the unchanged wakeup and hub-control tie-offs.
  The generated SS register headers now match USB2 97aa961, including HUB CONTROL
  at 0x20001030. Firmware must be rebuilt with matching register definitions.
  Existing bitstreams and packaged build directories retain their original RTL;
  this SS/core migration requires a fresh build, not RESUME of an older project.
  Debug generation uses the new zero8 declaration anchor and explicitly encodes
  the ULPI state enum because upstream removed usb_pie_fpga. Use the LTX from
  this new build; old debug state labels/layouts must not be assumed compatible.
  Saved ILA/debug-hub clock constraints resolve nets from preserved hierarchy
  pins, not temporary net aliases introduced by Vivado debug insertion.
  The required USB2 patch keeps UTMI disabled and ULPI enabled for HTG940.
  FPGA_VERSION is frozen to 52a124ef, the parent snapshot's version.
  Firmware binaries are external inputs and are not committed to this branch.
  The existing local default MCU ROM is the earlier enumeration image, not the
  single-read diagnostic or the subsequently supplied final MCU ROM.

Submodule patches:
The working copy already includes the required tracked local changes in
Caliptra-SS, Caliptra RTL and USB2. A parent-repository commit alone would NOT
preserve dirty submodule contents. Therefore submodule_patches/ and
submodule_pins.json record those changes and their required base commits.
prepare_sources.py verifies or reapplies them without network access.

USB startup diagnostic simulation:
  Run with Vivado Simulator, without rebuilding/programming the FPGA:
    python3 hw/fpga/htg940/simulate_usb_startup.py \
      --vivado-bin /path/to/Vivado/bin --output /new/simulation/output
  Run from the repository root. The output directory must not already exist.
  The test compiles the real USB2 VHDL compound device, including hub AHB
  registers, synchronizer, reset/clock selection and USB engine. A simulation-
  local engine copy adds state-transition reports only; production RTL is
  unchanged. The test uses the current ULPI-only generics and a 60 MHz core/
  approximately 60 MHz ULPI clock, with ROM-style mode/start register writes.
  Four normal scenarios check all four USB3320 ID bytes and access completion:
  mode selected after PHY readiness, mode selected before PHY readiness,
  PHY clock held off until readiness, and a one-cycle post-reset DIR-low gap.
  A fifth, deliberately faulty PHY scenario withholds the post-reset RXCMD.
  It must leave the engine in state 0x05 and the first read pending with
  ULPIDEBUG=0x82000000. This demonstrates the observed failure mechanism, not
  why the real board fails to deliver/sample that RXCMD.
  The PHY is a limited transaction-level responder, not a vendor USB3320
  model. PHY readiness is delayed 10 us rather than the board's 10 ms hold;
  this tests ordering, not the electrical reset pulse specification.
  The test does not run Rust firmware, Caliptra-SS, AXI bridges, FPGA IOBUFs,
  or routed timing. It cannot validate clock-mux glitches, metastability,
  PHY electrical behavior, or the bitstream's timing violations. It also does
  not prove that register-driven clock selection is safe in physical hardware.
  Inspect xsim.log and usb_startup.wdb in the output directory.

Upstream-main FPGA integration:
  - ULPI DATA still uses eight explicit IOBUFs and the core TX-enable signal.
  - USB AXI user filtering remains disabled for HTG940 bring-up. The policy is
    now wired at the FPGA wrapper to the upstream subsystem policy ports.
  - Upstream SS ties wakeup inputs to 1/1 and hub-enable/self-powered to 0/1,
    matching the former FPGA input tie-offs; unused legacy ports are removed.
  - The new MCI ROM-patch SRAM has a dedicated 4 KiB, 39-bit (data + ECC) XPM RAM.
  - The build-local subsystem patch preserves the separate I3C clock/reset and
    CDC paths. All four privileged-user slots use synchronized straps, including
    upstream's repeated authorized users; zero is not added to the allowlist.
  - The spare FPGA I3C instance uses the new explicit AXI/filtering parameters,
    with its old disabled-filtering policy preserved and unused AHB inputs tied.
  - MCU parameter types are imported from css_mcu0_el2_pkg rather than redefined.
  - The explicit fuse access bounds and AES packed-array workaround are retained.
    The SHA512 ICCM lock gate is now supplied by upstream's iccm_hash_trigger;
    the equivalent old local SHA512 patch is no longer needed.
  Backups of the previous SS/core working-tree patches are retained in local
  Git stashes. No recursive submodule update is needed for this prepared copy.
  Git metadata was reconstructed on November 5 from the recorded commits,
  restoring only missing baseline files and preserving existing source files.
  Original pre-restoration stashes/history are not recovered. The restored
  source backup and pre-update diffs are in the local sibling directory
  ../../htg940_migration_backup_20261105 (relative to the repository root).

For a fresh clone:
  git submodule update --init --recursive
  python3 hw/fpga/htg940/prepare_sources.py --apply

If a pinned commit is missing, the helper prints the exact fetch command.
Fetch that commit and rerun --apply. The helper refuses to switch a dirty
submodule or apply a conflicting patch; it does not discard local changes.
Do not run submodule update again after preparation: it can discard the
prepared dependency selection or conflict with the applied local patches.

Check the existing prepared copy:
  python3 hw/fpga/htg940/prepare_sources.py --check
The full-build entry point also runs this check before project generation.

Board clock regression:
  VIVADO_BIN=/path/to/Vivado/bin python3 -m unittest discover \
    -s hw/fpga/htg940 -p 'test_*.py'
  test_board_timing.py compiles the actual board/UART/control/log RTL with
  a stubbed system BD. It verifies 600000 reset-hold cycles, approximately
  10 ms at 60 MHz, counter saturation, asynchronous reset assertion and
  UART request/response bytes against an independent 115200-baud waveform.
  This is not a full-system firmware or physical timing qualification.

Build ONLY after approval:
  Supply a writable firmware directory containing:
    caliptra_rom.bin  98304 bytes
    mcu_rom.bin       131072 bytes
    flash_image.bin  flash payload for the 2 MiB firmware memory
  Without FW_IMAGE_DIR, the runner uses this folder's local firmware/ directory.
  Do not substitute a runtime payload for either ROM.

  cd hw/fpga
  submit --memory 168 --name htg940_ss164dfbd6_60mhz \
    --project caliptra.fe.caliptra \
    --licenses Synopsys_Vivado_Bundle \
    vivado -mode batch -log htg940_ss164dfbd6_60mhz.log \
    -journal htg940_ss164dfbd6_60mhz.jou -source "$PWD/htg940/run_full.tcl" \
    -tclargs BUILD_NAME=build_full_ss164dfbd6_60mhz_20261105 \
    FW_IMAGE_DIR="$PWD/htg940/firmware_minimal_ila_20261025" IMPLEMENT

Expected outputs:
  hw/fpga/htg940_usb_min_ila/build_full_ss164dfbd6_60mhz_20261105/
    caliptra_htg940_project.runs/impl_1/htg940_board_top.bit
    caliptra_htg940_project.runs/impl_1/htg940_usb_dual_ila.ltx
    caliptra_htg940_project.runs/impl_1/htg940_board_top.mmi

Use a different BUILD_NAME=build_full_<suffix> for another fresh build.
The runner refuses to overwrite an existing output.
The explicit firmware override avoids dependencies on ignored target/ files or
another workspace. ROM MEM and flash COE files are regenerated in the writable
firmware directory from the supplied BINs.

GitHub handoff:
Branch: htg940_usb_ulpi_forced in faydn23/caliptra-mcu-sw.
Based on htg940-caliptra-usb-recovery with the current 60 MHz HTG940 sources.
The parent gitlink records Caliptra-SS 164dfbd6; nested pins and local patches
are recorded in submodule_pins.json and submodule_patches/.
The optional FORCE_ULPI_MODE profile forces shared ULPI mode from reset.
The separate SOFTWARE_ULPI_STARTUP profile retains software mode selection,
uses the external ULPI clock directly and holds the local USB reset until
software selects ULPI (or scan testmode bypasses that requirement).
Neither profile is enabled by default. See ../htg940_usb_min_ila/README.txt
for profile flags, distinct build names, resume guards and firmware inputs.
The branch contains source code only: no local firmware BINs, build projects,
bitstreams, probes, logs or implementation archives are included.
The branch includes HTG940 scripts, the source overlay, submodule patches, pins
and documentation. Uncommitted submodule changes are reconstructed by the
documented preparation step; they are not carried by a parent gitlink alone.
Firmware binaries, local provenance manifests and generated BIT/DCP/XPR/log
outputs are excluded from the new commit.

Focused tests:
  python3 -m unittest discover -s hw/fpga/htg940 -p 'test_*.py'
  cd hw/fpga/htg940_usb_min_ila
  python3 -m unittest test_prepare_dual_ila_constraints.py

Qualification:
This preserves current local source changes, not a byte-identical reconstruction
of the October 2 bitstream. That build completed but did not close timing.
No new Vivado synthesis/implementation or hardware programming was performed
when preparing this handoff. Installed Vivado/licenses/scheduler are external
tools. Full recovery with the supplied final ROMs remains unverified. The
diagnostic PHY-read simulation pass does not establish full recovery success.

Preparation validation passed:
  - Recursive submodule commit/patch checks
  - Clean-base reconstruction of all three submodule patches (five files)
  - Full source-selection dry run (1042 selections), ROM conversion and
    subsystem patch dry run
  - Full-profile entry point and bundled firmware argument forwarding
  - Firmware binary hashes match the original full-build inputs
  - Three focused dual-ILA constraint unit tests
  - Repository layout, independent Git objects and input Git visibility
These checks are not a substitute for Vivado synthesis or timing qualification.

Earlier 6af59219 upstream-main migration validation:
  - Revalidated dependency pins and regenerated patch checksums
  - Source-collection dry run, ROM conversions, I3C patch and debug-source generation
  - SystemVerilog elaboration of the FPGA wrapper and upstream synthesis source
    list with Vivado-compatible hierarchical constants and processor headers
  The standalone elaborator excludes unused verification/legacy sources and
  leaves Xilinx primitives and the mixed-language USB VHDL entity as black boxes.
  This does not verify Vivado IP packaging, mixed-language binding or timing.
  These earlier checks do not qualify later dependency revisions.

e6090e8c migration validation:
  - 14 integration and 6 dual-ILA constraint unit tests passed.
  - Dependency pins and all three patch checksums/reconstructions passed.
  - FPGA source-collection dry run selected 929 files, checked file existence,
    converted ROMs, and generated patched SS, hardware wrapper and USB debug RTL.
    Vivado project/property calls were mocked; this is not HDL compilation.
  - SS default/FPGA hub capacity and HUB CONTROL header/RDL addresses agree.
  - Core and Adams Bridge checkouts match their upstream parent gitlinks.
  No new HDL elaboration, Vivado synthesis/implementation, timing qualification
  or hardware test has been performed for this migration.
