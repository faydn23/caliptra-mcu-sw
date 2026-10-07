#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check that E2E preparation does not change functional RTL or drop bus ports."""

import subprocess
import tempfile
import unittest
from pathlib import Path

TESTS = Path(__file__).resolve().parent
FPGA = TESTS.parent


class E2ePreparationTests(unittest.TestCase):
    def test_assertion_guard_only(self):
        source = FPGA.parent / (
            "caliptra-ss/third_party/usb2/src/usb_hub_composite_device/"
            "RTL/RTL/usb_ocp_recovery_post_sync_arb.m.vhdl"
        )
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "assertions.vhdl"
            subprocess.run(["python3", str(TESTS / "prepare_usb_e2e_assertions.py"),
                            str(source), str(output)], check=True)
            original = source.read_text()
            generated = output.read_text()
            modified = "elsif rising_edge(hclk) and hresetn = '1' then"
            self.assertEqual(generated.count(modified), 1)
            self.assertEqual(generated.replace(modified, "elsif rising_edge(hclk) then"), original)
            self.assertEqual(generated.count("assert "), original.count("assert "))

    def test_actual_wrapper_bindings(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "bindings.svh"
            subprocess.run(["python3", str(TESTS / "prepare_usb_e2e_bindings.py"),
                            str(FPGA / "src/caliptra_wrapper_top.sv"), str(output)], check=True)
            generated = output.read_text()
            self.assertIn("caliptra_wrapper_top #(.USB_ENABLE(1)) dut", generated)
            self.assertIn(".M_AXI_MCU_LSU_WDATA(m_wdata[0])", generated)
            self.assertIn(".S_AXI_USB_COMBO_WDATA(s_wdata[2][31:0])", generated)
            self.assertIn(".S_AXI_MCU_ROM_RDATA(s_rdata[0])", generated)
            self.assertIn(".mcu_rom_backdoor_din(rom_data)", generated)
            self.assertIn(".rom_backdoor_wrdata(core_rom_data)", generated)
            self.assertIn(".rom_backdoor_rddata(core_rom_q)", generated)
            self.assertIn(".S_AXI_WRAPPER_ARESETN(host_reset_n)", generated)
            self.assertIn(".S_AXI_WRAPPER_WVALID(host_active ? host_wvalid : s_wvalid[7])", generated)


if __name__ == "__main__":
    unittest.main()
