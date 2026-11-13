if {[llength $argv] != 2} {
    error "Usage: -tclargs INPUT_ROUTED_DCP NEW_OUTPUT_DIRECTORY"
}
lassign $argv checkpoint output
set checkpoint [file normalize $checkpoint]
set output [file normalize $output]
if {![file isfile $checkpoint]} {error "Missing checkpoint: $checkpoint"}
if {[file exists $output]} {error "Refusing to overwrite: $output"}
file mkdir $output
set_param general.maxThreads 4
open_checkpoint $checkpoint
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]
set prefix [file join $output htg940_TIMING_FAILED_DEBUG_ONLY]
report_timing_summary -report_unconstrained -max_paths 30 \
    -file [file join $output timing_summary.rpt]
report_drc -file [file join $output drc.rpt]
report_cdc -file [file join $output cdc.rpt]
report_route_status -file [file join $output route_status.rpt]
report_clocks -file [file join $output clocks.rpt]
report_clock_interaction -file [file join $output clock_interaction.rpt]
set fh [open [file join $output usb_clock_network.txt] w]
set pins [get_pins -hier -filter {NAME =~ */u_hub_compound/usb_pie_1/pie_clk}]
if {[llength $pins] != 1} {
    close $fh
    error "Expected one USB motor clock pin, found [llength $pins]"
}
puts $fh "Motor clock: $pins"
puts $fh "Clocks: [get_clocks -of_objects $pins]"
puts $fh "Clock fanin cells:"
foreach cell [all_fanin -flat -only_cells -to $pins] {
    puts $fh "$cell REF_NAME=[get_property REF_NAME $cell]"
}
puts $fh "PHY mode sinks:"
foreach pin [get_pins -hier -filter {NAME =~ */u_hub_compound/*phy_mode}] {
    puts $fh "$pin NET=[get_nets -of_objects $pin]"
}
close $fh
set warning [open [file join $output DEBUG_ONLY.txt] w]
puts $warning "TIMING FAILED: explicitly authorized diagnostic candidate, not a hardware fix."
puts $warning "No timing exceptions or DRC severity overrides were added."
puts $warning "Input: $checkpoint"
puts $warning "ROM contents are inherited from the checkpoint, NOT patched with the supplied ROM binaries."
puts $warning "Use the MMI to patch and verify exact ROMs before comparison with the failing hardware image."
puts $warning "No board programming is performed. Enumeration/recovery are not validated."
close $warning
write_mem_info -no_partial_mmi "$prefix.mmi"
write_debug_probes "$prefix.ltx"
write_bitstream "$prefix.bit"
foreach extension {bit mmi ltx} {
    set path "$prefix.$extension"
    if {![file isfile $path] || [file size $path] == 0} {
        error "Missing or empty deliverable: $path"
    }
}
set fh [open [file join $output COMPLETE.txt] w]
puts $fh "DEBUG BIT GENERATED; TIMING FAILED; NOT A VERIFIED FIX."
close $fh
close_design
exit 0
