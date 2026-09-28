# ============================================================
# VCK190 FMCP2 - HTG USB2 ULPI
# VADJ_FMC = 1.5 V
# ============================================================

# ULPI 60 MHz clock
# HTG: MIO52_USB_CLK -> FMC LA00_CC_P
set_property PACKAGE_PIN BC13 [get_ports USB_ULPI_CLK]
set_property IOSTANDARD LVCMOS15 [get_ports USB_ULPI_CLK]

# ULPI DATA[7:0]

# MIO56_USB_D0 -> LA08_P
set_property PACKAGE_PIN AV15 [get_ports {USB_ULPI_DATA[0]}]

# MIO57_USB_D1 -> LA12_P
set_property PACKAGE_PIN BB11 [get_ports {USB_ULPI_DATA[1]}]

# MIO54_USB_D2 -> LA05_P
set_property PACKAGE_PIN AY14 [get_ports {USB_ULPI_DATA[2]}]

# MIO59_USB_D3 -> LA16_P
set_property PACKAGE_PIN AV11 [get_ports {USB_ULPI_DATA[3]}]

# MIO60_USB_D4 -> LA20_P
set_property PACKAGE_PIN AP15 [get_ports {USB_ULPI_DATA[4]}]

# MIO61_USB_D5 -> LA22_P
set_property PACKAGE_PIN AP11 [get_ports {USB_ULPI_DATA[5]}]

# MIO62_USB_D6 -> LA09_P
set_property PACKAGE_PIN BD15 [get_ports {USB_ULPI_DATA[6]}]

# MIO63_USB_D7 -> LA13_P
set_property PACKAGE_PIN BB15 [get_ports {USB_ULPI_DATA[7]}]

set_property IOSTANDARD LVCMOS15 [get_ports {USB_ULPI_DATA[*]}]

# ULPI control

# MIO53_USB_DIR -> LA03_P
set_property PACKAGE_PIN BE11 [get_ports USB_ULPI_DIR]

# MIO55_USB_NXT -> LA01_CC_P
set_property PACKAGE_PIN AW12 [get_ports USB_ULPI_NXT]

# MIO58_USB_STP -> LA04_P
set_property PACKAGE_PIN BF11 [get_ports USB_ULPI_STP]

set_property IOSTANDARD LVCMOS15 [get_ports USB_ULPI_DIR]
set_property IOSTANDARD LVCMOS15 [get_ports USB_ULPI_NXT]
set_property IOSTANDARD LVCMOS15 [get_ports USB_ULPI_STP]

# HTG USB3320 supplies 60 MHz ULPI clock
create_clock -name usb_ulpi_clk -period 16.667 [get_ports USB_ULPI_CLK]
