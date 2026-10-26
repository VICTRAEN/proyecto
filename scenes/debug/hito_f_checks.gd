extends Node

## COMPROBACIONES EN EJECUCION DEL SISTEMA DE DUPES. SOLO para pruebas.
## Arranque:  godot --path . -- --dbg20   (escribe res://dbg20_resultados.txt)
## Usa las funciones y la ficha REALES del juego. Guarda y restaura el guardado.

const RESULTS_PATH := "res://dbg20_resultados.txt"
const CombatUnit := preload("res://core/combat_unit.gd")
const PANEL_SCENE := preload("res://ui/unit_info_panel.tscn")
const A := "nino"
const B := "nagi"

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
	_out("[DBG20] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _frames(count: int = 2) -> void:
	for i in count:
		await get_tree().process_frame


func _own(id: String, copies: int = 0, level: int = 0) -> void:
	if not GameState.roster.has(id):
		GameState.roster.append(id)
	GameState.progress[id] = { "level": 1, "xp": 0 }
	GameState.rarities.erase(id)
	GameState.duplicates[id] = copies
	if level > 0:
		GameState.dupe_levels[id] = level
	else:
		GameState.dupe_levels.erase(id)


func _snapshot() -> String:
	return JSON.stringify([GameState.duplicates, GameState.dupe_levels])


func run(app: Node) -> void:
	_app = app
	await _frames()
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out("[DBG20] --- comprobaciones de DUPES ---")
	_app.call("_backup_save")
	_check_config()
	_check_obtain()
	_check_upgrade_flow()
	_check_failures()
	_check_combat()
	_check_evolution()
	_check_overflow()
	_check_save_load()
	await _check_ui()
	_check_f2p_sources()
	_app.call("_restore_save")
	_out("[DBG20] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check_config() -> void:
	_out("[DBG20] == CONFIGURACION ==")
	var rules: Dictionary = DB.dupe_rules
	_check("hay 6 niveles (Dupe 0 a 5) y el maximo es 5", GameState.dupe_max_level() == 5 and (rules["levels"] as Array).size() == 6)
	_check("cada mejora cuesta al menos 1 copia y hay una por nivel", (rules["copies_per_level"] as Array).size() == 5 and (rules["copies_per_level"] as Array).all(func(c): return int(c) >= 1))
	var last := 0.0
	var monotone := true
	for lvl in range(1, 6):
		var bonus := float(GameState.dupe_bonus_for_level(lvl).get("atk", 0.0))
		if bonus <= last:
			monotone = false
		last = bonus
	_check("los bonus de ATK crecen en cada nivel", monotone)
	_check("el nivel 0 no da bonus", GameState.dupe_bonus_for_level(0).is_empty() and GameState.dupe_mods_for_level(0).is_empty())
	_check("un nivel fuera de rango no da bonus ni rompe", GameState.dupe_bonus_for_level(99).is_empty() and GameState.dupe_bonus_for_level(-1).is_empty())
	_check("los bonus se leen del archivo de datos (no del codigo)", is_equal_approx(float(GameState.dupe_bonus_for_level(5)["atk"]), float(rules["levels"][5]["atk"])))


func _check_obtain() -> void:
	_out("[DBG20] == OBTENER PERSONAJE NUEVO Y DUPLICADO ==")
	GameState.roster.erase(A)
	GameState.duplicates.erase(A)
	GameState.dupe_levels.erase(A)
	var first := GameState.add_character(A)
	_check("un personaje nuevo entra al roster sin copias", bool(first["added"]) and GameState.is_owned(A) and GameState.dupe_copies_available(A) == 0 and GameState.dupe_level_of(A) == 0)
	var second := GameState.add_character(A)
	_check("la segunda copia NO entra al roster otra vez: es una copia de Dupe", not bool(second["added"]) and bool(second["duplicate"]) and GameState.roster.count(A) == 1)
	_check("la copia queda disponible para ESE personaje", GameState.dupe_copies_available(A) == 1 and GameState.dupe_copies_available(B) == GameState.duplicates_of(B) - 0)
	_check("la copia no sube el Dupe sola", GameState.dupe_level_of(A) == 0)


func _check_upgrade_flow() -> void:
	_out("[DBG20] == MEJORAR DE DUPE 0 A DUPE 5 ==")
	_own(A, 5)
	var prev_atk := GameState.dupe_stat_preview(A, 0, 0)[1]["current"] as float
	var ok_chain := true
	for lvl in range(1, 6):
		var copies_before := GameState.dupe_copies_available(A)
		var rep := GameState.dupe_upgrade(A)
		if not bool(rep.get("done", false)) or GameState.dupe_level_of(A) != lvl or GameState.dupe_copies_available(A) != copies_before - 1:
			ok_chain = false
		var atk := GameState.dupe_stat_preview(A, lvl, lvl)[1]["current"] as float
		if atk <= prev_atk:
			ok_chain = false
		prev_atk = atk
	_check("Dupe 0 > 5: cada mejora consume una copia, sube un nivel y mejora el ATK", ok_chain)
	_check("al terminar quedan 0 copias y Dupe 5", GameState.dupe_copies_available(A) == 0 and GameState.dupe_level_of(A) == 5)
	var st := GameState.dupe_status(A)
	_check("en Dupe 5 el informe avisa del maximo y no permite mejorar", not bool(st["ok"]) and String(st["reason"]).contains("maximo"))
	var base_atk := (GameState.dupe_stat_preview(A, 0, 0)[1]["current"]) as float
	_check("la vista previa de Dupe 5 vale base x (1 + 18%)", absf(prev_atk - base_atk * 1.18) < 0.01)
	var data := GameState.character_data(A)
	_check("el Dupe no cambia el nivel de combate ni la rareza", int(data["level"]) == 1 and String(data["rarity"]) == String(DB.get_character(A)["rarity"]) and not bool(data["evolved"]))


func _check_failures() -> void:
	_out("[DBG20] == OPERACIONES INVALIDAS ==")
	_own(A, 0)
	var snap := _snapshot()
	var none := GameState.dupe_upgrade(A)
	_check("mejorar sin copias se rechaza y no cambia nada", not bool(none["done"]) and _snapshot() == snap and String(none["reason"]).contains("Faltan copias"))
	_own(A, 5, 5)
	snap = _snapshot()
	var over := GameState.dupe_upgrade(A)
	_check("superar Dupe 5 se rechaza y no cambia nada", not bool(over["done"]) and _snapshot() == snap and GameState.dupe_level_of(A) == 5)
	snap = _snapshot()
	var ghost := GameState.dupe_upgrade("id_que_no_existe")
	_check("un personaje inexistente se rechaza", not bool(ghost["done"]) and _snapshot() == snap)
	GameState.roster.erase(B)
	var unowned := GameState.dupe_upgrade(B)
	_check("un personaje que no se tiene se rechaza", not bool(unowned["done"]) and GameState.dupe_level_of(B) == 0)
	# Copias de A no sirven para B.
	_own(A, 3)
	_own(B, 0)
	var other := GameState.dupe_upgrade(B)
	_check("las copias de un personaje no mejoran a otro", not bool(other["done"]) and GameState.dupe_level_of(B) == 0 and GameState.dupe_copies_available(A) == 3)
	# Una sola copia no se puede consumir dos veces.
	_own(A, 1)
	var first := GameState.dupe_upgrade(A)
	var again := GameState.dupe_upgrade(A)
	_check("la misma copia no se consume dos veces", bool(first["done"]) and not bool(again["done"]) and GameState.dupe_level_of(A) == 1 and GameState.dupe_copies_available(A) == 0)


func _check_combat() -> void:
	_out("[DBG20] == EFECTO REAL EN COMBATE ==")
	_own(A, 5, 3)
	var data := GameState.character_data(A)
	var unit := CombatUnit.new()
	unit.setup(data, true, 0)
	var base_atk := unit.base_stat("atk")
	var expected := base_atk * 1.09
	_check("ATK en combate = base x (1 + bonus Dupe 3)", absf(unit.attack() - expected) < 0.01)
	_check("HP y DEF tambien suben", absf(unit.max_hp() - unit.base_stat("max_hp") * 1.09) < 0.01 and absf(unit.defense() - unit.base_stat("def") * 1.09) < 0.01)
	_check("la base se mantiene separada (base_stat no incluye el bonus)", absf(base_atk - float(DB.get_character(A)["stats"]["atk"])) < 0.01)
	# Sin acumulacion al reconstruir muchas veces o reaplicar.
	var again := CombatUnit.new()
	for i in 5:
		again.setup(GameState.character_data(A), true, 0)
		GameState.apply_dupe_mods(again.stats, A)
	_check("reconstruir y reaplicar el Dupe 5 veces NO acumula", absf(again.attack() - expected) < 0.01)
	var count := 0
	for mod in again.stats.active_mods():
		if String(mod["source"]) == "dupe" and String(mod["stat"]) == "atk":
			count += 1
	_check("hay un unico modificador de Dupe por estadistica", count == 1)
	# Otros personajes no se ven afectados.
	var other := CombatUnit.new()
	other.setup(GameState.character_data(B), true, 1)
	_check("otro personaje sin Dupe no cambia", absf(other.attack() - other.base_stat("atk")) < 0.01)
	# Motor de combate real.
	var BM := load("res://core/battle_manager.gd")
	var mgr: Node = BM.new()
	add_child(mgr)
	mgr.setup([GameState.character_data(A)], [DB.get_enemy("void_warden")], [GameState.character_data(A)])
	var in_mgr = mgr.allies[0]
	_check("el motor de combate usa el bonus de Dupe (activo)", absf(in_mgr.attack() - expected) < 0.01)
	_check("las reservas tambien lo llevan", absf((mgr.reserves[0]).attack() - expected) < 0.01)
	mgr.queue_free()
	# Un enemigo no recibe Dupes.
	var foe := CombatUnit.new()
	foe.setup(DB.get_enemy("void_warden"), false, 0)
	_check("un enemigo no tiene modificadores de Dupe", foe.stats.active_mods().all(func(m): return String(m["source"]) != "dupe"))
	# La ficha (BASE/ACTUAL) lee el mismo numero.
	var panel_unit := CombatUnit.new()
	panel_unit.setup(GameState.character_data(A), true, -1)
	_check("la ficha (vista previa) muestra el mismo ATK que el combate", absf(panel_unit.attack() - expected) < 0.01)


func _check_evolution() -> void:
	_out("[DBG20] == EVOLUCION CON DUPES ==")
	var id := "gojo"
	_own(id, 4, 3)
	GameState.progress[id] = { "level": 100, "xp": 0 }
	GameState.coins = 1000000
	var before := GameState.character_data(id)
	var evo := GameState.evolve(id)
	_check("Gojo evoluciona a UR por las reglas normales", not evo.is_empty() and GameState.rarity_of(id) == "UR")
	_check("el nivel de Dupe y las copias se conservan al evolucionar", GameState.dupe_level_of(id) == 3 and GameState.dupe_copies_available(id) == 1)
	var after := CombatUnit.new()
	after.setup(GameState.character_data(id), true, 0)
	var expect := after.base_stat("atk") * 1.09
	_check("tras evolucionar el bonus sigue siendo UN solo +9% (no se duplica)", absf(after.attack() - expect) < 0.01)
	_check("el Dupe no salta los requisitos de evolucion (sigue pidiendo nivel)", not bool(GameState.can_evolve(id)["ok"]) or GameState.level_of(id) >= 100)
	# Ruta especial Sakuta/Mai -> Sakuta
	GameState.roster.erase("sakuta")
	_own("sakuta_mai", 3, 2)
	GameState.progress["sakuta_mai"] = { "level": 100, "xp": 0 }
	GameState.inventory["rabbit_costume"] = 25
	GameState.rarities.erase("sakuta_mai")
	var special := GameState.evolve_special("sakuta_mai")
	_check("la evolucion especial Sakuta/Mai se ejecuta", not special.is_empty() and GameState.is_owned("sakuta"))
	_check("los Dupes pasan a la forma nueva y la vieja no los conserva", GameState.dupe_level_of("sakuta") == 2 and GameState.duplicates_of("sakuta") >= 3 and GameState.dupe_level_of("sakuta_mai") == 0 and not GameState.dupe_levels.has("sakuta_mai"))
	GameState.roster.erase("sakuta")
	GameState.roster.erase("sakuta_mai")
	GameState.rarities.erase("sakuta")
	GameState.dupe_levels.erase("sakuta")
	GameState.rarities.erase(id)
	# Fusion con costes DISTINTOS (se prueba con una tabla temporal): ninguna copia se pierde.
	var saved_costs = DB.dupe_rules.get("copies_per_level", [])
	DB.dupe_rules["copies_per_level"] = [1, 2, 3, 4, 5]
	_check("fusion con costes distintos: 0 copias gastadas -> Dupe 0", GameState._dupe_level_for_budget(0) == 0)
	_check("fusion con costes distintos: 2 copias gastadas -> Dupe 1 (no alcanza el 2)", GameState._dupe_level_for_budget(2) == 1)
	_check("fusion con costes distintos: 3 copias gastadas -> Dupe 2", GameState._dupe_level_for_budget(3) == 2)
	_check("fusion con costes distintos: presupuesto enorme -> tope Dupe 5", GameState._dupe_level_for_budget(1000) == 5)
	DB.dupe_rules["copies_per_level"] = saved_costs
	_check("con costes uniformes el nivel fusionado equivale a sumar niveles (con tope)", GameState._dupe_level_for_budget(3) == 3 and GameState._dupe_level_for_budget(9) == 5)


func _check_overflow() -> void:
	_out("[DBG20] == COPIAS SOBRANTES (TRAS DUPE 5) ==")
	var rate := GameState.dupe_overflow_rate()
	_check("la conversion de sobrantes esta configurada en rules.json (>0)", rate > 0)
	GameState.coins = 0
	_own(B, 4, 1)
	_own(A, 4, 2)
	_check("antes del Dupe maximo no hay copias sobrantes (todas sirven para mejorar)", GameState.dupe_overflow_copies(A) == 0)
	var before := _snapshot()
	var refuse := GameState.dupe_convert_overflow(A)
	_check("convertir antes del maximo se rechaza y no cambia nada", not bool(refuse["done"]) and _snapshot() == before and GameState.coins == 0)
	_own(A, 5, 5)
	var none := GameState.dupe_convert_overflow(A)
	_check("en Dupe 5 sin copias de mas no hay nada que convertir", not bool(none["done"]) and GameState.coins == 0 and GameState.duplicates_of(A) == 5)
	_own(A, 8, 5)
	var b_before := JSON.stringify([GameState.duplicates_of(B), GameState.dupe_level_of(B), GameState.dupe_copies_available(B)])
	_check("en Dupe 5 las copias extra son sobrantes", GameState.dupe_overflow_copies(A) == 3)
	_check("las copias de OTRO personaje no cuentan como sobrantes de este", GameState.dupe_overflow_copies(B) == 0)
	var done := GameState.dupe_convert_overflow(A)
	_check("convertir da monedas por cada sobrante (3 x tasa)", bool(done["done"]) and GameState.coins == 3 * rate)
	_check("el Dupe 5 y las copias YA GASTADAS no se tocan", GameState.dupe_level_of(A) == 5 and GameState.duplicates_of(A) == 5 and GameState.dupe_copies_available(A) == 0)
	_check("no se modifica a ningun otro personaje", JSON.stringify([GameState.duplicates_of(B), GameState.dupe_level_of(B), GameState.dupe_copies_available(B)]) == b_before)
	var again := GameState.dupe_convert_overflow(A)
	_check("una segunda conversion no cobra dos veces", not bool(again["done"]) and GameState.coins == 3 * rate)
	# Conversion desactivada por datos.
	_own(A, 7, 5)
	var saved_overflow = DB.dupe_rules.get("overflow", {})
	DB.dupe_rules["overflow"] = {}
	var coins_before := GameState.coins
	var off := GameState.dupe_convert_overflow(A)
	_check("con coins_per_copy desactivado no se convierte (y las copias se conservan)", not bool(off["done"]) and GameState.coins == coins_before and GameState.duplicates_of(A) == 7)
	DB.dupe_rules["overflow"] = saved_overflow
	_own(A, 0, 0)
	_own(B, 0, 0)


func _check_save_load() -> void:
	_out("[DBG20] == GUARDAR Y CARGAR ==")
	_own(A, 4, 2)
	GameState.save_game()
	GameState.dupe_levels = {}
	GameState.duplicates[A] = 0
	GameState.load_game()
	_check("el nivel de Dupe y las copias sobreviven a guardar/cargar", GameState.dupe_level_of(A) == 2 and GameState.duplicates_of(A) == 4 and GameState.dupe_copies_available(A) == 2)
	var unit := CombatUnit.new()
	unit.setup(GameState.character_data(A), true, 0)
	var expect := unit.base_stat("atk") * 1.06
	GameState.save_game()
	GameState.load_game()
	GameState.load_game()
	var unit2 := CombatUnit.new()
	unit2.setup(GameState.character_data(A), true, 0)
	_check("cargar varias veces no acumula el bonus", absf(unit2.attack() - expect) < 0.01)
	# Guardado ANTIGUO sin dupe_levels.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	(parsed as Dictionary).erase("dupe_levels")
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(parsed))
	f.close()
	GameState.load_game()
	_check("una partida antigua sin Dupes carga: nivel 0 y sus duplicados pasan a ser copias", GameState.dupe_level_of(A) == 0 and GameState.duplicates_of(A) == 4 and GameState.dupe_copies_available(A) == 4)
	# Guardado manipulado: nivel fuera de rango y mas niveles que copias.
	(parsed as Dictionary)["dupe_levels"] = { A: 99, "no_existe": 3 }
	(parsed as Dictionary)["duplicates"][A] = 1
	f = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(parsed))
	f.close()
	GameState.load_game()
	_check("un nivel fuera de rango se recorta al maximo y se ignoran ids inexistentes", GameState.dupe_level_of(A) == 5 and not GameState.dupe_levels.has("no_existe"))
	_check("nunca quedan menos copias que las que pagan el nivel (no se pierde ni se regala nada)", GameState.duplicates_of(A) >= 5 and GameState.dupe_copies_available(A) == GameState.duplicates_of(A) - 5)
	GameState.dupe_levels.erase(A)


