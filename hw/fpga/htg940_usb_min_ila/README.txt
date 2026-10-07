HTG940 full-build and dual-ILA support scripts
============================================

This directory is NOT a separate MCU-only design or an old build output.
The historical "usb_min_ila" name is retained to preserve the working flow.
The prepared entry point selects the FULL MCU + Caliptra core/crypto + USB
profile, with two ILAs and a 40 MHz core clock.

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
