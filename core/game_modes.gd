extends RefCounted

## MODOS DE JUEGO (X.3): incursiones, mazmorras, roguelike, campo de entrenamiento y Boss Rush.
##
## Una sola clase, un solo origen de combate ("mode", GameState.BATTLE_MODE). Reutiliza TODO lo
## existente: el combate (BattleManager), los enemigos (data/enemies con "based_on" y fases), el
## pago de recompensas (core/rewards.gd), los links y el lider (GameState._tower_lead), las reglas
## de efectos (formato de pasivas/objetos) y el guardado de partida. No hay monedas ni sistemas
## nuevos: solo las del juego.
##
## Datos (todo en JSON, anadir contenido no toca scripts):
##   data/raids/<id>.json         incursiones (jefe enorme con fases, tramos de dano, objetivos)
##   data/dungeons/<id>.json      mazmorras de materiales (dificultades y premios)
##   data/modes/boss_rush.json    cadena de jefes y dificultades
##   data/modes/roguelike.json    mejoras (boons), escalado y premios por profundidad
##   data/modes/training.json     limites del campo de entrenamiento
##
## Estado guardado (clave "modes", aditiva: un guardado anterior no la trae y empieza vacia):
##   raids, dungeons, rush_best, rush_run, rogue_best, rogue_run.
## El campo de entrenamiento NO guarda nada. Las mejoras del roguelike viven solo en rogue_run y
## se montan en cada CombatUnit al empezar el combate: nunca tocan al personaje guardado.

const Rewards := preload("res://core/rewards.gd")

const MODE_RAID := "raid"
const MODE_DUNGEON := "dungeon"
const MODE_RUSH := "rush"
const MODE_ROGUE := "rogue"
const MODE_TRAINING := "training"

var gs = null
var rng := RandomNumberGenerator.new()

## --- Estado guardado --------------------------------------------------------------------
var raids: Dictionary = {}       # raid_id -> { best_damage, attempts, kills, best_phase, week, claimed_tiers, claimed_objectives, log }
var dungeons: Dictionary = {}    # dungeon_id -> { difficulty_id: victorias }
var rush_best: Dictionary = {}   # difficulty -> { bosses, clears, runs, milestones: [n...] }
var rush_run: Dictionary = {}
var rogue_best: Dictionary = {}  # { depth, runs, milestones: [n...] }
var rogue_run: Dictionary = {}

## --- Estado de ejecucion (NO se guarda) ------------------------------------------------------
var ctx: Dictionary = {}          # { mode, ... } de la batalla preparada
var training: Dictionary = {}     # configuracion del campo de entrenamiento
var battle_summary: Dictionary = {}
var last_report: Dictionary = {}


func _init(owner = null) -> void:
	gs = owner
	rng.randomize()
	reset_training()


## =========================================================================================
## Comun
## =========================================================================================

func is_sandbox() -> bool:
	return String(ctx.get("mode", "")) == MODE_TRAINING


func active_mode() -> String:
	return String(ctx.get("mode", ""))


func _scale_of(raw: Variant) -> Dictionary:
	var d: Dictionary = raw if raw is Dictionary else {}
	return { "hp": float(d.get("hp", 1.0)), "atk": float(d.get("atk", 1.0)), "def": float(d.get("def", 1.0)) }


func _mul_scale(a: Dictionary, b: Dictionary) -> Dictionary:
	return { "hp": float(a["hp"]) * float(b["hp"]), "atk": float(a["atk"]) * float(b["atk"]), "def": float(a["def"]) * float(b["def"]) }


## Datos de un enemigo (con escalado). Un id "char:<id>" usa a un personaje como rival (entrenamiento).
func _enemy_dict(enemy_id: String) -> Dictionary:
	if enemy_id.begins_with("char:"):
		var base: Dictionary = DB.get_character(enemy_id.substr(5)).duplicate(true)
		if not base.is_empty():
			base["id"] = "rival_" + String(base.get("id", "x"))
		return base
	return DB.get_enemy(enemy_id).duplicate(true)


func enemy_entries() -> Array:
	var e = ctx.get("enemies", [])
	return e if e is Array else []


## Enemigos de la batalla en curso, ya escalados. GameState.enemy_data() delega aqui.
func enemy_data() -> Array:
	var out: Array = []
	for entry in enemy_entries():
		var d := _enemy_dict(String(entry["id"]))
		if d.is_empty():
			continue
		var stats: Dictionary = (d.get("stats", {}) as Dictionary).duplicate(true)
		stats["max_hp"] = maxf(1.0, roundf(float(stats.get("max_hp", 100)) * float(entry.get("hp", 1.0))))
		stats["atk"] = maxf(1.0, roundf(float(stats.get("atk", 10)) * float(entry.get("atk", 1.0))))
		stats["def"] = maxf(0.0, roundf(float(stats.get("def", 0)) * float(entry.get("def", 1.0))))
		d["stats"] = stats
		out.append(d)
	return out


## "Stage" virtual de la batalla (lo lee la pantalla de combate y GameState.prepare_battle).
func battle_info() -> Dictionary:
	if ctx.is_empty():
		return {}
	var ids: Array = []
	for entry in enemy_entries():
		ids.append(String(entry["id"]))
	return {
		"id": "mode_%s" % String(ctx.get("mode", "")),
		"name": String(ctx.get("name", "")),
		"background": String(ctx.get("background", "battle")),
		"enemies": ids,
		"xp_reward": 0,
		"coin_reward": 0,
		"survive_rounds": int(ctx.get("rounds", 0)),
	}


## Prepara el combate. `team` vacio = el equipo normal del jugador.
func _begin(info: Dictionary, team: Array = []) -> bool:
	ctx = info
	if not gs.prepare_mode_battle({ "mode": String(info.get("mode", "")) }, team):
		ctx = {}
		return false
	return true


func end_context() -> void:
	ctx = {}


## --- Resumen del combate (lo rellena la pantalla de combate al terminar) -----------------

