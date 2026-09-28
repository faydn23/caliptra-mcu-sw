# Reuse the existing project and completed IP synthesis checkpoints.
set fpgaDir [file normalize [file dirname [info script]]]
set projectFile [file join $fpgaDir caliptra_build_htg940_hw_logs caliptra_htg940_project.xpr]
if {![file isfile $projectFile]} {error "Existing hardware project missing: $projectFile"}
open_project $projectFile
if {[get_property top [current_fileset]] ne "htg940_board_top"} {error "Unexpected project top"}
foreach run [get_runs] {
    set status [get_property STATUS $run]
    if {[regexp -nocase {running|queued} $status]} {error "Run still active: $run ($status)"}
}
# Ensure this project references the exact files patched by the installer.
foreach rel {board/htg940_board_top.sv constraints/htg940_board_nxp.xdc} {
    set expected [file normalize [file join $fpgaDir $rel]]
    set found 0
    foreach f [get_files -quiet *[file tail $rel]] {
        if {[file normalize [get_property NAME $f]] eq $expected} {set found 1}
    }
    if {!$found} {error "Project does not reference patched file: $expected"}
    set fd [open $expected r]
    set content [read $fd]
    close $fd
    if {[string first HTG940_NO_FMC_JTAG_V1 $content] < 0} {error "Patch marker missing: $expected"}
}
if {[llength [get_files -quiet *htg940_jtag_route.xdc]]} {
    error "Unexpected earlier JTAG routing exception in project; remove it before proceeding"
}
update_compile_order -fileset sources_1
# Do not reset OOC runs. Report their state before rebuilding the board top.
foreach run [get_runs -filter {IS_SYNTHESIS == 1}] {
    if {[get_property NAME $run] ne "synth_1"} {
        puts "HTG940_IP_STATUS: $run : [get_property STATUS $run]"
    }
}
proc require_complete {name} {
    wait_on_run $name
    set status [get_property STATUS [get_runs $name]]
    puts "HTG940_RUN_STATUS: $name : $status"
    if {![string match *Complete* $status]} {error "Run failed: $name ($status)"}
}
# Reset only top-level implementation and synthesis, not IP runs or the project.
reset_run impl_1
reset_run synth_1
launch_runs synth_1 -jobs 4
require_complete synth_1
# Inspect the synthesized result before starting implementation.
open_run synth_1
if {[llength [get_ports -quiet jlink_*]] || [llength [get_cells -quiet u_jtag_bufg]]} {
    error "Unused processor JTAG circuitry remains in synthesized top"
}
puts "HTG940_NO_FMC_JTAG_SYNTH_PASS"
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
require_complete impl_1
open_run impl_1
set runDir [get_property DIRECTORY [get_runs impl_1]]
report_timing_summary -file [file join $runDir htg940_final_timing.rpt]
report_utilization -file [file join $runDir htg940_final_utilization.rpt]
report_drc -file [file join $runDir htg940_final_drc.rpt]
set bits [glob -nocomplain -directory $runDir *.bit]
if {[llength $bits] != 1} {error "Expected one bitstream, found: $bits"}
puts "HTG940_BITSTREAM_CREATED: [lindex $bits 0]"
puts "Review timing, DRC and board I/O before programming; bitstream creation is not boot PASS."
close_project
exit
