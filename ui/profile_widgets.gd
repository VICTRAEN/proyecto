extends RefCounted

## Piezas visuales del perfil (v16): avatar con marco, miniatura de una forma y el selector
## modal. Solo pintan: las reglas (que se puede elegir) viven en core/player_profile.gd.

const VI := preload("res://ui/visual_identity.gd")


static func choice_texture(choice: Dictionary) -> Texture2D:
	var path: String = GameState.profile.icon_path(choice)
	if not path.is_empty():
		return load(path) as Texture2D
	var id: String = GameState.profile.character_of(choice)
	if id.is_empty():
		return null
	var art: Dictionary = GameState.character_data(id).get("art", {})
	for slot in ["icon", "front"]:
		var alt := String(art.get(slot, ""))
		if not alt.is_empty() and ResourceLoader.exists(alt):
			return load(alt) as Texture2D
	return null


## Estilo de marco: el cosmetico equipado (colores en su JSON) o el violeta de siempre.
static func frame_style(frame_data: Dictionary) -> StyleBox:
	if frame_data.is_empty():
		return VI.card(VI.VIOLET, true)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.12, 0.95)
	sb.border_color = Color(String(frame_data.get("color", "#ffd45a")))
	sb.set_border_width_all(7)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(String(frame_data.get("color2", "#b8841a")), 0.75)
	sb.shadow_size = 8
	return sb


## Cuadro cuadrado con foto y marco. `choice` vacio = hueco vacio.
static func framed(choice: Dictionary, size: float, frame_data: Dictionary, placeholder: String = "+") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(size, size)
	panel.add_theme_stylebox_override("panel", frame_style(frame_data))
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.custom_minimum_size = Vector2(size - 20, size - 20)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not choice.is_empty():
		tex.texture = choice_texture(choice)
	panel.add_child(tex)
	if tex.texture == null:
		var l := Label.new()
		l.text = placeholder
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", VI.FONT_SECTION)
		l.add_theme_color_override("font_color", VI.INK_DIM)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(l)
	return panel


## Selector modal. options: [{ key, label, selected, icon (Texture2D, opcional) }].
## Llama a on_pick(key) y se cierra. Los botones se llaman Opt_<key>.
static func open_picker(host: Node, title: String, options: Array, on_pick: Callable) -> Control:
	var old := host.get_node_or_null("Picker")
	if old != null:
		old.queue_free()
	var root := Control.new()
	root.name = "Picker"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 120)
	root.add_child(margin)
	var win := PanelContainer.new()
	win.add_theme_stylebox_override("panel", VI.window(VI.GOLD, 0.98))
	margin.add_child(win)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	win.add_child(col)
	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	head.add_theme_color_override("font_color", VI.GOLD)
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for raw in options:
		var o: Dictionary = raw
		var b := Button.new()
		b.name = "Opt_%s" % String(o.get("key", ""))
		b.text = String(o.get("label", "")) + ("   (EQUIPADO)" if bool(o.get("selected", false)) else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 92)
		b.add_theme_font_size_override("font_size", VI.FONT_BODY)
		if o.get("icon", null) != null:
			b.icon = o["icon"]
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 72)
		VI.tint_button(b, VI.GOLD if bool(o.get("selected", false)) else VI.VIOLET)
		b.pressed.connect(func():
			root.queue_free()
			on_pick.call(String(o.get("key", ""))))
		list.add_child(b)
	var close := Button.new()
	close.name = "PickerClose"
	close.text = "CERRAR"
	close.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(close, VI.BLUE)
	close.pressed.connect(root.queue_free)
	col.add_child(close)
	host.add_child(root)
	return root
