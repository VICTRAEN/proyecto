extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const Preview := preload("res://core/preview.gd")
const TypeColors := preload("res://ui/type_colors.gd")

## COMPARAR PERSONAJES (v15). Dos personajes que tienes, lado a lado: rareza, tipo, nivel,
## estadisticas finales (las mismas que usa el combate), pasivas y categorias. Solo LEE;
## no cambia nada del jugador. La mejor cifra de cada fila se marca en verde.

var _pick_a: OptionButton
var _pick_b: OptionButton
var _ids: Array = []
var _table: VBoxContainer
var _verdict: Label


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	margin.add_child(main)
	var title := Label.new()
	title.text = "COMPARAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.screen_title(title, VI.CYAN)
	main.add_child(title)
	_pick_a = _make_picker("PickA")
	main.add_child(_pick_a)
	_pick_b = _make_picker("PickB")
	main.add_child(_pick_b)
	_verdict = Label.new()
	_verdict.name = "Verdict"
	_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	VI.style_subtitle(_verdict)
	main.add_child(_verdict)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	_table = VBoxContainer.new()
	_table.name = "Table"
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.add_theme_constant_override("separation", 6)
	scroll.add_child(_table)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "VOLVER"
	back.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(back, VI.BLUE)
	back.pressed.connect(_back)
	main.add_child(back)
	refresh()


func _make_picker(node_name: String) -> OptionButton:
	var b := OptionButton.new()
	b.name = node_name
	b.custom_minimum_size = Vector2(0, 64)
	VI.tint_button(b, VI.VIOLET)
	b.item_selected.connect(func(_i): _rebuild())
	return b


func refresh() -> void:
	var keep_a := _selected(_pick_a)
	var keep_b := _selected(_pick_b)
	_ids = []
	for data in GameState.roster_data():
		_ids.append(String((data as Dictionary).get("id", "")))
	_ids.sort_custom(func(x, y): return GameState.display_name(String(x)) < GameState.display_name(String(y)))
	for picker in [_pick_a, _pick_b]:
		picker.clear()
		for id in _ids:
			picker.add_item("%s  (%s Nv.%d)" % [GameState.display_name(String(id)), GameState.rarity_of(String(id)), GameState.level_of(String(id))])
	_select(_pick_a, keep_a, 0)
	_select(_pick_b, keep_b, 1)
	_rebuild()


## Elige por id (o la posicion de reserva si ese id ya no esta).
func select_pair(id_a: String, id_b: String) -> void:
	_select(_pick_a, id_a, 0)
	_select(_pick_b, id_b, 1)
	_rebuild()


func _selected(picker: OptionButton) -> String:
	var i := picker.selected
	return String(_ids[i]) if i >= 0 and i < _ids.size() else ""


func _select(picker: OptionButton, id: String, fallback: int) -> void:
	var i := _ids.find(id) if not id.is_empty() else -1
	if i < 0:
		i = mini(fallback, maxi(0, _ids.size() - 1))
	if picker.item_count > 0:
		picker.select(i)


func _rebuild() -> void:
	for child in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	var id_a := _selected(_pick_a)
	var id_b := _selected(_pick_b)
	if id_a.is_empty() or id_b.is_empty():
		_verdict.text = "Necesitas al menos dos personajes."
		return
	var info_a: Dictionary = Preview.compare_info(GameState, id_a)
	var info_b: Dictionary = Preview.compare_info(GameState, id_b)
	var rows: Array = Preview.compare(GameState, id_a, id_b)
	var verdict := Preview.compare_verdict(rows)
	_verdict.text = "Mismas estadisticas" if verdict == "=" else "Gana en mas estadisticas: %s" % String((info_a if verdict == "a" else info_b)["name"])
	_table.add_child(_row("", String(info_a["name"]), String(info_b["name"]), VI.GOLD, VI.GOLD, VI.GOLD))
	_table.add_child(_row("Rareza", String(info_a["rarity"]), String(info_b["rarity"]), VI.rarity_color(String(info_a["rarity"])), VI.rarity_color(String(info_b["rarity"])), VI.INK_DIM))
	_table.add_child(_row("Tipo", String(info_a["type"]), String(info_b["type"]), TypeColors.color_for(String(info_a["type"])), TypeColors.color_for(String(info_b["type"])), VI.INK_DIM))
	_table.add_child(_row("Nivel", str(info_a["level"]), str(info_b["level"]), VI.INK, VI.INK, VI.INK_DIM))
	_table.add_child(_row("Dupe", str(info_a["dupe_level"]), str(info_b["dupe_level"]), VI.INK, VI.INK, VI.INK_DIM))
	for r in rows:
		var col_a: Color = VI.GREEN if String(r["better"]) == "a" else VI.INK
		var col_b: Color = VI.GREEN if String(r["better"]) == "b" else VI.INK
		var n := _row(String(r["label"]), String(r["a_text"]), String(r["b_text"]), col_a, col_b, VI.INK_DIM)
		n.name = "Stat_" + String(r["stat"])
		_table.add_child(n)
	_table.add_child(_row("Pasivas", ", ".join(PackedStringArray(info_a["passives"])), ", ".join(PackedStringArray(info_b["passives"])), VI.INK_SOFT, VI.INK_SOFT, VI.INK_DIM))
	_table.add_child(_row("Categorias", _cat_names(info_a["categories"]), _cat_names(info_b["categories"]), VI.INK_SOFT, VI.INK_SOFT, VI.INK_DIM))


func _row(label_text: String, a_text: String, b_text: String, a_color: Color, b_color: Color, label_color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	l.add_theme_color_override("font_color", label_color)
	row.add_child(l)
	for pair in [[a_text, a_color], [b_text, b_color]]:
		var v := Label.new()
		v.text = String(pair[0])
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		v.add_theme_color_override("font_color", pair[1])
		row.add_child(v)
	return row


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


## Nombres legibles de categoria (el JSON guarda ids como "shonen").
func _cat_names(ids: Array) -> String:
	var out := PackedStringArray()
	for id in ids:
		out.append(String((DB.categories.get(String(id), {}) as Dictionary).get("name", String(id).capitalize())))
	return ", ".join(out)
