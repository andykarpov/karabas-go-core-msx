# Инвентаризация upstream (Ф0)

Снято 2026-10-30. Клоны для сравнения — вне git, `src/sim/build/upstream/`:

| Репозиторий | Коммит | Дата | Роль |
|---|---|---|---|
| [MiSTer-devel/MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer), ветка `main` | `d947f4a` | 2025-01-08 | основа, `src/rtl/msx` |
| [fbelavenuto/msx1fpga](https://github.com/fbelavenuto/msx1fpga) | `e5e4720` | 2024-01-08 | донор (Ф5) |
| C-BIOS 0.29a ([cbios.sourceforge.net](http://cbios.sourceforge.net/), `cbios-0.29a.zip`) | — | 2018-09-23 | BIOS по умолчанию, `src/roms` |

История `src/rtl/msx` в git: коммит импорта (`7085126`, файлы как в upstream), `sv2v` (`6681756`), затем правки под XST, каждая помечена `karabas:` в коде. `git diff 7085126 -- src/rtl/msx` показывает всё, что изменено.

## MSX1_MiSTer: что взято

| Файл | Язык | Что это | Правки |
|---|---|---|---|
| `msx1.v` | Verilog | машина: T80, VDP, PPI, PSG, слоты, мультиплексор шины | порт памяти `mem_*` и карта SRAM вместо BRAM / SDRAM; объявления проводов перед использованием; массив `compr` как `case`; `HALT_n` — выход; `ram_mapper` (Ф5) и вход `ram_mapper_en` |
| `T80/` | VHDL | Z80 (`t80pa`; `T80s.vhd` не в prj) | нет |
| `vdp18/` | VHDL | TMS9918A (Arnim Läuger) | `entity work.` в инстансах; синхронный сброс счётчиков `hor_vert` |
| `jt49/` | Verilog | AY-3-8910 (jotego); `filter/` не в prj | нет |
| `jt8255.v` | Verilog | PPI 8255 | нет |
| `keyboard.vhd` | VHDL | PS/2 (`ps2_key` MiSTer) → матрица MSX | нет; заменяется своим HID (Ф1) |
| `cv_clock.vhd` | VHDL | 3,58 МГц из 10,7 МГц | нет |
| `io_decoder.v`, `memory_mapper.v` | Verilog | порты I/O, первичные слоты | `memory_mapper`: регистр `enable` на `clk` |
| `ram_mapper.v` | Verilog | — | **свой** (Ф5): memory mapper RAM слота 3, порты FC–FF, 512 КБ (32 сегмента по 16 КБ) |
| `jtopl/` (из [jotego/jtopl](https://github.com/jotego/jtopl) `7ac0c81`, GPL v3; файлы `jt2413` из `cfg/jt2413.yaml`, импорт `94a506f` без изменений) | Verilog | OPLL YM2413 (MSX-MUSIC), Ф5 | `jtopll_reg_ch.v`: убрано `i <= 0` (XST: смесь блокирующих и неблокирующих присваиваний) |
| `ls74.v` (был `.sv`) | SV → свой Verilog | 74LS74 для WAIT и строба PSG | переписан на `clk` с enable (upstream тактировался `clk_en_3m58_p`) |
| `slots.v` (`sv2v`) | SV | слоты 1–3, картриджи A / B, FDD | RAM слота 3 и ROM картриджа — в SRAM; `last_loadRom` на `clk`; вход `fdd_rom_en` |
| `cart/rom.v`, `rom_detect.v`, мапперы (`konami`, `konami_scc`, `ascii8`, `ascii16`, `gamemaster2`) | Verilog | картридж, автоопределение маппера по потоку загрузки | `rom_detect`: `reg` из always наружу, конвейер счётчиков, `mapper` / `offset` зарегистрированы (тайминг); `ascii16`: синхронный сброс |
| `cart/scc_wave.vhd`, `cart/ram.vhd` | VHDL | SCC (OCM) | `entity work.` |
| `tape.v` (`sv2v`) | SV | CAS-плеер (MiSTer `tape.sv`) | блокирующие присваивания сигналам других always — неблокирующие (как строит Quartus); `SILENT` / `SYNC` — параметры (короче в симуляции) |
| `cart/vy0010.v` | Verilog | FDD Philips VY0010 | регистры 7FFC / 7FFD на `clk`; ROM `.mif` → `.hex`; разметка `img_ss` для образов ≤ 360 КБ; вход `rom_en` (ROM отдаёт FF для «Disk (no ROM)») |
| `cart/wd1793.v` (`sv2v`) | SV | FDC WD1793 (Sorgelig), `RWMODE=1`, `EDSK=0` | `buff_wr` / `spt_addr` объявлены в модуле |
| `rom/vy0010.mif` → `vy0010.hex` | | Disk ROM VY0010, 16 КБ | `src/tools/mif2hex.py` |

Не взято: фреймворк MiSTer (`sys/`, `MSX1.sv` — верх с `hps_io`, `video_mixer`), `pll`, `sdram.sv`, `ddram.sv` (CAS читался из DDR3 — в Ф3 буфер в SRAM), `bram.vhd` (altsyncram → `rtl/msx/spram.v` на `kg_spram`). `tape.v` (`sv2v`) лежит в `src/rtl/msx`, в prj — с Ф3. В upstream нет `cbios_main_msx1_eu.mif`, на который ссылается `msx1.v`: C-BIOS берётся из дистрибутива.

## Интерфейсы MiSTer → Karabas

| MiSTer (`MSX1.sv`) | Karabas |
|---|---|
| `ioctl_index` 0 / 1 (BIOS), FWBIOS | `roms` в `core.json` (ROM loader `kg_mcu`), свой BIOS — `FL` с `autoload` |
| `ioctl_index` 2 / 3 (ROM A / B) | `FL`-пункты Cart A / B (file loader, burst) |
| `ioctl_index` 4 (CAS) | `FL` Tape (Ф3) |
| `img_mount`, `sd_lba`, `sd_rd` / `sd_wr`, `sd_ack`, `sd_buff_*` | `F`-слот → `img_sdc` (Ф2) |
| `status[20:17]` / `[24:21]` (маппер A / B), `status[16]` (PAL), `status[3]` (бордюр) | soft switches |
| `ps2_key` | USB HID `kg_mcu` → матрица MSX |
| `joy0` / `joy1` (6 бит) | `JOY_L` / `JOY_R` |
| SDRAM (картриджи), DDR3 (CAS) | SRAM 4 МБ (карта в `msx1.v`) |

## Результат пробного синтеза (`make msx1-xst`, 2026-10-30)

6 194 LUT (41 %), 2 610 регистров, 26 из 52 RAMB16 (VRAM 8, VY0010 ROM 8, SRAM картриджей 2 x 4, буфер `wd1793`, SCC); один клок `clk`, латчей нет.

## MSX1FPGA: что взять в Ф5

`src/peripheral/`: memory mapper в `memoryctl.vhd`, `escci/` (ESE-SCC MegaRAM), `vm2413/` (OPLL), `msxsd.vhd` (SPI-интерфейс SD для Nextor), `SW/nextor` (драйвер Nextor). Лицензия GPL-3.0 (MSX1_MiSTer — GPL-2.0, проверить совместимость при переносе).
