# Osborne 1 para MiSTer

*[Read in English](README.md)*

Implementación en FPGA del **Osborne 1** (1981), el primer ordenador portátil
de éxito comercial, para la plataforma **MiSTer**. Ejecuta la ROM original de
la BIOS 1.44 y arranca CP/M 2.2 desde imágenes de disco de simple y doble
densidad.

## Origen

Este repositorio es un fork de
[jackpot51/Osborne_MiSTer](https://github.com/jackpot51/Osborne_MiSTer), de
Jeremy Soller, que empezó el proyecto: CPU, ROMs y el vídeo de texto. Aquel core
no pasaba de la pantalla inicial porque le faltaba casi todo el hardware:

- No había controlador de disquete, ni PIAs, ni ACIA.
- El cambio de banco de memoria no era el de la placa real.
- No había interrupciones (la BIOS trabaja en IM 2).
- El teclado no estaba decodificado.

La máquina se ha reescrito siguiendo el *Osborne 1 Technical Manual* y el driver
`osborne1` de MAME, comprobando cada paso contra el desensamblado de la ROM 1.44.

## Características

- **CPU**: Z80 a 3,9936 MHz (T80) con clock enables desde un reloj de sistema
  de 31,95 MHz (2 x 15,9744 MHz, la frecuencia maestra del Osborne).
- **Memoria**: 64 KB de RAM, ROM de BIOS 1.44, generador de caracteres
  7A3007-00 y RAM de atributos de 4K x 1 bit.
- **Cambio de banco** como en la placa:
  - Modo ROM: 0000-1FFF BIOS (4 KB espejada), 2000-3FFF periféricos;
    las escrituras en la zona de ROM se ignoran.
  - Modo RAM: 64 KB de RAM.
  - E/S: `OUT 0` modo ROM, `OUT 1` modo RAM, `OUT 2`/`OUT 3` activan y
    desactivan BIT 9 (F000-FFFF pasa a la RAM de atributos, bit D7).
  - Los biestables UB4A/UB6A, actualizados en cada ciclo M1 y en el
    reconocimiento de interrupción, fuerzan el modo ROM al atender una
    interrupción y al pulsar RESET en el frontal (NMI).
- **Interrupciones** en IM 2 con los vectores originales: PIA IEEE F0h, PIA de
  vídeo F8h, ACIA FCh.
- **Periféricos** con la decodificación parcial original (cada uno mira solo
  dos líneas de dirección y, si coinciden varios, el bus es el AND de todos):
  - 2100 controlador de disquete
  - 2200 teclado (A0-A7 seleccionan filas)
  - 2900 PIA IEEE-488
  - 2A00 ACIA
  - 2C00 PIA de vídeo
- **Vídeo**: ventana de 52 x 24 caracteres de 8 x 10 sobre la pantalla virtual
  de 128 x 32, con scroll horizontal (PIA puerto A) y vertical (PIA puerto B)
  por hardware, media intensidad (bit de atributo), subrayado (bit 7 del
  carácter) y gráficos de bloque. Temporización de 512 x 260 píxeles a
  7,9872 MHz: 15,6 kHz / 60 Hz. Fósforo verde, ámbar o blanco y efectos del
  scandoubler.
- **PIAs MC6821**: implementación propia con registros de dirección, flancos
  configurables de CA1/CB1/CA2/CB2 e interrupciones. El borrado vertical entra
  por CA1 de la PIA de vídeo y genera la interrupción de 60 Hz que usa la BIOS.
- **Disquete**: WD1793/MB8877 con dos unidades, lectura y escritura.
  - Simple densidad: 40 pistas x 10 sectores x 256 bytes (102400 bytes).
  - Doble densidad: 40 pistas x 5 sectores x 1024 bytes (204800 bytes).
  - La densidad de cada imagen se deduce de su tamaño. Si la línea DDEN de la
    PIA no coincide con la del disco, el controlador devuelve *Record Not
    Found*, y así la BIOS detecta la densidad sola, como en la máquina real.
    Se puede tener un disco de doble densidad en A: y uno de simple en B:.
  - Selección de unidad por los bits 6 y 7 del puerto B de la PIA de vídeo.
- **Teclado**: matriz de 8 x 8 desde PS/2.
- **Sonido**: el zumbador, activado por el bit 5 del puerto B y modulado por el
  contador de líneas (4 de cada 10), como el original.

No implementado: puerto serie (la ACIA siempre indica transmisor libre),
dispositivos IEEE-488, SCREEN-PAC y placas de 80 columnas.

## Uso

1. Copia `releases/Osborne_AAAAMMDD.rbf` a `_Computer/` en la SD.
2. Copia las imágenes de disco a `games/Osborne`.
3. Monta un disco de sistema CP/M como Drive A: desde el OSD y pulsa **Intro**
   cuando aparezca *Insert disk in Drive A and press RETURN*.

### Imágenes de disco

El core usa imágenes raw ordenadas por pista y sector (empezando por el
sector 1), con extensión `.IMG` o `.DSK`. Las imágenes ImageDisk (`.IMD`) se
convierten con la herramienta incluida:

```
python3 tools/imd2img.py OS1SYSD.IMD OS1SYSD.IMG
```

La herramienta indica la geometría de cada disco y avisa si falta algún sector.
Muchos ficheros `.DSK` de Osborne que circulan por Internet son en realidad
IMD: si empiezan por `IMD 1.1x`, hay que convertirlos igual. Los ficheros
Teledisk (`.TD0`) se pueden pasar antes a IMD con las herramientas de
ImageDisk.

### Teclado

Las teclas siguen el símbolo en un teclado de distribución estadounidense.

| PC | Osborne |
|----|---------|
| Retroceso, Supr | cursor izquierda (como en MAME) |
| Cursores | cursores |
| `[` | `[` |
| `]` | `]` (la tecla `[` con SHIFT) |
| Bloq Mayús | ALPHA LOCK |
| Teclado numérico | números, `.` e Intro |
| **F10** | botón RESET del frontal |

## Cómo funciona

**CPU y memoria.** El T80 funciona con un clock enable cada 8 ciclos del reloj
de sistema. La RAM es un bloque de 64 KB en BRAM con un segundo puerto de solo
lectura para el vídeo. El mapa de memoria se resuelve con el estado de los
biestables de banco; estos se actualizan al principio de cada ciclo M1 o INTA,
antes de que la CPU lea el bus, igual que en la placa real.

**Interrupciones.** Durante el ciclo INTA el core pone en el bus el vector de
la fuente con más prioridad. La rutina de interrupción de la BIOS está en ROM,
y el hardware fuerza el modo ROM en la primera instrucción tras la
interrupción.

**Vídeo.** Por cada celda se lee el carácter y el atributo un carácter por
adelantado, luego la ROM de caracteres, y se carga un registro de
desplazamiento. La dirección de la fila se calcula con el scroll vertical
leído al principio de cada cuadro; la columna, con el scroll horizontal más
11, como hace el hardware.

**Disquete.** El controlador parte del `wd1793` de Sorgelig, adaptado:

- formato de 10 sectores de 256 bytes;
- disposición lineal para discos de una cara;
- entrada de *Record Not Found* para disco ausente o densidad distinta;
- SEEK actualiza el registro de pista y READ ADDRESS copia la pista al
  registro de sector, como el chip real (la BIOS usa las dos cosas);
- READ ADDRESS no comprueba el registro de sector;
- *Force Interrupt* durante un comando conserva el formato de estado tipo II,
  porque la BIOS lo comprueba tras cada lectura multisector.

Hay una instancia por unidad, conectadas a dos imágenes del OSD.

## Pruebas

En `sim/` hay un banco de pruebas de Verilator que ejecuta la máquina completa
con imágenes de disco reales: escribe teclas a tiempos dados, vuelca el texto
de la pantalla y guarda un cuadro de vídeo (`frame.pgm`). El T80 se pasa a
Verilog con GHDL.

```
cd sim && ./build.sh
./obj/vsim -a sistema.img -b utilidades.img -t 10 -k 1.0 $'\n' -k 5.0 $'\x1b' -k 6.5 $'DIR B:\n'
```

Opciones: `-a`/`-b` imágenes, `-t` segundos simulados, `-k tiempo texto`
pulsaciones, `-v 1` traza del controlador de disco.

Comprobado en simulación:

- La ROM 1.44 llega a la pantalla de inicio.
- Arranque de CP/M 2.2 desde disco de doble densidad y de simple densidad.
- `DIR B:` con un disco de simple densidad en B: y el sistema de doble en A:.
- `STAT`, `SAVE` (escritura en la imagen) y scroll vertical por hardware.

Las notas de desarrollo y lo pendiente están en `docs/PROGRESO.md`.

## Compilación

Abre `Osborne.qpf` en Quartus Prime Lite 17.0 y compila. Resultado con 17.0.2:
23 % de ALMs, 1,15 Mbit de BRAM y todos los relojes dentro de tiempos.

## Créditos

**Código usado en el core**

- **Jeremy Soller (jackpot51)**: proyecto Osborne_MiSTer original.
- **T80**, núcleo Z80: Daniel Wallner, con arreglos de Sorgelig y la comunidad
  MiSTer. Licencia tipo BSD.
- **wd1793**: Viacheslav Slavinsky y Sorgelig, adaptado aquí a los formatos
  del Osborne. GPL.
- **Framework de MiSTer** (`sys/`): Sorgelig y la comunidad MiSTer-devel.

**Referencias**

- Driver `osborne1` de **MAME** (Wilbert Pol, Vas Crabb y el equipo de MAME):
  la referencia principal del hardware.
- *Osborne 1 Technical Manual*.

## Agradecimientos

Al **Retro-Wiki FPGA-dev Team**, en especial a **Ron, Manuel (teiram), Somhi,
Roderick, Rampa, Kyp y Benito**, por su ayuda y su paciencia.

## Asistencia de IA y recursos

Partes de este core se desarrollaron con la ayuda de Claude (Anthropic), usado
para código, simulación y documentación. El acceso a Claude lo proporcionó
Advanced Computer Trading, S.L. (actsl.com), que además autoriza la
publicación de este trabajo bajo la licencia indicada abajo. Todas las
decisiones de diseño, la integración, las pruebas en hardware real y la
revisión final las hizo el autor, Shaeon (Carlos Palmero).

## Licencia

Copyright (C) 2024 Jeremy Soller, (C) 2026 Shaeon (Carlos Palmero).

Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo
los términos de la **Licencia Pública General de GNU** publicada por la Free
Software Foundation, ya sea la **versión 3** de la licencia o (a tu elección)
cualquier versión posterior. Ver [LICENSE](LICENSE).

El repositorio original traía el texto de la GPL v2 de la plantilla de MiSTer,
pero varios módulos del framework de MiSTer que ya incluía (`hps_io`,
`sd_card`, `scandoubler`, `ddr_svc`) son GPL v3 o posterior, así que el
conjunto tiene que ser GPL v3. Los ficheros de terceros conservan sus propios
avisos de copyright y licencias.

## Exención de responsabilidad

Este proyecto se entrega **"tal cual", sin garantía de ningún tipo**, ni
expresa ni implícita, incluidas, entre otras, las garantías de
comerciabilidad y de idoneidad para un fin concreto. En ningún caso los
autores o colaboradores serán responsables de ninguna reclamación, daño u otra
responsabilidad derivada del uso de este software, del hardware en el que se
ejecuta o de cualquier equipo conectado. Úsalo bajo tu propia responsabilidad.

Osborne es una marca de sus respectivos propietarios. Este proyecto no está
afiliado a ellos ni cuenta con su respaldo.
