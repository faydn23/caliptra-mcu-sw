#!/usr/bin/env python3
"""Generate the HTG940 SoC-controller MCU/MCI without duplicating USB or Caliptra."""

import argparse
from pathlib import Path
import re


AXI_PORTS = {
    "S_AXI_MCI": "S_AXI_MCI1",
    "S_AXI_MCU_ROM": "S_AXI_MCU1_ROM",
    "M_AXI_MCU_IFU": "M_AXI_MCU1_IFU",
    "M_AXI_MCU_LSU": "M_AXI_MCU1_LSU",
    "M_AXI_MCU_SB": "M_AXI_MCU1_SB",
}
INTERFACES = {
    "cptra_ss_mci_s_axi": "cptra_ss_mci1_s_axi",
    "cptra_ss_mcu_rom_s_axi_if": "cptra_ss_mcu1_rom_s_axi_if",
    "cptra_ss_mcu_lsu_m_axi_if": "cptra_ss_mcu1_lsu_m_axi_if",
    "cptra_ss_mcu_ifu_m_axi_if": "cptra_ss_mcu1_ifu_m_axi_if",
    "cptra_ss_mcu_sb_m_axi_if": "cptra_ss_mcu1_sb_m_axi_if",
}


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one anchor: {old[:100]!r}")
    return text.replace(old, new, 1)


def tokens(text, mapping):
    return re.sub(r"\b[A-Za-z_]\w*\b", lambda m: mapping.get(m[0], m[0]), text)


def instance(text, name):
    match = re.search(rf"\b{re.escape(name)}\s*\(", text)
    if not match:
        raise ValueError(f"Missing instance {name}")
    start = match.end()
    depth = 1
    for end in range(start, len(text)):
        if text[end] == "(":
            depth += 1
        elif text[end] == ")":
            depth -= 1
            if not depth:
                return text[start:end]
    raise ValueError(f"Unterminated instance {name}")


def connections(body):
    body = re.sub(r"//[^\n]*", "", body)
    result = {}
    for item in re.split(r",\s*(?=\.)", body.strip()):
        match = re.fullmatch(r"\.(\w+)(?:\s*\((.*)\))?\s*", item, re.S)
        if not match:
            raise ValueError(f"Unsupported connection: {item}")
        name, expression = match.groups()
        if name in result:
            raise ValueError(f"Duplicate port {name}")
        result[name] = name if expression is None else expression.strip()
    return result


def render_connections(ports):
    return ",\n".join(f"        .{name}({value})" for name, value in ports.items())


def signal_type(source, name):
    match = re.search(
        rf"^\s*(?:(?:input|output)\s+)?"
        rf"((?:logic|wire|soc_ifc_pkg::security_state_t|mci_reg__\w+|"
        rf"lc_ctrl_state_pkg::lc_state_e)\b[^;\n,]*?)\s+{name}\s*[,;]",
        source, re.M,
    )
    if not match:
        raise ValueError(f"Cannot determine signal type for {name}")
    return re.sub(r"^wire\b", "logic", match[1].strip())


def memory(name, interface, words, width, address_width, rom=False):
    return f"""
    xpm_memory_spram #(
        .ADDR_WIDTH_A({address_width}),
        .BYTE_WRITE_WIDTH_A({width}),
        .MEMORY_SIZE({words}*{width}),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .READ_DATA_WIDTH_A({width}),
        .WRITE_DATA_WIDTH_A({width}),
        .READ_LATENCY_A(1),
        .WRITE_MODE_A("no_change"),
        .USE_MEM_INIT(1),
        .USE_MEM_INIT_MMI({int(rom)})
    ) {name} (
        .clka(cptra_ss_clk_i),
        .rsta(!cptra_ss_pwrgood_i),
        .ena({interface}.req.cs),
        .wea({interface}.req.we),
        .addra({interface}.req.addr),
        .dina({interface}.req.wdata),
        .douta({interface}.resp.rdata),
        .regcea(1'b1),
        .sleep(1'b0),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .sbiterra(),
        .dbiterra()
    );
"""


