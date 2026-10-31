# MSX1 core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

An MSX1 computer for the Karabas Go family of boards. It is a port of
[MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer) by molekula to the Xilinx Spartan-6
XC6SLX25 of the Karabas boards. All file work (cartridges, disk images, tapes, the BIOS) goes through
the OSD and the file browser of the board firmware: the core has no loader of its own.

| Board | Core file | Video | Audio |
|---|---|---|---|
| Karabas Go | `msx.kg1` | VGA, 640x480 60 Hz | I2S DAC (PCM5102) |
| Karabas Mini | `msx.kg2` | HDMI, 640x480 60 Hz | HDMI, analog output (sigma-delta) |
| Karabas Mini G | `msx.kg3` | HDMI, 640x480 60 Hz | HDMI, I2S DAC (PCM5102) |

The core files are in `src/` and in the release repos
([karabas-go](https://github.com/andykarpov/karabas-go),
[karabas-mini](https://github.com/andykarpov/karabas-mini)).

**State:** the Mini G build is tested on hardware (cartridges and games; the disk drive and the tape
with test cartridges, not yet with a real MSX BIOS). The Mini and Go builds are made from the same sources and are not tested on hardware yet.

## What it does

- **The MSX1 of MSX1_MiSTer:** Z80 (T80), TMS9918 VDP (vdp18), AY-3-8910 PSG (jt49), PPI, 512 KB of
  RAM in slot 3 with the memory mapper of the MSX2 (ports FC-FF; the OSD item RAM, 64K: the plain
  64 KB of an MSX1).
- **MSX-MUSIC:** the OPLL (YM2413, [jt2413](https://github.com/jotego/jtopl)) at the ports 7C-7D, as
  the internal MSX-MUSIC of later machines: without cartridge B, slot 2 shows its ROM signature
  (`APRLOPLL`), so games find it. The OSD item FM (MSX-MUSIC) turns it off.
- **BIOS:** [C-BIOS](http://cbios.sourceforge.net/) 0.29a is built into the core (EU version with
  its logo). It boots cartridges, but it has no BASIC and no tape or disk routines. For BASIC, disk
  and tape software load the BIOS of a real MSX1 with the OSD item BIOS (32 KB, or 48 KB with a
  ROM for page 2 of slot 0); it is loaded again at every start of the core.
- **Two cartridge slots** (A in slot 1, B in slot 2), up to 1 MB each, with the mapper found from
  the ROM: none (plain 16 / 32 / 48 KB), Konami, Konami SCC (with the SCC sound), ASCII 8, ASCII 16,
  Game Master 2, linear 64 KB. The OSD items Mapper A / Mapper B override the detection.
- **Disk drive:** the Philips VY-0010 interface (WD1793 FDC and its disk ROM) in slot 1 instead of
  cartridge A, with `.dsk` images of 360 or 720 KB. The image is read into the SRAM of the board in
  the background after it is mounted, so the drive works at the speed of a real one; writes go to
  the SRAM and to the image file at once.
- **Tape:** `.cas` files (up to 256 KB) played to the cassette input of the MSX at 2400 baud while
  the motor of the PPI is on, as on a real tape recorder (`RUN"CAS:"`, `BLOAD"CAS:",R`, `CLOAD`).
  The TAPE_IN pin of the board can be the cassette input instead (a real tape recorder), TAPE_OUT
  carries the cassette output (`CSAVE`).
- **Video:** the 256x192 picture with its border in the middle of 640x480 at 60 Hz (a frame buffer),
  the PAL (50 Hz) or NTSC (60 Hz) timing of the VDP chosen in the OSD. HDMI with sound on Mini and
  Mini G.
- **Input:** the USB keyboard as the MSX keyboard, two MSX joysticks: the joysticks of the board or
  USB gamepads.

Not there yet (see `docs/BACKLOG.md`): SCC MegaRAM,
Nextor on a hard disk image, the save RAM of Game Master 2 and other battery cartridges.

## Getting started

1. Copy `msx.kg1` (Go), `msx.kg2` (Mini) or `msx.kg3` (Mini G) to the root of the SD card.
2. Put your files into the folder `/msx` of the SD card: cartridges (`.rom`, `.mx1`, `.mx2`, `.bin`),
   disk images (`.dsk`), tapes (`.cas`), a BIOS (`.rom`).
3. Choose MSX1 in the core menu, open the OSD with Menu+Esc and load a cartridge with Cart A
   (Menu+F1). The machine starts the cartridge when it is loaded.

Disks and tapes need a real MSX BIOS (OSD item BIOS): C-BIOS hangs in the INIT of the disk ROM.
For a disk: Slot 1 = Disk drive, then a `.dsk` in Disk A. For a tape: a `.cas` in Tape, then
`RUN"CAS:"` (BASIC programs), `BLOAD"CAS:",R` (machine code) or `CLOAD` + `RUN`; Tape rewind starts
the file again.

## OSD menu

| Item | Values | Hotkey |
|---|---|---|
| Cart A | a cartridge for slot 1 | Menu+F1 |
| Mapper A | Auto / None / Game Master 2 / Konami / Konami SCC / ASCII 8 / ASCII 16 / Linear 64K | |
| Cart B | a cartridge for slot 2 | Menu+F2 |
| Mapper B | as Mapper A | |
| Slot 1 | Cartridge A / Disk drive / Disk (no ROM) | Menu+D |
| Disk A | the `.dsk` image of the drive | Menu+F3 |
| Tape | a `.cas` file | Menu+F4 |
| Tape rewind | the tape from its start | Menu+R |
| Tape input | CAS file / Tape in (TAPE_IN) | |
| RAM | 512K mapper / 64K | |
| FM (MSX-MUSIC) | On / Off | |
| Video | PAL 50Hz / NTSC 60Hz | Menu+V |
| Joysticks | Normal / Swap | Menu+J |
| BIOS | a BIOS file, loaded at every start | |
| Reset | resets the MSX | F12 |
| Eject carts | removes both cartridges (and resets) | Menu+E |

"Menu" is the Windows key of the keyboard. Loading a cartridge or a BIOS, or changing a mapper or
Slot 1, resets the machine; loading a tape does not. Disk (no ROM) is the drive without its disk ROM
(only its registers), for test programs that drive the FDC themselves under C-BIOS.

## Keyboard

The keys of the PC keyboard are the keys of the MSX in their places. The special keys of the MSX:

| MSX | PC |
|---|---|
| GRAPH | Right Alt |
| CODE | F10 |
| SELECT | F11 |
| STOP | Print Screen |
| dead key | F9 |
| HOME, INS, DEL, arrows | the same keys |
| F1..F5 | F1..F5 |

## Building

The core is built with Xilinx ISE 14.7 on Linux: `cd src && make` (all three boards, one after the
other), or `make go`, `make mini`, `make minig`; `make minig-report` shows the utilization and the
timing of the last build. The board modules are the submodule `modules/`
([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)): clone with
`git clone --recursive` or run `git submodule update --init`. Packing the `.kg` files needs the
sibling repo [karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) next to this one
(`make_core.py`).

The simulations (verilator with ghdl for the VHDL; regressions of the cartridge mappers, the disk
drive and the tape) are in `src/sim`. `CLAUDE.md` has the layout and the rules of the design,
`docs/PLAN.md` (Russian) the plan and the decisions, `docs/UPSTREAM.md` what was taken from the
upstream and what was changed.

The board firmware is [karabas-go-firmware](https://github.com/andykarpov/karabas-go-firmware).

## Credits and license

- [MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer): molekula and the MiSTer contributors
  (the machine, the slots and mappers, the VY-0010 / WD1793 disk interface, the CAS player).
- T80: Daniel Wallner, MikeJ, Sorgelig and others. vdp18: Arnim Laeuger. jt49, jt8255 and jt2413 (jtopl): Jose
  Tejada.
- [C-BIOS](http://cbios.sourceforge.net/): the C-BIOS team.
- Karabas Go boards and the port: Andy Karpov.

The core is under the GNU GPL v3 (`LICENSE`). Its parts keep their own licenses, all compatible with
it: MSX1_MiSTer GPL v2 or later, jt49 and jtopl GPL v3, T80 and vdp18 BSD-style licenses, jt8255 MIT,
C-BIOS a BSD 2-clause license (`src/roms/LICENSE.cbios`; the C-BIOS ROMs are built into the core
files). The disk ROM of the VY-0010 (`src/rtl/msx/rom`) comes from MSX1_MiSTer.
