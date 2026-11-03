extends RefCounted

## OBJETOS EQUIPABLES (X.2).
##
## Los datos viven en data/equipment/<id>.json (rareza, descripcion, pasiva visible y
## "rules" con el MISMO formato que las pasivas y los links: trigger static / battle_start /
## turn_start / on_hit / on_attack / on_crit / on_special / on_dodge / on_kill / low_hp ...).
## Esta clase NO sabe de efectos concretos: solo guarda que tienes y que lleva cada
## personaje, valida las reglas de equipar y entrega las reglas al combate. El motor de
## efectos (core/effect_engine.gd) y las estadisticas (core/stat_block.gd) siguen siendo
## los unicos que calculan nada, asi que cambiar un objeto es editar su JSON.
##
## Estado guardado (aditivo, SAVE_VERSION igual):
##   owned    { item_id: cantidad }      objetos que tienes (con repetidos)
##   equipped { character_id: item_id }  que lleva cada personaje
##
## Reglas:
##   - Un objeto no evoluciona: su rareza es siempre la de su JSON.
##   - Solo se equipa lo que se posee y hay tantos portadores como copias.
##   - Dos companeros del MISMO equipo (party o torre) no pueden llevar el mismo objeto.
##   - Los efectos NO se guardan: se montan en cada CombatUnit al empezar la batalla, asi
##     que cambiar de equipo, entrar en combate o cargar partida nunca los acumula.

const RARITIES := ["N", "R", "SR", "SSR", "UR", "LR"]

var gs = null
var owned: Dictionary = {}
var equipped: Dictionary = {}


func _init(owner = null) -> void:
	gs = owner


## --- Catalogo ---------------------------------------------------------------------

static func data_of(item_id: String) -> Dictionary:
	return DB.get_equipment(item_id)


## DOS familias de objetos, separadas a proposito:
##   - EQUIPABLES (esto, data/equipment): se llevan puestos y NO sirven para evolucionar.
##   - EVOLUTIVOS (data/items, "kind": "evolutive", ej. Uniforme de conejita): suben de
##     rareza a un personaje y NO se pueden equipar.
## Sus catalogos, inventarios y recompensas ("items" vs "equipment") no se mezclan.
static func is_evolutive(item_id: String) -> bool:
	return DB.items.has(String(item_id)) and not DB.equipment.has(String(item_id))


static func exists(item_id: String) -> bool:
	return not data_of(item_id).is_empty()


static func name_of(item_id: String) -> String:
	return String(data_of(item_id).get("name", item_id))


## Rareza FIJA del objeto (nunca cambia: los objetos no evolucionan).
static func rarity_of(item_id: String) -> String:
	return String(data_of(item_id).get("rarity", "N"))


static func rarity_rank(rarity: String) -> int:
	return RARITIES.find(rarity)


## --- Inventario -----------------------------------------------------------------------

func count_of(item_id: String) -> int:
	return maxi(0, int(owned.get(String(item_id), 0)))


func owns(item_id: String) -> bool:
	return exists(item_id) and count_of(item_id) > 0


## Da `amount` copias. Falso si el objeto no existe en los datos.
func add(item_id: String, amount: int = 1) -> bool:
	if amount <= 0 or not exists(item_id) or DB.items.has(String(item_id)):
		return false
	owned[String(item_id)] = count_of(item_id) + amount
	return true


## Ids poseidos (que existen), ordenados por rareza (mejor primero) y luego nombre.
func owned_ids() -> Array:
	var out: Array = []
	for id in owned.keys():
		if exists(String(id)) and count_of(String(id)) > 0:
			out.append(String(id))
	out.sort_custom(func(a, b):
		var ra := rarity_rank(rarity_of(String(a)))
		var rb := rarity_rank(rarity_of(String(b)))
		if ra != rb:
			return ra > rb
		return name_of(String(a)) < name_of(String(b)))
	return out


## --- Equipar ----------------------------------------------------------------------------

## Objeto que lleva el personaje AHORA y es valido ("" si ninguno).
func item_of(character_id: String) -> String:
	var id := String(equipped.get(String(character_id), ""))
	return id if (not id.is_empty() and owns(id)) else ""


## Personajes que llevan ese objeto (validos), en orden estable.
func holders_of(item_id: String) -> Array:
	var out: Array = []
	for ch in equipped.keys():
		if String(equipped[ch]) == String(item_id):
			out.append(String(ch))
	out.sort()
	return out