def subsystem(text, mci_source):
    mcu = connections(instance(text, "rvtop_wrapper"))
    mci = connections(instance(text, "mci_top_i"))
    outputs = set(re.findall(
        r"^\s*output\s+(?:[\w:]+\s+)?(?:\[[^\n]*?\]\s*)?(\w+)\s*[,;]",
        mci_source.split("mci_reg__out_t", 1)[0], re.M,
    ))
    # Internal CPU/MCI nets must not feed back into the primary subsystem.
    local_names = set()
    for name in outputs:
        expression = mci[name]
        if re.fullmatch(r"\w+", expression):
            local_names.add(expression)
    for expression in mcu.values():
        if re.fullmatch(r"\w+", expression) and re.search(
            rf"^\s*logic\b[^;\n]*\b{expression}\s*;", text, re.M
        ):
            local_names.add(expression)
    local_names.update({
        "cptra_ss_mcu_halt_ack_o", "cptra_ss_mcu_halt_status_o",
    })
    local_names.discard("usb_dev_irq")
    declarations = "\n".join(
        f"    {signal_type(text, name)} {name};" for name in sorted(local_names)
    )
    interface_ports = []
    pairs = {}
    for old, new in INTERFACES.items():
        for suffix in ("_w_sub", "_r_sub") if "mci_s_axi" in old or "rom_s_axi" in old else ("_w_mgr", "_r_mgr"):
            old_port, new_port = old + suffix, new + suffix
            direction = suffix[1:]
            interface_ports.append(f"    axi_if.{direction} {new_port},")
            pairs[old_port] = new_port
    mcu = {name: tokens(value, pairs) for name, value in mcu.items()}
    mci = {name: tokens(value, pairs) for name, value in mci.items()}
    mcu.update({
        "rst_l": "cptra_ss_mcu_rst_b_o",
        "core_id": "28'd1",
        "jtag_tck": "1'b0",
        "jtag_tms": "1'b1",
        "jtag_tdi": "1'b0",
        "jtag_trst_n": "1'b0",
        "jtag_tdo": "",
        "jtag_tdoEn": "",
    })
    mci.update({
        "mcu_cpu_halt_ack_i": "cptra_ss_mcu_halt_ack_o",
        "mcu_cpu_halt_status_i": "cptra_ss_mcu_halt_status_o",
        "cptra_core_rst_b_i": "cptra_ss_mci_cptra_rst_b_o",
        "strap_mcu_reset_vector": "32'hB006_0000",
        "strap_mcu_lsu_axi_user": "32'h0000_0002",
        "strap_mcu_ifu_axi_user": "32'h0000_0002",
        "strap_mcu_sram_config_axi_user": "32'h0000_0002",
        "strap_mci_soc_config_axi_user": "32'h0000_0001",
        "mcu_sram_fw_exec_region_lock": "1'b0",
        "cptra_mbox_data_avail": "1'b0",
        "mcu_no_rom_config": "1'b0",
        "mci_boot_seq_brkpoint": "1'b0",
        "mci_generic_input_wires": "64'b0",
        "agg_error_fatal": "{31'b0, mcu_dccm_ecc_double_error}",
        "agg_error_non_fatal": "{31'b0, mcu_dccm_ecc_single_error}",
    })
    for name in mci:
        if name.startswith("cptra_trace_"):
            mci[name] = "'0"
    memory_specs = [
        ("mcu_sram", "cptra_ss_mci_mcu_sram_req_if", 131072, 39, 17),
        ("mcu_rom_patch_sram", "cptra_ss_mcu_rom_patch_sram_req_if", 1024, 39, 10),
        ("mbox0", "cptra_ss_mcu_mbox0_sram_req_if", 4096, 39, 12),
        ("mbox1", "cptra_ss_mcu_mbox1_sram_req_if", 4096, 39, 12),
    ]
    memories = ""
    for name, interface, words, width, address_width in memory_specs:
        memories += f"""
    mci_mcu_sram_if #(.ADDR_WIDTH({address_width})) {interface} (
        .clk(cptra_ss_clk_i), .rst_b(cptra_ss_pwrgood_i)
    );
"""
        memories += memory(name, interface, words, width, address_width)
    memories += """
    axi_mem_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64)) mcu_rom_mem_export_if (
        .clk(cptra_ss_clk_i), .rst_b(cptra_ss_pwrgood_i)
    );
    axi_mem #(.AW(17), .DW(64), .IW(`CALIPTRA_AXI_ID_WIDTH)) mcu1_rom_axi (
        .clk(cptra_ss_clk_i), .rst_n(cptra_ss_rst_b_o),
        .s_axi_w_if(cptra_ss_mcu1_rom_s_axi_if_w_sub),
        .s_axi_r_if(cptra_ss_mcu1_rom_s_axi_if_r_sub),
        .s_mem_req_if(mcu_rom_mem_export_if)
    );
"""
    memories += memory("mcu1_rom", "mcu_rom_mem_export_if", 16384, 64, 17, rom=True)
    user_assignments = text[text.index("    // ARUSER"):text.index("    // Fuse controller output")]
    user_assignments = tokens(user_assignments, pairs)
    user_assignments = re.sub(r"^\s*(?:generate|endgenerate)\s*$", "", user_assignments, flags=re.M)
    user_assignments = user_assignments.replace(
        "cptra_ss_strap_mcu_lsu_axi_user_i", "32'h0000_0002"
    ).replace("cptra_ss_strap_mcu_ifu_axi_user_i", "32'h0000_0002")
    params = text[text.index("    mci_top #("):text.index(") mci_top_i (")]
    params = tokens(params, pairs)
    params = params.replace(".MCU_MBOX0_SIZE_KB(MCU_MBOX0_SIZE_KB)", ".MCU_MBOX0_SIZE_KB(16)")
    params = params.replace(".MCU_MBOX1_SIZE_KB(MCU_MBOX1_SIZE_KB)", ".MCU_MBOX1_SIZE_KB(16)")
    irq = """
    always_comb begin
        ext_int = '0;
        ext_int[`VEER_INTR_VEC_MCI] = mci_intr;
        ext_int[`VEER_INTR_VEC_USB] = cptra_ss_usb_dev1_irq_o;
    end
"""
    block = f"""
// MCU1 is the SoC controller; shared lifecycle inputs are read-only here.
if (1) begin : soc_controller
{declarations}
    css_mcu0_el2_mem_if cptra_ss_mcu0_el2_mem_export();
    caliptra_ss_veer_sram_export mcu1_memories (
        .cptra_ss_mcu0_el2_mem_export(cptra_ss_mcu0_el2_mem_export)
    );
{irq}
{user_assignments}
    mcu_top mcu1 (
{render_connections(mcu)}
    );
{params}) mci1 (
{render_connections(mci)}
    );
{memories}
end
"""
    text = replace_once(text, "    input logic cptra_ss_clk_i,", "\n".join(interface_ports) + "\n    input logic cptra_ss_clk_i,")
    text = replace_once(text, "mcu_top rvtop_wrapper (", "mcu_top mcu0 (")
    text = replace_once(text, ") mci_top_i (", ") mci0 (")
    return replace_once(text, "endmodule", block + "\nendmodule")