func summarize(manager) -> Dictionary:
	var s := { "damage": 0, "phase": 1, "rounds": int(manager.round_number), "fallen": [], "alive": [],
		"crits": 0, "boss_defeated": false, "hp": {}, "allies": [], "enemies_down": 0, "enemy_total": manager.enemies.size() }
	var enemy_damage := 0
	var all_down := true
	for e in manager.enemies:
		enemy_damage += int(e.battle.value("damage_received")) if e.battle != null else 0
		s["phase"] = maxi(int(s["phase"]), int(e.phase_index) + 1)
		if e.alive:
			all_down = false
		else:
			s["enemies_down"] = int(s["enemies_down"]) + 1
	s["boss_defeated"] = all_down
	var ally_damage := 0
	for a in manager.allies:
		var dealt := int(a.battle.value("damage_dealt")) if a.battle != null else 0
		ally_damage += dealt
		s["crits"] = int(s["crits"]) + (int(a.battle.value("crits")) if a.battle != null else 0)
		var ratio := clampf(a.hp / maxf(1.0, a.max_hp()), 0.0, 1.0) if a.alive else 0.0
		(s["hp"] as Dictionary)[a.id] = ratio
		(s["allies"] as Array).append({ "id": a.id, "name": a.display_name, "damage": dealt,
			"healing": int(a.battle.value("healing_done")) if a.battle != null else 0,
			"received": int(a.battle.value("damage_received")) if a.battle != null else 0,
			"crits": int(a.battle.value("crits")) if a.battle != null else 0, "alive": a.alive, "hp_ratio": ratio })
		if a.alive:
			(s["alive"] as Array).append(a.id)
		else:
			(s["fallen"] as Array).append(a.id)
	s["damage"] = enemy_damage if enemy_damage > 0 else ally_damage
	battle_summary = s
	return s


## Pago de la batalla de un modo. GameState._pay_battle_by_source delega aqui.
func pay(ally_ids: Array, victory: bool) -> Dictionary:
	var report: Dictionary = gs._empty_report()
	report["mode"] = gs.BATTLE_MODE
	report["title"] = String(ctx.get("name", ""))
	var summary := battle_summary.duplicate(true)
	match String(ctx.get("mode", "")):
		MODE_RAID:
			_pay_raid(report, summary, victory)
		MODE_DUNGEON:
			_pay_dungeon(report, summary, ally_ids, victory)
		MODE_RUSH:
			_pay_rush(report, summary, victory)
		MODE_ROGUE:
			_pay_rogue(report, summary, victory)
	battle_summary = {}
	last_report = report.duplicate(true)
	return report


## Informe de un modo SIN premios (entrenamiento): nada se cuenta ni se guarda.
func sandbox_report() -> Dictionary:
	var report: Dictionary = gs._empty_report()
	report["mode"] = gs.BATTLE_MODE
	report["title"] = String(ctx.get("name", ""))
	report["sandbox"] = true
	report["lines"] = ["Entrenamiento: sin recompensas ni progreso."]
	last_report = report.duplicate(true)
	return report


func _pay_reward_block(reward: Dictionary, report: Dictionary) -> void:
	var paid := Rewards.pay(gs, reward)
	report["coins"] = int(report.get("coins", 0)) + int(paid["coins"])
	report["gems"] = int(report.get("gems", 0)) + int(paid["gems"])
	report["materials"] = int(report.get("materials", 0)) + int(paid["materials"])
	for item_id in paid["items"]:
		(report["drops"] as Array).append({ "item": String(item_id), "name": gs.item_display_name(String(item_id)), "amount": int(paid["items"][item_id]) })
	for eid in paid["equipment"]:
		(report["drops"] as Array).append({ "item": String(eid), "name": Equipment_name(String(eid)), "amount": int(paid["equipment"][eid]), "equipment": true })
	report["granted"] = true


func Equipment_name(id: String) -> String:
	return String((DB.equipment.get(id, {}) as Dictionary).get("name", id))


func _lines(report: Dictionary) -> Array:
	if not report.has("lines"):
		report["lines"] = []
	return report["lines"]


## =========================================================================================
## INCURSIONES
## =========================================================================================

func raid_list() -> Array:
	return DB.all_raids()


## Lunes (dia absoluto) de la semana que contiene `day`.
static func _monday_of(day: int) -> int:
	return day - ((day + 3) % 7)


func raid_week_index() -> int:
	var cfg := DB.rotation_config()
	var start := _monday_of(gs._day_of_date(String(cfg.get("raid_start_date", cfg.get("start_date", "2026-11-02")))))
	var now_monday := _monday_of(gs.meta._local_day())
	return int(floor(float(now_monday - start) / 7.0))


## Incursion de ESTA semana: funcion pura de la fecha (rota sola; sobrevive a cerrar el juego).
func current_raid_id() -> String:
	var list := raid_list()
	if list.is_empty():
		return ""
	return String((list[posmod(raid_week_index(), list.size())] as Dictionary)["id"])


func next_raid_id() -> String:
	var list := raid_list()
	if list.is_empty():
		return ""
	return String((list[posmod(raid_week_index() + 1, list.size())] as Dictionary)["id"])


func raid_record(raid_id: String) -> Dictionary:
	var r: Dictionary = raids.get(raid_id, {})
	var week := String(gs.meta.period_key("weekly"))
	if String(r.get("week", "")) != week:
		# Semana nueva: los cobros semanales se reinician; los records se conservan.
		r["week"] = week
		r["claimed_tiers"] = []
		r["claimed_objectives"] = []
		r["week_damage"] = 0
	for key in ["best_damage", "attempts", "kills", "best_phase"]:
		r[key] = int(r.get(key, 0))
	if not (r.get("log", []) is Array):
		r["log"] = []
	r["log"] = r.get("log", [])
	return r


func raid_enemy_max_hp(raid_id: String) -> int:
	var e := DB.get_enemy(String(DB.get_raid(raid_id).get("enemy", "")))
	return int((e.get("stats", {}) as Dictionary).get("max_hp", 0))


func start_raid(raid_id: String) -> bool:
	var raid := DB.get_raid(raid_id)
	if raid.is_empty() or raid_id != current_raid_id():
		return false
	if not gs.team_problem().is_empty():
		return false
	return _begin({ "mode": MODE_RAID, "raid": raid_id, "name": String(raid.get("name", raid_id)),
		"background": String(raid.get("background", "battle")), "rounds": int(raid.get("rounds", 10)),
		"enemies": [{ "id": String(raid.get("enemy", "")), "hp": 1.0, "atk": 1.0, "def": 1.0 }] })


func _objective_met(obj: Dictionary, s: Dictionary) -> bool:
	var v := float(obj.get("value", 0))
	match String(obj.get("type", "")):
		"damage_at_least":
			return float(s.get("damage", 0)) >= v
		"phase_at_least":
			return float(s.get("phase", 1)) >= v
		"no_fallen":
			return (s.get("fallen", []) as Array).is_empty()
		"boss_defeated":
			return bool(s.get("boss_defeated", false))
		"rounds_at_most":
			return bool(s.get("boss_defeated", false)) and float(s.get("rounds", 99)) <= v
		"crits_at_least":
			return float(s.get("crits", 0)) >= v
	return false


