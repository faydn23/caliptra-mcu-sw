set diagnosticDir [file dirname [file normalize [info script]]]
set fpgaDir [file dirname $diagnosticDir]
set htgCoreClockMHz 60
cd $fpgaDir
set firmwareArgs [lsearch -all -inline -glob $argv FW_IMAGE_DIR=*]
if {[llength $firmwareArgs] > 1} {error "Only one FW_IMAGE_DIR is allowed"}
set versionArgs [lsearch -all -inline -glob $argv VERSION=*]
if {[llength $versionArgs] > 1} {error "Only one VERSION is allowed"}
if {[llength $versionArgs] == 1 &&
    ![regexp {^VERSION=[0-9a-fA-F]{1,8}$} [lindex $versionArgs 0]]} {
    error "VERSION must be one to eight hexadecimal digits"
}
set htgForceUlpiMode [expr {[lsearch -exact $argv FORCE_ULPI_MODE] >= 0}]
set htgSoftwareUlpiStartup [expr {[lsearch -exact $argv SOFTWARE_ULPI_STARTUP] >= 0}]
if {$htgForceUlpiMode && $htgSoftwareUlpiStartup} {
    error "FORCE_ULPI_MODE and SOFTWARE_ULPI_STARTUP are mutually exclusive"
}
set requestedMode REGISTER_CONTROLLED
if {$htgForceUlpiMode} {set requestedMode FORCED_ULPI}
if {$htgSoftwareUlpiStartup} {set requestedMode SOFTWARE_ULPI_STARTUP}
set mcuUsbOnly [expr {[lsearch -exact $argv MCU_USB_ONLY] >= 0}]
set outputName [expr {$mcuUsbOnly ?
    "htg940_usb_min_ila/build_mcu_usb_only" : "htg940_usb_min_ila/build_iobuf_dual"}]