def add_axi_ports(text):
    end = re.search(r"^\s*\);", text, re.M)
    if not end:
        raise ValueError("Missing module header terminator")
    header = text[:end.start()]
    mapping = {}
    for old, new in AXI_PORTS.items():
        for name in re.findall(r"\b" + old + r"_\w+\b", header):
            mapping[name] = name.replace(old, new, 1)
    ports = []
    for line in header.splitlines():
        if re.match(r"\s*(?:input|output)\b", line) and any(
            re.search(rf"\b{name}\b", line) for name in mapping
        ):
            ports.append(tokens(line, mapping))
    if not ports:
        raise ValueError("No AXI declarations found")
    anchor = re.search(r"^\s*input\s+(?:wire|logic|bit)\s+core_clk\s*,", header, re.M)
    if not anchor:
        raise ValueError("Missing core_clk port declaration")
    return text[:anchor.start()] + "\n" + "\n".join(ports) + "\n" + text[anchor.start():], mapping


def wrapper(text):
    text = text.replace("caliptra_ss_top_0.rvtop_wrapper.", "caliptra_ss_top_0.mcu0.")
    text = text.replace("caliptra_ss_top_0.mci_top_i.", "caliptra_ss_top_0.mci0.")
    extra = ""
    for interface in INTERFACES:
        match = re.search(rf"\b{interface}\s*\(", text)
        if not match:
            raise ValueError(f"Missing AXI interface {interface}")
        begin = text.rfind("axi_if #(", 0, match.start())
        end = text.index(";", match.end()) + 1
        if begin < 0:
            raise ValueError(f"Missing AXI declaration for {interface}")
        extra += text[begin:end] + "\n"
    # Sideband tieoffs are separate from the channel adapters in the wrapper.
    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    for assignment in re.findall(r"\bassign\s+[^;]+;", code):
        names = set(re.findall(r"\b\w+\b", assignment))
        if names.intersection(INTERFACES) or any(
            name.startswith(prefix + "_") for name in names for prefix in AXI_PORTS
        ):
            extra += assignment + "\n"
    all_names = set(re.findall(r"\b\w+\b", extra))
    mapping = dict(INTERFACES)
    for name in all_names:
        for old, new in AXI_PORTS.items():
            if name.startswith(old + "_"):
                mapping[name] = name.replace(old, new, 1)
    extra = tokens(extra, mapping)
    text, _ = add_axi_ports(text)
    text = replace_once(text, "// MCU ROM\n", extra + "\n// MCU ROM\n")
    port_connections = []
    for old, new in INTERFACES.items():
        for suffix, modport in (("_w_sub", "w_sub"), ("_r_sub", "r_sub")) if "mci_s_axi" in old or "rom_s_axi" in old else (("_w_mgr", "w_mgr"), ("_r_mgr", "r_mgr")):
            port_connections.append(f"    .{new + suffix}({new}.{modport}),")
    return replace_once(text, ") caliptra_ss_top_0 (", ") caliptra_ss_top_0 (\n" + "\n".join(port_connections))


