import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


BOARD = Path(__file__).resolve().parents[1] / "board"


class BoardTimingTest(unittest.TestCase):
    def test_60mhz_phy_hold_and_115200_uart(self):
        binaries = {}
        for name in ("xvlog", "xelab", "xsim"):
            executable = (
                str(Path(os.environ["VIVADO_BIN"]) / name)
                if "VIVADO_BIN" in os.environ else shutil.which(name)
            )
            if not executable or not Path(executable).is_file():
                self.skipTest("Set VIVADO_BIN to run the board timing simulation")
            binaries[name] = executable
        source = (BOARD / "htg940_board_top.sv").read_text()
        instance = source[source.index("caliptra_htg940_bd_wrapper u_system"):]
        names = re.findall(r"\.(\w+)\(", instance)
        outputs = {
            "board_core_clk": "ref_clock_156p25mhz_clk_p",
            "board_reset_n": "reset_n",
            "board_clock_locked": "1'b1",
            "board_mcu_log_valid": "1'b0",
            "board_core_log_valid": "1'b0",
            "board_mcu_log_byte": "8'b0",
            "board_core_log_byte": "8'b0",
            "host_entropy_req": "1'b0",
            "EXT_SDA_IN": "1'b0",
            "EXT_SDA_EN": "1'b1",
            "EXT_SDA_UP": "1'b0",
            "USB_ULPI_STP": "1'b0",
            "jtag_out": "15'b0",
        }
        widths = {
            "board_mcu_log_byte": "[7:0] ", "board_core_log_byte": "[7:0] ",
            "host_entropy_data": "[3:0] ", "USB_ULPI_DATA": "[7:0] ",
            "jtag_in": "[14:0] ", "jtag_out": "[14:0] ",
        }
        stub = "module caliptra_htg940_bd_wrapper (\n" + ",\n".join(
            f"  {'inout' if name == 'USB_ULPI_DATA' else 'output' if name in outputs else 'input'} "
            f"wire {widths.get(name, '')}{name}"
            for name in names
        ) + "\n);\n" + "\n".join(
            f"assign {name} = {value};" for name, value in outputs.items()
        ) + "\nendmodule\n"
        testbench = r"""
`timescale 1ns/1ps
module IOBUF(inout wire IO, input wire I, T, output wire O);
  assign IO = T ? 1'bz : I;
  assign O = IO;
endmodule

module board_timing_tb;
  reg clk = 0, reset_n = 0, rx = 1, reply_valid = 0;
  wire phy_reset_n, tx, cmd_valid;
  wire [7:0] cmd;
  wire [31:0] cmd_data;
  reg uart_done = 0;
  realtime hold_start, hold_time;
  localparam realtime BIT_NS = 1000000000.0 / 115200;
  always #8.333 clk = ~clk;
  htg940_board_top #(.CORE_CLK_HZ(60000000)) dut (
    .ref_clock_156p25mhz_clk_p(clk), .ref_clock_156p25mhz_clk_n(~clk),
    .resetn_i(reset_n), .usb_phy_resetn_i(1'b1),
    .usb_phy_resetn_o(phy_reset_n), .host_uart_rx_i(1'b1),
    .cptra_ss_usb_ulpi_clk_i(clk), .cptra_ss_usb_ulpi_dir_i(1'b0),
    .cptra_ss_usb_ulpi_nxt_i(1'b0), .cptra_ss_i3c_scl_io(1'b0)
  );
  htg940_entropy_uart #(.CLK_HZ(60000000)) uart (
    .clk(clk), .reset_n(reset_n), .uart_rx(rx), .uart_tx(tx),
    .cmd_valid(cmd_valid), .cmd(cmd), .cmd_data(cmd_data),
    .reply_valid(reply_valid), .reply_code(8'h00), .reply_data(32'h12345678)
  );
  task send_byte(input [7:0] value);
    rx = 0; #(BIT_NS);
    for (integer i = 0; i < 8; i++) begin rx = value[i]; #(BIT_NS); end
    rx = 1; #(BIT_NS);
  endtask
  task receive_byte(input [7:0] expected);
    reg [7:0] value;
    @(negedge tx); #(BIT_NS * 1.5);
    for (integer i = 0; i < 8; i++) begin
      value[i] = tx; #(BIT_NS);
    end
    if (tx !== 1'b1 || value !== expected)
      $fatal(1, "UART response mismatch: expected %02x, got %02x", expected, value);
  endtask
  initial begin
    #100; reset_n = 1;
    wait(dut.phy_reset_sync[1] === 1'b1);
    hold_start = $realtime;
    if (dut.PHY_HOLD_CYCLES != 600000 || $bits(dut.phy_hold_count) != 20 ||
        dut.u_entropy_uart.DIV != 521)
      $fatal(1, "60 MHz board timing parameters incorrect");
    repeat (599999) begin
      @(posedge clk); #0.001;
      if (phy_reset_n !== 1'b0) $fatal(1, "PHY reset released early");
    end
    @(posedge clk); #0.001;
    hold_time = $realtime - hold_start;
    if (phy_reset_n !== 1'b1 || dut.phy_hold_count != 600000 ||
        hold_time < 9999000 || hold_time > 10001000)
      $fatal(1, "PHY hold is not 600000 cycles / approximately 10 ms: %f ns", hold_time);
    repeat (4) @(posedge clk);
    if (dut.phy_hold_count != 600000 || !uart_done)
      $fatal(1, "Reset counter did not saturate or UART test did not finish");
    reset_n = 0; #1;
    if (phy_reset_n !== 1'b0) $fatal(1, "PHY reset did not assert asynchronously");
    $display("BOARD_60MHZ_TIMING_PASS");
    $finish;
  end
  initial begin
    wait(reset_n); #100;
    send_byte(8'ha5); send_byte(8'h02); send_byte(8'h00);
    repeat (4) send_byte(8'h00);
    send_byte(8'ha7); send_byte(8'h5a);
  end
  initial begin
    wait(cmd_valid);
    if (cmd !== 8'h02 || cmd_data !== 32'h00000000)
      $fatal(1, "115200 baud UART request was not decoded");
    @(negedge clk); reply_valid = 1;
    @(negedge clk); reply_valid = 0;
  end
  initial begin
    receive_byte(8'ha5); receive_byte(8'h82); receive_byte(8'h00);
    receive_byte(8'h78); receive_byte(8'h56); receive_byte(8'h34);
    receive_byte(8'h12); receive_byte(8'ha5 ^ 8'h82 ^ 8'h78 ^ 8'h56 ^ 8'h34 ^ 8'h12);
    receive_byte(8'h5a);
    uart_done = 1;
  end
  initial begin #12000000; $fatal(1, "Board timing test timed out"); end
endmodule
"""
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / "board_timing_tb.sv").write_text(testbench + stub)
            commands = (
                [binaries["xvlog"], "--sv", *map(str, (
                    BOARD / "htg940_board_top.sv",
                    BOARD / "htg940_entropy_uart.sv",
                    BOARD / "htg940_entropy_control.sv",
                    BOARD / "htg940_log_bridge.sv",
                    work / "board_timing_tb.sv",
                ))],
                [binaries["xelab"], "board_timing_tb", "--timescale", "1ns/1ps",
                 "-s", "board_timing"],
                [binaries["xsim"], "board_timing", "-runall"],
            )
            for command in commands:
                result = subprocess.run(
                    command, cwd=work, capture_output=True, text=True, timeout=120,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            log = (work / "xsim.log").read_text()
            self.assertNotIn("Fatal:", log)
            self.assertIn("BOARD_60MHZ_TIMING_PASS", log)


if __name__ == "__main__":
    unittest.main()
