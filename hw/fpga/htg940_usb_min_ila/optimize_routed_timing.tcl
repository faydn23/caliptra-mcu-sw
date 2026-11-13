proc htg_worst_slacks {} {
    set slacks {}
    foreach delay {max min} {
        set paths [get_timing_paths -delay_type $delay -max_paths 1]
        if {[llength $paths] != 1} {
            error "Expected one worst $delay timing path, found [llength $paths]"
        }
        set slack [get_property SLACK [lindex $paths 0]]
        if {![string is double -strict $slack] ||
            $slack in {Inf -Inf NaN}} {
            error "Invalid $delay slack: $slack"
        }
        lappend slacks $slack
    }
    return $slacks
}

proc htg_timing_reports {directory} {
    file mkdir $directory
    report_timing_summary -report_unconstrained -max_paths 20 \
        -file [file join $directory timing_summary.rpt]
    report_timing -to [get_ports cptra_ss_usb_ulpi_stp_o] \
        -delay_type min_max -max_paths 30 -path_type full_clock_expanded \
        -file [file join $directory stp.rpt]
    report_timing -from [get_ports {cptra_ss_usb_ulpi_dir_i cptra_ss_usb_ulpi_nxt_i cptra_ss_usb_ulpi_data_io[*]}] \
        -delay_type min_max -max_paths 30 -path_type full_clock_expanded \
        -file [file join $directory ulpi_inputs.rpt]
    report_timing -to [get_ports {cptra_ss_usb_ulpi_stp_o cptra_ss_usb_ulpi_data_io[*]}] \
        -delay_type min_max -max_paths 30 -path_type full_clock_expanded \
        -file [file join $directory ulpi_outputs.rpt]
    report_clock_interaction -file [file join $directory clock_interaction.rpt]
    report_cdc -file [file join $directory cdc.rpt]
    check_timing -verbose -file [file join $directory check_timing.rpt]
    report_drc -file [file join $directory drc.rpt]
    report_route_status -file [file join $directory route_status.rpt]
}

if {[llength $argv] != 2} {
    error "Usage: vivado -mode batch -source optimize_routed_timing.tcl -tclargs INPUT_ROUTED_DCP NEW_OUTPUT_DIRECTORY"
}
lassign $argv checkpoint output
set checkpoint [file normalize $checkpoint]
set output [file normalize $output]
if {![file isfile $checkpoint]} {
    error "Missing routed checkpoint: $checkpoint"
}
if {[file exists $output]} {
    error "Output already exists; refusing to overwrite: $output"
}
file mkdir $output
set_param general.maxThreads 4
open_checkpoint $checkpoint
foreach port {cptra_ss_usb_ulpi_clk_i cptra_ss_usb_ulpi_stp_o cptra_ss_usb_ulpi_dir_i cptra_ss_usb_ulpi_nxt_i} {
    if {[llength [get_ports -quiet $port]] != 1} {
        error "Expected one HTG940 ULPI port: $port"
    }
}
htg_timing_reports [file join $output baseline]
lassign [htg_worst_slacks] baselineSetup baselineHold

# Keep the original clock, I/O and timing-exception model unchanged.
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
htg_timing_reports [file join $output candidate]
lassign [htg_worst_slacks] setup hold
write_checkpoint [file join $output optimized_routed.dcp]

set result [open [file join $output result.txt] w]
puts $result "SOURCE_CHECKPOINT=$checkpoint"
puts $result "BASELINE_SETUP_SLACK_NS=$baselineSetup"
puts $result "BASELINE_HOLD_SLACK_NS=$baselineHold"
puts $result "CANDIDATE_SETUP_SLACK_NS=$setup"
puts $result "CANDIDATE_HOLD_SLACK_NS=$hold"
if {$setup < 0 || $hold < 0} {
    puts $result "STATUS=TIMING_FAILED"
    puts $result "Not qualified for hardware. No bitstream generated."
    close $result
    close_design
    exit 2
}
puts $result "STATUS=SLACK_GATE_PASSED_REVIEW_REQUIRED"
puts $result "Review unconstrained paths, pulse width, CDC, DRC and routing before signoff."
puts $result "No bitstream generated. PHY/enumeration must still be tested on hardware."
close $result
close_design
exit 0
