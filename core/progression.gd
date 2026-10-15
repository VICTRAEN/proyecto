extends RefCounted
class_name Progression

## Reglas de NIVEL y EXPERIENCIA. Solo matematicas puras: no lee archivos, no
## guarda nada y no conoce ningun personaje concreto.
##
## El estado (cuanto nivel y cuanta XP tiene AHORA un personaje) vive en
## autoload/game_state.gd, nunca en el JSON del personaje: el JSON es su ficha de
## identidad y no debe cambiar porque el jugador haya jugado.
##
## Todo lo que depende del nivel se define aqui. Subir de nivel no toca ningun
## otro archivo.

## Un personaje empieza en 1 y no pasa de 100.
const LEVEL_MIN := 1
const LEVEL_MAX := 100

## Cuanta XP hace falta para pasar del nivel indicado al siguiente.
## Curva lineal sencilla: 100 XP para el nivel 2, 140 para el 3, 180 para el 4...
## Subir la pendiente aqui alarga toda la progresion del juego.
const XP_BASE := 100
const XP_STEP := 40


## XP necesaria para subir del nivel "level" al siguiente.
static func xp_to_next(level: int) -> int:
	var clamped := clampi(level, LEVEL_MIN, LEVEL_MAX)
	return XP_BASE + XP_STEP * (clamped - LEVEL_MIN)


## Cuanto crecen las estadisticas por nivel: 4% del valor base por cada nivel
## extra. En nivel 1 el multiplicador es 1.0, asi que el balance de nivel 1 no
## cambia. Las probabilidades (critico y esquiva) NO crecen con el nivel: un
## personaje no se vuelve mas preciso por ser fuerte.
const GROWTH_PER_LEVEL := 0.04
const GROWTH_STATS := ["max_hp", "atk", "def", "speed"]


static func grows_with_level(stat_name: String) -> bool:
	return GROWTH_STATS.has(stat_name)


## Multiplicador de una estadistica segun el nivel. 1.0 en nivel 1.
static func growth_factor(level: int) -> float:
	var clamped := clampi(level, LEVEL_MIN, LEVEL_MAX)
	return 1.0 + GROWTH_PER_LEVEL * float(clamped - LEVEL_MIN)


## Reparte una cantidad de XP. Devuelve el estado NUEVO sin modificar nada:
##   { level, xp, levels_gained, maxed }
## Un personaje al maximo deja de acumular XP.
static func apply_xp(level: int, xp: int, amount: int) -> Dictionary:
	var new_level := clampi(level, LEVEL_MIN, LEVEL_MAX)
	var new_xp := maxi(0, xp)
	var gained := 0
	if new_level >= LEVEL_MAX:
		return { "level": LEVEL_MAX, "xp": 0, "levels_gained": 0, "maxed": true }

	var remaining := maxi(0, amount)
	while remaining > 0:
		var need := xp_to_next(new_level)
		if new_xp + remaining < need:
			new_xp += remaining
			remaining = 0
			break
		remaining -= (need - new_xp)
		new_xp = 0
		new_level += 1
		gained += 1
		if new_level >= LEVEL_MAX:
			new_level = LEVEL_MAX
			new_xp = 0
			remaining = 0
			break

	return {
		"level": new_level,
		"xp": new_xp,
		"levels_gained": gained,
		"maxed": new_level >= LEVEL_MAX,
	}


## Texto del progreso de XP de una ficha: "820 / 1000 XP".
static func xp_text(level: int, xp: int) -> String:
	if level >= LEVEL_MAX:
		return "NIVEL MAXIMO"
	return "%d / %d XP" % [xp, xp_to_next(level)]


## Ratio 0..1 de la barra de XP.
static func xp_ratio(level: int, xp: int) -> float:
	if level >= LEVEL_MAX:
		return 1.0
	var need := xp_to_next(level)
	if need <= 0:
		return 0.0
	return clampf(float(xp) / float(need), 0.0, 1.0)
