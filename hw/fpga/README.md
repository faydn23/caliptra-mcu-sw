_*SPDX-License-Identifier: Apache-2.0<BR>
<BR>
<BR>
Licensed under the Apache License, Version 2.0 (the "License");<BR>
you may not use this file except in compliance with the License.<BR>
You may obtain a copy of the License at<BR>
<BR>
http://www.apache.org/licenses/LICENSE-2.0 <BR>
<BR>
Unless required by applicable law or agreed to in writing, software<BR>
distributed under the License is distributed on an "AS IS" BASIS,<BR>
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.<BR>
See the License for the specific language governing permissions and<BR>
limitations under the License.*_<BR>

# **Caliptra FPGA Guide** #
FPGA provides a fast environment for software development and testing that is built on Caliptra Core and Subsystem RTL.
The ARM CPU takes the place of an SOC manager and can drive stimulus to Caliptra SS over an AXI bus. In addition the Caliptra Core, MCU, and LCC JTAGs are connected to GPIO pins for debug and testing from the ARM CPU.

### USB RTL integration for the Versal handoff

This integration keeps the existing ARM reset controls, ROM-loading backdoors,
core/MCU/OTP memories, staging SRAM, CIPS, DDR/NoC and PetaLinux packaging flow.
It does not include HTG940 flash memories, entropy UART logic or HTG940 pin mappings.
The only added memories are the USB IP's two required 64 KiB packet SRAMs
(8192 x 64 bits per device), implemented in
[usb_packet_sram.sv](./src/usb_packet_sram.sv).

#### Source versions and reproducibility

The starting software repository commit is
`20f7fcff1b51d69b03d0b352685fc7360536ad9a`.
The required RTL commits are:

| Submodule | Commit |
|---|---|
| caliptra-ss | `4fb99b4dadc235e5989fa594dcd38894851676a1` |
| caliptra-rtl | `c46bf7ca8e0b6dd1c82aa812073c02d6cd8c4fbd` |
| i3c-core | `067bfe14ea8bb54470b6af9af154bee5cda6ded7` |
| usb2 | `87a1a3789604dd5a611693a6ba97fff871498593` |

For a fresh checkout, initialize and select the versions below. Fetch a listed
commit from its submodule's origin first if it is not already available.
Do not run submodule checkout/update commands over unsaved local patches.

```sh
git submodule update --init hw/caliptra-ss
git -C hw/caliptra-ss checkout 4fb99b4dadc235e5989fa594dcd38894851676a1
git -C hw/caliptra-ss submodule update --init --recursive
git -C hw/caliptra-ss/third_party/caliptra-rtl checkout c46bf7ca8e0b6dd1c82aa812073c02d6cd8c4fbd
git -C hw/caliptra-ss/third_party/caliptra-rtl submodule update --init --recursive
git -C hw/caliptra-ss/third_party/i3c-core checkout 067bfe14ea8bb54470b6af9af154bee5cda6ded7
git -C hw/caliptra-ss/third_party/i3c-core submodule update --init --recursive
git -C hw/caliptra-ss/third_party/usb2 checkout 87a1a3789604dd5a611693a6ba97fff871498593
git -C hw/caliptra-ss/third_party/usb2 submodule update --init --recursive
```

Then prepare the local patches:

```sh
python3 hw/fpga/prepare_usb_sources.py
python3 hw/fpga/prepare_usb_sources.py --check
```

The helper verifies pins and applies only
[caliptra-ss.patch](./usb_patches/caliptra-ss.patch) (explicitly disabled USB AXI
USER filtering, a package-qualified MuBi helper for independent compilation,
and a selectable MCI streaming-transport reset value)
and [usb2.patch](./usb_patches/usb2.patch) (ULPI-only
`C_UTMI_SUPPORT=0`). It does not fetch, change commits, discard local changes,
or commit anything. The existing packaging flow checks this preparation and
applies [caliptra_ss_top.patch](./src/caliptra_ss_top.patch) to a build-local copy
for the separate I3C clock/CDC. USB VHDL comment-directive adjustments also affect
generated copies only. Preserve the patches in the parent repository: gitlinks
alone do not contain uncommitted submodule edits.

