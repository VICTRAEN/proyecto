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
## --- TRANSFORMACION (X.5) -----------------------------------------------------------------------
## Definicion de la transformacion del personaje (primera entrada valida de "transformations" de
## su JSON). Vacia = el personaje no puede transformarse. Solo los ALIADOS la reciben.
var transformation: Dictionary = {}
var transformed := false
## Dominio del personaje (clave "domain" de su JSON; X.6). Vacio = no tiene. Solo los ALIADOS lo reciben.
var domain: Dictionary = {}
## Copia del estado original para volver a el al terminar el combate (o en las pruebas).
var _form_backup: Dictionary = {}
## --- Estado de combate v12 -------------------------------------------------
## Escudos: absorben dano ANTES que la vida. [{ amount, turns, source }]
var shields: Array = []
## Efectos periodicos: sangrado/quemadura/veneno (dano) y regeneracion (cura) al
## empezar el turno del portador. [{ kind, per_turn, turns, source }]
var periodics: Array = []
## Cargas de "ultimo aliento": cuando un golpe lo mataria, sobrevive. Cada carga se
## gasta una vez; undying_heal es la fraccion de vida maxima con la que se queda.
var undying := 0
var undying_heal := 0.0
## Reglas de LINKS que lleva esta unidad en ESTE combate (mismo formato que una
## pasiva con disparador). Las pone el BattleManager al empezar; no son pasivas del
## personaje, asi que no salen en su ficha.
var link_rules: Array = []
## X.2: reglas con disparador del objeto equipado (las monta el BattleManager al empezar).
var equipment_rules: Array = []
## Control de las reglas con disparador: id -> { used, next_round }.
var rule_state: Dictionary = {}
## True cuando ya se han resuelto las consecuencias de su caida (no se repiten).
var death_handled := false
## Lo que absorbio el escudo y si el ultimo golpe se sobrevivio por "ultimo aliento".
var last_absorbed := 0.0
var last_survived := false
## --- Jefes con fases (v14) -------------------------------------------------
## Datos del JSON del enemigo. Un enemigo sin "phases" ni "intro" se comporta
## exactamente como antes. phase_index = fases ya activadas; pattern = ciclo de
## acciones del jefe (lo cambia cada fase); pattern_step = por donde va.
var is_boss := false
var intro: Dictionary = {}
var phases: Array = []
var phase_index := 0
var pattern: Array = []
var pattern_step := 0


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
	is_boss = bool(data.get("boss", false)) or data.get("phases", []) is Array and not (data.get("phases", []) as Array).is_empty()
	var raw_intro = data.get("intro", {})
	intro = (raw_intro as Dictionary).duplicate(true) if raw_intro is Dictionary else {}
	phases = []
	var raw_phases = data.get("phases", [])
	if raw_phases is Array:
		for entry in raw_phases:
			if entry is Dictionary:
				phases.append((entry as Dictionary).duplicate(true))
	phase_index = 0
	var raw_pattern = data.get("pattern", [])
	pattern = (raw_pattern as Array).duplicate() if raw_pattern is Array else []
	pattern_step = 0
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
	transformation = {}
	transformed = false
	_form_backup = {}
	domain = {}
	var raw_domain = data.get("domain", {})
	if ally_flag and raw_domain is Dictionary and not String((raw_domain as Dictionary).get("id", "")).is_empty():
		domain = (raw_domain as Dictionary).duplicate(true)
	var raw_forms = data.get("transformations", [])
	if ally_flag and raw_forms is Array:
		for entry in raw_forms:
			if entry is Dictionary and not String((entry as Dictionary).get("id", "")).is_empty():
				# `min_rarity` (opcional): la transformacion solo existe a partir de esa FORMA. Un SSR que
				# aun no ha evolucionado a UR no la tiene (la rareza efectiva llega en data["rarity"]).
				var need := String((entry as Dictionary).get("min_rarity", ""))
				if not need.is_empty() and TRANSFORM_RARITY_ORDER.find(String(data.get("rarity", rarity))) < TRANSFORM_RARITY_ORDER.find(need):
					continue
				transformation = (entry as Dictionary).duplicate(true)
				break


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
	last_absorbed = 0.0
	last_survived = false
	var left := amount
	var index := 0
	while left > 0.0 and index < shields.size():
		var shield: Dictionary = shields[index]
		var absorbed := minf(float(shield["amount"]), left)
		shield["amount"] = float(shield["amount"]) - absorbed
		left -= absorbed
		last_absorbed += absorbed
		if float(shield["amount"]) <= 0.0:
			shields.remove_at(index)
		else:
			index += 1
	var dealt := minf(left, hp)
	hp = maxf(0.0, hp - left)
	if hp <= 0.0:
		if undying > 0:
			undying -= 1
			hp = maxf(1.0, max_hp() * undying_heal)
			last_survived = true
		else:
			alive = false
	return dealt