def package(text):
    text, mapping = add_axi_ports(text)
    body = instance(text, "cptra_wrapper")
    added = {}
    for name, new in mapping.items():
        matches = re.findall(rf"\.{name}\s*\(([^()]*)\)", body)
        if len(matches) != 1:
            raise ValueError(f"Expected one package connection for {name}")
        added[new] = tokens(matches[0], mapping)
    match = re.search(r"\bcptra_wrapper\s*\(", text)
    if not match:
        raise ValueError("Missing package wrapper instance")
    return text[:match.end()] + "\n" + render_connections(added) + ",\n" + text[match.end():]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subsystem", type=Path, required=True)
    parser.add_argument("--mci-source", type=Path, required=True)
    parser.add_argument("--wrapper", type=Path, required=True)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--package-out", type=Path, required=True)
    args = parser.parse_args()
    outputs = {
        args.subsystem: subsystem(args.subsystem.read_text(), args.mci_source.read_text()),
        args.wrapper: wrapper(args.wrapper.read_text()),
        args.package_out: package(args.package.read_text()),
    }
    for path, text in outputs.items():
        path.write_text(text)
    print("HTG_DUAL_MCU_SOURCES_GENERATED: MCU0/MCI0 and MCU1/MCI1; USB unchanged")


if __name__ == "__main__":
    main()
