#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Keep VHDL assertions active only after reset becomes known and released."""

import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    text = args.source.read_text()
    start = text.index("assertions_proc : process (hclk, hresetn)")
    end = text.index("end process assertions_proc;", start)
    block = text[start:end]
    anchor = "elsif rising_edge(hclk) then"
    if block.count(anchor) != 1:
        raise ValueError("Ambiguous VHDL assertion clock guard")
    block = block.replace(anchor, "elsif rising_edge(hclk) and hresetn = '1' then")
    args.output.write_text(text[:start] + block + text[end:])


if __name__ == "__main__":
    main()
