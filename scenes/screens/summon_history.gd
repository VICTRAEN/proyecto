extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")

## HISTORIAL DE INVOCACIONES (v13). Solo LEE GameState.summon_history, que se escribe
## dentro de GameState.summon() en el mismo guardado que el cobro: lo que se ve aqui
## es exactamente lo que se invoco, sin contarlo dos veces ni perderlo al cerrar.
## Arriba: total de invocaciones, totales por banner y progreso del pity. Debajo, la
## lista (la mas reciente primero) con fecha y hora, banner, gasto, pity y resultados.

const PAGE := 30

var _filter := ""
var _shown := PAGE
var _summary: Label
var _pity_box: VBoxContainer
var _filter_option: OptionButton
var _list: VBoxContainer
var _more_button: Button
var _empty: Label


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	margin.add_child(main)
	var title := Label.new()
	title.text = "HISTORIAL DE INVOCACIONES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.screen_title(title, VI.MAGENTA)
	main.add_child(title)
	_summary = Label.new()
	_summary.name = "Summary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.style_subtitle(_summary)
	main.add_child(_summary)
	_pity_box = VBoxContainer.new()
	_pity_box.name = "PityBox"
	main.add_child(_pity_box)
	_filter_option = OptionButton.new()
	_filter_option.name = "BannerFilter"
	_filter_option.custom_minimum_size = Vector2(0, 60)
	VI.tint_button(_filter_option, VI.VIOLET)
	_filter_option.item_selected.connect(_on_filter)
	main.add_child(_filter_option)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_more_button = Button.new()
	_more_button.name = "MoreButton"
	_more_button.text = "VER MAS ANTIGUAS"
	_more_button.custom_minimum_size = Vector2(0, 72)
	VI.tint_button(_more_button, VI.BLUE)
	_more_button.pressed.connect(func():
		_shown += PAGE
		_build_list())
	main.add_child(_more_button)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "VOLVER"
	back.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(back, VI.BLUE)
	back.pressed.connect(_back)
	main.add_child(back)
	refresh()


## App la repinta cada vez que se muestra.
func refresh() -> void:
	if _filter_option == null:
		return
	_shown = PAGE
	_build_filter()
	_build_header()
	_build_list()


func _build_filter() -> void:
	_filter_option.clear()
	_filter_option.add_item("TODOS LOS BANNERS")
	_filter_option.set_item_metadata(0, "")
	var selected := 0
	for raw in DB.all_banners():
		var banner: Dictionary = raw
		var banner_id := String(banner.get("id", ""))
		_filter_option.add_item(String(banner.get("name", banner_id)).to_upper())
		_filter_option.set_item_metadata(_filter_option.item_count - 1, banner_id)
		if banner_id == _filter:
			selected = _filter_option.item_count - 1
	_filter_option.select(selected)


func _on_filter(index: int) -> void:
	_filter = String(_filter_option.get_item_metadata(index))
	_shown = PAGE
	_build_list()


func _build_header() -> void:
	_summary.text = "Total de invocaciones: %d   -   historial desde la v13 (se conservan las ultimas %d)" % [
		GameState.summon_total, GameState.SUMMON_HISTORY_MAX]
	for child in _pity_box.get_children():
		_pity_box.remove_child(child)
		child.queue_free()
	for raw in DB.all_banners():
		var banner_id := String((raw as Dictionary).get("id", ""))
		var st := GameState.pity_status(banner_id)
		if not bool(st["enabled"]):
			continue
		var label := Label.new()
		label.name = "Pity_" + banner_id
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		label.add_theme_color_override("font_color", VI.GOLD)
		label.text = "%s  -  PITY %d/%d   (%d tiradas en este banner)" % [
			String((raw as Dictionary).get("name", banner_id)), int(st["counter"]), int(st["pulls"]),
			int(GameState.summon_banner_totals.get(banner_id, 0))]
		_pity_box.add_child(label)


func _entries() -> Array:
	var out: Array = []
	var all := GameState.summon_history_list()
	all.reverse()
	for entry in all:
		if _filter.is_empty() or String((entry as Dictionary).get("banner", "")) == _filter:
			out.append(entry)
	return out


func _build_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var entries := _entries()
	_more_button.visible = entries.size() > _shown
	if entries.is_empty():
		var empty := Label.new()
		empty.name = "Empty"
		empty.text = "Todavia no hay invocaciones registradas."
		VI.style_note(empty)
		_list.add_child(empty)
		return
	for i in mini(entries.size(), _shown):
		_list.add_child(_entry_panel(entries[i]))


func _entry_panel(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", VI.panel(0.85, true))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var head := Label.new()
	head.text = "%s   -   %s" % [GameState.format_timestamp(int(entry.get("time", 0))), String(entry.get("banner_name", ""))]
	head.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	head.add_theme_color_override("font_color", VI.GOLD)
	box.add_child(head)
	var meta := Label.new()
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var text := "x%d invocacion(es)  -  %d gemas  -  %d nuevos  -  total acumulado %d" % [
		int(entry.get("count", 0)), int(entry.get("cost", 0)), int(entry.get("new_count", 0)), int(entry.get("total_after", 0))]
	if bool(entry.get("pity_enabled", false)):
		text += "\nPity: %d -> %d" % [int(entry.get("pity_before", 0)), int(entry.get("pity_after", 0))]
		if int(entry.get("guaranteed", 0)) > 0:
			text += "   (garantizado x%d)" % int(entry.get("guaranteed", 0))
	meta.text = text
	meta.add_theme_font_size_override("font_size", VI.FONT_TINY)
	meta.add_theme_color_override("font_color", VI.INK_SOFT)
	box.add_child(meta)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 4)
	box.add_child(flow)
	for result in entry.get("results", []):
		var chip := Label.new()
		var tag := ""
		if bool((result as Dictionary).get("guaranteed", false)):
			tag = " [PITY]"
		elif bool((result as Dictionary).get("new", false)):
			tag = " (nuevo)"
		chip.text = "%s %s%s" % [String((result as Dictionary).get("rarity", "")), String((result as Dictionary).get("name", "")), tag]
		chip.add_theme_font_size_override("font_size", VI.FONT_TINY)
		chip.add_theme_color_override("font_color", VI.rarity_color(String((result as Dictionary).get("rarity", "SR"))))
		flow.add_child(chip)
	return panel


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")