#### Added and updated file guide

All USB handoff documentation, helper messages and comments are in English.
The original Versal build entry points remain in use; there is no new
top-level build runner and no requirement to generate an FPGA image for the
RTL-only handoff.

| File | Change | Purpose / use |
|---|---|---|
| [prepare_usb_sources.py](./prepare_usb_sources.py) | New Python helper | Verifies the four RTL pins and idempotently applies the two persisted submodule patches. `--check` is read-only. Run before packaging. |
| [usb_compound_sources.tcl](./usb_compound_sources.tcl) | New Tcl helper | Selects the pinned compound USB SV/VHDL sources and generated register header. Sourced by the packaging script, not run independently. Legacy VHDL comment-directive changes affect generated copies only. |
| [create_caliptra_package.tcl](./create_caliptra_package.tcl) | Updated existing Tcl | Checks source preparation, includes the USB source helper, applies the build-local SS clock/CDC patch, and packages USB interfaces/parameters. |
| [fpga_configuration.tcl](./fpga_configuration.tcl) | Updated existing Tcl | Adds the four USB AXI windows, fabric clock/reset wiring and USB enable/export profiles while retaining the existing Versal flow. |
| [caliptra_package_top.v](./src/caliptra_package_top.v) | Updated RTL | Exposes the USB AXI/physical ports and forwards USB_ENABLE. |
| [caliptra_wrapper_top.sv](./src/caliptra_wrapper_top.sv) | Updated RTL | Connects USB AXI, ULPI IOBUFs, packet SRAMs and recovery signals; selects the profile-dependent recovery reset. |
| [backdoor_otp.sv](./src/backdoor_otp.sv) | Updated RTL | Renames the OTP package import for compatibility with the pinned RTL; memory behavior is unchanged. |
| [usb_packet_sram.sv](./src/usb_packet_sram.sv) | New RTL | Implements each USB device's required 64 KiB packet SRAM. |
| [caliptra_ss_top.patch](./src/caliptra_ss_top.patch) | Updated patch | Adapts the pinned SS top for the existing FPGA I3C clock/CDC integration in a build-local copy. |
| [caliptra-ss.patch](./usb_patches/caliptra-ss.patch), [usb2.patch](./usb_patches/usb2.patch) | New persisted patches | Reproduce local nested RTL edits that are not captured by submodule pointers alone. Applied by the preparation helper. |
| [vck190_usb_fmc.xdc](./constraints/vck190_usb_fmc.xdc) | New constraints | Reserves VCK190 FMC pins when physical USB ports are exported. Existing XDC files are unchanged; voltage and compatibility limits are described below. |
| [test_usb_tcl.py](./tests/test_usb_tcl.py) | New Python tests | Checks actual Tcl source selection, six-manager addressing, clock/reset connections and enable/export profiles using mocks. |
| [run_usb_unit_tests.py](./tests/run_usb_unit_tests.py) | New Python runner | Runs focused XSim SRAM, ULPI-pad and recovery-selector reset tests. Requires Vivado tools; accepts `--vivado-bin`. |
| [tb_usb_packet_sram.sv](./tests/tb_usb_packet_sram.sv), [tb_usb_ulpi_pads.sv](./tests/tb_usb_ulpi_pads.sv), [tb_usb_transport_reset.sv](./tests/tb_usb_transport_reset.sv) | New SV tests | Check memory behavior, actual wrapper pad logic and actual generated MCI register behavior. Used by the unit runner. |
| [run_usb_e2e.py](./tests/run_usb_e2e.py) | New Python runner | Runs the MCU single-PHY-read test, or the bounded final-ROM initialization profile with `--core-rom`. Requires an isolated precompiled Versal cache and external ROM/OTP/PHY-model inputs. |
| [prepare_usb_e2e_bindings.py](./tests/prepare_usb_e2e_bindings.py) | New Python helper | Generates flat-port bindings from the actual wrapper for the behavioral test fabric. Called by the E2E runner. |
| [prepare_usb_e2e_assertions.py](./tests/prepare_usb_e2e_assertions.py) | New Python helper | Guards the VHDL assertion process against unknown startup reset in a generated simulation copy. Does not remove assertions or modify production RTL. |
| [test_usb_e2e_preparation.py](./tests/test_usb_e2e_preparation.py) | New Python tests | Checks wrapper bindings and verifies that assertion preparation changes only the intended guard. |
| [tb_versal_usb_single_read.sv](./tests/tb_versal_usb_single_read.sv) | New SV test | Instantiates the actual Versal wrapper, performs backdoor loading/readback and PS-style configuration writes, and checks firmware/AXI/PHY evidence. Its fabric is behavioral, not CIPS/SmartConnect. |
| [README.md](./README.md) | Updated documentation | Records pins, reproduction steps, profiles, register maps, tests, results and remaining validation limits. |

