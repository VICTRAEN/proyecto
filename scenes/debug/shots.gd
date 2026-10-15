extends Node

## CAPTURAS DE PANTALLA para revisar el aspecto de cada menu. SOLO para pruebas:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 540x960 -- --shots
## Guarda un PNG por pantalla en user://shots/. Respalda y restaura la partida.

var _app: Node = null


func run(app: Node) -> void:
	_app = app
	DirAccess.make_dir_recursive_absolute("user://shots")
	await _frames(5)
	_app.call("_backup_save")
	GameState.coins = 12840
	GameState.gems = 3200
	GameState.add_item("rabbit_costume", 7)
	GameState.add_item("mai_token", 1)
	GameState.add_character("sakuta_mai_lr")
	GameState.add_character("sakuta")
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.normalize_party()
	GameState.counters["victorias"] = 3
	GameState.counters["combates_jugados"] = 4
	GameState.missions_claimed = { "mis_primera_victoria": true }
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7).split(",")
	for key in ["main_menu", "collection", "team", "summon", "inventory", "evolution", "mutations", "missions", "history", "events", "tower", "shop", "settings", "stage_select"]:
		if not only.is_empty() and not only.has(key):
			continue
		_app.call("open_screen", key)
		await _frames(30)
		_save(key)
		_app.call("go_back")
		await _frames(3)
	if not only.is_empty() and not only.has("battle"):
		_app.call("_restore_save")
		get_tree().quit(0)
		return
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	_app.call("open_battle")
	await _wait(2.0)
	_save("battle")
	_app.call("close_battle")
	_app.call("_restore_save")
	get_tree().quit(0)


func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots/%s.png" % shot_name)
	print("[SHOT] %s %dx%d" % [shot_name, img.get_width(), img.get_height()])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
