#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate flat-port bindings for the actual Versal wrapper, not a RTL stub."""

import argparse
import re
from pathlib import Path

MASTERS = ["M_AXI_MCU_LSU", "M_AXI_MCU_IFU", "M_AXI_MCU_SB"]
TARGETS = ["S_AXI_MCU_ROM", "S_AXI_MCI", "S_AXI_USB_COMBO",
           "S_AXI_OTP", "S_AXI_LCC", "S_AXI_CALIPTRA", "S_AXI_I3C", "S_AXI_WRAPPER"]
WIDTHS = {
    "AWADDR": 32, "AWBURST": 2, "AWSIZE": 3, "AWLEN": 8,
    "AWUSER": 32, "AWID": 19, "AWLOCK": 1, "AWVALID": 1, "AWREADY": 1,
    "WDATA": 64, "WSTRB": 8, "WVALID": 1, "WREADY": 1, "WLAST": 1,
    "BRESP": 2, "BID": 19, "BVALID": 1, "BREADY": 1,
    "ARADDR": 32, "ARBURST": 2, "ARSIZE": 3, "ARLEN": 8,
    "ARUSER": 32, "ARID": 19, "ARLOCK": 1, "ARVALID": 1, "ARREADY": 1,
    "RDATA": 64, "RRESP": 2, "RID": 19, "RLAST": 1, "RVALID": 1, "RREADY": 1,
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wrapper", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    text = args.wrapper.read_text()
    header = text[text.index(") (") + 3:text.index("\n    );")]
    header = re.sub(r"/\*.*?\*/|//[^\n]*|\(\*.*?\*\)", "", header, flags=re.S)
    ports = re.findall(
        r"\b(input|output|inout)\s+(?:(?:wire|logic|reg|bit)\s*)?"
        r"(\[\s*\d+\s*:\s*0\s*\])?\s*(\w+)", header
    )
    if len(ports) < 400:
        raise ValueError(f"Unexpected wrapper port count: {len(ports)}")
    declarations = []
    for prefix, count in (("m", len(MASTERS)), ("s", len(TARGETS))):
        for field, width in WIDTHS.items():
            declarations.append(f"logic [{count - 1}:0][{width - 1}:0] {prefix}_{field.lower()};")
    connections = []
    extensions = []
    special = {
        "core_clk": "clk", "i3c_clk": "clk",
        "USB_ULPI_CLK": "phy_clk", "USB_ULPI_DATA": "phy_data",
        "USB_ULPI_DIR": "phy_dir", "USB_ULPI_NXT": "phy_nxt",
        "USB_ULPI_STP": "phy_stp", "USB_VBUS_VALID": "1'b1",
        "mcu_rom_backdoor_clk": "clk", "mcu_rom_backdoor_en": "rom_en",
        "mcu_rom_backdoor_we": "rom_we", "mcu_rom_backdoor_addr": "rom_addr",
        "mcu_rom_backdoor_din": "rom_data", "mcu_rom_backdoor_dout": "rom_q",
        "mcu_rom_backdoor_rst": "memory_reset",
        "rom_backdoor_clk": "clk", "rom_backdoor_rst": "memory_reset",
        "rom_backdoor_en": "core_rom_en", "rom_backdoor_we": "core_rom_we",
        "rom_backdoor_addr": "core_rom_addr", "rom_backdoor_wrdata": "core_rom_data",
        "rom_backdoor_rddata": "core_rom_q",
        "otp_mem_backdoor_clk": "clk", "otp_mem_backdoor_en": "otp_en",
        "otp_mem_backdoor_we": "otp_we", "otp_mem_backdoor_addr": "otp_addr",
        "otp_mem_backdoor_din": "otp_data", "otp_mem_backdoor_rst": "memory_reset",
        "S_AXI_WRAPPER_ARESETN": "host_reset_n",
        "mcu_ifu_i0_pc": "mcu_pc", "mci_boot_fsm": "boot_state",
        "axi_i3c_scl_t": "1'b1", "axi_i3c_sda_t": "1'b1",
        "axi_i3c_sda_pullup_en": "1'b1",
        "jtag_trst_n": "1'b1", "mcu_jtag_trst_n_i": "1'b1",
        "lc_jtag_trst_n_i": "1'b1",
    }
    for direction, vector, name in ports:
        expression = special.get(name)
        if expression is None and name.startswith("S_AXI_WRAPPER_"):
            field = name.removeprefix("S_AXI_WRAPPER_").lower()
            declarations.append(f"logic {vector} host_{field};")
            if field.upper() in WIDTHS:
                width = int(re.search(r"\d+", vector).group()) + 1 if vector else 1
                signal = f"s_{field}[7]"
                if width < WIDTHS[field.upper()]:
                    signal += f"[{width - 1}:0]"
                    if direction == "output":
                        extensions.append(
                            f"assign s_{field}[7][{WIDTHS[field.upper()] - 1}:{width}] = '0;"
                        )
                if direction == "input":
                    expression = f"host_active ? host_{field} : {signal}"
                else:
                    expression = signal
                    extensions.append(f"assign host_{field} = {signal};")
            else:
                expression = f"host_{field}"
        if expression is None:
            for prefix, group in (("m", MASTERS), ("s", TARGETS)):
                for index, bus in enumerate(group):
                    if name.startswith(bus + "_"):
                        field = name[len(bus) + 1:]
                        if field not in WIDTHS:
                            break
                        width = int(re.search(r"\d+", vector).group()) + 1 if vector else 1
                        expression = f"{prefix}_{field.lower()}[{index}]"
                        full = WIDTHS[field]
                        if width < full:
                            expression += f"[{width - 1}:0]"
                            if direction == "output":
                                extensions.append(
                                    f"assign {prefix}_{field.lower()}[{index}]"
                                    f"[{full - 1}:{width}] = '0;"
                                )
                        break
        if expression is None:
            if direction == "inout":
                raise ValueError(f"Unbound bidirectional port: {name}")
            expression = "'0" if direction == "input" else ""
        connections.append(f"    .{name}({expression})")
    args.output.write_text(
        "\n".join(declarations) +
        "\ncaliptra_wrapper_top #(.USB_ENABLE(1)) dut (\n" +
        ",\n".join(connections) + "\n);\n" + "\n".join(extensions) +
        "\nassign s_bid[7] = '0;\nassign s_rid[7] = '0;\nassign s_rlast[7] = 1'b1;\n"
    )


if __name__ == "__main__":
    main()
