# Osborne 1 MiSTer: progreso y pendientes

## Estado (21/11/2026)

El core original solo tenía CPU, ROM, RAM y el vídeo de texto: no había FDC, PIAs,
banco de memoria correcto ni interrupciones, por eso no pasaba de la pantalla inicial.
Se ha reescrito la máquina entera en `rtl/osborne1.sv`.

Comprobado en simulación (Verilator, `sim/`):
- ROM 1.44 llega a "Insert disk in Drive A and press RETURN"
- Arranca CP/M 2.2 desde disco de doble densidad (O1CPM) y de simple densidad (O1CPMS)
- HELP, ESC a CP/M, `DIR B:` con disco SD en B: y sistema DD en A:
- `STAT`, `SAVE` (escritura en la imagen) y scroll vertical por hardware

## Errores que había y arreglos

1. Faltaba todo el hardware de E/S: FDC, PIA de vídeo (scroll, DDEN, selección de
   unidad, zumbador), PIA IEEE, ACIA, teclado mal decodificado.
2. Banco de memoria: el modo ROM solo cubre 0000-3FFF (ROM 0000-1FFF, E/S 2000-3FFF),
   escrituras en ROM ignoradas, BIT 9 para la RAM de atributos, y los biestables
   UB4A/UB6A (M1 e INTA) que fuerzan modo ROM al atender una interrupción.
3. Interrupciones IM 2 con vector en el bus durante INTA (F0/F8/FC/FE).
4. Orden de filas del teclado: A0..A7 -> filas 0,1,3,4,5,2,6,7.
5. wd1793 de Sorgelig adaptado:
   - formato 10x256 (size_code 5)
   - `layout=1` para discos de una cara (con 0 la pista 1 leía la 2)
   - entrada `rnf`: Record Not Found si no hay disco o la densidad no coincide
   - SEEK actualiza el registro de pista; READ ADDRESS copia la pista al registro de sector
   - READ ADDRESS no comprueba el registro de sector
   - Force Interrupt con comando en curso conserva el formato de estado tipo II
     (la BIOS lo comprueba con AND 5Ch tras cada lectura multisector)

## Pendiente

- Probar en la placa (no se ha probado en hardware real)
- ACIA 6850 real conectada al UART de MiSTer
- Imágenes de doble cara / otros formatos (IBM 8x512, DEC 9x512, Xerox 18x128)
- SCREEN-PAC (104 columnas)
- Convertir TD0 directamente (ahora solo IMD; los TD0 del usuario tienen IMD equivalente)

## Compilación

- Quartus Prime Lite 17.0.2, MiSTer (5CSEBA6): 23 % ALMs, 1,15 Mbit de BRAM
- Todos los relojes cumplen tiempos (clk_sys 31,95 MHz: holgura setup +15,0 ns, hold +0,25 ns)
- RBF: `releases/Osborne_20261121.rbf`
