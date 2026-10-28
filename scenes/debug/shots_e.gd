extends Node

## CAPTURAS del Hito E (duo David & Lucy) para REVISION VISUAL. SOLO pruebas:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 540x960 -- --shots-e
## Guarda PNG en user://shots_e/. Respalda y restaura la partida. Son capturas de
## ESCRITORIO a 540x960 (viewport del proyecto 1080x1920 reducido), no pruebas en movil real.

const DUO := "david_lucy_duo"
var _app: Node = null


func run(app: Node) -> void:
	_app = app
	DirAccess.make_dir_recursive_absolute("user://shots_e")
	await _frames(5)
	_app.call("_backup_save")
	GameState.pending_reveal = {}
	GameState.coins = 2000000
	GameState.gems = 5000
	GameState.add_item("rabbit_costume", 7)
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.normalize_party()

	# 1) Banner del duo
	_app.call("open_screen", "summon")
	await _frames(20)
	var summon = _app.get("_screens")["summon"]
	summon.set("_banner_id", "banner_david_lucy")
	summon.call("refresh")
	await _frames(25)
	_save("01_banner_duo")
	summon.set("_banner_id", "banner_apertura")
	summon.call("refresh")
	await _frames(10)
	_save("02_banner_apertura")

	# 2) x1 normal (resultado controlado SSR y SR)
	await _reveal_shots(summon, ["gojo"], "03_x1", 1)
	# 3) x10 individual: fotogramas 1/10, 5/10, final, resumen
	await _reveal_x10(summon)
	# 4) El duo: cinematica (fallback) + carta SSR especial + copia extra
	await _duo_reveal(summon)

	# 5) Ficha del duo en SSR / UR / LR
	GameState.add_character(DUO)
	for form in ["SSR", "UR", "LR"]:
		if form == "SSR":
			GameState.rarities.erase(DUO)
		else:
			GameState.rarities[DUO] = form
		_app.call("open_screen", "collection")
		await _frames(25)
		var col = _app.get("_screens")["collection"]
		col.call("_on_card_pressed", GameState.character_data(DUO))
		await _frames(30)
		_save("10_ficha_%s" % form.to_lower())
		var panel = col.get("info_panel")
		if panel != null and panel.has_method("close_panel"):
			panel.call("close_panel")
		_app.call("go_back")
		await _frames(3)
	GameState.rarities.erase(DUO)

	# 6) Evolucion: SSR nivel 100 y UR nivel 100 + animacion
	GameState.progress[DUO] = { "level": 100, "xp": 0 }
	_app.call("open_screen", "evolution")
	await _frames(20)
	var evo = _app.get("_screens")["evolution"]
	evo.set("_selected_id", DUO)
	evo.call("refresh")
	await _frames(25)
	_save("20_evo_ssr_ur")
	evo.call("_on_evolve_pressed")
	for i in 6:
		await _wait(0.4)
		_save("21_evo_fx_ur_%d" % i)
	await _wait(2.0)
	GameState.progress[DUO] = { "level": 100, "xp": 0 }
	evo.set("_selected_id", DUO)
	evo.call("refresh")
	await _frames(25)
	_save("22_evo_ur_lr")
	evo.call("_on_evolve_pressed")
	for i in 6:
		await _wait(0.4)
		_save("23_evo_fx_lr_%d" % i)
	await _wait(2.0)
	_app.call("go_back")
	await _frames(3)

	# 7) Combate con la ultimate (el duo ya es LR)
	GameState.party = [DUO, "", "", ""]
	GameState.normalize_party()
	GameState.current_stage_enemies = ["void_warden", "vigia_alfa", "vigia_beta"]
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
	mgr.allies[0].sp = 3
	battle.call("_refresh_ultimate_button", mgr.allies[0])
	await _frames(10)
	_save("30_combate_antes")
	battle.call("_on_ultimate_pressed")
	for i in 14:
		await _wait(0.25)
		_save("31_ult_%02d" % i)
	await _wait(2.0)
	_save("32_ult_despues")
	_app.call("close_battle")
	await _frames(5)

	# 8) Panel de desarrollador
	_app.call("open_screen", "settings")
	await _frames(25)
	_save("40_settings_dev_top")
	var sc = _app.get("_screens")["settings"]
	var scroll = sc.find_child("*", true, false)
	for s in sc.find_children("*", "ScrollContainer", true, false):
		(s as ScrollContainer).scroll_vertical = 100000
	await _frames(10)
	_save("41_settings_dev_bottom")
	_app.call("go_back")

	_app.call("_restore_save")
	get_tree().quit(0)


