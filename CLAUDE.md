# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A port of an MSX1 machine to the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25-2, ISE 14.7 (XST). One core, three tops (`src/rtl/karabas_go_top.v` VGA + PCM5102, `karabas_mini_top.v` HDMI + sigma-delta + PCM1808 ADC, `karabas_minig_top.v` HDMI + PCM5102), as in `karabas-go-core-nes` and `karabas-go-core-tsconf`. Mini G is the first target.

Status: Ф0 done (2026-10-30, branch `f0-skeleton`): the machine of MiSTer MSX1 is in `src/rtl/msx` and goes through XST alone (`make msx1-xst`); no board tops yet (Ф1). The plan is `docs/PLAN.md` (Russian): the upstream candidates, the architecture, the phases Ф0..Ф5 and the decisions. Follow its phases and record each decision in its "Решения" section. `docs/UPSTREAM.md`: what was taken from the upstream and what was changed.

The main rule of this port: **all file work goes through the MCU firmware** (the OSD, the file loader `FL` items with `autoload`, the file mounter `F` items = `CMD_IMG_*`, bursts). The core has no soft CPU, no IPL, no FAT driver and no OSD menu of its own: only the MSX machine and a thin layer from `kg_mcu` to its interfaces. Do not bring in the SD / FAT / IPL boot of MSX1FPGA or OCM.

Base (variant C, decided 2026-10-30): MiSTer MSX1 (`MiSTer-devel/MSX1_MiSTer`, branch `main`, `d947f4a`): its `ioctl` (BIOS, cartridges, CAS) maps to the file loader of `kg_mcu`, its `img_mount` / `sd_*` (DSK on the VY0010 + WD1793 FDC) to `img_sdc`, the mapper detection is in RTL. Donor: MSX1FPGA (`fbelavenuto/msx1fpga`, the MSX core of ZX-Uno / ZXDOS) for the memory mapper, MegaRAM SCC, OPLL and Nextor on a HDD image (Ф5).

## Related repositories (siblings in `..`)

- `karabas-go-modules` (submodule `modules/`, from Ф0): `kg_mcu` (`ENABLE_IMG`), `img_sdc`, `kg_pll`, `kg_dcm`, the `kg_*` memories, `zhdmi`, `kg_osd_overlay`, the DACs. Its `CLAUDE.md` has the rules (Verilog-2001 for XST, no coregen, `ENABLE_*` parameters, clock crossings, tests). A change to them is made there and taken here by updating the submodule commit.
- `karabas-go-firmware`: the MCU side. `docs/protocol.md` (file loader, file mounter section 6, `CMD_CAPS` section 7) and `docs/burst_protocol.md`. This port needs no firmware change for Ф0..Ф4.
- `karabas-go-tools`: `make_core.py` packs `core.json` (Go), `core_mini.json`, `core_minig.json` into `msx.kg1` / `kg2` / `kg3`; `src/make_core.py` will be a symlink to it.
- Examples: `karabas-go-core-nes` (Makefile, `sv2v` of upstream SV, frame buffer video, `hid_parser`, burst sim), `karabas-go-core-nanomig` (`img_sdc` with a floppy, `FL` autoload of the Kickstart), `karabas-go-core-next186` (`img_sdc` + `hdf_ata`, `tb_ata` with an MCU model), `karabas-go-core-snes` (a port plan with a fit gate; the video timing lessons on the user's monitor).

## Build

- `cd src && make` builds the three boards (`make go`, `mini`, `minig`; steps `minig-xst`, `-impl`, `-core`; `make minig-report` the utilization and timing), the ISE command-line flow, sourcing `/opt/Xilinx/14.7/ISE_DS/settings64.sh`. No `.xise`, no `ipcore_dir`. The boards share `xst/` and `_ngo/` in `src/`: one build at a time.
- Inputs per board: `karabas_<board>.prj` (sources, the shared modules as `"../modules/rtl/..."`), `.xst`, `.ut`, `.ucf`. Map / par with cost table `-t 2` by default (`MAP_T_<board>`).
- Check `*_map.mrp` (LUTs, slices, RAMB16) and `*.par` (timing) after a change. The `.bin` and `.kg*` files are committed as the release.
- `make msx1-xst` synthesizes the machine alone (`msx1.prj`, `msx1.xst`, `-iobuf NO`) in about a minute; `make msx1-report` prints its LUTs, registers and block RAMs. Use it to check a change of `src/rtl/msx` (errors, the one clock in "Clock Information" of `msx1.syr`, no latches) before a board build.
- Builds take 10..30 minutes: run them in the background, one board at a time, do not edit RTL while XST runs, and do not run builds of all boards without need.

## Layout

- `src/rtl/msx`: the machine (`msx1.v` and what it instantiates, see `docs/UPSTREAM.md`). Its memory port `mem_addr` / `mem_we` / `mem_din` / `mem_dout` goes to the SRAM; the map is at the end of `msx1.v` (000000 BIOS, 008000 the ROM of slot 0 page 2, 010000 RAM, 100000 cartridge B, 200000 cartridge A). `spram.v` is the MiSTer `spram` on `kg_spram`. `tape.v` is not in the prj yet (Ф3).
- `src/roms`: C-BIOS 0.29a (BSD-2, `LICENSE.cbios`) for the `roms` of `core.json`.
- `src/tools/mif2hex.py`: the `.mif` of the upstream to `$readmemh` files.

## Rules

- **Upstream code** is in `src/rtl/msx` at a fixed commit (`docs/UPSTREAM.md`; the import commit `7085126` has the files unchanged) and keeps its form; local changes are marked `// karabas:` (`-- karabas:` in VHDL) with the reason. SystemVerilog is converted with `sv2v` (`/opt/sv2v/sv2v`); Altera memories become `kg_*`, `.mif` become `.hex`. The upstream clones for study go to `src/sim/build/upstream` (not in git).
- **Verilog-2001 that XST accepts** for our code (see the modules `CLAUDE.md`). No clocks from logic, no latches (check "Clock Information" of the `.syr`). What Quartus takes and XST does not (found in Ф0): wires used before their declaration, regs of a generate block used by their short name outside it, `x : work.y` without `entity`, constants on output ports, async resets to non-constant values (latches), registers clocked by strobes or clock enables.
- **Mini / Mini G must always drive `FT_CLK_OUT`** (~8 MHz) from the start of the core.
- **Video: standard timing only, syncs always present** (640x480@60 from a frame buffer); the user's Mini G monitor rejects anything else.
- **OSD switch index** = position of the item in the `osd` list of `core.json`, file items included: moving an item renumbers the soft switch registers after it.
- A test is worth something only if it fails without the code it covers. Simulators: verilator, iverilog, ghdl, ISim. If a tool is missing, ask the user to install it.
- Hardware tests are done by the user: ask before flashing anything.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`, `link.sh` there makes the links). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
