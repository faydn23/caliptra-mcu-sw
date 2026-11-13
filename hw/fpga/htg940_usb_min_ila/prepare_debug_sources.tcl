# Build-local attributes: do not modify the USB submodule's original sources.
source [file join $fpgaDir htg940_usb_min_ila probe_schema.tcl]
set forceUlpiMode [expr {[info exists htgForceUlpiMode] && $htgForceUlpiMode}]
set softwareUlpiStartup [expr {
    [info exists htgSoftwareUlpiStartup] && $htgSoftwareUlpiStartup
}]
if {$forceUlpiMode && $softwareUlpiStartup} {
    error "Forced ULPI and software-selected ULPI startup are mutually exclusive"
}
foreach {instance filename} {
    usb_pie_1 usb_pie.m.vhdl
    usb_synchronizer_1 usb_synchronizer.m.vhdl
    usb_reg_if_1 usb_reg_if.m.vhdl
    u_hub_compound ip_xxx_3511_hs_mem_compound_structure.a.vhdl
} {
    set matches {}
    foreach file [get_files -quiet *$filename] {
        if {[string first usb_hub_composite_device $file] >= 0 ||
            [file dirname [file normalize $file]] eq
                [file normalize [file join $outputDir htg940_usb_vhdl]]} {
            lappend matches $file
        }
    }
    if {[llength $matches] != 1} {
        error "Expected one composite-device source $filename; got $matches"
    }
    set original [lindex $matches 0]
    set library [get_property LIBRARY [get_files $original]]
    set fh [open $original r]
    set text [read $fh]
    close $fh
    if {($forceUlpiMode || $softwareUlpiStartup) && $instance eq "usb_synchronizer_1"} {
        if {[regexp -all {phy_mode[ \t]+<=[ \t]+usbreg_phy_mode;} $text] != 1} {
            error "ULPI startup profiles require the direct shared PHY mode connection"
        }
    }
    if {$forceUlpiMode && $instance eq "u_hub_compound"} {
        set modeConnection {\mhub_phy_mode[ \t]*=>[ \t]*usbreg_phy_mode\M}
        if {[regexp -all $modeConnection $text] != 1} {
            error "Expected one hub-owned PHY mode driver in $original"
        }
        regsub $modeConnection $text {hub_phy_mode => open} text
        set modeAnchor {usb_synchronizer_1: usb_synchronizer}
        if {[string first $modeAnchor $text] < 0 ||
            [string first $modeAnchor $text] != [string last $modeAnchor $text]} {
            error "Expected one shared PHY synchronizer in $original"
        }
        set text [string map [list $modeAnchor \
            "-- HTG940 diagnostic: select ULPI even while subsystem reset is asserted.\nusbreg_phy_mode <= '1';\n\n$modeAnchor"] $text]
    }
    if {$softwareUlpiStartup && $instance eq "u_hub_compound"} {
        set clockBlock {  --UTMI/ULPI clock selection
  pie_clk <= utmi_clk when (testmode = '1' and C_UTMI_SUPPORT) else
             ulpi_clk when (testmode = '1' and C_ULPI_SUPPORT) else
             utmi_clk when phy_mode = '0'                      else
             ulpi_clk;}
        set resetProcess {  proc_pie_reset_gen : process(hresetn,pie_clk)
  begin
    if hresetn = '0' then}
        foreach anchor [list $clockBlock $resetProcess] {
            if {[string first $anchor $text] < 0 ||
                [string first $anchor $text] != [string last $anchor $text]} {
                error "Expected one software-ULPI clock/reset anchor in $original"
            }
        }
        set text [string map [list $clockBlock {
  assert C_ULPI_SUPPORT and not C_UTMI_SUPPORT
    report "SOFTWARE_ULPI_STARTUP requires ULPI-only hardware"
    severity failure;
  -- Keep the clock on its physical source; software still selects the PHY mode.
  pie_clk <= ulpi_clk;
  htg_pie_reset_n <= hresetn and (usbreg_phy_mode or testmode);
} $resetProcess {  proc_pie_reset_gen : process(htg_pie_reset_n,pie_clk)
  begin
    if htg_pie_reset_n = '0' then}] $text]
    }
    set attributes "\n"
    if {$instance eq "usb_pie_1"} {
        append attributes "signal htg_ulpi_state : std_logic_vector(4 downto 0);\n"
    }
    if {$softwareUlpiStartup && $instance eq "u_hub_compound"} {
        append attributes "signal htg_pie_reset_n : std_logic;\n"
    }
    append attributes "attribute mark_debug : string;\nattribute keep : string;\n"
    set signals {}
    foreach spec [concat $htg_ulpi_schema $htg_core_schema] {
        lassign $spec owner signal width
        if {$owner eq $instance} {lappend signals $signal}
    }
    foreach signal [lsort -unique $signals] {
        append attributes "attribute mark_debug of $signal : signal is \"true\";\n"
        append attributes "attribute keep of $signal : signal is \"true\";\n"
    }
    switch $instance {
        usb_pie_1 {set anchorSignal pie_success_int}
        usb_synchronizer_1 {set anchorSignal pie_lowpower_n_s}
        usb_reg_if_1 {set anchorSignal reg_dev_force_fullspeed}
        u_hub_compound {set anchorSignal zero8}
    }
    set expression [format {\n[ \t]*signal %s[^\n]*\n} $anchorSignal]
    set anchors [regexp -all -inline $expression $text]
    if {[llength $anchors] != 1} {
        error "Expected one architecture declaration anchor in $original"
    }
    set anchor [lindex $anchors 0]
    set text [string map [list $anchor "$anchor$attributes"] $text]
    if {$instance eq "usb_pie_1"} {
        if {![regexp {end function test_paket_decod;[\r\n \t]*begin} $text anchor]} {
            error "PIE architecture body not found"
        }
        set text [string map [list $anchor \
            "$anchor\nhtg_ulpi_state <= std_logic_vector(to_unsigned(t_ulpi_oper_state'pos(ulpi_oper_state_r), 5));\n"] $text]
    }
    set generated [file join $outputDir htg_debug_$filename]
    set fh [open $generated w]
    puts -nonewline $fh $text
    close $fh
    remove_files [get_files $original]
    add_files -norecurse $generated
    set_property LIBRARY $library [get_files $generated]
    set_property file_type {VHDL 2008} [get_files $generated]
}
set modeName [expr {$forceUlpiMode ? "FORCED_ULPI" : "REGISTER_CONTROLLED"}]
if {$softwareUlpiStartup} {set modeName SOFTWARE_ULPI_STARTUP}
set fh [open [file join $outputDir htg_phy_mode.txt] w]
puts $fh $modeName
close $fh
puts "HTG_PHY_MODE: $modeName (build-local RTL; hub register readback is unchanged)"

set fh [open $wrapperGenerated r]
set text [read $fh]
close $fh
set anchor {// USB ULPI signals}
if {[llength [regexp -all -inline $anchor $text]] != 1} {
    error "Expected one ULPI monitor insertion point"
}
set monitor {
// A divided ULPI clock observed through a two-flop core-clock synchronizer.
logic [7:0] htg_ulpi_count;
(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
logic [1:0] htg_ulpi_clock_sync;
(* mark_debug = "true", keep = "true" *)
wire htg_ulpi_clock_activity = htg_ulpi_clock_sync[1];
always_ff @(posedge USB_ULPI_CLK or negedge axi_reset) begin
    if (!axi_reset) htg_ulpi_count <= '0;
    else htg_ulpi_count <= htg_ulpi_count + 1'b1;
end
always_ff @(posedge core_clk or negedge axi_reset) begin
    if (!axi_reset) htg_ulpi_clock_sync <= '0;
    else htg_ulpi_clock_sync <= {htg_ulpi_clock_sync[0], htg_ulpi_count[7]};
end
}
set text [string map [list $anchor "$monitor\n$anchor"] $text]
set fh [open $wrapperGenerated w]
puts -nonewline $fh $text
close $fh
