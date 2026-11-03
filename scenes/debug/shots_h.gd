extends Node

## CAPTURAS v16 para REVISION VISUAL (solo pruebas):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 540x960 -- --shots-h
## Guarda PNG en user://shots_h/. Respalda y restaura la partida.

var _app: Node = null


func run(app: Node) -> void:
	_app = app
	DirAccess.make_dir_recursive_absolute("user://shots_h")
	await _frames(5)
	_app.call("_backup_save")
	GameState.account.add_xp(1800)
	GameState.account.grant_cosmetic("bg_equipo")
	GameState.account.grant_cosmetic("ill_goku")
	GameState.account.equip_background("bg_equipo")
	GameState.account.claim_level(2)
	GameState.account.claim_level(3)
	for it in ["rueda_adaptabilidad", "dedo_sukuna", "armadura_saiyan", "semilla_senzu", "sombrero_paja"]:
		GameState.equipment.add(it, 1)
	GameState.equipment.equip(String(GameState.party[0]), "rueda_adaptabilidad")
	for c in ["frame_oro", "theme_violeta", "deco_estrellas", "theme_cian"]:
		GameState.account.grant_cosmetic(c)
	GameState.profile.equip("frame", "frame_oro")
	GameState.profile.equip("theme", "theme_violeta")
	GameState.profile.equip("decoration", "deco_estrellas")
	for i in 3:
		var r := String(GameState.profile.selectable_roots()[i])
		GameState.profile.set_showcase_slot(i, r, String((GameState.profile.available_forms(r)[0] as Dictionary)["form"]))
	GameState.profile.set_avatar(String(GameState.profile.selectable_roots()[0]), "ssr" if GameState.profile.is_valid_choice({"root": String(GameState.profile.selectable_roots()[0]), "form": "ssr"}) else String((GameState.profile.available_forms(String(GameState.profile.selectable_roots()[0]))[0] as Dictionary)["form"]))
	for name in ["main_menu", "equipment", "summon", "profile", "menu_customize", "collection_rewards", "compare", "collection", "missions", "evolution", "shop", "events", "inventory", "settings", "team"]:
		_app.call("open_screen", name)
		await _frames(25)
		_save("screen_" + name)
		if name == "summon":
			var s = _app.get("_screens").get("summon", null)
			if s != null:
				s.call("_on_info_pressed")
				await _frames(20)
				_save("summon_info_panel")
				var panel = s.get_node_or_null("BannerInfoPanel")
				if panel != null:
					panel.queue_free()
		if name == "profile":
			var pr = _app.get("_screens").get("profile", null)
			if pr != null:
				var sc: ScrollContainer = pr.find_child("List", true, false).get_parent()
				sc.scroll_vertical = 100000
				await _frames(5)
				_save("profile_bottom")
		if name == "collection_rewards":
			var r = _app.get("_screens").get("collection_rewards", null)
			if r != null:
				r.call("_toggle_expand", "col_serie_dragon_ball")
				await _frames(10)
				_save("collection_rewards_expanded")
	_app.call("_restore_save")
	get_tree().quit(0)


func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots_h/%s.png" % shot_name)
	print("[SHOT] %s %dx%d" % [shot_name, img.get_width(), img.get_height()])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
