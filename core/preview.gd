extends RefCounted

## PREVISIONES Y COMPARACION (v15). Solo LEE: no cambia ningun estado del jugador.
##
## Las cifras salen del MISMO sitio que en combate: se construye una CombatUnit con el
## diccionario de GameState.character_data (nivel, multiplicador de forma y Dupes ya
## resueltos) y se leen sus estadisticas finales (core/stat_block.gd). Ninguna pantalla
## calcula estadisticas por su cuenta. Quedan fuera lo que solo existe dentro de un
## equipo o una batalla (links, Leader Skill, pasivas, buffs) y la mutacion: es la
## estadistica BASE de la unidad, la misma columna BASE de la ficha.

const CombatUnit := preload("res://core/combat_unit.gd")
const Progression := preload("res://core/progression.gd")
const StatBlock := preload("res://core/stat_block.gd")

const STATS := ["hp", "atk", "def", "speed", "crit_rate", "dodge_rate"]


## Estadisticas finales de un diccionario de datos de personaje.
static func stats_of_data(data: Dictionary) -> Dictionary:
	var unit := CombatUnit.new()
	unit.setup(data, true, -1)
	return {
		"hp": unit.max_hp(), "atk": unit.attack(), "def": unit.defense(),
		"speed": unit.speed(), "crit_rate": unit.crit_rate(), "dodge_rate": unit.dodge_rate(),
	}


static func stats_of(gs, id: String) -> Dictionary:
	var data: Dictionary = gs.character_data(id)
	return stats_of_data(data) if not data.is_empty() else {}


## Texto de un valor: enteros para las estadisticas y puntos porcentuales para
## critico y esquiva (se guardan como fraccion).
static func value_text(stat: String, value: float) -> String:
	if StatBlock.is_rate_stat(stat):
		return "%d%%" % int(round(value * 100.0))
	return str(int(round(value)))


static func delta_text(stat: String, delta: float) -> String:
	if absf(delta) < 0.0005:
		return "="
	var sign := "+" if delta > 0.0 else "-"
	if StatBlock.is_rate_stat(stat):
		return "%s%d%%" % [sign, int(round(absf(delta) * 100.0))]
	return "%s%d" % [sign, int(round(absf(delta)))]


## --- Comparar dos personajes ------------------------------------------------------

## Filas [{ stat, label, a, b, a_text, b_text, better }] ("a", "b" o "=") para dos ids.
static func compare(gs, id_a: String, id_b: String) -> Array:
	var sa := stats_of(gs, id_a)
	var sb := stats_of(gs, id_b)
	var rows: Array = []
	if sa.is_empty() or sb.is_empty():
		return rows
	for stat in STATS:
		var a := float(sa[stat])
		var b := float(sb[stat])
		var better := "="
		if absf(a - b) >= 0.0005:
			better = "a" if a > b else "b"
		rows.append({
			"stat": stat, "label": StatBlock.label(stat), "a": a, "b": b,
			"a_text": value_text(stat, a), "b_text": value_text(stat, b), "better": better,
		})
	return rows


## Datos no numericos de comparacion: rareza, tipo, nivel, pasivas, categorias y links.
static func compare_info(gs, id: String) -> Dictionary:
	var data: Dictionary = gs.character_data(id)
	if data.is_empty():
		return {}
	var passive_names: Array = []
	for p in data.get("passives", []):
		if p is Dictionary and not String((p as Dictionary).get("name", "")).is_empty():
			passive_names.append(String((p as Dictionary)["name"]))
	return {
		"id": id, "name": String(data.get("name", id)), "rarity": String(data.get("rarity", "")),
		"type": String(data.get("type", "")), "level": int(data.get("level", 1)),
		"owned": bool(data.get("owned", false)), "passives": passive_names,
		"categories": (data.get("categories", []) as Array).duplicate(),
		"dupe_level": int(data.get("dupe_level", 0)),
	}


## Quien gana mas filas: "a", "b" o "=" (para el resumen).
static func compare_verdict(rows: Array) -> String:
	var a := 0
	var b := 0
	for r in rows:
		if String(r["better"]) == "a":
			a += 1
		elif String(r["better"]) == "b":
			b += 1
	if a == b:
		return "="
	return "a" if a > b else "b"


## --- Estadisticas previstas al evolucionar --------------------------------------------

## Previsión de la evolucion de `id` ({} si no tiene ninguna ruta).
##   kind        "normal" (misma identidad, sube de rareza) | "special" (cambia de personaje)
##   after_level nivel con el que queda tras evolucionar: la evolucion NORMAL reinicia a
##               nivel 1 (lo dice GameState.evolve); la ESPECIAL hereda el nivel actual.
##   rows        [{ stat, label, now, after_now, after_max, ... }]
##                  now        estadistica actual
##                  after_now  tras evolucionar, a `after_level`
##                  after_max  tras evolucionar y subir al nivel maximo
static func evolution_preview(gs, id: String) -> Dictionary:
	var key := String(id)
	var data: Dictionary = gs.character_data(key)
	if data.is_empty() or not gs.is_owned(key):
		return {}
	var special: Dictionary = gs.can_special_evolve(key)
	var kind := ""
	var to_id := key
	var to_rarity := ""
	var route: Dictionary = {}
	if not special.is_empty() and not String(special.get("to", "")).is_empty():
		kind = "special"
		to_id = String(special["to"])
		to_rarity = String(special.get("to_rarity", ""))
		route = special.get("route", {})
	else:
		var normal: Dictionary = gs.can_evolve(key)
		if normal.is_empty() or String(normal.get("to", "")).is_empty():
			return {}
		kind = "normal"
		to_rarity = String(normal["to"])
		route = normal.get("route", {})
	var now_stats := stats_of_data(data)
	var after_level := int(data.get("level", 1)) if kind == "special" else Progression.LEVEL_MIN
	var after_data: Dictionary
	if kind == "special":
		after_data = gs.character_data(to_id)
		if after_data.is_empty():
			return {}
		# El personaje nuevo hereda el nivel y los Dupes; su forma es la de su propio JSON.
		after_data["dupe_mods"] = data.get("dupe_mods", [])
		after_data["rarity"] = to_rarity
		after_data["stat_multiplier"] = 1.0
	else:
		after_data = data.duplicate(true)
		after_data["rarity"] = to_rarity
		after_data["stat_multiplier"] = float(route.get("stat_multiplier", 1.0))
	after_data["level"] = after_level
	var after_now := stats_of_data(after_data)
	after_data["level"] = Progression.LEVEL_MAX
	var after_max := stats_of_data(after_data)
	var rows: Array = []
	for stat in STATS:
		rows.append({
			"stat": stat, "label": StatBlock.label(stat),
			"now": float(now_stats[stat]), "after_now": float(after_now[stat]), "after_max": float(after_max[stat]),
			"now_text": value_text(stat, float(now_stats[stat])),
			"after_now_text": value_text(stat, float(after_now[stat])),
			"after_max_text": value_text(stat, float(after_max[stat])),
			"delta_text": delta_text(stat, float(after_now[stat]) - float(now_stats[stat])),
		})
	return {
		"kind": kind, "from": key, "to": to_id, "to_rarity": to_rarity,
		"after_level": after_level, "max_level": Progression.LEVEL_MAX, "rows": rows,
		"note": "La evolucion normal vuelve a nivel 1: la comparacion de la derecha es al nivel maximo." if kind == "normal" else "Hereda tu nivel actual y los Dupes.",
	}
