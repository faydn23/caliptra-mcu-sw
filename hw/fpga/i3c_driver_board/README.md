# I3C reference files for HTG940 integration

This directory retains reference driver-board design files. It is not the
HTG940 connector or power-rail installation guide.

Use the [HTG940 FPGA guide](../README.md),
[HTG940 pin constraints](../constraints/htg940_board_nxp.xdc) and
[board wrapper](../board/htg940_board_top.sv) for the active integration.
Verify connector pinout, I/O voltage, external pull-ups and driver wiring
against the actual board/daughtercard schematics before connecting hardware.
Reference-board files alone do not qualify those connections.

The current FPGA profile uses a 60 MHz core and a separate 120 MHz I3C
clock. This does not qualify operation at the subsystem's higher upstream
I3C clock requirement. Dual-MCU integration does not add another I3C block
or change the existing I3C wiring.
