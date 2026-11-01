extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const Rewards := preload("res://core/rewards.gd")
const Families := preload("res://core/families.gd")

## PERFIL (v15, rediseñado en v16): nivel de cuenta, barra de experiencia, recompensas por
## nivel y los cosmeticos (fondos del menu e ilustracion de perfil). Solo LEE
## GameState.account; lo unico que cambia es claim_level() y equip_*(). Los titulos se
## equipan en MISIONES > LOGROS.
##
## Nombres de nodo estables (los usan las pruebas): LevelLabel, XpBar, Feedback, List,
## ClaimAllLevels, Level_<n>, Cos_<id>, BackButton.

var _head: Label
var _title_label: Label
var _bar: ProgressBar
var _xp_label: Label
var _portrait: TextureRect
var _chips: HBoxContainer
var _feedback: Label
var _list: VBoxContainer


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 14)
	margin.add_child(main)
	var title := Label.new()
	title.text = "PERFIL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(title)
	VI.screen_title(title, VI.GOLD)
	main.add_child(_build_hero())
	_chips = HBoxContainer.new()
	_chips.name = "Stats"
	_chips.add_theme_constant_override("separation", 10)
	main.add_child(_chips)
	_feedback = Label.new()
	_feedback.name = "Feedback"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	_feedback.add_theme_color_override("font_color", VI.GREEN)
	main.add_child(_feedback)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_list)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "VOLVER"
	back.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(back, VI.BLUE)
	back.pressed.connect(_back)
	main.add_child(back)
	refresh()


## Cabecera: retrato, nivel, titulo equipado y barra de experiencia.
func _build_hero() -> Control:
	var card := PanelContainer.new()
	card.name = "Hero"
	card.add_theme_stylebox_override("panel", VI.window(VI.GOLD, 0.96))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(190, 190)
	frame.add_theme_stylebox_override("panel", VI.card(VI.VIOLET, true))
	row.add_child(frame)
	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.custom_minimum_size = Vector2(170, 170)
	frame.add_child(_portrait)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	_head = Label.new()
	_head.name = "LevelLabel"
	_head.add_theme_font_size_override("font_size", VI.FONT_TITLE)
	_head.add_theme_color_override("font_color", VI.GOLD_LIGHT)
	_head.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.20, 0.95))
	_head.add_theme_constant_override("outline_size", 8)
	var bold := VI.font("bold")
	if bold != null:
		_head.add_theme_font_override("font", bold)
	col.add_child(_head)
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
	_title_label.add_theme_color_override("font_color", VI.CYAN)
	col.add_child(_title_label)
	_bar = ProgressBar.new()
	_bar.name = "XpBar"
	_bar.custom_minimum_size = Vector2(0, 30)
	_bar.show_percentage = false
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color(0.03, 0.02, 0.09, 0.95)
	back_style.border_color = Color(0.62, 0.52, 0.92, 0.7)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = VI.GOLD
	fill_style.border_color = VI.GOLD_LIGHT
	for s in [back_style, fill_style]:
		s.set_corner_radius_all(8)
		s.set_border_width_all(2)
	_bar.add_theme_stylebox_override("background", back_style)
	_bar.add_theme_stylebox_override("fill", fill_style)
	col.add_child(_bar)
	_xp_label = Label.new()
	_xp_label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	_xp_label.add_theme_color_override("font_color", VI.INK_SOFT)
	col.add_child(_xp_label)
	return card


func refresh() -> void:
	_feedback.text = ""
	_rebuild()


func _portrait_texture() -> Texture2D:
	var id: String = GameState.account.illustration_character()
	if id.is_empty():
		id = String(GameState.party[0]) if not GameState.party.is_empty() else ""
	if id.is_empty() or not DB.characters.has(id):
		return null
	var art: Dictionary = GameState.character_data(id).get("art", {})
	for slot in ["icon", "front"]:
		var path := String(art.get(slot, ""))
		if not path.is_empty() and ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