## --- Escudos y efectos periodicos --------------------------------------------

func shield_total() -> float:
	var total := 0.0
	for shield in shields:
		total += float(shield["amount"])
	return total


## Un escudo del mismo origen se SUSTITUYE (no se acumula): reaplicar la misma
## fuente refresca, igual que los modificadores de estadistica.
func add_shield(amount: float, turns: int, source: String) -> void:
	var kept: Array = []
	for shield in shields:
		if String(shield["source"]) != source:
			kept.append(shield)
	kept.append({ "amount": maxf(0.0, amount), "turns": turns, "source": source })
	shields = kept


func add_periodic(kind: String, per_turn: float, turns: int, source: String) -> void:
	var kept: Array = []
	for entry in periodics:
		if not (String(entry["source"]) == source and String(entry["kind"]) == kind):
			kept.append(entry)
	kept.append({ "kind": kind, "per_turn": per_turn, "turns": turns, "source": source })
	periodics = kept


const DAMAGE_PERIODICS := ["bleed", "burn", "poison"]
## Estados que BENEFICIAN a quien los lleva (la purga no los toca).
const BENEFICIAL_STATUSES := ["taunt"]


## Quita lo malo que caduca: debuffs de estadistica, estados (aturdimiento,
## provocacion...) y sangrado/quemadura/veneno. Devuelve cuantas cosas ha quitado.
func cleanse() -> int:
	var removed := stats.remove_temporary(false)
	var kept_statuses: Array = []
	for status in statuses:
		if BENEFICIAL_STATUSES.has(String(status["name"])):
			kept_statuses.append(status)
		else:
			removed += 1
	statuses = kept_statuses
	var kept: Array = []
	for entry in periodics:
		if DAMAGE_PERIODICS.has(String(entry["kind"])):
			removed += 1
		else:
			kept.append(entry)
	periodics = kept
	return removed


## Quita los buffs temporales (y escudos) de un rival.
func dispel() -> int:
	var removed := stats.remove_temporary(true)
	removed += shields.size()
	shields = []
	var kept: Array = []
	for entry in periodics:
		if String(entry["kind"]) == "regen":
			removed += 1
		else:
			kept.append(entry)
	periodics = kept
	return removed


func has_debuff() -> bool:
	for status in statuses:
		if not BENEFICIAL_STATUSES.has(String(status["name"])):
			return true
	for entry in periodics:
		if DAMAGE_PERIODICS.has(String(entry["kind"])):
			return true
	for mod in stats.mods:
		if int(mod["turns"]) > 0 and not StatBlock.mod_is_beneficial(String(mod["stat"]), float(mod["value"])):
			return true
	return false


func has_status(status_name: String) -> bool:
	for status in statuses:
		if String(status["name"]) == status_name:
			return true
	return false