The added Python files are preparation/testing tools, not ARM runtime software
or replacements for the firmware team's USB recovery application. The supplied
HTG940 recovery GUI, ROM/runtime/manifest binaries, simulator caches and build
outputs are not included by these changes. E2E external inputs and cache
requirements are detailed in the validation section; a fresh clone alone does
not provide a complete standalone E2E simulation environment.

#### Normal hardware mode and simulation mode

`USB_ENABLE=FALSE` is the normal Tcl default; the RTL package/wrapper parameter
also defaults to zero. In this mode:

- USB DATA is high impedance; STP and exported DEV1 interrupts are low.
- Floating FMC inputs and a missing ULPI clock cannot enter the USB PHY logic.
- MCI HW_CAPABILITIES.STREAMING_BOOT_SELECT resets to I3C (`1`), so the core
  uses the existing I3C recovery base and payload/activation indications.
  USB-enabled simulation resets the selector to USB (`0`). Firmware can still
  configure the selector before the core latches its recovery base.
- USB PHY accesses are not supported. Firmware must not issue a PHY request
  and wait for completion with USB disabled.

For USB simulation, instantiate `caliptra_package_axi_top` with
`.USB_ENABLE(1)` (or the wrapper with the same parameter), supply the 60 MHz
ULPI clock and a PHY model, and drive VBUS/DIR/NXT/DATA appropriately.
DATA ownership uses eight explicit IOBUFs controlled by the IP's TXENABLE:
FPGA drives only when TXENABLE is asserted; otherwise DATA is released.
`DEV_EN=0` remains valid for pre-enumeration PHY register accesses.

The selectable reset is a local RTL patch carried through SS/MCI down to the
generated register block; generic SS/MCI defaults remain USB. If regenerating
MCI registers, preserve the reset parameter from the supplied patch. The
register layout and software-write behavior are unchanged.

The Tcl option `USB_ENABLE=TRUE` enables the physical USB integration, but this
is **not** a qualified hardware USB profile. With USB enabled, firmware must
select I3C or USB through MCI HW_CAPABILITIES before the core latches its recovery
base during initialization. The upstream software and pinned newer RTL are
not yet verified as a complete boot-compatible firmware/RTL pair.

#### AXI and recovery register map

All six existing AXI managers retain their original windows and receive these
four additional 1 MiB windows through a downstream four-output SmartConnect:

| Interface | Global base | Purpose |
|---|---|---|
| S_AXI_USB_COMBO | `0xA4200000` | DEV0 CSR, recovery and hub |
| S_AXI_USB_DEV0_MEM | `0xA4300000` | DEV0 packet memory access |
| S_AXI_USB_DEV1_CSR | `0xA4400000` | DEV1 CSR |
| S_AXI_USB_DEV1_MEM | `0xA4500000` | DEV1 packet memory access |

