# SPDX-License-Identifier: Apache-2.0
# VCK190 FMCP1 pin allocation. Requires VADJ_FMC = 1.5 V.
# This is not a USB3320 daughter-card wiring or electrical qualification.
# Pin reference: https://github.com/fpgadeveloper/board-repo/blob/main/fmc-pinouts/boards/amd-xilinx/VCK190.json
# Clock cross-reference: https://github.com/Xilinx/vck190-base-trd/blob/eab35eee3b72fd90bc3a6473125ae36e59833f98/platforms/vivado/vck190_mipiRxSingle_hdmiTx/xdc/mipi_vck190.xdc

set_property PACKAGE_PIN BD23 [get_ports USB_ULPI_CLK]
set_property PACKAGE_PIN BC23 [get_ports {USB_ULPI_DATA[0]}]
set_property PACKAGE_PIN BD22 [get_ports {USB_ULPI_DATA[1]}]
set_property PACKAGE_PIN AW24 [get_ports {USB_ULPI_DATA[2]}]
set_property PACKAGE_PIN AY25 [get_ports {USB_ULPI_DATA[3]}]
set_property PACKAGE_PIN AV22 [get_ports {USB_ULPI_DATA[4]}]
set_property PACKAGE_PIN AW21 [get_ports {USB_ULPI_DATA[5]}]
set_property PACKAGE_PIN AU21 [get_ports {USB_ULPI_DATA[6]}]
set_property PACKAGE_PIN AV21 [get_ports {USB_ULPI_DATA[7]}]
set_property PACKAGE_PIN BF24 [get_ports USB_ULPI_DIR]
set_property PACKAGE_PIN BG23 [get_ports USB_ULPI_NXT]
set_property PACKAGE_PIN BC20 [get_ports USB_ULPI_STP]
set_property PACKAGE_PIN BD20 [get_ports USB_VBUS_VALID]
set_property PACKAGE_PIN BC25 [get_ports USB_DEV1_IRQ]
set_property PACKAGE_PIN BD25 [get_ports USB_DEV1_FIQ]
set_property IOSTANDARD LVCMOS15 [get_ports USB_*]

create_clock -name usb_ulpi_clk -period 16.667 [get_ports USB_ULPI_CLK]
