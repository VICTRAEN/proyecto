extends RefCounted

## METAPROGRESO (v14): misiones DIARIAS/SEMANALES, LOGROS y TITULOS.
##
## Una sola fuente de eventos: GameState llama a record() desde los PUNTOS UNICOS donde
## algo ocurre de verdad (una batalla que cobra, una invocacion, una evolucion, un
## piso de torre, un stage de evento). Nada mas suma progreso, asi que una accion
## no se cuenta dos veces.
##
## Las misiones periodicas guardan {key, progress, claimed}; "key" es el periodo
## (dia o semana) en que se jugaron. Si el periodo actual es otro, el estado se
## reinicia al consultarlo: sin servidor ni conexion, solo el reloj del dispositivo.
## Los logros NO cuentan nada propio salvo los retos especiales y los jefes: se
## evaluan contra el estado real (roster, torre, contadores), asi que no se pueden
## desincronizar y un guardado antiguo desbloquea lo que ya cumplia.
##
## Todo es dato: data/missions/*.json con "period", data/achievements/*.json.

const RARITY_LADDER := ["R", "SR", "SSR", "UR", "LR"]
const DEFAULT_TITLE := "title_recien_llegado"

var gs = null                     # GameState (se inyecta; permite probar sin autoload)
var now_override := 0             # unix; 0 = reloj real (lo usan las pruebas)
var periodic: Dictionary = {}     # mission_id -> { key, progress, claimed }
var achievements: Dictionary = {} # id -> { unlocked, claimed }
var titles_owned: Array = []
var title_equipped := ""
var boss_kills: Dictionary = {}   # enemy_id -> veces derrotado
var challenges: Dictionary = {}   # stat -> n (retos especiales)


func _init(owner = null) -> void:
	gs = owner


## --- Reloj y periodos ---------------------------------------------------------

func now() -> int:
	return now_override if now_override > 0 else int(Time.get_unix_time_from_system())


func _local_day() -> int:
	var bias := 0
	if now_override <= 0:
		bias = int(Time.get_time_zone_from_system().get("bias", 0))
	return int(floor(float(now() + bias * 60) / 86400.0))


static func _date_text(day: int) -> String:
	var d := Time.get_date_dict_from_unix_time(day * 86400)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


func period_key(period: String) -> String:
	var day := _local_day()
	if period == "weekly":
		return "W" + _date_text(day - ((day + 3) % 7))   # semana que empieza en lunes
	return _date_text(day)


## Segundos que quedan para que acabe el periodo (para pintar "se reinicia en...").
func seconds_left(period: String) -> int:
	var bias := 0
	if now_override <= 0:
		bias = int(Time.get_time_zone_from_system().get("bias", 0))
	var local_now := now() + bias * 60
	var day := int(floor(float(local_now) / 86400.0))
	var end_day := day + 1
	if period == "weekly":
		end_day = day - ((day + 3) % 7) + 7
	return end_day * 86400 - local_now


## --- Misiones periodicas ------------------------------------------------------

func periodic_ids() -> Array:
	var out: Array = []
	for mission in DB.all_missions():
		if not String(mission.get("period", "")).is_empty():
			out.append(String(mission["id"]))
	return out


func _entry(id: String, period: String) -> Dictionary:
	var key := period_key(period)
	var entry: Dictionary = periodic.get(id, {})
	if String(entry.get("key", "")) != key:
		entry = { "key": key, "progress": 0, "claimed": false }
		periodic[id] = entry
	return entry


func periodic_state(id: String) -> Dictionary:
	var data: Dictionary = DB.get_mission(id)
	if data.is_empty() or String(data.get("period", "")).is_empty():
		return {}
	var period := String(data["period"])
	var entry := _entry(id, period)
	var target := maxi(1, int(data.get("target", 1)))
	var progress := mini(int(entry["progress"]), target)
	return {
		"id": id, "name": String(data.get("name", id)),
		"description": String(data.get("description", "")),
		"category": String(data.get("category", period.to_upper())),
		"period": period, "target": target, "progress": progress,
		"completed": progress >= target, "claimed": bool(entry["claimed"]),
		"reward_coins": int(data.get("reward_coins", 0)),
		"reward_gems": int(data.get("reward_gems", 0)),
		"reward_items": data.get("reward_items", {}),
		"key": String(entry["key"]),
	}


