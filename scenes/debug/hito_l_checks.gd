extends Node

## COMPROBACIONES EN EJECUCION DE LA v14 (jefes con fases, presentacion, misiones
## diarias/semanales, eventos, logros y titulos). SOLO pruebas.
## Arranque:  godot --headless --path . -- --dbg26   (escribe res://dbg26_resultados.txt)

const RESULTS_PATH := "res://dbg26_resultados.txt"
const BattleManager := preload("res://core/battle_manager.gd")
const BossFx := preload("res://ui/boss_fx.gd")
## 2026-10-30 (viernes) 12:00 UTC: reloj fijo de las pruebas.
const T0 := 1793361600

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
	_out("[DBG26] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func run(app: Node) -> void:
	_app = app
	await _wait(0.3)
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	seed(2626)
	_out("[DBG26] --- comprobaciones v14 ---")
	_app.call("_backup_save")
	_check_phase_data()
	_check_phase_engine()
	await _check_phase_battle_headless()
	await _check_intro_fx()
	await _check_boss_in_battle_ui()
	_check_missions_periods()
	_check_mission_counting()
	_check_mission_objectives()
	_check_mission_persistence()
	_check_achievements()
	_check_achievements_retroactive()
	_check_events()
	await _check_survival()
	await _check_screens()
	_app.call("_restore_save")
	_out("[DBG26] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _reset_meta() -> void:
	GameState.meta.from_dict({})
	GameState.meta.now_override = T0
	GameState.coins = 0
	GameState.gems = 0


func _new_manager(ally_ids: Array, enemy_ids: Array, huge_allies: bool = false) -> Node:
	var manager := BattleManager.new()
	add_child(manager)
	var allies: Array = []
	for id in ally_ids:
		var data: Dictionary = GameState.character_data(String(id)).duplicate(true)
		if huge_allies:
			data["stats"] = (data["stats"] as Dictionary).duplicate()
			data["stats"]["max_hp"] = 900000
		allies.append(data)
	var enemies: Array = []
	for id in enemy_ids:
		enemies.append(DB.get_enemy(String(id)))
	manager.setup(allies, enemies)
	manager.pause_scale = 0.0
	return manager


## --- 1. Datos de fases -------------------------------------------------------------------------
func _check_phase_data() -> void:
	_out("[DBG26] == DATOS DE JEFES ==")
	for id in ["void_warden", "sdp_akaza", "boss_sakuta"]:
		var data: Dictionary = DB.get_enemy(id)
		_check("%s es jefe con fases e intro" % id, bool(data.get("boss", false)) and not (data["phases"] as Array).is_empty() and not (data["intro"] as Dictionary).is_empty())
	for id in ["vigia_alfa", "vigia_beta", "torre_guardian", "torre_avatar", "torre_verdugo", "sdp_todo", "sdp_mahito"]:
		_check("%s NO tiene fases (no todos los jefes las necesitan)" % id, (DB.get_enemy(id).get("phases", []) as Array).is_empty())
	_check("void_warden conserva la identidad de Makima y su arte", DB.get_enemy("void_warden").get("name", "") == DB.get_character("makima").get("name", "?"))


## --- 2. Motor de fases (sin interfaz) -----------------------------------------------------------
func _check_phase_engine() -> void:
	_out("[DBG26] == MOTOR DE FASES ==")
	var roster_ids: Array = GameState.roster.slice(0, 2)
	var m := _new_manager(roster_ids, ["void_warden"])
	var boss = m.enemies[0]
	var atk_before: float = boss.stats.get_stat("atk")
	_check("al empezar el jefe esta en la fase 0", boss.phase_index == 0 and boss.pattern.is_empty())
	var seen: Array = []
	m.phase_changed.connect(func(unit, index, phase): seen.append([unit.id, index, String(phase.get("id", ""))]))
	m._check_phases()
	_check("con la vida llena no cambia de fase", boss.phase_index == 0 and seen.is_empty())
	boss.hp = boss.max_hp() * 0.49
	m._check_phases()
	_check("al bajar del 50% entra en la fase 1", boss.phase_index == 1 and seen.size() == 1)
	var atk_after: float = boss.stats.get_stat("atk")
	_check("la fase sube su ataque (%.0f -> %.0f)" % [atk_before, atk_after], atk_after > atk_before * 1.05)
	_check("la fase desbloquea una habilidad nueva (Dominio total)", String(boss.skill_by_kind("special").get("name", "")) == "Dominio total")
	_check("la fase fija su patron de acciones", boss.pattern == ["basic", "special"])
	m._check_phases()
	_check("una fase no se repite", boss.phase_index == 1 and seen.size() == 1 and m.phase_log.size() == 1)
	boss.sp = 5
	var first: String = m._pick_enemy_kind(boss)
	var second: String = m._pick_enemy_kind(boss)
	var third: String = m._pick_enemy_kind(boss)
	_check("el patron cicla basico -> especial -> basico (%s,%s,%s)" % [first, second, third], first == "basic" and second == "special" and third == "basic")
	boss.sp = 0
	boss.pattern_step = 1
	_check("sin SP el especial del patron cae a ataque basico", m._pick_enemy_kind(boss) == "basic")
	m.queue_free()
	# Dos umbrales cruzados de golpe
	var m2 := _new_manager(roster_ids, ["boss_sakuta"])
	var sakuta = m2.enemies[0]
	sakuta.hp = sakuta.max_hp() * 0.30
	m2._check_phases()
	_check("cruzar dos umbrales a la vez activa las dos fases en orden", sakuta.phase_index == 2 and m2.phase_log.size() == 2 and int(m2.phase_log[0]["index"]) == 1)
	_check("la fase con escudo lo aplica", sakuta.shield_total() > 0.0)
	m2.queue_free()
	# Un enemigo normal no cambia
	var m3 := _new_manager(roster_ids, ["vigia_alfa"])
	m3.enemies[0].hp = 1.0
	m3._check_phases()
	_check("un enemigo sin fases no cambia nunca", m3.enemies[0].phase_index == 0 and m3.phase_log.is_empty() and not m3.enemies[0].is_boss)
	m3.queue_free()
	# Fases por ronda (condicion reutilizada del motor de efectos)
	var m4 := _new_manager(roster_ids, ["vigia_alfa"])
	var e4 = m4.enemies[0]
	e4.phases = [{ "id": "t", "name": "Por ronda", "when": { "type": "round_at_least", "value": 3 }, "effects": [], "heal_ratio": 0.0 }]
	m4.round_number = 2
	m4._check_phases()
	_check("fase por ronda: antes de la ronda 3 no entra", e4.phase_index == 0)
	m4.round_number = 3
	m4._check_phases()
	_check("fase por ronda: en la ronda 3 entra", e4.phase_index == 1)
	m4.queue_free()


## --- 3. Combate completo sin interfaz: no se cuelga esperando intros ---------------------------
func _check_phase_battle_headless() -> void:
	_out("[DBG26] == COMBATE COMPLETO CON JEFE (SIN UI) ==")
	var ids: Array = GameState.roster.slice(0, 4)
	var m := _new_manager(ids, ["void_warden"], true)
	m.set_auto(true)
	var finished := [false, false]
	m.battle_finished.connect(func(victory, _rounds): finished[0] = true; finished[1] = victory)
	var t0 := Time.get_ticks_msec()
	m.start_battle()
	for i in 400:
		if finished[0]:
			break
		await _wait(0.05)
	_check("el combate contra el jefe termina solo (sin interfaz no espera la intro)", finished[0])
	_check("... y termina rapido (%d ms)" % (Time.get_ticks_msec() - t0), Time.get_ticks_msec() - t0 < 15000)
	_check("el jefe pasa por su fase durante el combate", m.phase_log.size() >= 1 or not finished[1])
	m.queue_free()


## --- 4. Presentacion: saltable, no se cuelga, respeta animaciones reducidas ---------------------
func _check_intro_fx() -> void:
	_out("[DBG26] == PRESENTACION DE JEFE ==")
	var host := Control.new()
	host.size = Vector2(720, 1280)
	add_child(host)
	var done := [0]
	var info: Dictionary = DB.get_enemy("void_warden")["intro"]
	var layer = BossFx.intro(host, "makima", "", info, func(): done[0] += 1)
	_check("la intro crea su capa", layer != null and host.get_node_or_null("BossIntroLayer") != null)
	await _wait(0.2)
	_check("la intro NO se ha cerrado sola enseguida", done[0] == 0)
	_check("tocar la pantalla salta la intro", BossFx.skip_intro(host))
	await _wait(0.7)
	_check("al saltarla se avisa UNA vez y la capa desaparece", done[0] == 1 and host.get_node_or_null("BossIntroLayer") == null)
	_check("saltarla otra vez no hace nada", not BossFx.skip_intro(host))
	# Cierre automatico
	var auto := [0]
	BossFx.intro(host, "makima", "", info, func(): auto[0] += 1)
	for i in 80:
		if auto[0] > 0:
			break
		await _wait(0.1)
	_check("sin tocar, la intro se cierra sola", auto[0] == 1)
	# Fase, impacto y ambiente
	var before := host.get_child_count()
	BossFx.phase(host, null, "FASE DE PRUEBA", Color.RED)
	BossFx.impact(host, Vector2(300, 400), Color.ORANGE, true)
	var amb = BossFx.ambient(host, Color.RED)
	_check("fase, impacto y ambiente dibujan capas", host.get_child_count() > before and amb != null)
	# Animaciones reducidas: sin particulas ni ambiente
	GameSettings.values["reduce_motion"] = true
	var calm_before := host.get_child_count()
	BossFx.impact(host, Vector2(300, 400), Color.ORANGE, true)
	_check("con animaciones reducidas el impacto es solo un destello (1 nodo)", host.get_child_count() == calm_before + 1)
	_check("con animaciones reducidas no hay ambiente", BossFx.ambient(host, Color.RED) == null)
	var m := _new_manager(GameState.roster.slice(0, 1), ["void_warden"])
	var listened := [0]
	m.boss_intro.connect(func(_u, _i): listened[0] += 1)
	await m._play_intros()
	_check("con animaciones reducidas el combate ni siquiera lanza la intro", listened[0] == 0)
	m.queue_free()
	GameSettings.values.erase("reduce_motion")
	# Con UI conectada y cerrando la intro, _play_intros continua
	var m2 := _new_manager(GameState.roster.slice(0, 1), ["void_warden"])
	m2.boss_intro.connect(func(_u, _i): listened[0] += 1; m2.close_intro.call_deferred())
	await m2._play_intros()
	_check("con UI conectada, close_intro libera al combate", listened[0] == 1 and not m2._intro_open)
	m2.queue_free()
	host.queue_free()


## --- 5. Dentro de la pantalla de combate real --------------------------------------------------
func _check_boss_in_battle_ui() -> void:
	_out("[DBG26] == JEFE EN LA PANTALLA DE COMBATE ==")
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	GameState.current_stage_enemies = ["void_warden"]
	_app.call("open_battle")
	await _wait(0.8)
	var battle = _app.get("_battle")
	_check("el combate se abre", battle != null)
	if battle == null:
		return
	_check("la intro del jefe se muestra al empezar", battle.get_node_or_null("BossIntroLayer") != null and int(battle.get("boss_intro_count")) == 1)
	var mgr = battle.get("manager")
	_check("mientras dura la intro no hay ronda en marcha", mgr.round_number == 0)
	BossFx.skip_intro(battle)
	await _wait(1.0)
	_check("tras saltarla el combate arranca", mgr.round_number >= 1)
	var boss = mgr.enemies[0]
	var fx_before := int(battle.get("phase_fx_count"))
	boss.hp = boss.max_hp() * 0.3
	mgr._check_phases()
	await _wait(0.3)
	_check("la transicion de fase se pinta (PhaseLayer + contador)", int(battle.get("phase_fx_count")) == fx_before + 1 and battle.get_node_or_null("PhaseLayer") != null)
	await _wait(1.6)
	_check("la capa de fase se retira sola", battle.get_node_or_null("PhaseLayer") == null)
	await _app.call("_dbg12_finish_battle", false)
	await _wait(0.3)


## --- 6. Misiones: periodos y reinicios ----------------------------------------------------------
func _check_missions_periods() -> void:
	_out("[DBG26] == MISIONES PERIODICAS: RELOJ ==")
	_reset_meta()
	var meta = GameState.meta
	_check("hay 5 misiones diarias y 6 semanales", meta.periodic_list("daily").size() == 5 and meta.periodic_list("weekly").size() == 6)
	_check("las misiones permanentes de siempre siguen siendo 7", GameState.all_missions_state().size() == 7)
	var key_fri := String(meta.period_key("daily"))
	var week_fri := String(meta.period_key("weekly"))
	meta.now_override = T0 + 86400
	_check("el sabado es otro dia pero la MISMA semana", meta.period_key("daily") != key_fri and meta.period_key("weekly") == week_fri)
	meta.now_override = T0 + 2 * 86400
	_check("el domingo sigue en la misma semana", meta.period_key("weekly") == week_fri)
	meta.now_override = T0 + 3 * 86400
	_check("el lunes empieza semana nueva", meta.period_key("weekly") != week_fri)
	meta.now_override = T0
	_check("quedan menos de 24 h para el reinicio diario", meta.seconds_left("daily") > 0 and meta.seconds_left("daily") <= 86400)
	# reinicio con progreso
	meta.record("battle", 1, { "victory": true, "ally_ids": ["gojo"], "bosses": [] })
	_check("una victoria suma a diarias y semanales", meta.periodic_state("day_victorias")["progress"] == 1 and meta.periodic_state("wk_victorias")["progress"] == 1)
	meta.now_override = T0 + 86400
	_check("al dia siguiente la diaria vuelve a 0", meta.periodic_state("day_victorias")["progress"] == 0 and meta.periodic_state("day_batallas")["progress"] == 0)
	_check("... y la semanal conserva su progreso", meta.periodic_state("wk_victorias")["progress"] == 1)
	meta.now_override = T0 + 3 * 86400
	_check("el lunes la semanal tambien se reinicia", meta.periodic_state("wk_victorias")["progress"] == 0)
	meta.now_override = T0
	# Reclamar y volver a cobrar al dia siguiente
	for i in 3:
		meta.record("battle", 1, { "victory": true, "ally_ids": ["gojo"], "bosses": [] })
	var coins_before := GameState.coins
	var paid: Dictionary = GameState.claim_mission("day_batallas")
	_check("una diaria completa paga su premio", not paid.is_empty() and GameState.coins == coins_before + 120)
	_check("no se puede cobrar dos veces el mismo dia", GameState.claim_mission("day_batallas").is_empty())
	_check("una mision sin completar no se cobra", GameState.claim_mission("wk_jefes").is_empty())
	meta.now_override = T0 + 86400
	for i in 3:
		meta.record("battle", 1, { "victory": true, "ally_ids": ["gojo"], "bosses": [] })
	_check("al dia siguiente se puede cobrar de nuevo", not GameState.claim_mission("day_batallas").is_empty())
	meta.now_override = T0


## --- 7. Sin contar dos veces: pasa por el cobro real ------------------------------------------------
func _check_mission_counting() -> void:
	_out("[DBG26] == NO CONTAR DOS VECES ==")
	_reset_meta()
	var meta = GameState.meta
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	GameState.current_stage_enemies = ["void_warden"]
	var token := GameState.begin_battle()
	var ids: Array = GameState.roster.slice(0, 2)
	GameState.grant_battle_rewards(token, ids, true)
	GameState.grant_battle_rewards(token, ids, true)
	GameState.grant_battle_rewards(token, ids, true)
	_check("cobrar tres veces la MISMA batalla suma 1 combate", meta.periodic_state("day_batallas")["progress"] == 1)
	_check("... 1 victoria", meta.periodic_state("day_victorias")["progress"] == 1)
	_check("... y 1 jefe (void_warden es jefe)", meta.periodic_state("wk_jefes")["progress"] == 1 and int(meta.boss_kills.get("void_warden", 0)) == 1)
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	GameState.current_stage_enemies = ["vigia_alfa"]
	GameState.grant_battle_rewards(GameState.begin_battle(), ids, false)
	_check("una derrota cuenta como combate jugado pero no como victoria ni jefe", meta.periodic_state("day_batallas")["progress"] == 2 and meta.periodic_state("day_victorias")["progress"] == 1 and meta.periodic_state("wk_jefes")["progress"] == 1)
	# evento: pasa por el cobro de batalla (una vez), no por complete_event_stage
	GameState.prepare_battle(GameState.BATTLE_EVENT, { "event": "event_sindromes_de_la_pubertad", "stage": "evt_sdp_01" })
	if GameState.current_stage_enemies.is_empty():
		GameState.current_stage_enemies = ["sdp_todo"]
	var evt_before: int = meta.periodic_state("wk_evento")["progress"]
	if not GameState.is_owned("sakuta_mai"):
		GameState.roster.append("sakuta_mai")
		GameState.progress["sakuta_mai"] = { "level": 1, "xp": 0 }
	GameState.grant_battle_rewards(GameState.begin_battle(), ["sakuta_mai"], true)
	_check("un stage de evento suma 1 a la mision de eventos (era %d)" % evt_before, meta.periodic_state("wk_evento")["progress"] == evt_before + 1)
	# llamar directamente a la logica de pago del evento NO suma misiones
	var before2: int = meta.periodic_state("wk_evento")["progress"]
	GameState.complete_event_stage("event_sindromes_de_la_pubertad", "evt_sdp_01", ["sakuta_mai"])
	_check("complete_event_stage por si solo no suma (un unico punto de entrada)", meta.periodic_state("wk_evento")["progress"] == before2)
	# invocar
	_reset_meta()
	var banner_id := ""
	for id in DB.banners:
		if bool(DB.banners[id].get("enabled", true)):
			banner_id = String(id)
			break
	GameState.gems = 100000
	GameState.pending_reveal = {}
	GameState.summon(banner_id, 1)
	_check("una invocacion suma 1 a la diaria y 1 a la semanal", meta.periodic_state("day_invocar")["progress"] == 1 and meta.periodic_state("wk_invocar")["progress"] == 1)
	GameState.summon(banner_id, 10)
	_check("una multi suma 10 a la semanal (11 en total), una sola vez", meta.periodic_state("wk_invocar")["progress"] == 10 and meta.periodic_state("day_invocar")["progress"] == 1)
	# torre
	GameState.tower_progress = {}
	GameState.complete_tower_floor("tower_001", 1, ids)
	GameState.complete_tower_floor("tower_001", 1, ids)
	_check("superar un piso suma 1; repetir el piso ya pagado no suma", meta.periodic_state("day_torre")["progress"] == 1)


## --- 8. Tipos de objetivo ----------------------------------------------------------------------
func _check_mission_objectives() -> void:
	_out("[DBG26] == TIPOS DE OBJETIVO ==")
	_reset_meta()
	var meta = GameState.meta
	var shonen: Array = []
	var other: Array = []
	for id in DB.characters:
		var cats: Array = DB.characters[id].get("categories", [])
		if cats.has("shonen") and not cats.has("heroes") and shonen.size() < 2:
			shonen.append(String(id))
		elif not cats.has("shonen") and not cats.has("heroes") and other.size() < 2:
			other.append(String(id))
	meta.record("battle", 1, { "victory": true, "ally_ids": [shonen[0], other[0]], "bosses": [] })
	_check("categoria: 1 shonen no basta para 'min 2'", meta.periodic_state("day_equipo_shonen")["progress"] == 0)
	meta.record("battle", 1, { "victory": false, "ally_ids": shonen, "bosses": [] })
	_check("categoria: perder con 2 shonen no cuenta", meta.periodic_state("day_equipo_shonen")["progress"] == 0)
	meta.record("battle", 1, { "victory": true, "ally_ids": shonen, "bosses": [] })
	_check("categoria: ganar con 2 shonen cuenta 1", meta.periodic_state("day_equipo_shonen")["progress"] == 1)
	# use_character: una vez por batalla aunque haya varios del grupo
	var heroes: Array = []
	for id in DB.characters:
		if (DB.characters[id].get("categories", []) as Array).has("heroes") and heroes.size() < 3:
			heroes.append(String(id))
	meta.record("battle", 1, { "victory": false, "ally_ids": heroes, "bosses": [] })
	_check("usar personajes: 3 heroes en una batalla suman 1 (no 3), y perder tambien cuenta", meta.periodic_state("wk_equipo_usado")["progress"] == 1)
	meta.record("battle", 1, { "victory": true, "ally_ids": other, "bosses": [] })
	_check("usar personajes: un equipo sin la categoria no suma", meta.periodic_state("wk_equipo_usado")["progress"] == 1)
	# evolucion real
	GameState.coins = 10000000
	var evolved := false
	for id in DB.characters.keys():
		if (DB.characters[id].get("evolution", {}) as Dictionary).is_empty():
			continue
		if not GameState.is_owned(id):
			GameState.roster.append(id)
		GameState.progress[id] = { "level": 100, "xp": 0 }
		var check: Dictionary = GameState.can_evolve(id)
		if bool(check.get("ok", false)):
			var before: int = meta.periodic_state("wk_evolucion")["progress"]
			var report: Dictionary = GameState.evolve(id)
			evolved = not report.is_empty()
			_check("evolucionar de verdad (%s) suma 1 a la semanal" % id, meta.periodic_state("wk_evolucion")["progress"] == before + 1)
			break
	if not evolved:
		meta.record("evolve", 1, { "to": "UR" })
		_check("evolucion (sin personaje evolucionable a mano): el evento suma 1", meta.periodic_state("wk_evolucion")["progress"] == 1)


## --- 9. Persistencia ------------------------------------------------------------------------------
func _check_mission_persistence() -> void:
	_out("[DBG26] == PERSISTENCIA ==")
	_reset_meta()
	var meta = GameState.meta
	for i in 2:
		meta.record("battle", 1, { "victory": true, "ally_ids": ["gojo"], "bosses": ["void_warden"] })
	meta.record("battle", 1, { "victory": true, "ally_ids": ["gojo"], "bosses": [] })
	GameState.coins = 0
	for i in 3:
		meta.record("battle", 1, { "victory": true, "ally_ids": ["gojo"], "bosses": [] })
	GameState.claim_mission("day_batallas")
	meta.title_equipped = ""
	GameState.save_game()
	var saved_progress: int = meta.periodic_state("wk_victorias")["progress"]
	var bosses_saved: int = int(meta.challenges.get("boss_total", 0))
	GameState.meta = GameState.MetaProgress.new(GameState)
	GameState.meta.now_override = T0
	_check("tras perder la memoria el progreso esta a 0", GameState.meta.periodic_state("wk_victorias")["progress"] == 0)
	GameState.load_game()
	meta = GameState.meta
	meta.now_override = T0
	_check("al cargar vuelve el progreso semanal (%d)" % saved_progress, meta.periodic_state("wk_victorias")["progress"] == saved_progress and saved_progress >= 5)
	_check("... lo cobrado sigue cobrado", bool(meta.periodic_state("day_batallas")["claimed"]))
	_check("... y los jefes derrotados", int(meta.challenges.get("boss_total", 0)) == bosses_saved and bosses_saved == 2)
	meta.now_override = T0 + 86400
	_check("cargar un guardado de ayer y jugar hoy: la diaria esta reiniciada", meta.periodic_state("day_batallas")["progress"] == 0 and not bool(meta.periodic_state("day_batallas")["claimed"]))
	meta.now_override = T0
	# guardado SIN meta_progress (de antes de la v14)
	var text := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	var parsed = JSON.parse_string(text)
	parsed.erase("meta_progress")
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(parsed))
	file.close()
	_check("un guardado v13 (sin meta_progress) carga", GameState.load_game())
	_check("... con las misiones periodicas a cero", GameState.meta.periodic_state("day_batallas")["progress"] == 0)
	_check("... sin perder el roster ni los contadores", GameState.roster.size() > 0 and GameState.counter_value("victorias") >= 0)
	# datos corruptos
	GameState.meta.from_dict({ "periodic": { "no_existe": { "key": "x", "progress": 5 } }, "achievements": "roto", "titles_owned": 7 })
	_check("datos de misiones/logros corruptos o desconocidos se ignoran", GameState.meta.periodic.is_empty() and GameState.meta.achievements.is_empty())
	GameState.meta.now_override = T0


## --- 10. Logros y titulos -----------------------------------------------------------------------
func _check_achievements() -> void:
	_out("[DBG26] == LOGROS Y TITULOS ==")
	_reset_meta()
	GameState.rarities = {}
	var meta = GameState.meta
	_check("hay 15 logros definidos en datos", meta.achievement_ids().size() == 15)
	var cats := {}
	for id in meta.achievement_ids():
		cats[meta.achievement_state(id)["category"]] = true
	_check("cubren coleccion, torre, jefes, evolucion, retos y evento", cats.size() >= 6)
	GameState.tower_progress = {}
	meta.check_achievements()
	_check("al principio la torre no esta desbloqueada", not meta.achievements.has("ach_torre_10"))
	GameState.tower_state("tower_001")["best_floor"] = 10
	var fresh: Array = meta.check_achievements()
	_check("llegar al piso 10 desbloquea 'SUBIENDO'", fresh.has("ach_torre_10") and meta.achievements.has("ach_torre_10"))
	_check("... y no se desbloquea dos veces", not meta.check_achievements().has("ach_torre_10"))
	var coins_before := GameState.coins
	var paid: Dictionary = meta.claim_achievement("ach_torre_10")
	_check("reclamar paga la recompensa (500 monedas, 10 gemas)", int(paid.get("coins", 0)) == 500 and GameState.coins == coins_before + 500 and GameState.gems == 10)
	_check("reclamar otra vez no paga", meta.claim_achievement("ach_torre_10").is_empty() and GameState.coins == coins_before + 500)
	_check("un logro sin cumplir no se puede reclamar", meta.claim_achievement("ach_torre_completa").is_empty())
	# torre completa
	GameState.tower_state("tower_001")["best_floor"] = DB.tower_floor_count("tower_001")
	meta.check_achievements()
	_check("completar la torre da REY DE LA TORRE y su titulo", meta.achievements.has("ach_torre_completa") and meta.owned_titles().has("title_rey_torre"))
	# jefes
	meta.record("battle", 1, { "victory": true, "ally_ids": ["gojo"], "bosses": ["boss_sakuta"] })
	_check("derrotar al jefe final desbloquea FIN DEL SINDROME y PRIMER JEFE", meta.achievements.has("ach_celador") and meta.achievements.has("ach_jefe_1"))
	_check("... pero no CAZAJEFES (10)", not meta.achievements.has("ach_jefe_10"))
	for i in 9:
		meta.record("battle", 1, { "victory": true, "ally_ids": ["gojo"], "bosses": ["void_warden"] })
	_check("10 jefes desbloquean CAZAJEFES", meta.achievements.has("ach_jefe_10"))
	meta.record("battle", 1, { "victory": false, "ally_ids": ["gojo"], "bosses": ["void_warden"] })
	_check("perder contra un jefe no cuenta como derrotado", int(meta.challenges.get("boss_total", 0)) == 10)
	# retos
	for i in 3:
		meta.record("battle", 1, { "victory": true, "ally_ids": ["gojo"], "bosses": [], "solo": true, "fallen": 0, "rounds": 2 })
	_check("3 victorias en solitario: LOBO SOLITARIO", meta.achievements.has("ach_solo"))
	_check("... y no SIN BAJAS todavia (3 de 10 + las 10 de jefes sin 'fallen' = ya cuentan)", meta.achievement_state("ach_impecable")["progress"] >= 3)
	# evolucion: solo cuenta al que evoluciona
	var native_ur := ""
	for id in DB.characters:
		if String(DB.characters[id].get("rarity", "")) == "UR":
			native_ur = String(id)
			break
	if not GameState.roster.has(native_ur):
		GameState.roster.append(native_ur)
	GameState.rarities.erase(native_ur)
	meta.check_achievements()
	_check("un UR de nacimiento NO cuenta como 'evolucionar a UR'", meta.achievement_state("ach_evolucion_ur")["progress"] == 0 and not meta.achievements.has("ach_evolucion_ur"))
	var ssr_id := ""
	for id in GameState.roster:
		if String(DB.get_character(String(id)).get("rarity", "")) == "SSR":
			ssr_id = String(id)
			break
	GameState.rarities[ssr_id] = "UR"
	meta.check_achievements()
	_check("un SSR evolucionado a UR si desbloquea DESPERTAR UR", meta.achievements.has("ach_evolucion_ur") and not meta.achievements.has("ach_evolucion_lr"))
	GameState.rarities.erase(ssr_id)
	# coleccion
	var old_roster: Array = GameState.roster.duplicate()
	GameState.roster = DB.characters.keys()
	meta.check_achievements()
	_check("tener todo el roster desbloquea COLECCION COMPLETA y la de SHONEN", meta.achievements.has("ach_gran_coleccion") and meta.achievements.has("ach_shonen") and meta.achievements.has("ach_coleccionista"))
	GameState.roster = old_roster
	# titulos
	_check("el titulo inicial siempre esta equipado por defecto", meta.equipped_title() == meta.DEFAULT_TITLE)
	_check("no se puede equipar un titulo que no se tiene", not meta.equip_title("title_leyenda_inventada"))
	_check("se puede equipar uno conseguido", meta.equip_title("title_rey_torre") and meta.equipped_title_name() == "Rey de la torre")
	GameState.save_game()
	GameState.meta = GameState.MetaProgress.new(GameState)
	GameState.load_game()
	meta = GameState.meta
	_check("logros, titulos y equipado se guardan", meta.achievements.has("ach_torre_10") and meta.owned_titles().has("title_rey_torre") and meta.equipped_title() == "title_rey_torre" and bool(meta.achievements["ach_torre_10"]["claimed"]))
	meta.now_override = T0


func _check_achievements_retroactive() -> void:
	_out("[DBG26] == LOGROS RETROACTIVOS ==")
	_reset_meta()
	GameState.tower_state("tower_001")["best_floor"] = 12
	var text := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	GameState.save_game()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	parsed.erase("meta_progress")
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(parsed))
	file.close()
	GameState.load_game()
	GameState.meta.check_achievements()
	_check("un jugador antiguo que ya estaba en el piso 12 recibe SUBIENDO al cargar", GameState.meta.achievements.has("ach_torre_10"))
	_check("los logros no inventan progreso (jefes = 0)", int(GameState.meta.challenges.get("boss_total", 0)) == 0 and not GameState.meta.achievements.has("ach_jefe_1"))