The wrapper passes each window's low 20 address bits to the USB IP.
The combo recovery block starts at `0xA4200800`; the I3C recovery base remains
`0xA4030100`. Do not reuse the I3C register layout with a changed base alone:
USB DEVICE_STATUS0 is recovery `+0x28`, DEVICE_RESET `+0x68`, RECOVERY_CTRL
`+0x6c`, FIFO_CTRL0 `+0x184`, FIFO_STATUS0 `+0x18c`, and FIFO_DATA `+0x1a0`.
The I3C FIFO_DATA offset is `+0x68`, not `+0x1a0`.

USB AXI USER filtering is explicitly disabled for debug compatibility; this
is not production access-control qualification. DEV1 IRQ/FIQ are exported,
not connected to PS interrupts. OCP_LOCK and key-release support remain disabled
at the old wrapper feature level. The pinned MCU reserves interrupts 3-5 for
its integrated SPI/UARTs; spare I3C and the existing primary/secondary flash
interrupt inputs therefore occupy external interrupt indices 6, 7 and 8.

#### VCK190 FMC constraints and no-card operation

Existing XDC files are unchanged. A separate
[vck190_usb_fmc.xdc](./constraints/vck190_usb_fmc.xdc) reserves FMCP1 pins for
the USB ports, with a clock-capable `BD23` ULPI clock input. It uses LVCMOS15
and **requires the FMC bank's VADJ supply to be configured and powered at 1.5 V**.
No connected card is required, but an unpowered FMC I/O bank is not a verified
operating configuration. Do not assume the system controller enables VADJ
automatically when no card is present.

These are reserved board pins, **not a USB3320 daughter-card pinout**.
Connecting a future card requires checking its connector wiring, voltage levels,
reset, VBUS detection, and input/output timing; direct 1.8 V ULPI compatibility
has not been established.

`USB_EXPORT_PORTS` defaults to true for VCK190 and false for VMK180.
Setting `USB_EXPORT_PORTS=FALSE` omits the physical USB ports and the added XDC;
USB_ENABLE must then remain false. Original memory and processor connections
remain in place in either profile. No FPGA image was generated or programmed
as part of the RTL handoff; existing binaries are unchanged.

#### Focused validation

The MCU single-register fixture is
[tb_versal_usb_single_read.sv](./tests/tb_versal_usb_single_read.sv).
It instantiates the actual USB-enabled Versal wrapper, loads and reads back all
128 KiB of the diagnostic ROM through the existing backdoor, loads a simulation
OTP fixture, and releases power/reset through the wrapper's AXI-Lite registers.
It requires exactly one firmware PHY request, a physical-model vendor read of
`0x24`, an AXI-visible cleared PHY_ACCESS, firmware PASS and the final halt
message. It rejects DEV_EN writes, retries, AXI errors and unsupported accesses.

[run_usb_e2e.py](./tests/run_usb_e2e.py) requires an isolated writable cache
containing the **current Versal SV sources** and existing USB/vendor simulation
libraries, plus explicit ROM, OTP and USB3320-model paths:

```sh
python3 hw/fpga/tests/test_usb_e2e_preparation.py -v
python3 hw/fpga/tests/run_usb_e2e.py \
  --cache /path/to/precompiled-versal-simulation-cache \
  --vivado-bin /path/to/Vivado/bin \
  --mcu-rom /path/to/simulation_short_delays.mem \
  --otp-image /path/to/otp-img.2048.vmem \
  --phy-model /path/to/usb3320_register_model.sv
```

This is not a fresh standalone compilation flow. The cache must not be shared
with a running elaboration or another simulation preparation. The runner does
not rebuild production RTL, fetch dependencies, or generate an FPGA image.
It checks failure messages and an anchored functional PASS marker because XSim
can exit zero after a VHDL assertion stops simulation.

The fixture uses a serial behavioral AXI routing/width-conversion harness,
not the generated Versal SmartConnect or CIPS/ARM software. Thus it checks MCU
execution, wrapper endpoints, USB RTL and pads, but not SmartConnect arbitration,
the complete ARM boot procedure, or physical FPGA timing. The prior short-delay
diagnostic ROM retains the one-read/no-retry/DEV_EN=0 behavior but uses 2000-cycle
startup/settle waits; it is not the hardware-delay ROM. The runner rejects
images without both simulation-only markers and requires the firmware logs to
confirm both 2000-cycle waits. In the retained HTG940 simulation artifacts,
`simulation_short_delays.mem` is the simulation image; `diagnostic_mcu_rom.mem`
is the hardware-delay image and must not be used for this bounded test.

