# План порта MSX1 на Karabas Go / Mini / Mini G

Цель: ядро MSX1 для трёх плат (Xilinx Spartan-6 XC6SLX25-2, ISE 14.7, XST): одно ядро, три верха, как у `karabas-go-core-nes` и `karabas-go-core-tsconf`. Первая плата — Mini G (HDMI, PCM5102), затем Mini (HDMI, sigma-delta, PCM1808 ADC), затем Go (VGA, PCM5102, разъём дисковода).

Главный принцип: **вся работа с файлами — через прошивку MCU** (OSD, загрузчик файлов `FL`, монтирование образов `F` = `CMD_IMG_*`, burst). В ядре нет своего софт-процессора, IPL, FAT-драйвера и OSD-меню: только машина MSX и тонкий слой `kg_mcu` → её интерфейсы.

Затрагиваемые репозитории:

| Репозиторий | Что меняется |
|---|---|
| `karabas-go-core-msx` | ядро: upstream RTL, верхи плат, контроллер SRAM, видео, загрузчики, FDC на image-слоте |
| `karabas-go-modules` | на старте ничего нового (`kg_mcu` с `ENABLE_IMG`, `img_sdc`, `kg_pll`, `kg_dcm`, `kg_*` память, `zhdmi`, `kg_osd_overlay`, ЦАП); позже, возможно, общий эмулятор SD-карты по SPI (Ф5) |
| `karabas-go-firmware` | на старте ничего: `FL` (с `autoload`), `F`, burst, `CMD_CAPS` уже есть; `kg_bk_ram` / `.sav` — при необходимости в Ф5 |
| `karabas-go-tools` | только `core*.json` нового ядра |

## 0. Исходные данные

### Платы

- FPGA XC6SLX25-2: 15 032 LUT6, 3 758 слайсов, 52 RAMB16 (117 КБ), 38 DSP48A1.
- SRAM 2M x 16 (4 МБ), асинхронная, 10 нс. SDRAM 32 МБ (для MSX1 не нужна).
- MCU-линк `kg_mcu`: загрузчики ROM / файлов (burst), OSD, HID (клавиатура, мышь, `JOY_L` / `JOY_R`), RTC, file mounter (`ENABLE_IMG`, `img_sdc`).
- Видео: Go — VGA, Mini / Mini G — HDMI (`zhdmi`). Звук: Go и Mini G — `kg_pcm5102`, Mini — `kg_sigma_delta_dac`.
- Общие правила всех ядер (память karabas-go-notes): Mini / Mini G обязаны всегда давать `FT_CLK_OUT` ~8 МГц; map / par с `-t 2` по умолчанию; сборки только через `src/Makefile`, без `.xise`; не гонять лишние сборки всех плат.

### Что нужно MSX1

| Узел | Объём / темп |
|---|---|
| Z80 3,58 МГц | 1 доступ к памяти на 3–4 такта Z80 (≈ 1 на 280 нс) — SRAM 10 нс с огромным запасом |
| BIOS (MSX1, 32 КБ), Disk ROM (16 КБ) | ROM, из файла ядра или с SD |
| RAM | 64 КБ (слот 3); позже — memory mapper до 1 МБ |
| Картриджи A / B | обычно ≤ 512 КБ, единицы игр 1–2 МБ, мапперы Konami, Konami SCC, ASCII8/16, Gamemaster2, R-Type, linear |
| VRAM TMS9918A | 16 КБ |
| Видео | 256 x 192, 16 цветов, 15 кГц, 60 / 50 Гц |
| Звук | PSG AY-3-8910, SCC в картридже, key click, кассета |

### Кандидаты upstream

