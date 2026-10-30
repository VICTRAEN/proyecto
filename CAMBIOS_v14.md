# CAMBIOS v14 - jefes con fases, presentacion, misiones, eventos y logros

## Nuevo
1. **Jefes con fases** (`core/battle_manager.gd`, `core/combat_unit.gd`): fases por datos
   (`phases`, `intro`, `pattern`, `boss`) que reutilizan las condiciones y efectos del
   motor existente. Senales `boss_intro`, `phase_changed`. Jefes: `void_warden` (Makima),
   `sdp_akaza` (Akaza), `boss_sakuta` (2 fases). Los demas enemigos NO cambian.
2. **Presentacion** (`ui/boss_fx.gd`, `scenes/battle/battle_ui.gd`): intro de jefe
   saltable (toque), transicion de fase, chispas/anillo en los impactos, reaccion del
   enemigo (`hit_shake`) y brasas ambientales. Respeta animaciones reducidas y la
   velocidad; sin UI el combate no espera ninguna intro.
3. **Misiones diarias y semanales** (`core/meta_progress.gd`, `data/missions/`): 5 diarias
   y 6 semanales, reinicio por fecha local, un unico punto de entrada por accion.
4. **Eventos reutilizables**: `story`, `completion_reward`, `first_clear_items`,
   `survive_rounds`, deteccion de jefe. Sindromes de la Pubertad solo gana `story`.
5. **Logros y titulos**: 15 logros (`data/achievements/`), pestana LOGROS con reclamar y
   seleccion de titulo. Antes de la v14 NO existia sistema de titulos de jugador.
6. La pantalla MISIONES gana 4 pestanas: DIARIAS, SEMANALES, PERMANENTES, LOGROS.

## Guardado
Clave nueva `meta_progress`; un guardado v13 carga sin cambios y los logros se
reevaluan contra el estado real (retroactivos). `SAVE_VERSION` sigue en 3.

## Pruebas (DBG26: 130 comprobaciones)
Datos de jefes, motor de fases, combate completo sin UI, intro saltable/automatica/
calmada, jefe dentro de la pantalla de combate real, reloj de misiones (dia/semana/lunes),
no contar dos veces (3 cobros de la misma batalla = 1), objetivos, persistencia y guardado
antiguo, logros, titulos, eventos solo-datos, supervivencia y pantallas.

## Pendiente / honesto
- Los jefes con fases son algo mas duros que antes (efectos de fase): no se ha
  reequilibrado ni simulado.
- No se ha probado en dispositivo ni con capturas; los efectos son por codigo.
- Las transformaciones NO se han implementado (fuera de alcance).
- La evolucion de logros cuenta solo evoluciones por ruta normal (no la especial).
