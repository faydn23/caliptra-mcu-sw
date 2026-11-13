#!/usr/bin/env python3
"""Run the real USB2 VHDL with a deliberately limited ULPI startup model."""

import argparse
import re
import shutil
import subprocess
from pathlib import Path


HERE = Path(__file__).resolve().parent
DEFAULT_RTL = (
    HERE.parents[1]
    / "caliptra-ss/third_party/usb2/src/usb_hub_composite_device/RTL"
)


def port_map(entity):
    text = re.sub(r"--[^\n]*", "", entity.read_text())
    text = text.split("port(", 1)[1].split("end ip_xxx", 1)[0]
    connections = {
        "hclk": "core_clk",
        "hresetn": "reset_n",
        "ahbs_resetn": "reset_n",
        "utmi_clk": "core_clk",
        "ulpi_clk": "phy_clk",
        "ulpi_rxdata": "phy_data",
        "ulpi_txdata": "link_data",
        "ulpi_txenable": "link_enable",
        "ulpi_dir": "phy_dir",
        "ulpi_nxt": "phy_nxt",
        "ulpi_stp": "link_stp",
        "hub_ahbs_haddr": "hub_addr",
        "hub_ahbs_htrans": "hub_trans",
        "hub_ahbs_hwrite": "hub_write",
        "hub_ahbs_hwdata": "hub_wdata",
        "hub_ahbs_hsel": "hub_sel",
        "hub_ahbs_hrdata": "hub_rdata",
        "hub_ahbs_hreadyout": "hub_ready",
        "hub_ahbs_hresp": "hub_resp",
        "dev0_ahbs_haddr": "(others => '0')",
        "dev0_ahbs_htrans": "dev_trans",
        "dev0_ahbs_hwrite": "dev_write",
        "dev0_ahbs_hwdata": "dev_wdata",
        "dev0_ahbs_hsel": "dev_sel",
        "USB_VBus": "'1'",
        "USB_self_powered": "'1'",
        "sys_donotwakeup_n": "'1'",
        "sys_dev_wakeup_n": "'1'",
        "sys_utmi_clkin_lock": "'1'",
    }
    entries = []
    used = set()
    for declaration in text.split(";"):
        match = re.search(r"^\s*(\w+)\s*:\s*(in|out)\s+(.+)", declaration, re.S)
        if not match:
            if declaration.strip() not in ("", ");"):
                raise ValueError(f"Unparsed entity port: {declaration}")
            continue
        name, direction, kind = match.groups()
        if name in connections:
            value = connections[name]
            used.add(name)
        elif direction == "out":
            value = "open"
        elif name.endswith("hreadyin"):
            value = "'1'"
        elif "std_logic_vector" in kind:
            value = "(others => '0')"
        elif kind.strip().startswith("std_logic"):
            value = "'0'"
        else:
            raise ValueError(f"Unsupported input type: {name}: {kind}")
        entries.append(f"      {name} => {value}")
    if used != connections.keys():
        raise ValueError(f"Missing mapped ports: {connections.keys() - used}")
    return ",\n".join(entries)


def run(command, directory):
    print("+", " ".join(str(part) for part in command), flush=True)
    subprocess.run(command, cwd=directory, check=True, timeout=240)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vivado-bin", type=Path)
    parser.add_argument("--rtl", type=Path, default=DEFAULT_RTL)
    parser.add_argument("--compound-structure", type=Path,
                        help="Use a generated compound architecture instead of the original")
    parser.add_argument("--expect-forced-ulpi", action="store_true",
                        help="Test accesses with hub mode bit zero; requires a forced architecture")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.expect_forced_ulpi and not args.compound_structure:
        parser.error("--expect-forced-ulpi requires --compound-structure")
    args.rtl = args.rtl.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    bins = {}
    for name in ("xvhdl", "xelab", "xsim"):
        executable = (
            str(args.vivado_bin / name) if args.vivado_bin else shutil.which(name)
        )
        if not executable or not Path(executable).is_file():
            parser.error(f"{name} not found; specify --vivado-bin")
        bins[name] = executable
    template = (HERE / "usb_startup_tb.vhdl").read_text()
    if args.expect_forced_ulpi:
        template = template.replace(
            "constant force_ulpi_test : boolean := false;",
            "constant force_ulpi_test : boolean := true;",
        )
    entity = args.rtl / "INTERFACE/ip_xxx_3511_hs_mem_compound.e.vhdl"
    (output / "usb_startup_tb.vhdl").write_text(
        template.replace("-- DUT_PORT_MAP", port_map(entity))
    )
    # Add observation only to a simulation-local copy; do not change IP behavior.
    pie = (args.rtl / "RTL/usb_pie.m.vhdl").read_text()
    anchor = "ulpi_oper_state_r <= ulpi_oper_state_nxt;"
    if pie.count(anchor) != 1:
        raise ValueError("Expected exactly one ULPI state update")
    pie = pie.replace(
        anchor,
        """if ulpi_oper_state_r /= ulpi_oper_state_nxt then
         report "ULPI_STATE " & t_ulpi_oper_state'image(ulpi_oper_state_nxt);
      end if;
      """ + anchor,
    )
    (output / "usb_pie_observed.vhdl").write_text(pie)
    packages = [
        "usb_general_subcmp_pkg.p.vhdl",
        "usb_ep_config_hub_pkg.p.vhdl",
        "usb_subcmp_pkg.p.vhdl",
        "usb_configuration_subcmp_pkg.p.vhdl",
    ]
    sources = [args.rtl / "INTERFACE" / name for name in packages]
    sources.append(entity)
    sources.extend(
        path for path in sorted((args.rtl / "RTL").glob("*.vhdl"))
        if path.name != "usb_pie.m.vhdl"
    )
    sources += [
        output / "usb_pie_observed.vhdl",
        args.compound_structure.resolve() if args.compound_structure else
        args.rtl / "STRUCTURE/ip_xxx_3511_hs_mem_compound_structure.a.vhdl",
        output / "usb_startup_tb.vhdl",
    ]
    run([bins["xvhdl"], "--2008", "--work", "work", *map(str, sources)], output)
    run(
        [bins["xelab"], "work.usb_startup_tb", "-debug", "typical", "-s", "usb_startup"],
        output,
    )
    (output / "run.tcl").write_text(
        "log_wave -r /\nrun all\nquit\n"
    )
    run([bins["xsim"], "usb_startup", "-tclbatch", "run.tcl"], output)
    log = (output / "xsim.log").read_text()
    if "USB_STARTUP_ALL_PASS" not in log or "Failure:" in log:
        raise RuntimeError(f"Simulation did not pass; inspect {output / 'xsim.log'}")
    for scenario in range(5):
        if f"SCENARIO {scenario} PASS" not in log:
            raise RuntimeError(f"Scenario {scenario} did not pass")
    if log.count("ID_PASS address=") != 16:
        raise RuntimeError("Expected four checked PHY ID bytes in each normal scenario")
    fault_log = log.split("SCENARIO 4 starting", 1)[1]
    states = re.findall(r"ULPI_STATE (\w+)", fault_log)
    if not states or states[-1] != "ulpi_oper_reset_wf_rxcmd_update":
        raise RuntimeError("Missing RXCMD did not leave the engine in state 0x05")
    print(f"Verified startup scenarios; logs and waveform: {output}")


if __name__ == "__main__":
    main()