The bounded MCU/PHY test passed with the retained short-delay image
(readmemh-file SHA256
`31547444a59d8bdd9490adea921de11cdb969ad9e123679a02789b8f2e280e9e`).
Both startup and settle waits were confirmed as 2000 cycles by firmware.
ROM backdoor readback and native OTP/MCI boot completed without forced reset
or completion signals. The observed transaction was:

```text
VERSAL_USB_WRITE: addr=a420003c data=82000000
PHY_READ: address=00 data=24 extended=1
VERSAL_USB_COMPLETION: ULPIDEBUG=80240000
MCU_LOG [usb-single] END ULPIDEBUG=0x80240000 elapsed_cycles=51
MCU_LOG [usb-single] PASS: register 00 returned 0x24
VERSAL_USB_E2E_PASS: real MCU ROM, DEV_EN=0, one read, PHY=24, access cleared
```

This establishes the single PHY-register transaction for the fixture and
profiles described above, not enumeration, recovery transfers, normal firmware
boot, the generated SmartConnect, or hardware operation.

For a bounded initialization check with full recovery ROMs, also supply
`--core-rom /path/to/core_rom.mem` to the same runner. This selects a separate
`final_rom_init` snapshot and result log, accepts the full MCU ROM rather than
requiring simulation-delay markers, and loads/readback-checks both the 96 KiB
core and 128 KiB MCU ROM through their existing backdoors. Firmware binaries
must first be converted to 64-bit little-endian readmemh words without patching
their instructions. The runner reports hashes of the reconstructed binaries.

This profile releases the core boot breakpoint and permits normal firmware USB
initialization (including DEV_EN and multiple PHY accesses). It stops only on
the firmware log checkpoint `[usb] Waiting for USB bus reset` or
`[mcu-rom] Waiting for MCU firmware to be ready`, after verified ROM loading,
native MCU reset release and an observed PHY software reset. The exact reached
checkpoint is reported; the first does not imply the second. A 20 ms simulated
watchdog bounds this smoke test, so an unchanged hardware-delay firmware may
need a longer separately justified run. A watchdog failure is not evidence of
a USB RTL defect by itself.

It models PS-style loading/configuration transactions, not an ARM processor,
generated CIPS/SmartConnect, the production OTP contents, or the complete ARM
host software. It uses the existing simulation OTP fixture. No USB host packets
are supplied, and the three recovery payloads are not loaded: enumeration,
image authentication/activation and final runtime execution remain unverified.

The supplied HTG940 final ROMs (core binary SHA256
`6ebd36fc24bbf8f24d098ab6d60dc493dd00bb95dce9a4a6c781e1786628a9ad`,
MCU binary SHA256
`0e392c4b2a1e86fc6d7a3021f5f2345ac69af0da35e1ad3eb446eb76410e7419`)
were loaded and fully read back, and the MCU started with its native reset flow.
The MCU log reached `Disabled retained MCU watchdog`, then executed its
5,000,000-cycle startup wait (125 ms at 40 MHz). The run was stopped in favor of
the small diagnostic tests; neither initialization checkpoint was reached.
This is not a final-ROM PASS or a PHY-access failure. The final ROMs were not
patched to shorten their waits.

At the first core clock edge, synchronous wrapper reset registers are still
unknown and an upstream VHDL numeric assertion otherwise fires before USB has
seen reset. Preparation changes only the assertion-process clock guard in a
**generated copy** to require known released HRESETn. All assertions in that
process remain present and run after reset; functional RTL and submodule files
are unchanged. Other pre-existing structural-check assertion workarounds
described below still apply. Elaboration alone is not a functional PASS.

From the repository root:

```sh
python3 hw/fpga/tests/test_usb_tcl.py -v
python3 hw/fpga/tests/run_usb_unit_tests.py --vivado-bin /path/to/Vivado/bin
```

