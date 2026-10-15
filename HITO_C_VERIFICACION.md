# HITO C — Cómo verificarlo en Godot y plantilla de resultados

> **Estado real: Hito C NO está verificado.** Quien escribió el código (Claude, en un entorno
> sin Godot y sin red) **no ha podido abrir el proyecto ni ejecutarlo**. Todo lo que hay abajo son
> instrucciones para que lo haga Summer/Godot y una plantilla para devolver los resultados.
> Nada de lo marcado `[ ]` está comprobado.

## 0. Cambio incluido desde el informe anterior: Leader Skill

Regla definitiva, implementada en `GameState.party_leader_id()` (constante `LEADER_SLOT = 0`):

- **Posición 1 ocupada → ese personaje es el líder.**
- **Posición 1 vacía → no hay Leader Skill**, aunque haya alguien en las posiciones 2, 3 o 4.
- Es una propiedad de la *posición*, no de un personaje: no hay ninguna rama "si el slot 1 está vacío usar el 2".
- Todo lo que depende del líder (`leader_report`, `leader_affects`, `leader_mods_for`, el combate) pasa por esa única función.

El arnés `DEBUG_V17` tiene ahora una sección `== LEADER SKILL ==` con 12 comprobaciones: líder = posición 1, su skill
activa, cambiar el personaje de la posición 1 cambia la skill, posición 1 vacía → sin líder / sin skill / sin bonus para
nadie, un personaje solo en la posición 2, 3 o 4 nunca es líder, y al volver a ocupar la posición 1 vuelve a haber líder.

## 1. Orden recomendado

### Paso 1 — Abrir y compilar (sin ejecutar pruebas)
```
godot --headless --path . --import
godot --headless --path . --quit-after 120 2>&1 | tee salida_arranque.txt
```
Buscar en `salida_arranque.txt`: `ERROR`, `SCRIPT ERROR`, `Parse Error`, `Identifier not found`, `DB:` (deben salir los
recuentos de personajes/enemigos/etc. y **ninguna** línea de error de DB). Comprobar en **Proyecto → Ajustes → Autoload** que
están, en este orden: `DB`, `GameState`, `GameSettings`, `GameAudio`.

### Paso 2 — Arnés automático (usa las funciones y handlers reales)
```
godot --headless --path . -- --dbg17 2>&1 | tee salida_dbg17.txt
```
(o `DEBUG_V17 := true` en `scenes/app.gd` y ejecutar con ventana). Cada línea acaba en `OK` o `FALLO`; el resultado también
queda en `res://dbg17_resultados.txt`. En modo `--headless` cierra solo con código de salida **0 = todo OK, 1 = hay FALLO**.
Guarda y restaura el guardado y los ajustes del jugador. Después, `DEBUG_V15` (ya existente, adaptado al equipo sin atajos).

### Paso 3 — Ajustes entre DOS ejecuciones reales (cerrar y abrir el juego)
```
godot --headless --path . -- --dbg17-write
godot --headless --path . -- --dbg17-read
```
La primera guarda música 30 %, efectos 60 %, combate rápida, números OFF y animaciones reducidas; la segunda, en un proceso
nuevo, comprueba que se cargaron y **restaura los ajustes que había**.

### Paso 4 — Manual, con ventana (lo que el arnés no puede juzgar)
1. **Equipo con huecos desde la interfaz**: 4/4 → 3/4 → 2/4 → 1/4 → 0/4, tocando cada personaje en su posición y con QUITAR. Debe verse `HUECO LIBRE`.
2. **Stage 3 desde la pantalla Equipo**: `[SAKUTA UR]` solo → permite; `[Sakuta+Mai SSR]` solo → bloquea; `[Sakuta UR + otro]` → bloquea; `[Sakuta UR]` solo otra vez → permite.
3. **Ajustes con ventana**: probar los sliders, velocidad y "Animaciones reducidas" (sin latido del botón JUGAR, sin fundido).
4. **Tamaño de texto GRANDE (×1,2)**: recorrer **todas** las pantallas y anotar cuáles se desbordan.
5. **Audio**: arrancar sin archivos (sin errores). Copiar cualquier `.ogg` como `audio/music/menu.ogg` y `audio/music/battle.ogg` → debe sonar sin tocar código; menú → combate cambia de pista; al terminar, `results` (o `menu` si no existe).
6. **Mutaciones**: elegir personaje, gastar 150, ver mutación, cerrar/abrir (persiste), tirar otra vez (sustituye), sin monedas (no cobra), y que aparezca en la **ficha**.
7. **Evento** "Síndromes de la pubertad": los 3 stages con Todo, Mahito+Todo y Akaza; comprobar que se pueden jugar y superar.
8. **Menú**: recorrer Menú → Colección → Equipo → Inventario → Mutaciones → Evolución → Eventos → Historia → Ajustes.

## 2. Plantilla de resultados (rellenar y devolver)

```
ERRORES DE COMPILACION (Paso 1):            [ninguno / lista]
ERRORES DE RUNTIME (Pasos 1-4):             [ninguno / lista]
AUTOLOADS EN ORDEN DB, GameState, GameSettings, GameAudio:   [SI/NO]
DB: recuentos correctos y sin load_errors:   [SI/NO]

DEBUG_V17 (Paso 2):        N OK / N FALLO   -> FALLOS: [lista de lineas "FALLO"]
DEBUG_V15 adaptado:        N OK / N FALLO
Ajustes entre 2 ejecuciones (Paso 3):        [OK / FALLO: ...]

LEADER SKILL
  posicion 1 ocupada -> lider:               [OK/FALLO]
  posicion 1 vacia -> sin Leader Skill:      [OK/FALLO]
  cambiar personaje de la posicion 1:        [OK/FALLO]
  slot 2/3/4 nunca es lider:                 [OK/FALLO]
EQUIPO CON HUECOS (interfaz): 4/4 3/4 2/4 1/4 0/4, quitar al repetir:   [OK/FALLO]
STAGE 3: UR solo permite / SSR solo bloquea / UR+otro bloquea:          [OK/FALLO]
AJUSTES: persistencia, velocidad rapida, numeros OFF, reducidas:        [OK/FALLO]
TEXTO GRANDE: pantallas que se desbordan:    [ninguna / lista]
AUDIO sin archivos sin errores / detecta menu.ogg y battle.ogg:         [OK/FALLO]
MUTACIONES: 150 monedas, guarda, sustituye, sin monedas, ficha:         [OK/FALLO]
EVENTO: Todo / Mahito / Akaza aparecen, stages superables:              [OK/FALLO]
MENU: 11 botones sin ninguno muerto:                                    [OK/FALLO]
```

## 3. Puerta de entrada al Hito D

**No empezar el Hito D hasta que la plantilla de arriba esté rellena sin FALLOS.** Cualquier fallo se corrige primero
(pásame la línea exacta de `dbg17_resultados.txt` o el error de la consola).

Orden acordado del Hito D, **una pantalla cada vez** (inspeccionar → rediseñar → ejecutar → comprobar → siguiente):
1. Selección de Stage · 2. Colección · 3. Equipo · 4. Eventos · 5. Inventario · 6. Misiones · 7. Evolución · 8. Invocar · 9. Historia/Mapa.
Se mantiene la arquitectura de rarezas SSR/UR/LR del Hito B y no se toca ningún PNG.
