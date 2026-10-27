extends Node

## COMPROBACIONES EN EJECUCION DEL COMBATE: AUTO Y VELOCIDAD (v10). SOLO para pruebas.
## Arranque:  godot --path . -- --dbg22   (escribe res://dbg22_resultados.txt)
## Abre un combate REAL (escena, BattleManager y botones reales) y pulsa los botones.

const RESULTS_PATH := "res://dbg22_resultados.txt"

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
	_out("[DBG22] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Espera (max `limit` s) a que la condicion sea cierta.
func _until(cond: Callable, limit: float = 20.0) -> bool:
	var waited := 0.0
	while waited < limit:
		if cond.call():
			return true
		await _wait(0.1)
		waited += 0.1
	return cond.call()


func run(app: Node) -> void:
	_app = app
	await _wait(0.3)
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out("[DBG22] --- comprobaciones de AUTO y VELOCIDAD en combate ---")
	_app.call("_backup_save")
	GameSettings.set_value("battle_speed", "normal", false)
	GameSettings.set_value("anim_speed", "normal", false)
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.normalize_party()
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	_app.call("open_battle")
	await _wait(0.8)
	var battle = _app.get("_battle")
	_check("el combate se abre", battle != null)
	if battle == null:
		_finish()
		return
	var mgr = battle.get("manager")
	var auto_btn: Button = battle.get("auto_button")
	var speed_btn: Button = battle.get("speed_button")
	_check("existen los botones AUTO y VELOCIDAD", auto_btn != null and speed_btn != null)
	_check("AUTO empieza apagado en cada batalla", not bool(mgr.get("auto_mode")) and auto_btn.text == "AUTO NO")
	_check("la velocidad empieza en x1", speed_btn.text == "x1" and is_equal_approx(float(mgr.get("pause_scale")), 1.0))

	# --- velocidad: cambia el ajuste, la pausa del combate EN VIVO y se restaura
	speed_btn.pressed.emit()
	_check("x2: el ajuste battle_speed pasa a 'fast'", GameSettings.choice("battle_speed") == "fast" and GameSettings.choice("anim_speed") == "fast")
	_check("x2: el combate en curso usa pausas mas cortas", float(mgr.get("pause_scale")) < 0.7 and speed_btn.text == "x2")
	speed_btn.pressed.emit()
	_check("x1 otra vez: vuelve a pausas normales", is_equal_approx(float(mgr.get("pause_scale")), 1.0) and speed_btn.text == "x1")

	# --- manual: el combate espera al jugador
	var waiting := await _until(func(): return bool(battle.get("awaiting_input")))
	_check("sin AUTO el combate espera la accion del jugador", waiting)

	# --- AUTO activado justo cuando se espera al jugador: la accion se resuelve sola
	var resolved := [0]
	mgr.action_resolved.connect(func(_p): resolved[0] += 1)
	auto_btn.pressed.emit()
	_check("AUTO SI: el boton cambia y el modo se activa", bool(mgr.get("auto_mode")) and auto_btn.text == "AUTO SI")
	var before: int = resolved[0]
	var moved := await _until(func(): return resolved[0] >= before + 4, 30.0)
	_check("con AUTO los turnos de los aliados se resuelven sin pulsar nada (%d acciones)" % (resolved[0] - before), moved)

	# --- apagar AUTO devuelve el control
	auto_btn.pressed.emit()
	_check("AUTO NO: el modo se apaga", not bool(mgr.get("auto_mode")) and auto_btn.text == "AUTO NO")
	var back := await _until(func(): return bool(battle.get("awaiting_input")), 30.0)
	_check("al apagar AUTO el combate vuelve a esperar al jugador", back)

	# --- AUTO lleva el combate hasta el resultado (enemigos casi muertos, modo rapido)
	for e in mgr.enemies:
		(e as Object).call("take_damage", maxf(0.0, float(e.get("hp")) - 30.0))
	speed_btn.pressed.emit()
	auto_btn.pressed.emit()
	var overlay: Control = battle.get("result_overlay")
	var done := await _until(func(): return overlay.visible, 60.0)
	_check("con AUTO el combate llega solo a la pantalla de resultado", done)
	_check("al llegar el resultado los botones de AUTO/velocidad se apartan", not (battle.get("_tools_row") as Control).visible)
	var alive := 0
	for a in mgr.allies:
		if a.get("alive"):
			alive += 1
	_check("el resultado es victoria (quedan aliados vivos: %d)" % alive, alive > 0)
	_app.call("close_battle")
	await _wait(0.4)

	# --- la siguiente batalla empieza con AUTO apagado, y la velocidad se conserva
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	_app.call("open_battle")
	await _wait(0.8)
	var battle2 = _app.get("_battle")
	_check("otra batalla: AUTO vuelve a empezar apagado", battle2 != null and not bool((battle2.get("manager")).get("auto_mode")))
	_check("otra batalla: la velocidad elegida (x2) se conserva", (battle2.get("speed_button") as Button).text == "x2")
	_app.call("close_battle")
	await _wait(0.3)
	GameSettings.set_value("battle_speed", "normal", false)
	GameSettings.set_value("anim_speed", "normal", false)
	await _check_team_sort()
	_check_safe_save()
	# Los botones guardan el ajuste: se deja como estaba (normal) y se guarda.
	GameSettings.set_value("battle_speed", "normal")
	GameSettings.set_value("anim_speed", "normal")
	_finish()


## Selector de ORDEN de la pantalla Equipo (pantalla real, tarjetas reales).
func _check_team_sort() -> void:
	_out("[DBG22] == EQUIPO: ORDEN DE LA LISTA ==")
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.normalize_party()
	GameState.rarities.erase("frieren")
	for id in ["makima", "yuno", "denji", "asta"]:
		if not GameState.roster.has(id):
			GameState.roster.append(id)
			GameState.progress[id] = { "level": 1, "xp": 0 }
	GameState.progress["denji"] = { "level": 7, "xp": 0 }
	var team: Node = load("res://scenes/screens/team.tscn").instantiate()
	add_child(team)
	await _wait(0.3)
	team.call("refresh")
	await _wait(0.2)
	var sel: OptionButton = team.find_child("SortOption", true, false)
	_check("la pantalla Equipo tiene el selector de orden", sel != null and sel.item_count == 4)
	if sel == null:
		team.queue_free()
		return
	var pool: Node = team.get("pool")
	var VI := preload("res://ui/visual_identity.gd")
	var n_roster: int = GameState.roster_data().size()
	_check("la lista muestra a TODOS los personajes (%d) sin duplicar ni perder" % n_roster, pool.get_child_count() == n_roster)
	var ranks: Array = []
	for c in pool.get_children():
		ranks.append(VI.rarity_rank(String((c.get("data") as Dictionary).get("rarity", "R"))))
	var sorted_ok := true
	for i in range(1, ranks.size()):
		if ranks[i] > ranks[i - 1]:
			sorted_ok = false
	_check("orden por RAREZA: de mejor a peor", sorted_ok)
	sel.select(1)
	sel.item_selected.emit(1)
	await _wait(0.2)
	var levels: Array = []
	for c in pool.get_children():
		levels.append(int((c.get("data") as Dictionary).get("level", 1)))
	var lv_ok := levels.size() > 1
	for i in range(1, levels.size()):
		if levels[i] > levels[i - 1]:
			lv_ok = false
	_check("orden por NIVEL: de mayor a menor (primero %d)" % (levels[0] if levels.size() > 0 else 0), lv_ok and levels[0] == 7)
	sel.select(2)
	sel.item_selected.emit(2)
	await _wait(0.2)
	var names: Array = []
	for c in pool.get_children():
		names.append(String((c.get("data") as Dictionary).get("name", "")))
	var sorted_names := names.duplicate()
	sorted_names.sort()
	_check("orden por NOMBRE: alfabetico", names == sorted_names)
	_check("cambiar el orden no toca el equipo", GameState.party == ["gojo", "isagi", "frieren", "mai"])
	sel.select(0)
	sel.item_selected.emit(0)
	team.queue_free()
	await _wait(0.1)


## Guardado seguro: temporal + copia .bak + recuperacion de un guardado roto.
func _check_safe_save() -> void:
	_out("[DBG22] == GUARDADO SEGURO ==")
	var path: String = GameState.SAVE_PATH
	var coins_backup: int = GameState.coins
	GameState.coins = 4242
	GameState.save_game()
	GameState.coins = 4343
	GameState.save_game()
	_check("el guardado se escribe sin dejar el temporal (.tmp) atras", FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp"))
	_check("existe la copia .bak con el guardado anterior", FileAccess.file_exists(path + ".bak"))
	var bak = JSON.parse_string(FileAccess.get_file_as_string(path + ".bak"))
	_check("la copia .bak es el guardado anterior (4242), el principal el actual (4343)", bak is Dictionary and int(bak.get("coins", 0)) == 4242 and int(JSON.parse_string(FileAccess.get_file_as_string(path)).get("coins", 0)) == 4343)
	# Simula una escritura cortada: el principal queda a medias.
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{ \"version\": 3, \"coins\": 99")
	broken.close()
	GameState.coins = 1
	var ok: bool = GameState.load_game()
	_check("con el guardado ROTO se recupera la copia anterior (monedas 4242)", ok and GameState.coins == 4242)
	GameState.save_game()
	_check("tras recuperar, el siguiente guardado repara el principal", JSON.parse_string(FileAccess.get_file_as_string(path)) is Dictionary)
	# Un guardado roto SIN copia sigue ignorandose (como antes) y no revienta.
	GameState.delete_save()
	_check("delete_save borra principal, .bak y .tmp", not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak") and not FileAccess.file_exists(path + ".tmp"))
	var junk := FileAccess.open(path, FileAccess.WRITE)
	junk.store_string("basura")
	junk.close()
	_check("guardado roto y sin copia: se ignora sin error (false)", not GameState.load_game())
	GameState.delete_save()
	GameState.coins = coins_backup


func _finish() -> void:
	_app.call("_restore_save")
	_out("[DBG22] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