## Fin de ronda: los escudos con duracion se gastan.
func tick_round() -> void:
	var kept: Array = []
	for shield in shields:
		var turns := int(shield["turns"])
		if turns <= 0:
			kept.append(shield)
			continue
		turns -= 1
		if turns > 0:
			shield["turns"] = turns
			kept.append(shield)
	shields = kept


## Reglas con disparador: las pasivas del personaje y las de sus links activos.
func rules_for_trigger(trigger: String) -> Array:
	var out: Array = passives_for_trigger(trigger)
	for rule in link_rules:
		if String(rule.get("trigger", "")) == trigger:
			out.append(rule)
	for rule in equipment_rules:
		if String(rule.get("trigger", "")) == trigger:
			out.append(rule)
	return out


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


## Sustituye (por "kind") o anade una habilidad. Lo usan las fases de jefe para
## desbloquear un especial nuevo sin tocar el personaje base.
func unlock_skill(skill: Dictionary) -> void:
	var kind := String(skill.get("kind", "special"))
	var fresh := skill.duplicate(true)
	for i in skills.size():
		if String(skills[i].get("kind", "")) == kind:
			skills = skills.duplicate()
			skills[i] = fresh
			return
	skills = skills.duplicate()
	skills.append(fresh)


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
			"positive": StatBlock.mod_is_beneficial(String(mod.get("stat", "")), value),
			"origin": _origin_label(source),
		})
	if shield_total() > 0.0:
		var longest := 0
		for shield in shields:
			longest = maxi(longest, int(shield["turns"]))
		effects.append({
			"source_kind": "shield", "key": "shield", "value": shield_total(),
			"mod_kind": "shield", "turns": longest, "positive": true, "origin": "",
		})
	for entry in periodics:
		effects.append({
			"source_kind": "periodic", "key": String(entry["kind"]), "value": float(entry["per_turn"]),
			"mod_kind": "periodic", "turns": int(entry["turns"]),
			"positive": String(entry["kind"]) == "regen", "origin": "",
		})
	if undying > 0:
		effects.append({
			"source_kind": "undying", "key": "undying", "value": float(undying),
			"mod_kind": "undying", "turns": 0, "positive": true, "origin": "",
		})
	for status in statuses:
		effects.append({
			"source_kind": "status",
			"key": String(status.get("name", "")),
			"value": 0.0,
			"mod_kind": "status",
			"turns": int(status.get("turns", 0)),
			"positive": BENEFICIAL_STATUSES.has(String(status.get("name", ""))),
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
	if source.begins_with("link:"):
		return "Link"
	if source.begins_with("equip"):
		return "Objeto"
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


## --- TRANSFORMACION (X.5) ---------------------------------------------------------------------
## Todo lo que cambia sale del JSON de la transformacion (data/SCHEMA.md, "Transformaciones"):
## estadisticas (stat_multiplier + stat_mods), habilidades (por tipo), pasivas, arte, nombre, tipo y
## demas. Se aplica sobre ESTA unidad de combate y nunca sobre el personaje guardado.
const TRANSFORM_RARITY_ORDER := ["N", "R", "SR", "SSR", "UR", "LR"]
const TRANSFORM_CORE_STATS := ["max_hp", "atk", "def", "speed"]
const TRANSFORM_SOURCE_MULT := "transform:mult"
const TRANSFORM_SOURCE_EXTRA := "transform:extra"
const TRANSFORM_DEFAULT_FORM := "transform"


func has_transformation() -> bool:
	return not transformation.is_empty()


func can_transform() -> bool:
	return alive and is_ally and has_transformation() and not transformed


## Ataque especial que se hace al transformarse (el del JSON, o uno por defecto).
func transform_attack() -> Dictionary:
	var attack = transformation.get("attack", {})
	var out: Dictionary = (attack as Dictionary).duplicate(true) if attack is Dictionary and not (attack as Dictionary).is_empty() else {
		"id": "sk_%s_attack" % String(transformation.get("id", "transform")),
		"name": String(transformation.get("name", "Transformacion")),
		"power": 150, "target": "enemy_all", "effects": [],
		"description": "Un ataque especial al transformarse.",
	}
	out["kind"] = "special"
	out["cost"] = 0
	return out


func transform_form_key() -> String:
	return String(transformation.get("form", TRANSFORM_DEFAULT_FORM))


## Forma visual para el retrato: la de la transformacion mientras dura, o "" (la del personaje).
func visual_form() -> String:
	return transform_form_key() if transformed else ""


func apply_transformation() -> bool:
	if not can_transform():
		return false
	var d := transformation
	_form_backup = {
		"display_name": display_name, "type": type, "portrait_style": portrait_style, "art": art.duplicate(true),
		"roles": roles, "categories": categories, "skills": skills.duplicate(true), "passives": passives.duplicate(true),
		"passive": passive, "ultimate": ultimate.duplicate(true), "ultimate_used": ultimate_used,
		"pattern": pattern.duplicate(), "rule_state": rule_state.duplicate(true), "undying": undying, "undying_heal": undying_heal,
	}
	var old_max := max_hp()
	var multiplier := float(d.get("stat_multiplier", 1.0))
	if multiplier != 1.0:
		for stat_name in TRANSFORM_CORE_STATS:
			stats.add_mod(stat_name, "mult", multiplier - 1.0, TRANSFORM_SOURCE_MULT)
	var extra = d.get("stat_mods", [])
	if extra is Array:
		for mod in extra:
			if mod is Dictionary and not String((mod as Dictionary).get("stat", "")).is_empty():
				stats.add_mod(String(mod["stat"]), String(mod.get("kind", "mult")), float(mod.get("value", 0.0)), "%s:%s" % [TRANSFORM_SOURCE_EXTRA, String(mod["stat"])])
	# La vida actual sube lo que sube la maxima (como cualquier mejora de vida maxima).
	var new_max := max_hp()
	if new_max > old_max:
		hp = minf(new_max, hp + (new_max - old_max))
	var heal_ratio := float(d.get("heal_ratio", 0.0))
	if heal_ratio > 0.0:
		hp = minf(new_max, hp + roundf(new_max * heal_ratio))
	if not String(d.get("name", "")).is_empty():
		display_name = String(d["name"])
	if not String(d.get("type", "")).is_empty():
		type = String(d["type"])
	if not String(d.get("portrait_style", "")).is_empty():
		portrait_style = String(d["portrait_style"])
	var new_art = d.get("art", {})
	if new_art is Dictionary:
		for slot_name in (new_art as Dictionary):
			art[String(slot_name)] = String(new_art[slot_name])
	if d.get("roles", null) is Array:
		roles = d["roles"]
	if d.get("categories", null) is Array:
		categories = d["categories"]
	# Habilidades: las que declara sustituyen a las del mismo tipo (basic / special) y se anaden si no hay.
	var new_skills = d.get("skills", [])
	if new_skills is Array:
		for skill in new_skills:
			if skill is Dictionary:
				unlock_skill(skill)
	var new_passives: Array = []
	if d.get("passives", null) is Array:
		for entry in d["passives"]:
			if entry is Dictionary and not (entry as Dictionary).is_empty():
				new_passives.append((entry as Dictionary).duplicate(true))
	elif d.get("passive", null) is Dictionary and not (d["passive"] as Dictionary).is_empty():
		new_passives.append((d["passive"] as Dictionary).duplicate(true))
	if not new_passives.is_empty():
		passives = new_passives
		passive = new_passives[0]
	if d.get("ultimate", null) is Dictionary and not (d["ultimate"] as Dictionary).is_empty():
		ultimate = (d["ultimate"] as Dictionary).duplicate(true)
		ultimate_used = false
	if d.get("pattern", null) is Array:
		pattern = (d["pattern"] as Array).duplicate()
		pattern_step = 0
	transformed = true
	return true


## Vuelve al estado original (fin del combate). Conserva la proporcion de vida y si esta vivo.
func revert_transformation() -> void:
	if not transformed:
		return
	var ratio := hp_ratio()
	stats.remove_source(TRANSFORM_SOURCE_MULT)
	var extra = transformation.get("stat_mods", [])
	if extra is Array:
		for mod in extra:
			if mod is Dictionary:
				stats.remove_source("%s:%s" % [TRANSFORM_SOURCE_EXTRA, String((mod as Dictionary).get("stat", ""))])
	# Efectos que dejaron las pasivas de la forma (p. ej. un buff de ataque): salen con ella.
	var form_rule_ids: Array = []
	for rule in passives:
		if rule is Dictionary and not String((rule as Dictionary).get("id", "")).is_empty():
			form_rule_ids.append(String(rule["id"]))
	if not form_rule_ids.is_empty():
		var original_ids: Array = []
		for rule in (_form_backup["passives"] as Array):
			if rule is Dictionary:
				original_ids.append(String((rule as Dictionary).get("id", "")))
		var kept_mods: Array = []
		for mod in stats.mods:
			var src := String(mod["source"])
			var from_form := false
			for rid in form_rule_ids:
				if not original_ids.has(rid) and src.begins_with("passive:") and src.find(String(rid)) != -1:
					from_form = true
			if not from_form:
				kept_mods.append(mod)
		stats.mods = kept_mods
	display_name = String(_form_backup["display_name"])
	type = String(_form_backup["type"])
	portrait_style = String(_form_backup["portrait_style"])
	art = (_form_backup["art"] as Dictionary).duplicate(true)
	roles = _form_backup["roles"]
	categories = _form_backup["categories"]
	skills = (_form_backup["skills"] as Array).duplicate(true)
	passives = (_form_backup["passives"] as Array).duplicate(true)
	passive = _form_backup["passive"]
	ultimate = (_form_backup["ultimate"] as Dictionary).duplicate(true)
	ultimate_used = bool(_form_backup["ultimate_used"])
	pattern = (_form_backup["pattern"] as Array).duplicate()
	pattern_step = 0
	# Lo que la forma dejo atras (cargas de 'no morir', cuentas de sus pasivas) se va con ella.
	undying = int(_form_backup.get("undying", 0))
	undying_heal = float(_form_backup.get("undying_heal", 0.0))
	rule_state = (_form_backup.get("rule_state", {}) as Dictionary).duplicate(true)
	if alive:
		hp = maxf(1.0, roundf(max_hp() * ratio))
	transformed = false
	_form_backup = {}


## --- Dominio (X.6) -------------------------------------------------------------
## La definicion vive en el JSON del personaje (data/SCHEMA.md, "Bloque de dominio"). Lo que
## cambia (fondo, bonus y penalizaciones por categoria) lo aplica el BattleManager; aqui solo se
## guarda la definicion y se contesta "puede abrirlo?".

func has_domain() -> bool:
	return not domain.is_empty()


func domain_cost() -> int:
	return maxi(0, int(domain.get("cost", 0)))


func can_open_domain() -> bool:
	return alive and is_ally and has_domain() and sp >= domain_cost()


## Ataque opcional que acompana a la expansion (mismo formato que el de la transformacion). {} = ninguno.
func domain_attack() -> Dictionary:
	var raw = domain.get("attack", {})
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return {}
	var out: Dictionary = (raw as Dictionary).duplicate(true)
	if String(out.get("id", "")).is_empty():
		out["id"] = "%s_attack" % String(domain.get("id", "domain"))
	if String(out.get("name", "")).is_empty():
		out["name"] = String(domain.get("name", "Dominio"))
	out["kind"] = "special"
	out["cost"] = 0
	if not out.has("power"):
		out["power"] = 120
	if not out.has("target"):
		out["target"] = "enemy_all"
	if not out.has("effects"):
		out["effects"] = []
	return out

