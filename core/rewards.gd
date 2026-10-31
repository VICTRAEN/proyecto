extends RefCounted

## RECOMPENSAS (v15): el UNICO sitio que sabe pagar un bloque de recompensa.
##
## Colecciones, nivel de cuenta y misiones personales declaran sus premios con el mismo
## formato de datos y todos pasan por aqui. Asi no hay un segundo sistema de monedas ni
## cada pantalla paga a su manera:
##
##   { "coins": 500, "gems": 10, "materials": 5,
##     "items": { "item_id": 2 },
##     "title": { "id": "title_x", "name": "Nombre del titulo" },
##     "cosmetics": ["bg_tower", "ill_goku"] }
##
## Todo es opcional. Solo existen los recursos reales del juego (monedas, gemas, el
## contador de materiales, objetos del inventario, titulos y cosmeticos): no hay tickets
## ni monedas nuevas. Los titulos y cosmeticos NO se duplican: darlos dos veces es no-op.

const KEYS := ["coins", "gems", "materials", "items", "title", "cosmetics"]


## Paga `reward` al jugador (gs = GameState). NO guarda: lo hace quien llama, una vez,
## despues de marcar la recompensa como reclamada.
## Devuelve lo realmente entregado: { coins, gems, materials, items, titles, cosmetics }.
static func pay(gs, reward: Dictionary) -> Dictionary:
	var out := { "coins": 0, "gems": 0, "materials": 0, "items": {}, "titles": [], "cosmetics": [] }
	if gs == null or reward.is_empty():
		return out
	var coins_amount := maxi(0, int(reward.get("coins", 0)))
	var gems_amount := maxi(0, int(reward.get("gems", 0)))
	var materials_amount := maxi(0, int(reward.get("materials", 0)))
	if coins_amount > 0:
		gs.add_coins(coins_amount)
		out["coins"] = coins_amount
	if gems_amount > 0:
		gs.add_gems(gems_amount)
		out["gems"] = gems_amount
	if materials_amount > 0:
		gs.add_materials(materials_amount)
		out["materials"] = materials_amount
	var items = reward.get("items", {})
	if items is Dictionary:
		for item_id in items:
			var amount := maxi(0, int((items as Dictionary)[item_id]))
			if amount > 0 and DB.items.has(String(item_id)):
				gs.add_item(String(item_id), amount)
				out["items"][String(item_id)] = amount
	var title = reward.get("title", {})
	if title is Dictionary and not String((title as Dictionary).get("id", "")).is_empty():
		var title_id := String((title as Dictionary)["id"])
		if not gs.meta.titles_owned.has(title_id):
			gs.meta.titles_owned.append(title_id)
			out["titles"].append(title_id)
	var cosmetics = reward.get("cosmetics", [])
	if cosmetics is Array:
		for raw in cosmetics:
			var cosmetic_id := String(raw)
			if gs.account.grant_cosmetic(cosmetic_id):
				out["cosmetics"].append(cosmetic_id)
	return out


## Texto corto de una recompensa para pintarla ("500 monedas, 10 gemas, Titulo: X").
static func describe(reward: Dictionary) -> String:
	var parts := PackedStringArray()
	if int(reward.get("coins", 0)) > 0:
		parts.append("%d monedas" % int(reward["coins"]))
	if int(reward.get("gems", 0)) > 0:
		parts.append("%d gemas" % int(reward["gems"]))
	if int(reward.get("materials", 0)) > 0:
		parts.append("%d materiales" % int(reward["materials"]))
	var items = reward.get("items", {})
	if items is Dictionary:
		for item_id in items:
			var item_name := String((DB.items.get(String(item_id), {}) as Dictionary).get("name", item_id))
			parts.append("%d x %s" % [int((items as Dictionary)[item_id]), item_name])
	var title = reward.get("title", {})
	if title is Dictionary and not String((title as Dictionary).get("id", "")).is_empty():
		parts.append("Titulo: %s" % String((title as Dictionary).get("name", title["id"])))
	var cosmetics = reward.get("cosmetics", [])
	if cosmetics is Array:
		for raw in cosmetics:
			var cosmetic: Dictionary = DB.cosmetics.get(String(raw), {})
			var type_text := "Fondo" if String(cosmetic.get("type", "")) == "background" else "Ilustracion"
			parts.append("%s: %s" % [type_text, String(cosmetic.get("name", raw))])
	return ", ".join(parts)


## Problemas de un bloque de recompensa (para el diagnostico y las pruebas): claves
## desconocidas, cantidades negativas, objetos o cosmeticos que no existen, un titulo sin
## nombre. Una recompensa vacia tambien es un problema (no paga nada).
static func problems(reward: Variant, label: String) -> Array:
	var out: Array = []
	if not (reward is Dictionary) or (reward as Dictionary).is_empty():
		out.append("%s: recompensa vacia" % label)
		return out
	var r: Dictionary = reward
	for key in r.keys():
		if not KEYS.has(String(key)):
			out.append("%s: clave de recompensa desconocida '%s'" % [label, key])
	for numeric in ["coins", "gems", "materials"]:
		if r.has(numeric) and int(r[numeric]) < 0:
			out.append("%s: %s negativo" % [label, numeric])
	var items = r.get("items", {})
	if items is Dictionary:
		for item_id in items:
			if not DB.items.has(String(item_id)):
				out.append("%s: el objeto '%s' no existe" % [label, item_id])
			elif int((items as Dictionary)[item_id]) <= 0:
				out.append("%s: cantidad no positiva de '%s'" % [label, item_id])
	var title = r.get("title", {})
	if r.has("title"):
		if not (title is Dictionary) or String((title as Dictionary).get("id", "")).is_empty() or String((title as Dictionary).get("name", "")).is_empty():
			out.append("%s: titulo sin id o sin nombre" % label)
	var cosmetics = r.get("cosmetics", [])
	if cosmetics is Array:
		for raw in cosmetics:
			if not DB.cosmetics.has(String(raw)):
				out.append("%s: el cosmetico '%s' no existe" % [label, raw])
	return out
