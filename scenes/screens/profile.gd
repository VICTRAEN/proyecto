extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const Rewards := preload("res://core/rewards.gd")
const Families := preload("res://core/families.gd")
const PW := preload("res://ui/profile_widgets.gd")

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
var _chips: GridContainer
var _frame_panel: PanelContainer
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
	_chips = GridContainer.new()
	_chips.name = "Stats"
	_chips.columns = 3
	_chips.add_theme_constant_override("h_separation", 10)
	_chips.add_theme_constant_override("v_separation", 10)
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
	frame.name = "AvatarFrame"
	frame.custom_minimum_size = Vector2(190, 190)
	frame.add_theme_stylebox_override("panel", VI.card(VI.VIOLET, true))
	row.add_child(frame)
	_frame_panel = frame
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
	# v16: el AVATAR elegido (una forma que de verdad se posee) manda sobre todo lo demas.
	var av: Dictionary = GameState.profile.avatar
	if GameState.profile.is_valid_choice(av):
		var t := PW.choice_texture(av)
		if t != null:
			return t
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
	_frame_panel.add_theme_stylebox_override("panel", PW.frame_style(GameState.profile.equipped_data("frame")))
	var st: Dictionary = GameState.profile.stats()
	_chips.add_child(_chip("%d / %d" % [int(st["families"]), int(st["families_total"])], "PERSONAJES", VI.VIOLET))
	_chips.add_child(_chip(str(int(st["summons"])), "INVOCACIONES", VI.CYAN))
	_chips.add_child(_chip(str(int(st["evolutions"])), "EVOLUCIONES", VI.GOLD))
	_chips.add_child(_chip(str(int(st["battles_won"])), "VICTORIAS", VI.GREEN))
	_chips.add_child(_chip("%d / %d" % [int(st["stages_completed"]), int(st["stages_total"])], "STAGES", VI.BLUE))
	_chips.add_child(_chip(str(int(st["battles_played"])), "COMBATES", VI.VIOLET))
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_build_identity_sections(st)
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


