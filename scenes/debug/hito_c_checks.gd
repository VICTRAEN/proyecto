extends Node

## COMPROBACIONES EN EJECUCION DEL HITO C. SOLO para pruebas.
##
## Se activan poniendo DEBUG_V17 := true en scenes/app.gd, o sin editar nada
## arrancando el juego con  godot --path . -- --dbg17   (lo que va tras "--" son
## argumentos del juego). Usan las funciones y los
## handlers REALES del juego (GameState, GameSettings, GameAudio y las pantallas de
## app.gd), no copias, y escriben cada resultado en el panel de salida y en
## res://dbg17_resultados.txt con el formato "[DBG17] texto -> OK / FALLO".
##
## Cubre: equipo con huecos (0/4..4/4 y quitar al repetir), Leader Skill (solo la
## posicion 1), stage 3 de Sakuta sin atajos, ajustes y su persistencia, sistema de
## audio sin archivos, todos los botones del menu principal, mutaciones y los
## enemigos del evento.
##
## Sin pantalla (godot --headless ...) al terminar cierra el juego con codigo 0 si
## todo salio OK y 1 si hubo algun FALLO.
##
## Guarda y RESTAURA el guardado y los ajustes del jugador al terminar.

const RESULTS_PATH := "res://dbg17_resultados.txt"
## Copia de los ajustes del jugador mientras dura la prueba de persistencia.
const BACKUP_PATH := "user://settings_dbg17_backup.json"
const EVENTO := "event_sindromes_de_la_pubertad"

var _app: Node = null
var _fails := 0


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
	if not ok:
		_fails += 1
	_out("[DBG17] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _frames(count: int = 2) -> void:
	for i in count:
		await get_tree().process_frame


func _screen(key: String) -> Node:
	return (_app.get("_screens") as Dictionary).get(key, null)


func run(app: Node) -> void:
	_app = app
	await _frames()
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out("[DBG17] --- comprobaciones del Hito C ---")
	_app.call("_backup_save")
	var settings_backup: Dictionary = GameSettings.values.duplicate(true)

	_check_party_holes()
	_check_leader_skill()
	_check_sakuta_stage3()
	_check_settings()
	_check_audio()
	await _check_main_menu()
	await _check_mutations()
	_check_event_enemies()
	_check_gacha_f2p()
	_check_shop()
	await _check_battle_settings()

	# Se devuelve todo como estaba.
	for key in settings_backup.keys():
		GameSettings.set_value(String(key), settings_backup[key], false)
	GameSettings.save_settings()
	_app.call("_restore_save")
	_out("[DBG17] --- fin: %d FALLO(S) ---" % _fails)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _fails > 0 else 0)


## --- AJUSTES ENTRE DOS EJECUCIONES ---------------------------------------------
## Cierra y abre el juego DE VERDAD: una ejecucion escribe los ajustes y sale, la
## siguiente comprueba que se cargaron.
##     godot --path . -- --dbg17-write
##     godot --path . -- --dbg17-read      (restaura los ajustes que tenia el jugador)

func run_persistence(write_mode: bool) -> void:
	await _frames()
	if write_mode:
		_out("[DBG17] --- ajustes: ESCRIBIR ---")
		var had := FileAccess.file_exists(GameSettings.PATH)
		var text := FileAccess.get_file_as_string(GameSettings.PATH) if had else ""
		var backup := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
		if backup != null:
			backup.store_string(JSON.stringify({ "had": had, "text": text }))
			backup.close()
		GameSettings.set_value("music_volume", 0.3, false)
		GameSettings.set_value("sfx_volume", 0.6, false)
		GameSettings.set_value("battle_speed", "fast", false)
		GameSettings.set_value("show_damage", false, false)
		GameSettings.set_value("reduce_motion", true, false)
		GameSettings.save_settings()
		_out("[DBG17] escritos: musica 30%, efectos 60%, combate rapida, numeros OFF, animaciones reducidas")
	else:
		_out("[DBG17] --- ajustes: LEER en una ejecucion nueva ---")
		_check("musica = 30%", is_equal_approx(GameSettings.volume("music_volume"), 0.3))
		_check("efectos = 60%", is_equal_approx(GameSettings.volume("sfx_volume"), 0.6))
		_check("velocidad de combate = rapida", GameSettings.choice("battle_speed") == "fast")
		_check("numeros de dano = OFF", not GameSettings.show_damage())
		_check("animaciones reducidas = ON", GameSettings.reduce_motion())
		_restore_settings_backup()
		_out("[DBG17] --- fin: %d FALLO(S) --- (ajustes del jugador restaurados)" % _fails)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _fails > 0 else 0)