## Equipos del jugador (cada uno es una lista de ids): el de combate y el de la torre.
func _teams() -> Array:
	var teams: Array = []
	if gs != null:
		teams.append(gs.party)
		teams.append(gs.tower_team)
	return teams


## Companeros de equipo de `character_id` (en cualquiera de sus equipos), sin el.
func teammates_of(character_id: String) -> Array:
	var out: Array = []
	for team in _teams():
		if (team as Array).has(character_id):
			for other in team:
				if String(other) != "" and String(other) != character_id and not out.has(String(other)):
					out.append(String(other))
	return out


## Se puede equipar? { ok, reason }.
func can_equip(character_id: String, item_id: String) -> Dictionary:
	var ch := String(character_id)
	var item := String(item_id)
	if gs == null or not gs.is_owned(ch):
		return { "ok": false, "reason": "Ese personaje no es tuyo." }
	if is_evolutive(item):
		return { "ok": false, "reason": "%s es un objeto evolutivo: sirve para evolucionar, no se equipa." % String(DB.items[item].get("name", item)) }
	if not exists(item):
		return { "ok": false, "reason": "Ese objeto no existe." }
	if count_of(item) <= 0:
		return { "ok": false, "reason": "No tienes ese objeto." }
	var other_holders := 0
	for h in holders_of(item):
		if h == ch:
			continue
		other_holders += 1
		if teammates_of(ch).has(h):
			return { "ok": false, "reason": "%s ya lleva %s en este equipo." % [gs.display_name(h), name_of(item)] }
	if other_holders >= count_of(item):
		return { "ok": false, "reason": "Todas tus copias de %s estan equipadas." % name_of(item) }
	return { "ok": true, "reason": "" }


## Equipa (sustituye lo que llevara). Devuelve el resultado de can_equip.
func equip(character_id: String, item_id: String) -> Dictionary:
	var check := can_equip(character_id, item_id)
	if bool(check["ok"]):
		equipped[String(character_id)] = String(item_id)
	return check


func unequip(character_id: String) -> bool:
	return equipped.erase(String(character_id))


## --- Combate ------------------------------------------------------------------------------

## Asignacion EFECTIVA para un grupo de unidades (en orden): como mucho un portador por
## objeto en el grupo, el primero que lo lleva. { character_id: item_id }.
func assignment_for(unit_ids: Array) -> Dictionary:
	var out := {}
	var used := {}
	for raw in unit_ids:
		var ch := String(raw)
		var item := item_of(ch)
		if item.is_empty() or used.has(item):
			continue
		used[item] = true
		out[ch] = item
	return out


## Mods permanentes (reglas "static") de un objeto: [{ stat, kind, value, source }].
static func static_mods(item_id: String) -> Array:
	var out: Array = []
	for rule in data_of(item_id).get("rules", []):
		if not (rule is Dictionary) or String((rule as Dictionary).get("trigger", "static")) != "static":
			continue
		for effect in (rule as Dictionary).get("effects", []):
			if effect is Dictionary and String((effect as Dictionary).get("type", "")) == "stat_mod":
				out.append({ "stat": String(effect.get("stat", "")), "kind": String(effect.get("kind", "mult")),
					"value": float(effect.get("value", 0.0)),
					"source": "equip:%s:%s" % [item_id, String((rule as Dictionary).get("id", "base"))] })
	return out


## Reglas con disparador de un objeto, en formato de pasiva (las dispara el BattleManager).
static func trigger_rules(item_id: String) -> Array:
	var out: Array = []
	var data := data_of(item_id)
	for rule in data.get("rules", []):
		if not (rule is Dictionary) or String((rule as Dictionary).get("trigger", "static")) == "static":
			continue
		var copy: Dictionary = (rule as Dictionary).duplicate(true)
		copy["id"] = "equip_%s_%s" % [item_id, String(rule.get("id", "regla"))]
		copy["name"] = "%s: %s" % [String(data.get("name", item_id)), String(rule.get("name", ""))]
		copy["origin"] = "equipment"
		out.append(copy)
	return out


## Aplica los mods permanentes del objeto de `character_id` a su StatBlock. Se llama una
## vez por unidad y batalla; el origen es propio, asi que repetirlo SUSTITUYE, no suma.
func apply_mods(stat_block, character_id: String, assignment: Dictionary) -> void:
	var item := String(assignment.get(String(character_id), ""))
	if stat_block == null or item.is_empty():
		return
	for mod in static_mods(item):
		stat_block.add_mod(String(mod["stat"]), String(mod["kind"]), float(mod["value"]), String(mod["source"]))


