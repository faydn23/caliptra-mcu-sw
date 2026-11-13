import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).parent


class MinimalProbeTest(unittest.TestCase):
    def schema(self):
        script = (
            f"source {{{ROOT / 'probe_schema.tcl'}}}\n"
            "foreach domain {ulpi core} {\n"
            "  foreach spec [set htg_${domain}_schema] {\n"
            "    puts \"$domain [join $spec { }]\"\n"
            "  }\n"
            "}\n"
        )
        result = subprocess.run(
            ["tclsh"], input=script, capture_output=True, text=True, check=True,
        )
        schemas = {"ulpi": [], "core": []}
        for line in result.stdout.splitlines():
            domain, instance, signal, width = line.split()
            schemas[domain].append((instance, signal, int(width)))
        return schemas

    def test_core_observes_active_hub_not_old_dev0_phy(self):
        core = self.schema()["core"]
        for signal, width in (
            ("usbreg_phy_addr", 8), ("usbreg_phy_wdata", 8),
            ("usbreg_phy_write", 1), ("usbreg_phy_start", 1),
            ("usbreg_phy_mode", 1), ("sync_phy_endtoggle", 1),
            ("sync_phy_rdata", 8), ("clock_on", 1),
        ):
            self.assertIn(("u_hub_compound", signal, width), core)
        self.assertEqual(
            [entry for entry in core if entry[0] == "usb_reg_if_1"],
            [("usb_reg_if_1", "hresetn", 1)],
        )

    def test_minimal_width_and_no_duplicate_schema_entries(self):
        schemas = self.schema()
        self.assertEqual(sum(width for _, _, width in schemas["ulpi"]), 26)
        self.assertEqual(sum(width for _, _, width in schemas["core"]), 30)
        for entries in schemas.values():
            self.assertEqual(len(entries), len(set(entries)))

    def test_motor_state_reset_and_completion_retained(self):
        ulpi = self.schema()["ulpi"]
        for signal, width in (
            ("htg_ulpi_state", 5), ("reset_n", 1), ("phy_start", 1),
            ("phy_address", 8), ("phy_write", 1),
            ("ulpi_xreg_rdata_r", 8), ("phy_endtoggle_r", 1),
        ):
            self.assertIn(("usb_pie_1", signal, width), ulpi)

    def test_physical_clock_and_resets_retained_on_core_ila(self):
        source = (ROOT / "add_dual_ila.tcl").read_text()
        for label in (
            "ULPI_CLOCK_ACTIVITY_SYNC", "PHY_RESET_N_INPUT_RAW",
            "PHY_RESET_N_OUTPUT_TO_DAUGHTER",
        ):
            self.assertIn(f"lappend coreProbes [list {label}", source)
        self.assertIn("min_pad_buffer usb_phy_resetn_i IBUF I", source)
        self.assertIn("min_pad_buffer usb_phy_resetn_o OBUF O", source)


if __name__ == "__main__":
    unittest.main()
