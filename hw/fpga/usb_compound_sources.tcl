# USB source set for usb2 87a1a378: compound variants replace legacy units.
set usbRoot [file join $ssrtlDir third_party usb2 src]
set usbVhdl {
    usb_hub_composite_device/RTL/INTERFACE/usb_ep_config_hub_pkg.p.vhdl
    usb_hub_composite_device/RTL/INTERFACE/usb_general_subcmp_pkg.p.vhdl
    usb_hub_composite_device/RTL/RTL/usb_ahb_slave.m.vhdl
    usb_hub_composite_device/RTL/RTL/usb_mux.m.vhdl
    usb_hub_composite_device/RTL/RTL/usb_ocp_recovery_post_sync_arb.m.vhdl
    usb_hub_composite_device/RTL/RTL/usb_synchronizer.m.vhdl
    usb_hub_composite_device/RTL/INTERFACE/ip_xxx_3511_hs_mem_compound.e.vhdl
    usb_hub_composite_device/RTL/INTERFACE/usb_subcmp_pkg.p.vhdl
    usb_hub_composite_device/RTL/RTL/ahb_dma_slave.m.vhdl
    usb_hub_composite_device/RTL/RTL/usb_ep0_handler.m.vhdl
    usb_hub_composite_device/RTL/RTL/usb_ep0_hub_descr.m.vhdl
    usb_hub_composite_device/RTL/RTL/usb_ep_config_handler.m.vhdl
    usb_hub_composite_device/RTL/INTERFACE/usb_configuration_subcmp_pkg.p.vhdl
    usb_hub_composite_device/RTL/RTL/usb_app_hw_hub.m.vhdl
    usb_hub_composite_device/RTL/RTL/usb_dma.m.vhdl
    usb_hub_composite_device/RTL/RTL/usb_pie.m.vhdl
    usb_hub_composite_device/RTL/RTL/usb_reg_if.m.vhdl
    usb_hub_composite_device/RTL/STRUCTURE/ip_xxx_3511_hs_mem_compound_structure.a.vhdl
}
foreach rel $usbVhdl {
    set f [file join $usbRoot $rel]
    if {![file isfile $f]} {error "Missing USB VHDL source: $f"}
    if {[file tail $f] in {
        ip_xxx_3511_hs_mem_compound.e.vhdl
        ip_xxx_3511_hs_mem_compound_structure.a.vhdl
    }} {
        set fh [open $f r]
        set usbVhdlText [read $fh]
        close $fh

        # Keep legacy debug/PHY comments inactive in synthesis.
        regsub -all -nocase -- \
            {--[ \t]*synthesis[ \t]+read_comments_as_HDL[ \t]+(on|off)} \
            $usbVhdlText \
            {-- FPGA: legacy comment activation disabled} \
            usbVhdlText

        set usbVhdlDir [file join $outputDir usb_vhdl]
        file mkdir $usbVhdlDir
        set f [file join $usbVhdlDir [file tail $f]]
        set fh [open $f w]
        puts -nonewline $fh $usbVhdlText
        close $fh
    }
    add_files -norecurse $f
    set_property library rtl [get_files $f]
}
set usbSv {
    integration/rtl/generated/usb_ocp_recovery_reg_pkg.sv
    integration/rtl/usb_ocp_recovery_pkg.sv
    integration/rtl/usb_compound_pkg.sv
    integration/rtl/axilite_to_ahb.sv
    integration/rtl/axi_to_ahb.sv
    integration/rtl/generated/usb_ocp_recovery_reg.sv
    integration/rtl/usb_ocp_recovery_ctrl_decode.sv
    integration/rtl/usb_ocp_recovery_rb_adapter.sv
    integration/rtl/usb_ocp_recovery_cms_fifo.sv
    integration/rtl/usb_ocp_recovery_top.sv
    integration/rtl/usb_compound_ahb_decoder.sv
    integration/rtl/ip_xxx_3511_hs_mem_compound_wrapper.sv
}
foreach rel $usbSv {
    set f [file join $usbRoot $rel]
    if {![file isfile $f]} {error "Missing USB SV source: $f"}
    add_files -norecurse $f
}
set_property include_dirs [concat [get_property include_dirs [current_fileset]] \
    [list [file join $usbRoot integration rtl] \
          [file join $usbRoot integration rtl generated]]] [current_fileset]


set usbHeader [file join $usbRoot integration rtl generated usb_ocp_recovery_reg_addr_defs.svh]
if {![file isfile $usbHeader]} {
    error "Missing USB register header: $usbHeader"
}
add_files -norecurse $usbHeader
set_property file_type {Verilog Header} [get_files $usbHeader]