func rules_for(character_id: String, assignment: Dictionary) -> Array:
	var item := String(assignment.get(String(character_id), ""))
	return trigger_rules(item) if not item.is_empty() else []


## --- Obtencion -----------------------------------------------------------------------------

## Objetos que pueden salir de un banner o de un evento (JSON "obtain").
static func obtainable_ids(source: String) -> Array:
	var out: Array = []
	for item in DB.all_equipment():
		var obtain = (item as Dictionary).get("obtain", {})
		if obtain is Dictionary and bool((obtain as Dictionary).get(source, false)):
			out.append(String((item as Dictionary)["id"]))
	return out


## Tasas efectivas de un banner: { rareza: tasa } normalizadas. Las rarezas sin ningun
## objeto en el pool se reparten entre las demas (nunca se tira una rareza vacia).
static func banner_rates(banner_id: String) -> Dictionary:
	var banner := DB.get_equipment_banner(banner_id)
	var pool := obtainable_ids("banner")
	var raw: Dictionary = banner.get("rates", {})
	var rates := {}
	var total := 0.0
	for r in RARITIES:
		var has_items := false
		for id in pool:
			if rarity_of(String(id)) == r:
				has_items = true
				break
		if has_items and float(raw.get(r, 0.0)) > 0.0:
			rates[r] = float(raw[r])
			total += float(raw[r])
	if total <= 0.0:
		return {}
	for r in rates.keys():
		rates[r] = float(rates[r]) / total
	return rates


static func banner_problems(banner_id: String) -> Array:
	var out: Array = []
	var banner := DB.get_equipment_banner(banner_id)
	if banner.is_empty():
		return ["el banner de objetos '%s' no existe" % banner_id]
	var raw: Dictionary = banner.get("rates", {})
	var sum := 0.0
	for r in raw.keys():
		if not RARITIES.has(String(r)):
			out.append("rareza desconocida '%s'" % r)
		sum += float(raw[r])
	if absf(sum - 1.0) > 0.0001:
		out.append("las tasas suman %.4f en vez de 1" % sum)
	var pool := obtainable_ids("banner")
	for r in raw.keys():
		if float(raw[r]) > 0.0 and not pool.any(func(id): return rarity_of(String(id)) == String(r)):
			out.append("la rareza %s tiene tasa pero ningun objeto en el pool" % r)
	for f in banner.get("featured", []):
		if not exists(String(f)):
			out.append("destacado '%s' no existe" % f)
	return out


## Tira UN objeto del banner con `rng`.
static func roll(banner_id: String, rng: RandomNumberGenerator) -> String:
	var rates := banner_rates(banner_id)
	if rates.is_empty():
		return ""
	var banner := DB.get_equipment_banner(banner_id)
	var x := rng.randf()
	var acc := 0.0
	var chosen := "N"
	for r in RARITIES:
		if not rates.has(r):
			continue
		acc += float(rates[r])
		chosen = r
		if x < acc:
			break
	var candidates: Array = []
	for id in obtainable_ids("banner"):
		if rarity_of(String(id)) == chosen:
			candidates.append(String(id))
	if candidates.is_empty():
		return ""
	# Destacados: tasa propia dentro de su rareza (mismo concepto que los banners de personajes).
	var feat_rates: Dictionary = banner.get("featured_rates", {})
	var y := rng.randf()
	var facc := 0.0
	for f in feat_rates.keys():
		if candidates.has(String(f)):
			facc += float(feat_rates[f]) / maxf(0.0001, float(rates[chosen]))
			if y < facc:
				return String(f)
	return String(candidates[rng.randi_range(0, candidates.size() - 1)])


## Invoca `count` tiradas pagando gemas. Informe: { ok, reason, results: [id], new: [id] }.
func summon(banner_id: String, count: int) -> Dictionary:
	var report := { "ok": false, "reason": "", "results": [], "new": [], "cost": 0 }
	var banner := DB.get_equipment_banner(banner_id)
	if banner.is_empty() or not bool(banner.get("enabled", true)) or not banner_problems(banner_id).is_empty():
		report["reason"] = "Ese banner de objetos no esta disponible."
		return report
	var multi := maxi(2, int(banner.get("multi_pulls", 10)))
	if count != 1 and count != multi:
		report["reason"] = "Cantidad de tiradas no valida."
		return report
	var cost := int(banner.get("cost", {}).get("single" if count == 1 else "multi", 0))
	if gs.gems < cost:
		report["reason"] = "No tienes gemas suficientes."
		return report
	if not gs.spend_gems(cost):
		report["reason"] = "No tienes gemas suficientes."
		return report
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var id := roll(banner_id, rng)
		if id.is_empty():
			continue
		if count_of(id) == 0 and not (report["new"] as Array).has(id):
			(report["new"] as Array).append(id)
		add(id, 1)
		(report["results"] as Array).append(id)
	report["ok"] = true
	report["cost"] = cost
	gs.add_counter("objetos_equipables_obtenidos", count)
	gs.save_game()
	return report