The Tcl tests execute the actual source-selection and address/clock/reset
sections with mocks, including all six managers and physical-port export on/off.
The XSim tests exercise all 8192 SRAM addresses, byte masks, synchronous
read-first behavior, chip select, and the actual wrapper pad generate block
in enabled/disabled modes. The generated MCI register test verifies USB/I3C
reset values, software selection and reset restoration.

Full-wrapper structural elaboration was also checked using current SV sources
and existing simulator/VHDL/IP libraries with Vivado 2025.1 Rel2. Older tool
versions listed later in this guide were not revalidated with the new RTL pins.
XSim does not support some upstream
`$past`/`$stable` assertions: the structural check used SYNTHESIS plus an
assertion-only generated USB recovery copy; repository assertions were not
removed. This is not a fresh standalone simulator build, an end-to-end ROM boot
or USB transaction regression, timing closure, or BOOT.BIN qualification.

### FPGA Block Diagram Components ###
- Wrapper Registers
  - Controls resets, straps, and FPGA wrapper utilities such as the log and debug FIFOs.
- AXI Interconnect
  - SS requires the integrator to connect the various SS AXI busses to an interconnect to allow MMIO access both from the SOC manager and SS components with an AXI manager interface.
- Backdoor memory interfaces
  - The Caliptra Core, MCU, and OTP ROMs are implemented as dual port SRAM's to allow them to be reconfigured without rebuilding. These SRAMs are mapped into the ARM CPU to allow them to be written by the hw-model before taking SS out of reset.
- Xilinx I3C
  - The FPGA instantiates an I3C host controller to communicate with the SS I3C. In order for the I3C controllers to reach I3C bus speeds a higher clock is needed. The FPGA modifies caliptra_ss_top to insert CDC logic and run the SS I3C at the same clock.

![](./images/caliptra_ss_fpga_block_diagram.svg)

