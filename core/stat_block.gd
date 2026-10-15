extends RefCounted

const Progression := preload("res://core/progression.gd")

## Estadisticas base de una unidad mas sus modificadores temporales.
## Es el UNICO lugar donde se calcula el valor final de una estadistica.
## Cualquier cosa que altere una stat (link, lider, pasiva, buff, debuff) pasa
## por aqui, asi que depurar un numero raro es mirar un solo sitio.

var base: Dictionary = {}
var mods: Array = []
## Nivel del personaje. Las estadisticas del JSON son las de nivel 1; el nivel
## escala desde ahi (ver core/progression.gd). A nivel 1 el factor es 1.0, asi
## que los datos del JSON se leen tal cual.
var level := 1
## Multiplicador de RAREZA. Una forma evolucionada pega mas fuerte con las mismas
## estadisticas de JSON: el numero NO vive aqui, sale de la ruta de evolucion
## (res://data/evolution/rules.json -> stat_multiplier) y GameState lo entrega ya
## resuelto. A nivel de forma base vale 1.0, asi que el balance de un personaje sin
## evolucionar no cambia. Forma parte del paso "rareza" del calculo: el valor final
## se sigue resolviendo SOLO aqui.
var rarity_mult := 1.0


func _init(base_stats: Dictionary = {}, unit_level: int = 1) -> void:
	base = base_stats.duplicate(true)
	level = clampi(unit_level, Progression.LEVEL_MIN, Progression.LEVEL_MAX)


## El multiplicador de rareza se puede fijar despues de construir el bloque, igual
## que el nivel, y todos los valores se recalculan solos.
func set_rarity_multiplier(value: float) -> void:
	rarity_mult = maxf(0.0, value)


## El nivel se puede cambiar despues de construir el bloque (subir de nivel en la
## ficha, por ejemplo) y todos los valores se recalculan solos: la estadistica
## final nunca se guarda en un sitio y se lee de otro.
func set_level(new_level: int) -> void:
	level = clampi(new_level, Progression.LEVEL_MIN, Progression.LEVEL_MAX)


func get_stat(stat_name: String) -> float:
	var value := base_value(stat_name)
	var mult := 0.0
	var flat := 0.0
	for mod in mods:
		if String(mod["stat"]) != stat_name:
			continue
		if String(mod["kind"]) == "mult":
			mult += float(mod["value"])
		else:
			flat += float(mod["value"])
	return maxf(0.0, value * (1.0 + mult) + flat)


## Valor base CON nivel: es lo que el panel ensena en la columna BASE, y sobre lo
## que se aplican pasivas y buffs. Las estadisticas que no crecen con el nivel
## (critico y esquiva) devuelven el valor del JSON sin tocar.
func base_value(stat_name: String) -> float:
	var raw := float(base.get(stat_name, 0.0))
	if not Progression.grows_with_level(stat_name):
		return raw
	return raw * Progression.growth_factor(level) * rarity_mult


## Valor EXACTO del JSON, sin nivel y sin modificadores. Casi nada deberia usarlo:
## esta aqui para poder comparar y para depurar.
func raw_value(stat_name: String) -> float:
	return float(base.get(stat_name, 0.0))


## Nombre visible de cada estadistica. Vive aqui, junto a las stats, para que el
## panel de informacion y el registro del combate no inventen etiquetas distintas.
const LABELS := {
	"max_hp": "VIDA MAX",
	"atk": "ATAQUE",
	"def": "DEFENSA",
	"speed": "VELOCIDAD",
	"crit_rate": "CRITICO",
	"dodge_rate": "ESQUIVA",
}

## Estadisticas que son PROBABILIDADES: se leen en puntos porcentuales, no como
## porcentaje del valor base. Un +0.2 de critico son +20 puntos, no un 20% mas.
const RATE_STATS := ["crit_rate", "dodge_rate"]


static func label(stat_name: String) -> String:
	return String(LABELS.get(stat_name, stat_name.to_upper()))


static func is_rate_stat(stat_name: String) -> bool:
	return RATE_STATS.has(stat_name)


## Texto del valor de un modificador, sin el nombre de la estadistica. Es el UNICO
## sitio donde se decide este formato, asi que el panel y el registro coinciden.
## "mult" siempre es relativo al valor base; "flat" es absoluto, y si la stat es
## una probabilidad tambien se lee en puntos porcentuales.
static func mod_value_text(stat_name: String, kind: String, value: float) -> String:
	if kind == "mult" or is_rate_stat(stat_name):
		return _signed(int(round(value * 100.0)), "%")
	return _signed(int(round(value)), "")


static func _signed(amount: int, suffix: String) -> String:
	var sign_text := "+" if amount >= 0 else ""
	return "%s%d%s" % [sign_text, amount, suffix]


## Anade un modificador. "source" identifica quien lo puso: reaplicar el mismo
## origen sobre la misma stat sustituye el anterior en lugar de acumularlo, que
## es lo que impide que una pasiva de turno se dispare hasta el infinito.
func add_mod(stat_name: String, kind: String, value: float, source: String, turns: int = 0) -> void:
	remove_source(source, stat_name)
	mods.append({
		"stat": stat_name,
		"kind": kind,
		"value": value,
		"source": source,
		"turns": turns,
	})


func remove_source(source: String, stat_name: String = "") -> void:
	var kept: Array = []
	for mod in mods:
		var same_source: bool = String(mod["source"]) == source
		var same_stat: bool = stat_name.is_empty() or String(mod["stat"]) == stat_name
		if same_source and same_stat:
			continue
		kept.append(mod)
	mods = kept


## Descuenta un turno a cada modificador temporal y elimina los caducados.
## turns 0 significa permanente hasta que se quite por origen.
func tick() -> void:
	var kept: Array = []
	for mod in mods:
		var turns: int = int(mod["turns"])
		if turns <= 0:
			kept.append(mod)
			continue
		turns -= 1
		if turns > 0:
			mod["turns"] = turns
			kept.append(mod)
	mods = kept


func active_mods() -> Array:
	return mods.duplicate(true)
