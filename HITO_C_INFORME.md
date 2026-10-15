# HITO C — Informe final (menús, ajustes, audio, equipo con huecos, evento)

Estado: **entregado para revisión. No se ha empezado el Hito D.**

> **Límite importante.** Todo lo de aquí abajo se ha comprobado de forma **estática**
> (lectura de código, datos y scripts Python). **No he ejecutado Godot ni el juego** y el
> GDScript nuevo o modificado **nunca se ha compilado**. Las pruebas de ejecución están
> escritas (sección 9) y son para Summer/Godot. No doy por probado nada que no se haya visto
> funcionar.

## 1. Qué se ha hecho, en una frase por bloque

| Bloque | Resultado |
|---|---|
| Equipo con huecos | `GameState.party` admite 0/4…4/4. Repetir al personaje que ya ocupa la posición la deja **vacía**. Regla general, sin ningún `if` por personaje. Botón **QUITAR** nuevo. |
| Stage 3 de Sakuta | Se **eliminó el atajo** que montaba el equipo solo (`_solo_party_for_source`). El jugador forma `[SAKUTA]` 1/4 en Equipo y el stage lo valida con los datos del stage. |
| Ajustes | Pantalla real + autoload `GameSettings`, guardado en `user://settings.json` (separado del guardado de partida). |
| Audio | Sistema por carpetas (`music/ui/combat/progression`), 25 sonidos en catálogo, fallbacks, volúmenes de Ajustes, anti-spam. **Sin archivos de audio** (no se han inventado). |
| Menú principal | Rehecho y agrupado (11 botones, ninguno sin destino). |
| Mutaciones | Pantalla **nueva** (no existía; la ficha ya la mencionaba). |
| Enemigos del evento | Los 3 stages usan personajes del roster (Todo, Mahito, Akaza) con las estadísticas de los antiguos NPC. |

## 2. Archivos

**Modificados (24):** `.summerrules`, `art/characters/ASSET_REPORT.md`, `audio/README.md`, `audio/audio.gd`,
`autoload/db.gd`, `autoload/game_state.gd`, `core/battle_manager.gd`, `data/SCHEMA.md`,
`data/events/event_sindromes_de_la_pubertad.json`, `project.godot`, `scenes/app.gd`,
`scenes/battle/battle_ui.gd`, `scenes/screens/events.gd`, `evolution.gd`, `main_menu.gd`,
`main_menu.tscn`, `missions.gd`, `stage_select.gd`, `summon.gd`, `team.gd`, `world_map.gd`,
`tools/project_check.py`, `ui/screen_fade.gd`, `ui/unit_info_panel.gd`.

**Añadidos (14, + este informe):** `autoload/settings.gd`, `scenes/screens/settings.gd/.tscn`,
`scenes/screens/mutations.gd/.tscn`, `scenes/debug/hito_c_checks.gd`, `data/enemies/sdp_todo.json`,
`sdp_mahito.json`, `sdp_akaza.json`, `tools/gd_check.py`, y 4 `_pon_tus_sonidos_aqui.txt`
(en `audio/music`, `ui`, `combat`, `progression`).

**Eliminados: ninguno. Imágenes: 64 antes, 64 ahora, ninguna modificada** (comprobado con sha256).
No se ha tocado la arquitectura de assets del Hito B.

`project.godot`: una sola línea nueva, el autoload `GameSettings` (antes de `GameAudio`).

## 3. Pantallas

**Cambiadas**

- **Menú principal** (rehecho). Jerarquía: título y cartera → **JUGAR** (grande, dorado) → **HISTORIA** →
  grupos con etiqueta: **GESTIÓN** (Equipo, Colección), **CONTENIDO** (Invocar, Eventos, Misiones),
  **PROGRESIÓN** (Inventario, Evolución, Mutaciones) → **AJUSTES** aparte y discreto. Se construye desde
  la lista `GROUPS` de `main_menu.gd`.
- **Equipo**: título `TU EQUIPO – n / 4`, huecos con texto `HUECO LIBRE`, botón `QUITAR POS. n` (solo activo si la
  posición está ocupada), pistas que cambian según la posición esté ocupada o vacía, y `COMBATIR` avisa en vez de
  navegar si el equipo está vacío.
