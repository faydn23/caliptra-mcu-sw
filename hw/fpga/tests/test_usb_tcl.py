# SPDX-License-Identifier: Apache-2.0
"""Execute source-selection and USB wiring sections of the actual Versal Tcl."""

import subprocess
import tempfile
import unittest
from pathlib import Path

FPGA = Path(__file__).resolve().parents[1]


def tcl(script):
    result = subprocess.run(["tclsh"], input=script, text=True, capture_output=True, cwd=FPGA)
    if result.returncode or result.stderr:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout


class UsbTclTests(unittest.TestCase):
    def test_usb_mode_profiles(self):
        source = (FPGA / "fpga_configuration.tcl").read_text()
        defaults = source.split("# If VERSION was not set", 1)[0]
        instance = source.split("# Add Caliptra package", 1)[1].split("#### Add Versal PS", 1)[0]
        for arguments, enabled, exported in (
            ("", 0, 1),
            ("USB_ENABLE=TRUE", 1, 1),
            ("BOARD=VMK180", 0, 0),
            ("USB_EXPORT_PORTS=FALSE", 0, 0),
        ):
            with self.subTest(arguments=arguments):
                script = r"""
proc create_bd_cell {args} {}
proc get_bd_cells {args} {return [lindex $args end]}
proc set_property {name value target} {set ::packaged_usb_enable $value}
""" + f"set argv {{{arguments}}}\n" + defaults + instance + f"""
if {{$packaged_usb_enable != {enabled}}} {{error "Wrong packaged USB mode"}}
if {{($USB_EXPORT_PORTS ? 1 : 0) != {exported}}} {{error "Wrong USB physical-port profile"}}
puts USB_MODE_PROFILE_PASS
"""
                self.assertIn("USB_MODE_PROFILE_PASS", tcl(script))

    def test_source_selection(self):
        source = (FPGA / "create_caliptra_package.tcl").read_text()
        prefix = source.split("save_bd_design", 1)[0]
        with tempfile.TemporaryDirectory(prefix="versal-usb-sources-") as output:
            script = r"""
proc create_project {args} {}
proc current_project {} {return project}
proc current_fileset {} {return sources}
proc get_files {args} {return [lindex $args end]}
proc get_property {args} {return {}}
set properties [dict create]
proc set_property {name value target} {dict set ::properties $name $value}
proc create_bd_design {args} {}
proc create_bd_cell {args} {}
proc get_bd_cells {args} {return [lindex $args end]}
set selected [dict create]
proc add_files {args} {
    foreach f [lindex $args end] {
        if {![file isfile $f]} {error "Missing source: $f"}
        dict set ::selected $f 1
    }
}
proc remove_files {args} {
    foreach f [lindex $args end] {dict unset ::selected $f}
}
""" + f"""
set fpgaDir {{{FPGA}}}
set outputDir {{{output}}}
set ssrtlDir [file normalize [file join $fpgaDir .. caliptra-ss]]
set caliptrartlDir [file join $ssrtlDir third_party caliptra-rtl]
set VERILOG_OPTIONS {{}}
set PART test
set BOARD VCK190
set USB_ENABLE FALSE
""" + prefix + r"""
foreach f {
    src/usb_packet_sram.sv
    src/caliptra_wrapper_top.sv
    src/caliptra_package_top.v
} {
    if {![dict exists $selected [file join $fpgaDir $f]]} {
        error "Missing packaged FPGA source: $f"
    }
}
set vhdl_count 0
dict for {f unused} $selected {
    if {[file extension $f] eq ".vhdl"} {incr vhdl_count}
}
if {$vhdl_count != 18} {error "Expected 18 compound USB VHDL files, got $vhdl_count"}
if {[dict get $properties CONFIG.USB_ENABLE] != 0} {
    error "Normal hardware mode did not disable USB"
}
puts USB_SOURCE_SELECTION_PASS
"""
            self.assertIn("USB_SOURCE_SELECTION_PASS", tcl(script))
            enabled = script.replace("set USB_ENABLE FALSE", "set USB_ENABLE TRUE")
            enabled = enabled.replace(
                "[dict get $properties CONFIG.USB_ENABLE] != 0",
                "[dict get $properties CONFIG.USB_ENABLE] != 1",
            )
            with tempfile.TemporaryDirectory(prefix="versal-usb-enabled-sources-") as enabled_output:
                enabled = enabled.replace(
                    f"set outputDir {{{output}}}", f"set outputDir {{{enabled_output}}}"
                )
                self.assertIn("USB_SOURCE_SELECTION_PASS", tcl(enabled))

    def test_usb_address_and_clock_wiring(self):
        source = (FPGA / "fpga_configuration.tcl").read_text()
        registers = source.split("#### Add AXI Infrastructure", 1)[1].split("# Create reset block", 1)[0]
        clock_reset = source.split("# Create reset connections", 1)[1].split("# Create clock connection for I3C", 1)[0]
        mappings = source.split("#### Assign address segments for all AXI managers ####", 1)[1].split("# Connect JTAG signals", 1)[0]
        script = r"""
proc get_bd_cells {args} {return [lindex $args end]}
proc get_bd_pins {args} {return [lindex $args end]}
proc get_bd_intf_pins {args} {return [lindex $args end]}
proc get_bd_ports {args} {return [lindex $args end]}
proc get_bd_addr_spaces {args} {return [lindex $args end]}
proc get_bd_addr_segs {args} {return [lindex $args end]}
proc create_bd_cell {args} {}
proc connect_bd_intf_net {args} {lappend ::intf_nets $args}
proc connect_bd_net {args} {lappend ::nets $args}
proc set_property {args} {lappend ::properties $args}
proc add_files {args} {
    if {![file isfile [lindex $args end]]} {error "Missing constraint file: $args"}
    lappend ::constraints $args
}
proc assign_bd_address {args} {lappend ::addresses $args}
proc create_bd_port {args} {
    set name [lindex $args end]
    if {[dict exists $::ports $name]} {error "Duplicate BD port: $name"}
    dict set ::ports $name $args
}
set intf_nets {}
set nets {}
set properties {}
set addresses {}
set ports [dict create]
set constraints {}
set fpgaDir [pwd]
set USB_EXPORT_PORTS 1
set ps_pl_resetn ps_0/pl_resetn0
set ps_pl_clk ps_0/pl0_ref_clk
set ps_axi_aclk ps_0/m_axi_fpd_aclk
""" + registers + clock_reset + mappings + r"""
if {[dict size $ports] != 8} {error "Expected eight unique USB ports"}
if {[lsearch -exact $intf_nets {axi_interconnect_0/M14_AXI usb_interconnect_0/S00_AXI}] < 0} {
    error "Missing USB interconnect upstream connection"
}
foreach pin {usb_interconnect_0/aclk usb_interconnect_0/aresetn} {
    if {[string first $pin $nets] < 0} {error "Missing USB clock/reset: $pin"}
}
foreach bus {COMBO DEV0_MEM DEV1_CSR DEV1_MEM} offset {0xA4200000 0xA4300000 0xA4400000 0xA4500000} {
    set seen 0
    foreach assignment $addresses {
        if {[lindex $assignment 6] eq "caliptra_package_top_0/S_AXI_USB_$bus/reg0"} {
            if {[lindex $assignment 1] != $offset || [lindex $assignment 3] != 0x100000} {
                error "Wrong USB address or size: $assignment"
            }
            incr seen
        }
    }
    if {$seen != 6} {error "USB $bus mapped for $seen managers instead of six"}
}
puts USB_TCL_MAPPING_PASS
"""
        self.assertIn("USB_TCL_MAPPING_PASS", tcl(script))
        disabled_script = script.replace("set USB_EXPORT_PORTS 1", "set USB_EXPORT_PORTS 0")
        disabled_script = disabled_script.replace(
            "if {[dict size $ports] != 8} {error \"Expected eight unique USB ports\"}",
            "if {[dict size $ports] != 0} {error \"Disabled export created USB ports\"}",
        )
        self.assertIn("USB_TCL_MAPPING_PASS", tcl(disabled_script))


if __name__ == "__main__":
    unittest.main()
