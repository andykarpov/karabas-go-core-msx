# Ядро MSX1 для Karabas Go / Mini / Mini G

[English version](README.md)

Компьютер MSX1 для плат семейства Karabas Go. Это порт
[MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer) (автор molekula) на Xilinx Spartan-6
XC6SLX25 плат Karabas. Вся работа с файлами (картриджи, образы дисков, кассеты, BIOS) идёт через OSD
и файловый браузер прошивки платы: своего загрузчика в ядре нет.

| Плата | Файл ядра | Видео | Звук |
|---|---|---|---|
| Karabas Go | `msx.kg1` | VGA, 640x480 60 Гц | I2S ЦАП (PCM5102) |
| Karabas Mini | `msx.kg2` | HDMI, 640x480 60 Гц | HDMI, аналоговый выход (sigma-delta) |
| Karabas Mini G | `msx.kg3` | HDMI, 640x480 60 Гц | HDMI, I2S ЦАП (PCM5102) |

Файлы ядра лежат в `src/` и в релизных репозиториях
([karabas-go](https://github.com/andykarpov/karabas-go),
[karabas-mini](https://github.com/andykarpov/karabas-mini)).

**Состояние:** сборка для Mini G проверена на железе (картриджи и игры; дисковод и кассета — тестовыми
картриджами, с настоящим BIOS MSX пока нет). Сборки для Mini и Go сделаны из тех же исходников и на
железе ещё не проверены.

## Что умеет

- **MSX1 из MSX1_MiSTer:** Z80 (T80), видеопроцессор TMS9918 (vdp18), звук AY-3-8910 (jt49), PPI,
  512 КБ RAM в слоте 3 с memory mapper MSX2 (порты FC–FF; пункт OSD RAM, 64K — обычные 64 КБ MSX1).
- **BIOS:** в ядро встроен [C-BIOS](http://cbios.sourceforge.net/) 0.29a (европейская версия с
  логотипом). Он запускает картриджи, но в нём нет BASIC и процедур кассеты и дисковода. Для BASIC,
  дисков и кассет загрузите BIOS настоящего MSX1 пунктом OSD BIOS (32 КБ или 48 КБ с ROM страницы 2
  слота 0); он загружается заново при каждом старте ядра.
- **Два слота картриджей** (A в слоте 1, B в слоте 2), до 1 МБ каждый, маппер определяется по ROM:
  без маппера (16 / 32 / 48 КБ), Konami, Konami SCC (со звуком SCC), ASCII 8, ASCII 16, Game Master 2,
  линейный 64 КБ. Пункты Mapper A / Mapper B задают маппер вручную.
- **Дисковод:** интерфейс Philips VY-0010 (контроллер WD1793 и его Disk ROM) в слоте 1 вместо
  картриджа A, образы `.dsk` на 360 или 720 КБ. После монтирования образ в фоне копируется в SRAM
  платы, поэтому дисковод работает со скоростью настоящего; запись идёт в SRAM и сразу в файл образа.
- **Кассета:** файлы `.cas` (до 256 КБ) проигрываются на вход магнитофона MSX со скоростью 2400 бод,
  пока PPI включает мотор, как с настоящим магнитофоном (`RUN"CAS:"`, `BLOAD"CAS:",R`, `CLOAD`).
  Вместо файла входом может быть вывод TAPE_IN платы (настоящий магнитофон), на TAPE_OUT — выход
  записи (`CSAVE`).
- **Видео:** картинка 256x192 с бордюром в середине 640x480 60 Гц (через буфер кадра), развёртка
  VDP PAL (50 Гц) или NTSC (60 Гц) выбирается в OSD. HDMI со звуком на Mini и Mini G.
- **Управление:** USB-клавиатура как клавиатура MSX, два джойстика MSX: джойстики платы или
  USB-геймпады.

Пока нет (см. `docs/BACKLOG.md`): SCC MegaRAM, OPLL (MSX-MUSIC), Nextor на
образе жёсткого диска, сохранение памяти Game Master 2 и других картриджей с батарейкой.

## Как начать

1. Скопируйте `msx.kg1` (Go), `msx.kg2` (Mini) или `msx.kg3` (Mini G) в корень SD-карты.
2. Положите файлы в папку `/msx` на SD-карте: картриджи (`.rom`, `.mx1`, `.mx2`, `.bin`), образы
   дисков (`.dsk`), кассеты (`.cas`), BIOS (`.rom`).
3. Выберите MSX1 в меню ядер, откройте OSD (Menu+Esc) и загрузите картридж пунктом Cart A (Menu+F1).
   Машина запускает картридж сразу после загрузки.

Для дисков и кассет нужен настоящий BIOS MSX (пункт BIOS): C-BIOS зависает в INIT Disk ROM.
Диск: Slot 1 = Disk drive, затем `.dsk` в Disk A. Кассета: `.cas` в Tape, затем `RUN"CAS:"`
(программы на BASIC), `BLOAD"CAS:",R` (машинный код) или `CLOAD` + `RUN`; Tape rewind ставит файл
на начало.

## Меню OSD

| Пункт | Значения | Клавиши |
|---|---|---|
| Cart A | картридж в слот 1 | Menu+F1 |
| Mapper A | Auto / None / Game Master 2 / Konami / Konami SCC / ASCII 8 / ASCII 16 / Linear 64K | |
| Cart B | картридж в слот 2 | Menu+F2 |
| Mapper B | как Mapper A | |
| Slot 1 | Cartridge A / Disk drive / Disk (no ROM) | Menu+D |
| Disk A | образ `.dsk` дисковода | Menu+F3 |
| Tape | файл `.cas` | Menu+F4 |
| Tape rewind | кассета на начало | Menu+R |
| Tape input | CAS file / Tape in (TAPE_IN) | |
| RAM | 512K mapper / 64K | |
| Video | PAL 50Hz / NTSC 60Hz | Menu+V |
| Joysticks | Normal / Swap | Menu+J |
| BIOS | файл BIOS, загружается при каждом старте | |
| Reset | сброс MSX | F12 |
| Eject carts | вынуть оба картриджа (и сброс) | Menu+E |

«Menu» — клавиша Windows на клавиатуре. Загрузка картриджа или BIOS, смена маппера или Slot 1
сбрасывают машину; загрузка кассеты — нет. Disk (no ROM) — дисковод без Disk ROM (только его
регистры), для тестовых программ, которые сами управляют контроллером под C-BIOS.

## Клавиатура

Клавиши PC-клавиатуры — клавиши MSX на своих местах. Особые клавиши MSX:

| MSX | PC |
|---|---|
| GRAPH | правый Alt |
| CODE | F10 |
| SELECT | F11 |
| STOP | Print Screen |
| мёртвая клавиша | F9 |
| HOME, INS, DEL, стрелки | те же клавиши |
| F1..F5 | F1..F5 |

## Сборка

Ядро собирается Xilinx ISE 14.7 под Linux: `cd src && make` (все три платы по очереди) или
`make go`, `make mini`, `make minig`; `make minig-report` показывает занятость и тайминг последней
сборки. Модули плат — подмодуль `modules/`
([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)): клонируйте с
`git clone --recursive` или выполните `git submodule update --init`. Для упаковки `.kg` нужен
соседний репозиторий [karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) рядом с этим
(`make_core.py`).

Симуляция (verilator, VHDL через ghdl; регрессии мапперов картриджей, дисковода и кассеты) — в
`src/sim`. В `CLAUDE.md` устройство и правила проекта, в `docs/PLAN.md` план и решения, в
`docs/UPSTREAM.md` — что взято из исходного проекта и что изменено.

Прошивка платы — [karabas-go-firmware](https://github.com/andykarpov/karabas-go-firmware).

## Авторы и лицензия

- [MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer): molekula и участники MiSTer (машина,
  слоты и мапперы, дисковый интерфейс VY-0010 / WD1793, проигрыватель CAS).
- T80: Daniel Wallner, MikeJ, Sorgelig и другие. vdp18: Arnim Laeuger. jt49 и jt8255: Jose Tejada.
- [C-BIOS](http://cbios.sourceforge.net/): команда C-BIOS.
- Платы Karabas Go и порт: Andy Karpov.

Ядро распространяется под GNU GPL v3 (`LICENSE`). Его части сохраняют свои лицензии, совместимые с
ней: MSX1_MiSTer — GPL v2 или новее, jt49 — GPL v3, T80 и vdp18 — лицензии в стиле BSD, jt8255 — MIT,
C-BIOS — BSD из двух пунктов (`src/roms/LICENSE.cbios`; ROM C-BIOS встроены в файлы ядра). Disk ROM
VY-0010 (`src/rtl/msx/rom`) взят из MSX1_MiSTer.
