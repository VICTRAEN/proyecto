extends "res://scenes/screens/mode_base.gd"

## MODO ROGUELIKE (X.3): equipo propio, combates seguidos y 1 mejora de 3 tras cada victoria. Las
## mejoras duran solo la partida: no tocan a tus personajes. La partida se guarda y se puede retomar.

var _selected: Array = []


func _screen_title() -> String:
	return "MODO ROGUELIKE"


func refresh() -> void:
	if list == null:
		return
	clear_list()
	if GameState.modes.rogue_active():
		_run_view()
	else:
		_menu_view()
	var last := make_card("LastCard", "", VI.BLUE)
	add_last_report(last)
	if last.get_child_count() == 0:
		last.get_parent().queue_free()


func _menu_view() -> void:
	var m = GameState.modes
	var cfg: Dictionary = m.rogue_config()
	var rec: Dictionary = m.rogue_record()
	var info := make_card("RogueInfo", String(cfg.get("name", "Roguelike")).to_upper(), VI.VIOLET)
	info.add_child(make_label(String(cfg.get("description", "")), VI.FONT_SMALL, VI.INK_SOFT))
	info.add_child(make_label("Mejor profundidad: %d   Partidas: %d" % [int(rec["depth"]), int(rec["runs"])], VI.FONT_SMALL, VI.GOLD_LIGHT))
	var size_max := int(cfg.get("team_size", 4))
	var team := make_card("TeamCard", "ELIGE TU EQUIPO (%d/%d)" % [_selected.size(), size_max], VI.BLUE)
	for id in GameState.roster:
		var key := String(id)
		var on := _selected.has(key)
		team.add_child(make_button("Pick_" + key, ("[x] " if on else "[ ] ") + GameState.display_name(key), VI.GOLD if on else VI.BLUE, _toggle.bind(key), 64.0))
	var go := make_button("RogueStart", "EMPEZAR PARTIDA", VI.GREEN, _start, 96.0)
	go.disabled = _selected.is_empty()
	list.add_child(go)


func _run_view() -> void:
	var m = GameState.modes
	var run: Dictionary = m.rogue_run
	var col := make_card("RunCard", "PARTIDA EN CURSO - combate %d" % (int(run["depth"]) + 1), VI.VIOLET)
	for id in run["team"]:
		var dead: bool = (run["dead"] as Array).has(String(id))
		col.add_child(make_label("%s   %s" % [GameState.display_name(String(id)), hp_text(float(run["hp"].get(id, 1.0)), not dead)], VI.FONT_SMALL, VI.RED if dead else VI.INK))
	var boons: Dictionary = run["boons"]
	if boons.is_empty():
		col.add_child(make_label("Aun no tienes mejoras.", VI.FONT_TINY, VI.INK_DIM))
	for bid in boons:
		var b: Dictionary = m.rogue_boon(String(bid))
		col.add_child(make_label("%s x%d: %s" % [String(b.get("name", bid)), int(boons[bid]), String(b.get("description", ""))], VI.FONT_TINY, VI.GOLD_LIGHT))
	var run_items: Dictionary = run.get("items", {})
	for ch in run_items:
		col.add_child(make_label("%s lleva %s (solo esta partida)" % [GameState.display_name(String(ch)), GameState.equipment.name_of(String(run_items[ch]))], VI.FONT_TINY, VI.CYAN))
	if String(run["phase"]) == "choose":
		var pick := make_card("ChoiceCard", "ELIGE UNA MEJORA U OBJETO", VI.GOLD)
		for bid in run["choices"]:
			var cid := String(bid)
			if cid.begins_with("item:"):
				var iid := cid.substr(5)
				var idata: Dictionary = DB.equipment.get(iid, {})
				pick.add_child(make_label("OBJETO: %s (%s). %s" % [String(idata.get("name", iid)), String(idata.get("rarity", "")), String((idata.get("passive", {}) as Dictionary).get("description", ""))], VI.FONT_TINY, VI.INK))
				for ch in m.rogue_alive_team():
					pick.add_child(make_button("Item_%s_%s" % [iid, String(ch)], "DAR A %s" % GameState.display_name(String(ch)).to_upper(), VI.CYAN, _pick.bind(cid, String(ch)), 64.0))
			else:
				var b2: Dictionary = m.rogue_boon(cid)
				pick.add_child(make_label("%s (%s): %s" % [String(b2.get("name", cid)), String(b2.get("rarity", "")), String(b2.get("description", ""))], VI.FONT_TINY, VI.INK))
				pick.add_child(make_button("Boon_" + cid, "ELEGIR  " + String(b2.get("name", cid)).to_upper(), VI.GOLD, _pick.bind(cid), 72.0))
	else:
		col.add_child(make_button("RogueFight", "COMBATIR", VI.VIOLET, _fight, 96.0))
	col.add_child(make_button("RogueEnd", "TERMINAR Y COBRAR", VI.RED, _end, 72.0))


func _toggle(id: String) -> void:
	var size_max := int(GameState.modes.rogue_config().get("team_size", 4))
	if _selected.has(id):
		_selected.erase(id)
	elif _selected.size() < size_max:
		_selected.append(id)
	refresh()


func _start() -> void:
	var r: Dictionary = GameState.modes.rogue_start_run(_selected)
	if not bool(r["ok"]):
		say(String(r["reason"]), false)
		return
	GameState.save_game()
	say("Partida empezada.")
	refresh()


func _fight() -> void:
	if not GameState.modes.rogue_fight():
		say("No se puede combatir.", false)
		return
	say("")
	open_battle()


func _pick(choice_id: String, holder: String = "") -> void:
	var r: Dictionary = GameState.modes.rogue_pick(choice_id, holder)
	if not bool(r["ok"]):
		say(String(r["reason"]), false)
		return
	GameState.save_game()
	say("Mejora elegida.")
	refresh()


func _end() -> void:
	var rep: Dictionary = GameState.modes.rogue_end_run()
	GameState.save_game()
	say("Partida terminada. Recompensas cobradas.")
	refresh()
