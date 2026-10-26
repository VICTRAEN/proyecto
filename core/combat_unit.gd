extends RefCounted

const StatBlock := preload("res://core/stat_block.gd")
const BattleStats := preload("res://core/battle_stats.gd")

## Una unidad dentro de un combate: se construye a partir de un diccionario de
## datos (JSON) y anade el estado vivo, HP, SP y estados alterados.
## El mismo objeto sirve para aliados y enemigos.
##
## V0.3: cada unidad lleva sus contadores de batalla (battle). Son estado de la
## BATALLA, no del personaje: se crean aqui y desaparecen al construir otra
## unidad, asi que el JSON del personaje nunca se ensucia con resultados.

## Tope de SP. La barra de SP de la tarjeta y el panel de informacion pintan
## este mismo numero.
const SP_MAX := 3

var id := ""
var display_name := ""
var is_ally := true
var rarity := "R"
## Nivel del personaje en esta batalla. Sale del estado del jugador (GameState),
## que es quien lo sube; el JSON del personaje solo guarda su identidad.
var level := 1
var type := "STR"
var portrait_style := "short"
## Rutas de arte por ranura: front (de frente, para el rival), back (de espaldas,
## para las unidades del jugador), icon (cara, para barras y menus). Una ruta
## vacia significa "usa la convencion res://art/characters/<id>/<ranura>.png".
## Ver ui/portrait.gd.
var art: Dictionary = {}
var roles: Array = []
var categories: Array = []
## Pasiva PRINCIPAL de la unidad. Es la que ensenan la ficha y el registro del
## combate, y siempre es la primera de "passives".
var passive: Dictionary = {}
## TODAS las pasivas activas. Un personaje normal lleva una; uno que ha
## evolucionado a UR lleva la pasiva mejorada mas la segunda que anade su bloque
## de evolucion. GameState.character_data(id) entrega la lista ya resuelta, asi
## que esto no sabe nada de rarezas ni de evoluciones.
var passives: Array = []
var skills: Array = []
var stats: StatBlock = null
var hp := 1.0
var sp := 0
var alive := true
var statuses: Array = []
var source_key := ""
var slot := 0
## Contadores dinamicos de esta batalla (core/battle_stats.gd).
var battle: BattleStats = null


func setup(data: Dictionary, ally_flag: bool, slot_index: int) -> void:
	id = String(data.get("id", "desconocido"))
	display_name = String(data.get("name", id))
	is_ally = ally_flag
	rarity = String(data.get("rarity", "R"))
	type = String(data.get("type", "STR"))
	portrait_style = String(data.get("portrait_style", "short"))
	var art_data = data.get("art", {})
	art = art_data if art_data is Dictionary else {}
	roles = data.get("roles", [])
	categories = data.get("categories", [])
	# La lista "passives" la monta GameState (pasiva base, o pasiva de evolucion
	# mas la segunda). Si el diccionario solo trae "passive" (enemigos, o datos
	# sin pasar por GameState) se usa esa, asi que nada deja de funcionar.
	passive = data.get("passive", {})
	passives = []
	var loaded_passives = data.get("passives", [])
	if loaded_passives is Array:
		for entry in loaded_passives:
			if entry is Dictionary and not entry.is_empty():
				passives.append(entry)
	if passives.is_empty() and passive is Dictionary and not passive.is_empty():
		passives.append(passive)
	skills = data.get("skills", [])
	# ULTIMATE de forma (solo la trae GameState.character_data si el personaje esta en
	# la forma que la declara, p. ej. el LR del duo). Un enemigo o un personaje en
	# otra forma llega sin ella: ultimate vacia = no tiene.
	var loaded_ultimate = data.get("ultimate", {})
	ultimate = (loaded_ultimate as Dictionary).duplicate(true) if loaded_ultimate is Dictionary else {}
	ultimate_used = false
	slot = slot_index
	source_key = "%s#%d" % [id, slot_index]
	# El nivel que trae el diccionario viene del estado del jugador (GameState),
	# no del JSON del personaje. StatBlock lo usa para escalar las estadisticas.
	level = maxi(1, int(data.get("level", 1)))
	stats = StatBlock.new(data.get("stats", {}), level)
	# Paso de RAREZA del calculo: un personaje evolucionado pega mas fuerte con las
	# mismas estadisticas de JSON. El multiplicador viene de los datos (la ruta de
	# evolucion) ya resuelto por GameState.character_data; una unidad sin evolucionar
	# o un enemigo (que no trae el campo) valen 1.0 y no cambian.
	stats.rarity_mult = maxf(0.01, float(data.get("stat_multiplier", 1.0)))
	# DUPES: bonus permanente del personaje, como modificadores de origen "dupe".
	# GameState.character_data los trae ya resueltos; un enemigo no trae ninguno. Se
	# aplican AQUI, una vez por unidad construida, y add_mod sustituye por origen:
	# abrir menus o cargar partidas no puede acumularlos.
	var dupe_mods = data.get("dupe_mods", [])
	if dupe_mods is Array:
		for mod in dupe_mods:
			if mod is Dictionary:
				stats.add_mod(String(mod["stat"]), String(mod["kind"]), float(mod["value"]), String(mod.get("source", "dupe")))
	battle = BattleStats.new()
	hp = max_hp()


