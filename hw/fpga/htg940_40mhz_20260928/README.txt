Active HTG940 board RTL overlay
==============================

This directory is NOT an old build output or a separate FPGA design.
The historical directory name is retained to preserve the working build flow.

htg940_board_top.sv and htg940_entropy_uart.sv are the active replacements for
the corresponding files in ../board/. The dual-ILA runner selects these files
after the initial project is generated.

The board-top implements physical IO, UART control/log connections and
subsystem reset control for the 40 MHz HTG940 configuration.
Other board components remain in ../board/.

Start the full build through ../htg940/run_full.tcl, not this directory.
See ../htg940/README.txt for preparation steps, firmware inputs and build command.
