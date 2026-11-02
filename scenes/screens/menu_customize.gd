extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")

## PERSONALIZAR MENU (v16): fondos, temas de color y decoraciones animadas del menu
## principal. Solo se puede elegir lo desbloqueado (cosmeticos de data/cosmetics, que da el
## nivel de cuenta). Anadir uno nuevo = un JSON en data/cosmetics (tipo background, theme
## o decoration) y asignarlo a un nivel en data/account/levels.json.
## Nodos estables: List, Feedback, BackButton, Cos_<id>, Cos_none_<tipo>.

var _list: VBoxContainer
var _feedback: Label


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
	title.text = "PERSONALIZAR MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(title)
	VI.screen_title(title, VI.GOLD)
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
	_list.add_theme_constant_override("separation", 12)
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
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_section("FONDOS", "background", "Fondo normal")
	_section("TEMAS DE COLOR", "theme", "Sin tema")
	_section("DECORACIONES", "decoration", "Sin decoracion")
	var bg := get_node_or_null("Background")
	if bg != null and bg.has_method("show_slot"):
		bg.call("show_slot", GameState.account.menu_background_slot())
		var deco: Dictionary = GameState.profile.equipped_data("decoration")
		bg.call("set_ambient_override", [] if deco.is_empty() else [String(deco.get("mode", "motes")), int(deco.get("count", 24)), Color(String(deco.get("color", "#ffffff"))), Color(String(deco.get("color2", "#ffffff")))])


func _equipped(type_name: String) -> String:
	return GameState.account.background_equipped if type_name == "background" else GameState.profile.equipped_id(type_name)


func _section(text: String, type_name: String, none_label: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	l.add_theme_color_override("font_color", VI.GOLD)
	_list.add_child(l)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_list.add_child(grid)
	var cur := _equipped(type_name)
	grid.add_child(_btn("", none_label, type_name, cur.is_empty()))
	for id in GameState.account.owned_of_type(type_name):
		grid.add_child(_btn(String(id), String(DB.get_cosmetic(String(id)).get("name", id)), type_name, cur == String(id)))
	var locked := 0
	for c in DB.all_cosmetics():
		if String((c as Dictionary).get("type", "")) == type_name and not GameState.account.owns_cosmetic(String(c["id"])):
			locked += 1
	if locked > 0:
		var n := Label.new()
		n.text = "%d por desbloquear con niveles de cuenta." % locked
		n.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		n.add_theme_color_override("font_color", VI.INK_SOFT)
		_list.add_child(n)


func _btn(id: String, label: String, type_name: String, on: bool) -> Button:
	var b := Button.new()
	b.name = "Cos_%s" % (id if not id.is_empty() else "none_" + type_name)
	b.text = ("%s\nEQUIPADO" % label) if on else label
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 92)
	b.add_theme_font_size_override("font_size", VI.FONT_BODY)
	var tint: Color = VI.GOLD if on else VI.VIOLET
	if type_name == "theme" and not id.is_empty():
		tint = Color(String(DB.get_cosmetic(id).get("tint", "#7a3dff")))
	VI.tint_button(b, tint)
	b.pressed.connect(_on_pick.bind(id, type_name))
	return b


func _on_pick(id: String, type_name: String) -> void:
	var ok: bool = GameState.account.equip_background(id) if type_name == "background" else GameState.profile.equip(type_name, id)
	if ok:
		GameState.save_game()
		_feedback.text = "Guardado."
	refresh()


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")