func periodic_list(period: String) -> Array:
	var out: Array = []
	for id in periodic_ids():
		if String(DB.get_mission(id).get("period", "")) == period:
			out.append(periodic_state(id))
	return out


func claim_periodic(id: String) -> Dictionary:
	var state := periodic_state(id)
	if state.is_empty() or not bool(state["completed"]) or bool(state["claimed"]):
		return {}
	periodic[id]["claimed"] = true
	return _pay(state)


func _pay(state: Dictionary) -> Dictionary:
	var coins_earned := int(state.get("reward_coins", 0))
	var gems_earned := int(state.get("reward_gems", 0))
	gs.coins += coins_earned
	gs.gems += gems_earned
	var items: Dictionary = {}
	var raw_items = state.get("reward_items", {})
	if raw_items is Dictionary:
		for item_id in raw_items:
			gs.add_item(String(item_id), int(raw_items[item_id]))
			items[String(item_id)] = int(raw_items[item_id])
	gs.save_game()
	return { "coins": coins_earned, "gems": gems_earned, "items": items, "name": String(state.get("name", "")) }


## --- Eventos: el unico camino por el que entra progreso ----------------------------
## kind: "battle" | "summon" | "evolve" | "tower_floor" | "event_stage"
## ctx (battle): { victory, ally_ids, rounds, fallen, bosses: [ids], solo }

func record(kind: String, amount: int, ctx: Dictionary) -> void:
	if kind == "battle":
		_record_battle_stats(ctx)
	for id in periodic_ids():
		var data: Dictionary = DB.get_mission(id)
		var add := _objective_gain(data.get("objective", {}), kind, amount, ctx)
		if add <= 0:
			continue
		var entry := _entry(id, String(data["period"]))
		entry["progress"] = mini(int(entry["progress"]) + add, maxi(1, int(data.get("target", 1))))
	check_achievements()


func _record_battle_stats(ctx: Dictionary) -> void:
	if not bool(ctx.get("victory", false)):
		return
	for boss_id in ctx.get("bosses", []):
		boss_kills[String(boss_id)] = int(boss_kills.get(String(boss_id), 0)) + 1
		challenges["boss_total"] = int(challenges.get("boss_total", 0)) + 1
	if bool(ctx.get("solo", false)):
		challenges["solo_wins"] = int(challenges.get("solo_wins", 0)) + 1
	if int(ctx.get("fallen", 0)) == 0:
		challenges["flawless_wins"] = int(challenges.get("flawless_wins", 0)) + 1
	if int(ctx.get("rounds", 99)) <= 3:
		challenges["fast_wins"] = int(challenges.get("fast_wins", 0)) + 1


func _objective_gain(objective: Variant, kind: String, amount: int, ctx: Dictionary) -> int:
	if not (objective is Dictionary):
		return 0
	var objective_type := String(objective.get("type", ""))
	var won := bool(ctx.get("victory", false))
	match objective_type:
		"battle_played":
			return 1 if kind == "battle" else 0
		"battle_won":
			return 1 if kind == "battle" and won else 0
		"boss_defeated":
			return (ctx.get("bosses", []) as Array).size() if kind == "battle" and won else 0
		"evolve":
			if kind != "evolve":
				return 0
			var wanted := String(objective.get("to", ""))
			return amount if wanted.is_empty() or wanted == String(ctx.get("to", "")) else 0
		"summon":
			return amount if kind == "summon" else 0
		"tower_floor":
			return amount if kind == "tower_floor" else 0
		"event_stage":
			return amount if kind == "event_stage" else 0
		"use_character":
			# Una batalla suma UNA vez si en el equipo esta el personaje o categoria.
			if kind != "battle" or (bool(objective.get("win", false)) and not won):
				return 0
			return 1 if _team_matches(ctx.get("ally_ids", []), objective) else 0
		"category_win":
			if kind != "battle" or not won:
				return 0
			return 1 if _team_matches(ctx.get("ally_ids", []), objective) else 0
	return 0


