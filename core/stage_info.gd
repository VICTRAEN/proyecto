extends RefCounted

## INFORMACION DE FASES (v15): que pide cada combate y que paga, dicho con las reglas
## REALES del juego. Solo LEE datos; las recompensas las siguen pagando GameState.
##
## Reglas que se anuncian (salen de como paga GameState):
##   stage     -> XP y monedas CADA vez que se gana.
##   historia  -> cada dificultad paga UNA sola vez; superar una dificultad alta paga
##                tambien las menores que aun no estuvieran cobradas. La XP para los
##                personajes solo se reparte la primera vez que se supera el nivel.
##   torre     -> un piso paga UNA sola vez (la primera que se supera).
##   evento    -> primera victoria + los objetos que el stage declare.

const STAGE_RULE := "Se paga cada vez que ganas."
const STORY_RULE := "Cada dificultad se paga una sola vez; una dificultad alta paga tambien las menores pendientes."
const TOWER_RULE := "Cada piso solo paga la primera vez que lo superas."


## [{ id, name, type, boss, phases }] de una lista de ids de enemigo.
static func enemies_info(enemy_ids: Array) -> Array:
	var out: Array = []
	for raw in enemy_ids:
		var id := String(raw)
		var data: Dictionary = DB.enemies.get(id, {})
		var phases := (data.get("phases", []) as Array).size() if data.get("phases", []) is Array else 0
		out.append({
			"id": id, "name": String(data.get("name", id)), "type": String(data.get("type", "")),
			"boss": bool(data.get("boss", false)) or phases > 0, "phases": phases,
		})
	return out


## "JEFE: Celador del Sindrome (2 fases)" para cada jefe, o "" si no hay.
static func boss_text(enemy_ids: Array) -> String:
	var parts := PackedStringArray()
	for info in enemies_info(enemy_ids):
		if bool(info["boss"]):
			var phases := int(info["phases"])
			parts.append("%s%s" % [String(info["name"]), (" (%d fases)" % phases) if phases > 1 else ""])
	return "JEFE: %s" % ", ".join(parts) if not parts.is_empty() else ""


## Tipos de los rivales sin repetir, para elegir equipo ("PHY, STR").
static func types_text(enemy_ids: Array) -> String:
	var types: Array = []
	for info in enemies_info(enemy_ids):
		var t := String(info["type"])
		if not t.is_empty() and not types.has(t):
			types.append(t)
	return "Tipos rivales: %s" % ", ".join(PackedStringArray(types)) if not types.is_empty() else ""


## Lineas de informacion de una fase. `mode`: "stage" | "story" | "tower".
## Devuelve lineas de texto listas para pintar (la primera es la recompensa).
static func lines(mode: String, enemy_ids: Array, xp: int, coins: int, extra: Dictionary = {}) -> Array:
	var out: Array = []
	var reward := "Recompensa: %d XP  %d monedas" % [xp, coins]
	if not String(extra.get("first_clear_item", "")).is_empty():
		var item_id := String(extra["first_clear_item"])
		var item_name := String((DB.items.get(item_id, {}) as Dictionary).get("name", item_id))
		reward += "  + %d x %s (primera vez)" % [int(extra.get("first_clear_amount", 1)), item_name]
	out.append(reward)
	match mode:
		"story":
			out.append(STORY_RULE)
		"tower":
			out.append(TOWER_RULE)
		_:
			out.append(STAGE_RULE)
	var boss := boss_text(enemy_ids)
	if not boss.is_empty():
		out.append(boss)
	var types := types_text(enemy_ids)
	if not types.is_empty():
		out.append(types)
	var min_size := int(extra.get("requires_party_size", 0))
	if min_size > 1:
		out.append("Requisito: equipo de %d unidades." % min_size)
	return out