func _set_pending(ids: Array, cinematic_done: bool = false) -> void:
	var results: Array = []
	for id in ids:
		results.append({ "id": String(id), "name": GameState.display_name(String(id)), "rarity": GameState.rarity_of(String(id)), "new": false, "duplicate": true, "duplicates": 1 })
	GameState.pending_reveal = {
		"banner": "banner_david_lucy", "banner_name": "Edgerunners", "count": ids.size(), "cost": 90, "index": 0,
		"results": results, "new_count": 0, "duplicate_count": ids.size(), "cinematic_done": cinematic_done,
	}


func _open(summon) -> Node:
	summon.call("_begin_reveal")
	await _frames(3)
	return summon.get_node_or_null("SummonReveal")


func _wait_card(rv: Node) -> void:
	for i in 60:
		if not is_instance_valid(rv):
			return
		if rv.call("phase") == "card" and not bool(rv.call("is_busy")):
			await _wait(0.4)
			return
		await _wait(0.1)


func _reveal_shots(summon, ids: Array, prefix: String, _n: int) -> void:
	_set_pending(ids)
	var rv = await _open(summon)
	if rv == null:
		return
	await _wait(0.4)
	_save("%s_a_transicion" % prefix)
	await _wait_card(rv)
	_save("%s_b_carta" % prefix)
	rv.call("tap")
	await _wait(0.6)
	_save("%s_c_fin" % prefix)
	if is_instance_valid(rv):
		rv.call("tap")
	await _wait(0.4)
	if is_instance_valid(rv):
		var back = rv.find_child("ReturnButton", true, false)
		if back != null:
			back.pressed.emit()
	await _wait(0.5)


func _reveal_x10(summon) -> void:
	var ids := ["gojo", "isagi", "frieren", "mai", "goku", "akaza", "deku", "rem", "gon", "arthur"]
	_set_pending(ids)
	var rv = await _open(summon)
	if rv == null:
		return
	for i in 10:
		await _wait_card(rv)
		if i in [0, 4, 9]:
			_save("04_x10_%02d" % (i + 1))
		rv.call("tap")
		await _wait(0.3)
		if i in [0, 4]:
			_save("04_x10_%02d_transicion" % (i + 1))
	await _wait(0.6)
	_save("05_x10_fin")
	# v11: el resumen se abre solo al terminar.
	if is_instance_valid(rv) and rv.find_child("SummaryGrid", true, false) != null:
		_save("06_x10_resumen")
	if is_instance_valid(rv):
		var back = rv.find_child("ReturnButton", true, false)
		if back != null:
			back.pressed.emit()
	await _wait(0.5)


func _duo_reveal(summon) -> void:
	GameState.add_character(DUO)
	_set_pending([DUO, "gojo", DUO])
	var rv = await _open(summon)
	if rv == null:
		return
	for i in 8:
		await _wait(0.35)
		_save("07_duo_cine_%02d" % i)
	await _wait_card(rv)
	_save("08_duo_carta")
	await _wait(0.5)
	_save("08_duo_carta_b")
	rv.call("tap")
	await _wait(0.6)
	_save("09_tras_duo_gojo")
	await _wait_card(rv)
	rv.call("tap")
	for i in 4:
		await _wait(0.3)
		_save("09_duo_copia_%d" % i)
	await _wait_card(rv)
	_save("09_duo_copia_carta")
	rv.call("tap")
	await _wait(0.5)
	if is_instance_valid(rv):
		var back = rv.find_child("ReturnButton", true, false)
		if back != null:
			back.pressed.emit()
	await _wait(0.5)
	GameState.pending_reveal = {}


func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots_e/%s.png" % shot_name)
	print("[SHOT] %s %dx%d" % [shot_name, img.get_width(), img.get_height()])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
