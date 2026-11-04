extends "res://scenes/screens/mode_base.gd"

## MAZMORRAS DE MATERIALES (X.3): una tarjeta por mazmorra (data/dungeons) con sus dificultades.
## Anadir una mazmorra es soltar un JSON: esta pantalla la pinta sola.

func _screen_title() -> String:
	return "MAZMORRAS"


func refresh() -> void:
	if list == null:
		return
	clear_list()
	var m = GameState.modes
	var problem: String = GameState.team_problem()
	if not problem.is_empty():
		list.add_child(make_label(problem, VI.FONT_SMALL, VI.RED))
	for dungeon in m.dungeon_list():
		var did := String(dungeon["id"])
		var col := make_card("Dungeon_" + did, String(dungeon.get("name", did)).to_upper(), VI.GREEN)
		col.add_child(make_label(String(dungeon.get("description", "")), VI.FONT_TINY, VI.INK_SOFT))
		for diff in m.dungeon_difficulties(did):
			var dif := String(diff["id"])
			var unlocked: bool = m.dungeon_unlocked(did, dif)
			col.add_child(make_label("%s  -  %s  (superada %d veces)" % [String(diff.get("name", dif)), m.dungeon_reward_text(did, dif) if unlocked else "bloqueada: supera la dificultad anterior", m.dungeon_clears(did, dif)], VI.FONT_TINY, VI.INK if unlocked else VI.INK_DIM))
			var b := make_button("Dng_%s_%s" % [did, dif], "ENTRAR  %s" % String(diff.get("name", dif)).to_upper(), VI.GREEN, _enter.bind(did, dif), 72.0)
			b.disabled = not unlocked or not problem.is_empty()
			col.add_child(b)
	var last := make_card("LastCard", "", VI.BLUE)
	add_last_report(last)
	if last.get_child_count() == 0:
		last.get_parent().queue_free()


func _enter(dungeon_id: String, difficulty: String) -> void:
	if not GameState.modes.start_dungeon(dungeon_id, difficulty):
		say("No se puede entrar: dificultad bloqueada o equipo vacio.", false)
		return
	say("")
	open_battle()
