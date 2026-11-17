# Timex Sinclair 2068 for MiSTer

MiSTer core of the **Timex Sinclair 2068** (USA, 1983) and the **Timex Computer 2068**
(Portugal), based on the [ts2068](https://github.com/Kyp069/ts2068) core by **Kyp**.

MiSTer port: Shaeon (Carlos Palmero).

Documentation in Spanish: [README_es.md](README_es.md).

## Installation

- Copy the `.rbf` to `/media/fat/_Computer/`.
- No ROM files are needed: the TC2068 ROM (HOME 16K + EXROM 8K) and esxDOS come
  inside the core, as in Kyp's core.
- Optional: put cartridges (`.dck`), tapes (`.tzx`, `.tap`, `.pzx`) and a
  `boot.vhd` for the DivMMC in `/media/fat/games/TS2068/`.

## OSD

| Option | |
|---|---|
| Load cartridge | `.dck` file (Warajevo format). The machine resets and starts the cartridge |
| Load tape | TZX, TAP or PZX. Kept in the DDR3, so there is no size limit |
| Mount SD (DivMMC) | VHD image for the DivMMC (esxDOS). Enable *DivMMC* too |
| Load ROM | Replaces the ROM: the first 16K go to HOME; with a 24K file (`ts2068.rom`) the next 8K go to the EXROM. `boot.rom` in the games folder is loaded the same way at startup |
| Model | TC2068 (PAL, 56.000 MHz, 312 lines) or TS2068 (NTSC, 56.488 MHz, 262 lines) |
| DivMMC | Off / On (as in Kyp's core) |
| Video | Aspect ratio, scandoubler/HQ2x/scanlines, integer scaling |
| Audio & Input | Tape sound, stereo mix of the AY (ABC stereo, as in Kyp's core), swap joysticks |
| Tape play / stop | Same as PgUp / PgDn |
| Remove cartridge | Takes the cartridge out and resets |
| NMI | Same as F5 (esxDOS menu with the DivMMC) |

Details of the tape player (formats, DDR3 address, timing): [docs/cinta.md](docs/cinta.md) (Spanish).

## Keys

- **F5**: NMI · **F9**: reset.
- **PgUp / PgDn**: tape play / stop.
- Esc = BREAK, Backspace = DELETE, cursor keys = CAPS SHIFT + 5/6/7/8; the
  rest follows `matrix.v` in Kyp's core.
- Joysticks: the TS2068 joystick ports (AY register 14, joysticks 1 and 2) and
  Kempston (port 0x1F, joystick 1).
- Tape from a real recorder: audio input of the I/O board (ADC).

## What it adds to Kyp's core

| Feature | Detail |
|---|---|
| PAL / NTSC | The PLL is reconfigured on the fly (56.000 / 56.488 MHz), instead of two PLLs and a clock multiplexer as in `psd.v` |
| Video | 512-pixel mode with the MiSTer scaler, scandoubler, HQ2x, scanlines, integer scaling |
| Tape | TZX, TAP and PZX in the DDR3; generalized data blocks (0x19), loops; play/stop from the OSD; real-time speed in NTSC too |
| Cartridges | The DCK header is decoded: DOCK, EXROM and HOME banks, AROS cartridges (chunks 4-7) and RAM chunks writable by the CPU |
| ROM | Optional, 16K or 24K (HOME + EXROM) |

## How it works

- **Kyp's core is a git submodule and is not modified** (`rtl/ts2068`). Only
  the modules in `core/` are used; `mist.v`, `i2s.v`, `scandoubler.v`,
  `tzx.v`/`tzxplayer.vhd` and the `psd/`, `npp/` and `mist/` folders belong to
  the Poseidon / Neptuno+ / MiST versions. `TS2068.sv` plays the role of
  `psd.v`.
- **Memory**: everything is in BRAM, the SDRAM is not used. HOME 64K (ROM +
  48K RAM, dual port for the video), EXROM 8K, DOCK 64K, DivMMC 128K RAM + 8K
  esxDOS. The ROM images are Kyp's `.mif` files from the submodule.
- **PAL/NTSC**: `rtl/pll_timing.sv` rewrites the fractional K of the PLL through
  `pll_cfg` (as the C64 core does) and holds the core in reset until the PLL
  locks again.
- **Cartridges**: `rtl/dck_loader.sv`. hps_io does not send the file size, so
  instead of deciding from the size whether there is a header (as `psd.v`
  does), the 9-byte header is decoded while the file arrives, and each data
  byte goes to its bank and chunk. Headerless images are not supported.
- **Blanking**: `vdu.v` does not export it, so its counters are rebuilt at
  14 MHz (896 pixels per line) from hsync/vsync.
- **Tape**: `rtl/tape_ddr.sv`, `rtl/tzxplayer.vhd` and `rtl/pzx_player.v` from
  [ZXP3_MiSTer](https://github.com/shaeon/ZXP3_MiSTer) and
  [Lynx_MiSTer](https://github.com/shaeon/Lynx_MiSTer).

## Building

```
git clone --recursive https://github.com/shaeon/TS2068_MiSTer.git
```

(`--recursive` is needed: Kyp's core brings the T80 as a nested submodule.)
Open `TS2068.qpf` with Quartus 17.0 and compile, or run `build.bat`, which
leaves the RBF in `releases/`.

GitHub Actions (`.github/workflows/build.yml`) compiles the core on every push
with Quartus 17.0 (`raetro/quartus:17.0` Docker image) and keeps the `.rbf` and
the reports as an artifact in the *Actions* tab. Pushing a `v*` tag also
creates a Release with the `.rbf`.

To update Kyp's core: `git -C rtl/ts2068 pull` and commit the new submodule
pointer.

## Credits and thanks

- **Kyp** (Kyp069): the TS2068 core this port is built on.
- T80 (Daniel Wallner, MikeJ and others), tzxplayer (György Szombathelyi),
  esxDOS, and the MiSTer framework (MiSTer-devel, Sorgelig).
- The people who documented the TS2068 and the DCK format (Warajevo, Fuse,
  the Timex Computer World and timexsinclair.com archives).

## Licence

GPL v3, like Kyp's core (the `sys/` framework is GPL v2 or later). The ROMs
are the property of their authors.

---

Developed with the help of Claude (Anthropic).
