import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("optimize_routed_timing.tcl")


class RoutedTimingTest(unittest.TestCase):
    def run_flow(self, setup="0.1", hold="0.01", missing_path=False,
                 existing_output=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checkpoint = root / "original.dcp"
            checkpoint.write_bytes(b"original checkpoint")
            output = root / "candidate"
            if existing_output:
                output.mkdir()
            script = """
proc set_param {args} {}
proc open_checkpoint {args} {}
proc close_design {args} {}
proc get_ports {args} {return port}
proc report_timing_summary {args} {}
proc report_timing {args} {}
proc report_clock_interaction {args} {}
proc report_cdc {args} {}
proc check_timing {args} {}
proc report_drc {args} {}
proc report_route_status {args} {}
proc get_timing_paths {args} {
    if {$::missing_path} {return {}}
    return [lindex $args 1]
}
proc get_property {property path} {
    if {$path eq "max"} {return $::setup}
    return $::hold
}
proc phys_opt_design {args} {puts "PHYS_OPT $args"}
proc route_design {args} {puts "ROUTE $args"}
proc write_checkpoint {path} {
    set fh [open $path w]
    puts $fh "candidate checkpoint"
    close $fh
}
"""
            script += (
                f"set setup {{{setup}}}\nset hold {{{hold}}}\n"
                f"set missing_path {int(missing_path)}\n"
                f"set argv [list {{{checkpoint}}} {{{output}}}]\n"
                f"if {{[catch {{source {{{SCRIPT}}}}} message]}} "
                "{puts stderr $message; exit 1}\n"
            )
            result = subprocess.run(
                ["tclsh"], input=script, capture_output=True, text=True,
            )
            self.assertEqual(checkpoint.read_bytes(), b"original checkpoint")
            status = output / "result.txt"
            return result, status.read_text() if status.exists() else ""

    def test_positive_slacks_require_further_review(self):
        result, status = self.run_flow()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SLACK_GATE_PASSED_REVIEW_REQUIRED", status)
        self.assertIn("No bitstream generated", status)
        self.assertIn("PHYS_OPT -directive AggressiveExplore", result.stdout)
        self.assertIn("ROUTE -directive Explore", result.stdout)

    def test_setup_or_hold_violation_fails(self):
        for setup, hold in (("-13.338", "0.01"), ("0.1", "-2.806")):
            with self.subTest(setup=setup, hold=hold):
                result, status = self.run_flow(setup, hold)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("STATUS=TIMING_FAILED", status)

    def test_zero_slack_passes_only_slack_gate(self):
        result, status = self.run_flow("0", "0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("REVIEW_REQUIRED", status)

    def test_missing_path_is_not_success(self):
        result, status = self.run_flow(missing_path=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected one worst max timing path", result.stderr)
        self.assertEqual(status, "")
        self.assertNotIn("PHYS_OPT", result.stdout)

    def test_invalid_slack_is_not_success(self):
        for slack in ("", "invalid", "NaN", "Inf", "-Inf"):
            with self.subTest(slack=slack):
                result, status = self.run_flow(setup=slack)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid max slack", result.stderr)
                self.assertEqual(status, "")

    def test_existing_output_is_preserved(self):
        result, status = self.run_flow(existing_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to overwrite", result.stderr)
        self.assertEqual(status, "")
        self.assertNotIn("PHYS_OPT", result.stdout)


if __name__ == "__main__":
    unittest.main()
