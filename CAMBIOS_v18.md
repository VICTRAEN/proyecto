# v18 / X.3 — Nuevos modos de juego

Todo reutiliza lo existente: un único origen de combate (`"mode"`), el motor de combate, `core/rewards.gd`, links/líder, fases de jefe, reglas de efectos y el guardado. Sin monedas ni sistemas paralelos. Código en `core/game_modes.gd` (`GameState.modes`).

## Modos
- **Incursiones** (`data/raids/*.json`, 3: Sukuna, Geto, Vegeta): jefe de 38–42 000 de vida con 4 fases (75/50/25 %) que añaden habilidades; límite de 10 rondas; premios por tramos de daño y objetivos (fase, sin bajas, críticos, derrotar al jefe) cobrables una vez por semana; rotación semanal pura por fecha (`data/rotation.json` → `raid_start_date`); registro de intentos y records.
- **Mazmorras** (`data/dungeons/*.json`, 5: XP, monedas, evolución, personajes, equipables): 4 dificultades, desbloqueo en cadena, premio creciente, drops con probabilidad. Añadir una mazmorra = un JSON.
- **Roguelike** (`data/modes/roguelike.json`): equipo propio, combates seguidos con escalado, jefe cada 5, 3 mejoras aleatorias tras cada victoria (26 mejoras: stats, críticos, curación, categoría, links, especiales). Las mejoras solo existen en la partida; los personajes guardados no cambian. Semilla guardada: la elección pendiente es idéntica tras recargar. Premio por profundidad + hitos.
- **Campo de entrenamiento** (`data/modes/training.json`): aliados propios, enemigos de todo el catálogo (incluso personajes), objetos de prueba del catálogo, multiplicador enemigo, vida y SP iniciales, límite de rondas. Sandbox: no paga, no cuenta, no guarda.
- **Boss Rush** (`data/modes/boss_rush.json`): 7 jefes seguidos, 3 dificultades, desgaste (recuperación parcial 15/8/0 %), caídos no vuelven, premio por jefe + hitos, records por dificultad, carrera guardada.

## Recursos nuevos
- `equipment_shard` (Fragmento de armería; 50 = 1 tirada en la Armería, botón nuevo en OBJETOS).
- `evo_ember`, `evo_core` (materiales de evolución genéricos; los de evento rabbit_costume/mai_token siguen siendo exclusivos de evento).

## Otros
- Pantallas: MODOS DE JUEGO (hub) + 5; botón en el menú principal.
- Diagnóstico `--diag` valida los datos de los modos. Guardado: bloque aditivo `"modes"`.
- Pruebas: `--dbg30` (172 comprobaciones). Todas las suites dbg17–dbg29 y `--diag` en verde.
