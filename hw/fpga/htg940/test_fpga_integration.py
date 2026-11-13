import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


FPGA = Path(__file__).resolve().parents[1]
SS = FPGA.parent / "caliptra-ss"


class FpgaIntegrationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.wrapper = (FPGA / "src/caliptra_wrapper_top.sv").read_text()
        cls.subsystem = (SS / "src/integration/rtl/caliptra_ss_top.sv").read_text()
        with tempfile.TemporaryDirectory() as directory:
            generated = Path(directory) / "caliptra_ss_top.sv"
            generated.write_text(cls.subsystem)
            subprocess.run(
                [
                    "patch", "--batch", "--forward", "--fuzz=0",
                    str(generated), str(FPGA / "src/caliptra_ss_top.patch"),
                ],
                check=True, capture_output=True, text=True,
            )
            cls.generated = generated.read_text()

    def test_wrapper_subsystem_ports_exist(self):
        start = self.generated.index("module caliptra_ss_top")
        header = self.generated[start:self.generated.index("\n);", start)]
        start = self.wrapper.index(") caliptra_ss_top_0 (")
        instance = self.wrapper[start:self.wrapper.index("\n);", start)]
        connections = re.findall(r"\.(cptra\w+)\s*\(", instance)
        self.assertTrue(connections)
        for port in set(connections):
            with self.subTest(port=port):
                self.assertRegex(header, rf"\b{port}\b")

    def test_wrapper_subsystem_parameters_exist(self):
        start = self.generated.index("module caliptra_ss_top")
        header = self.generated[start:self.generated.index(") (", start)]
        start = self.wrapper.index("caliptra_ss_top #(")
        parameters = self.wrapper[start:self.wrapper.index(") caliptra_ss_top_0", start)]
        connections = re.findall(r"\.(\w+)\s*\(", parameters)
        self.assertTrue(connections)
        for parameter in connections:
            with self.subTest(parameter=parameter):
                self.assertRegex(header, rf"\b{parameter}\b")

    def test_removed_subsystem_spi_uart_connections_absent(self):
        for legacy in (
            "SPI_HOST_ENA", "UART_ENA", "htg940_unused_spi_host_axi",
            "htg940_unused_uart_axi", "cptra_ss_spi_host_s_axi_if",
            "cptra_ss_uart_s_axi_if", "cptra_ss_sd_i", "cptra_ss_uart_rx_i",
        ):
            with self.subTest(legacy=legacy):
                self.assertNotIn(legacy, self.wrapper)
        self.assertRegex(
            self.generated, r"ext_int\[`VEER_INTR_VEC_RSVD4\]\s*=\s*1'b0;",
        )
        self.assertRegex(
            self.generated, r"ext_int\[`VEER_INTR_VEC_RSVD5\]\s*=\s*1'b0;",
        )

    def test_full_profile_clock_and_board_timing_are_consistent(self):
        flow = (FPGA / "htg940_usb_min_ila/run_dual_ila.tcl").read_text()
        board = (FPGA / "board/htg940_board_top.sv").read_text()
        connection = (FPGA / "board/connect_htg940_board.tcl").read_text()
        debug = (FPGA / "htg940_usb_min_ila/add_dual_ila.tcl").read_text()
        config = (FPGA / "fpga_configuration_htg940_hw.tcl").read_text()
        self.assertIn("set htgCoreClockMHz 60", flow)
        self.assertIn("CORE_CLK_MHZ=$htgCoreClockMHz", flow)
        self.assertIn("CORE_CLK_HZ=60000000", flow)
        self.assertNotIn("htg940_40mhz_20260928", flow)
        self.assertIn("CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $CORE_CLK_MHZ", config)
        self.assertIn("set htgI3cClockPin htg940_i3c_clocks/clk_out1", config)
        self.assertIn("set htgClockLockedPin htg940_clocks_locked/Res", config)
        self.assertIn("[get_bd_pins $htgClockLockedPin]", config)
        self.assertIn("board_clock_locked $htgClockLockedPin", connection)
        self.assertIn("HTG940_EXACT_CLOCK_PASS", config)
        self.assertIn("CORE_CLK_HZ=[expr {int($CORE_CLK_MHZ * 1000000)}]", connection)
        self.assertIn(".CLK_HZ(CORE_CLK_HZ)", board)
        self.assertIn("PHY_HOLD_CYCLES = CORE_CLK_HZ / 100", board)
        self.assertIn("$clog2(PHY_HOLD_CYCLES + 1)", board)
        self.assertIn("C_CLK_INPUT_FREQ_HZ [expr {$htgCoreClockMHz * 1000000}]", debug)

    def test_usb_policy_and_phy_tieoffs_preserved(self):
        for port, value in {
            "combo_enable_axi_user_filtering_i": "0",
            "dev1_enable_axi_user_filtering_i": "0",
        }.items():
            with self.subTest(port=port):
                self.assertIn(f".cptra_ss_usb_{port}(1'b{value})", self.wrapper)
        for port, value in {
            "sys_donotwakeup_n": "1",
            "sys_dev_wakeup_n": "1",
            "USB_EnableHub": "0",
            "USB_self_powered": "1",
        }.items():
            with self.subTest(port=port):
                self.assertRegex(self.generated, rf"\.{port}\s*\(1'b{value}\)")
        usb = (SS / "third_party/usb2/src/integration/rtl/"
               "ip_xxx_3511_hs_mem_compound_wrapper.sv").read_text()
        self.assertIn(".C_UTMI_SUPPORT(1'b0)", usb)
        self.assertIn(".C_ULPI_SUPPORT(1'b1)", usb)

    def test_ulpi_tristate_preserved(self):
        self.assertIn("ulpi_bit < 8", self.wrapper)
        for connection in (
            ".IO(USB_ULPI_DATA[ulpi_bit])",
            ".I(usb_ulpi_txdata[ulpi_bit])",
            ".O(usb_ulpi_rxdata[ulpi_bit])",
            ".T(~usb_ulpi_txenable)",
            ".cptra_ss_usb_ulpi_txenable_o(usb_ulpi_txenable)",
        ):
            self.assertIn(connection, self.wrapper)

    def test_subsystem_usb_connections_match_updated_wrapper(self):
        usb = (SS / "third_party/usb2/src/integration/rtl/"
               "ip_xxx_3511_hs_mem_compound_wrapper.sv").read_text()
        header = usb[:usb.index("\n);")]
        start = self.generated.index(") usb_core_i (")
        instance = self.generated[start:self.generated.index("\n    );", start)]
        for port in re.findall(r"\.(\w+)\s*\(", instance):
            with self.subTest(port=port):
                self.assertRegex(header, rf"\b{port}\b")
        for port in ("vbuscomp_on", "chrgvbus", "dischrgvbus", "avalid", "sessend"):
            self.assertNotRegex(self.wrapper, rf"\.cptra_ss_usb_{port}_[io]\s*\(")

    def test_hub_descriptor_capacity_matches_usb_release(self):
        usb = (SS / "third_party/usb2/src/integration/rtl/"
               "ip_xxx_3511_hs_mem_compound_wrapper.sv").read_text()
        capacity = int(re.search(r"\.USB_C_HUB_FIFO_SIZE\((\d+)\)", self.wrapper)[1])
        minimum = int(re.search(r"HUB_FIFO_SIZE_MIN = (\d+)", usb)[1])
        default = int(re.search(r"C_HUB_FIFO_SIZE = (\d+)", usb)[1])
        self.assertGreaterEqual(capacity, minimum)
        self.assertEqual(capacity, default)
        ss_default = int(re.search(r"USB_C_HUB_FIFO_SIZE = (\d+)", self.generated)[1])
        self.assertEqual(ss_default, capacity)

    def test_usb_header_matches_hub_register_map(self):
        header = (SS / "src/integration/rtl/soc_address_map/soc_address_map.h").read_text()
        hub = (SS / "third_party/usb2/systemrdl/usb_hub.rdl").read_text()
        combo = (SS / "third_party/usb2/systemrdl/usb_combo.rdl").read_text()
        control = int(re.search(r"}\s*CONTROL\s*@\s*(0x[0-9a-fA-F]+)", hub)[1], 16)
        hub_base = int(re.search(r"\)\s*hub\s*@\s*(0x[0-9a-fA-F]+)", combo)[1], 16)
        offset = int(re.search(r"#define HUB_CONTROL\s+\((0x[0-9a-fA-F]+)\)", header)[1], 16)
        address = int(re.search(
            r"#define SOC_USB_COMBO_HUB_CONTROL\s+\((0x[0-9a-fA-F]+)\)", header,
        )[1], 16)
        self.assertEqual(offset, control)
        self.assertEqual(address, 0x20000000 + hub_base + control)
        self.assertNotRegex(header, r"#define DEV0_CSR_ULPIDEBUG\s")

    def test_core_dependencies_match_upstream_gitlinks(self):
        for parent, child in (
            (SS, "third_party/caliptra-rtl"),
            (SS / "third_party/caliptra-rtl", "submodules/adams-bridge"),
        ):
            with self.subTest(child=child):
                tree = subprocess.run(
                    ["git", "-C", str(parent), "ls-tree", "HEAD", child],
                    check=True, capture_output=True, text=True,
                ).stdout
                head = subprocess.run(
                    ["git", "-C", str(parent / child), "rev-parse", "HEAD"],
                    check=True, capture_output=True, text=True,
                ).stdout.strip()
                self.assertEqual(tree.split()[2], head)

    @staticmethod
    def generate_usb_debug_sources(directory, force=False, software=False):
        script = (
            f"set fpgaDir {{{FPGA}}}\nset outputDir {{{directory}}}\n"
            f"set htgForceUlpiMode {int(force)}\n"
            f"set htgSoftwareUlpiStartup {int(software)}\n"
        ) + r"""
set ssrtlDir [file join $fpgaDir .. caliptra-ss]
set files {}
proc add_files {args} {
    global files
    foreach arg $args {
        if {[string match -* $arg]} {continue}
        if {![file isfile $arg]} {error "Missing source: $arg"}
        lappend files $arg
    }
}
proc get_files {args} {
    global files
    set result {}
    foreach f $files {
        if {[string match [lindex $args end] $f]} {lappend result $f}
    }
    return $result
}
proc set_property {args} {}
proc get_property {args} {return rtl}
proc current_fileset {} {return sources_1}
proc remove_files {args} {}
if {[catch {
    source [file join $fpgaDir htg940_usb_compound_sources.tcl]
    set wrapperGenerated [file join $outputDir wrapper.sv]
    file copy [file join $fpgaDir src caliptra_wrapper_top.sv] $wrapperGenerated
    source [file join $fpgaDir htg940_usb_min_ila prepare_debug_sources.tcl]
} message]} {puts stderr $message; exit 1}
"""
        result = subprocess.run(
            ["tclsh"], input=script, capture_output=True, text=True,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    def test_usb_debug_sources_generate_with_current_release(self):
        with tempfile.TemporaryDirectory() as directory:
            self.generate_usb_debug_sources(directory)
            pie = (Path(directory) / "htg_debug_usb_pie.m.vhdl").read_text()
            self.assertNotIn("usb_pie_fpga", pie)
            self.assertIn("t_ulpi_oper_state'pos(ulpi_oper_state_r)", pie)
            self.assertRegex(pie, r"(?i)use\s+ieee\.numeric_std\.all")
            states = re.search(
                r"(?is)type\s+t_ulpi_oper_state\s+is\s*\((.*?)\);", pie,
            )[1]
            self.assertLessEqual(len(states.split(",")), 32)

    def test_force_ulpi_changes_only_build_local_shared_mode(self):
        rtl = SS / "third_party/usb2/src/usb_hub_composite_device/RTL"
        original = (rtl / "STRUCTURE/ip_xxx_3511_hs_mem_compound_structure.a.vhdl").read_bytes()
        with tempfile.TemporaryDirectory() as normal, tempfile.TemporaryDirectory() as forced:
            self.generate_usb_debug_sources(normal)
            self.generate_usb_debug_sources(forced, force=True)
            name = "htg_debug_ip_xxx_3511_hs_mem_compound_structure.a.vhdl"
            baseline = (Path(normal) / name).read_text()
            candidate = (Path(forced) / name).read_text()
            self.assertRegex(baseline, r"hub_phy_mode\s*=>\s*usbreg_phy_mode")
            self.assertNotIn("usbreg_phy_mode <= '1';", baseline)
            self.assertRegex(candidate, r"hub_phy_mode\s*=>\s*open")
            self.assertEqual(candidate.count("usbreg_phy_mode <= '1';"), 1)
            restored = re.sub(
                r"hub_phy_mode\s*=>\s*open",
                "hub_phy_mode         => usbreg_phy_mode", candidate,
            ).replace(
                "-- HTG940 diagnostic: select ULPI even while subsystem reset is asserted.\n"
                "usbreg_phy_mode <= '1';\n\n", "",
            )
            self.assertEqual(restored, baseline)
            for name in (
                "htg_debug_usb_pie.m.vhdl",
                "htg_debug_usb_synchronizer.m.vhdl",
                "htg_debug_usb_reg_if.m.vhdl",
                "wrapper.sv",
            ):
                self.assertEqual((Path(normal) / name).read_bytes(),
                                 (Path(forced) / name).read_bytes())
            self.assertEqual((Path(normal) / "htg_phy_mode.txt").read_text().strip(),
                             "REGISTER_CONTROLLED")
            self.assertEqual((Path(forced) / "htg_phy_mode.txt").read_text().strip(),
                             "FORCED_ULPI")
        self.assertEqual(
            (rtl / "STRUCTURE/ip_xxx_3511_hs_mem_compound_structure.a.vhdl").read_bytes(),
            original,
        )

    def test_software_ulpi_startup_preserves_mode_and_register_reset(self):
        rtl = SS / "third_party/usb2/src/usb_hub_composite_device/RTL"
        source = rtl / "STRUCTURE/ip_xxx_3511_hs_mem_compound_structure.a.vhdl"
        original = source.read_bytes()
        with tempfile.TemporaryDirectory() as normal, tempfile.TemporaryDirectory() as software:
            self.generate_usb_debug_sources(normal)
            self.generate_usb_debug_sources(software, software=True)
            name = "htg_debug_ip_xxx_3511_hs_mem_compound_structure.a.vhdl"
            baseline = (Path(normal) / name).read_text()
            candidate = (Path(software) / name).read_text()
            self.assertRegex(candidate, r"hub_phy_mode\s*=>\s*usbreg_phy_mode")
            self.assertNotIn("usbreg_phy_mode <= '1';", candidate)
            self.assertIn("assert C_ULPI_SUPPORT and not C_UTMI_SUPPORT", candidate)
            self.assertEqual(candidate.count("pie_clk <="), 1)
            self.assertIn("pie_clk <= ulpi_clk;", candidate)
            self.assertNotIn("utmi_clk when phy_mode", candidate)
            self.assertIn(
                "htg_pie_reset_n <= hresetn and (usbreg_phy_mode or testmode);",
                candidate,
            )
            self.assertIn(
                "proc_pie_reset_gen : process(htg_pie_reset_n,pie_clk)\n"
                "  begin\n    if htg_pie_reset_n = '0' then",
                candidate,
            )
            self.assertIn(
                "elsif pie_clk'event and pie_clk = '1' then\n"
                "      sync_s_reset_n  <= '1';\n"
                "      sync_ss_reset_n <= sync_s_reset_n;",
                candidate,
            )
            self.assertEqual(candidate.count("=> htg_pie_reset_n"), 0)
            for name in (
                "htg_debug_usb_pie.m.vhdl",
                "htg_debug_usb_synchronizer.m.vhdl",
                "htg_debug_usb_reg_if.m.vhdl",
                "wrapper.sv",
            ):
                self.assertEqual((Path(normal) / name).read_bytes(),
                                 (Path(software) / name).read_bytes())
            self.assertEqual(
                (Path(software) / "htg_phy_mode.txt").read_text().strip(),
                "SOFTWARE_ULPI_STARTUP",
            )
            for component in ("usb_ahb_slave", "usb_synchronizer", "usb_ep0_hub_descr"):
                instances = list(re.finditer(rf"\b\w+\s*:\s*{component}\b", baseline))
                self.assertTrue(instances, component)
                for match in instances:
                    start = match.start()
                    instance = baseline[start:baseline.index(");", start) + 2]
                    self.assertIn(instance, candidate)
        self.assertEqual(source.read_bytes(), original)

    def test_software_ulpi_and_forced_generator_are_mutually_exclusive(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "mutually exclusive"):
                self.generate_usb_debug_sources(directory, force=True, software=True)

    def test_force_ulpi_runner_guards_and_argument_forwarding(self):
        runner = (FPGA / "htg940_usb_min_ila/run_dual_ila.tcl").read_text()
        cases = (
            ("FORCE_ULPI_MODE", None, "requires a separate BUILD_NAME"),
            ("BUILD_NAME=build_full_test VERSION=invalid", None, "VERSION must be"),
            ("BUILD_NAME=build_full_test FORCE_ULPI_MODE VERSION=52a124ef",
             None, "FRESH 1 VERSION=52a124ef"),
            ("BUILD_NAME=build_full_test", None, "FRESH 0"),
            ("BUILD_NAME=build_full_test RESUME FORCE_ULPI_MODE",
             "FORCED_ULPI", "VALID_RESUME"),
            ("BUILD_NAME=build_full_test RESUME FORCE_ULPI_MODE",
             "", "PHY mode mismatch"),
            ("BUILD_NAME=build_full_test RESUME",
             "FORCED_ULPI", "PHY mode mismatch"),
            ("BUILD_NAME=build_full_test RESUME", "", "VALID_RESUME"),
            ("SOFTWARE_ULPI_STARTUP", None, "requires a separate BUILD_NAME"),
            ("BUILD_NAME=build_full_test FORCE_ULPI_MODE SOFTWARE_ULPI_STARTUP",
             None, "mutually exclusive"),
            ("BUILD_NAME=build_full_test SOFTWARE_ULPI_STARTUP VERSION=52a124ef",
             None, "FRESH 0 VERSION=52a124ef SOFTWARE=1"),
            ("BUILD_NAME=build_full_test SOFTWARE_ULPI_STARTUP RESUME",
             "SOFTWARE_ULPI_STARTUP", "VALID_RESUME"),
            ("BUILD_NAME=build_full_test SOFTWARE_ULPI_STARTUP RESUME",
             "FORCED_ULPI", "PHY mode mismatch"),
            ("BUILD_NAME=build_full_test SOFTWARE_ULPI_STARTUP RESUME",
             "", "PHY mode mismatch"),
            ("BUILD_NAME=build_full_test RESUME",
             "SOFTWARE_ULPI_STARTUP", "PHY mode mismatch"),
            ("BUILD_NAME=build_mcu_usb_only_test MCU_USB_ONLY SOFTWARE_ULPI_STARTUP",
             None, "requires a separate BUILD_NAME"),
        )
        for args, saved_mode, expected in cases:
            with self.subTest(args=args, saved_mode=saved_mode), \
                    tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                diagnostic = root / "htg940_usb_min_ila"
                diagnostic.mkdir()
                script_path = diagnostic / "run_dual_ila.tcl"
                script_path.write_text(runner)
                if saved_mode is not None:
                    build = diagnostic / "build_full_test"
                    build.mkdir()
                    (build / "caliptra_htg940_project.xpr").touch()
                    if saved_mode:
                        (build / "htg_phy_mode.txt").write_text(saved_mode)
                script = f"set argv {{{args}}}\n" + r"""
proc open_project {args} {}
proc get_filesets {args} {return sources_1}
proc get_runs {args} {return synth_1}
proc get_property {name args} {
    switch $name {
        generic {return CORE_CLK_HZ=60000000}
        PROGRESS {return 100%}
        NEEDS_REFRESH {return 0}
        default {error "Unexpected property: $name"}
    }
}
rename source real_source
proc source {path} {
    global argv htgForceUlpiMode htgSoftwareUlpiStartup
    if {[file tail $path] eq "fpga_configuration_htg940_hw.tcl"} {
        error "FRESH $htgForceUlpiMode [lsearch -inline -glob $argv VERSION=*] SOFTWARE=$htgSoftwareUlpiStartup"
    }
    if {[file tail $path] eq "isolate_dual_ila_constraints.tcl"} {
        error VALID_RESUME
    }
    error "Unexpected source: $path"
}
""" + f"\nif {{[catch {{real_source {{{script_path}}}}} message]}} {{puts $message}}\n"
                result = subprocess.run(
                    ["tclsh"], input=script, capture_output=True, text=True, check=True,
                )
                self.assertIn(expected, result.stdout, result.stdout + result.stderr)

    def test_rom_patch_sram_connected_with_ecc(self):
        self.assertIn(".MCU_ROM_PATCH_SRAM_SIZE_KB(4)", self.wrapper)
        self.assertIn(".ADDR_WIDTH(10)", self.wrapper)
        start = self.wrapper.index("// Upstream MCI exposes")
        ram = self.wrapper[start:self.wrapper.index("mci_mcu_sram_if cptra_ss_mcu_mbox0", start)]
        for parameter in (
            ".ADDR_WIDTH_A(10)", ".MEMORY_SIZE(1024*39)",
            ".READ_DATA_WIDTH_A(39)", ".WRITE_DATA_WIDTH_A(39)",
            ".READ_LATENCY_A(1)",
        ):
            self.assertIn(parameter, ram)
        for port, signal in {
            "douta": "resp.rdata", "addra": "req.addr", "dina": "req.wdata",
            "ena": "req.cs", "wea": "req.we",
        }.items():
            self.assertIn(f".{port}(cptra_ss_mcu_rom_patch_sram_req_if.{signal})", ram)
        self.assertIn(
            ".cptra_ss_mcu_rom_patch_sram_req_if(cptra_ss_mcu_rom_patch_sram_req_if)",
            self.wrapper,
        )

    def test_i3c_cdc_and_upstream_allowlist_preserved(self):
        self.assertIn(".clk_i                          (cptra_i3c_clk_i)", self.generated)
        self.assertIn(".rst_ni                         (i3c_rst_sync)", self.generated)
        for index, strap in enumerate(("caliptra_dma", "mcu_lsu") * 2):
            self.assertIn(
                f"assign priv_ids[{index}] = cptra_ss_strap_{strap}_axi_user_i_synch;",
                self.generated,
            )
        self.assertIn("(disable_id_filtering_i_synch)", self.generated)
        self.assertIn("(i3c_irq_o_presync)", self.generated)
        self.assertIn("import css_mcu0_el2_pkg::*;", self.generated)
        self.assertNotIn('`include "css_mcu0_el2_pdef.vh"', self.generated)
        self.assertNotIn('`include "i3c_defines.svh"', self.wrapper)

    def test_fuse_access_bounds_match_upstream_table(self):
        package = (SS / "src/fuse_ctrl/rtl/otp_ctrl_pkg.sv").read_text()
        control = (SS / "src/fuse_ctrl/rtl/fuse_ctrl_filter.sv").read_text()
        bounds = re.findall(
            r"lower_addr:\s*(32'h[0-9A-Fa-f]+),\s*upper_addr:\s*(32'h[0-9A-Fa-f]+)",
            package,
        )
        self.assertEqual(len(bounds), 3)
        for index, (lower, upper) in enumerate(bounds):
            with self.subTest(index=index):
                self.assertRegex(
                    control,
                    rf"wr_allowed_vec\[{index}\]\s*=\s*"
                    rf"\(fuse_addr >= {lower}\) &&\s*"
                    rf"\(fuse_addr <= {upper}\)",
                )

    def test_ss_recursive_submodules_follow_parent_gitlinks(self):
        result = subprocess.run(
            ["git", "-C", str(SS), "submodule", "status", "--recursive"],
            check=True, capture_output=True, text=True,
        )
        lines = result.stdout.splitlines()
        self.assertTrue(lines)
        pins = {
            entry["path"]: entry["commit"]
            for entry in json.loads(
                (FPGA / "htg940/submodule_pins.json").read_text()
            )
        }
        for line in lines:
            with self.subTest(submodule=line):
                self.assertEqual(line[0], " ", "Submodule differs from parent gitlink")
                commit, path = line[1:].split()[:2]
                self.assertEqual(pins[f"hw/caliptra-ss/{path}"], commit)

    def test_upstream_iccm_hash_retains_lock_gate(self):
        source = (SS / "third_party/caliptra-rtl/src/soc_ifc/rtl/"
                  "sha512_acc_iccm_hash.sv").read_text()
        self.assertRegex(
            source,
            r"iccm_hash_trigger\s*=\s*\(iccm_hash_dv_i \| iccm_lock_i\)"
            r" & ~soc_has_lock & ~lock_value;",
        )
        self.assertIn("(iccm_armed | iccm_hash_trigger) & ~iccm_mode_done", source)
        self.assertIn("else if (iccm_hash_trigger & ~iccm_mode_done)", source)

    def test_spare_i3c_uses_explicit_upstream_configuration(self):
        start = self.wrapper.index("i3c_wrapper #(")
        instance = self.wrapper[start:self.wrapper.index("\n    );", start)]
        for connection in (
            ".UseAxi(1'b1)", ".EnableIdFiltering(1'b1)", ".NumPrivIds(4)",
            ".disable_id_filtering_i(1'b1)", ".priv_ids_i('{default: '0})",
            ".hsel_i(1'b0)", ".hready_i(1'b1)", ".htrans_i(2'b00)",
        ):
            self.assertIn(connection, instance)
        self.assertNotIn("`ifdef AXI_ID_FILTERING", self.wrapper)

    def test_patches_reconstruct_prepared_files(self):
        pins = json.loads((FPGA / "htg940/submodule_pins.json").read_text())
        for pin in pins:
            if "patch" not in pin:
                continue
            repository = FPGA.parents[1] / pin["path"]
            patch = FPGA / "htg940/submodule_patches" / pin["patch"]
            names = re.findall(r"^diff --git a/(\S+) b/\S+$", patch.read_text(), re.MULTILINE)
            self.assertTrue(names)
            with self.subTest(repository=pin["path"]), tempfile.TemporaryDirectory() as directory:
                for name in names:
                    base = subprocess.run(
                        ["git", "-C", str(repository), "show", f"{pin['commit']}:{name}"],
                        check=True, capture_output=True,
                    ).stdout
                    path = Path(directory) / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(base)
                subprocess.run(
                    ["git", "-C", directory, "apply", str(patch)],
                    check=True, capture_output=True,
                )
                for name in names:
                    self.assertEqual(
                        (Path(directory) / name).read_bytes(),
                        (repository / name).read_bytes(),
                    )


if __name__ == "__main__":
    unittest.main()
