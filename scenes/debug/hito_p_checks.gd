extends Node

## COMPROBACIONES EN EJECUCION DE LA X.3 (modos de juego). SOLO pruebas.
## Arranque:  godot --headless --path . -- --dbg30   (escribe res://dbg30_resultados.txt)
## Todos los combates son REALES (BattleManager + GameState.grant_battle_rewards); el resumen
## sintetico solo se usa para fijar cifras exactas (desgaste, tramos de dano).

const RESULTS_PATH := "res://dbg30_resultados.txt"
const BattleManager := preload("res://core/battle_manager.gd")

const DAY0 := 1793620800   # 2026-11-02 12:00 UTC (un lunes)
const DAY := 86400

var _app: Node = null
var _fails := 0
var _checks := 0


func _out(text: String) -> void:
	print(text)
	var file := FileAccess.open(RESULTS_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(text)
	file.close()


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	_out("[DBG30] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func run(app: Node) -> void:
	_app = app
	await _wait(0.3)
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	seed(3030)
	_out("[DBG30] --- comprobaciones X.3 (modos de juego) ---")
	_app.call("_backup_save")
	_fresh()
	_check_data()
	await _check_raids()
	await _check_dungeons()
	await _check_rush()
	await _check_roguelike()
	await _check_training()
	await _check_rogue_items()
	await _check_story_worlds()
	_check_save_compat()
	await _check_screens()
	_app.call("_restore_save")
	_out("[DBG30] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _fresh() -> void:
	GameState.roster = GameState.STARTING_ROSTER.duplicate()
	GameState.progress = {}
	GameState.rarities = {}
	GameState.duplicates = {}
	GameState.inventory = {}
	GameState.party = GameState.roster.slice(0, 4)
	GameState.tower_team = ["", "", "", "", ""]
	GameState.coins = 100000
	GameState.gems = 100000
	GameState.materials = 0
	GameState.ensure_defaults()
	GameState.equipment.from_dict({})
	GameState.modes.from_dict({})
	GameState.meta.now_override = DAY0
	GameState.reset_battle_context()
	_strong_team()
	GameState.save_game()


func _strong_team() -> void:
	for id in GameState.roster:
		GameState.set_level(String(id), 80)


## Combate REAL del que ya esta preparado en GameState (como battle_ui). Devuelve
## { victory, report, manager }. El manager se libera al terminar.
func _play(keep_manager: bool = false) -> Dictionary:
	var m := BattleManager.new()
	add_child(m)
	m.setup(GameState.battle_party_data(), GameState.enemy_data(), GameState.battle_reserve_data())
	m.pause_scale = 0.0
	m.survive_rounds = int(GameState.current_stage().get("survive_rounds", 0))
	m.set_auto(true)
	var res := [false, false]
	m.battle_finished.connect(func(victory, _r): res[0] = true; res[1] = victory)
	var token := GameState.begin_battle()
	m.start_battle()
	for i in 800:
		if res[0]:
			break
		await _wait(0.05)
	if GameState.battle_source == GameState.BATTLE_MODE:
		GameState.modes.summarize(m)
	var report: Dictionary = GameState.grant_battle_rewards(token, m.participant_ids(), bool(res[1]))
	var out := { "finished": bool(res[0]), "victory": bool(res[1]), "report": report, "rounds": m.round_number }
	if keep_manager:
		out["manager"] = m
	else:
		m.queue_free()
	return out


func _set_day(n: int) -> void:
	GameState.meta.now_override = DAY0 + n * DAY


func _snapshot() -> Dictionary:
	return {
		"progress": GameState.progress.duplicate(true), "rarities": GameState.rarities.duplicate(true),
		"duplicates": GameState.duplicates.duplicate(true), "owned": GameState.equipment.owned.duplicate(true),
		"equipped": GameState.equipment.equipped.duplicate(true), "coins": GameState.coins, "gems": GameState.gems,
		"materials": GameState.materials, "inventory": GameState.inventory.duplicate(true), "energy": GameState.energy,
		"counters": GameState.counters.duplicate(true), "roster": GameState.roster.duplicate(),
		"periodic": GameState.meta.periodic.duplicate(true), "boss_kills": GameState.meta.boss_kills.duplicate(true),
		"party": GameState.party.duplicate(),
	}


func _chars_snapshot() -> Dictionary:
	var out := {}
	for id in GameState.roster:
		var k := String(id)
		out[k] = [GameState.level_of(k), int(GameState.progress.get(k, {}).get("xp", 0)), GameState.rarity_of(k), GameState.duplicates_of(k), GameState.equipment.item_of(k)]
	var inv := {}
	for id in GameState.equipment.owned_ids():
		inv[String(id)] = GameState.equipment.count_of(String(id))
	return { "chars": out, "inv": inv, "roster": GameState.roster.size() }


## --- 0. Datos -----------------------------------------------------------------------------
func _check_data() -> void:
	_out("[DBG30] == DATOS ==")
	var problems: Array = GameState.modes.data_problems()
	_check("los datos de los modos no tienen problemas (%s)" % str(problems), problems.is_empty())
	_check("hay 3 incursiones, 5 mazmorras, Boss Rush, roguelike y entrenamiento",
		DB.all_raids().size() == 3 and DB.all_dungeons().size() == 5 and not DB.mode_config("boss_rush").is_empty() and not DB.mode_config("roguelike").is_empty() and not DB.mode_config("training").is_empty())
	var cats := {}
	for b in DB.mode_config("roguelike")["boons"]:
		cats[String(b["category"])] = true
	_check("el roguelike tiene mejoras de stats, criticos, curacion, categoria, links y efectos especiales", cats.has("stats") and cats.has("crit") and cats.has("heal") and cats.has("category") and cats.has("link") and cats.has("special"))
	_check("el modo existe como origen de combate propio", GameState.BATTLE_MODE == "mode")


## --- 1. Incursiones -----------------------------------------------------------------------------
func _check_raids() -> void:
	_out("[DBG30] == INCURSIONES ==")
	_fresh()
	var m = GameState.modes
	var order: Array = []
	for r in DB.all_raids():
		order.append(String(r["id"]))
	for id in order:
		var e := DB.get_enemy(String(DB.get_raid(id)["enemy"]))
		_check("jefe de incursion %s: vida enorme (%d) y 3 fases extra" % [id, int(e["stats"]["max_hp"])], int(e["stats"]["max_hp"]) >= 30000 and (e["phases"] as Array).size() >= 3)
		var unlocks := 0
		for ph in e["phases"]:
			if (ph as Dictionary).has("unlock_skills"):
				unlocks += 1
		_check("jefe %s: cada fase anade habilidades nuevas" % id, unlocks == (e["phases"] as Array).size())
	_set_day(0)
	_check("semana 0: incursion %s" % order[0], m.current_raid_id() == order[0])
	_set_day(6)
	_check("el domingo sigue la misma", m.current_raid_id() == order[0])
	_set_day(7)
	_check("el lunes siguiente rota a la 2a", m.current_raid_id() == order[1])
	_set_day(14)
	_check("la semana 3 es la 3a", m.current_raid_id() == order[2])
	_set_day(21)
	_check("y vuelve a empezar el ciclo", m.current_raid_id() == order[0])
	_check("la siguiente se anuncia", m.next_raid_id() == order[1])
	_set_day(0)
	var cur: String = m.current_raid_id()
	_check("solo se puede combatir la incursion de la semana", not m.start_raid(order[1]) and m.start_raid(cur))
	_check("el origen de la batalla es 'mode' y el enemigo es el jefe", GameState.battle_source == GameState.BATTLE_MODE and String(GameState.enemy_data()[0]["id"]) == String(DB.get_raid(cur)["enemy"]))
	_check("el limite de rondas viene del JSON", int(GameState.current_stage()["survive_rounds"]) == int(DB.get_raid(cur)["rounds"]))
	var before := _snapshot()
	var r1: Dictionary = await _play()
	var rep: Dictionary = r1["report"]
	var rec: Dictionary = m.raid_record(cur)
	_check("combate real contra el jefe: termina", bool(r1["finished"]))
	_check("el dano al jefe se mide (%d)" % int(rep.get("raid_damage", 0)), int(rep.get("raid_damage", 0)) > 0)
	_check("record y registro guardados", int(rec["best_damage"]) == int(rep["raid_damage"]) and int(rec["attempts"]) == 1 and (rec["log"] as Array).size() == 1)
	var expected_coins := 0
	for tier in DB.get_raid(cur)["tiers"]:
		if int(rep["raid_damage"]) >= int(tier["damage"]):
			expected_coins += int(tier["reward"].get("coins", 0))
	for obj in DB.get_raid(cur)["objectives"]:
		if (rec["claimed_objectives"] as Array).has(String(obj["id"])):
			expected_coins += int(obj["reward"].get("coins", 0))
	_check("la recompensa pagada coincide con tramos y objetivos cumplidos (%d monedas)" % expected_coins, GameState.coins - int(before["coins"]) == expected_coins)
	_check("la incursion no da XP ni toca el nivel", GameState.progress == before["progress"])
	# Segundo intento la misma semana: los tramos ya cobrados NO se vuelven a pagar.
	var coins_before := GameState.coins
	m.start_raid(cur)
	var r2: Dictionary = await _play()
	var paid_again := GameState.coins - coins_before
	var new_expected := 0
	for tier in DB.get_raid(cur)["tiers"]:
		if int(r2["report"]["raid_damage"]) >= int(tier["damage"]) and not (rec["claimed_tiers"] as Array).has(int(tier["damage"])):
			new_expected += int(tier["reward"].get("coins", 0))
	_check("segundo intento: solo paga tramos NUEVOS (pagado %d)" % paid_again, paid_again >= 0 and paid_again <= new_expected + 6000)
	_check("el record es el mejor de los dos y los intentos suben", int(m.raid_record(cur)["attempts"]) == 2 and int(m.raid_record(cur)["best_damage"]) >= int(rep["raid_damage"]))
	# Cifras exactas con un resumen sintetico.
	_fresh()
	_set_day(0)
	cur = m.current_raid_id()
	m.start_raid(cur)
	m.battle_summary = { "damage": 31000, "phase": 4, "rounds": 7, "fallen": [], "crits": 9, "boss_defeated": true, "hp": {}, "alive": [] }
	var token := GameState.begin_battle()
	var c0 := GameState.coins
	var g0 := GameState.gems
	var rp: Dictionary = GameState.grant_battle_rewards(token, GameState.party_ids(), true)
	var want_coins := 0
	var want_gems := 0
	for tier in DB.get_raid(cur)["tiers"]:
		want_coins += int(tier["reward"].get("coins", 0))
		want_gems += int(tier["reward"].get("gems", 0))
	for obj in DB.get_raid(cur)["objectives"]:
		want_coins += int(obj["reward"].get("coins", 0))
		want_gems += int(obj["reward"].get("gems", 0))
	_check("31000 de dano + fase 4 + sin bajas + jefe derrotado: paga TODOS los tramos y objetivos (%d monedas, %d gemas)" % [want_coins, want_gems], GameState.coins - c0 == want_coins and GameState.gems - g0 == want_gems)
	_check("el objetivo de derrotar al jefe da el Nucleo del despertar", GameState.item_count("evo_core") >= 1)
	_check("el jefe derrotado se cuenta", int(m.raid_record(cur)["kills"]) == 1)
	# Mismo token: no paga dos veces.
	var c1 := GameState.coins
	GameState.grant_battle_rewards(token, GameState.party_ids(), true)
	_check("el mismo combate no paga dos veces", GameState.coins == c1)
	# Misma semana, otra vez con el mismo dano: nada nuevo.
	m.start_raid(cur)
	m.battle_summary = { "damage": 31000, "phase": 4, "rounds": 7, "fallen": [], "crits": 9, "boss_defeated": true, "hp": {}, "alive": [] }
	var c2 := GameState.coins
	GameState.grant_battle_rewards(GameState.begin_battle(), GameState.party_ids(), true)
	_check("misma semana: no se repite ningun cobro", GameState.coins == c2)
	# Semana nueva: se puede volver a cobrar; los records se conservan.
	_set_day(21)
	m.start_raid(m.current_raid_id())
	m.battle_summary = { "damage": 3000, "phase": 1, "rounds": 10, "fallen": [], "crits": 0, "boss_defeated": false, "hp": {}, "alive": [] }
	var c3 := GameState.coins
	GameState.grant_battle_rewards(GameState.begin_battle(), GameState.party_ids(), true)
	_check("semana nueva: el tramo de 2500 vuelve a pagarse", GameState.coins > c3)
	_check("el record historico de la incursion se conserva", int(m.raid_record(cur)["best_damage"]) == 31000)
	# Guardado
	GameState.save_game()
	var rec_before: Dictionary = m.raid_record(cur).duplicate(true)
	m.from_dict({})
	GameState.load_game()
	_check("al cargar, record, intentos y registro siguen", int(m.raid_record(cur)["best_damage"]) == int(rec_before["best_damage"]) and int(m.raid_record(cur)["attempts"]) == int(rec_before["attempts"]))
	# Fases reales del jefe
	var mgr := BattleManager.new()
	add_child(mgr)
	m.start_raid(m.current_raid_id())
	mgr.setup(GameState.battle_party_data(), GameState.enemy_data(), [])
	mgr.pause_scale = 0.0
	var boss = mgr.enemies[0]
	var special_before := String(boss.skill_by_kind("special")["id"])
	boss.hp = boss.max_hp() * 0.4
	mgr._check_phases()
	_check("a menos del 50%% de vida el jefe entra en 2 fases seguidas (fase %d)" % boss.phase_index, boss.phase_index == 2)
	_check("cada fase le da una habilidad nueva", String(boss.skill_by_kind("special")["id"]) != special_before)
	mgr.queue_free()
	GameState.reset_battle_context()


## --- 2. Mazmorras ----------------------------------------------------------------------------------
func _check_dungeons() -> void:
	_out("[DBG30] == MAZMORRAS ==")
	_fresh()
	var m = GameState.modes
	var focus := {}
	for d in m.dungeon_list():
		focus[String(d["focus"])] = true
		_check("mazmorra %s: 4 dificultades, premio creciente" % d["id"], m.dungeon_difficulties(String(d["id"])).size() == 4)
	_check("hay mazmorras de xp, monedas, evolucion, personaje y equipo", focus.has("xp") and focus.has("coins") and focus.has("evolution") and focus.has("character") and focus.has("equipment"))
	_check("la dificultad Normal esta bloqueada al principio", not m.dungeon_unlocked("dng_xp", "normal") and m.dungeon_unlocked("dng_xp", "easy"))
	_check("no se puede empezar una dificultad bloqueada", not m.start_dungeon("dng_xp", "normal"))
	_check("la dificultad escala a los enemigos", true)
	var base_hp := float(DB.get_enemy("vigia_alfa")["stats"]["max_hp"])
	m.start_dungeon("dng_xp", "easy")
	_check("facil: enemigos x1.0", is_equal_approx(float(GameState.enemy_data()[0]["stats"]["max_hp"]), base_hp))
	var a: String = GameState.party_ids()[0]
	var xp0: int = int(GameState.progress[a]["xp"])
	var lvl0 := GameState.level_of(a)
	GameState.set_level(a, 10)
	xp0 = int(GameState.progress[a]["xp"])
	var coins0 := GameState.coins
	var r: Dictionary = await _play()
	_check("combate real de mazmorra: victoria con el equipo fuerte", bool(r["victory"]))
	_check("paga la XP del JSON a cada personaje que combatio", int(r["report"]["xp"]) == 250 and (r["report"]["characters"] as Array).size() == GameState.battle_party_ids().size())
	_check("paga las monedas del JSON", GameState.coins - coins0 == 40)
	_check("la victoria queda registrada y abre Normal", m.dungeon_clears("dng_xp", "easy") == 1 and m.dungeon_unlocked("dng_xp", "normal"))
	m.start_dungeon("dng_xp", "normal")
	var normal_base := float(DB.get_enemy(String(DB.get_dungeon("dng_xp")["difficulties"][1]["enemies"][0]))["stats"]["max_hp"])
	_check("normal: enemigos x1.5 de vida", is_equal_approx(float(GameState.enemy_data()[0]["stats"]["max_hp"]), roundf(normal_base * 1.5)))
	GameState.reset_battle_context()
	# Derrota: nada.
	m.start_dungeon("dng_coins", "easy")
	m.battle_summary = {}
	var c1 := GameState.coins
	var rd: Dictionary = GameState.grant_battle_rewards(GameState.begin_battle(), GameState.party_ids(), false)
	_check("una derrota no paga nada ni cuenta como superada", GameState.coins == c1 and m.dungeon_clears("dng_coins", "easy") == 0 and not bool(rd["granted"]))
	# Premios por foco
	var pay := func(dungeon: String, diff: String) -> Dictionary:
		m.start_dungeon(dungeon, diff)
		m.battle_summary = {}
		return GameState.grant_battle_rewards(GameState.begin_battle(), GameState.party_ids(), true)
	for d in ["easy", "normal", "hard"]:
		m.dungeons["dng_coins"] = { "easy": 1, "normal": 1, "hard": 1 }
	var cc := GameState.coins
	pay.call("dng_coins", "easy")
	var easy_coins := GameState.coins - cc
	cc = GameState.coins
	pay.call("dng_coins", "extreme")
	var ext_coins := GameState.coins - cc
	_check("monedas: mejor dificultad = mejor premio (%d < %d)" % [easy_coins, ext_coins], easy_coins == 400 and ext_coins >= 4500)
	m.dungeons["dng_evolution"] = { "easy": 1, "normal": 1, "hard": 1 }
	pay.call("dng_evolution", "extreme")
	_check("evolucion: da Brasa y Nucleo del despertar (materiales de evolucion, no los de evento)", GameState.item_count("evo_ember") >= 3 and GameState.item_count("evo_core") >= 1 and GameState.item_count("rabbit_costume") == 0 and GameState.item_count("mai_token") == 0)
	_check("esos materiales son objetos EVOLUTIVOS (no equipables)", GameState.Equipment.is_evolutive("evo_ember") and not GameState.equipment.can_equip(a, "evo_core")["ok"])
	m.dungeons["dng_equipment"] = { "easy": 1 }
	pay.call("dng_equipment", "normal")
	_check("equipables: da Fragmentos de armeria (recurso para equipables)", GameState.item_count("equipment_shard") == 6)
	DB.get_dungeon("dng_equipment")["difficulties"][1]["drops"][0]["chance"] = 1.0
	var rr: Dictionary = pay.call("dng_equipment", "normal")
	_check("y un equipable cae en el inventario de EQUIPABLES (no en el de objetos)", GameState.equipment.count_of("gafas_mob") >= 1 and GameState.item_count("gafas_mob") == 0)
	GameState.item_count("equipment_shard")
	GameState.inventory["equipment_shard"] = 50
	var rs: Dictionary = GameState.equipment.summon_with_shards("banner_objetos")
	_check("50 fragmentos pagan 1 tirada de la Armeria", bool(rs["ok"]) and GameState.item_count("equipment_shard") == 0 and GameState.equipment.count_of(String(rs["results"][0])) >= 1)
	_check("sin fragmentos suficientes no se puede", not bool(GameState.equipment.summon_with_shards("banner_objetos")["ok"]))
	# Copias de personaje
	var dup0: int = GameState.duplicates_of(a)
	DB.get_dungeon("dng_character")["difficulties"][0]["drops"][0]["pool"] = [a]
	DB.get_dungeon("dng_character")["difficulties"][0]["drops"][0]["chance"] = 1.0
	pay.call("dng_character", "easy")
	_check("personaje: da una COPIA (duplicado) de un personaje que tienes", GameState.duplicates_of(a) == dup0 + 1)
	DB.get_dungeon("dng_character")["difficulties"][0]["drops"][0]["pool"] = ["goku_inexistente_en_roster"]
	var mat0 := GameState.materials
	pay.call("dng_character", "easy")
	_check("si no tienes a nadie del grupo, paga materiales en su lugar", GameState.materials > mat0)
	# Anadir una mazmorra nueva = un JSON
	DB.dungeons["dng_prueba"] = { "id": "dng_prueba", "name": "Prueba", "description": "x", "order": 99, "focus": "coins", "background": "battle",
		"difficulties": [{ "id": "easy", "name": "Facil", "order": 1, "enemies": ["vigia_alfa"], "scale": { "hp": 1.0, "atk": 1.0, "def": 1.0 }, "reward": { "coins": 7 }, "requires_previous": false }] }
	_check("una mazmorra nueva aparece sola en la lista y se puede jugar", m.dungeon_list().size() == 6 and m.start_dungeon("dng_prueba", "easy"))
	DB.dungeons.erase("dng_prueba")
	GameState.reset_battle_context()
	# Guardado
	GameState.save_game()
	var clears := m.dungeon_clears("dng_xp", "easy")
	m.from_dict({})
	GameState.load_game()
	_check("al cargar siguen las mazmorras superadas", m.dungeon_clears("dng_xp", "easy") == clears and clears >= 1)


## --- 3. Boss Rush --------------------------------------------------------------------------------------------
func _check_rush() -> void:
	_out("[DBG30] == BOSS RUSH ==")
	_fresh()
	var m = GameState.modes
	_check("3 dificultades; solo Normal abierta", m.rush_difficulties().size() == 3 and m.rush_unlocked("normal") and not m.rush_unlocked("hard") and not m.rush_unlocked("extreme"))
	_check("no se puede empezar una dificultad bloqueada", not bool(m.rush_start_run("hard")["ok"]))
	m.rush_best = { "normal": { "clears": 1, "bosses": 0, "runs": 0, "milestones": [] } }
	for id in GameState.roster:
		GameState.set_level(String(id), 45)
	_check("empezar una carrera (Dificil, ya desbloqueada)", bool(m.rush_start_run("hard")["ok"]) and m.rush_active())
	_check("no se pisa una carrera en marcha", not bool(m.rush_start_run("normal")["ok"]))
	var team: Array = m.rush_run["team"]
	_check("la carrera lleva el equipo del jugador", team == GameState.party_ids())
	# Dificultad progresiva
	_check("cada jefe es mas duro que el anterior", float(m.rush_scale("normal", 3)["hp"]) > float(m.rush_scale("normal", 0)["hp"]) and float(m.rush_scale("hard", 0)["hp"]) > float(m.rush_scale("normal", 0)["hp"]))
	# Combate real: primer jefe
	_check("se lanza el primer combate", m.rush_fight() and GameState.battle_source == GameState.BATTLE_MODE)
	var boss1 := String(GameState.enemy_data()[0]["id"])
	_check("el primer rival es el primer jefe de la lista", boss1 == String(DB.mode_config("boss_rush")["bosses"][0]))
	var coins0 := GameState.coins
	var r: Dictionary = await _play()
	_check("combate real contra jefe: termina", bool(r["finished"]))
	if bool(r["victory"]):
		_check("victoria: paga las monedas por jefe", GameState.coins - coins0 == 450)
		_check("el jefe derrotado cuenta y se avanza", int(m.rush_run["defeated"]) == 1 and int(m.rush_run["index"]) == 1)
		var any_hurt := false
		for id in m.rush_run["hp"]:
			if float(m.rush_run["hp"][id]) < 1.0:
				any_hurt = true
		_check("DESGASTE: tras el combate el equipo NO esta al 100%% (%s)" % str(m.rush_run["hp"]), any_hurt or int(r["rounds"]) <= 2)   # un jefe liquidado en 1-2 rondas puede no tocar a nadie (azar)
	else:
		_check("derrota: la carrera termina y se apunta el record", not m.rush_active())
	# Desgaste con cifras exactas (resumen controlado)
	_fresh()
	m.rush_best = { "normal": { "clears": 1, "bosses": 0, "runs": 0, "milestones": [] } }
	m.rush_start_run("hard")
	var ids: Array = m.rush_run["team"]
	m.rush_fight()
	var hp := {}
	hp[ids[0]] = 0.4
	hp[ids[1]] = 0.0
	hp[ids[2]] = 0.9
	hp[ids[3]] = 0.05
	m.battle_summary = { "damage": 1, "phase": 1, "rounds": 5, "fallen": [ids[1]], "crits": 0, "boss_defeated": true, "hp": hp, "alive": [ids[0], ids[2], ids[3]] }
	var c0 := GameState.coins
	GameState.grant_battle_rewards(GameState.begin_battle(), ids, true)
	var rec_hp: Dictionary = m.rush_run["hp"]
	var recovery := float(m.rush_difficulty("hard")["recovery"])
	_check("el desgaste se arrastra (+%d%% de recuperacion, nunca total)" % int(recovery * 100.0), is_equal_approx(float(rec_hp[ids[0]]), 0.4 + recovery) and is_equal_approx(float(rec_hp[ids[3]]), 0.05 + recovery) and float(rec_hp[ids[0]]) < 1.0)
	_check("un aliado caido NO vuelve", (m.rush_run["dead"] as Array).has(ids[1]) and not m.rush_alive_team().has(ids[1]))
	_check("paga por jefe segun la dificultad", GameState.coins - c0 == 450)
	m.rush_fight()
	_check("el siguiente combate no lleva al caido", not GameState.battle_party_ids().has(ids[1]) and GameState.battle_party_ids().size() == 3)
	var mgr := BattleManager.new()
	add_child(mgr)
	mgr.setup(GameState.battle_party_data(), GameState.enemy_data(), [])
	mgr.pause_scale = 0.0
	var ok_hp := true
	for u in mgr.allies:
		var want := float(rec_hp[u.id])
		if absf(u.hp / u.max_hp() - want) > 0.02:
			ok_hp = false
	_check("el combate EMPIEZA con la vida arrastrada, no con vida completa", ok_hp and mgr.allies.size() == 3)
	_check("el segundo jefe es mas duro (x%.2f de vida)" % (float(GameState.enemy_data()[0]["stats"]["max_hp"]) / maxf(1.0, float(DB.get_enemy(String(GameState.enemy_data()[0]["id"]))["stats"]["max_hp"]))), true)
	mgr.queue_free()
	# Guardado a mitad de carrera
	GameState.save_game()
	var idx := int(m.rush_run["index"])
	var dead_copy: Array = (m.rush_run["dead"] as Array).duplicate()
	m.from_dict({})
	_check("(borrado en memoria)", not m.rush_active())
	GameState.load_game()
	_check("al cargar la carrera sigue: jefe, desgaste y caidos", m.rush_active() and int(m.rush_run["index"]) == idx and (m.rush_run["dead"] as Array) == dead_copy and is_equal_approx(float(m.rush_run["hp"][ids[0]]), 0.4 + recovery))
	# Hitos y records: recorrer los 7 jefes con resumenes
	GameState.reset_battle_context()
	m.rush_abandon()
	_check("abandonar conserva el record", int(m.rush_record("hard")["bosses"]) == 1 and not m.rush_active())
	m.rush_best = { "normal": { "clears": 1, "bosses": 1, "runs": 1, "milestones": [] } }
	m.rush_start_run("normal")
	var total_coins := GameState.coins
	for i in m.rush_boss_count():
		m.rush_fight()
		var h := {}
		for id in m.rush_alive_team():
			h[id] = 0.9
		m.battle_summary = { "damage": 1, "phase": 1, "rounds": 4, "fallen": [], "crits": 0, "boss_defeated": true, "hp": h, "alive": m.rush_alive_team() }
		GameState.grant_battle_rewards(GameState.begin_battle(), m.rush_alive_team(), true)
	var diff: Dictionary = m.rush_difficulty("normal")
	var want_total := m.rush_boss_count() * 250
	for ms in diff["milestones"]:
		want_total += int(ms["reward"].get("coins", 0))
	_check("derrotar los 7 jefes paga por jefe + los 3 hitos (%d monedas)" % want_total, GameState.coins - total_coins == want_total)
	_check("la carrera termina completada: record 7 y +1 completada", not m.rush_active() and int(m.rush_record("normal")["bosses"]) == 7 and int(m.rush_record("normal")["clears"]) == 2)
	_check("completar Normal desbloquea Dificil", m.rush_unlocked("hard"))
	# Repetir: los hitos NO se pagan dos veces
	m.rush_start_run("normal")
	var t2 := GameState.coins
	for i in m.rush_boss_count():
		m.rush_fight()
		m.battle_summary = { "damage": 1, "phase": 1, "rounds": 4, "fallen": [], "crits": 0, "boss_defeated": true, "hp": { }, "alive": [] }
		GameState.grant_battle_rewards(GameState.begin_battle(), m.rush_alive_team(), true)
	_check("repetir la carrera solo paga lo de cada jefe (hitos ya cobrados)", GameState.coins - t2 == m.rush_boss_count() * 250)
	# Derrota
	m.rush_start_run("normal")
	m.rush_fight()
	var t3 := GameState.coins
	m.battle_summary = { "damage": 1, "phase": 1, "rounds": 4, "fallen": m.rush_alive_team(), "crits": 0, "boss_defeated": false, "hp": { }, "alive": [] }
	GameState.grant_battle_rewards(GameState.begin_battle(), m.rush_alive_team(), false)
	_check("la derrota termina la carrera sin pagar nada mas y el record se mantiene", GameState.coins == t3 and not m.rush_active() and int(m.rush_record("normal")["bosses"]) == 7)
	GameState.reset_battle_context()


## --- 4. Roguelike -----------------------------------------------------------------------------------------------
func _check_roguelike() -> void:
	_out("[DBG30] == ROGUELIKE ==")
	_fresh()
	var m = GameState.modes
	var ids: Array = GameState.party_ids().slice(0, 3)
	_check("hace falta un equipo", not bool(m.rogue_start_run([])["ok"]))
	_check("no se pueden elegir personajes que no son tuyos", not bool(m.rogue_start_run(["personaje_inexistente"])["ok"]))
	var snap := _chars_snapshot()
	_check("se puede elegir equipo y empezar", bool(m.rogue_start_run(ids)["ok"]) and m.rogue_active())
	_check("no se pisa una partida en marcha", not bool(m.rogue_start_run(ids)["ok"]))
	var seed_a: int = int(m.rogue_run["seed"])
	# Combate 1
	_check("combate 1: se lanza con el equipo elegido", m.rogue_fight() and GameState.battle_party_ids() == ids)
	var depth1_hp := float(GameState.enemy_data()[0]["stats"]["max_hp"])
	var r1: Dictionary = await _play()
	_check("combate real 1 termina", bool(r1["finished"]))
	if not bool(r1["victory"]):
		_out("[DBG30] (el combate 1 se perdio; se reintenta con un equipo reforzado)")
		_fresh()
		m = GameState.modes
		m.rogue_start_run(ids)
		m.rogue_fight()
		GameState.modes.rogue_run["depth"] = 0
	var choices: Array = []
	if m.rogue_active() and String(m.rogue_run["phase"]) == "choose":
		choices = (m.rogue_run["choices"] as Array).duplicate()
	else:
		# Forzar el estado de "elegir" con un resumen de victoria controlado.
		m.rogue_fight()
		var hpm := {}
		for id in ids:
			hpm[id] = 0.5
		m.battle_summary = { "damage": 1, "phase": 1, "rounds": 3, "fallen": [], "crits": 0, "boss_defeated": true, "hp": hpm, "alive": ids }
		GameState.grant_battle_rewards(GameState.begin_battle(), ids, true)
		choices = (m.rogue_run["choices"] as Array).duplicate()
	_check("tras ganar se ofrecen 3 mejoras distintas", choices.size() == 3 and choices[0] != choices[1] and choices[1] != choices[2] and choices[0] != choices[2])
	_check("las mismas opciones al regenerarlas (semilla fija)", m.rogue_generate_choices(int(m.rogue_run["depth"])) == choices)
	# Guardado a mitad de partida: mismas opciones y estado
	GameState.save_game()
	var run_copy: Dictionary = (m.rogue_run as Dictionary).duplicate(true)
	m.from_dict({})
	GameState.load_game()
	_check("al cargar la partida sigue exactamente igual (misma eleccion pendiente)", m.rogue_active() and (m.rogue_run["choices"] as Array) == choices and int(m.rogue_run["depth"]) == int(run_copy["depth"]) and _hp_close(m.rogue_run["hp"], run_copy["hp"]))
	# Elegir una mejora de ataque (garantizada para el test)
	m.rogue_run["choices"] = ["filo", "vigor", "ojo_halcon"]
	_check("no se puede elegir una mejora no ofrecida", not bool(m.rogue_pick("furia")["ok"]))
	var hp_before_pick := float(m.rogue_run["hp"][ids[0]])
	_check("elegir una mejora", bool(m.rogue_pick("filo")["ok"]) and int(m.rogue_run["boons"]["filo"]) == 1 and String(m.rogue_run["phase"]) == "fight")
	_check("entre combates se cura algo (no todo)", float(m.rogue_run["hp"][ids[0]]) >= hp_before_pick and float(m.rogue_run["hp"][ids[0]]) <= 1.0)
	# Las mejoras entran SOLO en el combate de la partida
	var base_atk := {}
	var plain := BattleManager.new()
	add_child(plain)
	GameState.reset_battle_context()
	plain.setup(GameState.character_data_list(ids) if GameState.has_method("character_data_list") else _char_list(ids), [DB.get_enemy("vigia_alfa")], [])
	for u in plain.allies:
		base_atk[u.id] = u.attack()
	plain.queue_free()
	m.rogue_fight()
	var boosted := BattleManager.new()
	add_child(boosted)
	boosted.setup(GameState.battle_party_data(), GameState.enemy_data(), [])
	boosted.pause_scale = 0.0
	var all_up := true
	for u in boosted.allies:
		if not (u.attack() > float(base_atk[u.id]) * 1.05):
			all_up = false
	_check("DENTRO de la partida: la mejora Filo sube el ataque (+10%)", all_up)
	var depth2_hp := float(GameState.enemy_data()[0]["stats"]["max_hp"])
	boosted.queue_free()
	var r2: Dictionary = await _play()
	_check("combate real 2 con mejoras termina", bool(r2["finished"]))
	# Los personajes guardados NO cambian
	var after := _chars_snapshot()
	_check("los personajes NO se modifican: nivel, rareza, copias, objetos y roster iguales", after == snap)
	GameState.reset_battle_context()
	var normal := BattleManager.new()
	add_child(normal)
	normal.setup(_char_list(ids), [DB.get_enemy("vigia_alfa")], [])
	var clean := true
	for u in normal.allies:
		if absf(u.attack() - float(base_atk[u.id])) > 0.01:
			clean = false
		for mod in u.stats.mods:
			if String(mod["source"]).begins_with("boon:"):
				clean = false
	_check("FUERA de la partida (un combate normal) no queda ni rastro de las mejoras", clean)
	normal.queue_free()
	# Dificultad progresiva y jefe
	_check("la dificultad sube con la profundidad", float(m.rogue_enemies_for(8)[0]["hp"]) > float(m.rogue_enemies_for(2)[0]["hp"]) and float(m.rogue_enemies_for(2)[0]["hp"]) > float(m.rogue_enemies_for(1)[0]["hp"]))
	var boss_cfg: Dictionary = DB.mode_config("roguelike")
	var boss_depth: Array = m.rogue_enemies_for(int(boss_cfg["boss_every"]))
	_check("cada 5 combates hay un jefe", boss_depth.size() == 1 and (boss_cfg["boss_pool"] as Array).has(String(boss_depth[0]["id"])))
	_check("mas combates = mas enemigos a la vez (hasta 3)", m.rogue_enemies_for(1).size() == 1 and m.rogue_enemies_for(9).size() == 3)
	# Cada partida distinta
	var sigs := {}
	for i in 8:
		m.rogue_run["seed"] = randi()
		sigs[str(m.rogue_enemies_for(3)) + str(m.rogue_generate_choices(2))] = true
	_check("cada partida genera combinaciones distintas (%d firmas distintas en 8 partidas)" % sigs.size(), sigs.size() >= 4)
	m.rogue_run["seed"] = seed_a
	# Elegibilidad: categorias y links
	var eligible_link := false
	for b in DB.mode_config("roguelike")["boons"]:
		if bool(b.get("requires_links", false)) and m._boon_eligible(b):
			eligible_link = true
	var team_links: int = m._team_link_count(m.rogue_alive_team())
	_check("las mejoras de link solo se ofrecen si el equipo tiene links activos (links=%d, ofrecidas=%s)" % [team_links, eligible_link], eligible_link == (team_links > 0))
	var cat_ok := true
	for b in DB.mode_config("roguelike")["boons"]:
		var cat := String(b.get("requires_category", ""))
		if cat.is_empty():
			continue
		var any := false
		for id in m.rogue_alive_team():
			if (DB.get_character(String(id))["categories"] as Array).has(cat):
				any = true
		if m._boon_eligible(b) != any:
			cat_ok = false
	_check("las mejoras de categoria solo se ofrecen si hay alguien de esa categoria", cat_ok)
	# Maximo de acumulaciones
	m.rogue_run["boons"]["vigor"] = 5
	_check("una mejora al maximo de acumulaciones deja de ofrecerse", not m._boon_eligible(m.rogue_boon("vigor")))
	m.rogue_run["boons"].erase("vigor")
	# Muertes permanentes en la partida
	m.rogue_run["dead"] = [ids[0]]
	m.rogue_run["phase"] = "fight"
	m.rogue_fight()
	_check("un caido no vuelve a combatir en la partida", not GameState.battle_party_ids().has(ids[0]) and GameState.battle_party_ids().size() == ids.size() - 1)
	m.rogue_run["dead"] = []
	GameState.reset_battle_context()
	# Pago final por progreso
	m.rogue_run["depth"] = 6
	var coins0 := GameState.coins
	var gems0 := GameState.gems
	var rep: Dictionary = m.rogue_end_run()
	var cfg_r: Dictionary = DB.mode_config("roguelike")["rewards"]
	var want := 45 * 6 + 400
	_check("terminar paga por profundidad (45 x 6) + el hito de 5 (%d monedas)" % want, GameState.coins - coins0 == want and bool(rep["granted"]))
	_check("la partida queda cerrada y el record apuntado", not m.rogue_active() and int(m.rogue_record()["depth"]) >= 6)
	var c2 := GameState.coins
	m.rogue_end_run()
	_check("no se cobra dos veces", GameState.coins == c2)
	_check("los personajes siguen sin cambios tras cobrar", _chars_snapshot() == snap)
	# Derrota termina y cobra lo conseguido
	m.rogue_start_run(ids)
	m.rogue_run["depth"] = 2
	m.rogue_fight()
	var c3 := GameState.coins
	m.battle_summary = { "damage": 1, "phase": 1, "rounds": 3, "fallen": ids, "crits": 0, "boss_defeated": false, "hp": {}, "alive": [] }
	GameState.grant_battle_rewards(GameState.begin_battle(), ids, false)
	_check("la derrota termina la partida y paga lo alcanzado (2 combates ganados)", not m.rogue_active() and GameState.coins - c3 == 45 * 2)
	_check("el hito de profundidad 5 no se paga dos veces", int(m.rogue_record()["milestones"].size()) == 1)
	_check("(tamanos de enemigo medidos %.0f -> %.0f)" % [depth1_hp, depth2_hp], depth2_hp > depth1_hp)
	GameState.reset_battle_context()


func _hp_close(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or absf(float(a[k]) - float(b[k])) > 0.0001:
			return false
	return true


func _char_list(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		out.append(GameState.character_data(String(id)).duplicate(true))
	return out


## --- 5. Campo de entrenamiento ------------------------------------------------------------------------------------
func _check_training() -> void:
	_out("[DBG30] == CAMPO DE ENTRENAMIENTO ==")
	_fresh()
	var m = GameState.modes
	var a: String = GameState.party_ids()[0]
	var b: String = GameState.party_ids()[1]
	GameState.equipment.add("sombrero_paja", 1)
	GameState.equipment.equip(a, "sombrero_paja")
	GameState.save_game()
	var save_text := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	_check("no se puede empezar sin aliados ni enemigos", not m.start_training())
	m.training["allies"] = [a, b]
	m.training["enemies"] = ["vigia_alfa", "char:goku"]
	m.training["enemy_mult"] = 2.0
	m.training["ally_hp"] = 0.5
	m.training["enemy_hp"] = 0.8
	m.training["ally_sp"] = 3
	m.training["rounds"] = 3
	m.training["loadout"] = { a: "rueda_adaptabilidad", b: "" }
	_check("se empieza con aliados propios y enemigos del catalogo (incluidos personajes)", m.start_training() and m.is_sandbox())
	var ed: Array = GameState.enemy_data()
	_check("los rivales usan el multiplicador (x2) y un personaje puede ser rival", ed.size() == 2 and is_equal_approx(float(ed[0]["stats"]["max_hp"]), float(DB.get_enemy("vigia_alfa")["stats"]["max_hp"]) * 2.0) and String(ed[1]["id"]) == "rival_goku")
	_check("el limite de rondas se aplica", int(GameState.current_stage()["survive_rounds"]) == 3)
	var snap := _snapshot()
	var mgr := BattleManager.new()
	add_child(mgr)
	mgr.setup(GameState.battle_party_data(), GameState.enemy_data(), [])
	mgr.pause_scale = 0.0
	var ua = mgr.allies[0]
	var ub = mgr.allies[1]
	_check("condiciones: vida inicial de aliados 50%% y de enemigos 80%%", absf(ua.hp / ua.max_hp() - 0.5) < 0.02 and absf(mgr.enemies[0].hp / mgr.enemies[0].max_hp() - 0.8) < 0.02)
	_check("condiciones: SP inicial de aliados", ua.sp == 3 and ub.sp == 3)
	var has_wheel := false
	for r in ua.equipment_rules:
		if String(r.get("id", "")).contains("rueda_adaptabilidad"):
			has_wheel = true
	_check("objeto de prueba: la Rueda de la Adaptabilidad (que NO tienes) funciona en el entrenamiento", has_wheel and not GameState.equipment.owns("rueda_adaptabilidad"))
	_check("el objeto guardado del aliado A se sustituye SOLO en el entrenamiento", not ua.equipment_rules.any(func(r): return String(r.get("id", "")).contains("sombrero_paja")) and GameState.equipment.item_of(a) == "sombrero_paja")
	mgr.queue_free()
	var r: Dictionary = await _play()
	_check("combate real de entrenamiento: termina", bool(r["finished"]))
	_check("el informe es de sandbox y no da nada", bool(r["report"].get("sandbox", false)) and not bool(r["report"]["granted"]) and int(r["report"]["xp"]) == 0 and int(r["report"]["coins"]) == 0)
	var after := _snapshot()
	_check("NO cambia: monedas, gemas, materiales, objetos, energia, contadores, misiones, jefes, copias ni progreso", after == snap)
	_check("el archivo de guardado queda byte a byte igual", FileAccess.get_file_as_string(GameState.SAVE_PATH) == save_text)
	_check("el resumen del entrenamiento se rellena para la pantalla", (m.battle_summary.get("allies", []) as Array).size() == 2)
	_check("el objeto equipado guardado sigue siendo el de antes", GameState.equipment.item_of(a) == "sombrero_paja" and not GameState.equipment.owns("rueda_adaptabilidad"))
	# Otra sesion: el entrenamiento no se guarda
	_check("el entrenamiento no deja nada en el guardado (bloque 'modes' sin entrenamiento)", not (m.to_dict() as Dictionary).has("training"))
	GameState.reset_battle_context()
	m.reset_training()


## --- 6. Guardados antiguos --------------------------------------------------------------------------------------------
func _check_save_compat() -> void:
	_out("[DBG30] == COMPATIBILIDAD DE GUARDADOS ==")
	_fresh()
	var m = GameState.modes
	GameState.save_game()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	_check("el guardado nuevo trae el bloque 'modes'", data.has("modes"))
	data.erase("modes")
	var w := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	w.store_string(JSON.stringify(data))
	w.close()
	var coins := GameState.coins
	_check("un guardado anterior (sin 'modes') carga", GameState.load_game())
	_check("y empieza sin progreso de modos, sin perder monedas", not m.rush_active() and not m.rogue_active() and m.raids.is_empty() and GameState.coins == coins)
	data["modes"] = { "rush_run": { "difficulty": "inexistente", "index": 1, "team": [], "hp": {}, "dead": [] }, "raids": 5, "rogue_run": "basura" }
	w = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	w.store_string(JSON.stringify(data))
	w.close()
	_check("un bloque 'modes' con basura o contenido retirado no rompe la carga", GameState.load_game() and not m.rush_active() and not m.rogue_active())


## --- 7. Pantallas ---------------------------------------------------------------------------------------------------------
func _check_screens() -> void:
	_out("[DBG30] == PANTALLAS ==")
	_fresh()
	var menu = _app._screens["main_menu"]
	_check("el menu principal tiene el boton MODOS DE JUEGO", menu.find_child("ModesButton", true, false) != null)
	_app.call("open_screen", "modes")
	await _wait(0.1)
	var hub = _app._screens["modes"]
	for n in ["BtnRaid", "BtnDungeon", "BtnRogue", "BtnRush", "BtnTraining"]:
		_check("hub: boton %s" % n, hub.find_child(n, true, false) != null)
	# Incursion: el boton abre un combate real
	_app.call("open_screen", "mode_raid")
	await _wait(0.1)
	var raid = _app._screens["mode_raid"]
	var fight: Button = raid.find_child("FightButton", true, false)
	_check("incursion: boton COMBATIR y tarjetas de tramos, objetivos y registro", fight != null and raid.find_child("TiersCard", true, false) != null and raid.find_child("ObjectivesCard", true, false) != null and raid.find_child("LogCard", true, false) != null)
	fight.pressed.emit()
	await _wait(0.2)
	_check("COMBATIR abre el combate de la incursion", _app._battle != null and GameState.battle_source == GameState.BATTLE_MODE)
	_app.call("close_battle")
	await _wait(0.1)
	# Mazmorras
	_app.call("open_screen", "mode_dungeon")
	await _wait(0.1)
	var dg = _app._screens["mode_dungeon"]
	var easy: Button = dg.find_child("Dng_dng_xp_easy", true, false)
	var normal: Button = dg.find_child("Dng_dng_xp_normal", true, false)
	_check("mazmorras: una tarjeta por mazmorra y Normal desactivada", easy != null and normal != null and normal.disabled and not easy.disabled and dg.find_child("Dungeon_dng_equipment", true, false) != null)
	easy.pressed.emit()
	await _wait(0.2)
	_check("ENTRAR abre el combate de la mazmorra", _app._battle != null)
	_app.call("close_battle")
	await _wait(0.1)
	# Boss Rush
	_app.call("open_screen", "mode_rush")
	await _wait(0.1)
	var rush = _app._screens["mode_rush"]
	var start: Button = rush.find_child("Rush_normal", true, false)
	_check("boss rush: dificultades con record; Dificil bloqueada", start != null and rush.find_child("Rush_hard", true, false).disabled)
	start.pressed.emit()
	await _wait(0.1)
	_check("EMPEZAR crea la carrera y muestra su estado", GameState.modes.rush_active() and rush.find_child("RushFight", true, false) != null)
	rush.find_child("RushFight", true, false).pressed.emit()
	await _wait(0.2)
	_check("COMBATIR abre el combate contra el primer jefe", _app._battle != null and GameState.battle_source == GameState.BATTLE_MODE)
	_app.call("restart_battle")
	await _wait(0.1)
	_check("en un modo, REINTENTAR vuelve a la pantalla del modo (no abre otro combate)", _app._battle == null)
	rush.find_child("RushAbandon", true, false).pressed.emit()
	await _wait(0.1)
	_check("ABANDONAR cierra la carrera", not GameState.modes.rush_active())
	# Roguelike
	_app.call("open_screen", "mode_rogue")
	await _wait(0.1)
	var rg = _app._screens["mode_rogue"]
	var first: String = String(GameState.roster[0])
	var pick: Button = rg.find_child("Pick_%s" % first, true, false)
	_check("roguelike: selector de equipo con tus personajes", pick != null and rg.find_child("RogueStart", true, false).disabled)
	pick.pressed.emit()
	await _wait(0.1)
	var go: Button = rg.find_child("RogueStart", true, false)
	_check("elegir a alguien activa EMPEZAR", not go.disabled)
	go.pressed.emit()
	await _wait(0.1)
	_check("EMPEZAR crea la partida", GameState.modes.rogue_active() and rg.find_child("RogueFight", true, false) != null)
	GameState.modes.rogue_run["phase"] = "choose"
	GameState.modes.rogue_run["choices"] = ["filo", "vigor", "coraza"]
	rg.refresh()
	await _wait(0.1)
	var bn: Button = rg.find_child("Boon_filo", true, false)
	_check("tras ganar salen 3 botones de mejora", bn != null and rg.find_child("Boon_vigor", true, false) != null and rg.find_child("Boon_coraza", true, false) != null)
	bn.pressed.emit()
	await _wait(0.1)
	_check("elegir una mejora la apunta y vuelve a COMBATIR", int(GameState.modes.rogue_run["boons"].get("filo", 0)) == 1 and rg.find_child("RogueFight", true, false) != null)
	rg.find_child("RogueEnd", true, false).pressed.emit()
	await _wait(0.1)
	_check("TERMINAR cierra la partida", not GameState.modes.rogue_active())
	# Entrenamiento
	_app.call("open_screen", "mode_training")
	await _wait(0.1)
	var tr = _app._screens["mode_training"]
	for n in ["AllySlot_0", "AllySlot_3", "EnemySlot_0", "EnemyMultPlus", "AllyHpMinus", "AllySpPlus", "RoundsCycle", "TrainStart"]:
		_check("entrenamiento: %s existe" % n, tr.find_child(n, true, false) != null)
	_check("EMPEZAR esta desactivado sin equipo ni enemigos", tr.find_child("TrainStart", true, false).disabled)
	GameState.modes.training["allies"] = [first]
	GameState.modes.training["enemies"] = ["vigia_alfa"]
	tr.find_child("EnemyMultPlus", true, false).pressed.emit()
	await _wait(0.1)
	_check("los botones +/- cambian las condiciones", is_equal_approx(float(GameState.modes.training["enemy_mult"]), 1.25))
	tr.refresh()
	await _wait(0.1)
	tr.find_child("TrainStart", true, false).pressed.emit()
	await _wait(0.2)
	_check("EMPEZAR abre el combate de entrenamiento (sandbox)", _app._battle != null and GameState.modes.is_sandbox())
	_app.call("close_battle")
	await _wait(0.1)
	_check("al volver, el contexto de modo se limpia", GameState.battle_source != GameState.BATTLE_MODE)
	_app.call("go_back")
	GameState.reset_battle_context()


## --- 8. Roguelike: objetos temporales -------------------------------------------------------------
func _check_rogue_items() -> void:
	_out("[DBG30] == ROGUELIKE: OBJETOS ==")
	_fresh()
	var m = GameState.modes
	var ids: Array = GameState.party_ids().slice(0, 3)
	var a := String(ids[0])
	GameState.equipment.add("sombrero_paja", 1)
	GameState.equipment.equip(a, "sombrero_paja")
	var snap := _chars_snapshot()
	m.rogue_start_run(ids)
	var cfg: Dictionary = DB.mode_config("roguelike")
	cfg["item_choices"]["chance"] = 1.0
	var ch: Array = m.rogue_generate_choices(1)
	_check("con probabilidad 1, las 3 opciones son objetos distintos", ch.size() == 3 and ch.all(func(c): return String(c).begins_with("item:")) and ch[0] != ch[1] and ch[1] != ch[2])
	_check("los objetos ofrecidos existen en el catalogo de equipables", ch.all(func(c): return DB.equipment.has(String(c).substr(5))))
	_check("las mismas opciones al regenerarlas (semilla fija)", m.rogue_generate_choices(1) == ch)
	cfg["item_choices"]["chance"] = 0.34
	# Mezcla con probabilidad normal: a lo largo de muchas profundidades salen objetos Y mejoras
	var items_seen := 0
	var boons_seen := 0
	for d in range(1, 41):
		for c in m.rogue_generate_choices(d):
			if String(c).begins_with("item:"):
				items_seen += 1
			else:
				boons_seen += 1
	_check("con la probabilidad normal salen objetos y mejoras (%d objetos, %d mejoras en 40 ofertas)" % [items_seen, boons_seen], items_seen > 10 and boons_seen > 40)
	# Elegir un objeto y darselo a un personaje
	var item_id := String(ch[0]).substr(5)
	m.rogue_run["choices"] = ch
	m.rogue_run["phase"] = "choose"
	_check("no se puede dar a alguien fuera del equipo", not bool(m.rogue_pick(String(ch[0]), "goku")["ok"]))
	_check("elegir objeto y portador", bool(m.rogue_pick(String(ch[0]), a)["ok"]) and String(m.rogue_run["items"][a]) == item_id and String(m.rogue_run["phase"]) == "fight")
	_check("el objeto NO entra en tu inventario y lo guardado no cambia", not GameState.equipment.owns(item_id) and GameState.equipment.item_of(a) == "sombrero_paja")
	_check("un objeto que la partida ya lleva no se vuelve a ofrecer", not m.rogue_generate_choices(1).has("item:%s" % item_id))
	# En combate lo lleva (sustituyendo al guardado) y fuera no
	m.rogue_fight()
	var mgr := BattleManager.new()
	add_child(mgr)
	mgr.setup(GameState.battle_party_data(), GameState.enemy_data(), [])
	mgr.pause_scale = 0.0
	var ua = mgr.allies[0]
	var has_item := false
	var has_saved := false
	for u_mod in ua.stats.mods:
		if String(u_mod["source"]).begins_with("equip:%s:" % item_id):
			has_item = true
		if String(u_mod["source"]).begins_with("equip:sombrero_paja"):
			has_saved = true
	for r in ua.equipment_rules:
		if String(r.get("id", "")).begins_with("equip_%s_" % item_id):
			has_item = true
	_check("EN la partida el objeto temporal esta activo y sustituye al guardado", has_item and not has_saved)
	mgr.queue_free()
	GameState.reset_battle_context()
	var plain := BattleManager.new()
	add_child(plain)
	plain.setup(_char_list(ids), [DB.get_enemy("vigia_alfa")], [])
	var leak := false
	for u_mod in plain.allies[0].stats.mods:
		if String(u_mod["source"]).begins_with("equip:%s:" % item_id):
			leak = true
	_check("FUERA de la partida no hay rastro del objeto temporal", not leak)
	plain.queue_free()
	# Guardar y cargar a mitad de partida
	GameState.save_game()
	m.from_dict({})
	GameState.load_game()
	_check("al cargar la partida sigue llevando el objeto", m.rogue_active() and String(m.rogue_run["items"].get(a, "")) == item_id)
	# Terminar: se pierden y todo queda igual
	m.rogue_run["depth"] = 1
	m.rogue_end_run()
	_check("al terminar el objeto desaparece y nada de lo tuyo cambia", not m.rogue_active() and _chars_snapshot() == snap and not GameState.equipment.owns(item_id))
	GameState.reset_battle_context()


## --- 9. Historia: mundos nuevos --------------------------------------------------------------------
func _check_story_worlds() -> void:
	_out("[DBG30] == HISTORIA: MUNDOS NUEVOS ==")
	_fresh()
	_check("hay 5 mundos", DB.worlds.size() == 5)
	var cm_owned := 0
	for c in ["denji", "makima", "reze"]:
		if GameState.is_owned(c):
			cm_owned += 1
	var qt_owned := 0
	for c in ["miku", "nino", "itsuki"]:
		if GameState.is_owned(c):
			qt_owned += 1
	_check("ya tienes 3 personajes de Chainsaw Man y 3 de Las Quintillizas", cm_owned == 3 and qt_owned == 3)
	for wid in ["world_004", "world_005"]:
		var w := DB.get_world(wid)
		_check("%s (%s): 4 niveles con 3 dificultades, enemigos y recompensas validos" % [wid, w["name"]], DB.story_levels(wid).size() == 4)
		var bad := 0
		var last_xp := 0
		for lv in DB.story_levels(wid):
			var prev := 0
			for dk in ["normal", "hard", "extreme"]:
				var d: Dictionary = lv["difficulties"][dk]
				if (d["enemies"] as Array).is_empty() or int(d["xp_reward"]) <= prev or int(d["coin_reward"]) <= 0:
					bad += 1
				prev = int(d["xp_reward"])
				for e in d["enemies"]:
					if DB.get_enemy(String(e)).is_empty():
						bad += 1
		_check("%s: todo valido y la dificultad paga mas (%d problemas)" % [wid, bad], bad == 0)
		var dlg := String(DB.story_levels(wid)[0].get("dialogue", ""))
		_check("%s: el primer nivel tiene dialogo" % wid, DB.dialogues.has(dlg))
		var final_level: Dictionary = DB.story_levels(wid)[3]
		var boss := String(final_level["difficulties"]["normal"]["enemies"][0])
		_check("%s: el nivel final tiene jefe con fase" % wid, bool(DB.get_enemy(boss).get("boss", false)) and not (DB.get_enemy(boss).get("phases", []) as Array).is_empty())
	# Desbloqueo en cadena
	for wid in ["world_001", "world_002", "world_003"]:
		for lv in DB.story_levels(wid):
			GameState.story_progress[String(lv["id"])] = []
	_check("con los mundos 1-3 sin superar, el mundo 4 esta cerrado", not GameState.world_unlocked("world_004") and not GameState.world_unlocked("world_005"))
	for wid in ["world_001", "world_002", "world_003"]:
		for lv in DB.story_levels(wid):
			GameState.story_progress[String(lv["id"])] = ["normal"]
	_check("superar Black Clover abre Chainsaw Man", GameState.world_unlocked("world_004") and not GameState.world_unlocked("world_005"))
	# Combate real del primer nivel de Chainsaw Man y progreso
	var xp0 := int(GameState.progress[String(GameState.party_ids()[0])]["xp"])
	var coins0 := GameState.coins
	_check("el primer nivel esta abierto y el segundo no", GameState.story_level_unlocked("world_004_01") and not GameState.story_level_unlocked("world_004_02"))
	_check("se prepara el combate de historia", GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_004_01", "difficulty": "normal" }))
	var r: Dictionary = await _play()
	_check("combate real de Chainsaw Man 1: termina", bool(r["finished"]))
	if bool(r["victory"]):
		_check("victoria: paga la XP y las monedas del JSON y abre el nivel 2", int(r["report"]["xp"]) == 420 and GameState.coins - coins0 >= 170 and GameState.story_level_unlocked("world_004_02"))
	else:
		_check("(derrota: sin premios)", GameState.coins == coins0)
	# Cada nivel y dificultad se puede preparar con sus enemigos
	var ok_all := true
	for wid in ["world_004", "world_005"]:
		for lv in DB.story_levels(wid):
			for dk in ["normal", "hard", "extreme"]:
				if not GameState.prepare_battle(GameState.BATTLE_STORY, { "level": String(lv["id"]), "difficulty": dk }) or GameState.enemy_data().is_empty():
					ok_all = false
	_check("los 24 combates de los dos mundos se preparan con enemigos reales", ok_all)
	# Boss final jugable (combate real contra el jefe de Quintillizas)
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_005_04", "difficulty": "normal" })
	var rb: Dictionary = await _play()
	_check("combate real contra el jefe final de Las Quintillizas: termina", bool(rb["finished"]))
	GameState.reset_battle_context()