- **Ajustes** (nueva) y **Mutaciones** (nueva).
- Avisos de "equipo vacío" en **Selección de stage**, **Eventos** e **Historia**, y defensa final en `App.open_battle`.
- Ficha (`unit_info_panel`): sonidos al abrir, cambiar pestaña y cerrar.

**NO rediseñadas en este hito** (solo se les añadió sonido/avisos): Colección, Invocar, Historia/mapa, Eventos,
Inventario, Misiones, Evolución, Selección de stage. **Torres** no existe todavía (queda para su hito).

Por qué: sin poder ejecutar Godot, reconstruir 8 pantallas con layouts complejos a ciegas era el mayor riesgo de
romper lo que ya funciona ("no sacrifiques estabilidad por estética"). Propongo hacerlas **una a una** y verificando
cada una en Godot (ver sección 11).

## 4. Sistema de audio

- Autoload `GameAudio` (`audio/audio.gd`). API: `GameAudio.play("evento")`, `GameAudio.play_music("pista")`, `stop_music()`.
- **Catálogo** (arriba de `audio.gd`): `music` (menu, battle, history, events, results) · `ui` (click, select, back, open,
  close, equip, remove, claim, tab, buy) · `combat` (attack, special, critical, heal, victory, defeat) ·
  `progression` (summon, evolution, level_up, mutation).
- **Rutas exactas**: `res://audio/<carpeta>/<nombre>.ogg` (también `.wav`, `.mp3`). Documentado en `audio/README.md` y
  en el `.txt` de cada carpeta.
- **Archivo que falta = sin error.** Sustitutos: `tab→select`, `buy→claim`, `special→attack`, `critical→attack`,
  `level_up→claim`, `history/events/results→menu`. También sigue valiendo el archivo suelto antiguo (`button.ogg`, `crit.ogg`…).
- **Volumen** por categoría desde Ajustes; a 0% no se reproduce. **Anti-spam**: mismo sonido no antes de 60 ms; máximo 8 voces.
- **Botones**: todo `Button` suena solo (`click`; `back` si su nombre contiene "back"; `close` si "close/cancel"; se puede pedir otro
  con `set_meta("sfx", …)`).
- **Dónde se llama** (además de los botones): música por pantalla (`SCREEN_MUSIC` en `app.gd`) y de combate; resultados
  (`results`, `victory`/`defeat`, `level_up`); un sonido por acción de combate (crítico > especial > normal, o curación);
  seleccionar personaje/posición/stage; colocar (`equip`) y quitar (`remove`) del equipo; abrir ficha, cambiar pestaña,
  cerrar; reclamar misión/unidad de evento (`claim`); abrir inventario (`open`); invocar; evolucionar; mutar.
- **No hay tienda** en el juego, así que `buy` está preparado pero no se dispara desde ninguna pantalla.

## 5. Equipo con huecos y Stage 3 (sin lógica de Sakuta)

- `GameState.assign_party_slot(slot, id)`: misma posición → **quita**; estaba en otra → **mueve** (la otra recibe el hueco o lo
  que hubiera, sin duplicados); no estaba → **coloca** (solo personajes obtenidos). Guarda al momento.
- Ayudantes: `normalize_party()`, `party_ids()`, `party_count()`, `team_problem()`, `PARTY_MIN = 1`.
- **Atajo eliminado**: `prepare_battle` ya no fija `battle_party`; el combate lleva las posiciones ocupadas del equipo.
- La validación del stage sigue saliendo de los **datos** (`requires_party_character/rarity/solo` de
  `event_sindromes_de_la_pubertad.json`) vía `GameState.event_party_ready`, que ya ignoraba huecos.
- Los guardados antiguos (4 ids) cargan igual; `normalize_party()` solo rellena a 4 posiciones y quita repetidos.
- **Leader Skill (regla definitiva, actualizada tras tu revisión):** solo el personaje de la **posición 1** ejerce de líder
  (`GameState.LEADER_SLOT = 0`). Con la posición 1 vacía **no hay Leader Skill**, aunque haya gente en las posiciones 2–4.
  Ver `HITO_C_VERIFICACION.md`.

