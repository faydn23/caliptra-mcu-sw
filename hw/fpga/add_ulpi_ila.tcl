set xpr $::env(HTG_XPR)
open_project $xpr
open_run synth_1

set ulpi_nets [get_nets -hier -filter {NAME =~ *ulpi*}]
puts "ULPI candidate nets: [llength $ulpi_nets]"

proc find_ulpi_net {all_nets stem {bit -1}} {
    set matches {}
    if {$bit < 0} {
        set pattern [format {(^|/)%s$} $stem]
    } else {
        set pattern [format {(^|/)%s\[%d\]$} $stem $bit]
    }

    foreach net $all_nets {
        if {[regexp -- $pattern $net]} {
            lappend matches $net
        }
    }

    if {[llength $matches] == 0} {
        error "Missing synthesized net: $stem bit $bit"
    }
    set chosen [lindex $matches 0]
    foreach net $matches {
        if {[string length $net] < [string length $chosen]} {
            set chosen $net
        }
    }
    puts "Selected $stem bit $bit: $chosen"
    return $chosen
}

if {[llength [get_debug_cores -quiet ulpi_ila]] != 0} {
    error "ulpi_ila already exists in this project"
}

set ulpi_clk [find_ulpi_net $ulpi_nets cptra_ss_usb_ulpi_clk_i_IBUF]
create_debug_core ulpi_ila ila
set_property C_DATA_DEPTH 4096 [get_debug_cores ulpi_ila]
connect_debug_port ulpi_ila/clk [get_nets [list $ulpi_clk]]
puts "ILA clock: $ulpi_clk"

set probe_index 0
foreach {name width} {
    usb_ulpi_txdata            8
    usb_ulpi_txenable          1
    cptra_ss_usb_ulpi_rxdata_i   8
    cptra_ss_usb_ulpi_dir_i_IBUF 1
    cptra_ss_usb_ulpi_nxt_i_IBUF 1
    u_system/caliptra_htg940_bd_i/caliptra_package_top_0/inst/cptra_wrapper/caliptra_ss_top_0/usb_core_i/u_hub_compound/usb_pie_1/cptra_ss_usb_ulpi_stp_o 1
} {
    set selected {}
    if {$width == 1} {
        lappend selected [find_ulpi_net $ulpi_nets $name]
    } else {
        for {set bit 0} {$bit < $width} {incr bit} {
            lappend selected [find_ulpi_net $ulpi_nets $name $bit]
        }
    }

    if {$probe_index > 0} {
        create_debug_port ulpi_ila probe
    }
    set port "ulpi_ila/probe${probe_index}"
    set_property MARK_DEBUG true [get_nets $selected]
    set_property port_width $width [get_debug_ports $port]
    connect_debug_port $port [get_nets $selected]
    puts "$port <- $name : $selected"
    incr probe_index
}

if {[info exists ::env(ILA_PRECHECK)] && $::env(ILA_PRECHECK) eq "1"} {
    puts "ILA PROBES VERIFIED; implementation not started"
    exit 0
}
save_constraints
close_design

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set status [get_property STATUS [get_runs impl_1]]
puts "Implementation: $status"
if {![string match "*Complete*" $status]} {
    error "Implementation or bitstream generation failed"
}

open_run impl_1
set project_dir [file dirname $xpr]
set ltx [file join $project_dir ulpi_ila.ltx]
write_debug_probes -force $ltx

set bit [file join $project_dir caliptra_htg940_project.runs impl_1 htg940_board_top.bit]
if {![file exists $bit]} {
    error "New bitstream missing: $bit"
}
puts "NEW BASE BIT: $bit"
puts "MATCHING LTX: $ltx"
