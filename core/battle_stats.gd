extends RefCounted
class_name BattleStats

## Contadores dinamicos de UNA unidad durante UNA batalla.
##
## Esto NO es parte del personaje: el JSON solo guarda datos estaticos (name,
## type, stats, passive, art...). Aqui se guarda lo que HA PASADO en el combate,
## y se crea uno nuevo al empezar otra batalla (ver CombatUnit.setup).
##
## Anadir un contador nuevo es una linea en DISPLAY: la UI recorre esa lista
## para pintar la seccion de estadisticas, asi que no hay que tocar el panel.
##
## Regla del proyecto: un contador solo sube cuando la accion ha ocurrido de
## verdad (BattleManager._record_stats). Aqui no se inventa ningun numero.

const GROUPS := [
	{ "id": "attack", "label": "ATAQUE" },
	{ "id": "defense", "label": "DEFENSA" },
	{ "id": "support", "label": "APOYO" },
]

## key      -> nombre interno del contador
## label    -> texto que se pinta
## group    -> bloque de la lista
const DISPLAY := [
	{ "key": "basic_attacks", "label": "Ataques basicos", "group": "attack" },
	{ "key": "specials", "label": "Supers realizadas", "group": "attack" },
	{ "key": "damage_dealt", "label": "Dano total hecho", "group": "attack" },
	{ "key": "hits_dealt", "label": "Golpes realizados", "group": "attack" },
	{ "key": "crits", "label": "Criticos realizados", "group": "attack" },
	{ "key": "damage_received", "label": "Dano recibido", "group": "defense" },
	{ "key": "hits_received", "label": "Golpes recibidos", "group": "defense" },
	{ "key": "dodges", "label": "Esquivas", "group": "defense" },
	{ "key": "mitigations", "label": "Mitigaciones", "group": "defense" },
	{ "key": "healing_done", "label": "Curaciones hechas", "group": "support" },
	{ "key": "healing_received", "label": "Curaciones recibidas", "group": "support" },
	{ "key": "buffs_applied", "label": "Buffs aplicados", "group": "support" },
	{ "key": "debuffs_applied", "label": "Debuffs aplicados", "group": "support" },
]

## "mitigations" queda definido y a cero: el combate actual no tiene bloqueo
## discreto (la defensa se resta al dano), asi que nadie lo incrementa. Cuando
## exista un escudo o un bloqueo real, se suma aqui y ya sale en el panel.

var counters: Dictionary = {}


func _init() -> void:
	reset()


## Vuelve a cero. Se llama al construir la unidad para una batalla nueva.
func reset() -> void:
	counters.clear()
	for entry in DISPLAY:
		counters[String(entry["key"])] = 0


func add(key: String, amount: int = 1) -> void:
	if amount == 0:
		return
	counters[key] = int(counters.get(key, 0)) + amount


func value(key: String) -> int:
	return int(counters.get(key, 0))


## Bloques ya preparados para pintar: [{ group, items: [{ label, value }] }].
## Los bloques sin ningun contador definido se omiten.
func rows() -> Array:
	var out: Array = []
	for group in GROUPS:
		var items: Array = []
		for entry in DISPLAY:
			if String(entry["group"]) != String(group["id"]):
				continue
			items.append({
				"label": String(entry["label"]),
				"value": value(String(entry["key"])),
			})
		if items.is_empty():
			continue
		out.append({ "group": String(group["label"]), "items": items })
	return out


func snapshot() -> Dictionary:
	return counters.duplicate(true)
