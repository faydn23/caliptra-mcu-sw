set fpgaDir [file normalize [file dirname [info script]]]

# Generate and validate the hardware project first.
set argv [list BUILD=FALSE GUI=FALSE \
    OUTPUT_DIR=caliptra_build_htg940_hw_logs]
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

puts "HTG940_BUILD: implementation and bitstream"
launch_runs impl_1 -to_step write_bitstream -jobs 4
require_complete impl_1

open_run impl_1
set resultDir [get_property DIRECTORY [get_runs impl_1]]
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