func _check_ui() -> void:
	_out("[DBG20] == INTERFAZ: PESTANA DUPES ==")
	_own(A, 2, 1)
	var panel: Node = PANEL_SCENE.instantiate()
	add_child(panel)
	await _frames(2)
	panel.call("open_for_data", GameState.character_data(A))
	await _frames(3)
	var tabs: TabContainer = panel.get("tabs")
	var tab_titles: Array = []
	for i in tabs.get_tab_count():
		tab_titles.append(tabs.get_tab_title(i))
	_check("la ficha tiene la pestana DUPES", tab_titles.has("DUPES"))
	var root: Node = panel.get("tab_dupes")
	var label: Label = root.find_child("DupeLevelLabel", true, false)
	_check("muestra el nivel actual y el maximo (DUPE 1 / 5)", label != null and label.text == "DUPE 1 / 5")
	var pips: Node = root.find_child("DupePips", true, false)
	_check("muestra 5 pips de progreso", pips != null and pips.get_child_count() == 5)
	var copies_chip: Node = root.find_child("DupeCopies", true, false)
	_check("muestra las copias disponibles", copies_chip != null and _text_of(copies_chip).contains("1"))
	_check("muestra la tabla de estadisticas con vista previa", root.find_child("DupeStats", true, false) != null)
	var button: Button = root.find_child("DupeUpgradeButton", true, false)
	_check("hay un boton funcional de consumir (activo con copias)", button != null and not button.disabled)
	var level_before := GameState.dupe_level_of(A)
	button.pressed.emit()
	await _frames(2)
	root = panel.get("tab_dupes")
	_check("pulsarlo pide CONFIRMACION y no gasta nada todavia", root.find_child("DupeConfirmButton", true, false) != null and GameState.dupe_level_of(A) == level_before)
	(root.find_child("DupeCancelButton", true, false) as Button).pressed.emit()
	await _frames(2)
	_check("CANCELAR no consume nada", GameState.dupe_level_of(A) == level_before and GameState.dupe_copies_available(A) == 1)
	root = panel.get("tab_dupes")
	(root.find_child("DupeUpgradeButton", true, false) as Button).pressed.emit()
	await _frames(2)
	root = panel.get("tab_dupes")
	var confirm: Button = root.find_child("DupeConfirmButton", true, false)
	confirm.pressed.emit()
	confirm.pressed.emit()
	await _frames(3)
	_check("CONFIRMAR consume UNA copia (aunque se pulse dos veces) y sube a Dupe 2", GameState.dupe_level_of(A) == 2 and GameState.dupe_copies_available(A) == 0)
	root = panel.get("tab_dupes")
	label = root.find_child("DupeLevelLabel", true, false)
	_check("la interfaz se actualiza al instante (DUPE 2 / 5)", label != null and label.text == "DUPE 2 / 5")
	var empty_button: Button = root.find_child("DupeUpgradeButton", true, false)
	_check("sin copias el boton queda desactivado y lo explica", empty_button != null and empty_button.disabled and root.find_child("DupeMessage", true, false) != null)
	# Dupe maximo
	_own(A, 5, 5)
	panel.call("open_for_data", GameState.character_data(A))
	await _frames(3)
	root = panel.get("tab_dupes")
	var maxed: Label = root.find_child("DupeMessage", true, false)
	_check("en Dupe 5 se avisa del maximo y no hay boton de mejora", maxed != null and maxed.text.contains("MAXIMO") and root.find_child("DupeUpgradeButton", true, false) == null)
	# Copias sobrantes en Dupe 5: boton de convertir con confirmacion.
	_own(A, 7, 5)
	GameState.coins = 0
	panel.call("open_for_data", GameState.character_data(A))
	await _frames(3)
	root = panel.get("tab_dupes")
	var convert: Button = root.find_child("DupeConvertButton", true, false)
	_check("en Dupe 5 con copias de mas aparece el boton de convertir", convert != null and not convert.disabled and convert.text.contains("2"))
	convert.pressed.emit()
	await _frames(2)
	root = panel.get("tab_dupes")
	_check("convertir pide CONFIRMACION y no cobra todavia", root.find_child("DupeConfirmButton", true, false) != null and GameState.coins == 0 and GameState.duplicates_of(A) == 7)
	(root.find_child("DupeCancelButton", true, false) as Button).pressed.emit()
	await _frames(2)
	_check("CANCELAR la conversion no cambia nada", GameState.coins == 0 and GameState.duplicates_of(A) == 7)
	root = panel.get("tab_dupes")
	(root.find_child("DupeConvertButton", true, false) as Button).pressed.emit()
	await _frames(2)
	root = panel.get("tab_dupes")
	var convert_ok: Button = root.find_child("DupeConfirmButton", true, false)
	convert_ok.pressed.emit()
	convert_ok.pressed.emit()
	await _frames(3)
	_check("CONFIRMAR convierte una sola vez (aunque se pulse dos veces)", GameState.coins == 2 * GameState.dupe_overflow_rate() and GameState.duplicates_of(A) == 5)
	root = panel.get("tab_dupes")
	_check("tras convertir la interfaz ya no ofrece el boton", root.find_child("DupeConvertButton", true, false) == null and root.find_child("DupeMessage", true, false) != null)
	_own(A, 0, 0)
	panel.queue_free()


