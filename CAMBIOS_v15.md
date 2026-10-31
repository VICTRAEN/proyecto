# CAMBIOS v15 - colecciones con recompensas, misiones personales, nivel de cuenta, audio, calidad de vida y diagnostico

## Nuevo
1. **Colecciones con recompensas** (`core/collections.gd`, `data/collections/`, 28 colecciones:
   12 series, 13 categorias, 2 rarezas, 1 evento). Tramos 50 % / 100 % que pagan monedas, gemas,
   materiales, objetos, titulos y cosmeticos con el pagador unico `core/rewards.gd`. Los miembros
   son **familias evolutivas** (`core/families.gd`): Sakuta y Mai cuenta aunque ya haya evolucionado.
   Pantalla `collection_rewards` (desde COLECCION > RECOMPENSAS).
2. **Misiones personales** (`data/missions/pm_*.json`, 12): Sakuta y Mai, Goku y David y Lucy
   (usar en N combates, derrotar jefes, evolucionar, combatir con companeros compatibles o en
   solitario). Reutilizan `MetaProgress.record()`; pestana PERSONAJES en MISIONES.
3. **Nivel de cuenta** (`core/account.gd`, `data/account/levels.json`): antes de la v15 no existia.
   30 niveles, XP solo por `MetaProgress.record()`, recompensa por nivel que se cobra a mano.
   Desbloqueos cosmeticos (34): fondos del menu e ilustraciones de perfil. Pantalla PERFIL.
   Sin monedas nuevas. Un guardado v14 estima su XP **una sola vez** desde sus contadores.
4. **Audio y presentacion** (`audio/audio.gd`, `scenes/battle/battle_ui.gd`): fundidos entre
   musicas sobre el mismo reproductor (nunca suenan dos), pedir la misma pista no la reinicia,
   gana la ultima peticion, la musica baja en la intro de un jefe y sale con fundido en
   resultados, pista opcional `boss` (si no existe suena la de combate), efectos sin solape ni
   acumulacion, temblor de pantalla en criticos. Respeta los ajustes de volumen.
5. **Calidad de vida**: comparar personajes (`compare`), estadisticas previstas al evolucionar
   (`core/preview.gd`, mismas cifras que el combate), informacion de fases (regla de pago,
   jefe, tipos) en batalla, historia y torre, y proteccion de unidades importantes (nivel >= 50,
   Dupes, mutacion, equipo activo, misiones en curso): piden confirmacion en dos pasos antes de
   consumirlas; los favoritos siguen bloqueados.
6. **Diagnostico solo de desarrollo** (`dev/diagnostics.gd`, `--diag`, boton en el panel dev).
   No existe en la version publica. Ver `dev/README.md`.

## Corregido
- El logro Gran coleccion era imposible (las evoluciones especiales consumen ids): ahora cuenta familias.
- La pantalla de evolucion mostraba el nivel actual tras una evolucion normal (que reinicia a 1).

## Guardado
Claves nuevas y aditivas: `account`, `collections` y `meta_progress.personal`. `SAVE_VERSION` sigue
en 3; un guardado v14 carga sin cambios.

## Pruebas reales (godot 4.7 headless)
DBG27 (nuevo): **228 comprobaciones, 0 fallos**. Suites previas: DBG15 (0 fallos; no sale solo, se
corta por tiempo), DBG17 107, DBG18 240, DBG19 190, DBG20 79, DBG21 48, DBG22 30, DBG23 50, DBG24 104,
DBG25 101, DBG26 130: todas sin fallos. `--diag`: 0 errores, 6 avisos, 3 notas. Arranque sin errores
de script. Cambios en tests viejos (legitimos): menu 13 -> 14 botones, MISIONES 4 -> 5 pestanas y la
evolucion especial de una unidad importante pide segundo toque.

## Pendiente / honesto
- No probado en dispositivo ni con capturas; no se ha podido probar una exportacion release real
  (se simula con `DevTools.simulate_release`).
- Los fundidos de musica estan desactivados en headless por defecto; se probaron activandolos
  a proposito, pero no se ha escuchado el resultado.
- No existe `audio/music/boss.*`: los jefes usan la musica de combate hasta que la aportes.
- El valor de recompensas y XP no se ha simulado a nivel de equilibrio.
- 44 personajes aun no tienen arte propio (silueta); 2 iconos de objeto faltan.
- Las transformaciones NO se han implementado (fuera de alcance).
- Maomao no esta en ninguna coleccion.
