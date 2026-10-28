extends Node

## CAPTURAS de las COPIAS (v8) para REVISION VISUAL. SOLO pruebas:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 540x960 -- --shots-g
## Guarda PNG en user://shots_g/. Respalda y restaura la partida.

var _app: Node = null


func run(app: Node) -> void:
	_app = app
	DirAccess.make_dir_recursive_absolute("user://shots_g")
	await _frames(5)
	_app.call("_backup_save")
	GameState.pending_reveal = {}
	# Gojo UR con tres copias SSR y David & Lucy LR con una.
	for id in ["gojo", "david_lucy_duo"]:
		if not GameState.roster.has(id):
			GameState.roster.append(id)
		GameState.progress[id] = { "level": 1, "xp": 0 }
	GameState.rarities["gojo"] = "UR"
	GameState.duplicates["gojo"] = 3
	GameState.dupe_levels.erase("gojo")
	GameState.rarities["david_lucy_duo"] = "LR"
	GameState.duplicates["david_lucy_duo"] = 1
	GameState.dupe_levels.erase("david_lucy_duo")
	_app.call("open_screen", "collection")
	await _frames(30)
	_save("01_coleccion_copias")
	_app.call("open_screen", "inventory")
	await _frames(25)
	var inv = _app.get("_screens")["inventory"]
	inv.set("_category", "copies")
	inv.call("refresh")
	await _frames(15)
	_save("02_inventario_copias")
	# v11: 12 copias del duo (unidad SSR + 11) y las pantallas de Evolucion/Mutaciones.
	GameState.rarities.erase("david_lucy_duo")
	GameState.duplicates["david_lucy_duo"] = 11
	_app.call("open_screen", "collection")
	await _frames(30)
	_save("03_coleccion_duo_12")
	for id in ["gojo", "isagi", "frieren", "goku", "makima"]:
		if not GameState.roster.has(id):
			GameState.roster.append(id)
		GameState.progress[id] = { "level": 60, "xp": 0 }
	GameState.coins = 500000
	_app.call("open_screen", "evolution")
	await _frames(30)
	_save("04_evolucion")
	_app.call("open_screen", "mutations")
	await _frames(30)
	_save("05_mutaciones")
	_app.call("_restore_save")
	get_tree().quit()


func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots_g/%s.png" % shot_name)
	print("[SHOT] %s %dx%d" % [shot_name, img.get_width(), img.get_height()])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
