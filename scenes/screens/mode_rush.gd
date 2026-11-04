extends "res://scenes/screens/mode_base.gd"

## BOSS RUSH (X.3): jefes seguidos con desgaste. La carrera se guarda: puedes cerrar el juego y seguir.

func _screen_title() -> String:
	return "BOSS RUSH"


func refresh() -> void:
	if list == null:
		return
	clear_list()
	var m = GameState.modes
	if m.rush_active():
		_run_view()
	else:
		_menu_view()
	var last := make_card("LastCard", "", VI.BLUE)
	add_last_report(last)
	if last.get_child_count() == 0:
		last.get_parent().queue_free()


func _menu_view() -> void:
	var m = GameState.modes
	var cfg: Dictionary = m.rush_config()
	var head := make_card("RushInfo", String(cfg.get("name", "Boss Rush")).to_upper(), VI.GOLD)
	head.add_child(make_label(String(cfg.get("description", "")), VI.FONT_SMALL, VI.INK_SOFT))
	var names := PackedStringArray()
	for b in cfg.get("bosses", []):
		names.append(String(DB.get_enemy(String(b)).get("name", b)))
	head.add_child(make_label("Jefes: " + " > ".join(names), VI.FONT_TINY, VI.INK))
	var problem: String = GameState.team_problem()
	if not problem.is_empty():
		head.add_child(make_label(problem, VI.FONT_SMALL, VI.RED))
	for diff in m.rush_difficulties():
		var did := String(diff["id"])
		var rec: Dictionary = m.rush_record(did)
		var col := make_card("Diff_" + did, String(diff.get("name", did)).to_upper(), VI.VIOLET)
		col.add_child(make_label("Record: %d jefes   Carreras: %d   Completadas: %d   Recuperacion entre jefes: %d%%" % [int(rec["bosses"]), int(rec["runs"]), int(rec["clears"]), int(round(float(diff.get("recovery", 0.0)) * 100.0))], VI.FONT_TINY, VI.GOLD_LIGHT))
		var unlocked: bool = m.rush_unlocked(did)
		if not unlocked:
			col.add_child(make_label("Bloqueada: completa la dificultad anterior.", VI.FONT_TINY, VI.INK_DIM))
		var b := make_button("Rush_" + did, "EMPEZAR  %s" % String(diff.get("name", did)).to_upper(), VI.GOLD, _start.bind(did), 78.0)
		b.disabled = not unlocked or not problem.is_empty()
		col.add_child(b)


func _run_view() -> void:
	var m = GameState.modes
	var run: Dictionary = m.rush_run
	var diff: Dictionary = m.rush_difficulty(String(run["difficulty"]))
	var col := make_card("RunCard", "CARRERA EN CURSO - %s" % String(diff.get("name", "")).to_upper(), VI.GOLD)
	col.add_child(make_label("Jefes derrotados: %d / %d     Siguiente: %s" % [int(run["defeated"]), m.rush_boss_count(), String(DB.get_enemy(m.rush_next_boss_id()).get("name", "?"))], VI.FONT_SMALL, VI.INK))
	for id in run["team"]:
		var dead: bool = (run["dead"] as Array).has(String(id))
		col.add_child(make_label("%s   %s" % [GameState.display_name(String(id)), hp_text(float(run["hp"].get(id, 1.0)), not dead)], VI.FONT_SMALL, VI.RED if dead else VI.INK))
	col.add_child(make_button("RushFight", "COMBATIR AL SIGUIENTE JEFE", VI.GOLD, _fight, 96.0))
	col.add_child(make_button("RushAbandon", "ABANDONAR CARRERA", VI.RED, _abandon, 72.0))


func _start(diff_id: String) -> void:
	var r: Dictionary = GameState.modes.rush_start_run(diff_id)
	if not bool(r["ok"]):
		say(String(r["reason"]), false)
		return
	GameState.save_game()
	say("Carrera empezada.")
	refresh()


func _fight() -> void:
	if not GameState.modes.rush_fight():
		say("No se puede combatir.", false)
		return
	say("")
	open_battle()


func _abandon() -> void:
	GameState.modes.rush_abandon()
	GameState.save_game()
	say("Carrera abandonada. Tu record se conserva.")
	refresh()