func _pay_raid(report: Dictionary, s: Dictionary, victory: bool) -> void:
	var raid_id := String(ctx.get("raid", ""))
	var raid := DB.get_raid(raid_id)
	var rec := raid_record(raid_id)
	var damage := int(s.get("damage", 0))
	rec["attempts"] = int(rec["attempts"]) + 1
	rec["week_damage"] = maxi(int(rec.get("week_damage", 0)), damage)
	var new_record := damage > int(rec["best_damage"])
	rec["best_damage"] = maxi(int(rec["best_damage"]), damage)
	rec["best_phase"] = maxi(int(rec["best_phase"]), int(s.get("phase", 1)))
	if bool(s.get("boss_defeated", false)):
		rec["kills"] = int(rec["kills"]) + 1
	var lines := _lines(report)
	lines.append("Dano al jefe: %d%s" % [damage, "  (NUEVO RECORD)" if new_record else ""])
	lines.append("Fase alcanzada: %d   Rondas: %d" % [int(s.get("phase", 1)), int(s.get("rounds", 0))])
	# Tramos de dano: cada uno se cobra UNA vez por semana.
	for tier in raid.get("tiers", []):
		var need := int((tier as Dictionary).get("damage", 0))
		if damage >= need and not (rec["claimed_tiers"] as Array).has(need):
			(rec["claimed_tiers"] as Array).append(need)
			_pay_reward_block((tier as Dictionary).get("reward", {}), report)
			lines.append("Tramo de %d de dano: %s" % [need, Rewards.describe((tier as Dictionary).get("reward", {}))])
	for obj in raid.get("objectives", []):
		var oid := String((obj as Dictionary).get("id", ""))
		if _objective_met(obj, s) and not (rec["claimed_objectives"] as Array).has(oid):
			(rec["claimed_objectives"] as Array).append(oid)
			_pay_reward_block((obj as Dictionary).get("reward", {}), report)
			lines.append("Objetivo: %s -> %s" % [String((obj as Dictionary).get("text", oid)), Rewards.describe((obj as Dictionary).get("reward", {}))])
	var log: Array = rec["log"]
	log.push_front({ "week": String(rec["week"]), "damage": damage, "phase": int(s.get("phase", 1)), "rounds": int(s.get("rounds", 0)),
		"victory": victory, "boss_defeated": bool(s.get("boss_defeated", false)), "fallen": (s.get("fallen", []) as Array).size() })
	while log.size() > 20:
		log.pop_back()
	raids[raid_id] = rec
	report["raid_damage"] = damage
	report["granted"] = true


## =========================================================================================
## MAZMORRAS
## =========================================================================================

func dungeon_list() -> Array:
	return DB.all_dungeons()


func dungeon_difficulties(dungeon_id: String) -> Array:
	var out: Array = (DB.get_dungeon(dungeon_id).get("difficulties", []) as Array).duplicate()
	out.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return out


func dungeon_clears(dungeon_id: String, difficulty: String) -> int:
	return int((dungeons.get(dungeon_id, {}) as Dictionary).get(difficulty, 0))


func dungeon_unlocked(dungeon_id: String, difficulty: String) -> bool:
	var prev: Dictionary = {}
	for d in dungeon_difficulties(dungeon_id):
		if String(d["id"]) == difficulty:
			if not bool(d.get("requires_previous", true)) or prev.is_empty():
				return true
			return dungeon_clears(dungeon_id, String(prev["id"])) > 0
		prev = d
	return false


func dungeon_difficulty(dungeon_id: String, difficulty: String) -> Dictionary:
	for d in dungeon_difficulties(dungeon_id):
		if String(d["id"]) == difficulty:
			return d
	return {}


func start_dungeon(dungeon_id: String, difficulty: String) -> bool:
	var dungeon := DB.get_dungeon(dungeon_id)
	var diff := dungeon_difficulty(dungeon_id, difficulty)
	if dungeon.is_empty() or diff.is_empty() or not dungeon_unlocked(dungeon_id, difficulty):
		return false
	if not gs.team_problem().is_empty():
		return false
	var scale := _scale_of(diff.get("scale", {}))
	var entries: Array = []
	for id in diff.get("enemies", []):
		entries.append({ "id": String(id), "hp": scale["hp"], "atk": scale["atk"], "def": scale["def"] })
	return _begin({ "mode": MODE_DUNGEON, "dungeon": dungeon_id, "difficulty": difficulty,
		"name": "%s - %s" % [String(dungeon.get("name", dungeon_id)), String(diff.get("name", difficulty))],
		"background": String(dungeon.get("background", "battle")), "rounds": 0, "enemies": entries })


## Un drop de mazmorra: { type: item|equipment|copy, id|pool, chance, min/max|amount }.
func _roll_dungeon_drop(drop: Dictionary, report: Dictionary) -> void:
	if rng.randf() >= float(drop.get("chance", 1.0)):
		return
	match String(drop.get("type", "item")):
		"item":
			var n := rng.randi_range(int(drop.get("min", 1)), maxi(int(drop.get("min", 1)), int(drop.get("max", 1))))
			_pay_reward_block({ "items": { String(drop["id"]): n } }, report)
		"equipment":
			_pay_reward_block({ "equipment": { String(drop["id"]): int(drop.get("amount", 1)) } }, report)
		"copy":
			var owned_pool: Array = []
			for cid in drop.get("pool", []):
				if gs.is_owned(String(cid)):
					owned_pool.append(String(cid))
			if owned_pool.is_empty():
				_pay_reward_block({ "materials": int(drop.get("fallback_materials", 1)) }, report)
				return
			var pick := String(owned_pool[rng.randi_range(0, owned_pool.size() - 1)])
			var n2 := maxi(1, int(drop.get("amount", 1)))
			gs.duplicates[pick] = gs.duplicates_of(pick) + n2
			(report["drops"] as Array).append({ "item": pick, "name": "Copia de %s" % gs.display_name(pick), "amount": n2, "copy": true })
			report["granted"] = true


func _pay_dungeon(report: Dictionary, s: Dictionary, ally_ids: Array, victory: bool) -> void:
	if not victory:
		_lines(report).append("Mazmorra no superada: sin recompensas.")
		return
	var dungeon_id := String(ctx.get("dungeon", ""))
	var difficulty := String(ctx.get("difficulty", ""))
	var diff := dungeon_difficulty(dungeon_id, difficulty)
	var reward: Dictionary = (diff.get("reward", {}) as Dictionary).duplicate(true)
	var xp := int(reward.get("xp", 0))
	reward.erase("xp")
	if xp > 0:
		report["xp"] = xp
		report["characters"] = gs._grant_story_xp(ally_ids, xp)
	if not reward.is_empty():
		_pay_reward_block(reward, report)
	for drop in diff.get("drops", []):
		_roll_dungeon_drop(drop, report)
	var entry: Dictionary = dungeons.get(dungeon_id, {})
	entry[difficulty] = int(entry.get(difficulty, 0)) + 1
	dungeons[dungeon_id] = entry
	report["granted"] = true
	# Nueva dificultad abierta, si la hay.
	var found := false
	for d in dungeon_difficulties(dungeon_id):
		if found and bool(d.get("requires_previous", true)) and dungeon_clears(dungeon_id, String(d["id"])) == 0 and dungeon_clears(dungeon_id, difficulty) == 1:
			report["unlocked_names"] = ["%s - %s" % [String(DB.get_dungeon(dungeon_id).get("name", dungeon_id)), String(d.get("name", d["id"]))]]
			break
		if String(d["id"]) == difficulty:
			found = true


