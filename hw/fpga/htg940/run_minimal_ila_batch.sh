#!/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$script_dir/../../.." && pwd)
if [ "$#" -ne 1 ]; then
    echo "Usage: bash $0 SHARED_FIRMWARE_DIRECTORY" >&2
    exit 1
fi
firmware=$(cd -- "$1" && pwd)
work="$repo/hw/fpga/htg940_usb_min_ila/build_logs_minimal_ila_20261025"
build="$repo/hw/fpga/htg940_usb_min_ila/build_full_minimal_ila_20261025"
vivado=/home/cad/tools/synopsys/xilinx_vivado/2025.1_rel2/Vivado/bin/vivado
if [ -e "$build" ]; then
    echo "Refusing to overwrite existing build: $build" >&2
    exit 1
fi
for name in mcu_rom.bin caliptra_rom.bin flash_image.bin; do
    test -s "$firmware/$name"
done
mkdir -p "$work"
cd "$work"
echo "START $(date -Iseconds) host=$(hostname) job=${LSB_JOBID:-unknown}"
trap 'status=$?; echo "END $(date -Iseconds) exit=$status"' EXIT
sha256sum "$firmware/mcu_rom.bin" "$firmware/caliptra_rom.bin" \
    "$firmware/flash_image.bin" > firmware.sha256
python3 -m unittest discover -s "$repo/hw/fpga/htg940_usb_min_ila" \
    -p 'test_*.py' > tests.log 2>&1
python3 "$script_dir/prepare_sources.py" --check > sources.log 2>&1
"$vivado" -mode batch -log "$work/vivado.log" -journal "$work/vivado.jou" \
    -source "$script_dir/run_full.tcl" \
    -tclargs BUILD_NAME=build_full_minimal_ila_20261025 \
    "FW_IMAGE_DIR=$firmware" IMPLEMENT > console.log 2>&1
impl="$build/caliptra_htg940_project.runs/impl_1"
for name in htg940_board_top.bit htg940_board_top.mmi htg940_usb_dual_ila.ltx; do
    test -s "$impl/$name"
done
sha256sum "$impl/htg940_board_top.bit" "$impl/htg940_board_top.mmi" \
    "$impl/htg940_usb_dual_ila.ltx" > deliverables.sha256
sha256sum --check firmware.sha256
printf '%s\n' \
    'BIT_GENERATED: reduced PHY-startup ILAs.' \
    'DEBUG ONLY: inspect timing/CDC/DRC before hardware qualification.' \
    'No board programming performed.' > result.txt
cat result.txt
