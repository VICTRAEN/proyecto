# Audio (reemplazable)

## v9: banda sonora real colocada

Las 5 pistas de musica de pantalla ya son las del usuario (`.mp3`, ~3 min cada una):
`music/menu.mp3`, `battle.mp3`, `history.mp3`, `events.mp3` y `results.mp3`
(esta ultima viene de "Musica_RECOMPENSA.mp3"). Se retiraron los `.wav` provisionales de
esas 5 pistas, porque el orden de busqueda `.ogg > .wav > .mp3` hacia que ganaran al `.mp3`.
Tambien esta el tema del duo: `music/david_lucy_theme.ogg`. Los 20 efectos siguen siendo provisionales.
No esta escuchado por una persona en el entorno de pruebas: solo se verifica que carga y hace bucle.

## Estado actual

Los 25 sonidos del catalogo (`GameAudio.CATALOG`) tienen un archivo **provisional
propio** (`.wav`) generado por sintesis con `tools/gen_audio.py` (sin muestras de
terceros). No estan escuchados por una persona: son relleno funcional. Para
sustituir uno, deja un `.ogg`/`.wav`/`.mp3` con el mismo nombre en su carpeta
(`audio/ui`, `audio/combat`, `audio/progression`, `audio/music`); el orden de
busqueda es `.ogg`, `.wav`, `.mp3`, asi que un `.ogg` nuevo gana al `.wav`.
Para regenerar los provisionales: `python3 tools/gen_audio.py` y, despues,
`godot --headless --import`. Si borras un archivo, el juego sigue sin errores.

Musica por pantalla: menu (resto), history (Historia/mapa/stages), events
(Eventos/Torre), battle (combate). `results` suena al mostrarse el panel de resultados, tras el jingle de victoria/derrota.
Volumenes: ajustes `music_volume`, `sfx_volume` y `ui_volume`.

## A SUSTITUIR por la banda sonora definitiva (Suno u otra)

Todo lo de esta carpeta es PROVISIONAL (sonidos de prueba generados por codigo):
- **Musica (prioridad alta)**: `music/menu`, `music/battle`, `music/history`,
  `music/events`, `music/results`. Son bucles de chiptune de 10-23 s; hay que
  sustituirlos por pistas reales (`.ogg` en bucle).
- **Efectos**: los 20 archivos de `ui/`, `combat/` y `progression/` son tonos
  sencillos; funcionan pero suenan a prototipo. Los mas importantes para
  sustituir: `combat/attack`, `combat/special`, `combat/critical`,
  `progression/summon` y `progression/evolution`.
Se ha comprobado automaticamente que no recortan, no tienen DC y cierran el bucle,
pero NO se ha valorado su calidad de oido.

## Que hay que sustituir por la banda sonora definitiva (Suno u otra)

Todo lo de `audio/` es provisional y sintetizado (ondas cuadradas/triangulares y
ruido). Comprobado por analisis de senal (sin clipping, sonoridad pareja entre
-12.7 y -9.3 dB RMS, bucles que cierran), **no escuchado por una persona**.
- **Musica (5 pistas): sustituir TODAS**: `music/menu`, `music/battle`,
  `music/history`, `music/events`, `music/results` (son bucles de 10-23 s tipo
  chiptune; no son musica final).
- **Efectos clave: sustituir cuando haya definitivos**: `combat/attack`,
  `combat/special`, `combat/critical`, `combat/victory`, `combat/defeat`,
  `progression/summon`, `progression/evolution`, `progression/mutation`.
- Los clics de interfaz (`ui/*`) pueden valer como estan si suenan bien.

## Lo unico que tienes que hacer

1. Mira el nombre del sonido que quieres en la tabla de abajo.
2. Mete un `.ogg`, `.wav` o `.mp3` con **ese nombre exacto** en `res://audio/`.
3. Abre el juego.

**No hay que editar ningun script ni ningun JSON.** Si el archivo no existe, el
juego simplemente no suena: no hay error ni pantalla rota.

## Nombres de archivo

| Archivo | Cuando suena |
|---|---|
| `button.ogg` | Al pulsar **cualquier** boton del juego (se engancha solo) |
| `attack.ogg` | Golpe normal en combate |
| `crit.ogg` | Golpe critico |
| `heal.ogg` | Curacion |
| `victory.ogg` | Victoria |
| `defeat.ogg` | Derrota |
| `menu.ogg` | Musica de menus (en bucle) |
| `battle.ogg` | Musica de combate (en bucle) |

## Que funciona ya

- **El sonido de boton esta terminado**: en cuanto dejes `res://audio/button.ogg`,
  todos los botones del juego suenan, incluidos los que se crean en tiempo de
  ejecucion. No hay que tocar ninguna pantalla.
- **La musica esta lista para pedirla**: `GameAudio.play_music("menu")` y
  `GameAudio.play_music("battle")`. Pedir la misma dos veces no corta la cancion.

## Que falta por enganchar

Los efectos de combate (`attack`, `crit`, `heal`, `victory`, `defeat`) tienen el
archivo preparado, pero todavia no hay ninguna llamada que los dispare: cuando
quieras, se anaden en el punto donde el combate ya sabe que ha pasado (critico,
curacion, victoria). Es una linea por efecto.

## Formato recomendado

| Tipo | Formato | Nota |
|---|---|---|
| Efectos | `.ogg` o `.wav` | Cortos (menos de 1 segundo). El `.wav` es mas comodo para retocar. |
| Musica | `.ogg` | En bucle; el juego activa el loop solo. |

Los volumenes estan ajustados en `res://audio/audio.gd` (`SFX_VOLUME` y
`MUSIC_VOLUME`), por si un lote de sonidos sale mas alto o mas bajo que otro.