## Ruta de arte explicita para una ranura ("front", "back", "icon"), o "" si el
## JSON no la define y debe usarse la convencion de carpetas.
func art_for(slot_name: String) -> String:
	return String(art.get(slot_name, ""))


## Valor base de una estadistica, el del JSON, sin pasivas ni buffs. El panel de
## informacion pinta "Base" con esto y "Actual" con el getter de la estadistica,
## que es el mismo numero que usa el motor de combate.
func base_stat(stat_name: String) -> float:
	return stats.base_value(stat_name)


## Nombres legibles de los objetivos posibles de una habilidad.
const TARGET_LABELS := {
	"enemy": "Un rival",
	"enemy_all": "Todos los rivales",
	"ally": "Un aliado",
	"ally_all": "Todo el equipo",
	"ally_lowest": "El aliado mas debil",
	"self": "Uno mismo",
}


## Habilidad del tipo pedido ya aplanada para la interfaz: nombre, coste, texto y
## a quien afecta. Asi el panel no lee claves del JSON ni conoce su estructura.
func skill_info(kind: String) -> Dictionary:
	var skill := skill_by_kind(kind)
	if skill.is_empty():
		return {}
	var target := String(skill.get("target", "enemy"))
	return {
		"name": String(skill.get("name", kind)),
		"cost": int(skill.get("cost", 0)),
		"description": String(skill.get("description", "")),
		"target": target,
		"target_label": String(TARGET_LABELS.get(target, target)),
	}


func max_hp() -> float:
	return stats.get_stat("max_hp")


func attack() -> float:
	return stats.get_stat("atk")


func defense() -> float:
	return stats.get_stat("def")


func speed() -> float:
	return stats.get_stat("speed")


## Pasan por StatBlock, no por stats.base: asi una pasiva o un buff pueden
## modificar critico y esquiva como cualquier otra estadistica.
func crit_rate() -> float:
	return stats.get_stat("crit_rate")


func dodge_rate() -> float:
	return stats.get_stat("dodge_rate")


func hp_ratio() -> float:
	var maximum := max_hp()
	if maximum <= 0.0:
		return 0.0
	return clampf(hp / maximum, 0.0, 1.0)


func take_damage(amount: float) -> float:
	var dealt := minf(amount, hp)
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		alive = false
	return dealt


func heal(amount: float) -> float:
	if not alive:
		return 0.0
	var before := hp
	hp = minf(max_hp(), hp + amount)
	return hp - before


func gain_sp(amount: int) -> void:
	sp = clampi(sp + amount, 0, SP_MAX)