### Requirements: ###
 - Vivado
   - Version v2022.2 or 2024.2
 - PetaLinux Tools
   - Version must match Vivado
 - FPGA
   - [VCK190](https://www.xilinx.com/products/boards-and-kits/vck190.html)

### Versal ###
#### Processing system one time setup: ####
1. Download VCK-190 image
   - **Recommended**: A development image is built each week and uploaded by [this](https://github.com/chipsalliance/caliptra-sw/actions/workflows/fpga-image.yml) GitHub Action Job. You will want the image with the `-dev` postfix. This image is an almost exact replica of the image used for the Caliptra CI.
     - This is a debian based image and should make a similar user experience to the AMD image.
   - Ubuntu VCK190 SD card image and install to a microSD card. The Versal is packaged with a blank microSD card in the box that can be used for the OS.
1. Insert the OS SD card into the slot on top of the board.
  - The slot below the board is for the System Controller and the card there should be left inserted.
  - https://ubuntu.com/download/amd-xilinx
1. Configure SW1 to boot from SD1: [Image](./images/versal_boot_switch.jpg)
   - Mode SW1[4:1]: OFF, OFF, OFF, ON
1. Boot from the SD card.
   - Initial boot requires connecting over serial. The first serial port is for the PS. See below for settings.
   - Initial credentials (when using Ubuntu image)
     - User: ubuntu Pass: ubuntu
   - Update the date to avoid apt/git failures
     ```
     sudo dpkg-reconfigure tzdata
     sudo date -s 'yyyy-mm-dd hh:mm'
     ```
   - Install software dependencies - *Do not update the system*
     ```shell
     sudo apt update
     sudo apt install make gcc
     ```
   - Install rustup using Unix directions: https://rustup.rs/#
     ```
     curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
     ```
   - [Optional] Assign a hostname for SSH access.
   - [Optional] Save uboot environment variables to avoid the MAC being randomized each boot.
     - When connected to the serial port interrupt uboot at the message "Hit any key to stop autoboot:  0"
     - Issue ```saveenv``` command to uboot, which creates an env file in the boot partition for use in subsequent boots.

#### Serial port configuration: ####
The USB Type-C connecter J207 on the VCK190 provides UART and JTAG access to the board using an FTDI USB to quad UART/Serial converter.
1. VCK190 JTAG chain for waveform capture and management.
2. PS UART (First COM port) is a serial port used to access the operating system running on the ARM core.
3. PL UART (Currently unused)
4. System Controller UART (Third COM port)

Serial port settings for the PS UART:
 - Speed: 115200
 - Data bits: 8
 - Stop bits: 1
 - Parity: None
 - Flow control: None

### FPGA build steps: ###
The FPGA build process uses Vivado's batch mode to procedurally create the Vivado project using fpga_configuration.tcl and optionally create the caliptra_build/caliptra_fpga.xsa needed for the next step.
This script provides a number of configuration options for features that can be enabled using "-tclargs OPTION=VALUE OPTION=VALUE"

`vivado -nolog -nojournal -mode batch -source fpga_configuration.tcl -tclargs BUILD=TRUE`

| Option      | Purpose
| ------      | -------
| BUILD=TRUE  | Automatically start building the FPGA.
| GUI=TRUE    | Open the Vivado GUI.

### Build boot.bin: ###

Note: If using the Calptra CI Image (or PetaLinux image), you can skip this step. Instead use a segmented bitstream and load the PDI file directly.

Here is a link with more information about segmented bitstreams: https://github.com/Xilinx/Vivado-Design-Tutorials/tree/2024.2/Versal/Boot_and_Config/Segmented_Configuration

 - Source PetaLinux tools from the PetaLinux installation directory. *PetaLinux Tools must match Vivado version*
   - `source settings.sh`
 - Execute [create_boot_bin.sh](create_boot_bin.sh) to create a BOOT.BIN
   - `./create_boot_bin.sh caliptra_build/caliptra_fpga.xsa`
 - (Optional) After the BOOT.BIN is created once, update_boot_bin.sh can be used to incorporate a new xsa.
   - `./update_boot_bin.sh caliptra_build/caliptra_fpga.xsa`
 - Copy petalinux_project/images/linux/BOOT.BIN to the boot partition as boot1900.bin
   - If the Ubuntu image is booted, it will mount the boot partition at /boot/firmware/
   - If boot1900.bin fails to boot the system will fallback to the default boot1901.bin
   - [!WARNING]
     ```reboot``` seems to skip the image selector and will load from the same filename as the previous boot. If the fallback image is the last one booted then the proper procedure is ```shutdown``` and to toggle the power switch. In the serial boot log the fallback image uses PLM from 2022 while for any valid Caliptra FPGA image the PLM will be 2024.
   ```shell
   sudo su
   cp BOOT.BIN /boot/firmware/boot1900.bin
   reboot
   # OR
   shutdown
   # Toggle power switch
   ```

- Verify the correct image is loaded by checking FPGA wrapper registers.
   - fpga_magic (0xA4010000) contains 0x52545043.
   - fpga_version (0xA4010004) contains the hash of the git HEAD commit.

### Compiling and running Caliptra tests for the FPGA: ###

Please checkout the FPGA section of the MCU [spec](https://chipsalliance.github.io/caliptra-mcu-sw/fpga.html).

### Common Issues ###
- Caliptra logic missing or system hang when attempting to access FPGA Wrapper
  - ```sudo shutdown now``` and use power switch to reboot system
- Failures accessing GitHub or package repositories
  - Date incorrect. Fix date using: ```sudo date -s 'yyyy-mm-dd hh::mm'```

### Processing System - Programmable Logic interfaces ###
[FPGA Wrapper Registers](fpga_wrapper_regs.md)

#### Versal Memory Map ####
| IP/Peripheral                       | Accessibility        | Address size | Start address | End address |
| :---------------------------------- | -------------------- | :----------- | :------------ | :---------- |
| Caliptra core ROM Backdoor          | Always               | 96 KiB       | 0xB000_0000   | 0xB001_7FFF |
| MCU ROM Backdoor                    | Always               | 128 KiB      | 0xB002_0000   | 0xB003_FFFF |
| MCU ROM AXI Sub (provided by SS)    | cptra_ss_rst_b       | 128 KiB      | 0xB004_0000   | 0xB005_FFFF |
| MCU SRAM                            | Always               | 96 KiB       | 0xB008_0000   | 0xB005_FFFF |
| FPGA Wrapper Registers              | Always               | 8 KiB        | 0xA401_0000   | 0xA401_1FFF |
| SS I3C                              | cptra_ss_rst_b       | 8 KiB        | 0xA403_0000   | 0xA403_1FFF |
| LCC                                 | cptra_ss_rst_b       | 8 KiB        | 0xA404_0000   | 0xA404_1FFF |
| OTP                                 | cptra_ss_rst_b       | 8 KiB        | 0xA406_0000   | 0xA406_1FFF |
| Xilinx I3C                          | cptra_ss_rst_b       | 4 KiB        | 0xA408_0000   | 0xA408_0FFF |
| AXI Firewall Control                | Always               | 4 KiB        | 0xA409_0000   | 0xA409_0FFF |
| Caliptra                            | SS reset to Caliptra | 1 MiB        | 0xA410_0000   | 0xA41F_FFFF |
| MCI                                 | cptra_ss_rst_b       | 16 MiB       | 0xA800_0000   | 0xA8FF_FFFF |

### Waveform Debug ###
If built with DEBUG=TRUE common signals for debug will be connected to ILAs. In addition images may be built with additional debug signals. This is a general procedure for loading a probes file when consuming an image built by someone else. If the image was built locally, this is unnecessary because the probes file will be loaded automatically.
- Open Vivado 2024.2. Under "Tasks" there is an option for "Open Hardware Manager"
- Open target
  - If the machine running Vivado is directly connected over USB it can be opened automatically. Alternatively Vivado can connect to a remote host running the hw-server that is connected to the FPGA.
- Load the ltx
  - Under the "Hardware Device Properties" menu specify the "Probes file" by selecting the "..." button on the right.
- Open the ILA in the main window to view the waveform window.

### JTAG debug
Requirements:
- Security state must have either debug_locked == false or lifecycle == manuf.
- Set "debug = true" in firmware profile to provide line information to GDB.
- openocd 0.12.0 (must be configured with --enable-sysfsgpio)
- gdb-multiarch

#### Debugger launch procedure ####
JTAG connectivity is provided using EMIO GPIO pins bridging the PS and PL. OpenOCD is run on the ARM core and uses SysFs to interface with the GPIO pins. The Caliptra, MCU, and LCC JTAGs are each connected to their own set of EMIO pins and can be used independently.
1. Invoke OpenOCD server
    - `./caliptra-mcu-sw/hw/fpga/launch_openocd.sh [core/mcu/lcc]`
1. Connect client(s) for debug
    - GDB: `gdb-multiarch [bin] -ex 'target remote localhost:3333'`
    - Telnet: `telnet localhost 4444`

#### Caliptra SoC interface registers ####
Over Telnet connection to OpenOCD: `riscv.cpu riscv dmi_read [addr]`

#### JTAG testing ####
Test requirements for both OpenOCD and GDB:
- JTAG port is accessible when debug_locked == true or lifecycle == manufacturing. The port is inaccessible otherwise.
- Read access to ROM space using 8, 16, 32, and 64 bit reads.
- Read and write access to DCCM using 8, 16, 32, and 64 bit accesses.
- Access to ICCM using 32 and 64 bit reads, 32 bit writes.
- Access to VEER core registers.
- HW and SW breakpoints halt the CPU.
- Watchpoints on DCCM and Caliptra register access halt the CPU.
 
Test requirements exclusive to GDB:
- Basic commands all work (step, next, frame, info, bt, ni, si, etc.).
 
Test requirements exclusive to OpenOCD:
- Basic commands all work (reg, step, resume, etc.).
- Access to VEER CSRs.
- Access to Debug Module registers.
- Caliptra registers exposed to JTAG RW/RO status matches.
