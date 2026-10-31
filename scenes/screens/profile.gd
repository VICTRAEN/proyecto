extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const Rewards := preload("res://core/rewards.gd")

## PERFIL (v15): nivel de cuenta, barra de experiencia, recompensas por nivel y los
## cosmeticos (fondos del menu e ilustracion de perfil). Solo LEE GameState.account; lo
## unico que cambia es claim_level() y equip_*(). Los titulos se equipan en MISIONES > LOGROS.

var _head: Label
var _bar: ProgressBar
var _xp_label: Label
var _feedback: Label
var _list: VBoxContainer


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	margin.add_child(main)
	var title := Label.new()
	title.text = "PERFIL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.screen_title(title, VI.GOLD)
	main.add_child(title)
	_head = Label.new()
	_head.name = "LevelLabel"
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head.add_theme_font_size_override("font_size", VI.FONT_BIG)
	_head.add_theme_color_override("font_color", VI.GOLD)
	main.add_child(_head)
	_bar = ProgressBar.new()
	_bar.name = "XpBar"
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.show_percentage = false
	main.add_child(_bar)
	_xp_label = Label.new()
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.style_subtitle(_xp_label)
	main.add_child(_xp_label)
	_feedback = Label.new()
	_feedback.name = "Feedback"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	VI.style_note(_feedback)
	main.add_child(_feedback)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "VOLVER"
	back.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(back, VI.BLUE)
	back.pressed.connect(_back)
	main.add_child(back)
	refresh()


func refresh() -> void:
	_feedback.text = ""
	_rebuild()


func _rebuild() -> void:
	var acc = GameState.account
	var p: Dictionary = acc.progress()
	_head.text = "NIVEL %d%s  -  %s" % [int(p["level"]), " (MAX)" if bool(p["maxed"]) else "", GameState.meta.equipped_title_name()]
	_bar.max_value = float(p["xp_needed"])
	_bar.value = float(p["xp_in_level"])
	_xp_label.text = "%d / %d XP para el siguiente nivel" % [int(p["xp_in_level"]), int(p["xp_needed"])] if not bool(p["maxed"]) else "Nivel maximo alcanzado"
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var pending: Array = acc.pending_levels()
	_list.add_child(_section("RECOMPENSAS DE NIVEL"))
	if pending.is_empty():
		_list.add_child(_line("No hay recompensas de nivel pendientes.", VI.INK_DIM))
	else:
		var all_b := Button.new()
		all_b.name = "ClaimAllLevels"
		all_b.text = "RECLAMAR TODO (%d)" % pending.size()
		all_b.custom_minimum_size = Vector2(0, 60)
		VI.tint_button(all_b, VI.GREEN)
		all_b.pressed.connect(_on_claim_all)
		_list.add_child(all_b)
		for l in pending:
			_list.add_child(_level_row(int(l), Rewards.describe(acc.level_reward(int(l))), true))
	_list.add_child(_section("PROXIMOS NIVELES"))
	for entry in acc.upcoming(3):
		_list.add_child(_level_row(int(entry["level"]), String(entry["text"]), false))
	_list.add_child(_section("FONDOS DEL MENU"))
	_list.add_child(_cosmetic_row("", "Fondo normal", "background", acc.background_equipped.is_empty()))
	for id in acc.owned_of_type("background"):
		_list.add_child(_cosmetic_row(String(id), String(DB.get_cosmetic(String(id)).get("name", id)), "background", acc.background_equipped == id))
	_list.add_child(_section("ILUSTRACION DEL PERFIL"))
	_list.add_child(_cosmetic_row("", "Lider del equipo", "illustration", acc.illustration_equipped.is_empty()))
	for id in acc.owned_of_type("illustration"):
		_list.add_child(_cosmetic_row(String(id), String(DB.get_cosmetic(String(id)).get("name", id)), "illustration", acc.illustration_equipped == id))


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	l.add_theme_color_override("font_color", VI.INK)
	return l


func _line(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", VI.FONT_TINY)
	l.add_theme_color_override("font_color", color)
	return l


func _level_row(level_number: int, text: String, claimable: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "Level_%d" % level_number
	row.add_theme_constant_override("separation", 10)
	var l := _line("Nivel %d: %s" % [level_number, text], VI.GOLD if claimable else VI.INK_SOFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if claimable:
		var b := Button.new()
		b.text = "RECLAMAR"
		b.custom_minimum_size = Vector2(150, 52)
		VI.tint_button(b, VI.GREEN)
		b.pressed.connect(_on_claim.bind(level_number))
		row.add_child(b)
	return row


func _cosmetic_row(id: String, label: String, type_name: String, equipped: bool) -> Control:
	var b := Button.new()
	b.name = "Cos_%s" % (id if not id.is_empty() else "none_" + type_name)
	b.text = ("%s  (EQUIPADO)" % label) if equipped else label
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	VI.tint_button(b, VI.GOLD if equipped else VI.INK_DIM)
	b.pressed.connect(_on_equip.bind(id, type_name))
	return b


func _on_equip(id: String, type_name: String) -> void:
	var ok: bool = GameState.account.equip_background(id) if type_name == "background" else GameState.account.equip_illustration(id)
	if ok:
		GameState.save_game()
	_rebuild()


func _on_claim(level_number: int) -> void:
	var done: Dictionary = GameState.account.claim_level(level_number)
	_rebuild()
	_feedback.text = "Nivel %d: %s" % [level_number, String(done["text"])] if not done.is_empty() else "Esa recompensa ya se ha reclamado."


func _on_claim_all() -> void:
	var done: Array = GameState.account.claim_all_levels()
	_rebuild()
	_feedback.text = "%d recompensas de nivel reclamadas." % done.size()


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")
