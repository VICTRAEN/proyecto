extends Node

## COMPROBACIONES EN EJECUCION DE LA v11. SOLO para pruebas.
## Arranque:  godot --path . -- --dbg23   (escribe res://dbg23_resultados.txt)
## Cubre: volumen del tema del duo, libro de copias (12 copias), orden aleatorio del
## equipo, jefes con personajes de anime, interfaz de combate despejada, y el
## buscador/filtros de Evolucion y Mutaciones. Usa funciones y pantallas REALES.

const RESULTS_PATH := "res://dbg23_resultados.txt"
const DUO := "david_lucy_duo"

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
	_out("[DBG23] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func run(app: Node) -> void:
	_app = app
	await _wait(0.3)
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out("[DBG23] --- comprobaciones v11 ---")
	_app.call("_backup_save")
	_check_duo_volume()
	_check_ledger()
	_check_order_random()
	_check_enemies()
	await _check_battle_ui()
	await _check_pick_screens()
	_app.call("_restore_save")
	_out("[DBG23] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## --- 1. Volumen del tema del duo (x2 = +6 dB) solo para esa pista ---------------------
func _check_duo_volume() -> void:
	_out("[DBG23] == VOLUMEN DEL TEMA DEL DUO ==")
	GameSettings.set_value("music_volume", 0.8, false)
	var base_db: float = GameAudio._music_db("menu")
	var duo_db: float = GameAudio._music_db("david_lucy_theme")
	var ratio := db_to_linear(duo_db - base_db)
	_check("el tema del duo suena al DOBLE de amplitud (x%.3f, +%.2f dB)" % [ratio, duo_db - base_db], absf(ratio - 2.0) < 0.03)
	var others_same := true
	for slot in ["menu", "battle", "history", "events", "results"]:
		if not is_equal_approx(GameAudio._music_db(slot), base_db):
			others_same = false
	_check("el resto de la musica NO cambia de volumen", others_same)
	GameAudio.play_music("menu")
	var menu_player: AudioStreamPlayer = GameAudio.get("_music")
	var menu_db := menu_player.volume_db
	GameAudio.play_music("david_lucy_theme")
	var duo_play_db := menu_player.volume_db
	_check("al sonar de verdad, el reproductor sube +6 dB con el tema del duo (%.2f -> %.2f)" % [menu_db, duo_play_db], absf((duo_play_db - menu_db) - 6.02) < 0.1)
	GameAudio.play_music("battle")
	_check("al volver a otra pista el volumen vuelve al normal", absf(menu_player.volume_db - menu_db) < 0.01)
	GameSettings.set_value("music_volume", 0.0, false)
	GameAudio.play_music("david_lucy_theme")
	_check("con la musica a 0 el tema del duo tambien queda en silencio", menu_player.volume_db <= -79.0)
	GameAudio.stop_music()
	GameSettings.set_value("music_volume", 0.8, false)


## --- 5. Libro de copias: 12 copias = total 12, disponibles 11, usadas 1 ---------------
func _check_ledger() -> void:
	_out("[DBG23] == COPIAS DE DAVID + LUCY (libro de copias) ==")
	if not GameState.roster.has(DUO):
		GameState.roster.append(DUO)
	GameState.progress[DUO] = { "level": 1, "xp": 0 }
	GameState.rarities.erase(DUO)
	GameState.duplicates[DUO] = 11
	GameState.dupe_levels.erase(DUO)
	var l := GameState.copy_ledger(DUO)
	_check("12 copias SSR: total 12, disponibles 11, usadas 1 (la unidad)", int(l["total"]) == 12 and int(l["available"]) == 11 and int(l["used"]) == 1)
	_check("invariante total = disponibles + usadas", int(l["total"]) == int(l["available"]) + int(l["used"]))
	_check("el texto del libro es claro", GameState.copy_ledger_text(DUO) == "12 en total: 11 disponibles, 1 usadas")
	# Evolucionar la unidad a UR y a LR no pierde ni duplica copias.
	GameState.rarities[DUO] = "UR"
	var l2 := GameState.copy_ledger(DUO)
	_check("tras evolucionar a UR el total sigue siendo 12 (11 disponibles)", int(l2["total"]) == 12 and int(l2["available"]) == 11)
	GameState.rarities[DUO] = "LR"
	_check("tras evolucionar a LR sigue siendo 12", int(GameState.copy_ledger(DUO)["total"]) == 12)
	# Mejorar (Dupe): gasta copias pero el total no cambia.
	var up := GameState.dupe_upgrade(DUO)
	var l3 := GameState.copy_ledger(DUO)
	_check("mejorar con Dupe consume solo el coste (%d) y el total sigue en 12" % int(up.get("spent", 0)), bool(up.get("done", false)) and int(l3["total"]) == 12 and int(l3["spent"]) == int(up.get("spent", 0)) and int(l3["available"]) == 11 - int(up.get("spent", 0)))
	_check("usadas = unidad + gastadas en Dupes", int(l3["used"]) == 1 + int(l3["spent"]))
	_check("usadas + disponibles = total tras el Dupe", int(l3["used"]) + int(l3["available"]) == int(l3["total"]))
	# Guardar y cargar no cambia las cuentas.
	GameState.save_game()
	GameState.load_game()
	var l4 := GameState.copy_ledger(DUO)
	_check("guardar y cargar conserva total/disponibles/usadas", l4["total"] == l3["total"] and l4["available"] == l3["available"] and l4["used"] == l3["used"])
	# La pila de copias lo refleja.
	var stack := {}
	for st in GameState.copy_stacks():
		if String(st["id"]) == DUO:
			stack = st
	_check("la pila de copias SSR muestra disponibles (%d) y total (12)" % int(stack.get("count", -1)), not stack.is_empty() and int(stack["count"]) == int(l4["available"]) and int(stack["total"]) == 12)
	GameState.dupe_levels.erase(DUO)
	GameState.rarities.erase(DUO)
	GameState.duplicates[DUO] = 11
	var no_ghosts := GameState.copy_ledger("no_existe")
	_check("un personaje que no se tiene: libro vacio, sin errores", int(no_ghosts["total"]) == 0)


## --- 3. Orden de ataque aleatorio ------------------------------------------------------
func _check_order_random() -> void:
	_out("[DBG23] == ORDEN DE ATAQUE ALEATORIO DEL EQUIPO ==")
	var BM := load("res://core/battle_manager.gd")
	var mgr: Node = BM.new()
	add_child(mgr)
	var allies: Array = []
	for id in ["gojo", "isagi", "frieren", "mai"]:
		allies.append(GameState.character_data(id))
	mgr.setup(allies, [DB.get_enemy("vigia_alfa"), DB.get_enemy("vigia_beta")])
	# Referencia: orden por velocidad sin sorteo.
	mgr.randomize_ally_order = false
	mgr.call("_build_order")
	var base: Array = mgr.order.duplicate()
	var base_sides: Array = []
	for u in base:
		base_sides.append(u.is_ally)
	var det := true
	for i in 5:
		mgr.call("_build_order")
		for k in base.size():
			if mgr.order[k] != base[k]:
				det = false
	_check("sin sorteo el orden sigue siendo el de velocidad (determinista)", det)
	mgr.randomize_ally_order = true
	var seen := {}
	var rules_ok := true
	var sides_ok := true
	for i in 300:
		mgr.call("_build_order")
		var names: Array = []
		var ally_count := 0
		for k in mgr.order.size():
			var u = mgr.order[k]
			if u.is_ally:
				ally_count += 1
				names.append(u.source_key)
			if bool(u.is_ally) != bool(base_sides[k]):
				sides_ok = false
		if ally_count != 4 or names.size() != 4:
			rules_ok = false
		var unique := {}
		for n in names:
			unique[n] = true
		if unique.size() != 4:
			rules_ok = false
		seen[",".join(names)] = true
	_check("el orden de tu equipo CAMBIA entre rondas (%d ordenes distintos en 300)" % seen.size(), seen.size() >= 12)
	_check("cada aliado vivo actua exactamente una vez por ronda", rules_ok)
	_check("la velocidad sigue repartiendo los turnos entre bandos (mismas posiciones de aliados/enemigos)", sides_ok)
	# Un aliado caido no entra en el orden.
	var fallen = mgr.allies[0]
	fallen.take_damage(999999.0)
	mgr.call("_build_order")
	var in_order := false
	for u in mgr.order:
		if u == fallen:
			in_order = true
	_check("un aliado caido no actua", not in_order and mgr.order.size() == 5)
	mgr.queue_free()


## --- 4. Jefes con personajes de anime ---------------------------------------------------
func _check_enemies() -> void:
	_out("[DBG23] == JEFES Y ENEMIGOS: PERSONAJES DE ANIME ==")
	var expected := {
		"vigia_alfa": ["itadori", 4200], "vigia_beta": ["reze", 3400], "void_warden": ["makima", 5200],
		"torre_guardian": ["asta", 3200], "torre_verdugo": ["denji", 4200], "torre_avatar": ["goku", 5600],
	}
	var bases := {}
	var all_ok := true
	for enemy_id in expected.keys():
		var e := DB.get_enemy(String(enemy_id))
		var base_id := String(expected[enemy_id][0])
		var base := DB.get_character(base_id)
		var ok := not e.is_empty() and String(e.get("id", "")) == String(enemy_id) \
			and String(e.get("name", "")) == String(base.get("name", "?")) \
			and int((e["stats"] as Dictionary)["max_hp"]) == int(expected[enemy_id][1])
		var art: Dictionary = e.get("art", {})
		var has_art := String(art.get("front", "")) != "" and ResourceLoader.exists(String(art["front"]))
		_check("%s ahora es %s (id y estadisticas originales, con sprite propio)" % [enemy_id, base_id], ok and has_art)
		if not (ok and has_art):
			all_ok = false
		bases[base_id] = true
	_check("cada enemigo usa un personaje DISTINTO (sin duplicados)", bases.size() == expected.size())
	var generic := false
	for e in DB.enemies.values():
		var n := String((e as Dictionary).get("name", ""))
		if n.begins_with("Vigia") or n.begins_with("Guardian de la") or n.begins_with("Verdugo de") or n.begins_with("Avatar de"):
			generic = true
	_check("ya no queda ningun enemigo generico (Vigia/Guardian/Verdugo/Avatar)", not generic)
	# Todos los stages/torre/mundos siguen resolviendo sus enemigos.
	var missing: Array = []
	for world in DB.all_worlds():
		for level in DB.story_levels(String((world as Dictionary).get("id", ""))):
			for id in (level as Dictionary).get("enemies", []):
				if DB.get_enemy(String(id)).is_empty():
					missing.append(id)
	_check("todos los enemigos de la historia siguen existiendo (faltan: %s)" % str(missing), missing.is_empty())


## --- 2. Interfaz de combate despejada ----------------------------------------------------
func _check_battle_ui() -> void:
	_out("[DBG23] == INTERFAZ DE COMBATE DESPEJADA ==")
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.normalize_party()
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	_app.call("open_battle")
	await _wait(0.9)
	var battle = _app.get("_battle")
	_check("el combate se abre", battle != null)
	if battle == null:
		return
	var order_panel: Control = battle.get("order_panel")
	var log_panel: Control = battle.get("log_panel")
	var active_bar: Control = battle.get("active_bar")
	_check("por defecto NO se ve el orden de ataque, ni el registro, ni la barra grande", not order_panel.visible and not log_panel.visible and not active_bar.visible)
	var waiting := false
	var waited := 0.0
	while waited < 15.0 and not waiting:
		waiting = bool(battle.get("awaiting_input"))
		await _wait(0.1)
		waited += 0.1
	var attack: Button = battle.get("attack_button")
	_check("los controles de combate siguen visibles y usables", waiting and attack.is_visible_in_tree() and not attack.disabled)
	var hint: Label = battle.get("action_hint")
	_check("la linea de turno dice quien actua y su SP (%s)" % hint.text, hint.text.contains("SP") and hint.text.contains("/"))
	var ally_cards := 0
	var minimal_ok := true
	for card in battle.get("cards").values():
		ally_cards += 1
		if not bool(card.get("minimal")) or (card.get_node("VBox/Top/Info") as Control).visible:
			minimal_ok = false
	_check("todas las tarjetas (%d) estan en modo minimo: sprite y barra de vida" % ally_cards, ally_cards >= 5 and minimal_ok)
	var info_btn: Button = battle.get("info_button")
	_check("existe el boton INFO", info_btn != null)
	info_btn.pressed.emit()
	await _wait(0.2)
	_check("INFO muestra el orden de ataque y el registro", order_panel.visible and log_panel.visible)
	info_btn.pressed.emit()
	await _wait(0.2)
	_check("INFO otra vez los oculta", not order_panel.visible and not log_panel.visible)
	# Tocar una tarjeta abre la ficha con los datos (consulta bajo demanda).
	var first_key: String = String(battle.get("cards").keys()[0])
	var first_card = battle.get("cards")[first_key]
	battle.call("_on_card_pressed", first_card.unit)
	await _wait(0.3)
	var info_panel: Node = battle.get("info_panel")
	_check("tocar una tarjeta abre su ficha con la informacion", info_panel.is_open())
	info_panel.close_panel()
	_app.call("close_battle")
	await _wait(0.3)


## --- 7 y 8. Evolucion y Mutaciones: buscador y filtros --------------------------------------
func _check_pick_screens() -> void:
	_out("[DBG23] == EVOLUCION Y MUTACIONES: BUSCADOR Y FILTROS ==")
	for id in ["gojo", "goku", "makima", "frieren"]:
		if not GameState.roster.has(id):
			GameState.roster.append(id)
			GameState.progress[id] = { "level": 1, "xp": 0 }
	GameState.rarities.erase("gojo")
	GameState.progress["gojo"] = { "level": 100, "xp": 0 }
	GameState.coins = 10000000
	var evo: Node = load("res://scenes/screens/evolution.tscn").instantiate()
	add_child(evo)
	await _wait(0.3)
	evo.call("refresh")
	await _wait(0.2)
	var tb = evo.get("toolbar")
	_check("Evolucion tiene buscador y filtros", tb != null and tb.find_child("SearchBox", true, false) != null and tb.find_child("Filter_ready", true, false) != null)
	var all_ids: Array = evo.call("visible_ids")
	var eligible: Array = evo.call("eligible_ids")
	_check("sin filtro se ven todos los evolucionables (%d)" % eligible.size(), all_ids.size() == eligible.size() and eligible.size() > 0)
	tb.select_filter("ready")
	var ready_ids: Array = evo.call("visible_ids")
	var all_ready := true
	for id in ready_ids:
		if not bool(GameState.can_evolve(String(id)).get("ok", false)) and not bool(GameState.can_special_evolve(String(id)).get("ok", false)):
			all_ready = false
	_check("filtro LISTOS: solo los que cumplen los requisitos (%d)" % ready_ids.size(), all_ready and ready_ids.has("gojo"))
	tb.select_filter("missing")
	var missing_ids: Array = evo.call("visible_ids")
	_check("filtro FALTAN: complementa a LISTOS (%d + %d = %d)" % [ready_ids.size(), missing_ids.size(), eligible.size()], ready_ids.size() + missing_ids.size() == eligible.size())
	tb.select_filter("all")
	tb.set_query("GOJO")
	var found: Array = evo.call("visible_ids")
	_check("la busqueda encuentra por nombre sin importar mayusculas", found == ["gojo"])
	tb.set_query("zzzz")
	_check("busqueda sin resultados: lista vacia sin error", (evo.call("visible_ids") as Array).is_empty())
	tb.set_query("")
	var sorted_ids: Array = evo.call("visible_ids")
	var ready_first := true
	var seen_missing := false
	for id in sorted_ids:
		var ok := bool(GameState.can_evolve(String(id)).get("ok", false)) or bool(GameState.can_special_evolve(String(id)).get("ok", false))
		if not ok:
			seen_missing = true
		elif seen_missing:
			ready_first = false
	_check("la lista pone primero a los que ya pueden evolucionar", ready_first)
	evo.queue_free()
	var mut: Node = load("res://scenes/screens/mutations.tscn").instantiate()
	add_child(mut)
	await _wait(0.3)
	mut.call("refresh")
	await _wait(0.2)
	var mtb = mut.get("toolbar")
	_check("Mutaciones tiene buscador y filtros", mtb != null and mtb.find_child("SearchBox", true, false) != null and mtb.find_child("Filter_none", true, false) != null)
	var m_all: Array = mut.call("visible_ids")
	_check("sin filtro se ven todos los personajes (%d)" % GameState.roster.size(), m_all.size() == GameState.roster.size())
	GameState.mutations.erase("gojo")
	mtb.select_filter("none")
	var none_ids: Array = mut.call("visible_ids")
	_check("filtro SIN MUTACION incluye a quien no la tiene", none_ids.has("gojo"))
	mtb.set_query("frier")
	_check("la busqueda parcial encuentra a Frieren", (mut.call("visible_ids") as Array).has("frieren"))
	mtb.set_query("")
	mtb.select_filter("all")
	mut.queue_free()
	await _wait(0.1)
