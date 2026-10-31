extends RefCounted

## COLECCIONES CON RECOMPENSAS (v15).
##
## Una coleccion es un conjunto de personajes con premios por tramos. Es DATOS
## (res://data/collections/*.json): anadir una coleccion no toca ningun script. Tipos:
##
##   series    -> "members": lista explicita de personajes de una serie
##   category  -> "category": todos los personajes de esa categoria
##   rarity    -> "rarity": todos los que nacen con esa rareza
##   event     -> "members" + "event": ademas se puede pedir haber completado el evento
##   custom    -> "members": cualquier otro conjunto
##
## Los miembros son FAMILIAS evolutivas (core/families.gd), no ids sueltos: Sakuta y Mai
## cuenta aunque ya haya evolucionado y el id original se haya consumido. Por eso
## todas las colecciones se pueden completar con los personajes que existen.
##
## Cada tramo ("tiers") pide un porcentaje (o un numero) de miembros y paga una
## recompensa con el mismo formato que misiones y cuenta (core/rewards.gd). Un tramo
## se cobra una sola vez. El progreso se LEE del roster real: no se guarda aparte, lo
## unico que se guarda es que tramos ya se cobraron.

const Families := preload("res://core/families.gd")
const Rewards := preload("res://core/rewards.gd")

const KINDS := ["series", "category", "rarity", "event", "custom"]
const KIND_LABELS := { "series": "SERIES", "category": "CATEGORIAS", "rarity": "RAREZAS", "event": "EVENTOS", "custom": "OTRAS" }

var gs = null
var claimed: Dictionary = {}   # collection_id -> [tier ids cobrados]


func _init(owner = null) -> void:
	gs = owner


func ids() -> Array:
	var out: Array = DB.collections.keys()
	out.sort()
	return out


## Familias (raices) que componen la coleccion, sin repetir y en orden estable.
func members_of(collection_id: String) -> Array:
	var data: Dictionary = DB.get_collection(collection_id)
	var out: Array = []
	if data.is_empty():
		return out
	match String(data.get("kind", "")):
		"category":
			var wanted := String(data.get("category", ""))
			for id in DB.characters.keys():
				if (DB.characters[id].get("categories", []) as Array).has(wanted):
					var root := Families.root_of(String(id))
					if not out.has(root):
						out.append(root)
		"rarity":
			var rarity := String(data.get("rarity", ""))
			for root in Families.all_roots():
				if String((DB.characters.get(String(root), {}) as Dictionary).get("rarity", "")) == rarity and not out.has(root):
					out.append(String(root))
		_:
			for raw in data.get("members", []):
				if DB.characters.has(String(raw)):
					var root2 := Families.root_of(String(raw))
					if not out.has(root2):
						out.append(root2)
	out.sort()
	return out


## Cuantos miembros pide un tramo: "count" fijo o "percent" del total (redondeado
## hacia arriba, minimo 1, maximo el total).
func tier_need(total: int, tier: Dictionary) -> int:
	if tier.has("count"):
		return clampi(int(tier["count"]), 1, maxi(1, total))
	var percent := clampf(float(tier.get("percent", 100)), 1.0, 100.0)
	return clampi(int(ceil(float(total) * percent / 100.0)), 1, maxi(1, total))


func owned_members(collection_id: String) -> Array:
	var out: Array = []
	for root in members_of(collection_id):
		if Families.owns(gs, String(root)):
			out.append(String(root))
	return out


func is_tier_claimed(collection_id: String, tier_id: String) -> bool:
	return (claimed.get(collection_id, []) as Array).has(tier_id)


func _event_done(data: Dictionary) -> bool:
	var event_id := String(data.get("event", ""))
	return event_id.is_empty() or gs.event_completed(event_id)


## Estado completo de una coleccion para pintar.
func state(collection_id: String) -> Dictionary:
	var data: Dictionary = DB.get_collection(collection_id)
	if data.is_empty():
		return {}
	var members := members_of(collection_id)
	var owned := owned_members(collection_id)
	var total := members.size()
	var tiers_out: Array = []
	var ready_n := 0
	var event_done := _event_done(data)
	for raw in data.get("tiers", []):
		if not (raw is Dictionary):
			continue
		var tier: Dictionary = raw
		var need := tier_need(total, tier)
		var reached := owned.size() >= need
		if bool(tier.get("requires_event", false)) and not event_done:
			reached = false
		var is_claimed := is_tier_claimed(collection_id, String(tier.get("id", "")))
		if reached and not is_claimed:
			ready_n += 1
		var reward: Dictionary = tier.get("reward", {})
		tiers_out.append({
			"id": String(tier.get("id", "")), "need": need, "reached": reached,
			"claimed": is_claimed, "reward": reward, "text": Rewards.describe(reward),
			"requires_event": bool(tier.get("requires_event", false)),
		})
	var missing: Array = []
	for root in members:
		if not owned.has(root):
			missing.append({ "id": String(root), "name": gs.display_name(String(root)), "sources": Families.sources_text(String(root)) })
	var owned_info: Array = []
	for root in owned:
		owned_info.append({ "id": String(root), "name": gs.display_name(String(Families.owned_form(gs, String(root)))) })
	var all_claimed := not tiers_out.is_empty()
	for t in tiers_out:
		if not bool(t["claimed"]):
			all_claimed = false
	return {
		"id": collection_id, "name": String(data.get("name", collection_id)),
		"kind": String(data.get("kind", "custom")), "description": String(data.get("description", "")),
		"total": total, "owned": owned.size(), "tiers": tiers_out, "ready": ready_n,
		"missing": missing, "owned_list": owned_info,
		"complete": owned.size() >= total and total > 0 and event_done,
		"all_claimed": all_claimed,
		"event": String(data.get("event", "")), "event_done": event_done,
	}


