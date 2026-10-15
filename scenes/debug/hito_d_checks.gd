extends Node

## COMPROBACIONES EN EJECUCION DEL HITO D (torre y reglas de Mai). SOLO para pruebas.
## Arranque:  godot --headless --path . -- --dbg18
## Usa las funciones y pantallas REALES del juego. Escribe "[DBG18] texto -> OK/FALLO"
## en res://dbg18_resultados.txt. Guarda y restaura el guardado del jugador.

const RESULTS_PATH := "res://dbg18_resultados.txt"
const EVENTO := "event_sindromes_de_la_pubertad"
const TORRE := "tower_001"

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
	_out("[DBG18] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _frames(count: int = 2) -> void:
	for i in count:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _screen(key: String) -> Node:
	return (_app.get("_screens") as Dictionary).get(key, null)


func run(app: Node) -> void:
	_app = app
	await _frames()
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out("[DBG18] --- comprobaciones del Hito D ---")
	_app.call("_backup_save")
	GameState.tower_progress.clear()

	_check_mai_rules()
	await _check_story()
	await _check_event_flow()
	await _check_evolution()
	_check_art_by_id()
	await _check_combat_visuals()
	await _check_gacha()
	_check_missions()
	_check_gacha_rates()
	_check_audio_files()
	await _check_audio_flow()
	await _check_navigation()
	await _check_music_flow()
	_check_tower_data()
	_check_tower_team()
	await _check_tower_screen()
	await _check_tower_battle()
	await _check_tower_defeat()
	await _check_normal_team_untouched()

	_app.call("_restore_save")
	_out("[DBG18] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _fails > 0 else 0)


## --- Reglas de Mai: las fichas NO estan en la torre; si en el Stage 3 -----------
func _check_mai_rules() -> void:
	_out("[DBG18] == REGLAS DE MAI ==")
	var tower_has_token := false
	for raw in DB.tower_floors(TORRE):
		var fl: Dictionary = raw
		if String(fl.get("first_clear_item", "")) == "mai_token":
			tower_has_token = true
		for key in fl.keys():
			if str(fl[key]).contains("mai_token"):
				tower_has_token = true
	_check("ninguna recompensa de la torre da fichas de Mai", not tower_has_token)
	var stage3 := DB.event_stage(EVENTO, "evt_sdp_03")
	var drops_token := false
	for raw in stage3.get("drops", []):
		if String((raw as Dictionary).get("item", "")) == "mai_token":
			drops_token = true
	_check("el Stage 3 del evento suelta fichas doradas de Mai", drops_token)
	_check("Stage 3 es Sakuta UR SOLO 1 VS 1",
		String(stage3.get("requires_party_character", "")) == "sakuta"
		and bool(stage3.get("requires_party_solo", false))
		and int(stage3.get("requires_party_size", 0)) == 1
		and String(stage3.get("requires_party_rarity", "")) == "UR")
	var stage2_ok := false
	var stage2 := DB.event_stage(EVENTO, "evt_sdp_02")
	stage2_ok = String(stage2.get("requires_party_character", "")) == "sakuta_mai"
	_check("Stage 2 mantiene su requisito (Sakuta+Mai)", stage2_ok)
	var ur := {}
	var lr := {}
	for raw in DB.special_evolution_routes():
		var route: Dictionary = raw
		if String(route.get("to_rarity", "")) == "UR":
			ur = route
		elif String(route.get("to_rarity", "")) == "LR":
			lr = route
	_check("SSR->UR: nivel 100, 25 uniformes de conejita, 0 monedas",
		int(ur.get("level_required", 0)) == 100 and int(ur.get("coin_cost", -1)) == 0
		and str(ur.get("item_cost", [])).contains("rabbit_costume") and str(ur.get("item_cost", [])).contains("25"))
	_check("UR->LR: 3 fichas doradas de Mai, 0 monedas",
		int(lr.get("coin_cost", -1)) == 0 and str(lr.get("item_cost", [])).contains("mai_token") and str(lr.get("item_cost", [])).contains("3"))
	_check("UR->LR NO exige completar el evento 5 veces",
		not lr.has("requires_event_clears") and not lr.has("requires_event"))
	GameState.inventory.erase("mai_token")
	GameState.add_item("mai_token", 3)
	GameState.event_progress.erase("event_sindromes_de_la_pubertad")
	var rep: Dictionary = GameState.can_special_evolve("sakuta") if GameState.is_owned("sakuta") else {}
	_check("con 3 fichas y 0 vueltas la ruta LR no se bloquea por el evento",
		rep.is_empty() or bool(rep.get("event_ok", true)))
	GameState.inventory.erase("mai_token")
	_check("una victoria en Stage 3 entrega 1 ficha de Mai",
		_stage3_gives_token())


func _stage3_gives_token() -> bool:
	GameState.add_character("sakuta")
	var before := GameState.item_count("mai_token")
	var info: Dictionary = GameState.complete_event_stage(EVENTO, "evt_sdp_03", ["sakuta"])
	# Si el gate rechaza (p. ej. Sakuta no esta UR), se comprueba solo el drop declarado.
	if bool(info.get("ok", false)):
		return GameState.item_count("mai_token") == before + 1
	return false


## --- Datos de la torre -----------------------------------------------------------
func _check_tower_data() -> void:
	_out("[DBG18] == TORRE: DATOS ==")
	_check("la torre tiene 25 pisos", DB.tower_floor_count(TORRE) == 25)
	var boss_ok := true
	for n in [5, 10, 15, 20, 25]:
		boss_ok = boss_ok and DB.tower_floor_is_boss(TORRE, n)
	_check("hay jefes en los pisos 5, 10, 15, 20 y 25", boss_ok)
	var enemies_ok := true
	for raw in DB.tower_floors(TORRE):
		for id in (raw as Dictionary).get("enemies", []):
			if DB.get_enemy(String(id)).is_empty():
				enemies_ok = false
	_check("todos los enemigos de todos los pisos existen", enemies_ok)
	var xp_prev := 0
	var rising := true
	for n in [1, 5, 10, 15, 20, 25]:
		var xp := int(DB.tower_floor(TORRE, n).get("xp_reward", 0))
		rising = rising and xp >= xp_prev
		xp_prev = xp
	_check("la recompensa sube con el piso (dificultad progresiva)", rising)


## --- Equipo de torre ---------------------------------------------------------------
func _check_tower_team() -> void:
	_out("[DBG18] == TORRE: EQUIPO 3+2 ==")
	var ids: Array = GameState.roster.slice(0, 6)
	GameState.tower_team = ["", "", "", "", ""]
	for i in 5:
		GameState.assign_tower_slot(i, String(ids[i]))
	_check("se pueden poner 5 personajes (3 activos + 2 reserva)",
		GameState.tower_team_count() == 5 and GameState.tower_active_ids().size() == 3 and GameState.tower_reserve_ids().size() == 2)
	GameState.assign_tower_slot(4, String(ids[0]))
	_check("el mismo personaje no puede estar dos veces (se mueve)",
		String(GameState.tower_team[0]) == "" and String(GameState.tower_team[4]) == String(ids[0]))
	GameState.assign_tower_slot(4, String(ids[0]))
	_check("tocar al que ya esta lo quita", String(GameState.tower_team[4]) == "")
	GameState.assign_tower_slot(0, String(ids[0]))
	GameState.assign_tower_slot(4, String(ids[4]))
	var saved := GameState.tower_team.duplicate()
	GameState.save_game()
	GameState.tower_team = ["", "", "", "", ""]
	GameState.load_game()
	_check("el equipo de torre se guarda y se carga", GameState.tower_team == saved)
	GameState.tower_team = ["", "", "", "", ""]
	_check("sin activos el piso no se puede empezar", not GameState.tower_team_problem(TORRE, 1).is_empty())
	GameState.assign_tower_slot(3, String(ids[3]))
	_check("solo con reservas tampoco", not GameState.tower_team_problem(TORRE, 1).is_empty())
	GameState.tower_team = saved.duplicate()
	_check("con activos el piso 1 se puede empezar", GameState.tower_team_problem(TORRE, 1).is_empty())
	_check("el piso 2 esta bloqueado al empezar", not GameState.tower_team_problem(TORRE, 2).is_empty())


## --- Pantalla ---------------------------------------------------------------------
func _check_tower_screen() -> void:
	_out("[DBG18] == TORRE: PANTALLA ==")
	var menu := _screen("main_menu")
	var button: Button = menu.find_child("TowerButton", true, false)
	_check("el menu principal tiene boton TORRE", button != null)
	if button != null:
		button.pressed.emit()
	await _frames(3)
	_check("el boton TORRE abre la pantalla de torre", String(_app.call("current_screen")) == "tower")
	var tower: Node = _screen("tower")
	var list: VBoxContainer = tower.get("_floor_list")
	_check("la pantalla pinta los 25 pisos (%d)" % list.get_child_count(), list.get_child_count() == 25)
	var active_row: HBoxContainer = tower.get("_active_row")
	var reserve_row: HBoxContainer = tower.get("_reserve_row")
	_check("pinta 3 puestos activos y 2 de reserva", active_row.get_child_count() == 3 and reserve_row.get_child_count() == 2)
	tower.call("_open_picker", 1)
	await _frames()
	var grid: GridContainer = tower.get("_picker_grid")
	_check("el selector lista el roster (%d)" % grid.get_child_count(), grid.get_child_count() == GameState.roster.size())
	var chosen := String(GameState.roster[7])
	tower.call("_on_pick", chosen)
	await _frames()
	_check("elegir en el selector coloca al personaje en ese puesto", String(GameState.tower_team[1]) == chosen)
	var fight: Button = tower.get("_fight_button")
	_check("COMBATIR PISO 1 esta habilitado", not fight.disabled and fight.text == "COMBATIR PISO 1")


## --- Combate de torre ----------------------------------------------------------------
func _check_tower_battle() -> void:
	_out("[DBG18] == TORRE: COMBATE, RESERVAS Y RECOMPENSAS ==")
	var party_before: Array = GameState.party.duplicate()
	var tower: Node = _screen("tower")
	var coins_before := GameState.coins
	var fight: Button = tower.get("_fight_button")
	fight.pressed.emit()
	await _wait(0.9)
	var battle = _app.get("_battle")
	_check("COMBATIR abre el combate", battle != null)
	if battle == null:
		return
	var mgr = battle.get("manager")
	_check("combaten 3 activos", mgr.allies.size() == 3)
	_check("hay 2 reservas esperando", mgr.reserves.size() == 2)
	_check("el lider es el del puesto 1 de la torre", GameState.party_leader_id() == String(GameState.tower_team[0]))
	var fallen = mgr.allies[0]
	var fallen_key: String = fallen.source_key
	fallen.take_damage(999999.0)
	for i in 30:
		if mgr.reserves.size() < 2:
			break
		mgr.submit_action({ "kind": "basic" })
		await _wait(0.2)
	_check("al caer un activo entra una reserva", mgr.reserves.size() == 1 and mgr.allies.size() == 3)
	_check("la reserva ocupa el puesto del caido", mgr.find_unit(fallen_key) == null and mgr.allies[0].alive)
	var entered_id: String = mgr.allies[0].id
	_check("la reserva cuenta como participante (cobra XP)", mgr.participant_ids().has(entered_id) and mgr.participant_ids().has(fallen.id))
	var won: bool = await _app.call("_dbg12_finish_battle", false)
	_check("ganar el piso abre el resultado", won)
	_check("el piso 1 paga monedas", GameState.coins > coins_before)
	_check("el progreso avanza: mejor piso 1 y piso actual 2",
		GameState.tower_best_floor(TORRE) == 1 and GameState.tower_run_floor(TORRE) == 2)
	_check("el piso 1 queda cobrado una sola vez", GameState.tower_floor_rewarded(TORRE, 1))
	var token_before := GameState.item_count("mai_token")
	_app.call("close_battle")
	await _wait(0.3)
	_check("la torre NO entrega fichas de Mai", GameState.item_count("mai_token") == token_before)
	_check("el equipo normal de 4 no ha cambiado", GameState.party == party_before)
	_check("el piso 2 ya se puede empezar", GameState.tower_team_problem(TORRE, 2).is_empty())
	var fight2: Button = tower.get("_fight_button")
	_check("la pantalla se repinta con el piso actual 2", fight2.text == "COMBATIR PISO 2")


## --- Derrota y checkpoint ----------------------------------------------------------------
func _check_tower_defeat() -> void:
	_out("[DBG18] == TORRE: DERROTA Y CHECKPOINT ==")
	var state := GameState.tower_state(TORRE)
	state["best_floor"] = 7
	state["checkpoint"] = 5
	state["run_floor"] = 8
	var tower: Node = _screen("tower")
	tower.call("refresh")
	await _frames()
	_check("el piso 8 se puede empezar", GameState.prepare_tower_battle(TORRE, 8))
	_app.call("open_battle")
	await _wait(0.9)
	var battle = _app.get("_battle")
	var mgr = battle.get("manager")
	for unit in mgr.reserves:
		unit.take_damage(999999.0)
	var lost: bool = await _app.call("_dbg12_finish_battle", true)
	_check("la derrota abre el resultado", lost)
	_check("tras perder se vuelve a checkpoint+1 (piso 6)", GameState.tower_run_floor(TORRE) == 6)
	_check("lo conseguido no se pierde (mejor piso 7)", GameState.tower_best_floor(TORRE) == 7)
	_app.call("close_battle")
	await _wait(0.3)
	GameState.tower_state(TORRE)["best_floor"] = 24
	GameState.tower_state(TORRE)["run_floor"] = 25
	_check("el jefe final (25) se puede empezar", GameState.prepare_tower_battle(TORRE, 25))
	_check("el jefe final lleva 2 enemigos", GameState.current_stage_enemies.size() == 2)


## --- El equipo normal sigue funcionando -------------------------------------------------
func _check_normal_team_untouched() -> void:
	_out("[DBG18] == EQUIPO NORMAL TRAS LA TORRE ==")
	_app.call("open_screen", "main_menu")
	await _frames(3)
	_check("al salir de la torre el lider vuelve a ser el del puesto 1 normal",
		GameState.party_leader_id() == String(GameState.party[0]))
	GameState.select_stage(String((DB.all_stages()[0] as Dictionary).get("id", "")))
	_check("un stage normal usa el equipo normal (%d)" % GameState.battle_party_ids().size(),
		GameState.battle_party_ids() == GameState.party_ids())
	_check("un stage normal no tiene reservas", GameState.battle_reserve_data().is_empty())


## --- Estado limpio para las pruebas de historia y evento ----------------------------------
func _reset_progress() -> void:
	GameState.story_progress.clear()
	GameState.event_progress.clear()
	for id in ["sakuta_mai", "sakuta", "sakuta_mai_lr"]:
		GameState.roster.erase(id)
		GameState.rarities.erase(id)
		GameState.progress.erase(id)
	GameState.inventory.erase("mai_token")
	GameState.inventory.erase("rabbit_costume")
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.normalize_party()


## --- HISTORIA de punta a punta ---------------------------------------------------------------
func _check_story() -> void:
	_out("[DBG18] == HISTORIA: MAPA > NIVEL > DIALOGO > COMBATE > RECOMPENSA > PROGRESO ==")
	_reset_progress()
	var worlds: Array = DB.all_worlds()
	_check("hay mundos de historia (%d)" % worlds.size(), worlds.size() >= 3)
	# Datos: todos los niveles y dificultades son jugables.
	var broken: Array = []
	var levels_total := 0
	for raw_world in worlds:
		var world_id := String((raw_world as Dictionary).get("id", ""))
		for raw_level in DB.story_levels(world_id):
			var level: Dictionary = raw_level
			levels_total += 1
			var dialogue_id := String(level.get("dialogue", ""))
			if not dialogue_id.is_empty() and DB.get_dialogue(dialogue_id).is_empty():
				broken.append("dialogo %s" % dialogue_id)
			for diff in (level.get("difficulties", {}) as Dictionary).keys():
				if not GameState.prepare_battle(GameState.BATTLE_STORY, { "level": String(level.get("id", "")), "difficulty": String(diff) }):
					broken.append("%s/%s" % [level.get("id", ""), diff])
	_check("los %d niveles se pueden preparar con todas sus dificultades y dialogos" % levels_total, broken.is_empty())
	if not broken.is_empty():
		_out("[DBG18] ROTOS: %s" % str(broken))
	# Flujo real por las pantallas.
	_app.call("open_screen", "history")
	await _frames(2)
	var history := _screen("history")
	history.call("_on_world_pressed", "world_001")
	await _frames(3)
	_check("tocar el mundo abre el mapa de mundo", String(_app.call("current_screen")) == "world_map")
	var map := _screen("world_map")
	map.call("_on_level_pressed", "world_001_02")
	await _frames()
	var scrim: Control = map.get("panel_scrim")
	_check("un nivel bloqueado no abre su panel", not scrim.visible)
	map.call("_on_level_pressed", "world_001_01")
	await _frames()
	_check("el nivel 1 abre su panel de dificultades", scrim.visible)
	map.call("_on_difficulty_pressed", "normal")
	map.call("_on_start_pressed")
	await _frames(2)
	var dialogue: Control = map.get("dialogue_overlay")
	_check("EMPEZAR muestra primero el dialogo", dialogue.visible and _app.get("_battle") == null)
	var coins_before := GameState.coins
	map.call("_on_dialogue_finished")
	await _wait(0.9)
	_check("al acabar el dialogo se abre el combate", _app.get("_battle") != null)
	var won: bool = await _app.call("_dbg12_finish_battle", false)
	_check("ganar abre el resultado", won)
	_check("la victoria paga monedas", GameState.coins > coins_before)
	_check("el nivel 1 queda superado en NORMAL", GameState.story_level_cleared("world_001_01") or bool(GameState.story_level_status("world_001_01").get("difficulties_completed", 0)))
	_check("el nivel 2 se desbloquea", GameState.story_level_unlocked("world_001_02"))
	_app.call("close_battle")
	await _wait(0.3)
	# Recorrido completo por datos: abre los mundos siguientes.
	for raw_world in worlds:
		var world_id := String((raw_world as Dictionary).get("id", ""))
		for raw_level in DB.story_levels(world_id):
			var level: Dictionary = raw_level
			var diffs: Array = (level.get("difficulties", {}) as Dictionary).keys()
			diffs.sort_custom(func(a, b): return int(level["difficulties"][a].get("order", 0)) < int(level["difficulties"][b].get("order", 0)))
			for diff in diffs:
				GameState.complete_story_level(String(level.get("id", "")), String(diff), ["gojo"])
	var all_open := true
	for raw_world in worlds:
		all_open = all_open and GameState.world_unlocked(String((raw_world as Dictionary).get("id", "")))
	_check("completando los niveles se abren todos los mundos", all_open)
	_app.call("open_screen", "main_menu")
	await _frames(2)


## --- EVENTO: Sindromes de la Pubertad ------------------------------------------------------------
func _play_event_stage(stage_id: String, win: bool) -> bool:
	var events := _screen("events")
	events.call("_on_play_pressed", EVENTO, stage_id)
	await _wait(0.9)
	if _app.get("_battle") == null:
		return false
	var done: bool = await _app.call("_dbg12_finish_battle", not win)
	_app.call("close_battle")
	await _wait(0.3)
	return done


func _check_event_flow() -> void:
	_out("[DBG18] == EVENTO: STAGE 1, 2 y 3 ==")
	_reset_progress()
	_app.call("open_screen", "events")
	await _frames(2)
	var claim_before: Dictionary = GameState.claim_event_character(EVENTO)
	_check("Stage 1: NO se puede reclamar a Sakuta/Mai sin superarlo", not bool(claim_before.get("ok", true)) and not GameState.is_owned("sakuta_mai"))
	await _play_event_stage("evt_sdp_01", false)
	_check("perder el Stage 1 no lo marca como superado ni da la unidad",
		not GameState.event_stage_completed(EVENTO, "evt_sdp_01") and not GameState.claim_event_character(EVENTO).get("ok", false) and not GameState.is_owned("sakuta_mai"))
	await _play_event_stage("evt_sdp_01", true)
	_check("ganar el Stage 1 lo marca como superado", GameState.event_stage_completed(EVENTO, "evt_sdp_01"))
	var claim_after: Dictionary = GameState.claim_event_character(EVENTO)
	_check("tras superarlo SI se puede reclamar a Sakuta/Mai", bool(claim_after.get("ok", false)) and GameState.is_owned("sakuta_mai"))
	_check("reclamar de nuevo no la duplica", bool(GameState.claim_event_character(EVENTO).get("already", false)))

	# Stage 2: pide a Sakuta+Mai en el equipo.
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	var gate_without: Dictionary = GameState.event_party_ready(EVENTO, "evt_sdp_02", GameState.party)
	_check("Stage 2 sin Sakuta/Mai en el equipo: rechazado", not bool(gate_without.get("ok", true)))
	GameState.party = ["sakuta_mai", "isagi", "", ""]
	GameState.normalize_party()
	_check("Stage 2 con Sakuta/Mai: admitido", bool(GameState.event_party_ready(EVENTO, "evt_sdp_02", GameState.party).get("ok", false)))
	var costumes_before := GameState.item_count("rabbit_costume")
	await _play_event_stage("evt_sdp_02", true)
	_check("ganar el Stage 2 lo supera", GameState.event_stage_completed(EVENTO, "evt_sdp_02"))
	_check("el Stage 2 suelta uniformes de conejita", GameState.item_count("rabbit_costume") > costumes_before)

	# Stage 3: Sakuta UR SOLO.
	GameState.add_character("sakuta")
	_check("Sakuta esta en forma UR", GameState.rarity_of("sakuta") == "UR")
	GameState.party = ["sakuta_mai", "isagi", "", ""]
	GameState.normalize_party()
	_check("Stage 3 con Sakuta/Mai (no Sakuta UR): rechazado", not bool(GameState.event_party_ready(EVENTO, "evt_sdp_03", GameState.party).get("ok", true)))
	GameState.party = ["sakuta", "isagi", "", ""]
	GameState.normalize_party()
	_check("Stage 3 con Sakuta + otro personaje: rechazado (es 1 VS 1)", not bool(GameState.event_party_ready(EVENTO, "evt_sdp_03", GameState.party).get("ok", true)))
	GameState.assign_party_slot(1, "")
	_check("el equipo queda en 1/4", GameState.party_count() == 1)
	_check("Stage 3 con [SAKUTA][HUECO][HUECO][HUECO]: admitido", bool(GameState.event_party_ready(EVENTO, "evt_sdp_03", GameState.party).get("ok", false)))
	var tokens_before := GameState.item_count("mai_token")
	var events := _screen("events")
	events.call("_on_play_pressed", EVENTO, "evt_sdp_03")
	await _wait(0.9)
	var battle = _app.get("_battle")
	_check("el Stage 3 abre el combate", battle != null)
	if battle != null:
		var mgr = battle.get("manager")
		_check("el Stage 3 combate 1 VS 1 (aliados: %d)" % mgr.allies.size(), mgr.allies.size() == 1 and mgr.allies[0].id == "sakuta")
		await _app.call("_dbg12_finish_battle", false)
		_app.call("close_battle")
		await _wait(0.3)
	_check("ganar el Stage 3 da 1 ficha dorada de Mai", GameState.item_count("mai_token") == tokens_before + 1)
	_app.call("open_screen", "main_menu")
	await _frames(2)


## --- EVOLUCION: pantalla ANTES > MATERIAL > DESPUES, regla de Mai y animacion -----------------
func _check_evolution() -> void:
	_out("[DBG18] == EVOLUCION: PANTALLA Y ANIMACION ==")
	_reset_progress()
	GameState.add_character("sakuta_mai")
	GameState.inventory.erase("rabbit_costume")
	_app.call("open_screen", "evolution")
	await _frames(3)
	var screen := _screen("evolution")
	screen.set("_selected_id", "sakuta_mai")
	screen.call("_build_detail")
	await _frames(2)
	var detail: VBoxContainer = screen.get("detail_box")
	var row: Node = detail.find_child("EvolutionRow", true, false)
	_check("la pantalla pinta la fila ANTES > MATERIAL > DESPUES", row != null and row.get_child_count() == 3)
	_check("muestra el camino SSR > UR > LR", detail.find_child("RarityPath", true, false) != null)
	var button: Button = detail.find_child("EvolveButton", true, false)
	_check("sin nivel 100 ni uniformes el boton esta BLOQUEADO", button != null and button.disabled)
	var check: Dictionary = GameState.can_special_evolve("sakuta_mai")
	_check("SSR->UR pide nivel 100", int(check.get("level_required", 0)) == 100)
	_check("SSR->UR pide 25 uniformes y 0 monedas", int(check.get("coin_cost", -1)) == 0 and str(check.get("item_cost", [])).contains("25"))
	_check("con 10.000 monedas NO se puede evolucionar", _no_coin_shortcut())
	# Cumplir los requisitos y evolucionar de verdad desde el boton.
	GameState.set_level("sakuta_mai", 100)
	GameState.add_item("rabbit_costume", 25)
	screen.call("refresh")
	screen.call("_build_detail")
	await _frames(2)
	button = detail.find_child("EvolveButton", true, false)
	var ready := button != null and not button.disabled
	_check("con nivel 100 y 25 uniformes el boton se habilita", ready)
	if ready:
		screen.call("_on_evolve_pressed")
		await _frames(2)
		var fx = screen.get_node_or_null("EvolutionFx")
		_check("evolucionar lanza la animacion de evolucion", fx != null)
		_check("se consumen los 25 uniformes y no monedas", GameState.item_count("rabbit_costume") == 0)
		_check("Sakuta (UR) esta en el roster", GameState.is_owned("sakuta") and GameState.rarity_of("sakuta") == "UR")
		if fx != null:
			await _wait(2.6)
			_check("la animacion cambia el arte (flash + swap)", bool(fx.get("swapped")) if is_instance_valid(fx) else true)
			await _wait(2.0)
			_check("la animacion se retira sola", not is_instance_valid(fx))
	_app.call("open_screen", "main_menu")
	await _frames(2)


func _no_coin_shortcut() -> bool:
	GameState.coins = 10000
	var info: Dictionary = GameState.can_special_evolve("sakuta_mai")
	return not bool(info.get("ok", true))


## --- ARTE POR ID: rutas anidadas + compatibilidad con las carpetas de siempre -------------------
func _check_art_by_id() -> void:
	_out("[DBG18] == ARTE POR ID ==")
	var Portrait = load("res://ui/portrait.gd")
	_check("familia de gojo_002 es gojo", Portrait.family_of("gojo_002") == "gojo")
	_check("un id antiguo (gojo) es su propia familia", Portrait.family_of("gojo") == "gojo")
	var nested: Array = Portrait.art_dirs("gojo_002")
	_check("gojo_002 busca primero art/characters/gojo/gojo_002/ y luego la plana",
		nested.size() == 2 and String(nested[0]) == "res://art/characters/gojo/gojo_002/" and String(nested[1]) == "res://art/characters/gojo_002/")
	_check("un id antiguo solo usa su carpeta plana (nada existente se mueve)",
		Portrait.art_dirs("gojo") == ["res://art/characters/gojo/"])
	var probe = Portrait.new()
	probe.form = "ur"
	probe.slot = "front"
	var paths: Array = probe._candidates("gojo_002", "res://art/characters/gojo_002/front.png")
	_check("el arte de la forma UR va ANTES que el base y que la ruta explicita",
		String(paths[0]) == "res://art/characters/gojo/gojo_002/ur/front.png"
		and paths.find("res://art/characters/gojo_002/front.png") > paths.find("res://art/characters/gojo_002/ur/front.png"))
	probe.free()
	_check("el nombre visible NO es el id (gojo sigue mostrando su nombre)",
		GameState.display_name("gojo") != "gojo" and not GameState.display_name("gojo").is_empty())


## --- COMBATE: FRONT en la fila, BACK en el activo, ataque normal y ULTI -------------------------
func _check_combat_visuals() -> void:
	_out("[DBG18] == COMBATE VISUAL: FRONT/BACK, ATAQUE Y ULTI ==")
	_reset_progress()
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	_app.call("open_battle")
	await _wait(1.2)
	var battle = _app.get("_battle")
	_check("el combate se abre", battle != null)
	if battle == null:
		return
	var mgr = battle.get("manager")
	var all_front := true
	for unit in mgr.allies:
		var card = battle.get("cards").get(unit.source_key)
		if card == null or String(card.portrait.slot) != "front":
			all_front = false
	_check("los 4 personajes de la fila usan arte FRONT", all_front and mgr.allies.size() == 4)
	# esperar el turno de un aliado
	var actor = null
	for i in 40:
		actor = mgr.next_actor()
		if actor != null and actor.is_ally and bool(battle.get("awaiting_input")):
			break
		await _wait(0.15)
	_check("llega el turno de un aliado", actor != null and actor.is_ally)
	if actor == null:
		return
	var active = battle.get("active_portrait")
	_check("el personaje que ataca usa arte BACK grande", String(active.slot) == "back")
	_check("la fila y el activo usan ranuras distintas (no hay copia duplicada)",
		String(battle.get("cards").get(actor.source_key).portrait.slot) != String(active.slot))
	var fx_before: int = battle.get("fx_played")
	mgr.submit_action({ "kind": "basic" })
	await _wait(0.5)
	_check("el ataque normal lanza su animacion", int(battle.get("fx_played")) > fx_before)
	# ULTI en el siguiente turno aliado
	for i in 40:
		actor = mgr.next_actor()
		if actor != null and actor.is_ally and bool(battle.get("awaiting_input")):
			break
		await _wait(0.15)
	actor.sp = 10
	var ultimate_layers_before := _count_fx_layers(battle)
	fx_before = battle.get("fx_played")
	var t0 := Time.get_ticks_msec()
	mgr.submit_action({ "kind": "special" })
	await _wait(0.3)
	_check("la ulti lanza su animacion", int(battle.get("fx_played")) > fx_before)
	_check("la ulti dibuja su capa de efectos (oscurecer, lineas, flash)", _count_fx_layers(battle) > ultimate_layers_before)
	await _wait(2.5)
	_check("la capa de la ulti se retira sola", _count_fx_layers(battle) == ultimate_layers_before)
	_check("el combate sigue vivo tras la ulti", _app.get("_battle") != null and not mgr._finished)
	await _app.call("_dbg12_finish_battle", false)
	_app.call("close_battle")
	await _wait(0.3)


func _count_fx_layers(battle: Node) -> int:
	var count := 0
	for child in battle.get_children():
		if child is Control and (child as Control).z_index == 30:
			count += 1
	return count


## --- GACHA: tasas, 10 tiradas independientes, animacion y exclusion F2P ---------------------------
func _check_gacha() -> void:
	_out("[DBG18] == GACHA ==")
	_reset_progress()
	var banner_id := String((DB.all_banners()[0] as Dictionary).get("id", ""))
	var rates: Dictionary = GameState.banner_rates(banner_id)
	var ssr := 0
	var total := 20000
	for i in total:
		if GameState.roll_rarity(rates) == "SSR":
			ssr += 1
	var ratio := float(ssr) / float(total)
	_check("tasa de SSR por tirada ~15%% (medida %.3f en %d tiradas)" % [ratio, total], ratio > 0.14 and ratio < 0.16)
	GameState.gems = 100000
	var screen := _screen("summon")
	_app.call("open_screen", "summon")
	await _frames(3)
	var gems_before := GameState.gems
	var roster_before := GameState.roster.size()
	screen.call("_on_roll", 10)
	await _frames(2)
	var fx = screen.get_node_or_null("SummonFx")
	_check("invocar x10 lanza la animacion de invocacion", fx != null)
	# REGLA VIGENTE (V4): la x10 ya NO pinta una cuadricula de diez cartas; los resultados
	# se fijan y se revelan UNO A UNO en SummonReveal (se prueba a fondo en DBG19).
	# Esta comprobacion antigua se actualiza a ese flujo, con la misma exigencia.
	_check("no hay resultados visibles antes del destello", screen.get_node_or_null("SummonReveal") == null)
	var single: Button = screen.get("single_button")
	_check("los botones se bloquean durante la animacion", single.disabled)
	fx.call("_skip")
	await _frames(3)
	var rv := screen.get_node_or_null("SummonReveal")
	_check("tras la animacion aparece el revelado individual (no la cuadricula)", rv != null and GameState.has_pending_reveal())
	_check("la invocacion cobro las gemas del banner una sola vez", gems_before - GameState.gems == GameState.banner_cost(banner_id, 10))
	_check("hay exactamente 10 resultados fijados", (GameState.pending_reveal.get("results", []) as Array).size() == 10)
	# Se cierra la secuencia como lo hace VOLVER AL BANNER.
	if rv != null:
		rv.queue_free()
	GameState.reveal_finish()
	screen.call("_set_buttons_locked", false)
	await _frames(2)
	_check("los botones se vuelven a habilitar", not single.disabled)
	screen.call("_on_roll", 1)
	await _frames(2)
	fx = screen.get_node_or_null("SummonFx")
	if fx != null:
		fx.call("_skip")
		await _frames(3)
	rv = screen.get_node_or_null("SummonReveal")
	_check("tocar la pantalla salta la animacion y abre el revelado de la x1", rv != null and (GameState.pending_reveal.get("results", []) as Array).size() == 1)
	if rv != null:
		rv.queue_free()
	GameState.reveal_finish()
	screen.call("_set_buttons_locked", false)
	# pool: F2P fuera
	var leaked := false
	for raw in DB.all_banners():
		var pool: Array = GameState.banner_pool(String((raw as Dictionary).get("id", "")))
		for id in ["sakuta_mai", "sakuta", "sakuta_mai_lr"]:
			if pool.has(id):
				leaked = true
	_check("ningun banner incluye a Sakuta/Mai en su pool", not leaked)
	_app.call("open_screen", "main_menu")
	await _frames(2)


## --- Misiones: progreso, sin cobro anticipado, pago unico, persistencia -------
func _check_missions() -> void:
	var id := "mis_primera_victoria"
	GameState.missions_claimed.erase(id)
	var stat := String(DB.get_mission(id).get("stat", ""))
	var target := int(DB.get_mission(id).get("target", 1))
	GameState.counters[stat] = 0
	var before := GameState.coins + GameState.gems
	_check("mision: sin progreso no se puede cobrar", GameState.claim_mission(id).is_empty())
	GameState.counters[stat] = target
	var st := GameState.mission_state(id)
	_check("mision: completada con el contador en el objetivo", bool(st["completed"]))
	var paid := GameState.claim_mission(id)
	_check("mision: cobro entrega recompensa", not paid.is_empty()
		and GameState.coins + GameState.gems == before + int(paid["coins"]) + int(paid["gems"]))
	_check("mision: no se cobra dos veces", GameState.claim_mission(id).is_empty())
	_check("mision: queda guardada como cobrada", bool(GameState.mission_state(id)["claimed"]))
	GameState.missions_claimed.erase(id)


## --- Gacha: tabla REAL de probabilidades (se comprueban los datos, no una simulacion) -
func _check_gacha_rates() -> void:
	var excluded_ok := true
	for raw in DB.all_banners():
		var bid := String((raw as Dictionary).get("id", ""))
		var cfg: Dictionary = (raw as Dictionary).get("rates", {})
		var eff := GameState.banner_rates(bid)
		var total := 0.0
		for k in cfg:
			total += float(cfg[k])
		_out("[DBG18] gacha %s: tabla %s (suma %.6f)" % [bid, str(cfg), total])
		_check("%s: la tabla suma exactamente 100%%" % bid, absf(total - 1.0) < 1e-12)
		_check("%s: SSR configurado = 15%% por tirada" % bid, absf(float(cfg.get("SSR", -1.0)) - 0.15) < 1e-12)
		_check("%s: las probabilidades efectivas son las configuradas (sin renormalizar)" % bid, str(eff) == str(_clean(cfg)))
		_check("%s: sin rarezas sin personajes ni errores de configuracion (%s)" % [bid, str(GameState.banner_problems(bid))],
			GameState.banner_problems(bid).is_empty())
		_check("%s: no hay rareza R en la tabla (sin personajes R de relleno)" % bid, not cfg.has("R"))
		var pool: Array = GameState.banner_pool(bid)
		for banned in ["sakuta_mai", "sakuta", "sakuta_mai_lr"]:
			if pool.has(banned):
				excluded_ok = false
		var wanted: Array = (raw as Dictionary).get("pool_categories", [])
		if not wanted.is_empty():
			var all_in := true
			for id in pool:
				var cats: Array = DB.get_character(String(id)).get("categories", [])
				var hit := false
				for c in wanted:
					if cats.has(c):
						hit = true
				all_in = all_in and hit
			_check("%s: el pool respeta sus categorias %s" % [bid, str(wanted)], all_in and not pool.is_empty())
	_check("ningun banner contiene a Sakuta/Mai (F2P ni evoluciones)", excluded_ok)
	# El umbral de roll_rarity: con la tabla [SR .85, SSR .15] y un aleatorio justo
	# por debajo/encima de .85 se obtienen SR/SSR. Es la funcion real del juego.
	var rates := GameState.banner_rates("banner_apertura")
	_check("tirada exacta: 0.8499 -> SR y 0.8501 -> SSR", GameState.rarity_for_roll(rates, 0.8499) == "SR" and GameState.rarity_for_roll(rates, 0.8501) == "SSR" and GameState.rarity_for_roll(rates, 0.0) == "SR" and GameState.rarity_for_roll(rates, 0.99999) == "SSR")
	# INDEPENDENCIA: una x10 hace 10 tiradas, cada una con su propio sorteo y su
	# propio personaje de la rareza sacada. Se comprueba sobre el codigo real.
	GameState.gems = 100000
	var seen_ssr_counts := {}
	for rep in 40:
		var rep_report: Dictionary = GameState.summon("banner_apertura", 10)
		if not bool(rep_report.get("ok", false)):
			_out("[DBG18] summon x10 rechazado: %s" % String(rep_report.get("reason", "")))
		_check_silent(bool(rep_report.get("ok", false)) and (rep_report["results"] as Array).size() == 10)
		var n := 0
		for res in rep_report["results"]:
			if String(res["rarity"]) == "SSR":
				n += 1
		seen_ssr_counts[n] = true
	_check("x10: 40 multis dan cantidades de SSR distintas (las tiradas no estan atadas)", seen_ssr_counts.size() >= 3)
	_out("[DBG18] (la comprobacion anterior es de comportamiento; la probabilidad exacta se comprueba arriba sobre los datos y el umbral de roll_rarity)")
	# Un banner roto se rechaza SIN cobrar.
	var saved: Dictionary = DB.banners["banner_apertura"].duplicate(true)
	DB.banners["banner_apertura"]["rates"] = { "SR": 0.5, "SSR": 0.15 }
	var gems_before := GameState.gems
	var bad: Dictionary = GameState.summon("banner_apertura", 1)
	_check("un banner cuya tabla no suma 1 se rechaza sin cobrar", not bool(bad.get("ok", true)) and GameState.gems == gems_before)
	DB.banners["banner_apertura"] = saved


func _clean(cfg: Dictionary) -> Dictionary:
	var out := {}
	for k in cfg:
		if float(cfg[k]) > 0.0:
			out[String(k)] = float(cfg[k])
	return out


func _check_silent(ok: bool) -> void:
	if not ok:
		_check("tirada x10 valida", false)


## --- Audio: archivos propios sintetizados + el sistema tolera la falta de archivos --
func _check_audio_files() -> void:
	var missing: Array = GameAudio.missing_events()
	_check("audio: los %d sonidos del catalogo tienen archivo (faltan: %s)" % [GameAudio.all_events().size(), str(missing)], missing.is_empty())
	_check("audio: un slot sin archivo devuelve null y no rompe", GameAudio.load_stream("no_existe") == null)
	GameAudio.play("no_existe")
	GameAudio.play_music("no_existe")
	_check("audio: pedir musica inexistente deja la pista vacia", String(GameAudio.get("_music_path")).is_empty())
	GameSettings.set_value("music_volume", 0.8, false)
	GameAudio.play_music("history")
	_check("audio: la musica 'history' suena (pista cargada)", not String(GameAudio.get("_music_path")).is_empty())
	var player: AudioStreamPlayer = GameAudio.get("_music")
	var stream := player.stream as AudioStreamWAV
	_check("audio: el WAV de musica tiene bucle cerrado", stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end > 0)
	GameSettings.set_value("music_volume", 0.0, false)
	_check("audio: music_volume 0 = silencio", player.volume_db <= -79.0)
	GameSettings.set_value("music_volume", 0.8, false)
	_check("audio: music_volume 0.8 vuelve a sonar", player.volume_db > -30.0)
	GameAudio.stop_music()


func _music_players_playing() -> int:
	var n := 0
	for child in GameAudio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing and (child as AudioStreamPlayer).stream != null:
			if String((child as AudioStreamPlayer).stream.resource_path).contains("/music/"):
				n += 1
	return n


## Musica por pantalla, sin solapes, y musica de resultados al entrar en resultados.
func _check_music_flow() -> void:
	_out("[DBG18] == MUSICA POR PANTALLA ==")
	GameSettings.set_value("music_volume", 0.8, false)
	var expected := { "main_menu": "menu", "history": "history", "events": "events", "tower": "events", "inventory": "menu", "shop": "menu", "stage_select": "history" }
	for screen in expected:
		_app.call("open_screen", screen)
		await _frames(3)
		var path := String(GameAudio.get("_music_path"))
		_check("musica en %s = %s" % [screen, expected[screen]], path.ends_with("/%s.wav" % expected[screen]))
		_check("musica en %s: una sola pista sonando (%d)" % [screen, _music_players_playing()], _music_players_playing() <= 1)
		_app.call("go_back")
		await _frames(2)
	# Combate -> resultados.
	_reset_progress()
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	_app.call("open_battle")
	await _wait(0.6)
	_check("musica de combate al abrir la batalla", String(GameAudio.get("_music_path")).ends_with("/battle.wav"))
	await _app.call("_dbg12_finish_battle", false)
	await _wait(2.4)
	_check("musica de RESULTADOS al aparecer el panel de resultados", String(GameAudio.get("_music_path")).ends_with("/results.wav"))
	_check("resultados: una sola pista de musica sonando", _music_players_playing() <= 1)
	_app.call("close_battle")
	await _wait(0.3)
	_check("al cerrar el combate vuelve la musica de pantalla (no sigue 'results')", not String(GameAudio.get("_music_path")).ends_with("/results.wav"))
	GameAudio.stop_music()


## --- Audio en uso real: pista por pantalla, resultados, un solo reproductor, huecos --
func _music_name() -> String:
	return String(GameAudio.get("_music_path")).get_file().get_basename()


func _check_audio_flow() -> void:
	_out("[DBG18] == AUDIO EN USO ==")
	GameSettings.set_value("music_volume", 0.8, false)
	var expected := {
		"main_menu": "menu", "collection": "menu", "team": "menu", "summon": "menu", "shop": "menu",
		"history": "history", "world_map": "history", "stage_select": "history",
		"events": "events", "tower": "events",
	}
	for screen in expected:
		_app.call("open_screen", screen)
		await _frames(3)
		_check("musica de '%s' = %s (suena: %s)" % [screen, expected[screen], _music_name()], _music_name() == expected[screen])
	# Un solo AudioStreamPlayer de musica: contar reproductores de musica activos.
	var playing := 0
	for child in GameAudio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing and String((child as AudioStreamPlayer).stream.resource_path).contains("/music/"):
			playing += 1
	_check("solo suena UNA pista de musica a la vez (%d)" % playing, playing == 1)
	# Combate -> victoria -> resultados.
	_reset_progress()
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	_app.call("open_battle")
	await _wait(0.8)
	_check("en combate suena battle", _music_name() == "battle")
	await _app.call("_dbg12_finish_battle", false)
	await _wait(2.4)
	_check("al abrirse el resultado suena 'results' (%s)" % _music_name(), _music_name() == "results")
	playing = 0
	for child in GameAudio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing and String((child as AudioStreamPlayer).stream.resource_path).contains("/music/"):
			playing += 1
	_check("en resultados sigue habiendo una sola pista (%d)" % playing, playing == 1)
	_app.call("close_battle")
	await _wait(0.3)
	_check("al cerrar el combate vuelve la musica de la pantalla", _music_name() != "battle" and _music_name() != "results")
	# Efectos: volumen de efectos 0 = silencio; los de interfaz siguen su propio ajuste.
	GameSettings.set_value("sfx_volume", 0.0, false)
	GameSettings.set_value("ui_volume", 0.5, false)
	GameAudio.play("attack")
	GameAudio.play("click")
	var vols := {}
	for child in GameAudio.get_children():
		if child is AudioStreamPlayer and child.stream != null and not String(child.stream.resource_path).contains("/music/"):
			vols[String(child.stream.resource_path).get_file()] = (child as AudioStreamPlayer).volume_db
	_check("sfx_volume 0 silencia 'attack' (%s)" % str(vols.get("attack.wav")), vols.has("attack.wav") and vols["attack.wav"] <= -79.0)
	_check("ui_volume 0.5 baja 'click' sin silenciarlo", vols.has("click.wav") and vols["click.wav"] > -30.0 and vols["click.wav"] < GameAudio.SFX_VOLUME)
	GameSettings.set_value("sfx_volume", 0.8, false)
	GameSettings.set_value("ui_volume", 0.8, false)
	# AUSENCIA de archivos: se apartan TODOS los del catalogo y se pide cada sonido.
	# Los recursos que siguen sonando quedan en la cache de Godot: se paran antes.
	GameAudio.stop_music()
	for child in GameAudio.get_children():
		if child is AudioStreamPlayer and child != GameAudio.get("_music"):
			(child as AudioStreamPlayer).stop()
			child.queue_free()
	await _wait(0.5)
	var moved: Array = []
	for cat in GameAudio.CATALOG:
		for n in GameAudio.CATALOG[cat]:
			for ext in [".wav", ".wav.import"]:
				var path := "res://audio/%s/%s%s" % [cat, n, ext]
				if FileAccess.file_exists(path):
					DirAccess.rename_absolute(path, path + ".bak")
					moved.append(path)
	var none_missing := true
	for cat in GameAudio.CATALOG:
		for n in GameAudio.CATALOG[cat]:
			if cat == "music":
				GameAudio.play_music(String(n))
			else:
				GameAudio.play(String(n))
			if GameAudio.load_stream(String(n)) != null:
				none_missing = false
				_out("[DBG18]   aun carga: %s -> %s (existe archivo: %s)" % [n, GameAudio.path_for(String(n)), str(FileAccess.file_exists(GameAudio.path_for(String(n))))])
	_check("sin ningun archivo de audio: se piden los 25 sonidos sin error y no suena nada", none_missing and String(GameAudio.get("_music_path")).is_empty())
	for path in moved:
		DirAccess.rename_absolute(path + ".bak", path)
	GameAudio.stop_music()
	_check("archivos de audio restaurados tras la prueba", GameAudio.missing_events().is_empty())


## --- Navegacion REAL: se pulsan los botones del menu principal y los de VOLVER --------
func _find_back(screen: Node) -> Button:
	for b in screen.find_children("*", "Button", true, false):
		if String((b as Button).text).strip_edges() == "VOLVER" and (b as Button).is_visible_in_tree():
			return b
	return null


func _check_navigation() -> void:
	_out("[DBG18] == NAVEGACION: menu -> cada pantalla -> VOLVER ==")
	_reset_progress()
	_app.call("open_screen", "main_menu")
	await _frames(3)
	var menu := _screen("main_menu")
	var routes := {
		"TeamButton": "team", "CollectionButton": "collection", "SummonButton": "summon",
		"MissionsButton": "missions", "HistoryButton": "history", "EventsButton": "events",
		"EvolutionButton": "evolution", "InventoryButton": "inventory", "ShopButton": "shop",
		"MutationsButton": "mutations", "SettingsButton": "settings", "TowerButton": "tower",
		"PlayButton": "stage_select",
	}
	for node_name in routes:
		var btn := menu.find_child(String(node_name), true, false) as Button
		if btn == null:
			_check("existe el boton %s" % node_name, false)
			continue
		btn.pressed.emit()
		await _frames(4)
		var here := String(_app.call("current_screen"))
		_check("%s abre '%s' (abre: %s)" % [node_name, routes[node_name], here], here == routes[node_name])
		var back := _find_back(_screen(here))
		_check("'%s' tiene boton VOLVER visible" % here, back != null)
		if back != null:
			back.pressed.emit()
			await _frames(4)
		_check("VOLVER desde '%s' vuelve al menu" % here, String(_app.call("current_screen")) == "main_menu")
	# Historia -> mapa -> VOLVER -> Historia -> VOLVER -> menu
	(menu.find_child("HistoryButton", true, false) as Button).pressed.emit()
	await _frames(3)
	_screen("history").call("_on_world_pressed", "world_001")
	await _frames(4)
	_check("Historia -> mapa del mundo", String(_app.call("current_screen")) == "world_map")
	var back2 := _find_back(_screen("world_map"))
	if back2 != null:
		back2.pressed.emit()
		await _frames(4)
	_check("VOLVER del mapa lleva a Historia", String(_app.call("current_screen")) == "history")
	var back3 := _find_back(_screen("history"))
	if back3 != null:
		back3.pressed.emit()
		await _frames(4)
	_check("y de Historia al menu", String(_app.call("current_screen")) == "main_menu")
