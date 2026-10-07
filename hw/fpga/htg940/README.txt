HTG940 full-system FPGA build snapshot
======================================

This folder supplements the normal caliptra-mcu-sw repository structure.
Existing software, documentation, and recursive Git submodules are preserved.
Only the required untracked HTG940 sources/scripts were added; previous test
directories, build products, logs, backup files and waveform dumps were not.

Profile:
  XCVU13P, 40 MHz core, full Caliptra core/crypto, MCU, USB and dual ILAs.
  USB2 commit: 87a1a3789604dd5a611693a6ba97fff871498593.
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

For a fresh clone:
  git submodule update --init --recursive
  python3 hw/fpga/htg940/prepare_sources.py --apply

If a pinned commit is missing, the helper prints the exact fetch command.
Fetch that commit and rerun --apply. The helper refuses to switch a dirty
submodule or apply a conflicting patch; it does not discard local changes.
Do not run submodule update again after preparation: it can return USB2 to
the older gitlink recorded in the parent Caliptra-SS commit.

Check the existing prepared copy:
  python3 hw/fpga/htg940/prepare_sources.py --check
The full-build entry point also runs this check before project generation.

Build ONLY after approval:
  Supply a writable firmware directory containing:
    caliptra_rom.bin  98304 bytes
    mcu_rom.bin       131072 bytes
    flash_image.bin  flash payload for the 2 MiB firmware memory
  Without FW_IMAGE_DIR, the runner uses this folder's local firmware/ directory.
  Do not substitute a runtime payload for either ROM.

  cd hw/fpga
  submit --gui --memory 128 --name htg940_clean_full \
    --project caliptra.fe.caliptra \
    --licenses Synopsys_Vivado_Bundle \
    vivado -mode batch -log htg940_clean_full.log \
    -journal htg940_clean_full.jou -source "$PWD/htg940/run_full.tcl" \
    -tclargs BUILD_NAME=build_full_clean FW_IMAGE_DIR=/path/to/firmware IMPLEMENT

Expected outputs:
  hw/fpga/htg940_usb_min_ila/build_full_clean/
    caliptra_htg940_project.runs/impl_1/htg940_board_top.bit
    caliptra_htg940_project.runs/impl_1/htg940_usb_dual_ila.ltx
    caliptra_htg940_project.runs/impl_1/htg940_board_top.mmi

Use a different BUILD_NAME=build_full_<suffix> for another fresh build.
The runner refuses to overwrite an existing output.
The explicit firmware override avoids dependencies on ignored target/ files or
another workspace. ROM MEM and flash COE files are regenerated in the writable
firmware directory from the supplied BINs.

GitHub handoff:
Branch: htg940-caliptra-usb-recovery in faydn23/caliptra-mcu-sw.
The branch includes HTG940 scripts, the source overlay, submodule patches, pins
and documentation. Uncommitted submodule changes are reconstructed by the
documented preparation step; they are not carried by a parent gitlink alone.
Firmware binaries, local provenance manifests and generated BIT/DCP/XPR/log
outputs are excluded from the new commit.

Focused tests:
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
