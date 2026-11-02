# v16 / X.1 - Banners diarios, perfil y personalizacion

## Banners diarios rotativos
- 7 banners (`data/banners/banner_diario_*.json`, `"rotation": {"type":"daily","order":N}`), uno por dia, segun la fecha local real (mismo reloj que las misiones). Calendario: `data/rotation.json` (`start_date`, `overrides` por fecha).
- La rotacion es funcion pura de la fecha: no se guarda nada, sobrevive a cerrar/abrir el juego. `summon()` rechaza un diario que no toca hoy.
- Anadir un banner al ciclo = un JSON con `rotation`. Invocar muestra el de hoy + los permanentes; la info enseña cuenta atras y los proximos 7 dias.
- API: `GameState.daily_banner_id / banner_active / available_banners / banner_schedule / banner_rotation_text`.

## Destacado 7% -> 3%
- David y Lucy: 3% por tirada (SSR sigue 15%; resto del SSR 12%). Los diarios llevan 2 destacados al 3%. Tests y textos actualizados.

## Perfil, vitrina, personalizacion (`core/player_profile.gd`)
- Avatar, marco, titulo, favorito y vitrina de 5 huecos. Solo se elige lo desbloqueado: una forma `{root, form}` poseida. David y Lucy SSR no ofrece UR/LR hasta evolucionar; al evolucionar la nueva forma aparece (y la anterior sigue disponible).
- Estadisticas reales: personajes, rareza, invocaciones, victorias, combates, stages, evoluciones.
- Marcos, temas y decoraciones: cosmeticos nuevos en `data/cosmetics` (12), ganados por nivel de cuenta. Pantalla `menu_customize` (fondos + temas + decoraciones). Extensible: JSON + nivel.
- Guardado: bloque `profile` (aditivo, SAVE_VERSION igual). Un guardado v15 carga sin perder nada; los niveles ya cobrados reciben los cosmeticos nuevos una vez.

## Pruebas
- DBG28 (`--dbg28`): 111 comprobaciones. DBG17-27 y `--diag` sin errores.