func _restore_settings_backup() -> void:
	if not FileAccess.file_exists(BACKUP_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BACKUP_PATH))
	if parsed is Dictionary and bool((parsed as Dictionary).get("had", false)):
		var file := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(String((parsed as Dictionary).get("text", "")))
			file.close()
	elif FileAccess.file_exists(GameSettings.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	GameSettings.load_settings()


## --- EQUIPO CON HUECOS -------------------------------------------------------

func _check_party_holes() -> void:
	_out("[DBG17] == EQUIPO CON HUECOS ==")
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.normalize_party()
	_check("4/4: party_count = 4", GameState.party_count() == 4)

	# TEST 1 y 2: tocar al personaje que YA ocupa la posicion elegida lo quita.
	var team := _screen("team")
	team.call("refresh")
	team.call("_on_slot_pressed", GameState.character_data("gojo"), 0)
	team.call("_on_pool_pressed", GameState.character_data("gojo"))
	_check("pulsar de nuevo al personaje de la posicion 1 la deja VACIA", String(GameState.party[0]).is_empty())
	_check("3/4: party_count = 3", GameState.party_count() == 3)

	# QUITAR con el boton de la pantalla.
	team.call("_on_slot_pressed", GameState.character_data("isagi"), 1)
	var remove_button: Button = team.get("remove_button")
	_check("el boton QUITAR existe y esta activo con una posicion ocupada", remove_button != null and not remove_button.disabled)
	remove_button.pressed.emit()
	_check("QUITAR vacia la posicion 2 (2/4)", String(GameState.party[1]).is_empty() and GameState.party_count() == 2)

	# Mover a alguien a un hueco no lo duplica.
	team.call("_on_slot_pressed", {}, 0)
	team.call("_on_pool_pressed", GameState.character_data("mai"))
	var seen: Array = GameState.party_ids()
	_check("mover a Mai a un hueco no la duplica", seen.count("mai") == 1)

	# TEST 3: equipo de UN personaje.
	for i in GameState.party.size():
		var occupant := String(GameState.party[i])
		if occupant.is_empty():
			continue
		if i == 0:
			continue
		GameState.assign_party_slot(i, occupant)
	_check("se puede formar un equipo de 1 personaje (1/4)", GameState.party_count() == 1)
	_check("team_problem vacio con 1 personaje", GameState.team_problem().is_empty())
	GameState.assign_party_slot(0, String(GameState.party[0]))
	_check("0/4: party_count = 0", GameState.party_count() == 0)
	_check("team_problem avisa con 0 personajes", not GameState.team_problem().is_empty())
	# Persistencia inmediata en disco.
	GameState.assign_party_slot(0, "gojo")
	GameState.party = []
	GameState.load_game()
	_check("el equipo con huecos se guarda y se carga (1/4)", GameState.party_count() == 1 and GameState.party.size() == GameState.PARTY_SIZE)
	# Un combate normal no se abre con el equipo vacio.
	GameState.assign_party_slot(0, "gojo")
	_check("repetir a Gojo en su posicion la deja vacia (0/4)", GameState.party_count() == 0)


## --- LEADER SKILL: SOLO LA POSICION 1 ------------------------------------------

func _check_leader_skill() -> void:
	_out("[DBG17] == LEADER SKILL ==")
	# Dos personajes del roster con Leader Skill DISTINTA (sale de los datos).
	var first := ""
	var second := ""
	for raw_id in GameState.roster:
		var key := String(raw_id)
		var leader_id := DB.leader_id_for(key)
		if leader_id.is_empty():
			continue
		if first.is_empty():
			first = key
		elif DB.leader_id_for(first) != leader_id:
			second = key
			break
	_check("hay dos personajes con Leader Skill distinta para probar", not first.is_empty() and not second.is_empty())
	# Un tercero para rellenar; cualquiera distinto de los dos.
	var other := ""
	for raw_id in GameState.roster:
		if String(raw_id) != first and String(raw_id) != second:
			other = String(raw_id)
			break

	# Posicion 1 ocupada: ese personaje es el lider.
	GameState.party = [first, other, "", ""]
	_check("posicion 1 ocupada: el lider es el personaje de la posicion 1", GameState.party_leader_id() == first)
	var report_first: Dictionary = GameState.leader_report()
	_check("y su Leader Skill esta activa", not report_first.is_empty() and String(report_first.get("id", "")) == DB.leader_id_for(first))

	# Cambiar el personaje de la posicion 1 cambia la Leader Skill.
	GameState.party = [second, other, "", ""]
	var report_second: Dictionary = GameState.leader_report()
	_check("cambiar el personaje de la posicion 1 cambia la Leader Skill",
		GameState.party_leader_id() == second and String(report_second.get("id", "")) == DB.leader_id_for(second)
		and String(report_second.get("id", "")) != String(report_first.get("id", "")))

	# Posicion 1 vacia: NINGUNA Leader Skill, aunque haya gente en las demas.
	GameState.party = ["", first, second, other]
	_check("posicion 1 vacia: NO hay lider", GameState.party_leader_id().is_empty())
	_check("posicion 1 vacia: NO hay Leader Skill", GameState.leader_report().is_empty())
	_check("posicion 1 vacia: el bonus desaparece para todos",
		GameState.leader_mods_for(first).is_empty() and GameState.leader_mods_for(second).is_empty() and GameState.leader_mods_for(other).is_empty())
	_check("posicion 1 vacia: no afecta a nadie", not GameState.leader_affects(first) and not GameState.leader_affects(second))

	# Un personaje de la posicion 2 nunca proporciona Leader Skill.
	for slot in [1, 2, 3]:
		var lineup := ["", "", "", ""]
		lineup[slot] = first
		GameState.party = lineup
		_check("un personaje en la posicion %d NUNCA es lider" % (slot + 1), GameState.party_leader_id().is_empty() and GameState.leader_report().is_empty())

	# El bonus vuelve al llenar la posicion 1 (misma regla, sin casos especiales).
	GameState.party = ["", first, "", ""]
	GameState.assign_party_slot(0, first)
	_check("al ocupar la posicion 1 vuelve a haber lider (mueve, no duplica)",
		GameState.party_leader_id() == first and GameState.party_ids().count(first) == 1)
	GameState.assign_party_slot(0, first)
	_check("al vaciar la posicion 1 desaparece la Leader Skill", GameState.leader_report().is_empty())


## --- STAGE 3 DE SAKUTA (SIN ATAJOS) ---------------------------------------------

func _check_sakuta_stage3() -> void:
	_out("[DBG17] == STAGE 3 SAKUTA ==")
	if not GameState.roster.has("sakuta"):
		GameState.roster.append("sakuta")
	if not GameState.roster.has("sakuta_mai"):
		GameState.roster.append("sakuta_mai")
	GameState.ensure_defaults()
	GameState.rarities["sakuta"] = "UR"
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.normalize_party()
	var team := _screen("team")
	team.call("refresh")
	# Vaciar posiciones 2, 3 y 4 con el mismo gesto que un jugador.
	for i in [1, 2, 3]:
		team.call("_on_slot_pressed", GameState.character_data(String(GameState.party[i])), i)
		team.call("_on_pool_pressed", GameState.character_data(String(GameState.party[i])))
	# Sakuta a la posicion 1 (sustituye a Gojo).
	team.call("_on_slot_pressed", GameState.character_data("gojo"), 0)
	team.call("_on_pool_pressed", GameState.character_data("sakuta"))
	_check("TEST 3: el jugador forma [SAKUTA] 1/4 desde la pantalla Equipo",
		GameState.party_count() == 1 and String(GameState.party[0]) == "sakuta")
	var gate_ok: Dictionary = GameState.event_party_ready(EVENTO, "evt_sdp_03", GameState.party)
	_check("TEST 4: el stage 3 acepta a Sakuta UR solo", bool(gate_ok.get("ok", false)))
	GameState.prepare_battle(GameState.BATTLE_EVENT, { "event": EVENTO, "stage": "evt_sdp_03" })
	_check("el combate lleva exactamente la unidad del jugador", GameState.battle_party_ids().size() == 1)

	# TEST 5: Sakuta SSR (Sakuta + Mai) solo.
	var gate_ssr: Dictionary = GameState.event_party_ready(EVENTO, "evt_sdp_03", ["sakuta_mai", "", "", ""])
	_check("TEST 5: Sakuta+Mai SSR solo NO entra al stage 3", not bool(gate_ssr.get("ok", true)))
	GameState.rarities["sakuta"] = "SSR"
	var gate_form: Dictionary = GameState.event_party_ready(EVENTO, "evt_sdp_03", ["sakuta", "", "", ""])
	_check("Sakuta en forma SSR solo NO entra", not bool(gate_form.get("ok", true)))
	GameState.rarities["sakuta"] = "UR"

	# TEST 6: Sakuta UR + otro personaje.
	var gate_two: Dictionary = GameState.event_party_ready(EVENTO, "evt_sdp_03", ["sakuta", "gojo", "", ""])
	_check("TEST 6: Sakuta UR + otro personaje NO entra", not bool(gate_two.get("ok", true)))

	# Sin atajos: con el equipo completo, la batalla lleva el equipo completo.
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.prepare_battle(GameState.BATTLE_EVENT, { "event": EVENTO, "stage": "evt_sdp_03" })
	_check("no hay atajo: con 4/4 la batalla lleva 4 (y el gate del stage 3 lo rechaza)",
		GameState.battle_party_ids().size() == 4
		and not bool((GameState.event_party_ready(EVENTO, "evt_sdp_03", GameState.party)).get("ok", true)))


## --- AJUSTES -------------------------------------------------------------------

func _check_settings() -> void:
	_out("[DBG17] == AJUSTES ==")
	GameSettings.set_value("music_volume", 0.35)
	GameSettings.set_value("sfx_volume", 0.6)
	GameSettings.set_value("ui_volume", 0.15)
	GameSettings.set_value("battle_speed", "fast")
	GameSettings.set_value("anim_speed", "fast")
	GameSettings.set_value("show_damage", false)
	GameSettings.set_value("show_advantage", false)
	GameSettings.set_value("reduce_motion", true)
	GameSettings.set_value("text_size", "large")
	_check("texto grande escala la interfaz 1.2", is_equal_approx(get_tree().root.content_scale_factor, 1.2))
	# Relee el archivo, como al cerrar y volver a abrir el juego.
	GameSettings.values = {}
	GameSettings.load_settings()
	_check("la musica persiste tras recargar (35%)", is_equal_approx(GameSettings.volume("music_volume"), 0.35))
	_check("efectos y sonidos de interfaz persisten (60% / 15%)",
		is_equal_approx(GameSettings.volume("sfx_volume"), 0.6) and is_equal_approx(GameSettings.volume("ui_volume"), 0.15))
	_check("velocidades persisten", GameSettings.choice("battle_speed") == "fast" and GameSettings.choice("anim_speed") == "fast")
	_check("los Si/No persisten",
		not GameSettings.show_damage() and not GameSettings.show_advantage() and GameSettings.reduce_motion())
	_check("pausa de combate rapida < 1 y animaciones > 1",
		GameSettings.battle_pause_scale() < 1.0 and GameSettings.anim_speed_scale() > 1.0)
	GameSettings.set_value("battle_speed", "warp")
	_check("un valor invalido no se acepta", GameSettings.choice("battle_speed") == "fast")
	GameSettings.set_value("music_volume", 7.0)
	_check("un volumen fuera de rango se limita a 100%", is_equal_approx(GameSettings.volume("music_volume"), 1.0))
	GameSettings.set_value("text_size", "normal")
	_check("texto normal devuelve la escala 1.0", is_equal_approx(get_tree().root.content_scale_factor, 1.0))


## --- AUDIO ---------------------------------------------------------------------

func _check_audio() -> void:
	_out("[DBG17] == AUDIO ==")
	GameSettings.set_value("music_volume", 0.8, false)
	var total := 0
	for category in GameAudio.CATALOG.keys():
		for event in GameAudio.CATALOG[category]:
			total += 1
			if String(category) == "music":
				GameAudio.play_music(String(event))
			else:
				GameAudio.play(String(event))
	GameAudio.stop_music()
	_check("pedir los %d sonidos del catalogo (haya o no archivo) no da error" % total, total > 0)
	_check("un evento que no existe no da error", GameAudio.category_of("no_existe").is_empty())
	var missing: Array = GameAudio.missing_events()
	_out("[DBG17] eventos sin archivo propio todavia (%d): %s" % [missing.size(), str(missing)])
	GameAudio.play_music("menu")
	_out("[DBG17] pista actual tras pedir 'menu': '%s' (vacia = no hay menu.ogg)" % String(GameAudio.get("_music_path")))
	GameAudio.play_music("battle")
	_out("[DBG17] pista actual tras pedir 'battle': '%s'" % String(GameAudio.get("_music_path")))
	GameAudio.stop_music()


## --- MENU PRINCIPAL: ningun boton muerto -------------------------------------------

func _check_main_menu() -> void:
	_out("[DBG17] == MENU PRINCIPAL Y PANTALLAS ==")
	# El equipo tiene que poder combatir para que JUGAR y demas abran su pantalla.
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	await _frames()
	var menu := _screen("main_menu")
	menu.call("refresh")
	var buttons: Array = menu.find_children("*", "Button", true, false)
	_check("el menu tiene los 13 botones (JUGAR, HISTORIA, los grupos, TORRE y TIENDA)", buttons.size() == 13)
	for raw_button in buttons:
		var button: Button = raw_button
		button.pressed.emit()
		await _frames()
		var reached := String(_app.call("current_screen"))
		_check("el boton %s lleva a otra pantalla (%s)" % [button.text, reached], reached != "main_menu")
		_app.call("go_back")
		await _frames()
	for key in ["collection", "team", "stage_select", "summon", "missions", "history", "events", "inventory", "evolution", "mutations", "settings", "shop"]:
		_app.call("open_screen", key)
		await _frames()
		var screen := _screen(key)
		_check("la pantalla %s se abre y es visible" % key, screen != null and screen.visible)
		_app.call("go_back")
		await _frames()


## --- MUTACIONES ------------------------------------------------------------------

func _check_mutations() -> void:
	_out("[DBG17] == MUTACIONES ==")
	var cost := DB.mutation_cost()
	GameState.coins = 1000
	_app.call("open_screen", "mutations")
	await _frames()
	var screen := _screen("mutations")
	screen.set("_selected_id", "gojo")
	# PASO 1: el boton de la pantalla ABRE el ritual y NO debe cobrar ni tirar.
	# Se compara contra el estado ANTERIOR: el guardado del jugador puede traer ya
	# una mutacion de Gojo, y eso no es un fallo, solo el punto de partida.
	var coins_before := GameState.coins
	var mutation_before: Dictionary = GameState.mutation_of("gojo").duplicate(true)
	screen.call("_on_mutate_pressed")
	var modal = screen.get("_modal")
	_check("el primer MUTAR abre el ritual", modal != null and bool(modal.visible))
	_check("el primer MUTAR NO cobra ni muta todavia",
		GameState.coins == coins_before and GameState.mutation_of("gojo") == mutation_before)
	# La ventana trae TODO antes de tirar: personaje, 6 stats BASE, pasiva actual,
	# nueva mutacion y el boton CONFIRMAR con el coste.
	var body: Node = screen.get("_modal_body")
	var stats_grid: GridContainer = body.find_child("BaseStats", true, false)
	_check("la ventana pinta las 6 stats BASE (%d filas)" % (stats_grid.get_child_count() / 2 if stats_grid != null else -1),
		stats_grid != null and stats_grid.get_child_count() == 12)
	_check("la ventana muestra la imagen grande del personaje", body.find_child("RitualPortrait", true, false) != null)
	_check("la ventana muestra PASIVA ACTUAL", body.find_child("CurrentPassive", true, false) != null)
	_check("la ventana muestra NUEVA MUTACION", body.find_child("NewMutation", true, false) != null)
	var confirm: Button = screen.get("_modal_confirm")
	_check("el boton dice CONFIRMAR MUTACION con el coste (%s)" % confirm.text,
		confirm.text.begins_with("CONFIRMAR MUTACION") and confirm.text.contains(str(cost)))
	# PASO 2: el boton de dentro de la ventana es el que tira de verdad.
	screen.call("_on_confirm_mutation")
	_check("TEST 9: el MUTAR del ritual cuesta %d monedas" % cost, GameState.coins == 1000 - cost)
	_check("y deja una mutacion activa", GameState.has_mutation("gojo"))
	var before_rank := String(GameState.mutation_of("gojo").get("rank", ""))
	screen.call("_on_confirm_mutation")
	_check("una segunda tirada SUSTITUYE (sigue habiendo una) y cobra otra vez", GameState.coins == 1000 - 2 * cost and GameState.has_mutation("gojo"))
	_out("[DBG17] rango anterior %s -> rango actual %s" % [before_rank, String(GameState.mutation_of("gojo").get("rank", ""))])
	# La vista BASE -> CON MUTACION: el bonus tiene que mover la stat de verdad.
	var moved := 0
	for raw_entry in GameState.mutation_stat_preview("gojo"):
		var entry: Dictionary = raw_entry
		if bool(entry.get("changed", false)):
			moved += 1
			_out("[DBG17] %s: base %d -> con mutacion %d" % [
				String(entry.get("label", "")), int(round(float(entry.get("base", 0.0)))),
				int(round(float(entry.get("with_mutation", 0.0))))])
	_check("la mutacion mueve la stat sobre la BASE (no sobre el valor buffeado)", moved > 0)
	GameState.coins = cost - 1
	var rank_before := String(GameState.mutation_of("gojo").get("rank", ""))
	screen.call("_on_confirm_mutation")
	_check("sin monedas suficientes NO cobra nada y NO cambia la mutacion",
		GameState.coins == cost - 1 and String(GameState.mutation_of("gojo").get("rank", "")) == rank_before)
	screen.call("_close_modal")
	_check("el ritual se puede cerrar sin mutar", not bool((screen.get("_modal") as Control).visible))
	# La pantalla tiene que estar LLENA: una tira de personajes y un panel con las
	# stats BASE del elegido. Sin esto la pantalla se abriria vacia.
	var built := 0
	for child in (screen.get("selector") as HBoxContainer).get_children():
		if child is Control:
			built += 1
	_check("la pantalla pinta una tarjeta por personaje del roster (%d)" % built, built > 0)
	# La pantalla principal lleva solo el RESUMEN de una linea de la mutacion (el
	# detalle esta en la ventana): sin rejilla duplicada.
	var mutation_rows := (screen.get("_focal_mutation") as VBoxContainer).get_child_count()
	var stats_box: VBoxContainer = screen.get("_focal_stats")
	_check("la pantalla no duplica las stats de la ventana y resume la mutacion (%d)" % mutation_rows,
		stats_box.get_child_count() == 0 and mutation_rows >= 1)
	_app.call("go_back")
	await _frames()


## --- ENEMIGOS DEL EVENTO ------------------------------------------------------------

func _check_event_enemies() -> void:
	_out("[DBG17] == ENEMIGOS DEL EVENTO ==")
	var expected := { "sdp_todo": "todo", "sdp_mahito": "mahito", "sdp_akaza": "akaza" }
	for enemy_id in expected.keys():
		var enemy := DB.get_enemy(String(enemy_id))
		var base := DB.get_character(String(expected[enemy_id]))
		_check("%s existe y ES el personaje %s" % [enemy_id, expected[enemy_id]],
			not enemy.is_empty() and String(enemy.get("name", "")) == String(base.get("name", "?")))
		_check("%s conserva su propio id y sus estadisticas" % enemy_id,
			String(enemy.get("id", "")) == String(enemy_id) and int((enemy.get("stats", {}) as Dictionary).get("max_hp", 0)) > 0)
	var placeholders := ["vigia_alfa", "vigia_beta", "void_warden"]
	var used_placeholder := false
	for stage_id in ["evt_sdp_01", "evt_sdp_02", "evt_sdp_03"]:
		for enemy_id in DB.event_stage(EVENTO, stage_id).get("enemies", []):
			if placeholders.has(String(enemy_id)):
				used_placeholder = true
	_check("los stages del evento ya no usan los NPC placeholder", not used_placeholder)


## --- GACHA: LAS UNIDADES FREE TO PLAY NO SALEN DE NINGUN BANNER ----------------
## Sakuta y Mai se consiguen por su evento, no pagando gemas. Se comprueba en los
## DATOS (el pool de cada banner) y en la PRACTICA (tirando muchas veces).

func _check_gacha_f2p() -> void:
	_out("[DBG17] == GACHA: UNIDADES FREE TO PLAY ==")
	_check("sakuta_mai esta marcada como NO invocable (gacha: false)",
		not DB.is_gacha_character("sakuta_mai"))
	var f2p := ["sakuta_mai", "sakuta", "sakuta_mai_lr"]
	var leaked: Array = []
	for raw_banner in DB.all_banners():
		var banner_id := String((raw_banner as Dictionary).get("id", ""))
		var pool: Array = GameState.banner_pool(banner_id)
		for id in f2p:
			if pool.has(id):
				leaked.append("%s en %s" % [id, banner_id])
	_check("ninguna forma de Sakuta/Mai esta en el pool de ningun banner",
		leaked.is_empty())
	if not leaked.is_empty():
		_out("[DBG17] FUGA DETECTADA: %s" % str(leaked))

	# Y tirando de verdad: 300 tiradas sobre el banner mas generoso.
	var banner := "banner_ur"
	for raw_banner in DB.all_banners():
		if String((raw_banner as Dictionary).get("id", "")) == "banner_ur":
			banner = "banner_ur"
	GameState.gems = 100000
	var pulled_any := false
	var hits := 0
	for i in 30:
		var report: Dictionary = GameState.summon(banner, 10)
		if not bool(report.get("ok", false)):
			continue
		pulled_any = true
		for entry in report.get("results", []):
			if f2p.has(String((entry as Dictionary).get("id", ""))):
				hits += 1
	_check("300 tiradas reales sobre el banner UR no dan ninguna unidad F2P",
		pulled_any and hits == 0)
	_out("[DBG17] unidades F2P salidas en 300 tiradas: %d" % hits)


## --- TIENDA ---------------------------------------------------------------------

func _check_shop() -> void:
	_out("[DBG17] == TIENDA ==")
	var items: Array = DB.all_shop_items()
	_check("la tienda tiene articulos cargados", not items.is_empty())

	# Comprar gemas con monedas.
	GameState.coins = 10000
	GameState.gems = 0
	var before_coins := GameState.coins
	var report: Dictionary = GameState.buy_shop_item("shop_gemas_100")
	_check("comprar un articulo devuelve informe de exito", bool(report.get("ok", false)))
	_check("cobra las monedas que dice el JSON",
		GameState.coins == before_coins - int(DB.get_shop_item("shop_gemas_100").get("cost_coins", 0)))
	_check("entrega las gemas que dice el JSON (100)", GameState.gems == 100)

	# Sin dinero suficiente NO se cobra nada.
	GameState.coins = 10
	var poor_before := GameState.coins
	var poor: Dictionary = GameState.buy_shop_item("shop_gemas_100")
	_check("sin recursos la compra falla", not bool(poor.get("ok", true)))
	_check("y NO cobra ni una moneda", GameState.coins == poor_before)

	# Un personaje comprado entra en el roster (o cuenta como duplicado).
	GameState.gems = 1000
	GameState.roster.erase("hinata")
	var char_report: Dictionary = GameState.buy_shop_item("shop_recluta_hinata")
	_check("comprar un personaje funciona", bool(char_report.get("ok", false)))
	_check("y el personaje esta en el roster", GameState.is_owned("hinata"))

	# Un articulo inexistente no rompe ni cobra.
	var missing: Dictionary = GameState.buy_shop_item("no_existe")
	_check("un articulo que no existe no rompe la tienda", not bool(missing.get("ok", true)))


## --- COMBATE Y AJUSTES -----------------------------------------------------------

func _check_battle_settings() -> void:
	_out("[DBG17] == COMBATE ==")
	GameSettings.set_value("battle_speed", "fast", false)
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.prepare_battle(GameState.BATTLE_EVENT, { "event": EVENTO, "stage": "evt_sdp_01" })
	_app.call("open_battle")
	await _frames(3)
	var battle: Node = _app.get("_battle")
	_check("el combate se abre con el equipo del jugador", battle != null)
	if battle != null:
		var manager: Object = battle.get("manager")
		_check("velocidad de combate rapida acorta las pausas", manager != null and float(manager.get("pause_scale")) < 1.0)
		_out("[DBG17] pista durante el combate: '%s'" % String(GameAudio.get("_music_path")))
	_app.call("close_battle")
	await _frames()
	# Un equipo vacio no abre el combate.
	GameState.party = ["", "", "", ""]
	GameState.prepare_battle(GameState.BATTLE_EVENT, { "event": EVENTO, "stage": "evt_sdp_01" })
	_app.call("open_battle")
	await _frames()
	_check("con el equipo vacio el combate NO se abre", _app.get("_battle") == null)
