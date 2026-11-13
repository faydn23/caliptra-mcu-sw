set fpgaDir [file dirname [file dirname [file normalize [info script]]]]
cd $fpgaDir
puts [exec python3 [file join $fpgaDir htg940 prepare_sources.py] --check]
open_project [file join $fpgaDir htg940_usb_min_ila build_full_usb2_97aa961_ws3 caliptra_htg940_project.xpr]

foreach ipRun [get_runs -quiet *_synth_1] {
    if {[get_property PROGRESS $ipRun] ne "100%" ||
        [get_property NEEDS_REFRESH $ipRun]} {
        puts "HTG940_RECOVERY: restarting incomplete IP $ipRun"
        reset_run $ipRun
    } else {
        puts "HTG940_RECOVERY: retaining completed IP $ipRun"
    }
}

if {[get_property PROGRESS [get_runs synth_1]] ne "100%" ||
    [get_property NEEDS_REFRESH [get_runs synth_1]]} {
    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
}
if {[get_property PROGRESS [get_runs synth_1]] ne "100%" ||
    [get_property NEEDS_REFRESH [get_runs synth_1]]} {
    error "Synthesis incomplete; implementation was not started."
}
close_project
set argv [list BUILD_NAME=build_full_usb2_97aa961_ws3 RESUME IMPLEMENT]
source [file join $fpgaDir htg940 run_full.tcl]
