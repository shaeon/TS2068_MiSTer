# TS2068_MiSTer — Carga de cintas (TZX / TAP / PZX)

Documento técnico de cómo funciona la cinta en el core **TS2068_MiSTer** (port del core
[ts2068](https://github.com/Kyp069/ts2068) de Kyp).

---

## 1. Resumen

- **La cinta no se copia en la memoria del TS2068.** El fichero se guarda entero en la
  **DDR3 de la placa DE10-Nano** (la memoria del ARM/HPS), a partir de la dirección física
  **`0x3000_0000`**.
- Desde ahí, `tzxplayer` (o `pzx_player` para PZX) lo **reproduce como si fuera un casete**:
  genera la señal de audio EAR en tiempo real.
- El Z80 lee esa señal por el **bit 6 del puerto `0xFE`**, igual que en la máquina real. Es la
  **rutina de carga de la ROM** del TS2068 (o el cargador del juego) la que decide en qué
  dirección de RAM se guardan los datos. Esa dirección viene en la cabecera de cada bloque de la
  cinta, no la decide el core.

```
 SD de MiSTer ──hps_io──► DDR3 (0x30000000 + offset) ──► tzxplayer / pzx_player
                                                               │ señal EAR
                                                               ▼
                    RAM del TS2068 ◄── rutina LOAD de la ROM ◄── puerto 0xFE, bit 6
```

---

## 2. Cómo cargar una cinta

1. Copia los ficheros a `/media/fat/games/TS2068/`.
2. Abre el OSD (F12) y elige **Load tape**. Admite `.tzx`, `.tap` y `.pzx`.
3. En el TS2068, escribe `LOAD ""` y pulsa Enter:
   - `LOAD` = tecla **J** (en modo K, como en el Spectrum).
   - `"` = **Symbol Shift + P**. En el teclado PS/2, Symbol Shift es la tecla **Ctrl**
     (código `0x14` en `matrix.v` de Kyp).
4. Pon la cinta en marcha con **RePág (PgUp)** o con **Tape play** en el OSD.
5. Para pararla: **AvPág (PgDn)** o **Tape stop** en el OSD.

Opciones relacionadas en el OSD:

| Opción | Efecto |
|---|---|
| `Audio & Input → Tape sound` | Mezcla el sonido de la cinta con el audio del core |
| `Tape play` / `Tape stop` | Igual que RePág / AvPág |

El LED de usuario de la placa se enciende mientras la cinta se reproduce.

Al cargar otra cinta desde el OSD, la anterior se para y la nueva sustituye a la anterior en la DDR3.
La cinta **no arranca sola**: hay que darle a play.

---

## 3. Dónde se guarda: la DDR3

Módulo: `rtl/tape_ddr.sv` (el mismo que en ZXP3_MiSTer).

### 3.1 Dirección

```verilog
assign DDRAM_ADDR = { 4'b0011, ramA };   // ramA = dirección del byte [27:3]
```

- `DDRAM_ADDR` cuenta **palabras de 64 bits** (29 bits en total).
- Los 4 bits altos `0011` sitúan la zona en la dirección de byte física **`0x3000_0000`**.
  Es la zona de la DDR3 que el Linux de MiSTer deja reservada para los cores.
- Un byte que está en la posición `offset` del fichero queda en:

| | Valor |
|---|---|
| Dirección física del byte | `0x3000_0000 + offset` |
| Palabra DDR (`DDRAM_ADDR`) | `0x0600_0000 + (offset >> 3)` |
| Byte dentro de la palabra | `offset & 7` (con `DDRAM_BE = 1 << (offset & 7)`) |

- **Tamaño máximo**: `ioctl_addr` tiene 27 bits, así que el máximo son **128 MB**. Ninguna cinta se
  acerca a eso.

### 3.2 Escritura (al cargar desde el OSD)

- `hps_io` manda el fichero byte a byte (`ioctl_index = 2`, el `F2` del CONF_STR).
- Cada byte se escribe en la DDR3 con su *byte enable*. Mientras la escritura no termina se
  activa `ioctl_wait`, así que el HPS espera y no se pierde ningún byte.
- Se guarda el tamaño (`size = último ioctl_addr + 1`) para saber dónde termina la cinta.
- Mientras se carga el fichero la cinta se para (`motor = 0`).

### 3.3 Lectura (al reproducir)

- Hay una **caché de una palabra de 64 bits** (8 bytes): cuando el reproductor pide un byte que no
  está en la caché, se lee esa palabra de la DDR3.
- `tzxplayer` pide los bytes con un protocolo `req/ack`, así que puede esperar todo lo que haga
  falta y la latencia de la DDR3 no afecta a la temporización de la señal.

---

## 4. Formatos

El formato se detecta por el contenido del fichero, no por su extensión:

| Formato | Cómo se detecta | Quién lo reproduce |
|---|---|---|
| **TZX** | Los 8 primeros bytes son `ZXTape!` + `0x1A` | `tzxplayer.vhd` |
| **PZX** | Los 4 primeros bytes son `PZXT` | `pzx_player.v` |
| **TAP** | Cualquier otro caso | `tzxplayer.vhd`, con un TZX equivalente generado **al vuelo** |

### TAP → TZX al vuelo

El fichero TAP no se convierte en la DDR3: `tape_ddr.sv` va dando a `tzxplayer` los bytes de un
TZX que no existe en memoria:

1. Primero la cabecera TZX: `ZXTape!`, `0x1A` y la versión 1.20.
2. Por cada bloque del TAP, un bloque **`0x10` (Standard Speed Data)** con **1000 ms de pausa**
   (`0xE8 0x03`), seguido de la longitud y los datos tal como están en el TAP.

### Bloques TZX

`tzxplayer.vhd` es la versión mejorada de ZXP3_MiSTer / Lynx_MiSTer. Además de los bloques de
datos estándar, turbo, tonos, pulsos y pausas, reproduce:

- **`0x19`**: bloques de datos generalizados.
- **`0x24` / `0x25`**: inicio y fin de bucle. Se guarda la posición del inicio y se vuelve a ella.
- **`0x2A`** (*Stop the tape if in 48K mode*): **para la cinta** (`stop48 = 1`, como el `tzx.v` de
  Kyp). El TS2068 se comporta como una máquina de 48K.
- **Fin de cinta**: el motor se para al llegar a `size`.

---

## 5. Temporización

| Elemento | Valor |
|---|---|
| Reloj del core | 56,000 MHz (PAL, TC2068) / 56,488 MHz (NTSC, TS2068) |
| `tzxplayer` | `TZX_MS = 56000` ciclos de `ce` por milisegundo |
| `ce` de la cinta en PAL | Siempre activo → 56000 ciclos/ms, exacto |
| `ce` de la cinta en NTSC | Un acumulador quita 488 de cada 56488 ciclos → 56000/ms, exacto |
| `pzx_player` | `TS = 16` ciclos de reloj por T-estado (3,5 MHz en PAL) |

- **TZX y TAP** van a velocidad real en los dos modelos. Kyp usa 56000 en los dos relojes, así que
  en su versión NTSC la cinta va un 0,87 % más rápida.
- **PZX** no usa `ce`: en NTSC va un **0,87 % más rápido** (16 ciclos de 56,488 MHz por
  T-estado = 3,53 MHz). Los cargadores toleran esa diferencia de sobra.

---

## 6. Señal EAR

En `TS2068.sv`:

```verilog
wire ear = tzxBusy ? tzxTape : tapeAdcActS && !tapeAdcS;
```

- Si la cinta virtual está en marcha, manda ella.
- Si no, se usa la **entrada de audio de la placa I/O** (ADC `ltc2308_tape`) para cargar desde un
  casete real o un móvil. Las dos señales pasan por dos registros de sincronización con el reloj
  del core.

En `ts.v` de Kyp, el puerto `0xFE` (decodificación completa de `A7..A0`) devuelve:

```
bit 7   6    5   4..0
    1   EAR  1   columnas del teclado
```

---

## 7. Dónde acaban los datos en la RAM del TS2068

Lo decide la cinta, no el core:

| Bloque de la cinta | Destino en la RAM |
|---|---|
| `Program:` (BASIC) | Zona de programa, a partir de la variable del sistema `PROG` |
| `Bytes:` / `CODE` | La dirección de inicio que viene en la cabecera, o la de `LOAD "" CODE dir` |
| `SCREEN$` | `0x4000` (pantalla) |
| Cargadores turbo | Donde decida el propio cargador |

Mapa de memoria del core (BRAM de la FPGA, `TS2068.sv`):

| Rango | Contenido (banco HOME) |
|---|---|
| `0x0000–0x3FFF` | ROM HOME 16K (`tc2068-0`) |
| `0x4000–0x5FFF` | RAM, pantalla 1 |
| `0x6000–0x7FFF` | RAM, pantalla 2 (modos de doble pantalla y de 512 píxeles) |
| `0x8000–0xFFFF` | RAM |

- Los trozos de 8K se pueden cambiar al banco **DOCK** (cartucho) o al banco **EXROM** con el
  puerto `0xF4` (un bit por trozo). El bit 7 del puerto `0xFF` elige DOCK o EXROM. Esto es igual
  que en el hardware real y en el core de Kyp.
- La RAM HOME es de doble puerto: el segundo puerto lo usa el vídeo para leer `0x4000–0x7FFF`.

---

## 8. Compatibilidad

- El formato de cinta del TS2068 es el mismo que el del ZX Spectrum, así que las cintas de
  Spectrum **cargan**.
- Muchos programas de Spectrum **no funcionan** después de cargar, porque la ROM del TS2068 es
  distinta (otras direcciones de rutinas y de variables del sistema). Es un problema de la máquina
  real, no del core.
- Para esos programas se puede probar a cargar la ROM del Spectrum 48K (`rom/48.rom` del repo de
  Kyp) con **Load ROM**. Sustituye a la ROM HOME, como hacía el cartucho emulador de Spectrum de la
  época. **Sin probar en el core.**

---

## 9. Diferencias con la versión de Kyp (Poseidon / Neptuno+)

| | `tzx.v` de Kyp | `tape_ddr.sv` (MiSTer) |
|---|---|---|
| Memoria | 256 KB de BRAM | DDR3, hasta 128 MB |
| Formatos | TZX | TZX, TAP y PZX |
| Bucles `0x24/0x25` | No | Sí |
| Bloque `0x19` | No | Sí |
| Velocidad en NTSC | +0,87 % | Exacta (TZX/TAP) |
| Play / stop | RePág / AvPág | RePág / AvPág y el OSD |
| Casete real | Entrada `tape` | ADC de la placa I/O |

El TZX no cabe en BRAM en MiSTer: la BRAM ya está ocupada por HOME, EXROM, DOCK, la DivMMC y el
marco de MiSTer (65 % de los bloques en uso).

---

## 10. Ficheros implicados

| Fichero | Función |
|---|---|
| `TS2068.sv` | CONF_STR (`F2,TZXTAPPZX,Load tape`), `ce` de la cinta en NTSC, señal EAR, ADC |
| `rtl/tape_ddr.sv` | Escritura y lectura en la DDR3, detección del formato, TAP→TZX, bucles |
| `rtl/tzxplayer.vhd` | Reproductor TZX (genera los pulsos) |
| `rtl/pzx_player.v` | Reproductor PZX |
| `rtl/ts2068/core/ts.v` | Puerto `0xFE` (bit 6 = EAR), de Kyp |
| `rtl/ts2068/core/matrix.v` | RePág / AvPág → play / stop, de Kyp |
