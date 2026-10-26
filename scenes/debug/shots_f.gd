extends Node

## CAPTURAS del sistema de DUPES para REVISION VISUAL. SOLO pruebas:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 540x960 -- --shots-f
## Guarda PNG en user://shots_f/. Respalda y restaura la partida. Son capturas de
## ESCRITORIO a 540x960 (viewport del proyecto 1080x1920 reducido), no pruebas en movil real.

const ID := "gojo"
var _app: Node = null


func run(app: Node) -> void:
	_app = app
	DirAccess.make_dir_recursive_absolute("user://shots_f")
	await _frames(5)
	_app.call("_backup_save")
	GameState.pending_reveal = {}
	GameState.coins = 2000000
	GameState.gems = 5000
	GameState.add_character(ID)
	GameState.dupe_levels.erase(ID)

	# 1) Sin copias (Dupe 0, ninguna repeticion; `duplicates` cuenta SOLO las copias extra)
	GameState.duplicates[ID] = 0
	await _ficha("01_sin_copias")

	# 2) Con copias disponibles (Dupe 0, 3 copias extra)
	GameState.duplicates[ID] = 4
	await _ficha("02_con_copias")

	# 3) Pidiendo confirmacion
	var panel = await _open_ficha()
	panel.call("_on_dupe_ask")
	await _frames(8)
	_save("03_confirmacion")
	# 4) Confirmar -> Dupe 1
	panel.call("_on_dupe_confirm")
	await _frames(10)
	_save("04_tras_confirmar_dupe1")
	_close(panel)

	# 5) Dupe 4 con copia -> siguiente es el Dupe 5 (bono especial de critico)
	GameState.dupe_levels[ID] = 4
	GameState.duplicates[ID] = 4 + 2
	await _ficha("05_dupe4_con_copias")

	# 6) Maximo
	GameState.dupe_levels[ID] = 5
	GameState.duplicates[ID] = 5 + 3
	await _ficha("06_maximo_con_sobrantes")
	var pm = await _open_ficha()
	pm.call("_on_dupe_ask")
	await _frames(8)
	_save("06b_convertir_confirmacion")
	pm.call("_on_dupe_confirm")
	await _frames(10)
	_save("06c_tras_convertir")
	_close(pm)

	# 7) Forma UR del mismo personaje conserva los Dupes
	GameState.rarities[ID] = "UR"
	await _ficha("07_ur_conserva_dupes")
	GameState.rarities.erase(ID)

	# 8) Datos de la ficha (para ver la pestana DATOS con el bono aplicado) y la barra de pestanas
	GameState.dupe_levels[ID] = 3
	GameState.duplicates[ID] = 3
	await _ficha("08_dupe3_sin_copias_extra")
	var p2 = await _open_ficha(0)
	_save("09_datos_con_dupe3")
	_close(p2)

	# 9) En combate: solo lectura (sin boton de mejora)
	GameState.party = [ID, "mai", "", ""]
	GameState.normalize_party()
	GameState.current_stage_enemies = ["void_warden"]
	GameState.battle_source = GameState.BATTLE_STAGE
	GameState.battle_party = []
	_app.call("open_battle")
	await _wait(1.0)
	var battle = _app.get("_battle")
	var mgr = battle.get("manager")
	for i in 60:
		if bool(battle.get("awaiting_input")) and battle.get("current_actor") != null and battle.get("current_actor").is_ally:
			break
		await _wait(0.2)
	var ip = battle.get("info_panel")
	if ip == null:
		ip = battle.find_child("UnitInfoPanel", true, false)
	if ip != null and mgr != null:
		ip.call("open_for", mgr.allies[0], true)
		await _frames(10)
		ip.tabs.current_tab = 5
		await _frames(10)
		_save("10_en_combate_solo_lectura")
		ip.call("close_panel")
	else:
		print("[SHOT] AVISO: no se encontro el panel de info en combate")
	_app.call("close_battle")
	await _frames(5)

	_app.call("_restore_save")
	get_tree().quit(0)


func _open_ficha(tab: int = 5) -> Node:
	_app.call("open_screen", "collection")
	await _frames(25)
	var col = _app.get("_screens")["collection"]
	col.call("_on_card_pressed", GameState.character_data(ID))
	await _frames(30)
	var panel = col.get("info_panel")
	panel.tabs.current_tab = tab
	await _frames(10)
	return panel


func _close(panel: Node) -> void:
	if panel != null and panel.has_method("close_panel"):
		panel.call("close_panel")
	_app.call("go_back")
	await _frames(3)


func _ficha(shot_name: String) -> void:
	var panel = await _open_ficha()
	_save(shot_name)
	await _close(panel)


func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots_f/%s.png" % shot_name)
	print("[SHOT] %s %dx%d" % [shot_name, img.get_width(), img.get_height()])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
