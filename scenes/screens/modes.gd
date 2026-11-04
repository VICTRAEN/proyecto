extends "res://scenes/screens/mode_base.gd"

## HUB de MODOS DE JUEGO (X.3): una entrada a cada modo, con su estado real.

func _screen_title() -> String:
	return "MODOS DE JUEGO"


func refresh() -> void:
	if list == null:
		return
	clear_list()
	var m = GameState.modes
	var raid := DB.get_raid(m.current_raid_id())
	var raid_rec: Dictionary = m.raid_record(m.current_raid_id()) if not raid.is_empty() else {}
	_entry("BtnRaid", "INCURSION DE JEFE", "Esta semana: %s. Mejor dano: %d." % [String(raid.get("name", "-")), int(raid_rec.get("best_damage", 0))], "mode_raid", VI.RED)
	_entry("BtnDungeon", "MAZMORRAS DE MATERIALES", "%d mazmorras: experiencia, monedas, evolucion, personajes y equipables." % m.dungeon_list().size(), "mode_dungeon", VI.GREEN)
	var rogue: Dictionary = m.rogue_record()
	_entry("BtnRogue", "MODO ROGUELIKE", ("Partida en marcha: combate %d." % (int(m.rogue_run.get("depth", 0)) + 1)) if m.rogue_active() else "Mejor profundidad: %d." % int(rogue["depth"]), "mode_rogue", VI.VIOLET)
	var best_rush := 0
	for d in m.rush_difficulties():
		best_rush = maxi(best_rush, int(m.rush_record(String(d["id"]))["bosses"]))
	_entry("BtnRush", "BOSS RUSH", ("Carrera en marcha: jefe %d." % (int(m.rush_run.get("index", 0)) + 1)) if m.rush_active() else "Record: %d jefes." % best_rush, "mode_rush", VI.GOLD)
	_entry("BtnTraining", "CAMPO DE ENTRENAMIENTO", "Prueba equipos y objetos sin gastar nada ni ganar nada.", "mode_training", VI.CYAN)


func _entry(node_name: String, title: String, sub: String, screen: String, color: Color) -> void:
	var col := make_card("Card_" + node_name, "", color)
	col.add_child(make_label(sub, VI.FONT_SMALL, VI.INK_SOFT))
	col.add_child(make_button(node_name, title, color, _goto.bind(screen), 92.0))


func _goto(screen: String) -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("open_screen"):
		app.call("open_screen", screen)