## El equipo cumple si tiene `min` (por defecto 1) miembros del personaje o categoria.
func _team_matches(ally_ids: Array, objective: Dictionary) -> bool:
	var need := maxi(1, int(objective.get("min", 1)))
	var character := String(objective.get("character", ""))
	var category := String(objective.get("category", ""))
	var count := 0
	for raw in ally_ids:
		var id := String(raw)
		if not character.is_empty():
			if id == character:
				count += 1
		elif not category.is_empty():
			if (DB.get_character(id).get("categories", []) as Array).has(category):
				count += 1
		else:
			count += 1
	return count >= need


## --- Logros --------------------------------------------------------------------

func achievement_ids() -> Array:
	var ids: Array = DB.achievements.keys()
	ids.sort()
	return ids


## Progreso y objetivo actuales de un logro, leidos del estado real.
func achievement_state(id: String) -> Dictionary:
	var data: Dictionary = DB.achievements.get(id, {})
	if data.is_empty():
		return {}
	var cond: Dictionary = data.get("condition", {})
	var pt := _condition_progress(cond)
	var saved: Dictionary = achievements.get(id, {})
	var target := maxi(1, int(pt[1]))
	var progress := mini(int(pt[0]), target)
	var title_data: Dictionary = data.get("title", {}) if data.get("title", {}) is Dictionary else {}
	return {
		"id": id, "name": String(data.get("name", id)),
		"description": String(data.get("description", "")),
		"category": String(data.get("category", "GENERAL")),
		"progress": progress, "target": target,
		"completed": progress >= target,
		"unlocked": saved.has("unlocked"), "claimed": bool(saved.get("claimed", false)),
		"reward_coins": int(data.get("reward_coins", 0)),
		"reward_gems": int(data.get("reward_gems", 0)),
		"reward_items": data.get("reward_items", {}),
		"title_id": String(title_data.get("id", "")),
		"title_name": String(title_data.get("name", "")),
	}


func _condition_progress(cond: Dictionary) -> Array:
	var target := int(cond.get("target", 1))
	match String(cond.get("type", "")):
		"roster_count":
			return [gs.roster.size(), target]
		"counter":
			return [gs.counter_value(String(cond.get("stat", ""))), target]
		"rarity_count":
			var wanted := RARITY_LADDER.find(String(cond.get("rarity", "UR")))
			var n := 0
			for id in gs.roster:
				if RARITY_LADDER.find(gs.rarity_of(String(id))) >= wanted:
					n += 1
			return [n, target]
		"evolved_rarity":
			# Solo cuenta al que HA EVOLUCIONADO (no al que ya nacio con esa rareza).
			var need_rank := RARITY_LADDER.find(String(cond.get("rarity", "UR")))
			var evolved := 0
			for id in gs.roster:
				if gs.is_evolved(String(id)) and RARITY_LADDER.find(gs.rarity_of(String(id))) >= need_rank:
					evolved += 1
			return [evolved, target]
		"tower_floor":
			return [gs.tower_best_floor(String(cond.get("tower", "tower_001"))), target]
		"tower_complete":
			var tower := String(cond.get("tower", "tower_001"))
			return [gs.tower_best_floor(tower), maxi(1, DB.tower_floor_count(tower))]
		"boss_kills":
			var boss := String(cond.get("boss", ""))
			return [int(boss_kills.get(boss, 0)) if not boss.is_empty() else int(challenges.get("boss_total", 0)), target]
		"collection":
			var cat := String(cond.get("category", ""))
			var total := 0
			var owned := 0
			for char_id in DB.characters:
				if (DB.characters[char_id].get("categories", []) as Array).has(cat):
					total += 1
					if gs.is_owned(String(char_id)):
						owned += 1
			return [owned, maxi(1, total)]
		"collection_all":
			return [gs.roster.size(), maxi(1, DB.characters.size())]
		"challenge":
			return [int(challenges.get(String(cond.get("stat", "")), 0)), target]
		"event_completed":
			return [gs.event_times_completed(String(cond.get("event", ""))), target]
	return [0, 1]