func _text_of(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text
	for child in node.get_children():
		out += _text_of(child)
	return out


func _check_f2p_sources() -> void:
	_out("[DBG20] == FUENTES (F2P, TIENDA, EVENTOS) E INVOCACIONES ==")
	GameState.roster.erase("sakuta_mai")
	GameState.duplicates.erase("sakuta_mai")
	GameState.dupe_levels.erase("sakuta_mai")
	GameState._grant_shop_reward({ "type": "character", "character_id": "sakuta_mai" })
	GameState._grant_shop_reward({ "type": "character", "character_id": "sakuta_mai" })
	_check("un F2P repetido por una recompensa genera una copia de Dupe, sin pago", GameState.is_owned("sakuta_mai") and GameState.dupe_copies_available("sakuta_mai") == 1)
	var up := GameState.dupe_upgrade("sakuta_mai")
	_check("el personaje F2P se puede mejorar con esa copia", bool(up["done"]) and GameState.dupe_level_of("sakuta_mai") == 1)
	GameState.roster.erase("sakuta_mai")
	GameState.dupe_levels.erase("sakuta_mai")
	GameState.duplicates.erase("sakuta_mai")
	# Invocaciones siguen funcionando y cuentan copias.
	GameState.gems = 100000
	GameState.pending_reveal = {}
	var gems_before := GameState.gems
	var report := GameState.summon("banner_apertura", 10)
	_check("la invocacion x10 sigue funcionando (10 resultados, coste una vez)", bool(report["ok"]) and (report["results"] as Array).size() == 10 and gems_before - GameState.gems == 90)
	var total_dups := 0
	for entry in report["results"]:
		if bool((entry as Dictionary).get("duplicate", false)):
			total_dups += 1
	_check("los repetidos de la invocacion se cuentan como copias de Dupe", total_dups == int(report["duplicate_count"]))