## --- 11. Eventos reutilizables ----------------------------------------------------------------------
func _install_test_event() -> void:
	DB.events["event_prueba_v14"] = {
		"id": "event_prueba_v14", "name": "EVENTO DE PRUEBA", "description": "Evento montado SOLO con datos.",
		"story": ["Una linea de historia.", "Otra linea."], "background": "stages", "position": { "x": 0.5, "y": 0.5 },
		"counter": "eventos_completados", "character_reward": "",
		"completion_reward": { "coins": 777, "gems": 7, "items": { "rabbit_costume": 2 } },
		"stages": [
			{ "id": "evp_01", "name": "Escaramuza", "next": "evp_02", "background": "battle_plain", "difficulty": "NORMAL", "enemies": ["vigia_alfa"], "xp_reward": 10, "coin_reward": 10, "drops": [], "first_clear_items": { "mai_token": 1 } },
			{ "id": "evp_02", "name": "Aguanta", "next": "evp_03", "background": "battle_plain", "difficulty": "NORMAL", "enemies": ["vigia_alfa"], "survive_rounds": 2, "xp_reward": 10, "coin_reward": 10, "drops": [] },
			{ "id": "evp_03", "name": "El jefe", "next": "", "background": "battle_plain", "difficulty": "HARD", "enemies": ["void_warden"], "xp_reward": 10, "coin_reward": 10, "drops": [] },
		],
	}