## --- Validacion de datos (diagnostico y pruebas) --------------------------------------------

const TRIGGERS := ["static", "battle_start", "turn_start", "on_hit", "on_attack", "on_crit", "on_special", "on_dodge", "on_kill", "on_ally_down", "low_hp"]
const EFFECT_TYPES := ["damage", "heal", "stat_mod", "sp_gain", "status", "shield", "periodic", "cleanse", "dispel", "sp_drain", "undying"]

static func problems_of(item_id: String) -> Array:
	var out: Array = []
	var d := data_of(item_id)
	if d.is_empty():
		return ["no existe"]
	for key in ["name", "anime", "description", "icon"]:
		if String(d.get(key, "")).is_empty():
			out.append("falta '%s'" % key)
	if String(d.get("kind", "")) != "equipment":
		out.append("kind debe ser 'equipment'")
	if DB.items.has(item_id):
		out.append("su id coincide con un objeto evolutivo de data/items")
	if not RARITIES.has(String(d.get("rarity", ""))):
		out.append("rareza invalida '%s'" % d.get("rarity", ""))
	var passive = d.get("passive", {})
	if not (passive is Dictionary) or String((passive as Dictionary).get("description", "")).is_empty():
		out.append("falta la descripcion de la pasiva")
	var rules = d.get("rules", [])
	if not (rules is Array) or (rules as Array).is_empty():
		out.append("sin efectos")
		return out
	var seen := {}
	for rule in rules:
		var rid := String((rule as Dictionary).get("id", ""))
		if rid.is_empty() or seen.has(rid):
			out.append("regla sin id o repetida '%s'" % rid)
		seen[rid] = true
		if not TRIGGERS.has(String((rule as Dictionary).get("trigger", ""))):
			out.append("trigger desconocido '%s'" % (rule as Dictionary).get("trigger", ""))
		for effect in (rule as Dictionary).get("effects", []):
			if not EFFECT_TYPES.has(String((effect as Dictionary).get("type", ""))):
				out.append("efecto desconocido '%s'" % (effect as Dictionary).get("type", ""))
		var chance := float((rule as Dictionary).get("chance", 1.0))
		if chance <= 0.0 or chance > 1.0:
			out.append("probabilidad fuera de rango en '%s'" % rid)
	return out


## --- Guardado ----------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return { "owned": owned.duplicate(), "equipped": equipped.duplicate() }


## Carga sin perder nada: un objeto desconocido se conserva en `owned` (por si vuelve a los
## datos) pero no cuenta; lo equipado se limpia si ya no es valido o no hay copias.
func from_dict(raw: Variant) -> void:
	owned = {}
	equipped = {}
	if not (raw is Dictionary):
		return
	var data: Dictionary = raw
	var o = data.get("owned", {})
	if o is Dictionary:
		for id in o.keys():
			var n := int(o[id])
			if n > 0:
				owned[String(id)] = n
	var e = data.get("equipped", {})
	if e is Dictionary:
		for ch in e.keys():
			equipped[String(ch)] = String(e[ch])
	sanitize()


## Quita lo equipado que ya no es valido: objeto no poseido, personaje que no es tuyo,
## mas portadores que copias, o dos companeros con el mismo objeto.
func sanitize() -> void:
	var keys: Array = equipped.keys()
	keys.sort()
	var used := {}
	for ch in keys:
		var item := String(equipped[ch])
		var bad: bool = item.is_empty() or not owns(item) or (gs != null and not gs.is_owned(String(ch)))
		if not bad:
			var n := int(used.get(item, 0))
			if n >= count_of(item):
				bad = true
			else:
				for other in holders_of(item):
					if other != String(ch) and used.has("%s|%s" % [item, other]) and teammates_of(String(ch)).has(other):
						bad = true
		if bad:
			equipped.erase(ch)
		else:
			used[item] = int(used.get(item, 0)) + 1
			used["%s|%s" % [item, ch]] = true
