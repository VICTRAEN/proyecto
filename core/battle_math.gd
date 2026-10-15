extends RefCounted

const CombatUnit := preload("res://core/combat_unit.gd")

## Formulas puras del combate. Ningun otro archivo calcula dano.
## La rueda de tipos y los factores viven aqui para poder rebalancear el juego
## sin tocar el flujo de turnos.

## STR vence a AGL, AGL a INT, INT a TEQ, TEQ a PHY y PHY a STR.
const TYPE_ADVANTAGE := {
	"STR": "AGL",
	"AGL": "INT",
	"INT": "TEQ",
	"TEQ": "PHY",
	"PHY": "STR",
}
const TYPE_ADVANTAGE_MULT := 1.25
const TYPE_DISADVANTAGE_MULT := 0.8
const CRIT_MULTIPLIER := 1.6
const DEF_FACTOR := 0.45
## Variacion aleatoria del dano final (95%-105%). Se aplica AL RESULTADO, nunca a
## las estadisticas: el ATQ de la ficha no cambia por tirar el dado. El rango no
## se ensena en pantalla, y no hay ninguna estadistica de minimo ni de maximo.
const VARIANCE_MIN := 0.95
const VARIANCE_MAX := 1.05

## Verificacion en ejecucion: imprime cada tirada (probabilidad de critico usada,
## dado, si ha salido critico, base y variacion). Se deja en false en el juego.
const DEBUG_ROLLS := false


static func type_multiplier(attacker_type: String, defender_type: String) -> float:
	if String(TYPE_ADVANTAGE.get(attacker_type, "")) == defender_type:
		return TYPE_ADVANTAGE_MULT
	if String(TYPE_ADVANTAGE.get(defender_type, "")) == attacker_type:
		return TYPE_DISADVANTAGE_MULT
	return 1.0


## Probabilidad real de critico de una unidad. Es EXACTAMENTE la que se usa para
## tirar el dado en deal_damage, y el panel de informacion pinta esta misma
## funcion: el numero que ve el jugador y el que decide el golpe no pueden
## separarse, porque son el mismo.
static func crit_chance(unit: CombatUnit) -> float:
	return clampf(unit.crit_rate(), 0.0, 1.0)


## Resuelve un golpe y lo aplica. Devuelve un resultado que la UI sabe pintar.
static func deal_damage(attacker: CombatUnit, defender: CombatUnit, power: float, ctx: Dictionary) -> Dictionary:
	var rng: RandomNumberGenerator = ctx["rng"]
	if defender.dodge_rate() > 0.0 and rng.randf() < defender.dodge_rate():
		return {
			"kind": "damage",
			"target_key": defender.source_key,
			"target_name": defender.display_name,
			"value": 0.0,
			"dodged": true,
			"crit": false,
			"type_mult": 1.0,
		}
	var raw := attacker.attack() * (power / 100.0)
	var mitigated := maxf(1.0, raw - defender.defense() * DEF_FACTOR)
	var type_mult := type_multiplier(attacker.type, defender.type)
	var total := mitigated * type_mult
	var chance := crit_chance(attacker)
	var roll := rng.randf()
	var crit := roll < chance
	if crit:
		total *= CRIT_MULTIPLIER
	# La variacion se aplica al RESULTADO, nunca a las estadisticas: el ATQ de la
	# ficha no cambia por tirar el dado.
	var variance := rng.randf_range(VARIANCE_MIN, VARIANCE_MAX)
	total *= variance
	var dealt := defender.take_damage(roundf(total))
	if DEBUG_ROLLS:
		# Traza de verificacion: probabilidad usada, dado, critico si/no, dano
		# antes de la variacion y factor aplicado.
		print("[DBG] %s > %s crit=%.3f dado=%.3f %s base=%d x%.3f = %d" % [
			attacker.display_name,
			defender.display_name,
			chance,
			roll,
			"CRIT" if crit else "normal",
			int(round(total / variance)),
			variance,
			int(round(total)),
		])
	return {
		"kind": "damage",
		"target_key": defender.source_key,
		"target_name": defender.display_name,
		"value": dealt,
		"dodged": false,
		"crit": crit,
		"type_mult": type_mult,
	}