## Marca como desbloqueados los logros cuya condicion ya se cumple (y da su titulo).
## Devuelve los ids recien desbloqueados.
func check_achievements() -> Array:
	var fresh: Array = []
	if gs == null:
		return fresh
	for id in achievement_ids():
		var state := achievement_state(id)
		if state.is_empty() or not bool(state["completed"]) or achievements.has(id):
			continue
		achievements[id] = { "unlocked": now(), "claimed": false }
		fresh.append(id)
		var title_id := String(state["title_id"])
		if not title_id.is_empty() and not titles_owned.has(title_id):
			titles_owned.append(title_id)
	return fresh


func claim_achievement(id: String) -> Dictionary:
	check_achievements()
	var state := achievement_state(id)
	if state.is_empty() or not achievements.has(id) or bool(achievements[id].get("claimed", false)):
		return {}
	achievements[id]["claimed"] = true
	return _pay(state)


func achievements_unclaimed() -> int:
	var n := 0
	for id in achievement_ids():
		if achievements.has(id) and not bool(achievements[id].get("claimed", false)):
			n += 1
	return n


## --- Titulos ----------------------------------------------------------------------

## Todos los titulos que existen: el inicial mas los que dan los logros (datos).
func title_catalog() -> Dictionary:
	var out := { DEFAULT_TITLE: "Recien llegado" }
	for id in DB.achievements:
		var title_data = DB.achievements[id].get("title", {})
		if title_data is Dictionary and not String(title_data.get("id", "")).is_empty():
			out[String(title_data["id"])] = String(title_data.get("name", title_data["id"]))
	return out


func owned_titles() -> Array:
	var out: Array = [DEFAULT_TITLE]
	for id in titles_owned:
		if not out.has(id):
			out.append(id)
	return out


func equipped_title() -> String:
	return title_equipped if owned_titles().has(title_equipped) else DEFAULT_TITLE


func equipped_title_name() -> String:
	return String(title_catalog().get(equipped_title(), "Recien llegado"))


func equip_title(id: String) -> bool:
	if not owned_titles().has(id):
		return false
	title_equipped = id
	return true


## --- Guardado -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"periodic": periodic.duplicate(true), "achievements": achievements.duplicate(true),
		"titles_owned": titles_owned.duplicate(), "title_equipped": title_equipped,
		"boss_kills": boss_kills.duplicate(), "challenges": challenges.duplicate(),
	}


func from_dict(raw: Variant) -> void:
	periodic = {}
	achievements = {}
	titles_owned = []
	title_equipped = ""
	boss_kills = {}
	challenges = {}
	if not (raw is Dictionary):
		return
	var data: Dictionary = raw
	var per = data.get("periodic", {})
	if per is Dictionary:
		for id in per:
			var e = per[id]
			if e is Dictionary and DB.missions.has(String(id)):
				periodic[String(id)] = { "key": String(e.get("key", "")), "progress": maxi(0, int(e.get("progress", 0))), "claimed": bool(e.get("claimed", false)) }
	var ach = data.get("achievements", {})
	if ach is Dictionary:
		for id in ach:
			var e = ach[id]
			if e is Dictionary and DB.achievements.has(String(id)):
				achievements[String(id)] = { "unlocked": int(e.get("unlocked", 0)), "claimed": bool(e.get("claimed", false)) }
	var owned = data.get("titles_owned", [])
	if owned is Array:
		for id in owned:
			if not titles_owned.has(String(id)):
				titles_owned.append(String(id))
	title_equipped = String(data.get("title_equipped", ""))
	for key in ["boss_kills", "challenges"]:
		var src = data.get(key, {})
		if src is Dictionary:
			for k in src:
				(boss_kills if key == "boss_kills" else challenges)[String(k)] = maxi(0, int(src[k]))