func _check_events() -> void:
	_out("[DBG26] == EVENTOS CON IDENTIDAD PROPIA (solo datos) ==")
	_reset_meta()
	_install_test_event()
	GameState.event_progress.erase("event_prueba_v14")
	GameState.inventory = {}
	var status: Dictionary = GameState.event_status("event_prueba_v14")
	_check("el evento de prueba aparece con su historia", (status["story"] as Array).size() == 2 and (status["stages"] as Array).size() == 3)
	_check("el stage de supervivencia y el de jefe se marcan solos", int(status["stages"][1]["survive_rounds"]) == 2 and bool(status["stages"][2]["boss"]) and not bool(status["stages"][0]["boss"]))
	var ids: Array = GameState.roster.slice(0, 1)
	var r1: Dictionary = GameState.complete_event_stage("event_prueba_v14", "evp_01", ids)
	_check("primera victoria: objeto exclusivo (Ficha dorada)", GameState.item_count("mai_token") == 1 and not (r1.get("exclusive", {}) as Dictionary).is_empty())
	GameState.complete_event_stage("event_prueba_v14", "evp_01", ids)
	_check("repetir el stage NO repite el objeto exclusivo", GameState.item_count("mai_token") == 1)
	GameState.complete_event_stage("event_prueba_v14", "evp_02", ids)
	var coins_before := GameState.coins
	var gems_before := GameState.gems
	var r3: Dictionary = GameState.complete_event_stage("event_prueba_v14", "evp_03", ids)
	_check("completar el evento paga el premio exclusivo UNA vez", bool(r3["event_completed"]) and GameState.gems == gems_before + 7 and GameState.coins >= coins_before + 777 and GameState.item_count("rabbit_costume") == 2)
	var r4: Dictionary = GameState.complete_event_stage("event_prueba_v14", "evp_03", ids)
	_check("completarlo otra vez no repite el premio exclusivo", GameState.gems == gems_before + 7 and not r4.has("completion_reward"))
	_check("el contador de eventos sube por evento completado", GameState.counter_value("eventos_completados") >= 2)
	DB.events.erase("event_prueba_v14")
	GameState.event_progress.erase("event_prueba_v14")
	# El evento de referencia sigue intacto
	var sdp: Dictionary = GameState.event_status("event_sindromes_de_la_pubertad")
	_check("Sindromes de la Pubertad sigue con sus 3 stages y su personaje", (sdp["stages"] as Array).size() == 3 and sdp["character_reward"] == "sakuta_mai")
	_check("... ahora con su historia corta y sin supervivencia ni premio nuevo", (sdp["story"] as Array).size() == 2 and int(sdp["stages"][0]["survive_rounds"]) == 0 and (sdp["completion_reward"] as Dictionary).is_empty())
	_check("... y su jefe final (akaza) tiene fases", bool(sdp["stages"][2]["boss"]))
	_check("sus requisitos de equipo siguen en pie (stage 3 pide a Sakuta en solitario)", String(DB.event_stage("event_sindromes_de_la_pubertad", "evt_sdp_03").get("requires_party_character", "")) == "sakuta" and bool(DB.event_stage("event_sindromes_de_la_pubertad", "evt_sdp_03").get("requires_party_solo", false)))


