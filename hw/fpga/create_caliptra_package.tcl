# Licensed under the Apache-2.0 license

# Create a project to package Caliptra.
# Packaging Caliptra allows Vivado to recognize the APB bus as an endpoint for the memory map.
create_project caliptra_package_project $outputDir -part $PART
if {$BOARD eq "VCK190"} {
  set_property board_part xilinx.com:vck190:part0:3.1 [current_project]
}

# TODO: Check these SS defines: https://github.com/chipsalliance/caliptra-mcu-sw/issues/368
lappend VERILOG_OPTIONS TECH_SPECIFIC_ICG
lappend VERILOG_OPTIONS USER_ICG=fpga_fake_icg
lappend VERILOG_OPTIONS RV_FPGA_OPTIMIZE
lappend VERILOG_OPTIONS css_mcu0_TEC_RV_ICG=css_mcu0_clockhdr
lappend VERILOG_OPTIONS TECH_SPECIFIC_EC_RV_ICG
lappend VERILOG_OPTIONS css_mcu0_USER_EC_RV_ICG=mcu_clockhdr
lappend VERILOG_OPTIONS css_mcu0_RV_BUILD_AXI4
lappend VERILOG_OPTIONS MCU_RV_BUILD_AXI4
lappend VERILOG_OPTIONS I3C_USE_AXI
# TODO: This AXI_ID_WIDTH is probably way larger than needed.
lappend VERILOG_OPTIONS AXI_ID_WIDTH=19 AXI_USER_WIDTH=32 AXI_DATA_WIDTH=32 AXI_ADDR_WIDTH=32
# Might be removed in newer RTL? TLUL has compilation failure
lappend VERILOG_OPTIONS CALIPTRA_AXI_ID_WIDTH=19 CALIPTRA_AXI_USER_WIDTH=32
# Try using xilinx primitives
lappend VERILOG_OPTIONS CALIPTRA_PRIM_DEFAULT_IMPL=caliptra_prim_pkg::ImplXilinx

set_property verilog_define $VERILOG_OPTIONS [current_fileset]
puts "\n\nVERILOG DEFINES: [get_property verilog_define [current_fileset]]"

