set htgSynthOnly [expr {[lsearch -exact $argv SYNTH_ONLY] >= 0}]
set fpgaDir [file normalize [file dirname [info script]]]

if {[file exists [file join $fpgaDir caliptra_build_htg940_rtl_usb_4d4c3d5]]} {
    error "Output directory already exists. Use the resume script after synthesis or select a new build directory."
}

# Generate and validate the hardware project first.
set argv [list BUILD=FALSE GUI=FALSE \
    OUTPUT_DIR=caliptra_build_htg940_rtl_usb_4d4c3d5]
source [file join $fpgaDir fpga_configuration_htg940_hw.tcl]

if {[get_property top [get_filesets sources_1]] ne "htg940_board_top"} {
    error "Unexpected top module; build stopped."
}

proc require_complete {runName} {
    wait_on_run $runName
    set status [get_property STATUS [get_runs $runName]]
    puts "$runName STATUS: $status"
    if {![string match "*Complete*" $status]} {
        error "$runName failed or stopped: $status"
    }
}

puts "HTG940_BUILD: synthesis"
launch_runs synth_1 -jobs 4
require_complete synth_1
if {$htgSynthOnly} {
    puts "HTG940_SYNTHESIS_COMPLETE: inspect synthesis warnings before implementation."
    close_project
    exit
}

puts "HTG940_BUILD: implementation and bitstream"
launch_runs impl_1 -to_step write_bitstream -jobs 4
require_complete impl_1

open_run impl_1
set resultDir [get_property DIRECTORY [get_runs impl_1]]

set mmiFile [file join $resultDir htg940_board_top.mmi]
write_mem_info -force $mmiFile

set fh [open $mmiFile r]
set mmiText [read $fh]
close $fh

foreach rom {imem_inst1 mcu_rom} {
    if {![regexp "InstPath=\"\[^\"]*/${rom}/\[^\"]*\"" $mmiText]} {
        error "MMI does not contain expected ROM instance: $rom"
    }
}
puts "HTG940_ROM_MMI_CREATED: $mmiFile"

report_timing_summary -file [file join $resultDir htg940_timing_summary.rpt]
report_utilization -file [file join $resultDir htg940_utilization.rpt]
report_drc -file [file join $resultDir htg940_drc.rpt]

set bits [glob -nocomplain [file join $resultDir *.bit]]
if {[llength $bits] != 1} {
    error "Expected one bitstream, found: $bits"
}
puts "HTG940_BITSTREAM_CREATED: [lindex $bits 0]"
puts "Review timing and DRC reports before programming."
close_project
exit