## Recompensa garantizada + posibles drops, en texto (para la pantalla).
func dungeon_reward_text(dungeon_id: String, difficulty: String) -> String:
	var diff := dungeon_difficulty(dungeon_id, difficulty)
	var reward: Dictionary = (diff.get("reward", {}) as Dictionary).duplicate(true)
	var parts := PackedStringArray()
	if int(reward.get("xp", 0)) > 0:
		parts.append("%d XP por personaje" % int(reward["xp"]))
	reward.erase("xp")
	var base := Rewards.describe(reward)
	if not base.is_empty():
		parts.append(base)
	for drop in diff.get("drops", []):
		var label := ""
		match String(drop.get("type", "")):
			"item":
				label = String((DB.items.get(String(drop["id"]), {}) as Dictionary).get("name", drop["id"]))
			"equipment":
				label = Equipment_name(String(drop["id"]))
			"copy":
				label = "copia de personaje"
		parts.append("%s (%d%%)" % [label, int(round(float(drop.get("chance", 1.0)) * 100.0))])
	return ", ".join(parts)


## =========================================================================================
## BOSS RUSH
## =========================================================================================

func rush_config() -> Dictionary:
	return DB.mode_config("boss_rush")


func rush_difficulties() -> Array:
	var out: Array = (rush_config().get("difficulties", []) as Array).duplicate()
	out.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return out


func rush_difficulty(diff_id: String) -> Dictionary:
	for d in rush_difficulties():
		if String(d["id"]) == diff_id:
			return d
	return {}


func rush_record(diff_id: String) -> Dictionary:
	var r: Dictionary = rush_best.get(diff_id, {})
	for key in ["bosses", "clears", "runs"]:
		r[key] = int(r.get(key, 0))
	r["milestones"] = (r["milestones"] as Array) if r.get("milestones", null) is Array else []
	return r


func rush_unlocked(diff_id: String) -> bool:
	var d := rush_difficulty(diff_id)
	if d.is_empty():
		return false
	var req := String(d.get("requires_clear", ""))
	return req.is_empty() or int(rush_record(req)["clears"]) > 0


func rush_active() -> bool:
	return not rush_run.is_empty()


func rush_boss_count() -> int:
	return (rush_config().get("bosses", []) as Array).size()


func rush_scale(diff_id: String, index: int) -> Dictionary:
	var per: Dictionary = rush_config().get("boss_scale_per_index", {})
	var step := _scale_of({ "hp": 1.0 + float(per.get("hp", 0.0)) * index, "atk": 1.0 + float(per.get("atk", 0.0)) * index, "def": 1.0 + float(per.get("def", 0.0)) * index })
	return _mul_scale(_scale_of(rush_difficulty(diff_id).get("scale", {})), step)


## Empieza una carrera nueva con el equipo actual. Si ya hay una en marcha, no la pisa.
func rush_start_run(diff_id: String) -> Dictionary:
	if rush_active():
		return { "ok": false, "reason": "Ya tienes una carrera en marcha." }
	if not rush_unlocked(diff_id):
		return { "ok": false, "reason": "Dificultad bloqueada: supera la anterior." }
	if not gs.team_problem().is_empty():
		return { "ok": false, "reason": gs.team_problem() }
	var team: Array = gs.party_ids().duplicate()
	var hp := {}
	for id in team:
		hp[String(id)] = 1.0
	rush_run = { "difficulty": diff_id, "index": 0, "team": team, "hp": hp, "dead": [], "defeated": 0, "coins": 0, "rounds": 0 }
	var rec := rush_record(diff_id)
	rec["runs"] = int(rec["runs"]) + 1
	rush_best[diff_id] = rec
	return { "ok": true, "reason": "" }


func rush_alive_team() -> Array:
	var out: Array = []
	for id in rush_run.get("team", []):
		if not (rush_run.get("dead", []) as Array).has(String(id)):
			out.append(String(id))
	return out


func rush_next_boss_id() -> String:
	var bosses: Array = rush_config().get("bosses", [])
	var idx := int(rush_run.get("index", 0))
	return String(bosses[idx]) if idx < bosses.size() else ""


## Lanza el siguiente combate de la carrera.
func rush_fight() -> bool:
	if not rush_active():
		return false
	var diff_id := String(rush_run["difficulty"])
	var idx := int(rush_run["index"])
	var boss := rush_next_boss_id()
	var alive := rush_alive_team()
	if boss.is_empty() or alive.is_empty():
		return false
	var scale := rush_scale(diff_id, idx)
	var cfg := rush_config()
	return _begin({ "mode": MODE_RUSH, "name": "%s %s - Jefe %d/%d" % [String(cfg.get("name", "Boss Rush")), String(rush_difficulty(diff_id).get("name", diff_id)), idx + 1, rush_boss_count()],
		"background": String(cfg.get("background", "battle")), "rounds": 0,
		"enemies": [{ "id": boss, "hp": scale["hp"], "atk": scale["atk"], "def": scale["def"] }] }, alive)


## Cierra la carrera (derrota, victoria final o abandono). Apunta el record.
func rush_end_run(cleared: bool) -> void:
	if not rush_active():
		return
	var diff_id := String(rush_run["difficulty"])
	var rec := rush_record(diff_id)
	rec["bosses"] = maxi(int(rec["bosses"]), int(rush_run.get("defeated", 0)))
	if cleared:
		rec["clears"] = int(rec["clears"]) + 1
	rush_best[diff_id] = rec
	rush_run = {}


func rush_abandon() -> void:
	rush_end_run(false)