func _rebuild() -> void:
	var acc = GameState.account
	var p: Dictionary = acc.progress()
	_head.text = "NIVEL %d%s" % [int(p["level"]), " (MAX)" if bool(p["maxed"]) else ""]
	_title_label.text = GameState.meta.equipped_title_name()
	_title_label.visible = not _title_label.text.is_empty()
	_bar.max_value = float(p["xp_needed"])
	_bar.value = float(p["xp_in_level"])
	_xp_label.text = "%d / %d XP para el siguiente nivel" % [int(p["xp_in_level"]), int(p["xp_needed"])] if not bool(p["maxed"]) else "Nivel maximo alcanzado"
	_portrait.texture = _portrait_texture()
	for child in _chips.get_children():
		_chips.remove_child(child)
		child.queue_free()
	_chips.add_child(_chip("%d / %d" % [Families.owned_roots(GameState), Families.all_roots().size()], "PERSONAJES", VI.VIOLET))
	_chips.add_child(_chip(str(GameState.counter_value("combates_jugados")), "COMBATES", VI.BLUE))
	_chips.add_child(_chip(str(GameState.counter_value("victorias")), "VICTORIAS", VI.GREEN))
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var pending: Array = acc.pending_levels()
	_list.add_child(_section("RECOMPENSAS DE NIVEL"))
	if pending.is_empty():
		_list.add_child(_note("No tienes recompensas de nivel pendientes. Sube de nivel jugando."))
	else:
		var all_b := Button.new()
		all_b.name = "ClaimAllLevels"
		all_b.text = "RECLAMAR TODO (%d)" % pending.size()
		all_b.custom_minimum_size = Vector2(0, 84)
		VI.tint_button(all_b, VI.GREEN)
		all_b.pressed.connect(_on_claim_all)
		_list.add_child(all_b)
		for l in pending:
			_list.add_child(_level_row(int(l), Rewards.describe(acc.level_reward(int(l))), true))
	var upcoming: Array = acc.upcoming(3)
	if not upcoming.is_empty():
		_list.add_child(_section("PROXIMOS NIVELES"))
		for entry in upcoming:
			_list.add_child(_level_row(int(entry["level"]), String(entry["text"]), false))
	_list.add_child(_section("FONDOS DEL MENU"))
	var bgs := GridContainer.new()
	bgs.columns = 2
	bgs.add_theme_constant_override("h_separation", 12)
	bgs.add_theme_constant_override("v_separation", 12)
	_list.add_child(bgs)
	bgs.add_child(_cosmetic_card("", "Fondo normal", "background", acc.background_equipped.is_empty()))
	for id in acc.owned_of_type("background"):
		bgs.add_child(_cosmetic_card(String(id), String(DB.get_cosmetic(String(id)).get("name", id)), "background", acc.background_equipped == id))
	_list.add_child(_section("ILUSTRACION DEL PERFIL"))
	var ills := GridContainer.new()
	ills.columns = 2
	ills.add_theme_constant_override("h_separation", 12)
	ills.add_theme_constant_override("v_separation", 12)
	_list.add_child(ills)
	ills.add_child(_cosmetic_card("", "Lider del equipo", "illustration", acc.illustration_equipped.is_empty()))
	for id in acc.owned_of_type("illustration"):
		ills.add_child(_cosmetic_card(String(id), String(DB.get_cosmetic(String(id)).get("name", id)), "illustration", acc.illustration_equipped == id))
	if acc.owned_of_type("background").is_empty() and acc.owned_of_type("illustration").is_empty():
		_list.add_child(_note("Los fondos e ilustraciones se ganan con niveles de cuenta y colecciones."))


func _chip(value: String, caption: String, color: Color) -> Control:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override("panel", VI.card(color))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(col)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	v.add_theme_color_override("font_color", VI.INK)
	col.add_child(v)
	var c := Label.new()
	c.text = caption
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	c.add_theme_color_override("font_color", VI.INK_SOFT)
	col.add_child(c)
	return box


func _section(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	l.add_theme_color_override("font_color", VI.GOLD)
	var bold := VI.font("bold")
	if bold != null:
		l.add_theme_font_override("font", bold)
	box.add_child(l)
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 3)
	line.color = Color(VI.GOLD.r, VI.GOLD.g, VI.GOLD.b, 0.55)
	box.add_child(line)
	return box


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	l.add_theme_color_override("font_color", VI.INK_SOFT)
	return l


func _level_row(level_number: int, text: String, claimable: bool) -> Control:
	var card := PanelContainer.new()
	card.name = "Level_%d" % level_number
	var accent: Color = VI.GREEN if claimable else VI.VIOLET
	card.add_theme_stylebox_override("panel", VI.card(accent, false, "", claimable))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(96, 0)
	badge.add_theme_stylebox_override("panel", VI.chip(VI.GOLD if claimable else VI.INK_DIM))
	var num := Label.new()
	num.text = "NIV\n%d" % level_number
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	num.add_theme_color_override("font_color", VI.GOLD_LIGHT if claimable else VI.INK_SOFT)
	badge.add_child(num)
	row.add_child(badge)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", VI.FONT_BODY)
	l.add_theme_color_override("font_color", VI.INK if claimable else VI.INK_SOFT)
	row.add_child(l)
	if claimable:
		var b := Button.new()
		b.text = "RECLAMAR"
		b.custom_minimum_size = Vector2(190, 76)
		VI.tint_button(b, VI.GREEN)
		b.pressed.connect(_on_claim.bind(level_number))
		row.add_child(b)
	return card


func _cosmetic_card(id: String, label: String, type_name: String, equipped: bool) -> Control:
	var b := Button.new()
	b.name = "Cos_%s" % (id if not id.is_empty() else "none_" + type_name)
	b.text = ("%s\nEQUIPADO" % label) if equipped else label
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 100)
	b.add_theme_font_size_override("font_size", VI.FONT_BODY)
	VI.tint_button(b, VI.GOLD if equipped else VI.VIOLET)
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
