extends RefCounted

const Progression := preload("res://core/progression.gd")
const BattleMath := preload("res://core/battle_math.gd")

## AUTOCONFIGURACION DE EQUIPOS (v12). Dado lo que el jugador tiene y lo que pide el
## contenido (personaje obligatorio, tamano, tipos de los enemigos), propone un
## equipo y explica POR QUE. No modifica nada: devuelve una propuesta que el
## jugador puede cambiar antes de combatir.
##
## Puntuacion = poder individual x (1 + sinergias):
##   - niveles de LINK alcanzados (los mismos que aplica el combate),
##   - mezcla de roles (algun soporte/tanque/sanador y al menos 2 de dano),
##   - ventaja de tipo frente a los enemigos del contenido,
##   - Leader Skill de la posicion 1 (a cuantos del equipo alcanza).
## Todo sale de los datos (estadisticas, links, roles, tipos y lideres): no hay ninguna
## regla por personaje.

const POOL_LIMIT := 16
const LINK_TIER_BONUS := 0.05
const ROLE_SUPPORT_BONUS := 0.06
const ROLE_DAMAGE_BONUS := 0.04
const NO_DAMAGE_PENALTY := 0.12
const TYPE_ADVANTAGE_BONUS := 0.03
const TYPE_DISADVANTAGE_PENALTY := 0.02
const LEADER_BONUS_SCALE := 0.25


## Poder individual de un personaje con SU nivel y forma actuales.
static func member_power(id: String) -> float:
	var data: Dictionary = GameState.character_data(id)
	if data.is_empty():
		return 0.0
	var stats: Dictionary = data.get("stats", {})
	var growth := Progression.growth_factor(int(data.get("level", 1))) * float(data.get("stat_multiplier", 1.0))
	var atk := float(stats.get("atk", 0.0)) * growth
	var defense := float(stats.get("def", 0.0)) * growth
	var hp := float(stats.get("max_hp", 0.0)) * growth
	var crit := float(stats.get("crit_rate", 0.0))
	return atk * (1.0 + crit * 0.6) + hp / 8.0 + defense * 1.5


## Evalua un equipo. Devuelve { score, power, parts: [textos], leader }.
static func evaluate(members: Array, enemy_types: Array = []) -> Dictionary:
	var power := 0.0
	var links := {}
	var roles := {}
	var types: Array = []
	var datas: Array = []
	for id in members:
		var key := String(id)
		if key.is_empty():
			continue
		var data: Dictionary = GameState.character_data(key)
		datas.append(data)
		power += member_power(key)
		for link_id in data.get("links", []):
			links[String(link_id)] = int(links.get(String(link_id), 0)) + 1
		for role in data.get("roles", []):
			roles[String(role)] = int(roles.get(String(role), 0)) + 1
		types.append(String(data.get("type", "")))
	var parts: Array = []
	var bonus := 0.0
	# Links: los mismos niveles que usara el combate.
	for link_id in links.keys():
		var tier := GameState.link_tier_reached(String(link_id), int(links[link_id]))
		if tier > 0:
			bonus += LINK_TIER_BONUS * float(tier)
			parts.append("Link %s nivel %d (%d portadores)" % [String(DB.get_link(String(link_id)).get("name", link_id)), tier, int(links[link_id])])
	# Roles.
	var damage := int(roles.get("Damage Dealer", 0))
	var support_like := int(roles.get("Support", 0)) + int(roles.get("Tank", 0)) + int(roles.get("Healer", 0))
	if damage == 0 and members.size() > 1:
		bonus -= NO_DAMAGE_PENALTY
		parts.append("Sin personajes de dano")
	else:
		if damage >= 2 or members.size() <= 2:
			bonus += ROLE_DAMAGE_BONUS
		if support_like >= 1 and members.size() > 2:
			bonus += ROLE_SUPPORT_BONUS
			parts.append("Equipo equilibrado: dano + apoyo/aguante")
	# Tipos frente a los enemigos del contenido.
	var advantages := 0
	var disadvantages := 0
	for own_type in types:
		for enemy_type in enemy_types:
			var mult := BattleMath.type_multiplier(String(own_type), String(enemy_type))
			if mult > 1.0:
				advantages += 1
			elif mult < 1.0:
				disadvantages += 1
	if not enemy_types.is_empty():
		bonus += TYPE_ADVANTAGE_BONUS * float(advantages) - TYPE_DISADVANTAGE_PENALTY * float(disadvantages)
		if advantages > 0:
			parts.append("%d ventaja(s) de tipo frente a los enemigos" % advantages)
	# Leader Skill del que ocupe la posicion 1.
	var leader_id := String(members[0]) if not members.is_empty() else ""
	var leader_gain := leader_value(leader_id, members)
	if leader_gain > 0.0:
		bonus += leader_gain
		var leader := DB.leader_for(leader_id)
		parts.append("Lider %s: %s" % [GameState.display_name(leader_id), String(leader.get("name", ""))])
	return { "score": power * (1.0 + bonus), "power": power, "parts": parts, "leader": leader_id }