## 6. Enemigos del evento

Nuevo mecanismo de datos: un enemigo puede llevar `"based_on": "<personaje>"` (ver `data/SCHEMA.md`). `DB` copia al
personaje (nombre, tipo, habilidades, pasiva, arte…) y aplica encima las `stats` propias.

| Stage | Antes | Ahora (mismas stats) |
|---|---|---|
| evt_sdp_01 | vigia_alfa | `sdp_todo` = **Aoi Todo** (STR SR) |
| evt_sdp_02 | vigia_beta + vigia_alfa | `sdp_mahito` = **Mahito** (INT SR) + `sdp_todo` |
| evt_sdp_03 | void_warden | `sdp_akaza` = **Akaza** (PHY SSR, jefe) |

Se eligió el mismo tipo y rareza que el NPC sustituido para no alterar el balance. Los NPC antiguos **siguen existiendo**
(los usan stages sueltos, mundos y torre). No se ha buscado balance.

## 7. Ajustes

| Opción | Qué hace exactamente |
|---|---|
| Música / Efectos / Sonidos de interfaz | Slider 0–100 %. Aplica al instante y se guarda al soltar (o 0,5 s después). |
| Velocidad de combate | Normal / Rápida: divide las pausas entre turnos (×1,75). |
| Velocidad de animaciones | Normal / Rápida: los tweens del combate van ×1,75. |
| Tamaño de texto e interfaz | Normal / Grande: escala **toda** la interfaz ×1,2 (`content_scale_factor`), no solo el texto. |
| Números de daño | Sí/No: oculta los números; "CRITICO!" y "ESQUIVA" siguen. |
| Indicadores de ventaja | Sí/No: oculta el aviso flotante "VENTAJA/DESVENTAJA DE TIPO" (la línea del registro de combate se mantiene). |
| Animaciones reducidas | Sí/No: sin latido de JUGAR, sin entrada del menú, sin fundido entre pantallas, sin pulso del personaje activo, sin desplazamiento de popups; y las animaciones del combate a ≥ ×2. |

**Omitida a propósito: "Confirmación de acciones".** El combate no tiene ningún paso de confirmación (elegir objetivo ya
es el paso final) y las pantallas de evolucionar/mutar no tienen diálogo de confirmación; añadirlo habría sido UI nueva
a ciegas. Queda para el hito de esas pantallas.

## 8. Pruebas ESTÁTICAS realizadas (no son pruebas de ejecución)

- `python3 tools/project_check.py check` → **0 errores, 1 aviso** (el de `reze_` ya conocido): 139 JSON válidos + 3 nuevos, IDs únicos,
  referencias (incluye `based_on` y los enemigos del evento), **imágenes 64 = 64 sin cambios**, audio 0/25 archivos (esperado).
- `python3 tools/gd_check.py` (nuevo) → **0 problemas** en 44 scripts: sintaxis básica, `preload` de archivos existentes,
  miembros de `GameState/DB/GameSettings/GameAudio` y de constantes `preload`, nodos `$Ruta` frente a su `.tscn` y nombres de
  sonido contra el catálogo. **Validé el propio linter** inyectando 6 errores en una copia temporal: detectó los 6.
- Análisis léxico de todos los `.gd` con el lexer GDScript de Pygments: sin errores.
- Búsqueda manual de la trampa clásica de tipos (`:=` sobre valores `Variant`): todos los casos están envueltos en `String()/int()/float()`.
- `tools/test_asset_resolution.py` (Hito B) → 14/14, sin cambios.
- Comprobación de que `event_party_ready` valida por datos (tamaño, forma, personaje) y **ya ignoraba huecos**.

**Lo que esto NO cubre:** errores de tipos o de número de argumentos que solo detecta el compilador de Godot, comportamiento visual,
layouts, audio real, y cualquier interacción entre nodos en ejecución.

## 9. Pruebas para Summer/Godot