func _pay_rush(report: Dictionary, s: Dictionary, victory: bool) -> void:
	if not rush_active():
		return
	var diff_id := String(rush_run["difficulty"])
	var diff := rush_difficulty(diff_id)
	var lines := _lines(report)
	rush_run["rounds"] = int(rush_run.get("rounds", 0)) + int(s.get("rounds", 0))
	# El desgaste se arrastra: la vida con la que acaba cada aliado es con la que empieza el siguiente.
	var hp: Dictionary = rush_run["hp"]
	for id in (s.get("hp", {}) as Dictionary):
		hp[String(id)] = float(s["hp"][id])
	for id in (s.get("fallen", []) as Array):
		if not (rush_run["dead"] as Array).has(String(id)):
			(rush_run["dead"] as Array).append(String(id))
	if not victory:
		var reached := int(rush_run.get("defeated", 0))
		lines.append("Derrota. Jefes derrotados en esta carrera: %d" % reached)
		report["rush_defeated"] = reached
		rush_end_run(false)
		return
	rush_run["defeated"] = int(rush_run["defeated"]) + 1
	rush_run["index"] = int(rush_run["index"]) + 1
	var defeated := int(rush_run["defeated"])
	_pay_reward_block(diff.get("per_boss", {}), report)
	lines.append("Jefe %d derrotado: %s" % [defeated, Rewards.describe(diff.get("per_boss", {}))])
	# Recuperacion parcial (nunca total) de los supervivientes.
	var recovery := float(diff.get("recovery", 0.0))
	for id in rush_alive_team():
		hp[id] = minf(1.0, float(hp.get(id, 1.0)) + recovery)
	var rec := rush_record(diff_id)
	for m in diff.get("milestones", []):
		var n := int((m as Dictionary).get("bosses", 0))
		if defeated >= n and not (rec["milestones"] as Array).has(n):
			(rec["milestones"] as Array).append(n)
			_pay_reward_block((m as Dictionary).get("reward", {}), report)
			lines.append("Hito de %d jefes: %s" % [n, Rewards.describe((m as Dictionary).get("reward", {}))])
	rush_best[diff_id] = rec
	report["rush_defeated"] = defeated
	if defeated >= rush_boss_count():
		lines.append("CARRERA COMPLETADA")
		rush_end_run(true)


## =========================================================================================
## ROGUELIKE
## =========================================================================================

func rogue_config() -> Dictionary:
	return DB.mode_config("roguelike")


func rogue_active() -> bool:
	return not rogue_run.is_empty()


func rogue_record() -> Dictionary:
	var r: Dictionary = rogue_best.duplicate()
	r["depth"] = int(r.get("depth", 0))
	r["runs"] = int(r.get("runs", 0))
	r["milestones"] = (r["milestones"] as Array) if r.get("milestones", null) is Array else []
	return r


func rogue_boon(boon_id: String) -> Dictionary:
	for b in rogue_config().get("boons", []):
		if String((b as Dictionary).get("id", "")) == boon_id:
			return b
	return {}


## Elige un equipo y empieza. Los personajes deben ser tuyos; nada de ellos se modifica.
func rogue_start_run(team: Array) -> Dictionary:
	if rogue_active():
		return { "ok": false, "reason": "Ya tienes una partida en marcha." }
	var ids: Array = []
	for raw in team:
		var id := String(raw)
		if gs.is_owned(id) and not ids.has(id):
			ids.append(id)
	var size_max := int(rogue_config().get("team_size", 4))
	if ids.is_empty():
		return { "ok": false, "reason": "Elige al menos un personaje." }
	if ids.size() > size_max:
		return { "ok": false, "reason": "Maximo %d personajes." % size_max }
	var hp := {}
	for id in ids:
		hp[id] = 1.0
	rogue_run = { "team": ids, "hp": hp, "dead": [], "depth": 0, "boons": {}, "items": {}, "seed": rng.randi(), "phase": "fight", "choices": [], "rounds": 0 }
	var rec := rogue_record()
	rec["runs"] = int(rec["runs"]) + 1
	rogue_best = rec
	return { "ok": true, "reason": "" }


func rogue_alive_team() -> Array:
	var out: Array = []
	for id in rogue_run.get("team", []):
		if not (rogue_run.get("dead", []) as Array).has(String(id)):
			out.append(String(id))
	return out