## Cobra un tramo. Devuelve {} si no se puede (no alcanzado, ya cobrado, no existe).
func claim_tier(collection_id: String, tier_id: String) -> Dictionary:
	var st := state(collection_id)
	if st.is_empty():
		return {}
	for tier in st["tiers"]:
		if String(tier["id"]) != tier_id:
			continue
		if not bool(tier["reached"]) or bool(tier["claimed"]):
			return {}
		if not claimed.has(collection_id):
			claimed[collection_id] = []
		(claimed[collection_id] as Array).append(tier_id)
		var report := Rewards.pay(gs, tier["reward"])
		gs.save_game()
		return { "collection": collection_id, "name": String(st["name"]), "tier": tier_id, "report": report, "text": String(tier["text"]) }
	return {}


## Cobra todos los tramos listos de todas las colecciones.
func claim_all() -> Array:
	var out: Array = []
	for cid in ids():
		var st := state(String(cid))
		for tier in st.get("tiers", []):
			if bool(tier["reached"]) and not bool(tier["claimed"]):
				var done := claim_tier(String(cid), String(tier["id"]))
				if not done.is_empty():
					out.append(done)
	return out


## Tramos listos para cobrar en total (para la insignia de la pantalla).
func unclaimed_count() -> int:
	var n := 0
	for cid in ids():
		n += int(state(String(cid)).get("ready", 0))
	return n


## Colecciones completas / totales.
func completed_count() -> int:
	var n := 0
	for cid in ids():
		if bool(state(String(cid)).get("complete", false)):
			n += 1
	return n


## Colecciones a las que pertenece una familia (para decirlo en la ficha).
func collections_with(root: String) -> Array:
	var out: Array = []
	for cid in ids():
		if members_of(String(cid)).has(root):
			out.append(String(cid))
	return out


## --- Validacion (la usan el diagnostico y las pruebas) ---------------------------

## Problemas de configuracion de una coleccion; lista vacia = valida Y completable.
func problems(collection_id: String) -> Array:
	var out: Array = []
	var data: Dictionary = DB.get_collection(collection_id)
	if data.is_empty():
		return ["%s: no existe" % collection_id]
	var kind := String(data.get("kind", ""))
	if not KINDS.has(kind):
		out.append("%s: tipo desconocido '%s'" % [collection_id, kind])
	if kind == "category" and not DB.categories.has(String(data.get("category", ""))):
		out.append("%s: la categoria '%s' no existe" % [collection_id, data.get("category", "")])
	if kind == "rarity" and not VALID_RARITIES.has(String(data.get("rarity", ""))):
		out.append("%s: rareza no valida '%s'" % [collection_id, data.get("rarity", "")])
	if kind != "category" and kind != "rarity":
		for raw in data.get("members", []):
			if not DB.characters.has(String(raw)):
				out.append("%s: el personaje '%s' no existe" % [collection_id, raw])
	var members := members_of(collection_id)
	if members.is_empty():
		out.append("%s: no tiene ningun miembro" % collection_id)
	for root in members:
		if not Families.reachable(String(root)):
			out.append("%s: '%s' no se puede conseguir, la coleccion no es completable" % [collection_id, root])
	var event_id := String(data.get("event", ""))
	if not event_id.is_empty() and not DB.events.has(event_id):
		out.append("%s: el evento '%s' no existe" % [collection_id, event_id])
	var tiers = data.get("tiers", [])
	if not (tiers is Array) or (tiers as Array).is_empty():
		out.append("%s: no tiene tramos de recompensa" % collection_id)
		return out
	var seen: Array = []
	var has_full := false
	for raw in tiers:
		if not (raw is Dictionary):
			out.append("%s: un tramo no es un objeto" % collection_id)
			continue
		var tier: Dictionary = raw
		var tier_id := String(tier.get("id", ""))
		if tier_id.is_empty() or seen.has(tier_id):
			out.append("%s: id de tramo vacio o repetido ('%s')" % [collection_id, tier_id])
		seen.append(tier_id)
		if tier.has("percent") and (float(tier["percent"]) <= 0.0 or float(tier["percent"]) > 100.0):
			out.append("%s/%s: porcentaje fuera de 1-100" % [collection_id, tier_id])
		if tier.has("count") and int(tier["count"]) > members.size():
			out.append("%s/%s: pide %d miembros y solo hay %d" % [collection_id, tier_id, int(tier["count"]), members.size()])
		if tier_need(members.size(), tier) >= members.size():
			has_full = true
		if bool(tier.get("requires_event", false)) and event_id.is_empty():
			out.append("%s/%s: pide un evento pero la coleccion no declara 'event'" % [collection_id, tier_id])
		out.append_array(Rewards.problems(tier.get("reward", {}), "%s/%s" % [collection_id, tier_id]))
	if not has_full:
		out.append("%s: ningun tramo pide la coleccion entera" % collection_id)
	return out


const VALID_RARITIES := ["N", "R", "SR", "SSR", "UR", "LR"]


## --- Guardado --------------------------------------------------------------------

func to_dict() -> Dictionary:
	return { "claimed": claimed.duplicate(true) }


func from_dict(raw: Variant) -> void:
	claimed = {}
	if not (raw is Dictionary):
		return
	var src = (raw as Dictionary).get("claimed", {})
	if not (src is Dictionary):
		return
	for cid in src:
		if not DB.collections.has(String(cid)) or not (src[cid] is Array):
			continue
		var tier_ids: Array = []
		for t in src[cid]:
			if not tier_ids.has(String(t)):
				tier_ids.append(String(t))
		claimed[String(cid)] = tier_ids