### A. Automáticas (recomendado primero)
En `scenes/app.gd` pon **`DEBUG_V17 := true`**, ejecuta, y lee la salida o `res://dbg17_resultados.txt`. Cada línea acaba en
`OK` o `FALLO`. Usa los handlers reales de las pantallas y **restaura tu guardado y tus ajustes** al terminar. Cubre:
equipo 4/4→0/4 y quitar al repetir, botón QUITAR, equipo de 1, persistencia del equipo; Stage 3 (tests 3–6); ajustes y su
persistencia; catálogo de audio sin archivos; los 11 botones del menú y 11 pantallas; mutación (150 monedas, sustitución,
sin monedas); enemigos del evento; combate con velocidad rápida y combate bloqueado con equipo vacío.
Además, `DEBUG_V15` (ya existente) fue **actualizado** al equipo sin atajos.

### B. Manuales
1. **AJUSTES**: cambiar Música al 30 %, Efectos al 60 %, "Velocidad de combate: Rápida", "Números de daño: No". Cerrar el juego, abrir → todo igual.
2. **AUDIO** (hace falta poner al menos `music/menu.ogg` y `music/battle.ogg`, aunque sean cualquier archivo): Menú → suena `menu`; entrar
   a un combate → cambia a `battle`; terminarlo → `results` (o `menu` si no existe); volver → `menu`. Con solo `menu.ogg`, Historia y Eventos siguen con `menu` sin cortarse.
3. **EQUIPO**: crear 4/4, 3/4, 2/4, 1/4. Tocar un personaje ya colocado en su posición → queda **vacío**. Botón QUITAR. `COMBATIR` con 0/4 avisa y no navega.
4. **SAKUTA**: dejar `[SAKUTA UR]` solo (1/4) y entrar al Stage 3. Después `[Sakuta+Mai SSR]` solo → bloquea; `[Sakuta UR + otro]` → bloquea.
5. **MENÚS**: Menú → Colección → Equipo → Inventario → Mutaciones → Evolución → Eventos → Historia → Ajustes → volver. Ningún botón muerto (el modo automático los pulsa todos).
6. **Texto GRANDE**: revisar que ninguna pantalla se desborda (es la opción con más riesgo visual).
7. **Evento**: los 3 stages muestran Todo, Mahito+Todo y Akaza (sin arte si faltan sus PNG: silueta).
8. Cerrar/reabrir: equipo con huecos, ajustes y mutaciones persisten.

## 10. Riesgos restantes

1. **El GDScript no se ha compilado.** Un error en `game_state.gd`, `db.gd` o `settings.gd` (autoloads) impide arrancar. Primero: abrir el proyecto y mirar Errores/Salida.
2. **"Texto grande" escala toda la UI** (×1,2): puede desbordar alguna pantalla. Si molesta, el valor está en `UI_SCALE` de `settings.gd`.
3. Los `.gd.uid` de los scripts nuevos los generará Godot al abrir.
4. **Botones y sonido**: `click` suena en todos los botones; en acciones que además tienen sonido propio (p. ej. invocar) suenan los dos a la vez.
5. `HistoryScreen`/otras pantallas sin rediseñar pueden verse "de otra época" junto al nuevo menú.
6. Los guardados no cambian de formato, pero un equipo con huecos guardado y cargado en una versión anterior perdería los huecos.

## 11. Pendiente para el Hito D (propuesta, sin empezarlo)

1. Rediseño **pantalla a pantalla** (con verificación en Godot entre cada una): Selección de stage → Colección → Equipo (más visual) → Eventos → Historia → Inventario/Misiones → Invocar → Evolución.
2. Confirmación de acciones destructivas (evolucionar, mutar) si se quiere.
3. **Audio real**: los 25 archivos (o al menos menu/battle/click/attack/victory/defeat).
4. Sustituir el resto de NPC placeholder (`vigia_*`, `void_warden`) en stages sueltos, mundos y torre.
5. **Torres** (siguiente hito acordado) y `mai_token` (su única fuente hoy es el piso 25).
6. Tienda (para que `buy` suene).