| Проект | Язык | Как грузит софт | Вывод |
|---|---|---|---|
| [MiSTer-devel/MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer), ветка `main` (Molekula, `d947f4a` 2025-01-08, GPL-2.0) | `msx1.v`, мапперы, `rom_detect.v` — Verilog; T80, vdp18 (TMS9918A) — VHDL; `slots.sv`, `tape.sv`, `wd1793.sv`, `ls74.sv` — SV; jt49 (PSG), jt8255 | Всё от HPS: `ioctl` (BIOS, ROM A / B, CAS), `img_mount` + `sd_lba` / `sd_buff_*` (DSK на FDD Philips VY0010 + WD1793), автоопределение маппера в RTL | **Основа (рекомендация).** Модель «прошивка грузит, ядро только машина» ровно наша: `ioctl` → `kg_mcu` file loader, `img_mount` → `img_sdc` (его интерфейс `sdc_*` для NanoMig близок к `sd_*` MiSTer: LBA, rd / wr, ack, побайтовый буфер). Встроен C-BIOS (открытый). Маленькое — в LX25 с запасом. Минусы: 4 SV-файла (`sv2v`, как в NES), картриджи в SDRAM / DDR (у нас — SRAM), 15 кГц видео через video_mixer MiSTer (у нас — свой вывод). |
| [fbelavenuto/msx1fpga](https://github.com/fbelavenuto/msx1fpga) (`e5e4720` 2024-01-08, GPL-3.0), цели `syn-zxuno` (ZX-Uno, XC6SLX9), multicore, MiST и др. — это и есть MSX-ядро ZX-Uno / ZXDOS | VHDL, проекты ISE для Spartan-6 | IPL на самом Z80 читает BIOS / Nextor / `CONFIG.TXT` с FAT16 SD-карты; дальше всё через Nextor на SPI SD (`msxsd.vhd`) и утилиты MSX-DOS (`SROM.COM` для .ROM, `SRI.COM` для .DSK); ESE-SCC MegaRAM, memory mapper до 1 МБ, OPLL (vm2413), 50/60 Гц | **Донор (Ф5).** Почти без правок проходит XST, но вся загрузка устроена «изнутри MSX» через SD-карту и FAT — это ровно то, чего мы хотим избежать. Брать из него: memory mapper, ESE-SCC MegaRAM, OPLL, `msxsd.vhd` + драйвер Nextor (для HDD-образа, см. Ф5). Отдельного порта для UnoXT2 я не нашёл; ZX-Uno / ZXDOS используют MSX1FPGA. |
| MiSTer MSX1, ветки `MSX2` / `MSX2test` | много SV, зависит от свежего Main_MiSTer (ROM pack, FM, DB-файлы) | — | Не для этого порта: MSX2 — отдельный проект позже. |
| OCM-PLD / ESE MSX (1chipMSX, MSX2+) | VHDL | IPL из EPCS / SD, MegaSD | Не MSX1, тянет за собой свою экосистему SD / EPCS. Вне рамок. |

Варианты порта:

- **A. MiSTer MSX1 как есть** + наши загрузчики. Быстрее всего даёт картриджи, DSK и CAS из OSD.
- **B. MSX1FPGA как есть** + эмуляция SD по SPI поверх image-слота. Быстрее всего до первого запуска (XST-ready), но .ROM / .DSK — только через утилиты под Nextor, нативного монтирования из OSD нет.
- **C (рекомендация). A как основа, B как донор** по фазам: сначала машина MiSTer с картриджами / DSK / CAS из OSD (Ф1–Ф3), затем из MSX1FPGA — mapper, MegaRAM SCC, OPLL, Nextor на HDD-образе (Ф5).

Решение по варианту фиксируется здесь (после Ф0).

## Архитектура (предварительно, проверяется в Ф0)

### Клоки

Один `kg_pll` от 50 МГц. `clk_sys` MiSTer = 42,95 МГц (12 x 3,58; `ce_10m7` = /4, точка VDP `ce_5m3` = /8). Выбрано (см. «Решения»): VCO 600 МГц, `clk_sys` 42,857 МГц, видео 25,0 МГц, `FT_CLK_OUT` 8,0 МГц; HDMI: `kg_dcm` 5x пиксельного клока.

### Память

| Где | Что |
|---|---|
| SRAM | BIOS 32 КБ и Disk ROM 16 КБ (из файла ядра, `roms` в `core.json`: освобождает 24 RAMB16 против `.mif`), RAM 64 КБ, картридж A и картридж B (до 1,5 МБ каждый), буфер CAS. Раскладка — в Ф0. Один доступ на `ce_10m7` с запасом (10 нс). |
| BRAM | VRAM 16 КБ (8 RAMB16), кадровый буфер (ниже), OSD, буфер сектора `img_sdc`. |
| SDRAM | не используется (`FT_CLK_OUT` и пины — в безопасное состояние). Резерв для картриджей > 1,5 МБ. |

### Видео

Урок SNES (монитор пользователя на Mini G — придирчивый скейлер): только стандартный тайминг, синхры всегда. Поэтому **кадровый буфер** 256 x 192 x 4 бит (индекс палитры TMS9918, 24 КБ, ~12 RAMB16) + цвет бордюра регистром; вывод — ровно 640x480@60 (пиксель MSX = 2 x 2, бордюр вокруг), как у NES. PAL-игры (50 Гц) на выходе 60 Гц — с повтором кадра; опция 576p50 позже, если понадобится. Go — то же на VGA.

### Загрузка и монтирование (только прошивка)

| OSD-пункт `core.json` | Механизм | Куда |
|---|---|---|
| BIOS | `roms` (C-BIOS по умолчанию) + `FL` с `autoload` для своего BIOS (как Kickstart у NanoMig) | SRAM |
| Cart A / Cart B (`.rom`, `.mx1`, `.mx2`) | `FL`, burst; сброс машины на время загрузки | SRAM, `rom_detect` по потоку, маппер Auto / ручной выбор |
| Mapper A / B | soft switch | `slots` MiSTer |
| Disk A: (`.dsk`) | `F`-слот 0, `img_sdc` → `sd_lba` / `sd_rd` / `sd_wr` / `sd_buff_*` | `vy0010` + `wd1793` |
| Tape (`.cas`) | `FL` → буфер в SRAM, `tape.sv` | порт кассеты PPI |
| Video 50/60, Border, Reset, Joy swap и т. п. | soft switches | |

Всё это — существующие механизмы прошивки; новых команд не нужно.

### Ввод и звук

- Клавиатура: USB HID из `kg_mcu` → матрица MSX (свой `hid_parser`, как у NES / TSConf; MiSTer ждёт `ps2_key`). Раскладка — как в README MSX1FPGA (Left Alt = GRAPH, Right Alt = CODE, PgUp = SELECT, End = STOP).
- Джойстики: `JOY_L` / `JOY_R` → два порта MSX (2 кнопки), опция swap.
- Звук: jt49 + SCC + key click + кассета → микшер → `kg_pcm5102` / `kg_sigma_delta_dac`. Вход кассеты с ADC PCM1808 на Mini — опция Ф3.

## Фазы

### Ф0. Каркас и fit gate

1. Репозиторий на GitHub (`andykarpov/karabas-go-core-msx`, создаёт пользователь), сабмодуль `modules/` (`../karabas-go-modules.git`), `src/make_core.py` → симлинк на karabas-go-tools, `src/Makefile` по образцу NES (`go`, `mini`, `minig`, шаги `-xst`, `-impl`, `-core`, `-report`, `MAP_T_<board>` = 2).
2. Клон MiSTer MSX1 (`main`, зафиксированный коммит) в `src/sim/build/upstream` (вне git); `docs/UPSTREAM.md` — инвентарь файлов, языков, что берём.
3. Перенос RTL в `src/rtl/msx`: VHDL и Verilog как есть, SV — через `sv2v` (`/opt/sv2v/sv2v`), правки помечены `// karabas:`; Altera `spram` / `dpram` → `kg_spram` / `kg_tdpram`, `.mif` → `.hex` (`modules/tools/coe2hex.py` или свой конвертер).
4. Пробный XST-синтез `msx1` отдельно: LUT, RAMB16, отчёт «Clock Information» (никаких клоков из логики и латчей). Записать решение по варианту и раскладке SRAM сюда.

Готово, когда: `msx1` синтезируется в XST без ошибок, ресурсы записаны, вариант утверждён.

### Ф1. Mini G: первый запуск

1. `karabas_minig_top.v`: `kg_pll`, `kg_mcu` (burst, `BURST_MAX_MHZ` 32), `kg_soft_switches`, `kg_osd_overlay`, `zhdmi`, `kg_pcm5102`, `FT_CLK_OUT`.
2. Контроллер SRAM, BIOS из `roms`, RAM 64 КБ.
3. Кадровый буфер и вывод 640x480@60.
4. Клавиатура и джойстики.
5. Картридж A (и B) через `FL` с автоопределением маппера.
6. Тесты: verilator / iverilog — загрузка ROM через модель `kg_mcu` (как `run_burst_sim.sh` NES), кадр C-BIOS в `.ppm`; на железе — пользователь.

Готово, когда: на Mini G грузится C-BIOS, BASIC, игры с картриджей Konami / ASCII.

### Ф2. Дисковод

1. `F`-слот 0 → `img_sdc` → интерфейс `sd_*` `vy0010` / `wd1793`; Disk ROM в SRAM.
2. Запись секторов, смена диска, write protect (если образ только для чтения).
3. Риск: сектор через MCU идёт 5–15 мс (у MiSTer — микросекунды). `wd1793` ждёт `sd_ack`, но загрузчики с таймаутами по индексу могут сломаться: проверить на нескольких DSK-играх; если надо — предвыборка трека / сектора вперёд.
4. Тест `tb_fdd` с моделью MCU (по образцу `tb_ata` next186).

### Ф3. Кассета

`FL` для `.cas` → буфер в SRAM → `tape.sv` (мотор от PPI); опция «Tape input: File / ADC» (PCM1808 на Mini).

### Ф4. Mini и Go, релиз

Верхи Mini (sigma-delta, PCM1808) и Go (VGA); `core_mini.json`, `core.json`; сборка трёх плат, тайминг, `.bin` / `.kg*` в git, релиз в `karabas-go` / `karabas-mini`.

### Ф5. Расширения (по желанию, порядок обсуждается)

- Memory mapper 256 КБ – 1 МБ в SRAM (MSX1FPGA / OCM).
- ESE-SCC MegaRAM, OPLL (vm2413 из MSX1FPGA) как опции.
- Nextor на HDD-образе: `F`-слот 1 + интерфейс SD MSX1FPGA (`msxsd.vhd`) поверх эмулятора SPI SD-карты на `img_sdc` (CMD0/8/55/41/58/17/24/18/25, ответ R1 / токены данных); Nextor ROM с драйвером MSX1FPGA. Тогда драйвер Nextor не меняется. Альтернатива — прямой доступ к SD2 (вторая карта у FPGA, как у PDP-11 / next186), но это мимо прошивки.
- Gamemaster2 SRAM и другие батарейные картриджи — `.sav` через `kg_bk_ram` (caps bit 3, как у NES).
- Физический дисковод Karabas Go (`F` с флагом `physical`, как у NanoMig).
- Turbo, 576p50 для PAL.

## Решения

- **2026-10-30, вариант C** (пользователь): основа MiSTer MSX1 `main` `d947f4a`, донор MSX1FPGA. Репозиторий `andykarpov/karabas-go-core-msx` (создан приватным: публичный не дала создать политика инструментов; видимость меняет пользователь), работа Ф0 в ветке `f0-skeleton`.
- **2026-10-30, fit gate пройден** (`make msx1-xst`): 6 194 LUT (41 %), 26 / 52 RAMB16, один клок, без латчей. Инвентарь и правки — `docs/UPSTREAM.md`.
- **2026-10-30, память**: BIOS, logo / firmware ROM, RAM слота 3, картриджи — в SRAM (карта в `msx1.v`: 000000 BIOS, 008000 ROM слота 0 страницы 2, 010000 RAM, 100000 картридж B, 200000 картридж A, по 1 МБ; файл больше 1 МБ обрезается). В BRAM остаются VRAM, Disk ROM VY0010 (8 RAMB16, кандидат на перенос в SRAM, если понадобится место), SRAM картриджей 8 КБ, буферы.
- **2026-10-30, клоки**: один `kg_pll`, VCO 600 МГц (M = 12, D = 1): `clk_sys` /14 = 42,857 МГц (−0,23 % к 12 x 3,579545: кадр 59,80 Гц вместо 59,94, звук на 4 цента ниже), видео /24 = 25,000 МГц, `FT_CLK_OUT` /75 = 8,000 МГц; 5x для HDMI — `kg_dcm` от 25 МГц, как у NES. Точнее по частоте только VCO 1075 МГц (43,0 МГц, +0,11 %), но с него нет 8 МГц для FT812 (делитель > 128) и 25 МГц только /43.
- **2026-10-30, BIOS**: C-BIOS 0.29a (BSD-2, `src/roms/LICENSE.cbios`): `cbios_main_msx1_eu.rom` (как у MiSTer) в 000000, `cbios_logo_msx1.rom` в 008000 (слот 0, 8000–BFFF, как в конфигах openMSX C-BIOS). У C-BIOS нет BASIC: для BASIC / дисков пользователь грузит свой BIOS через `FL` с `autoload`.
- **2026-10-30, Ф1**: PR на фазу (пользователь). `kg_mcu` получил `FILELOAD_SLOT` (ветка модулей `msx-core`, PR в конце Ф1): без него три `FL`-пункта не различить. Клавиатура — PS/2 set 2 из `KB_SCANCODE` прошивки → `ps2_key` MiSTer, `keyboard.vhd` без изменений. OSD — `kg_osd_overlay` на clk_vga, команды через `kg_async_fifo`. HDMI — `hdmi_tx` zhdmi напрямую (`zhdmi_top` заточен под 28/24 МГц), аудио 48 кГц. Пункт `S` OSD — не больше 8 вариантов: маппер R-Type убран из меню (Linear 64K оставлен, индекс = код маппера).
- **2026-10-30, Ф1, сборка 26103001 Mini G**: 8 081 LUT, 76 % слайсов, 40 RAMB16 + 2 RAMB8, тайминг выполнен. Симуляция (verilator, VHDL через ghdl --synth): C-BIOS до текстового экрана, мапперы Konami / Konami SCC / ASCII8 / ASCII16 с автоопределением — OK (`src/sim/carts/run_carts.sh`). На железе не проверено.
- **2026-10-30, Ф1, железо (пользователь, Mini G, 26103001)**: картинка есть, тестовые картриджи и игры работают, PAL/NTSC переключаются без потери сигнала, клавиатура работает. Открыто: в симуляции клавиатура не доходит до программы — BIOS не меняет строку матрицы (порт C PPI остаётся 0, хотя прерывания идут раз в кадр); на железе работает, так что это особенность стенда (`keys.rom`, `SIM_KBDBG`, `SIM_ISR` в `sim_sys`), разбираться при случае.

