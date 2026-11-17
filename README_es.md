# Timex Sinclair 2068 para MiSTer

Core de MiSTer del **Timex Sinclair 2068** (EE. UU., 1983) y el **Timex Computer 2068**
(Portugal), a partir del core [ts2068](https://github.com/Kyp069/ts2068) de **Kyp**.

Port a MiSTer: Shaeon (Carlos Palmero).

## Instalación

- Copia el `.rbf` a `/media/fat/_Computer/`.
- No hace falta ninguna ROM: la del TC2068 (HOME 16K + EXROM 8K) y la de esxDOS
  van dentro del core, como en el core de Kyp.
- Opcional: cartuchos (`.dck`), cintas (`.tzx`, `.tap`, `.pzx`) y un `boot.vhd`
  para la DivMMC en `/media/fat/games/TS2068/`.

## OSD

| Opción | |
|---|---|
| Load cartridge | Fichero `.dck` (formato de Warajevo). La máquina se reinicia y arranca el cartucho |
| Load tape | TZX, TAP o PZX. Se guarda en la DDR3, sin límite práctico de tamaño |
| Mount SD (DivMMC) | Imagen VHD para la DivMMC (esxDOS). Hay que activar también *DivMMC* |
| Load ROM | Cambia la ROM: los primeros 16K van a HOME y, con un fichero de 24K (`ts2068.rom`), los 8K siguientes a la EXROM. Un `boot.rom` en la carpeta de juegos se carga igual al arrancar |
| Model | TC2068 (PAL, 56,000 MHz, 312 líneas) o TS2068 (NTSC, 56,488 MHz, 262 líneas) |
| DivMMC | Off / On (como en el core de Kyp) |
| Video | Aspect ratio, scandoubler/HQ2x/scanlines, escalado entero |
| Audio & Input | Sonido de la cinta, mezcla estéreo del AY (estéreo ABC, como en el core de Kyp), intercambiar mandos |
| Tape play / stop | Igual que RePág / AvPág |
| Remove cartridge | Quita el cartucho y reinicia |
| NMI | Igual que F5 (menú de esxDOS con la DivMMC) |

Detalles del reproductor de cinta (formatos, dirección en la DDR3, temporización): [docs/cinta.md](docs/cinta.md).

## Teclas

- **F5**: NMI · **F9**: reset.
- **RePág / AvPág**: play / stop de la cinta.
- Esc = BREAK, Retroceso = DELETE, cursores = CAPS SHIFT + 5/6/7/8; el resto
  según `matrix.v` del core de Kyp.
- Mandos: los puertos de joystick del TS2068 (registro 14 del AY, mandos 1 y 2)
  y Kempston (puerto 0x1F, mando 1).
- Cinta desde un casete real: entrada de audio de la placa I/O (ADC).

## Qué añade respecto al core de Kyp

| Función | Detalle |
|---|---|
| PAL / NTSC | La PLL se reconfigura en caliente (56,000 / 56,488 MHz), en vez de dos PLL y un multiplexor de reloj como en `psd.v` |
| Vídeo | Modo de 512 píxeles con el escalador de MiSTer, scandoubler, HQ2x, scanlines, escalado entero |
| Cinta | TZX, TAP y PZX en la DDR3; bloques de datos generalizados (0x19), bucles; play/stop desde el OSD; velocidad real también en NTSC |
| Cartuchos | Se interpreta la cabecera del DCK: bancos DOCK, EXROM y HOME, cartuchos AROS (trozos 4-7) y trozos de RAM que la CPU puede escribir |
| ROM | Opcional, de 16K o 24K (HOME + EXROM) |

## Cómo funciona

- **El core de Kyp es un submódulo de git y no se modifica** (`rtl/ts2068`).
  Solo se usan los módulos de `core/`; `mist.v`, `i2s.v`, `scandoubler.v`,
  `tzx.v`/`tzxplayer.vhd` y las carpetas `psd/`, `npp/` y `mist/` son de las
  versiones de Poseidon / Neptuno+ / MiST. `TS2068.sv` hace el papel de `psd.v`.
- **Memoria**: todo en BRAM, no se usa la SDRAM. HOME 64K (ROM + 48K de RAM, de
  doble puerto para el vídeo), EXROM 8K, DOCK 64K, DivMMC 128K de RAM + 8K de
  esxDOS. Las ROM son los `.mif` de Kyp del submódulo.
- **PAL/NTSC**: `rtl/pll_timing.sv` reescribe la K fraccional de la PLL con
  `pll_cfg` (como el core C64) y mantiene el core en reset hasta que la PLL
  vuelve a enganchar.
- **Cartuchos**: `rtl/dck_loader.sv`. hps_io no da el tamaño del fichero, así
  que en vez de decidir por el tamaño si hay cabecera (como `psd.v`) se
  interpreta la cabecera de 9 bytes conforme llega el fichero y cada byte de
  datos va a su banco y su trozo. No admite imágenes sin cabecera.
- **Blanking**: `vdu.v` no lo exporta, así que se reconstruyen sus contadores a
  14 MHz (896 píxeles por línea) a partir de hsync/vsync.
- **Cinta**: `rtl/tape_ddr.sv`, `rtl/tzxplayer.vhd` y `rtl/pzx_player.v` de
  [ZXP3_MiSTer](https://github.com/shaeon/ZXP3_MiSTer) y
  [Lynx_MiSTer](https://github.com/shaeon/Lynx_MiSTer).

## Compilar

```
git clone --recursive https://github.com/shaeon/TS2068_MiSTer.git
```

(`--recursive` hace falta: el core de Kyp trae el T80 como submódulo anidado.)
Abre `TS2068.qpf` con Quartus 17.0 y compila, o ejecuta `build.bat`, que deja el
RBF en `releases/`.

GitHub Actions (`.github/workflows/build.yml`) compila el core en cada push con
Quartus 17.0 (imagen Docker `raetro/quartus:17.0`) y deja el `.rbf` y los
informes como artefacto en la pestaña *Actions*. Una etiqueta `v*` crea además
una Release con el `.rbf`.

Para actualizar el core de Kyp: `git -C rtl/ts2068 pull` y hacer commit del
nuevo puntero del submódulo.

## Créditos y agradecimientos

- **Kyp** (Kyp069): el core del TS2068 en el que se basa este port.
- T80 (Daniel Wallner, MikeJ y otros), tzxplayer (György Szombathelyi),
  esxDOS y el marco de MiSTer (MiSTer-devel, Sorgelig).
- Quienes documentaron el TS2068 y el formato DCK (Warajevo, Fuse y los
  archivos de Timex Computer World y timexsinclair.com).

## Licencia

GPL v3, como el core de Kyp (el marco `sys/` es GPL v2 o posterior). Las ROM son
propiedad de sus autores.

---

Desarrollado con la ayuda de Claude (Anthropic).
