extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const PW := preload("res://ui/profile_widgets.gd")

## Base comun de las pantallas de los MODOS DE JUEGO (X.3). Solo pinta: las reglas viven en
## GameState.modes (core/game_modes.gd). Cada pantalla hija pone su titulo y rellena `List` en
## refresh(). Nodos estables: List, Feedback, BackButton.

var list: VBoxContainer
var feedback: Label
var _title_label: Label


func _screen_title() -> String:
	return "MODO"


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	margin.add_child(main)
	_title_label = Label.new()
	_title_label.text = _screen_title()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_title_label)
	VI.screen_title(_title_label, VI.GOLD)
	feedback = Label.new()
	feedback.name = "Feedback"
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	feedback.add_theme_color_override("font_color", VI.GREEN)
	main.add_child(feedback)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "VOLVER"
	back.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(back, VI.BLUE)
	back.pressed.connect(_back)
	main.add_child(back)
	refresh()


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


func refresh() -> void:
	pass


func on_battle_closed() -> void:
	GameState.reset_battle_context()
	refresh()


func say(text: String, ok: bool = true) -> void:
	if feedback != null:
		feedback.text = text
		feedback.add_theme_color_override("font_color", VI.GREEN if ok else VI.RED)


func clear_list() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()


func make_label(text: String, size: int = VI.FONT_SMALL, color: Color = VI.INK_SOFT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func make_button(node_name: String, text: String, color: Color, on_press: Callable, height: float = 84.0) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", VI.FONT_BODY)
	VI.tint_button(b, color)
	b.pressed.connect(on_press)
	return b


## Tarjeta con titulo; devuelve el VBox donde meter el contenido.
func make_card(node_name: String, title: String, accent: Color = VI.VIOLET) -> VBoxContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.add_theme_stylebox_override("panel", VI.window(accent, 0.96))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	if not title.is_empty():
		col.add_child(make_label(title, VI.FONT_SECTION, VI.GOLD_LIGHT))
	list.add_child(card)
	return col


## Abre el combate ya preparado en GameState (origen "mode").
func open_battle() -> bool:
	var app := NAV.app_of(self)
	if app == null or not app.has_method("open_battle"):
		return false
	app.call("open_battle")
	return true


func hp_text(ratio: float, alive: bool = true) -> String:
	return "CAIDO" if not alive else "%d%%" % int(round(ratio * 100.0))


## Lineas del ultimo informe de un modo (lo que acaba de pagar).
func add_last_report(col: VBoxContainer) -> void:
	var rep: Dictionary = GameState.modes.last_report
	if rep.is_empty():
		return
	col.add_child(make_label("ULTIMO RESULTADO", VI.FONT_SMALL, VI.GOLD))
	for line in rep.get("lines", []):
		col.add_child(make_label(String(line), VI.FONT_TINY, VI.INK))
	for d in rep.get("drops", []):
		col.add_child(make_label("+ %s x%d" % [String(d.get("name", "")), int(d.get("amount", 1))], VI.FONT_TINY, VI.GREEN))
	var parts := PackedStringArray()
	if int(rep.get("coins", 0)) > 0:
		parts.append("%d monedas" % int(rep["coins"]))
	if int(rep.get("gems", 0)) > 0:
		parts.append("%d gemas" % int(rep["gems"]))
	if int(rep.get("materials", 0)) > 0:
		parts.append("%d materiales" % int(rep["materials"]))
	if int(rep.get("xp", 0)) > 0:
		parts.append("%d XP por personaje" % int(rep["xp"]))
	if not parts.is_empty():
		col.add_child(make_label("Total: " + ", ".join(parts), VI.FONT_TINY, VI.GOLD_LIGHT))