set buildNameArgs [lsearch -all -inline -glob $argv BUILD_NAME=*]
if {[llength $buildNameArgs] > 1} {error "Only one BUILD_NAME is allowed"}
if {$htgForceUlpiMode && ([llength $buildNameArgs] != 1 || $mcuUsbOnly)} {
    error "FORCE_ULPI_MODE requires a separate BUILD_NAME=build_full_<suffix>"
}
if {$htgSoftwareUlpiStartup && ([llength $buildNameArgs] != 1 || $mcuUsbOnly)} {
    error "SOFTWARE_ULPI_STARTUP requires a separate BUILD_NAME=build_full_<suffix>"
}
if {[llength $buildNameArgs] == 1} {
    set buildName [string range [lindex $buildNameArgs 0] 11 end]
    set namePattern [expr {$mcuUsbOnly ?
        {^build_mcu_usb_only_[A-Za-z0-9_]+$} : {^build_full_[A-Za-z0-9_]+$}}]
    if {![regexp $namePattern $buildName]} {
        error "BUILD_NAME must match the selected profile: $namePattern"
    }
    set outputName "htg940_usb_min_ila/$buildName"
}
set project [file join $fpgaDir $outputName caliptra_htg940_project.xpr]
set resume [expr {[lsearch -exact $argv RESUME] >= 0}]
set restartSynth [expr {[lsearch -exact $argv RESTART_SYNTH] >= 0}]
if {$resume && $restartSynth} {error "RESUME and RESTART_SYNTH are mutually exclusive"}
set implement [expr {[lsearch -exact $argv IMPLEMENT] >= 0}]
set restartImpl [expr {[lsearch -exact $argv RESTART_IMPL] >= 0}]
if {$restartImpl && (!$resume || !$implement)} {
    error "RESTART_IMPL requires RESUME IMPLEMENT"
}
set jobs 4
proc require_complete {runName} {
    wait_on_run $runName
    set status [get_property STATUS [get_runs $runName]]
    puts "$runName STATUS: $status"
    if {![string match "*Complete*" $status]} {
        error "$runName failed or stopped: $status"
    }
}
if {$resume || $restartSynth} {
    if {![file exists $project]} {error "Missing project: $project"}
    open_project $project
    if {[lsearch -exact [get_property generic [get_filesets sources_1]] \
        CORE_CLK_HZ=60000000] < 0} {
        error "Resume requires the 60 MHz board profile; create a fresh build instead."
    }
    set modeFile [file join [file dirname $project] htg_phy_mode.txt]
    set savedMode REGISTER_CONTROLLED
    if {[file isfile $modeFile]} {
        set fh [open $modeFile r]
        set savedMode [string trim [read $fh]]
        close $fh
    }
    if {$savedMode ne $requestedMode} {
        error "PHY mode mismatch: project=$savedMode requested=$requestedMode; create a fresh build."
    }
    if {$restartSynth} {
        source [file join $diagnosticDir isolate_dual_ila_constraints.tcl]
        foreach ipRun [get_runs -quiet *_synth_1] {
            if {[get_property PROGRESS $ipRun] ne "100%" ||
                [get_property NEEDS_REFRESH $ipRun]} {
                error "RESTART_SYNTH requires completed, current IP synthesis: $ipRun"
            }
        }
        if {![info exists ::env(HTG_SYNTH_RESTART_ARCHIVE)]} {
            error "RESTART_SYNTH requires HTG_SYNTH_RESTART_ARCHIVE for the stopped run"
        }
        set archive [file normalize $::env(HTG_SYNTH_RESTART_ARCHIVE)]
        if {[file exists $archive]} {error "Archive already exists: $archive"}
        set stoppedRunDir [get_property DIRECTORY [get_runs synth_1]]
        file mkdir [file dirname $archive]
        file copy $stoppedRunDir $archive
        puts "HTG_SYNTH_RESTART_ARCHIVED: $archive"
        reset_run synth_1
        puts "HTG_SYNTH_RESTART: restarting synth_1; completed IP runs retained"
        launch_runs synth_1 -jobs $jobs
        require_complete synth_1
    } else {
        if {[get_property PROGRESS [get_runs synth_1]] ne "100%" ||
            [get_property NEEDS_REFRESH [get_runs synth_1]]} {
            error "Resume requires completed, current synthesis."
        }
    }
} else {
    if {[file exists [file join $fpgaDir $outputName]]} {
        error "Output exists; use RESUME. The old build is preserved."
    }
    set HTG_ULPI_DIAGNOSTICS true
    set argv [list BUILD=FALSE GUI=FALSE OUTPUT_DIR=$outputName \
        CORE_CLK_MHZ=$htgCoreClockMHz DEBUG=FALSE]
    lappend argv MCU_USB_ONLY=$mcuUsbOnly STUB_ADAMS_BRIDGE=FALSE STUB_ECC=FALSE
    set argv [concat $argv $firmwareArgs $versionArgs]
    source [file join $fpgaDir fpga_configuration_htg940_hw.tcl]
    update_compile_order -fileset sources_1
    set profileDefines [get_property verilog_define [get_filesets sources_1]]
    if {!$mcuUsbOnly} {
        foreach forbidden {HTG940_MCU_USB_ONLY STUB_ADAMS_BRIDGE STUB_ECC} {
            if {[lsearch -exact $profileDefines $forbidden] >= 0} {
                error "Full build contains disabled-core/crypto define: $forbidden"
            }
        }
        puts "HTG_FULL_PROFILE_VERIFIED: core and crypto enabled; no MCU-only specialization"
    }
    source [file join $diagnosticDir isolate_dual_ila_constraints.tcl]
    launch_runs synth_1 -jobs $jobs
    require_complete synth_1
}
if {$resume} {
    source [file join $diagnosticDir isolate_dual_ila_constraints.tcl]
}
open_run synth_1
if {$mcuUsbOnly} {
    set removedCore [get_cells -quiet -hier -filter {NAME =~ */caliptra_top_dut*}]
    if {[llength $removedCore] != 0} {
        error "MCU_USB_ONLY synthesis still contains Caliptra core: $removedCore"
    }
    puts "HTG940_MCU_USB_ONLY_SYNTH_VERIFIED: no Caliptra core hierarchy"
} else {
    set restoredCore [get_cells -quiet -hier -filter {NAME =~ */caliptra_top_dut}]
    if {[llength $restoredCore] != 1} {
        error "Full synthesis requires one Caliptra core hierarchy: $restoredCore"
    }
    set disabledEndpoint [get_cells -quiet -hier -filter {NAME =~ */disabled_caliptra*}]
    if {[llength $disabledEndpoint] != 0} {
        error "Full synthesis contains disabled Caliptra endpoint: $disabledEndpoint"
    }
    puts "HTG_FULL_SYNTH_VERIFIED: restored Caliptra core $restoredCore"
}
set htgValidateOnly [expr {!$implement}]
source [file join $diagnosticDir add_dual_ila.tcl]
if {!$implement} {
    puts "HTG_DIAGNOSTIC_PREFLIGHT_COMPLETE: use RESUME IMPLEMENT for implementation."
    close_project
    exit
}
save_constraints
# Vivado can serialize a temporary debug clock alias absent from the synth DCP.
min_save_debug_clocks $localDebug $htgDebugClockPins
close_design
if {$restartImpl} {
    if {![info exists ::env(HTG_IMPL_RESTART_ARCHIVE)]} {
        error "RESTART_IMPL requires HTG_IMPL_RESTART_ARCHIVE for the failed run"
    }
    set archive [file normalize $::env(HTG_IMPL_RESTART_ARCHIVE)]
    if {[file exists $archive]} {error "Archive already exists: $archive"}
    file mkdir [file dirname $archive]
    file copy [get_property DIRECTORY [get_runs impl_1]] $archive
    reset_run impl_1
    puts "HTG_IMPL_RESTART: failed run archived to $archive; synthesis retained"
}
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
require_complete impl_1
open_run impl_1
set resultDir [get_property DIRECTORY [get_runs impl_1]]
write_debug_probes -force [file join $resultDir htg940_usb_dual_ila.ltx]
write_mem_info -force [file join $resultDir htg940_board_top.mmi]
report_timing_summary -file [file join $resultDir htg940_timing_summary.rpt]
report_drc -file [file join $resultDir htg940_drc.rpt]
puts "HTG_DUAL_ILA_BITSTREAM: $resultDir/htg940_board_top.bit"
close_project
exit