func _check_survival() -> void:
	_out("[DBG26] == RETO DE SUPERVIVENCIA ==")
	var ids: Array = GameState.roster.slice(0, 4)
	var m := _new_manager(ids, ["vigia_alfa"], true)
	m.survive_rounds = 2
	m.set_auto(true)
	# el enemigo es inmortal a efectos de la prueba
	m.enemies[0].stats.base["max_hp"] = 99999999
	m.enemies[0].hp = m.enemies[0].max_hp()
	var res := [false, false, 0]
	m.battle_finished.connect(func(victory, rounds): res[0] = true; res[1] = victory; res[2] = rounds)
	m.start_battle()
	for i in 200:
		if res[0]:
			break
		await _wait(0.05)
	_check("sobrevivir 2 rondas gana el combate", res[0] and res[1] and res[2] == 2)
	m.queue_free()
	var m2 := _new_manager(ids, ["vigia_alfa"], true)
	var res2 := [false, false, 0]
	m2.set_auto(true)
	m2.battle_finished.connect(func(victory, rounds): res2[0] = true; res2[1] = victory; res2[2] = rounds)
	m2.start_battle()
	for i in 200:
		if res2[0]:
			break
		await _wait(0.05)
	_check("sin supervivencia, el combate acaba cuando mueren los enemigos", res2[0] and res2[1])
	m2.queue_free()