## Rarezas, favorito, vitrina y botones de personalizacion.
func _build_identity_sections(st: Dictionary) -> void:
	var prof = GameState.profile
	var rar := Label.new()
	rar.name = "RarityLine"
	var parts: Array = []
	for r in ["R", "SR", "SSR", "UR", "LR"]:
		if int((st["by_rarity"] as Dictionary).get(r, 0)) > 0:
			parts.append("%s %d" % [r, int(st["by_rarity"][r])])
	rar.text = "Por rareza:  " + ("   ".join(parts) if not parts.is_empty() else "ninguno todavia")
	rar.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	rar.add_theme_color_override("font_color", VI.INK_SOFT)
	_list.add_child(rar)
	var fav: Dictionary = prof.favorite if prof.is_valid_choice(prof.favorite) else {}
	var fav_label := Label.new()
	fav_label.name = "FavoriteLabel"
	fav_label.text = "Favorito:  %s" % ("%s (%s)" % [GameState.display_name(prof.character_of(fav)), String(fav["form"]).to_upper()] if not fav.is_empty() else "ninguno")
	fav_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
	fav_label.add_theme_color_override("font_color", VI.GOLD_LIGHT)
	_list.add_child(fav_label)
	_list.add_child(_section("VITRINA"))
	var row := HBoxContainer.new()
	row.name = "Showcase"
	row.add_theme_constant_override("separation", 8)
	_list.add_child(row)
	var view: Array = prof.showcase_view()
	var frame_data: Dictionary = prof.equipped_data("frame")
	for i in view.size():
		var b := Button.new()
		b.name = "Showcase_%d" % i
		b.flat = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 150)
		var cell := PW.framed(view[i] as Dictionary, 138, frame_data)
		cell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cell)
		b.pressed.connect(_pick_showcase.bind(i))
		row.add_child(b)
	_list.add_child(_note("Toca un hueco para elegir uno de tus personajes. Solo salen las formas que ya has desbloqueado."))
	_list.add_child(_section("PERSONALIZAR"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_list.add_child(grid)
	for def in [["AvatarButton", "AVATAR", _pick_avatar], ["TitleButton", "TITULO", _pick_title], ["FrameButton", "MARCO", _pick_frame], ["FavoriteButton", "FAVORITO", _pick_favorite]]:
		var b := Button.new()
		b.name = String(def[0])
		b.text = String(def[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 84)
		b.add_theme_font_size_override("font_size", VI.FONT_BODY)
		VI.tint_button(b, VI.VIOLET)
		b.pressed.connect(def[2])
		grid.add_child(b)
	var menu_b := Button.new()
	menu_b.name = "CustomizeMenuButton"
	menu_b.text = "PERSONALIZAR MENU PRINCIPAL"
	menu_b.custom_minimum_size = Vector2(0, 88)
	menu_b.add_theme_font_size_override("font_size", VI.FONT_BODY)
	VI.tint_button(menu_b, VI.GOLD)
	menu_b.pressed.connect(_open_menu_customize)
	_list.add_child(menu_b)


## Opciones {key "root|form", label, icon} de todo lo que se puede elegir de verdad.
func _character_options(selected: Dictionary) -> Array:
	var out: Array = []
	for root in GameState.profile.selectable_roots():
		for e in GameState.profile.available_forms(String(root)):
			var choice := { "root": String(root), "form": String((e as Dictionary)["form"]) }
			out.append({
				"key": "%s|%s" % [root, choice["form"]],
				"label": "%s  (%s)" % [GameState.display_name(String((e as Dictionary)["id"])), String(choice["form"]).to_upper()],
				"selected": selected.get("root", "") == root and selected.get("form", "") == choice["form"],
				"icon": PW.choice_texture(choice) })
	return out


func _split_key(key: String) -> PackedStringArray:
	return key.split("|")


func _pick_avatar() -> void:
	PW.open_picker(self, "ELIGE TU AVATAR", _character_options(GameState.profile.avatar), func(key):
		var p := _split_key(key)
		if p.size() == 2 and GameState.profile.set_avatar(p[0], p[1]):
			_saved())


func _pick_favorite() -> void:
	var opts: Array = [{ "key": "none", "label": "Ninguno", "selected": GameState.profile.favorite.is_empty() }]
	opts.append_array(_character_options(GameState.profile.favorite))
	PW.open_picker(self, "PERSONAJE FAVORITO", opts, func(key):
		if key == "none":
			GameState.profile.clear_favorite()
			_saved()
			return
		var p := _split_key(key)
		if p.size() == 2 and GameState.profile.set_favorite(p[0], p[1]):
			_saved())


func _pick_showcase(slot: int) -> void:
	var opts: Array = [{ "key": "none", "label": "Vaciar hueco", "selected": false }]
	opts.append_array(_character_options(GameState.profile.showcase_view()[slot]))
	PW.open_picker(self, "VITRINA - HUECO %d" % (slot + 1), opts, func(key):
		if key == "none":
			GameState.profile.clear_showcase_slot(slot)
			_saved()
			return
		var p := _split_key(key)
		if p.size() == 2 and GameState.profile.set_showcase_slot(slot, p[0], p[1]):
			_saved())


func _pick_title() -> void:
	var opts: Array = []
	var cat: Dictionary = GameState.meta.title_catalog()
	for id in GameState.meta.owned_titles():
		opts.append({ "key": String(id), "label": String(cat.get(String(id), id)), "selected": GameState.meta.equipped_title() == String(id) })
	PW.open_picker(self, "ELIGE TU TITULO", opts, func(key):
		if GameState.meta.equip_title(key):
			_saved())


func _pick_frame() -> void:
	var opts: Array = [{ "key": "none", "label": "Sin marco", "selected": GameState.profile.equipped_id("frame").is_empty() }]
	for id in GameState.account.owned_of_type("frame"):
		opts.append({ "key": String(id), "label": String(DB.get_cosmetic(String(id)).get("name", id)), "selected": GameState.profile.equipped_id("frame") == String(id) })
	PW.open_picker(self, "ELIGE UN MARCO", opts, func(key):
		if GameState.profile.equip("frame", "" if key == "none" else key):
			_saved())


func _saved() -> void:
	GameState.save_game()
	_rebuild()


func _open_menu_customize() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("open_screen"):
		app.call("open_screen", "menu_customize")


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