# Add Caliptra VEER Headers
add_files $caliptrartlDir/src/riscv_core/veer_el2/rtl/el2_param.vh
add_files $caliptrartlDir/src/riscv_core/veer_el2/rtl/pic_map_auto.h
add_files $caliptrartlDir/src/riscv_core/veer_el2/rtl/el2_pdef.vh
add_files [ glob $caliptrartlDir/src/riscv_core/veer_el2/rtl/include/*.svh ]
add_files [ glob $caliptrartlDir/src/riscv_core/veer_el2/rtl/include/*.sv ]

# Add Caliptra VEER sources
add_files [ glob $caliptrartlDir/src/riscv_core/veer_el2/rtl/*.sv ]
add_files [ glob $caliptrartlDir/src/riscv_core/veer_el2/rtl/*/*.sv ]
add_files [ glob $caliptrartlDir/src/riscv_core/veer_el2/rtl/*/*.v ]

# Add Adam's Bridge
#source adams-bridge-files.tcl #fa
# Add Adam's Bridge (or stub for faster builds)
if {$STUB_ADAMS_BRIDGE eq "TRUE"} {
  puts "STUB_ADAMS_BRIDGE=TRUE: skipping full adams-bridge (~354 files), using stub"
  lappend VERILOG_OPTIONS STUB_ADAMS_BRIDGE
  set_property verilog_define $VERILOG_OPTIONS [current_fileset]
  source adams-bridge-files-stub.tcl
} else {
  source adams-bridge-files.tcl
}


# Add Caliptra headers and packages
add_files [ glob $caliptrartlDir/src/*/rtl/*.svh ]
add_files [ glob $caliptrartlDir/src/integration/rtl/caliptra_reg_ss/*.svh ]
add_files [ glob $caliptrartlDir/src/*/rtl/*_pkg.sv ]
# Add Caliptra sources
add_files [ glob $caliptrartlDir/src/*/rtl/*.sv ]
add_files [ glob $caliptrartlDir/src/*/rtl/*.v ]

# Add ss RTL
# Add MCU VEER Headers
add_files $ssrtlDir/src/riscv_core/veer_el2/rtl/defines/css_mcu0_pic_map_auto.h
add_files $ssrtlDir/src/riscv_core/veer_el2/rtl/defines/css_mcu0_el2_pdef.vh
add_files $ssrtlDir/src/riscv_core/veer_el2/rtl/defines/css_mcu0_el2_param.vh
add_files $ssrtlDir/src/riscv_core/veer_el2/rtl/defines/css_mcu0_common_defines.vh
add_files [ glob $ssrtlDir/src/riscv_core/veer_el2/rtl/design/include/*.svh ]
# For SS EL2_IC_DATA_SRAM is defined in testbench
add_files [ glob $ssrtlDir/src/riscv_core/veer_el2/tb/icache_macros.svh ]
# Add MCU VEER sources
add_files [ glob $ssrtlDir/src/riscv_core/veer_el2/rtl/design/*.sv ]
add_files [ glob $ssrtlDir/src/riscv_core/veer_el2/rtl/design/*/*.sv ]
add_files [ glob $ssrtlDir/src/riscv_core/veer_el2/rtl/design/*/*.v ]
# OTP
add_files [ glob $ssrtlDir/src/fuse_ctrl/rtl/*.sv ]
# OTP memory
add_files $ssrtlDir/src/fuse_ctrl/data/otp-img.2048.vmem
set_property file_type {Memory Initialization Files} [get_files $ssrtlDir/src/fuse_ctrl/data/otp-img.2048.vmem]
# OTP from testbench
add_files $ssrtlDir/src/integration/testbench/prim_generic_otp.sv
# SS IPs
add_files [ glob $ssrtlDir/src/*/rtl/*.svh ]
add_files [ glob $ssrtlDir/src/*/rtl/*.sv ]

# USB2 VHDL + SV RTL required by USB-enabled caliptra_ss_top

# usb_lib
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_general_subcmp_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_subcmp_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_fs_emb_dev_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_configuration_subcmp_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/ip_xxx_3511.e.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/ip_xxx_3511_cmp_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_cfg_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_configuration_app_cmsis_dap_jtag_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_ep_config_hub_cmsis_dap_jtag_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_ep_config_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_fs_hub_pkg.p.vhdl

add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_ahb_master.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_ahb_slave.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_clkrec.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_dma.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_host_dma.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_host_pie.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_host_reg_if.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_host_sof_timer.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_host_synchronizer.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_pie.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_reg_if.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_rgen.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_sie.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_sieint.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_synchronizer.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_timers_sf.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_tx_sf_dpdm.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_upstreamled.m.vhdl

# lib_usb_ip_3511
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511_hs/INTERFACE/ip_xxx_3511_hs.e.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511_hs/INTERFACE/ip_xxx_3511_hs_cmp_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511_hs/STRUCTURE/ip_xxx_3511_hs_structure.a.vhdl

# lib_usb_ip_3515
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3515_hs/INTERFACE/ip_xxx_3515_hs.e.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3515_hs/INTERFACE/ip_xxx_3515_hs_cmp_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3515_hs/STRUCTURE/ip_xxx_3515_hs_structure.a.vhdl

# lib_usb_ip_3516
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/ahb_dma_slave_cmp_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/ahb_dma_slave.m.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3516_hs_mem/INTERFACE/ip_xxx_3516_hs_mem.e.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3516_hs_mem/INTERFACE/ip_xxx_3516_hs_mem_cmp_pkg.p.vhdl
add_files $ssrtlDir/third_party/usb2/src/ip_xxx_3516_hs_mem/STRUCTURE/ip_xxx_3516_hs_mem_structure.a.vhdl

# SV wrappers
add_files $ssrtlDir/third_party/usb2/src/integration/rtl/axilite_to_ahb.sv
add_files $ssrtlDir/third_party/usb2/src/integration/rtl/axi_to_ahb.sv
add_files $ssrtlDir/third_party/usb2/src/integration/rtl/ip_xxx_3516_hs_mem_wrapper.sv

set usb_vhdl_files [list \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_general_subcmp_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_subcmp_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_fs_emb_dev_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_configuration_subcmp_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/ip_xxx_3511.e.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/ip_xxx_3511_cmp_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_cfg_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_configuration_app_cmsis_dap_jtag_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_ep_config_hub_cmsis_dap_jtag_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_ep_config_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/usb_fs_hub_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_ahb_master.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_ahb_slave.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_clkrec.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_dma.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_host_dma.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_host_pie.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_host_reg_if.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_host_sof_timer.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_host_synchronizer.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_pie.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_reg_if.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_rgen.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_sie.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_sieint.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_synchronizer.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_timers_sf.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_tx_sf_dpdm.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/usb_upstreamled.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511_hs/INTERFACE/ip_xxx_3511_hs.e.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511_hs/INTERFACE/ip_xxx_3511_hs_cmp_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511_hs/STRUCTURE/ip_xxx_3511_hs_structure.a.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3515_hs/INTERFACE/ip_xxx_3515_hs.e.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3515_hs/INTERFACE/ip_xxx_3515_hs_cmp_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3515_hs/STRUCTURE/ip_xxx_3515_hs_structure.a.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/INTERFACE/ahb_dma_slave_cmp_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3511/RTL/ahb_dma_slave.m.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3516_hs_mem/INTERFACE/ip_xxx_3516_hs_mem.e.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3516_hs_mem/INTERFACE/ip_xxx_3516_hs_mem_cmp_pkg.p.vhdl \
  $ssrtlDir/third_party/usb2/src/ip_xxx_3516_hs_mem/STRUCTURE/ip_xxx_3516_hs_mem_structure.a.vhdl \
]

foreach f $usb_vhdl_files {
    set obj [get_files $f]
    if {[llength $obj] == 0} {
        puts "ERROR: USB VHDL file not found in project: $f"
    } else {
        set_property library rtl $obj
        puts "USB LIB SET: $f -> [get_property library $obj]"
    }
}
puts "===== USB VHDL Library Check ====="
foreach f $usb_vhdl_files {
    puts "$f : [get_property library [get_files $f]]"
}

# I3C
set i3cDir $ssrtlDir/third_party/i3c-core
# Include headers and packages first
add_files [ glob $i3cDir/src/*.svh ]
add_files [ glob $i3cDir/src/libs/*.svh ]
add_files [ glob $i3cDir/src/*/*/*_pkg.sv ]

add_files [ glob $i3cDir/src/*/*_pkg.sv ]
add_files [ glob $i3cDir/src/*_pkg.sv ]
# Then the rest of the sv files
add_files [ glob $i3cDir/src/*/*/*.sv ]
add_files [ glob $i3cDir/src/*/*.sv ]
add_files [ glob $i3cDir/src/*.sv ]

# Remove unused spi_host files.
remove_files [ glob $caliptrartlDir/src/spi_host/rtl/*.sv ]

# Add FPGA specific sources
add_files [ glob $fpgaDir/src/*.sv]
add_files [ glob $fpgaDir/src/*.v]

# Replace RAM with FPGA block ram
#remove_files [ glob $caliptrartlDir/src/ecc/rtl/ecc_ram_tdp_file.sv ] #fa

# Replace RAM with FPGA block ram (skipped when ECC is stubbed — no RAM to replace)
if {$STUB_ECC eq "TRUE"} {
  puts "STUB_ECC=TRUE: removing full ECC RTL, using stub"
  lappend VERILOG_OPTIONS STUB_ECC
  set_property verilog_define $VERILOG_OPTIONS [current_fileset]
  remove_files [ glob $caliptrartlDir/src/ecc/rtl/*.sv ]
} else {
  remove_files [ glob $caliptrartlDir/src/ecc/rtl/ecc_ram_tdp_file.sv ]
}

# Replace caliptra_ss_top with version modified with faster I3C clocks
file copy [ glob $ssrtlDir/src/integration/rtl/caliptra_ss_top.sv ] $outputDir/caliptra_ss_top.sv
exec patch $outputDir/caliptra_ss_top.sv $fpgaDir/src/caliptra_ss_top.patch
remove_files [ glob $ssrtlDir/src/integration/rtl/caliptra_ss_top.sv ]
add_files $outputDir/caliptra_ss_top.sv

# Hack version to 2.1.1
file copy [ glob $caliptrartlDir/src/soc_ifc/rtl/soc_ifc_reg.sv ] $outputDir/soc_ifc_reg.sv
exec sed -i {s/\(CPTRA_HW_REV_ID.*16'h\)12/\1112/g} $outputDir/soc_ifc_reg.sv
remove_files [ glob $caliptrartlDir/src/soc_ifc/rtl/soc_ifc_reg.sv ]
add_files $outputDir/soc_ifc_reg.sv

# Add missing include
file copy [ glob $caliptrartlDir/src/ahb_lite_bus/rtl/ahb_lite_address_decoder.sv ] $outputDir/ahb_lite_address_decoder.sv
exec sed -i {1i `include \"config_defines.svh\"} $outputDir/ahb_lite_address_decoder.sv
remove_files [ glob $caliptrartlDir/src/ahb_lite_bus/rtl/ahb_lite_address_decoder.sv ]
add_files $outputDir/ahb_lite_address_decoder.sv

# Change soc_ifc to assign generic_input_wires[1] to CALIPTRA_FUSE_GRANULARITY
file copy [ glob $caliptrartlDir/src/soc_ifc/rtl/soc_ifc_top.sv ] $outputDir/soc_ifc_top.sv
exec sed -i {/`ifdef CALIPTRA_FUSE_GRANULARITY_32/,/`endif/calways_comb soc_ifc_reg_hwif_in.CPTRA_HW_CONFIG.Fuse_Granularity.next = generic_input_wires[0][1];} $outputDir/soc_ifc_top.sv
remove_files [ glob $caliptrartlDir/src/soc_ifc/rtl/soc_ifc_top.sv ]
add_files $outputDir/soc_ifc_top.sv

# Mark all Verilog sources as SystemVerilog because some of them have SystemVerilog syntax.
set_property file_type SystemVerilog [get_files *.v]

# Exception: caliptra_package_top.v needs to be Verilog to be included in a Block Diagram.
set_property file_type Verilog [get_files  $fpgaDir/src/caliptra_package_top.v]

# Set caliptra_package_top as top in case next steps fail so that the top is something useful.
set_property top caliptra_package_axi_top [current_fileset]

# Create block diagram that includes an instance of caliptra_package_top
create_bd_design "caliptra_package_bd"
create_bd_cell -type module -reference caliptra_package_axi_top caliptra_package_top_0

save_bd_design
close_bd_design [get_bd_designs caliptra_package_bd]

# Package IP
puts "Fileset when packaging: [current_fileset]"
puts "\n\nVERILOG DEFINES: [get_property verilog_define [current_fileset]]"
ipx::package_project -root_dir $caliptrapackageDir -vendor design -library user -taxonomy /UserIP -import_files
# Infer interfaces
ipx::infer_bus_interfaces xilinx.com:interface:bram_rtl:1.0 [ipx::current_core]
ipx::add_bus_parameter MASTER_TYPE [ipx::get_bus_interfaces rom_backdoor -of_objects [ipx::current_core]]
ipx::add_bus_parameter MASTER_TYPE [ipx::get_bus_interfaces mcu_rom_backdoor -of_objects [ipx::current_core]]
ipx::add_bus_parameter MASTER_TYPE [ipx::get_bus_interfaces otp_mem_backdoor -of_objects [ipx::current_core]]
# Associate clocks to busses
ipx::associate_bus_interfaces -busif S_AXI_WRAPPER -clock core_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif S_AXI_CALIPTRA -clock core_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif M_AXI_CALIPTRA -clock core_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif rom_backdoor -clock rom_backdoor_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif mcu_rom_backdoor -clock mcu_rom_backdoor_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif otp_mem_backdoor -clock otp_mem_backdoor_clk [ipx::current_core]

ipx::associate_bus_interfaces -busif M_AXI_MCU_IFU -clock core_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif M_AXI_MCU_LSU -clock core_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif M_AXI_MCU_SB -clock core_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif S_AXI_MCI -clock core_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif S_AXI_MCU_ROM -clock core_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif S_AXI_OTP -clock core_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif S_AXI_LCC -clock core_clk [ipx::current_core]

# USB AXI slave interfaces
ipx::associate_bus_interfaces -busif S_AXI_USB_DEV  -clock core_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif S_AXI_USB_HOST -clock core_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif S_AXI_USB_DMA  -clock core_clk [ipx::current_core]
# Different clock used for I3C
ipx::associate_bus_interfaces -busif S_AXI_I3C -clock i3c_clk [ipx::current_core]
ipx::associate_bus_interfaces -busif S_AXI_I3C_SPARE -clock i3c_clk [ipx::current_core]

# Other packager settings
set_property name caliptra_package_top [ipx::current_core]
set_property core_revision 1 [ipx::current_core]
set_property PAYMENT_REQUIRED FALSE [ipx::current_core]
ipx::update_source_project_archive -component [ipx::current_core]
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::check_integrity [ipx::current_core]
ipx::save_core [ipx::current_core]

# Close caliptra_package_project
close_project
