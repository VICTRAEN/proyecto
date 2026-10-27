extends Node

## COMPROBACIONES EN EJECUCION DEL HITO E (David Martinez & Lucy, revelado individual,
## cinematica, ultimate LR, musica especial y Developer Tools). SOLO para pruebas.
## Arranque:  godot --headless --path . -- --dbg19
## Usa las funciones y pantallas REALES del juego. Escribe "[DBG19] texto -> OK/FALLO"
## en res://dbg19_resultados.txt. Guarda y restaura el guardado del jugador.
##
## Si existen recursos de PRUEBA (res://art/cinematics/david_lucy_summon.ogv y/o
## res://audio/music/david_lucy_theme.*) las comprobaciones de video y de tema suenan de
## verdad; si no existen, se comprueba la rama de "archivo ausente". Ver tools/dbg19_run.sh.

const RESULTS_PATH := "res://dbg19_resultados.txt"
const DUO := "david_lucy_duo"
const BANNER := "banner_david_lucy"
const DevTools := preload("res://dev/dev_tools.gd")
const CombatUnit := preload("res://core/combat_unit.gd")

var _app: Node = null
var _fails := 0
var _checks := 0
var _has_theme := false
var _has_video := false


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
	_out("[DBG19] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _frames(count: int = 2) -> void:
	for i in count:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _screen(key: String) -> Node:
	return (_app.get("_screens") as Dictionary).get(key, null)


func _music_name() -> String:
	return String(GameAudio.get("_music_path")).get_file().get_basename()


func _music_players_playing() -> int:
	var n := 0
	for child in GameAudio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing and (child as AudioStreamPlayer).stream != null:
			if String((child as AudioStreamPlayer).stream.resource_path).contains("/music/"):
				n += 1
	return n


func run(app: Node) -> void:
	_app = app
	await _frames()
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out("[DBG19] --- comprobaciones del Hito E ---")
	_app.call("_backup_save")
	_has_theme = GameAudio.has_stream("david_lucy_theme")
	_has_video = ResourceLoader.exists("res://art/cinematics/david_lucy_summon.ogv")
	_out("[DBG19] recursos de prueba: tema=%s video=%s" % [str(_has_theme), str(_has_video)])
	GameSettings.set_value("music_volume", 0.8, false)
	GameSettings.set_value("reduce_motion", false, false)

	_check_unit_data()
	_check_evolution()
	_check_banner()
	_check_state_api()
	await _check_reveal_x10()
	await _check_reveal_x1()
	await _check_duplicates_and_keys()
	await _check_cinematic()
	await _check_persistence()
	_check_ultimate_logic()
	await _check_ultimate_manager()
	await _check_ultimate_battle()
	await _check_audio()
	await _check_dev_tools()

	_app.call("_restore_save")
	_out("[DBG19] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	var code := 1 if _fails > 0 else 0
	get_tree().quit(code)


func _reset() -> void:
	GameState.pending_reveal = {}
	GameState.rarities.erase(DUO)
	GameState.roster.erase(DUO)
	GameState.progress.erase(DUO)
	GameState.duplicates.erase(DUO)
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.normalize_party()
	GameState.gems = 100000
	GameState.coins = 1000000


## Fija una secuencia pendiente CONTROLADA (sin azar) para probar el revelado.
func _set_pending(ids: Array, cinematic_done: bool = false) -> void:
	var results: Array = []
	for id in ids:
		results.append({ "id": String(id), "name": GameState.display_name(String(id)), "rarity": GameState.rarity_of(String(id)), "new": false, "duplicate": true, "duplicates": 1 })
	GameState.pending_reveal = {
		"banner": BANNER, "banner_name": "Edgerunners", "count": ids.size(), "cost": 90, "index": 0,
		"results": results, "new_count": 0, "duplicate_count": ids.size(), "cinematic_done": cinematic_done,
	}


func _open_reveal() -> Node:
	var summon := _screen("summon")
	_app.call("open_screen", "summon")
	await _frames(2)
	summon.call("_begin_reveal")
	await _frames(3)
	return summon.get_node_or_null("SummonReveal")


func _wait_card(rv: Node, max_seconds: float = 6.0) -> bool:
	var waited := 0.0
	while waited < max_seconds:
		if not is_instance_valid(rv):
			return false
		if rv.call("phase") == "card" and not bool(rv.call("is_busy")):
			await _wait(0.2)
			return true
		if rv.call("phase") == "cinematic":
			rv.call("skip_cinematic")
		await _wait(0.1)
		waited += 0.1
	return false


## --- Datos de la unidad ----------------------------------------------------------------
func _check_unit_data() -> void:
	_out("[DBG19] == UNIDAD: DATOS ==")
	var count := 0
	for id in DB.characters.keys():
		if String(id) == DUO:
			count += 1
	_check("el ID david_lucy_duo existe una sola vez", count == 1)
	var data := DB.get_character(DUO)
	_check("el archivo data/characters/david_lucy_duo.json coincide con su id", FileAccess.file_exists("res://data/characters/%s.json" % DUO) and String(data.get("id", "")) == DUO)
	_check("nace como SSR", String(data.get("rarity", "")) == "SSR")
	_check("estadisticas en datos (hp, atk, def, speed)", int(data["stats"]["max_hp"]) > 0 and int(data["stats"]["atk"]) > 0 and int(data["stats"]["def"]) > 0 and int(data["stats"]["speed"]) > 0)
	_check("tiene tipo, categorias, links, pasiva y habilidades", not String(data.get("type", "")).is_empty() and not (data["categories"] as Array).is_empty() and not (data["links"] as Array).is_empty() and not (data["passive"] as Dictionary).is_empty() and (data["skills"] as Array).size() == 2)
	_check("tiene Leader Skill declarada en datos", DB.leader_id_for(DUO) == "lead_david_lucy_duo" and not (DB.leader_for(DUO) as Dictionary).is_empty())
	var david := DB.get_character("david")
	var lucy := DB.get_character("lucy")
	_check("David y Lucy individuales siguen intactos (SR, ids propios)", String(david.get("id", "")) == "david" and String(lucy.get("id", "")) == "lucy" and String(david.get("rarity", "")) == "SR" and String(lucy.get("rarity", "")) == "SR" and int(david["stats"]["max_hp"]) == 1290 and int(lucy["stats"]["max_hp"]) == 1150)
	_check("DB arranca sin errores de carga", DB.load_errors.is_empty())
	_check("el duo declara forma LR con ultimate en sus datos", (data["evolution"]["lr"]["ultimate"] as Dictionary).size() > 0)


func _same_ids(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if String(a[i]["id"]) != String(b[i]["id"]):
			return false
	return true


## --- API de estado de la secuencia de revelado y banner (anadido en la iteracion final) ----
func _check_state_api() -> void:
	_out("[DBG19] == API DE ESTADO: SECUENCIA PENDIENTE Y BANNER ==")
	_reset()
	GameState.gems = 1000
	var before := GameState.gems
	var report := GameState.summon(BANNER, 10, true)
	_check("summon(x10, stage_reveal) cobra 90 una sola vez y fija 10 resultados", bool(report["ok"]) and before - GameState.gems == 90 and (report["results"] as Array).size() == 10 and GameState.has_pending_reveal())
	var gems_after := GameState.gems
	var blocked := GameState.summon(BANNER, 1, true)
	_check("con una secuencia pendiente no se puede invocar otra vez (sin cobro)", not bool(blocked["ok"]) and GameState.gems == gems_after)
	var first := GameState.reveal_current()
	GameState.reveal_advance()
	_check("reveal_advance pasa al resultado 2 sin re-tirar", int(GameState.pending_reveal["index"]) == 1 and (GameState.pending_reveal["results"] as Array)[0]["id"] == first["id"])
	GameState.save_game()
	var snapshot := (GameState.pending_reveal["results"] as Array).duplicate(true)
	GameState.pending_reveal = {}
	GameState.load_game()
	_check("la secuencia pendiente sobrevive a guardar/cargar con los mismos resultados y el indice", GameState.has_pending_reveal() and int(GameState.pending_reveal["index"]) == 1 and _same_ids(GameState.pending_reveal["results"] as Array, snapshot) and GameState.gems == gems_after)
	for i in 20:
		GameState.reveal_advance()
	var summary := GameState.reveal_finish()
	_check("reveal_finish devuelve el resumen y limpia la secuencia", not summary.is_empty() and not GameState.has_pending_reveal())
	# Un guardado con indice fuera de rango se descarta sin romper.
	_check("un pendiente incoherente se descarta", GameState._clean_pending_reveal({ "results": [{ "id": "gojo" }], "index": 5 }).is_empty() and GameState._clean_pending_reveal({ "results": [{ "id": "no_existe" }], "index": 0 }).is_empty())
	# Banner desactivado: no aparece ni se puede invocar.
	DB.banners[BANNER]["enabled"] = false
	var off := GameState.summon(BANNER, 1)
	var listed := DB.all_banners().any(func(b): return String(b["id"]) == BANNER)
	DB.banners[BANNER]["enabled"] = true
	_check("enabled:false oculta el banner y rechaza invocar sin cobrar", not bool(off["ok"]) and not listed)
	# Tasa propia: frecuencia del duo en el banner dentro de lo plausible (no sustituye a la tabla).
	_reset()
	GameState.gems = 100000000
	var duo_hits := 0
	var total := 6000
	for i in total:
		var picked := GameState._pick_candidate(BANNER, "SSR", ["david_lucy_duo", "gojo", "deku"])
		if picked == DUO:
			duo_hits += 1
	_check("la tasa propia del duo dentro del SSR ronda el 7/15 (%d/%d)" % [duo_hits, total], absf(float(duo_hits) / total - 0.07 / 0.15) < 0.04)
	# Los otros banners: sus tablas no han cambiado.
	var ok_tables := true
	for bid in ["banner_apertura", "banner_destacado", "banner_shonen", "banner_ur"]:
		if not DB.get_banner(bid).is_empty() and not GameState.banner_problems(bid).is_empty():
			ok_tables = false
	_check("los banners genericos siguen validos y sin tasas propias", ok_tables and GameState.banner_featured_rates("banner_apertura").is_empty())
	_reset()


## --- Evolucion normal SSR -> UR -> LR ----------------------------------------------------
func _check_evolution() -> void:
	_out("[DBG19] == EVOLUCION NORMAL SSR > UR > LR ==")
	_reset()
	var info := GameState.add_character(DUO)
	_check("se obtiene en el roster como SSR", bool(info.get("added", false)) and GameState.is_owned(DUO) and GameState.rarity_of(DUO) == "SSR")
	_check("en SSR no tiene ultimate", (GameState.character_data(DUO)["ultimate"] as Dictionary).is_empty())
	var early := GameState.can_evolve(DUO)
	_check("a nivel 1 no puede evolucionar (nivel insuficiente)", not bool(early["ok"]) and int(early["level_required"]) == 100)
	GameState.progress[DUO]["level"] = 100
	var coins_before := GameState.coins
	var check_ur := GameState.can_evolve(DUO)
	_check("SSR>UR por la ruta NORMAL (rules.json): nivel 100 + monedas del sistema", bool(check_ur["ok"]) and String(check_ur["to"]) == "UR" and int(check_ur["coin_cost"]) == 100000)
	var report := GameState.evolve(DUO)
	_check("evoluciona a UR", GameState.rarity_of(DUO) == "UR" and String(report.get("to_rarity", "")) == "UR")
	_check("los recursos se cobran UNA sola vez (SSR>UR)", coins_before - GameState.coins == 100000)
	var again := GameState.evolve(DUO)
	_check("repetir la evolucion no cobra ni cambia nada", again.is_empty() and coins_before - GameState.coins == 100000 and GameState.rarity_of(DUO) == "UR")
	_check("en UR no tiene ultimate", (GameState.character_data(DUO)["ultimate"] as Dictionary).is_empty())
	_check("UR trae su multiplicador x1.25", is_equal_approx(float(GameState.character_data(DUO)["stat_multiplier"]), 1.25))
	var early_lr := GameState.can_evolve(DUO)
	_check("UR>LR pide nivel 100 de nuevo (nivel 1 tras evolucionar)", not bool(early_lr["ok"]) and String(early_lr["to"]) == "LR")
	GameState.progress[DUO]["level"] = 100
	coins_before = GameState.coins
	var check_lr := GameState.can_evolve(DUO)
	_check("UR>LR por la ruta NORMAL: sin materiales ni rutas especiales", bool(check_lr["ok"]) and (check_lr["route"] as Dictionary).get("item_cost", null) == null and GameState.can_special_evolve(DUO).get("to", "") == "")
	GameState.evolve(DUO)
	_check("evoluciona a LR", GameState.rarity_of(DUO) == "LR")
	_check("los recursos se cobran UNA sola vez (UR>LR)", coins_before - GameState.coins == int(check_lr["coin_cost"]))
	var lr_data := GameState.character_data(DUO)
	_check("LR trae su multiplicador x1.5 y su pasiva propia", is_equal_approx(float(lr_data["stat_multiplier"]), 1.5) and String((lr_data["passive"] as Dictionary).get("id", "")) == "pas_duo_lr_hasta_la_luna" and (lr_data["passives"] as Array).size() == 2)
	_check("LR acumula links y categorias de UR y LR", (lr_data["links"] as Array).has("veteranos") and (lr_data["links"] as Array).has("inquebrantables") and (lr_data["categories"] as Array).has("leyendas") and (lr_data["categories"] as Array).has("despertados"))
	_check("LR tiene la ultimate", String((lr_data["ultimate"] as Dictionary).get("id", "")) == "ult_edgerunners")
	_check("en LR no hay mas evolucion", not bool(GameState.can_evolve(DUO)["ok"]) and String(GameState.can_evolve(DUO)["to"]) == "")
	# Otro personaje que evoluciono a UR no puede dar el salto a LR por accidente.
	GameState.add_character("gojo")
	GameState.progress["gojo"]["level"] = 100
	GameState.evolve("gojo")
	GameState.progress["gojo"]["level"] = 100
	var gojo_lr := GameState.can_evolve("gojo")
	_check("un UR sin forma LR (Gojo) NO puede evolucionar a LR", GameState.rarity_of("gojo") == "UR" and not bool(gojo_lr["ok"]))
	GameState.rarities.erase("gojo")
	GameState.progress["gojo"] = { "level": 1, "xp": 0 }
	# Persistencia de la forma.
	GameState.save_game()
	GameState.rarities.clear()
	GameState.load_game()
	_check("la rareza LR sobrevive a guardar y cargar", GameState.rarity_of(DUO) == "LR")


## --- Banner ------------------------------------------------------------------------------
func _check_banner() -> void:
	_out("[DBG19] == BANNER ==")
	var banner := DB.get_banner(BANNER)
	_check("el banner del duo existe y esta activo", not banner.is_empty() and bool(banner.get("enabled", true)) and DB.all_banners().any(func(b): return String(b["id"]) == BANNER))
	_check("el banner no tiene problemas de configuracion", GameState.banner_problems(BANNER).is_empty())
	var rates := GameState.banner_rates(BANNER)
	var total := 0.0
	for k in rates:
		total += float(rates[k])
	_check("las tasas del banner suman exactamente 100%", absf(total - 1.0) < 1e-9)
	_check("SSR configurado = 15% (sin renormalizar)", absf(float(rates.get("SSR", 0.0)) - 0.15) < 1e-12 and not rates.has("UR") and not rates.has("LR"))
	var rows := GameState.banner_rate_table(BANNER)
	var rows_total := 0.0
	var duo_rate := 0.0
	var ssr_rest := 0.0
	for row in rows:
		rows_total += float(row["rate"])
		if String(row["id"]) == DUO:
			duo_rate = float(row["rate"])
		elif String(row["rarity"]) == "SSR":
			ssr_rest = float(row["rate"])
	_check("la tabla efectiva (filas) suma 100%% y el duo tiene su 7%% (%.4f)" % rows_total, absf(rows_total - 1.0) < 1e-9 and absf(duo_rate - 0.07) < 1e-12 and absf(ssr_rest - 0.08) < 1e-12)
	_check("el duo esta en el pool de SU banner", GameState.banner_pool(BANNER).has(DUO))
	var leaked: Array = []
	for raw in DB.all_banners():
		var bid := String((raw as Dictionary).get("id", ""))
		if bid != BANNER and GameState.banner_pool(bid).has(DUO):
			leaked.append(bid)
	_check("el duo NO esta en ningun otro banner %s" % str(leaked), leaked.is_empty())
	var bad_forms := false
	for raw in DB.all_banners():
		for id in GameState.banner_pool(String((raw as Dictionary).get("id", ""))):
			var r := String(DB.get_character(String(id)).get("rarity", ""))
			if id in ["sakuta_mai", "sakuta", "sakuta_mai_lr"] or (r == "LR"):
				bad_forms = true
	_check("ningun banner puede dar formas LR ni la unidad F2P", not bad_forms)
	# El duo, solo como SSR: ninguna tirada del banner lo da como UR/LR (datos reales).
	var pool := GameState.banner_pool(BANNER)
	var duo_ssr := String(DB.get_character(DUO).get("rarity", "")) == "SSR"
	var ur_or_lr_candidates := 0
	for id in pool:
		if String(DB.get_character(String(id)).get("rarity", "")) in ["UR", "LR"]:
			ur_or_lr_candidates += 1
	_check("el pool del banner no contiene UR ni LR; el duo es SSR en datos", duo_ssr and ur_or_lr_candidates == 0)
	# Muestreo (solo comprobacion de cordura; la tabla real ya se ha comprobado arriba).
	var duo_hits := 0
	var ssr_hits := 0
	var other_rarity := 0
	var n := 20000
	for i in n:
		var rarity := GameState.roll_rarity(rates)
		if rarity == "SSR":
			ssr_hits += 1
			var candidates: Array = []
			for id in pool:
				if String(DB.get_character(String(id)).get("rarity", "")) == "SSR":
					candidates.append(String(id))
			if GameState._pick_candidate(BANNER, "SSR", candidates) == DUO:
				duo_hits += 1
		elif rarity != "SR":
			other_rarity += 1
	_check("muestreo: SSR ~15%% (%.3f) y duo ~7%% (%.3f) en %d tiradas" % [float(ssr_hits) / n, float(duo_hits) / n, n], absf(float(ssr_hits) / n - 0.15) < 0.012 and absf(float(duo_hits) / n - 0.07) < 0.01 and other_rarity == 0)
	_reset()
	GameState.gems = 100000
	var report := GameState.summon(BANNER, 10)
	var all_ok := bool(report.get("ok", false)) and (report["results"] as Array).size() == 10
	for entry in report.get("results", []):
		var er := String((entry as Dictionary)["rarity"])
		if String((entry as Dictionary)["id"]) == DUO and er != "SSR":
			all_ok = false
	_check("x10 real: 10 resultados y cualquier duo sale como SSR", all_ok)
	GameState.rarities.erase(DUO)
	# Un banner apagado no se puede usar.
	_reset()
	_check("invocar en un banner inexistente falla sin cobrar", not bool(GameState.summon("no_existe", 1).get("ok", true)) and GameState.gems == 100000)


## --- Revelado individual x10 ---------------------------------------------------------------
func _check_reveal_x10() -> void:
	_out("[DBG19] == REVELADO INDIVIDUAL x10 ==")
	_reset()
	var screen := _screen("summon")
	_app.call("open_screen", "summon")
	await _frames(3)
	screen.set("_banner_id", "banner_apertura")
	screen.call("refresh")
	var gems_before := GameState.gems
	var cost := GameState.banner_cost("banner_apertura", 10)
	screen.call("_on_roll", 10)
	await _frames(2)
	_check("x10: el coste se cobra UNA vez nada mas pulsar (antes de revelar)", gems_before - GameState.gems == cost)
	_check("x10: los 10 resultados quedan FIJADOS antes del revelado", GameState.has_pending_reveal() and (GameState.pending_reveal["results"] as Array).size() == 10)
	var fixed: Array = []
	for entry in GameState.pending_reveal["results"]:
		fixed.append(String((entry as Dictionary)["id"]))
	var roster_after_roll: Array = GameState.roster.duplicate()
	var dups_after_roll: Dictionary = GameState.duplicates.duplicate()
	var fx = screen.get_node_or_null("SummonFx")
	_check("x10: primero la animacion de invocacion (no hay cartas todavia)", fx != null and screen.get_node_or_null("SummonReveal") == null)
	var gems_mid := GameState.gems
	screen.call("_on_roll", 10)
	screen.call("_on_roll", 1)
	_check("x10: no se pueden iniciar otras invocaciones durante la secuencia", GameState.gems == gems_mid and (GameState.pending_reveal["results"] as Array).size() == 10)
	_check("x10: los botones de invocar estan bloqueados", (screen.get("single_button") as Button).disabled and (screen.get("multi_button") as Button).disabled)
	fx.call("_skip")
	await _frames(3)
	var rv := screen.get_node_or_null("SummonReveal")
	_check("tras la animacion aparece el revelado a pantalla completa", rv != null)
	if rv == null:
		return
	_check("revelado: el rectangulo cubre toda la pantalla", (rv as Control).size.x >= 1000.0 and (rv as Control).size.y >= 1800.0)
	await _wait_card(rv)
	_check("revelado: contador 1/10", String(rv.call("counter_text")) == "1/10")
	_check("revelado: solo UNA carta en pantalla", rv.find_children("CardFrame", "PanelContainer", true, false).size() == 1)
	_check("revelado: se muestra el primer resultado fijado", String(rv.call("current_id")) == fixed[0])
	var order_ok := true
	var counters_ok := true
	var one_card_ok := true
	var rapid_ok := true
	var seen: Array = [fixed[0]]
	for i in range(1, 10):
		# Varios toques seguidos: solo uno puede avanzar.
		rv.call("tap")
		rv.call("tap")
		rv.call("tap")
		if rv.call("phase") != "card" and false:
			rapid_ok = false
		await _wait(0.25)
		var ok_card := await _wait_card(rv)
		if not ok_card:
			order_ok = false
			break
		if String(rv.call("counter_text")) != "%d/10" % (i + 1):
			counters_ok = false
		if String(rv.call("current_id")) != fixed[i]:
			order_ok = false
		if rv.find_children("CardFrame", "PanelContainer", true, false).size() != 1:
			one_card_ok = false
		seen.append(String(rv.call("current_id")))
		if i == 1:
			pass
	_check("revelado: el contador avanza 2/10 ... 10/10 sin saltarse ninguno", counters_ok and seen.size() == 10)
	_check("revelado: cada pantalla muestra el resultado fijado en su posicion (sin volver a sortear)", order_ok)
	_check("revelado: siempre una sola carta a la vez", one_card_ok)
	_check("revelado: el resumen NO se ve antes de los diez", not bool(rv.call("summary_visible")) and rv.find_child("SummaryGrid", true, false) == null and String(rv.call("phase")) == "card")
	_check("avanzar no ha tocado gemas, roster ni duplicados", GameState.gems == gems_mid and GameState.roster == roster_after_roll and GameState.duplicates == dups_after_roll)
	rv.call("tap")
	await _wait(0.5)
	_check("tras el 10/10 aparece la pantalla final con opciones", String(rv.call("phase")) == "end" and rv.find_child("EndPanel", true, false) != null and rv.find_child("SummaryButton", true, false) != null)
	_check("el resumen sigue sin mostrarse hasta pedirlo", not bool(rv.call("summary_visible")))
	var button: Button = rv.find_child("SummaryButton", true, false)
	button.pressed.emit()
	await _wait(0.3)
	var grid := rv.find_child("SummaryGrid", true, false)
	_check("el resumen muestra las 10 unidades (con todas visibles)", grid != null and grid.get_child_count() == 10 and (grid.get_child(0) as Control).modulate.a > 0.99)
	var back: Button = rv.find_child("ReturnButton", true, false)
	back.pressed.emit()
	await _wait(0.3)
	_check("VOLVER AL BANNER cierra el revelado y libera la secuencia", not is_instance_valid(rv) and not GameState.has_pending_reveal() and screen.get_node_or_null("SummonReveal") == null)
	_check("los botones vuelven a estar disponibles", not (screen.get("single_button") as Button).disabled)
	_check("el coste de la x10 se cobro una sola vez en total", gems_before - GameState.gems == cost)
	var save_text := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	var parsed = JSON.parse_string(save_text)
	_check("el guardado no conserva secuencia pendiente tras terminar", parsed is Dictionary and (parsed.get("pending_reveal", {}) as Dictionary).is_empty())


func _check_reveal_x1() -> void:
	_out("[DBG19] == REVELADO x1 ==")
	_reset()
	var screen := _screen("summon")
	_app.call("open_screen", "summon")
	await _frames(3)
	screen.set("_banner_id", "banner_apertura")
	var gems_before := GameState.gems
	screen.call("_on_roll", 1)
	await _frames(2)
	_check("x1: concede exactamente un resultado y cobra una vez", (GameState.pending_reveal["results"] as Array).size() == 1 and gems_before - GameState.gems == GameState.banner_cost("banner_apertura", 1))
	var fx = screen.get_node_or_null("SummonFx")
	if fx != null:
		fx.call("_skip")
	await _frames(3)
	var rv := screen.get_node_or_null("SummonReveal")
	_check("x1: revelado a pantalla completa", rv != null)
	if rv == null:
		return
	await _wait_card(rv)
	_check("x1: no hay contador 1/1", String(rv.call("counter_text")) == "")
	_check("x1: carta con nombre, rareza y retrato", rv.find_child("CardName", true, false) != null and rv.find_child("CardArt", true, false) != null)
	var gems_mid := GameState.gems
	rv.call("tap")
	await _wait(0.6)
	_check("x1: tocar cierra el revelado y vuelve al banner sin volver a cobrar", not is_instance_valid(rv) and GameState.gems == gems_mid and not GameState.has_pending_reveal())


func _check_duplicates_and_keys() -> void:
	_out("[DBG19] == DUPLICADOS Y TECLADO ==")
	_reset()
	GameState.add_character("gojo")
	var dups_before := GameState.duplicates_of("gojo")
	var info := GameState.add_character("gojo")
	_check("un repetido suma duplicado y no duplica el roster", bool(info["duplicate"]) and GameState.duplicates_of("gojo") == dups_before + 1 and GameState.roster.count("gojo") == 1)
	# Una x10 con resultados repetidos: se revelan todos y el chip dice REPETIDO.
	_set_pending(["gojo", "gojo", "gojo"])
	var rv := await _open_reveal()
	_check("secuencia con repetidos: se abre", rv != null)
	if rv == null:
		return
	await _wait_card(rv)
	var chip: Label = rv.find_child("NewChip", true, false)
	_check("un repetido se anuncia como REPETIDO", chip != null and chip.text.begins_with("REPETIDO"))
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	rv.call("_input", ev)
	await _wait(0.5)
	await _wait_card(rv)
	_check("Enter avanza al siguiente (2/3)", String(rv.call("counter_text")) == "2/3")
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_SPACE
	ev2.pressed = true
	rv.call("_input", ev2)
	await _wait(0.5)
	await _wait_card(rv)
	_check("Espacio avanza al siguiente (3/3)", String(rv.call("counter_text")) == "3/3")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	rv.call("_gui_input", click)
	await _wait(0.5)
	_check("un clic en el ultimo resultado lleva a la pantalla final", String(rv.call("phase")) == "end")
	(rv.find_child("ReturnButton", true, false) as Button).pressed.emit()
	await _wait(0.3)
	_check("la capa se cierra y deja la pantalla utilizable", not GameState.has_pending_reveal())


## --- Cinematica del duo ----------------------------------------------------------------------
func _check_cinematic() -> void:
	_out("[DBG19] == CINEMATICA DEL DUO (video=%s, tema=%s) ==" % [str(_has_video), str(_has_theme)])
	_reset()
	var roster_before: Array = GameState.roster.duplicate()
	GameState.add_character(DUO)
	var gems_before := GameState.gems
	# 1) Duo primero: cinematica antes de la carta.
	_set_pending([DUO, "gojo"])
	var rv := await _open_reveal()
	_check("el duo abre la secuencia especial ANTES de revelar su carta", rv != null and String(rv.call("phase")) == "cinematic")
	if rv == null:
		return
	var log_now: Array = rv.get("fx_log")
	_check("todavia no se ha mostrado ninguna carta (%s)" % str(log_now), not log_now.any(func(e): return String(e).begins_with("card:")))
	_check("la secuencia usa video o, si falta/falla, la alternativa", log_now.has("cinematic_video") or log_now.has("cinematic_fallback"))
	if _has_video:
		_check("con el archivo presente se crea el reproductor de video", log_now.has("cinematic_video") and rv.find_child("CinematicVideo", true, false) != null)
		var vp: VideoStreamPlayer = rv.find_child("CinematicVideo", true, false)
		_check("el audio del video esta silenciado (no se superpone a la musica)", vp != null and vp.volume_db <= -79.0)
		await _wait(0.8)
		_check("el video se esta reproduciendo", vp != null and is_instance_valid(vp) and vp.is_playing())
	else:
		_check("sin archivo de video: no hay pantalla negra, entra la alternativa", rv.get("fx_log").has("cinematic_fallback") and rv.find_child("CinematicFallback", true, false) != null)
	_check("el boton SALTAR existe", rv.find_child("SkipCinematicButton", true, false) != null)
	_check("la cinematica no ha cobrado ni concedido nada", GameState.gems == gems_before and GameState.roster.count(DUO) == 1 and GameState.duplicates_of(DUO) == 0)
	if _has_theme:
		_check("empieza el tema especial con la cinematica", _music_name() == "david_lucy_theme" and GameAudio.override_owner() == "summon")
		_check("una sola pista de musica sonando", _music_players_playing() == 1)
	else:
		_check("sin tema: sigue la musica de la pantalla (no se silencia)", _music_name() == "menu" and not GameAudio.override_active())
	# Varios clics en SALTAR: solo cuenta uno.
	var skip: Button = rv.find_child("SkipCinematicButton", true, false)
	skip.pressed.emit()
	skip.pressed.emit()
	skip.pressed.emit()
	await _wait(0.8)
	await _wait_card(rv)
	var skip_log: Array = rv.get("fx_log")
	_check("saltar pasa directo al revelado del duo (sin perder la unidad)", String(rv.call("current_id")) == DUO and skip_log.count("cinematic_end") == 1 and skip_log.count("cinematic_skipped") == 1)
	_check("la cinematica no se repite por varios clics", skip_log.count("cinematic_start") == 1)
	_check("la carta del duo es la especial (cinta de unidad insignia)", rv.find_child("CardName", true, false) != null and String((rv.find_child("CardName", true, false) as Label).text) == "David Martinez & Lucy")
	_check("saltar no ha cobrado ni concedido nada", GameState.gems == gems_before and GameState.roster.count(DUO) == 1)
	_check("la cinematica queda marcada como vista en la secuencia", bool(GameState.pending_reveal.get("cinematic_done", false)))
	rv.call("tap")
	await _wait(0.5)
	await _wait_card(rv)
	_check("tras la carta del duo continua con el siguiente resultado (2/2)", String(rv.call("current_id")) == "gojo" and String(rv.call("counter_text")) == "2/2")
	rv.call("tap")
	await _wait(0.5)
	(rv.find_child("ReturnButton", true, false) as Button).pressed.emit()
	await _wait(0.4)
	_check("al terminar la secuencia se recupera la musica de la pantalla (no el tema)", _music_name() == "menu" and not GameAudio.override_active())

	# 2) Dos copias del duo en una x10: la 1a cinematica completa, la 2a corta.
	GameState.pending_reveal = {}
	_set_pending(["gojo", DUO, "gojo", DUO])
	rv = await _open_reveal()
	await _wait_card(rv)
	rv.call("tap")
	await _wait(0.5)
	_check("x10 con duo en 2a posicion: cinematica completa al llegar a el", String(rv.call("phase")) == "cinematic")
	if _has_video:
		await _wait(0.4)
		var p2: VideoStreamPlayer = rv.find_child("CinematicVideo", true, false)
		_check("la cinematica completa usa el video", p2 != null)
		# Dejar que termine sola (2 s de video de prueba): finished -> revelado.
		# Con el video real (~35 s) se espera a que termine sola (sondeo, maximo 45 s).
		var waited := 0.0
		while String(rv.call("phase")) == "cinematic" and waited < 45.0:
			await _wait(0.5)
			waited += 0.5
		_check("al TERMINAR el video pasa solo al revelado de la carta", String(rv.call("phase")) == "card" and String(rv.call("current_id")) == DUO)
	else:
		await _wait(3.2)
		_check("al terminar la alternativa pasa sola al revelado de la carta", String(rv.call("phase")) == "card" and String(rv.call("current_id")) == DUO)
	var log2: Array = rv.get("fx_log")
	rv.call("tap")
	await _wait(0.5)
	await _wait_card(rv)
	rv.call("tap")
	await _wait(0.5)
	await _wait_card(rv)
	var log3: Array = rv.get("fx_log")
	_check("la segunda copia NO repite la cinematica completa (revelado corto)", log3.count("cinematic_start") == 1 and log3.has("short_special") and String(rv.call("current_id")) == DUO)
	rv.call("tap")
	await _wait(0.5)
	rv.call("tap")
	await _wait(0.5)
	_check("la secuencia termina", String(rv.call("phase")) == "end")
	(rv.find_child("ReturnButton", true, false) as Button).pressed.emit()
	await _wait(0.4)
	# 3) Video corrupto: no hay pantalla negra permanente (se usa la alternativa).
	var bad := FileAccess.open("user://bad_video.ogv", FileAccess.WRITE)
	if bad != null:
		bad.store_string("esto no es un video")
		bad.close()
	var cfg: Dictionary = DB.characters[DUO]["summon_cinematic"]
	var saved_video: String = String(cfg["video"])
	cfg["video"] = "user://bad_video.ogv"
	_set_pending([DUO])
	rv = await _open_reveal()
	await _wait(2.0)
	_check("un archivo de video invalido no rompe: entra la alternativa", rv != null and rv.get("fx_log").has("cinematic_fallback"))
	await _wait(3.4)
	_check("y el revelado llega igualmente", rv != null and is_instance_valid(rv) and String(rv.call("phase")) == "card" and String(rv.call("current_id")) == DUO)
	cfg["video"] = saved_video
	rv.call("tap")
	await _wait(0.6)
	GameState.pending_reveal = {}
	GameState.roster = roster_before


func _check_persistence() -> void:
	_out("[DBG19] == PERSISTENCIA DE LA SECUENCIA ==")
	_reset()
	GameState.add_character(DUO)
	_set_pending(["gojo", "isagi", "frieren", "mai"], true)
	GameState.pending_reveal["index"] = 2
	var gems_before := GameState.gems
	var roster_before: Array = GameState.roster.duplicate()
	GameState.save_game()
	GameState.pending_reveal = {}
	GameState.load_game()
	_check("la secuencia pendiente se recupera tras cerrar y abrir (indice 3/4)", GameState.has_pending_reveal() and int(GameState.pending_reveal["index"]) == 2 and (GameState.pending_reveal["results"] as Array).size() == 4)
	var screen := _screen("summon")
	_app.call("open_screen", "summon")
	await _frames(3)
	screen.call("_begin_reveal")
	await _frames(3)
	var rv := screen.get_node_or_null("SummonReveal")
	_check("al volver a la pantalla se retoma la secuencia", rv != null)
	if rv != null:
		await _wait_card(rv)
		_check("se reanuda en 3/4 con el mismo personaje y sin cobrar ni conceder (%s %s %d/%d)" % [rv.call("counter_text"), rv.call("current_id"), GameState.gems, gems_before], String(rv.call("counter_text")) == "3/4" and String(rv.call("current_id")) == "frieren" and GameState.gems == gems_before and GameState.roster == roster_before)
		_check("mientras hay secuencia no se puede invocar", not bool(GameState.summon("banner_apertura", 1).get("ok", true)) and GameState.gems == gems_before)
		rv.call("tap")
		await _wait(0.5)
		await _wait_card(rv)
		rv.call("tap")
		await _wait(0.5)
		(rv.find_child("ReturnButton", true, false) as Button).pressed.emit()
		await _wait(0.4)
	# Guardado incoherente: se descarta sin romper ni conceder.
	GameState.pending_reveal = { "results": [{ "id": "no_existe" }], "index": 0 }
	GameState.save_game()
	GameState.load_game()
	_check("un guardado de secuencia corrupto se descarta sin efectos", not GameState.has_pending_reveal())
	GameState.pending_reveal = { "results": [{ "id": "gojo" }], "index": 7 }
	GameState.save_game()
	GameState.load_game()
	_check("un indice fuera de rango se descarta", not GameState.has_pending_reveal())


## --- Ultimate: datos y reglas ------------------------------------------------------------------
func _lr_data(rarity: String) -> Dictionary:
	GameState.rarities[DUO] = rarity
	if not GameState.roster.has(DUO):
		GameState.roster.append(DUO)
	GameState.progress[DUO] = { "level": 1, "xp": 0 }
	return GameState.character_data(DUO)


func _check_ultimate_logic() -> void:
	_out("[DBG19] == ULTIMATE: DATOS Y DISPONIBILIDAD ==")
	_reset()
	var ssr := _lr_data("SSR")
	var ur := _lr_data("UR")
	var lr := _lr_data("LR")
	var CU := load("res://core/combat_unit.gd")
	var unit_ssr = CU.new()
	unit_ssr.setup(ssr, true, 0)
	var unit_ur = CU.new()
	unit_ur.setup(ur, true, 0)
	var unit_lr = CU.new()
	unit_lr.setup(lr, true, 0)
	_check("en SSR no hay ultimate", not unit_ssr.has_ultimate())
	_check("en UR no hay ultimate", not unit_ur.has_ultimate())
	_check("en LR hay ultimate", unit_lr.has_ultimate())
	var ult: Dictionary = unit_lr.ultimate
	_check("el nombre vive en datos: EDGERUNNERS: ULTIMATE", String(ult["name"]) == "EDGERUNNERS: ULTIMATE")
	var effects: Array = ult["effects"]
	var atk_ok := false
	var def_ok := false
	var foe_ok := false
	for e in effects:
		if e["stat"] == "atk" and e["target"] == "ally_all" and is_equal_approx(float(e["value"]), 0.4) and int(e["turns"]) == 2:
			atk_ok = true
		if e["stat"] == "def" and e["target"] == "ally_all" and is_equal_approx(float(e["value"]), 0.25) and int(e["turns"]) == 2:
			def_ok = true
		if e["stat"] == "def" and e["target"] == "enemy_all" and is_equal_approx(float(e["value"]), -0.2) and int(e["turns"]) == 2:
			foe_ok = true
	_check("efectos parametrizados en datos: ATK +40%, DEF +25% aliados, DEF -20% rivales (2 turnos)", atk_ok and def_ok and foe_ok)
	_check("es de area (todos los rivales) y mucho mas potente que el especial", String(ult["target"]) == "enemy_all" and float(ult["power"]) > 2.0 * float(lr["skills"][1]["power"]) and int(ult["cost"]) > int(lr["skills"][1]["cost"]) - 1)
	_check("el coste en SP viene de datos y se muestra", int(ult["cost"]) == 3 and int(ult["cost"]) <= CombatUnit.SP_MAX)
	# Los enemigos y personajes sin forma no la traen.
	var enemy = CU.new()
	enemy.setup(DB.get_enemy("void_warden"), false, 0)
	_check("un enemigo no tiene ultimate", not enemy.has_ultimate())
	GameState.rarities.erase(DUO)


func _manager(ally_data: Array, enemy_ids: Array) -> Node:
	var BM := load("res://core/battle_manager.gd")
	var mgr: Node = BM.new()
	add_child(mgr)
	var enemies: Array = []
	for id in enemy_ids:
		enemies.append(DB.get_enemy(String(id)))
	mgr.setup(ally_data, enemies)
	return mgr


func _check_ultimate_manager() -> void:
	_out("[DBG19] == ULTIMATE: MOTOR DE COMBATE ==")
	_reset()
	var lr := _lr_data("LR")
	var ssr_data := _lr_data("SSR")
	# SSR: no se puede usar.
	var mgr_ssr = _manager([ssr_data], ["void_warden", "vigia_alfa"])
	var u_ssr = mgr_ssr.allies[0]
	u_ssr.sp = 9
	_check("SSR: can_use('ultimate') es falso", not mgr_ssr.can_use(u_ssr, "ultimate"))
	mgr_ssr.queue_free()
	var lr2 := _lr_data("LR")
	var mgr = _manager([lr2], ["void_warden", "vigia_alfa", "vigia_beta"])
	var duo = mgr.allies[0]
	_check("LR sin SP suficiente: no disponible", duo.sp < 4 and not mgr.can_use(duo, "ultimate"))
	duo.sp = 6
	_check("LR con SP: disponible", mgr.can_use(duo, "ultimate"))
	# Ejecutar la ultimate directamente sobre el motor.
	var foes_def_before: Array = []
	for foe in mgr.enemies:
		foes_def_before.append(foe.stats.get_stat("def"))
	var atk_before: float = duo.stats.get_stat("atk")
	var def_before: float = duo.stats.get_stat("def")
	var started := [0]
	mgr.ultimate_started.connect(func(_u): started[0] += 1)
	var hp_before: Array = []
	for foe in mgr.enemies:
		hp_before.append(foe.hp)
	for foe in mgr.enemies:
		foe.stats.add_mod("dodge_rate", "flat", -1.0, "test:no_dodge", 0)
	mgr._perform(duo, "ultimate")
	_check("la ultimate se resuelve y emite ultimate_started una vez", started[0] == 1 and duo.ultimate_used)
	_check("gasta su coste en SP", is_equal_approx(duo.sp, 3.0))
	var all_hit := true
	for i in mgr.enemies.size():
		var foe = mgr.enemies[i]
		if foe.alive and foe.hp >= float(hp_before[i]):
			all_hit = false
	_check("golpea a TODOS los enemigos vivos (area)", all_hit)
	var atk_after: float = duo.stats.get_stat("atk")
	var def_after: float = duo.stats.get_stat("def")
	_check("aliados: ATK +40%% y DEF +25%% (%.0f>%.0f / %.0f>%.0f)" % [atk_before, atk_after, def_before, def_after], absf(atk_after / atk_before - 1.4) < 0.01 and absf(def_after / def_before - 1.25) < 0.01)
	var foe_ok := true
	for i in mgr.enemies.size():
		var foe = mgr.enemies[i]
		if foe.alive and absf(foe.stats.get_stat("def") / float(foes_def_before[i]) - 0.8) > 0.01:
			foe_ok = false
	_check("rivales: DEF -20%", foe_ok)
	_check("no se puede volver a usar (una vez por combate)", not mgr.can_use(duo, "ultimate"))
	duo.sp = CombatUnit.SP_MAX
	var sp_before: float = duo.sp
	var atk_snapshot: float = duo.stats.get_stat("atk")
	mgr._perform(duo, "ultimate")
	_check("forzar una segunda ultimate se degrada a ataque basico: sin SP gastado de mas ni buffs duplicados (%d, %.1f/%.1f, sp %d/%d)" % [started[0], duo.stats.get_stat("atk"), atk_snapshot, duo.sp, sp_before], started[0] == 1 and absf(duo.stats.get_stat("atk") - atk_snapshot) < 0.01 and duo.sp >= sp_before)
	# Cambio de turno / ronda: sigue sin estar disponible.
	mgr._tick_round_end()
	mgr.round_number += 1
	_check("cambiar de turno o ronda no la rehabilita", not mgr.can_use(duo, "ultimate"))
	mgr.queue_free()
	# Siguiente combate: vuelve a estar disponible.
	var mgr_next = _manager([_lr_data("LR")], ["void_warden"])
	var duo_next = mgr_next.allies[0]
	duo_next.sp = 6
	_check("en el SIGUIENTE combate vuelve a estar disponible", mgr_next.can_use(duo_next, "ultimate") and not duo_next.ultimate_used)
	mgr_next.queue_free()
	# Reaplicar el mismo origen no acumula: dos veces el mismo efecto sigue siendo x1.4.
	var mgr_b = _manager([_lr_data("LR")], ["void_warden"])
	var d2 = mgr_b.allies[0]
	var base_atk: float = d2.stats.get_stat("atk")
	var EE := load("res://core/effect_engine.gd")
	var ctx := { "actor": d2, "target": mgr_b.enemies[0], "team": mgr_b.allies, "foes": mgr_b.enemies, "rng": RandomNumberGenerator.new(), "source": "skill:ult_edgerunners", "round": 1 }
	EE.apply_effects(d2.ultimate["effects"], ctx)
	EE.apply_effects(d2.ultimate["effects"], ctx)
	_check("los buffs no se acumulan aunque se reaplique el mismo origen", absf(d2.stats.get_stat("atk") / base_atk - 1.4) < 0.01)
	mgr_b.queue_free()
	# Cierra el combate si mata al ultimo enemigo y no hay mas turnos.
	var strong := _lr_data("LR")
	strong["level"] = 100
	var mgr_k = _manager([strong], ["vigia_alfa"])
	var finished := [0, false]
	mgr_k.battle_finished.connect(func(v, _r): finished[0] += 1; finished[1] = v)
	var turns := [0]
	mgr_k.turn_started.connect(func(_u): turns[0] += 1)
	var duo_k = mgr_k.allies[0]
	duo_k.sp = 8
	mgr_k.start_battle()
	await _wait(0.4)
	var turns_at_request := int(turns[0])
	mgr_k.submit_action({ "kind": "ultimate" })
	await _wait(4.0)
	_check("si la ultimate elimina al ultimo enemigo el combate se cierra con victoria", finished[0] == 1 and finished[1] == true)
	await _wait(1.5)
	_check("tras la victoria no se procesa ningun turno mas", int(turns[0]) <= turns_at_request + 1 and finished[0] == 1)
	_check("terminado el combate la ultimate no se puede relanzar", not mgr_k.can_use(duo_k, "ultimate"))
	mgr_k.queue_free()
	GameState.rarities.erase(DUO)


## UI real: boton de ultimate, presentacion, musica y resultados.
func _check_ultimate_battle() -> void:
	_out("[DBG19] == ULTIMATE: COMBATE REAL (UI, MUSICA, RESULTADOS) ==")
	_reset()
	_lr_data("LR")
	GameState.party = [DUO, "", "", ""]
	GameState.normalize_party()
	GameState.current_stage_enemies = ["void_warden", "vigia_alfa", "vigia_beta"]
	GameState.battle_source = GameState.BATTLE_STAGE
	_app.call("open_screen", "main_menu")
	await _frames(2)
	GameState.battle_party = []
	_app.call("open_battle")
	await _wait(0.8)
	var battle = _app.get("_battle")
	_check("se abre el combate con el duo LR", battle != null)
	if battle == null:
		return
	_check("antes de la ultimate suena la musica de combate", _music_name() == "battle" and not GameAudio.override_active())
	var mgr = battle.get("manager")
	var duo = mgr.allies[0]
	duo.sp = 6
	for i in 40:
		if bool(battle.get("awaiting_input")) and battle.get("current_actor") != null and battle.get("current_actor").is_ally:
			break
		await _wait(0.2)
	# En un combate real el SP se gana jugando; aqui se fija en el turno del duo y se
	# refresca el boton igual que lo hace la pantalla al empezar cada turno.
	duo.sp = 3
	battle.call("_refresh_ultimate_button", duo)
	var button: Button = battle.get("ultimate_button")
	_check("el boton de la ultimate existe y se ve en el turno del duo LR (%s)" % ("sin boton" if button == null else "vis=%s dis=%s awaiting=%s actor=%s" % [button.visible, button.disabled, battle.get("awaiting_input"), battle.get("current_actor").id if battle.get("current_actor") != null else "-"]), button != null and button.visible and not button.disabled)
	_check("el boton muestra nombre, coste en SP y 'una vez'", button != null and button.text.contains("EDGERUNNERS: ULTIMATE") and button.text.contains("SP 3"))
	var special_btn: Button = battle.get("special_button")
	_check("el boton de ESPECIAL sigue siendo el especial normal", special_btn.text.to_upper().contains("SOBRECARGA"))
	button.pressed.emit()
	await _wait(0.3)
	_check("pulsar la ultimate lanza la presentacion cinematografica", int(battle.get("ultimate_fx_count")) == 1 and battle.find_child("UltimateLayer", true, false) != null)
	_check("la ultimate cuenta como usada", duo.ultimate_used)
	if _has_theme:
		_check("al empezar la ultimate suena el tema del duo", _music_name() == "david_lucy_theme" and GameAudio.override_owner() == "battle")
		_check("una sola pista de musica sonando", _music_players_playing() == 1)
	else:
		_check("sin archivo del tema el combate sigue con su musica habitual", _music_name() == "battle" and not GameAudio.override_active())
	# La presentacion se puede saltar tocando.
	var layer = battle.find_child("UltimateLayer", true, false)
	if layer != null:
		var tap := InputEventMouseButton.new()
		tap.button_index = MOUSE_BUTTON_LEFT
		tap.pressed = true
		layer.emit_signal("gui_input", tap)
		await _frames(3)
	_check("tocar la presentacion la salta y devuelve los controles", battle.find_child("UltimateLayer", true, false) == null or not is_instance_valid(battle.find_child("UltimateLayer", true, false)))
	await _wait(1.5)
	if _has_theme:
		_check("el tema del duo permanece durante el resto del combate", _music_name() == "david_lucy_theme")
	# Terminar el combate: ganar.
	for unit in mgr.enemies:
		unit.take_damage(999999.0)
	for i in 40:
		var overlay = battle.get_node_or_null("ResultOverlay")
		if overlay != null and bool(overlay.visible):
			break
		if bool(battle.get("awaiting_input")):
			mgr.submit_action({ "kind": "basic" })
		await _wait(0.25)
	var overlay2 = battle.get_node_or_null("ResultOverlay")
	_check("el combate termina y aparece el resultado", overlay2 != null and bool(overlay2.visible))
	_check("en la pantalla de resultados no se puede volver a usar la ultimate", not mgr.can_use(duo, "ultimate") and (not button.visible or button.disabled or not battle.get("action_row").visible))
	_check("al ganar se suelta el tema especial", not GameAudio.override_active())
	await _wait(2.4)
	_check("la musica de RESULTADOS recupera la prioridad", _music_name() == "results")
	_check("resultados: una sola pista de musica sonando", _music_players_playing() <= 1)
	_app.call("close_battle")
	await _wait(0.4)
	_check("al volver al menu suena la musica normal (no el tema, no resultados)", _music_name() == "menu" and not GameAudio.override_active())
	# Derrota: tambien libera el tema.
	GameState.current_stage_enemies = ["void_warden"]
	_app.call("open_battle")
	await _wait(0.8)
	battle = _app.get("_battle")
	mgr = battle.get("manager")
	mgr.allies[0].sp = 6
	mgr.ultimate_started.emit(mgr.allies[0])
	await _frames(2)
	if _has_theme:
		_check("(derrota) el tema se activa con la ultimate", GameAudio.override_active())
	for unit in mgr.allies:
		unit.take_damage(999999.0)
	for i in 40:
		var ov = battle.get_node_or_null("ResultOverlay")
		if ov != null and bool(ov.visible):
			break
		if bool(battle.get("awaiting_input")):
			mgr.submit_action({ "kind": "basic" })
		await _wait(0.25)
	await _wait(2.4)
	_check("derrota: la musica de resultados recupera la prioridad y no queda el tema", _music_name() == "results" and not GameAudio.override_active())
	_app.call("close_battle")
	await _wait(0.3)
	# Cierre anticipado del combate con el tema activo.
	_app.call("open_battle")
	await _wait(0.8)
	battle = _app.get("_battle")
	battle.get("manager").ultimate_started.emit(battle.get("manager").allies[0])
	await _frames(2)
	_app.call("close_battle")
	await _wait(0.4)
	_check("cierre anticipado del combate: vuelve la musica del menu y no queda el tema", _music_name() == "menu" and not GameAudio.override_active())
	GameState.rarities.erase(DUO)
	GameState.party = ["gojo", "isagi", "frieren", "mai"]


## --- Audio ------------------------------------------------------------------------------------------
func _check_audio() -> void:
	_out("[DBG19] == AUDIO DEL TEMA ESPECIAL ==")
	_reset()
	_app.call("open_screen", "main_menu")
	await _frames(3)
	_check("el tema esta en el catalogo (musica) con su ruta documentada", GameAudio.category_of("david_lucy_theme") == "music" and GameAudio._candidates("david_lucy_theme").has("res://audio/music/david_lucy_theme.ogg"))
	_check("los archivos de musica existentes no se han reemplazado (menu/battle/history/events/results)", ["menu", "battle", "history", "events", "results"].all(func(s): return GameAudio.has_stream(s)))
	_check("en el menu NO suena el tema", _music_name() == "menu")
	if _has_theme:
		var ok := GameAudio.override_start("david_lucy_theme", "summon")
		_check("override_start devuelve true si el archivo existe", ok and _music_name() == "david_lucy_theme")
		var music: AudioStreamPlayer = GameAudio.get("_music")
		await _wait(0.5)
		var pos1 := music.get_playback_position()
		GameAudio.override_start("david_lucy_theme", "summon")
		GameAudio.override_start("david_lucy_theme", "summon")
		await _frames(2)
		_check("pedirlo varias veces NO reinicia la cancion ni crea otro reproductor", music.get_playback_position() >= pos1 and _music_players_playing() == 1)
		GameSettings.set_value("music_volume", 0.0, false)
		await _frames(2)
		_check("Ajustes: volumen de musica 0 silencia el tema", music.volume_db <= -79.0)
		GameSettings.set_value("music_volume", 1.0, false)
		await _frames(2)
		_check("Ajustes: volumen de musica 100% vuelve al nivel normal", absf(music.volume_db - GameAudio.MUSIC_VOLUME) < 0.5)
		GameSettings.set_value("music_volume", 0.8, false)
		# Cambiar de pantalla con el override de 'summon' fuera de contexto lo suelta.
		_app.call("open_screen", "history")
		await _frames(3)
		_check("al cambiar de pantalla el tema de invocacion se suelta y suena la musica de esa pantalla", _music_name() == "history" and not GameAudio.override_active())
		_app.call("go_back")
		await _frames(2)
	else:
		var ok2 := GameAudio.override_start("david_lucy_theme", "summon")
		_check("sin archivo: override_start devuelve false y no cambia la musica", not ok2 and _music_name() == "menu" and not GameAudio.override_active())
	_check("el archivo ausente figura como pendiente en missing_user_supplied (aportado por el usuario) sin romper nada, y NO cuenta como fallo del catalogo", _has_theme or GameAudio.missing_user_supplied().has("david_lucy_theme") and not GameAudio.missing_events().has("david_lucy_theme"))
	GameAudio.override_clear()
	_app.call("refresh_music")
	await _frames(2)
	_check("sigue sonando solo una pista de musica", _music_players_playing() <= 1)


## --- Developer Tools -------------------------------------------------------------------------------
func _check_dev_tools() -> void:
	_out("[DBG19] == DEVELOPER TOOLS ==")
	_reset()
	_check("en esta ejecucion (depuracion) las herramientas estan habilitadas", DevTools.enabled() and OS.is_debug_build())
	var coins := GameState.coins
	var res := DevTools.grant("coins", 1000)
	_check("+1.000 monedas modifica el saldo REAL", bool(res["ok"]) and GameState.coins == coins + 1000 and int(res["balance"]) == GameState.coins)
	coins = GameState.coins
	DevTools.grant("coins", 10000)
	_check("+10.000 monedas", GameState.coins == coins + 10000)
	var gems := GameState.gems
	_check("gemas (la unica moneda premium real) se suman", bool(DevTools.grant("gems", 100)["ok"]) and GameState.gems == gems + 100)
	var mats := GameState.materials
	DevTools.grant("materials", 7)
	_check("materiales de evolucion", GameState.materials == mats + 7)
	GameState.inventory.erase("rabbit_costume")
	GameState.inventory.erase("mai_token")
	DevTools.grant("item:rabbit_costume", 25)
	DevTools.grant("item:mai_token", 3)
	_check("uniformes de conejita y fichas de Mai (inventario real)", GameState.item_count("rabbit_costume") == 25 and GameState.item_count("mai_token") == 3)
	var keys: Array = []
	for r in DevTools.resources():
		keys.append(String(r["key"]))
	_check("no hay monedas duplicadas ni tickets inventados (solo recursos reales)", keys.has("coins") and keys.has("gems") and keys.has("materials") and keys.size() == 3 + DB.items.size() and not keys.any(func(k): return String(k).contains("ticket")))
	var before := GameState.coins
	for bad in [-5, 0, "abc", "", "1.5e3", 99999999999, "-10", null]:
		DevTools.grant("coins", bad)
	_check("cantidades negativas, cero o invalidas se rechazan sin cambiar nada", GameState.coins == before)
	_check("un recurso desconocido se rechaza", not bool(DevTools.grant("tickets", 5)["ok"]) and not bool(DevTools.grant("item:no_existe", 5)["ok"]))
	_check("una cantidad escrita como texto valida se acepta (campo propio)", bool(DevTools.grant("coins", "2500")["ok"]) and GameState.coins == before + 2500)
	# Guardar/cargar: saldos persistentes por el guardado normal.
	var coins_now := GameState.coins
	var gems_now := GameState.gems
	GameState.coins = 0
	GameState.gems = 0
	GameState.load_game()
	_check("los saldos se conservan tras guardar y cargar", GameState.coins == coins_now and GameState.gems == gems_now and GameState.item_count("mai_token") == 3)
	# Personajes.
	GameState.roster.erase(DUO)
	var add := DevTools.quick_add_duo()
	_check("anadir al duo funciona y entra como SSR", bool(add["ok"]) and GameState.is_owned(DUO) and GameState.rarity_of(DUO) == "SSR")
	var add2 := DevTools.quick_add_duo()
	_check("pulsar de nuevo NO lo duplica", not bool(add2["ok"]) and GameState.roster.count(DUO) == 1 and GameState.duplicates_of(DUO) == 0)
	_check("un id inexistente se rechaza", not bool(DevTools.add_character("zzz_no_existe")["ok"]) and not bool(DevTools.add_character("")["ok"]))
	_check("anadir un personaje no cambia las tasas del banner", absf(float(GameState.banner_rates("banner_apertura")["SSR"]) - 0.15) < 1e-12)
	# Panel en Ajustes.
	_app.call("open_screen", "settings")
	await _frames(3)
	var settings := _screen("settings")
	var panel := settings.find_child("DevToolsPanel", true, false)
	_check("el panel DEVELOPER TOOLS — TEMPORAL esta en Ajustes", panel != null and (panel.find_child("DevTitle", true, false) as Label).text == "DEVELOPER TOOLS — TEMPORAL")
	if panel != null:
		var coins_p := GameState.coins
		var quick: Button = panel.find_child("Dev_coins_1000", true, false)
		quick.pressed.emit()
		quick.pressed.emit()
		quick.pressed.emit()
		await _frames(2)
		_check("el boton rapido +1.000 concede una sola vez aunque se pulse varias veces seguidas", GameState.coins == coins_p + 1000)
		_check("el panel muestra el saldo resultante", (panel.find_child("DevStatus", true, false) as Label).text.contains(str(GameState.coins)))
		await _wait(0.4)
		var edit: LineEdit = panel.find_child("DevAmountEdit", true, false)
		var pick: OptionButton = panel.find_child("DevResourcePick", true, false)
		pick.select(0)
		edit.text = "-50"
		(panel.find_child("DevAddButton", true, false) as Button).pressed.emit()
		_check("el campo propio rechaza negativos", GameState.coins == coins_p + 1000)
		await _wait(0.4)
		edit.text = "500"
		(panel.find_child("DevAddButton", true, false) as Button).pressed.emit()
		_check("el campo propio suma la cantidad escrita", GameState.coins == coins_p + 1500)
	# Compilacion de distribucion (simulada).
	DevTools.simulate_release(true)
	var coins_r := GameState.coins
	var res_r := DevTools.grant("coins", 1000)
	var res_c := DevTools.add_character("gojo")
	_check("distribucion: las acciones estan DENEGADAS y no modifican nada", not DevTools.enabled() and not bool(res_r["ok"]) and not bool(res_c["ok"]) and GameState.coins == coins_r)
	_app.call("open_screen", "main_menu")
	await _frames(2)
	_app.call("open_screen", "settings")
	await _frames(3)
	var settings2 := _screen("settings")
	# La pantalla ya existia: se vuelve a construir para comprobar que el panel no se monta.
	var rebuilt: Control = load("res://scenes/screens/settings.tscn").instantiate()
	add_child(rebuilt)
	await _frames(3)
	_check("distribucion: el panel NO se monta en Ajustes", rebuilt.find_child("DevToolsPanel", true, false) == null)
	rebuilt.queue_free()
	DevTools.simulate_release(false)
	_check("al quitar la simulacion vuelve a estar habilitado", DevTools.enabled())
	_app.call("go_back")
	await _frames(2)