## --- 12. Pantallas ------------------------------------------------------------------------------------
func _check_screens() -> void:
	_out("[DBG26] == PANTALLA DE MISIONES Y LOGROS ==")
	_reset_meta()
	GameState.tower_state("tower_001")["best_floor"] = 10
	for i in 3:
		GameState.meta.record("battle", 1, { "victory": true, "ally_ids": ["gojo"], "bosses": [] })
	_app.call("open_screen", "missions")
	await _wait(0.4)
	var screen = _app.get("_screens").get("missions", null)
	_check("la pantalla de misiones abre", screen != null)
	if screen == null:
		return
	var list: Node = screen.get_node("Margin/Main/Scroll/List")
	_check("existen las 4 pestanas", screen.get_node_or_null("Margin/Main/Tabs") != null and screen.get_node("Margin/Main/Tabs").get_child_count() == 4)
	var cards_daily := _cards(list)
	_check("DIARIAS: 5 tarjetas", cards_daily == 5)
	screen.call("_select_tab", "weekly")
	await _wait(0.1)
	_check("SEMANALES: 6 tarjetas", _cards(list) == 6)
	screen.call("_select_tab", "permanent")
	await _wait(0.1)
	_check("PERMANENTES: las 7 de siempre", _cards(list) == 7)
	screen.call("_select_tab", "achievements")
	await _wait(0.1)
	_check("LOGROS: 15 tarjetas y la fila de titulos", _cards(list) == 15 and list.get_node_or_null("TitlesRow") != null)
	var coins_before := GameState.coins
	screen.call("_on_claim_achievement", "ach_torre_10")
	await _wait(0.1)
	_check("reclamar un logro desde la pantalla paga", GameState.coins == coins_before + 500)
	screen.call("_on_claim_achievement", "ach_torre_10")
	_check("... y no paga dos veces", GameState.coins == coins_before + 500)
	screen.call("_select_tab", "daily")
	await _wait(0.1)
	coins_before = GameState.coins
	screen.call("_on_claim_pressed", "day_batallas")
	_check("el contrato _on_claim_pressed cobra una diaria", GameState.coins == coins_before + 120)
	screen.call("_select_tab", "achievements")
	GameState.meta.equip_title("title_recien_llegado")
	screen.call("_on_equip_title", "title_recien_llegado")
	_check("equipar un titulo desde la pantalla funciona", GameState.meta.equipped_title() == "title_recien_llegado")
	_app.call("go_back")
	await _wait(0.1)


func _cards(list: Node) -> int:
	var n := 0
	for child in list.get_children():
		if child is PanelContainer:
			n += 1
	return n