## Valor de la Leader Skill de `leader_id` para este equipo: a cuantos alcanza y
## cuanto da (suma de sus bonos porcentuales).
static func leader_value(leader_id: String, members: Array) -> float:
	if leader_id.is_empty():
		return 0.0
	var leader := DB.leader_for(leader_id)
	if leader.is_empty():
		return 0.0
	var condition: Dictionary = leader.get("condition", {})
	var field := String(condition.get("field", "all"))
	var wanted := String(condition.get("value", ""))
	var affected := 0
	var total := 0
	for id in members:
		var key := String(id)
		if key.is_empty():
			continue
		total += 1
		var data: Dictionary = GameState.character_data(key)
		var applies := true
		if field == "type":
			applies = String(data.get("type", "")) == wanted
		elif field == "category":
			applies = (data.get("categories", []) as Array).has(wanted)
		if applies:
			affected += 1
	if total == 0:
		return 0.0
	var magnitude := 0.0
	for effect in leader.get("effects", []):
		if effect is Dictionary and String(effect.get("type", "")) == "stat_mod":
			magnitude += float(effect.get("value", 0.0))
	# Normalizado: un +25% a todo (3 stats) en 4 aliados ~ el tope.
	return LEADER_BONUS_SCALE * (float(affected) / float(total)) * minf(1.0, magnitude / 0.75)


## Propone el mejor equipo de `size` puestos entre `candidates`.
## opts: { size, required (id que tiene que ir), solo (true = solo el requerido),
##         enemy_types: [tipos] }
## Devuelve { ok, members (lider primero), score, parts, reason }.
static func suggest(candidates: Array, opts: Dictionary = {}) -> Dictionary:
	var size := int(opts.get("size", 4))
	var required := String(opts.get("required", ""))
	var enemy_types: Array = opts.get("enemy_types", [])
	if bool(opts.get("solo", false)) and not required.is_empty():
		if not candidates.has(required):
			return { "ok": false, "members": [], "score": 0.0, "parts": [], "reason": "No tienes al personaje que pide este combate." }
		return { "ok": true, "members": [required], "score": member_power(required), "parts": ["Combate de un solo personaje"], "reason": "" }
	if not required.is_empty() and not candidates.has(required):
		return { "ok": false, "members": [], "score": 0.0, "parts": [], "reason": "No tienes al personaje que pide este combate." }
	if candidates.is_empty():
		return { "ok": false, "members": [], "score": 0.0, "parts": [], "reason": "No tienes personajes." }
	var ranked: Array = []
	for id in candidates:
		ranked.append([String(id), member_power(String(id))])
	ranked.sort_custom(func(a, b): return a[1] > b[1])
	var pool: Array = []
	for row in ranked:
		if pool.size() >= POOL_LIMIT:
			break
		pool.append(row[0])
	if not required.is_empty() and not pool.has(required):
		pool.append(required)
	var take := mini(size, pool.size())
	var best: Array = []
	var best_score := -1.0
	var best_eval: Dictionary = {}
	# Combinaciones de `take` entre el pool (como mucho C(17,5) = 6188).
	var combos: Array = []
	_combinations(pool, take, 0, [], combos)
	for chosen in combos:
		if not required.is_empty() and not chosen.has(required):
			continue
		var ordered := _leader_first(chosen)
		var result := evaluate(ordered, enemy_types)
		if float(result["score"]) > best_score:
			best_score = float(result["score"])
			best = ordered
			best_eval = result
	if best.is_empty():
		return { "ok": false, "members": [], "score": 0.0, "parts": [], "reason": "No se ha podido montar un equipo." }
	return { "ok": true, "members": best, "score": best_score, "parts": best_eval.get("parts", []), "reason": "" }


static func _combinations(pool: Array, take: int, start: int, current: Array, out: Array) -> void:
	if current.size() == take:
		out.append(current.duplicate())
		return
	for i in range(start, pool.size()):
		current.append(pool[i])
		_combinations(pool, take, i + 1, current, out)
		current.pop_back()


## Ordena el equipo: primero quien mas aporta como lider, luego por poder.
static func _leader_first(chosen: Array) -> Array:
	var best_id := ""
	var best_value := -1.0
	for id in chosen:
		var value := leader_value(String(id), chosen) + member_power(String(id)) * 0.00001
		if value > best_value:
			best_value = value
			best_id = String(id)
	var rest: Array = []
	for id in chosen:
		if String(id) != best_id:
			rest.append([String(id), member_power(String(id))])
	rest.sort_custom(func(a, b): return a[1] > b[1])
	var out: Array = [best_id]
	for row in rest:
		out.append(row[0])
	return out