func _rogue_rng(depth: int, salt: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(rogue_run.get("seed", 1)) * 7919 + depth * 104729 + salt
	return r


## Enemigos del combate de profundidad `depth` (1..). Salen de la semilla de la partida: la misma
## partida (aunque se recargue) ve lo mismo y dos partidas distintas ven combinaciones distintas.
func rogue_enemies_for(depth: int) -> Array:
	var cfg := rogue_config()
	var r := _rogue_rng(depth, 11)
	var sc: Dictionary = cfg.get("scaling", {})
	var step := depth - 1
	var scale := { "hp": 1.0 + float(sc.get("hp_per_depth", 0.0)) * step, "atk": 1.0 + float(sc.get("atk_per_depth", 0.0)) * step, "def": 1.0 + float(sc.get("def_per_depth", 0.0)) * step }
	var out: Array = []
	var boss_every := int(cfg.get("boss_every", 5))
	if boss_every > 0 and depth % boss_every == 0:
		var bosses: Array = cfg.get("boss_pool", [])
		out.append({ "id": String(bosses[r.randi_range(0, bosses.size() - 1)]), "hp": scale["hp"] * 1.3, "atk": scale["atk"], "def": scale["def"] })
		return out
	var ec: Dictionary = cfg.get("enemy_count", {})
	var count := mini(int(ec.get("max", 3)), int(ec.get("base", 1)) + int(floor(float(step) / maxf(1.0, float(ec.get("per_depths", 3))))))
	var pool: Array = cfg.get("enemy_pool", [])
	# Los rivales fuertes (final del pool) entran con la profundidad.
	var reach := mini(pool.size(), 2 + int(floor(float(step) / 3.0)))
	for i in count:
		out.append({ "id": String(pool[r.randi_range(0, reach - 1)]), "hp": scale["hp"], "atk": scale["atk"], "def": scale["def"] })
	return out


func rogue_links_active() -> int:
	return int(rogue_run.get("links", 0))


func _boon_eligible(boon: Dictionary) -> bool:
	var stacks := int((rogue_run.get("boons", {}) as Dictionary).get(String(boon["id"]), 0))
	if stacks >= int(boon.get("max_stacks", 1)):
		return false
	var cat := String(boon.get("requires_category", ""))
	if not cat.is_empty():
		var any := false
		for id in rogue_alive_team():
			if (DB.get_character(String(id)).get("categories", []) as Array).has(cat):
				any = true
		if not any:
			return false
	if bool(boon.get("requires_links", false)) and _team_link_count(rogue_alive_team()) <= 0:
		return false
	return true


func _team_link_count(team: Array) -> int:
	var saved: Array = gs._tower_lead
	gs._tower_lead = team.duplicate()
	var n: int = gs.active_link_ids().size()
	gs._tower_lead = saved
	return n


## Las 3 mejoras entre las que elegir tras ganar el combate de `depth`. Determinista por (semilla, profundidad).
func rogue_generate_choices(depth: int) -> Array:
	var cfg := rogue_config()
	var weights: Dictionary = cfg.get("rarity_weights", {})
	var pool: Array = []
	for b in cfg.get("boons", []):
		if _boon_eligible(b):
			pool.append(b)
	var r := _rogue_rng(depth, 53)
	var picks: Array = []
	var want := int(cfg.get("choices", 3))
	var item_cfg: Dictionary = cfg.get("item_choices", {})
	var item_chance := float(item_cfg.get("chance", 0.0))
	var item_pool := _rogue_item_pool()
	while picks.size() < want:
		var made := false
		# Un objeto equipable (temporal) en lugar de una mejora.
		if item_chance > 0.0 and not item_pool.is_empty() and r.randf() < item_chance:
			var iw: Dictionary = item_cfg.get("rarity_weights", {})
			var total_i := 0.0
			for id in item_pool:
				total_i += float(iw.get(String((DB.equipment[id] as Dictionary).get("rarity", "N")), 10))
			var xi := r.randf() * total_i
			var ci := 0
			for k in item_pool.size():
				xi -= float(iw.get(String((DB.equipment[item_pool[k]] as Dictionary).get("rarity", "N")), 10))
				if xi <= 0.0:
					ci = k
					break
			picks.append("item:%s" % String(item_pool[ci]))
			item_pool.remove_at(ci)
			made = true
		if not made:
			if pool.is_empty():
				break
			var total := 0.0
			for b in pool:
				total += float(weights.get(String(b.get("rarity", "common")), 10))
			var x := r.randf() * total
			var chosen := 0
			for i in pool.size():
				x -= float(weights.get(String((pool[i] as Dictionary).get("rarity", "common")), 10))
				if x <= 0.0:
					chosen = i
					break
			picks.append(String((pool[chosen] as Dictionary)["id"]))
			pool.remove_at(chosen)
	return picks


## Objetos equipables que aun pueden ofrecerse (los que la partida ya lleva no se repiten).
func _rogue_item_pool() -> Array:
	var held: Array = (rogue_run.get("items", {}) as Dictionary).values()
	var out: Array = []
	for item in DB.all_equipment():
		var id := String(item["id"])
		if not held.has(id):
			out.append(id)
	return out


func rogue_fight() -> bool:
	if not rogue_active() or String(rogue_run.get("phase", "")) != "fight":
		return false
	var alive := rogue_alive_team()
	if alive.is_empty():
		return false
	var depth := int(rogue_run["depth"]) + 1
	var cfg := rogue_config()
	rogue_run["links"] = _team_link_count(alive)
	return _begin({ "mode": MODE_ROGUE, "name": "%s - Combate %d" % [String(cfg.get("name", "Roguelike")), depth],
		"background": String(cfg.get("background", "battle")), "rounds": 0, "enemies": rogue_enemies_for(depth) }, alive)


func rogue_pick(choice_id: String, holder: String = "") -> Dictionary:
	if not rogue_active() or String(rogue_run.get("phase", "")) != "choose":
		return { "ok": false, "reason": "No hay mejora que elegir." }
	if not (rogue_run.get("choices", []) as Array).has(choice_id):
		return { "ok": false, "reason": "Esa mejora no estaba entre las ofrecidas." }
	var boons: Dictionary = rogue_run["boons"]
	if choice_id.begins_with("item:"):
		var item_id := choice_id.substr(5)
		var alive := rogue_alive_team()
		var target := holder
		if target.is_empty():
			# Sin portador indicado: el primero vivo que aun no lleva objeto de la partida.
			for id in alive:
				if not (rogue_run["items"] as Dictionary).has(String(id)):
					target = String(id)
					break
			if target.is_empty() and not alive.is_empty():
				target = String(alive[0])
		if not alive.has(target):
			return { "ok": false, "reason": "Ese personaje no puede llevarlo." }
		(rogue_run["items"] as Dictionary)[target] = item_id
	else:
		boons[choice_id] = int(boons.get(choice_id, 0)) + 1
	# Descanso entre combates: cura parcial a los vivos (base + Botiquin).
	var heal := float(rogue_config().get("base_rest_heal", 0.0))
	for key in boons:
		heal += float(rogue_boon(String(key)).get("rest_heal", 0.0)) * int(boons[key])
	var hp: Dictionary = rogue_run["hp"]
	for id in rogue_alive_team():
		hp[id] = minf(1.0, float(hp.get(id, 1.0)) + heal)
	rogue_run["choices"] = []
	rogue_run["phase"] = "fight"
	return { "ok": true, "reason": "" }


## Pago por progreso al terminar la partida (derrota, abandono o cima): monedas por profundidad
## y hitos la primera vez que se alcanzan. Un solo cobro: vacia la partida.
func rogue_end_run() -> Dictionary:
	var report: Dictionary = gs._empty_report()
	report["mode"] = gs.BATTLE_MODE
	report["title"] = String(rogue_config().get("name", "Roguelike"))
	if not rogue_active():
		return report
	var depth := int(rogue_run.get("depth", 0))
	var held_items: Dictionary = (rogue_run.get("items", {}) as Dictionary).duplicate()
	var rewards_cfg: Dictionary = rogue_config().get("rewards", {})
	var lines := _lines(report)
	var rec := rogue_record()
	var new_record := depth > int(rec["depth"])
	rec["depth"] = maxi(int(rec["depth"]), depth)
	if depth > 0:
		var per: Dictionary = (rewards_cfg.get("per_depth", {}) as Dictionary).duplicate(true)
		for key in ["coins", "gems", "materials"]:
			if per.has(key):
				per[key] = int(per[key]) * depth
		_pay_reward_block(per, report)
		lines.append("Profundidad alcanzada: %d%s" % [depth, "  (NUEVO RECORD)" if new_record else ""])
		lines.append("Por progreso: %s" % Rewards.describe(per))
		for m in rewards_cfg.get("milestones", []):
			var n := int((m as Dictionary).get("depth", 0))
			if depth >= n and not (rec["milestones"] as Array).has(n):
				(rec["milestones"] as Array).append(n)
				_pay_reward_block((m as Dictionary).get("reward", {}), report)
				lines.append("Hito de profundidad %d: %s" % [n, Rewards.describe((m as Dictionary).get("reward", {}))])
	else:
		lines.append("Partida abandonada sin ganar ningun combate.")
	if not held_items.is_empty():
		lines.append("Los objetos de la partida se pierden al terminar (eran temporales).")
	rogue_best = rec
	rogue_run = {}
	last_report = report.duplicate(true)
	return report


func _pay_rogue(report: Dictionary, s: Dictionary, victory: bool) -> void:
	if not rogue_active():
		return
	var hp: Dictionary = rogue_run["hp"]
	for id in (s.get("hp", {}) as Dictionary):
		hp[String(id)] = float(s["hp"][id])
	for id in (s.get("fallen", []) as Array):
		if not (rogue_run["dead"] as Array).has(String(id)):
			(rogue_run["dead"] as Array).append(String(id))
	rogue_run["rounds"] = int(rogue_run.get("rounds", 0)) + int(s.get("rounds", 0))
	if not victory:
		var final := rogue_end_run()
		for key in ["coins", "gems", "materials", "drops", "lines", "granted"]:
			report[key] = final[key] if final.has(key) else report.get(key)
		return
	rogue_run["depth"] = int(rogue_run["depth"]) + 1
	var depth := int(rogue_run["depth"])
	var lines := _lines(report)
	lines.append("Combate %d superado." % depth)
	if depth >= int(rogue_config().get("max_depth", 30)):
		var final2 := rogue_end_run()
		for key in ["coins", "gems", "materials", "drops", "granted"]:
			report[key] = final2[key]
		for l in final2.get("lines", []):
			lines.append(l)
		return
	rogue_run["choices"] = rogue_generate_choices(depth)
	rogue_run["phase"] = "choose"
	lines.append("Elige una mejora.")
	report["granted"] = true


## =========================================================================================
## CAMPO DE ENTRENAMIENTO (sandbox: no paga, no cuenta, no guarda)
## =========================================================================================

func training_config() -> Dictionary:
	return DB.mode_config("training")


func reset_training() -> void:
	training = { "allies": [], "enemies": [], "enemy_mult": 1.0, "ally_hp": 1.0, "enemy_hp": 1.0, "ally_sp": 0, "enemy_sp": 0, "rounds": 0, "loadout": {} }


func training_problem() -> String:
	if (training["allies"] as Array).is_empty():
		return "Elige al menos un personaje."
	if (training["enemies"] as Array).is_empty():
		return "Elige al menos un enemigo."
	return ""


func start_training() -> bool:
	if not training_problem().is_empty():
		return false
	var entries: Array = []
	var m := float(training["enemy_mult"])
	for id in training["enemies"]:
		entries.append({ "id": String(id), "hp": m, "atk": m, "def": m })
	var team: Array = []
	for id in training["allies"]:
		if gs.is_owned(String(id)):
			team.append(String(id))
	if team.is_empty():
		return false
	return _begin({ "mode": MODE_TRAINING, "name": "Campo de entrenamiento", "background": String(training_config().get("background", "battle")),
		"rounds": int(training["rounds"]), "enemies": entries }, team)


## Asignacion de objetos para el combate. En entrenamiento manda la configuracion (cualquier objeto
## del catalogo, sin tocar lo que llevan puesto tus personajes); en el resto, el equipo real.
func equipment_assignment(unit_ids: Array) -> Dictionary:
	var assignment: Dictionary = gs.equipment.assignment_for(unit_ids)
	if active_mode() == MODE_ROGUE:
		# Objetos de la partida: SOLO en este combate, sustituyen al guardado y no tocan tu inventario.
		var run_items: Dictionary = rogue_run.get("items", {})
		for ch in run_items:
			if not unit_ids.has(String(ch)):
				continue
			for other in assignment.keys():
				if String(assignment[other]) == String(run_items[ch]):
					assignment.erase(other)
			assignment[String(ch)] = String(run_items[ch])
		return assignment
	if not is_sandbox():
		return assignment
	var loadout: Dictionary = training.get("loadout", {})
	for id in loadout:
		var item := String(loadout[id])
		if item.is_empty():
			assignment.erase(String(id))
		elif DB.equipment.has(item):
			assignment[String(id)] = item
	return assignment


## =========================================================================================
## Aplicacion al combate (BattleManager._apply_mode_state)
## =========================================================================================

func apply_battle_state(manager) -> void:
	var mode := String(ctx.get("mode", ""))
	if mode.is_empty():
		return
	var hp_map: Dictionary = {}
	match mode:
		MODE_RUSH:
			hp_map = rush_run.get("hp", {})
		MODE_ROGUE:
			hp_map = rogue_run.get("hp", {})
			_apply_boons(manager)
		MODE_TRAINING:
			for a in manager.allies:
				hp_map[a.id] = float(training["ally_hp"])
			for e in manager.enemies:
				e.hp = maxf(1.0, e.max_hp() * float(training["enemy_hp"]))
			for a in manager.allies:
				a.sp = int(training["ally_sp"])
			for e in manager.enemies:
				e.sp = int(training["enemy_sp"])
	# Vida de partida: la que arrastra la carrera (o la configurada), nunca el 100% si hay desgaste.
	for a in manager.allies:
		if hp_map.has(a.id):
			a.hp = maxf(1.0, roundf(a.max_hp() * clampf(float(hp_map[a.id]), 0.01, 1.0)))
		else:
			a.hp = a.max_hp()


func _apply_boons(manager) -> void:
	var boons: Dictionary = rogue_run.get("boons", {})
	var links := int(rogue_run.get("links", 0))
	for boon_id in boons:
		var boon := rogue_boon(String(boon_id))
		var stacks := int(boons[boon_id])
		if boon.is_empty() or stacks <= 0:
			continue
		var cat := String(boon.get("requires_category", ""))
		var mult := float(stacks) * (float(links) if bool(boon.get("per_link", false)) else 1.0)
		for u in manager.allies:
			if not cat.is_empty() and not (u.categories as Array).has(cat):
				continue
			for rule in boon.get("rules", []):
				if String((rule as Dictionary).get("trigger", "static")) == "static":
					for effect in (rule as Dictionary).get("effects", []):
						if String((effect as Dictionary).get("type", "")) == "stat_mod":
							var kind := String(effect.get("kind", "mult"))
							u.stats.add_mod(String(effect["stat"]), kind, float(effect.get("value", 0.0)) * mult, "boon:%s" % String(boon_id))
				else:
					var copy: Dictionary = (rule as Dictionary).duplicate(true)
					copy["id"] = "boon_%s_%s" % [String(boon_id), String(rule.get("id", "r"))]
					copy["name"] = String(boon.get("name", boon_id))
					copy["origin"] = "boon"
					for effect in copy.get("effects", []):
						for key in boon.get("scale_keys", []):
							if (effect as Dictionary).has(key):
								effect[key] = float(effect[key]) * float(stacks) if not (effect[key] is int and key == "charges") else int(effect[key]) * stacks
					u.equipment_rules.append(copy)


## =========================================================================================
## Guardado
## =========================================================================================

func to_dict() -> Dictionary:
	return { "raids": raids.duplicate(true), "dungeons": dungeons.duplicate(true), "rush_best": rush_best.duplicate(true),
		"rush_run": rush_run.duplicate(true), "rogue_best": rogue_best.duplicate(true), "rogue_run": rogue_run.duplicate(true) }


func from_dict(d: Dictionary) -> void:
	raids = _dict_or_empty(d.get("raids"))
	dungeons = _dict_or_empty(d.get("dungeons"))
	rush_best = _dict_or_empty(d.get("rush_best"))
	rush_run = _dict_or_empty(d.get("rush_run"))
	rogue_best = _dict_or_empty(d.get("rogue_best"))
	rogue_run = _dict_or_empty(d.get("rogue_run"))
	# Una carrera guardada con contenido que ya no existe (jefe/dificultad retirados) se descarta.
	if not rush_run.is_empty() and (rush_difficulty(String(rush_run.get("difficulty", ""))).is_empty() or rush_next_boss_id().is_empty() and int(rush_run.get("index", 0)) < rush_boss_count()):
		rush_run = {}
	ctx = {}
	reset_training()


static func _dict_or_empty(v: Variant) -> Dictionary:
	return (v as Dictionary).duplicate(true) if v is Dictionary else {}


## =========================================================================================
## Validacion de datos (diagnostico y pruebas)
## =========================================================================================

func data_problems() -> Array:
	var out: Array = []
	for raid in DB.all_raids():
		var rid := String(raid["id"])
		if DB.enemies.has(String(raid.get("enemy", ""))) == false:
			out.append("incursion %s: enemigo '%s' no existe" % [rid, raid.get("enemy", "")])
		elif (DB.get_enemy(String(raid["enemy"])).get("phases", []) as Array).size() < 2:
			out.append("incursion %s: el jefe necesita varias fases" % rid)
		if int(raid.get("rounds", 0)) <= 0:
			out.append("incursion %s: sin limite de rondas" % rid)
		for tier in raid.get("tiers", []):
			out.append_array(Rewards.problems((tier as Dictionary).get("reward", {}), "incursion %s tramo %s" % [rid, (tier as Dictionary).get("damage", "?")]))
		for obj in raid.get("objectives", []):
			out.append_array(Rewards.problems((obj as Dictionary).get("reward", {}), "incursion %s objetivo %s" % [rid, (obj as Dictionary).get("id", "?")]))
			if not ["damage_at_least", "phase_at_least", "no_fallen", "boss_defeated", "rounds_at_most", "crits_at_least"].has(String((obj as Dictionary).get("type", ""))):
				out.append("incursion %s: objetivo '%s' de tipo desconocido" % [rid, (obj as Dictionary).get("id", "?")])
	for dungeon in DB.all_dungeons():
		var did := String(dungeon["id"])
		if (dungeon.get("difficulties", []) as Array).is_empty():
			out.append("mazmorra %s: sin dificultades" % did)
		for diff in dungeon.get("difficulties", []):
			for enemy in (diff as Dictionary).get("enemies", []):
				if not DB.enemies.has(String(enemy)):
					out.append("mazmorra %s/%s: enemigo '%s' no existe" % [did, (diff as Dictionary).get("id", "?"), enemy])
			var rwd: Dictionary = ((diff as Dictionary).get("reward", {}) as Dictionary).duplicate(true)
			rwd.erase("xp")
			if not rwd.is_empty():
				out.append_array(Rewards.problems(rwd, "mazmorra %s/%s" % [did, (diff as Dictionary).get("id", "?")]))
			for drop in (diff as Dictionary).get("drops", []):
				match String((drop as Dictionary).get("type", "")):
					"item":
						if not DB.items.has(String(drop.get("id", ""))):
							out.append("mazmorra %s: drop de objeto '%s' no existe" % [did, drop.get("id", "")])
					"equipment":
						if not DB.equipment.has(String(drop.get("id", ""))):
							out.append("mazmorra %s: equipable '%s' no existe" % [did, drop.get("id", "")])
					"copy":
						for c in drop.get("pool", []):
							if not DB.characters.has(String(c)):
								out.append("mazmorra %s: personaje '%s' no existe" % [did, c])
					_:
						out.append("mazmorra %s: tipo de drop desconocido" % did)
	var rush := rush_config()
	if rush.is_empty():
		out.append("falta data/modes/boss_rush.json")
	for b in rush.get("bosses", []):
		if not DB.enemies.has(String(b)):
			out.append("boss rush: jefe '%s' no existe" % b)
	for d in rush.get("difficulties", []):
		out.append_array(Rewards.problems((d as Dictionary).get("per_boss", {}), "boss rush %s por jefe" % (d as Dictionary).get("id", "?")))
		for m in (d as Dictionary).get("milestones", []):
			out.append_array(Rewards.problems((m as Dictionary).get("reward", {}), "boss rush %s hito" % (d as Dictionary).get("id", "?")))
	var rogue := rogue_config()
	if rogue.is_empty():
		out.append("falta data/modes/roguelike.json")
	for e in (rogue.get("enemy_pool", []) as Array) + (rogue.get("boss_pool", []) as Array):
		if not DB.enemies.has(String(e)):
			out.append("roguelike: enemigo '%s' no existe" % e)
	var seen := {}
	for b in rogue.get("boons", []):
		var bid := String((b as Dictionary).get("id", ""))
		if bid.is_empty() or seen.has(bid):
			out.append("roguelike: mejora sin id o repetida '%s'" % bid)
		seen[bid] = true
		if not (b as Dictionary).has("rules") or (((b as Dictionary)["rules"] as Array).is_empty() and not (b as Dictionary).has("rest_heal")):
			out.append("roguelike: mejora '%s' sin efectos" % bid)
		for rule in (b as Dictionary).get("rules", []):
			for effect in (rule as Dictionary).get("effects", []):
				if not Equipment_effect_ok(String((effect as Dictionary).get("type", ""))):
					out.append("roguelike: mejora '%s' con efecto desconocido" % bid)
		var rc := String((b as Dictionary).get("requires_category", ""))
		if not rc.is_empty() and not DB.categories.has(rc):
			out.append("roguelike: mejora '%s' usa la categoria inexistente '%s'" % [bid, rc])
	for m in (rogue.get("rewards", {}) as Dictionary).get("milestones", []):
		out.append_array(Rewards.problems((m as Dictionary).get("reward", {}), "roguelike hito %s" % (m as Dictionary).get("depth", "?")))
	return out


static func Equipment_effect_ok(effect_type: String) -> bool:
	return ["damage", "heal", "stat_mod", "sp_gain", "status", "shield", "periodic", "cleanse", "dispel", "sp_drain", "undying"].has(effect_type)