func is_stunned() -> bool:
	for status in statuses:
		if String(status["name"]) == "stun":
			return true
	return false


func add_status(status_name: String, turns: int) -> void:
	for status in statuses:
		if String(status["name"]) == status_name:
			status["turns"] = maxi(int(status["turns"]), turns)
			return
	statuses.append({ "name": status_name, "turns": turns })


func tick_statuses() -> void:
	var kept: Array = []
	for status in statuses:
		status["turns"] = int(status["turns"]) - 1
		if int(status["turns"]) > 0:
			kept.append(status)
	statuses = kept


## Devuelve la habilidad del tipo pedido ("basic" o "special") o {} si no existe.
## Ultimate de esta unidad en ESTE combate. Cada CombatUnit se construye de nuevo al
## empezar una batalla, asi que `ultimate_used` vuelve a false solo en el combate
## siguiente y nunca depende de pantallas ni de turnos.
var ultimate: Dictionary = {}
var ultimate_used := false


func has_ultimate() -> bool:
	return not ultimate.is_empty()


func skill_by_kind(kind: String) -> Dictionary:
	if kind == "ultimate":
		return ultimate
	for skill in skills:
		if String(skill.get("kind", "")) == kind:
			return skill
	return {}


func has_passive() -> bool:
	return not passive.is_empty()


func passive_name() -> String:
	return String(passive.get("name", "Sin pasiva"))


func passive_description() -> String:
	return String(passive.get("description", ""))


## Pasivas que deben dispararse con un trigger ("turn_start", "battle_start").
## Un personaje evolucionado devuelve dos; el resto, una.
func passives_for_trigger(trigger: String) -> Array:
	var out: Array = []
	for entry in passives:
		if String(entry.get("trigger", "")) == trigger:
			out.append(entry)
	return out


## Textos de todas las pasivas, en orden. Es lo que permite que una pantalla
## ensene varias sin saber cuantas hay.
func passive_texts() -> Array:
	var out: Array = []
	for entry in passives:
		out.append({
			"id": String(entry.get("id", "")),
			"name": String(entry.get("name", "Sin pasiva")),
			"description": String(entry.get("description", "")),
		})
	return out


## Efectos temporales vivos (modificadores de estadistica y estados) en formato
## de DATOS, para que la UI los pinte sin conocer las reglas del combate.
## Anadir un tipo de efecto nuevo al EffectEngine no obliga a tocar esta funcion
## mientras termine en un stat_mod o en un status.
##
## Devuelve: [{ source_kind: "stat"|"status", key, value, mod_kind,
##              turns, positive, origin }]
func active_effects() -> Array:
	var effects: Array = []
	for mod in stats.active_mods():
		var value := float(mod.get("value", 0.0))
		var source := String(mod.get("source", ""))
		effects.append({
			"source_kind": "stat",
			"key": String(mod.get("stat", "")),
			"value": value,
			"mod_kind": String(mod.get("kind", "mult")),
			"turns": int(mod.get("turns", 0)),
			"positive": value >= 0.0,
			"origin": _origin_label(source),
		})
	for status in statuses:
		effects.append({
			"source_kind": "status",
			"key": String(status.get("name", "")),
			"value": 0.0,
			"mod_kind": "status",
			"turns": int(status.get("turns", 0)),
			"positive": false,
			"origin": "",
		})
	return effects


## "passive:pas_gojo_infinito@gojo#0" -> "Pasiva". El nombre interno de la fuente
## se queda en core; la UI solo pinta la etiqueta.
func _origin_label(source: String) -> String:
	if source.begins_with("passive:"):
		return "Pasiva"
	if source.begins_with("skill:"):
		return "Habilidad"
	return ""


func roles_text() -> String:
	var parts := PackedStringArray()
	for role in roles:
		parts.append(String(role))
	return ", ".join(parts)


func status_text() -> String:
	var parts := PackedStringArray()
	for status in statuses:
		parts.append(String(status["name"]))
	return ", ".join(parts)
