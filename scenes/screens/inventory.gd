extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")

## INVENTARIO: los objetos que el jugador tiene DE VERDAD.
##
## La lista sale del catalogo (DB.all_items(), res://data/items/*.json) cruzado con
## las CANTIDADES que guarda GameState.item_count(). Esta pantalla no lleva su
## propia cuenta y no toca nunca el inventario: solo lo pinta. Quien suma y quien
## gasta objetos es siempre GameState (add_item / remove_item), asi que no puede
## haber dos verdades sobre cuantos uniformes hay.
##
## El catalogo es GENERICO: sirve igual para materiales, tickets y objetos
## evolutivos. Un objeto nuevo es un JSON mas su PNG en res://art/items/.
##
## El icono sale del campo "icon" del JSON, asi que no hay ninguna ruta de imagen
## escrita aqui. Si el PNG todavia no existe se dibuja un marcador con la inicial
## del objeto sobre el color de su rareza: falta arte, pero nada se rompe.

@onready var title_label: Label = $Margin/Main/Title
@onready var subtitle_label: Label = $Margin/Main/Subtitle
@onready var list: VBoxContainer = $Margin/Main/Scroll/List
@onready var back_button: Button = $Margin/Main/BackButton


func _ready() -> void:
	_apply_identity()
	back_button.pressed.connect(_back)


## Aspecto estatico, con los tokens de la identidad visual.
func _apply_identity() -> void:
	VI.style_title(title_label, VI.FONT_BIG)
	VI.style_subtitle(subtitle_label)
	VI.tint_button(back_button, VI.BLUE)
	back_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)


## La pantalla se repinta cada vez que App la muestra: una recompensa o una
## evolucion pueden haber cambiado las cantidades.
func refresh() -> void:
	_build()


## INVENTARIO = una mochila de verdad: CARTERA arriba (monedas, gemas, materiales de
## mejora), CATEGORIAS como pestanas, y una REJILLA de casillas con la cantidad
## visible. Las casillas libres se dibujan vacias hasta completar filas, asi la
## mochila se ve como una mochila y no como una lista. Tocar una casilla abre su
## detalle debajo. Las categorias salen del "type" de cada objeto (data/items).
const CATEGORY_NAMES := {
	"all": "TODO",
	"evolution_material": "EVOLUCION",
	"consumable": "CONSUMIBLES",
	"token": "FICHAS",
	"special": "ESPECIALES",
}
const COLUMNS := 3
const MIN_SLOTS := 9

var _category := "all"
var _selected_item := ""
var _wallet: HBoxContainer = null
var _tabs: HBoxContainer = null
var _grid: GridContainer = null
var _detail: PanelContainer = null


func _ensure_layout() -> void:
	if _grid != null:
		return
	var main: VBoxContainer = list.get_parent().get_parent()
	var scroll: Node = list.get_parent()
	var index := scroll.get_index()
	_wallet = HBoxContainer.new()
	_wallet.name = "Wallet"
	_wallet.add_theme_constant_override("separation", 10)
	main.add_child(_wallet)
	main.move_child(_wallet, index)
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 6)
	main.add_child(_tabs)
	main.move_child(_tabs, index + 1)
	_grid = GridContainer.new()
	_grid.name = "ItemGrid"
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	list.add_child(_grid)
	_detail = PanelContainer.new()
	_detail.name = "ItemDetail"
	main.add_child(_detail)
	main.move_child(_detail, scroll.get_index() + 1)


func _build() -> void:
	_ensure_layout()
	_build_wallet()
	var entries: Array = owned_items()
	_build_tabs(entries)
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var shown: Array = []
	for entry in entries:
		if _category == "all" or _category_of(entry) == _category:
			shown.append(entry)
	var units := 0
	for entry in entries:
		units += int(entry["count"])
	subtitle_label.text = ("%d objetos distintos, %d unidades en total." % [entries.size(), units]) if not entries.is_empty() else "La mochila esta vacia. Los eventos y las recompensas la van llenando."
	for entry in shown:
		_grid.add_child(_make_slot(entry))
	var total := maxi(MIN_SLOTS, int(ceil(float(shown.size()) / float(COLUMNS))) * COLUMNS)
	for i in range(shown.size(), total):
		_grid.add_child(_make_empty_slot())
	_build_detail(entries)


func _category_of(item: Dictionary) -> String:
	var t := String(item.get("type", ""))
	return t if CATEGORY_NAMES.has(t) else "special"


func _build_wallet() -> void:
	for child in _wallet.get_children():
		_wallet.remove_child(child)
		child.queue_free()
	_wallet.add_child(_wallet_chip("MONEDAS", GameState.coins, VI.GOLD))
	_wallet.add_child(_wallet_chip("GEMAS", GameState.gems, Color(0.55, 0.9, 1.0)))
	_wallet.add_child(_wallet_chip("MATERIALES", GameState.materials, VI.GREEN))


func _wallet_chip(title: String, value: int, color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", VI.card(color, false, "", false))
	var v := VBoxContainer.new()
	panel.add_child(v)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", VI.FONT_TINY)
	t.add_theme_color_override("font_color", VI.INK_DIM)
	v.add_child(t)
	var n := Label.new()
	n.text = str(value)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	n.add_theme_color_override("font_color", color)
	v.add_child(n)
	return panel


func _build_tabs(entries: Array) -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	var present := {"all": true}
	for entry in entries:
		present[_category_of(entry)] = true
	if not present.has(_category):
		_category = "all"
	for key in CATEGORY_NAMES.keys():
		if not present.has(key):
			continue
		var tab := Button.new()
		tab.text = String(CATEGORY_NAMES[key])
		tab.toggle_mode = true
		tab.button_pressed = key == _category
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, 64)
		tab.add_theme_font_size_override("font_size", VI.FONT_TINY)
		VI.tint_button(tab, VI.GOLD if key == _category else VI.BLUE)
		tab.pressed.connect(_on_tab.bind(String(key)))
		_tabs.add_child(tab)


func _on_tab(key: String) -> void:
	_category = key
	_build()


func _make_slot(item: Dictionary) -> Control:
	var rarity := String(item.get("rarity", ""))
	var accent: Color = VI.rarity_color(rarity) if not rarity.is_empty() else VI.BLUE
	var panel := PanelContainer.new()
	panel.name = "Slot_%s" % String(item.get("id", ""))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 230)
	var selected := String(item.get("id", "")) == _selected_item
	panel.add_theme_stylebox_override("panel", VI.card(accent, selected, rarity, false))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var icon := _make_icon(item)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(110, 110)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	var name_label := Label.new()
	name_label.text = String(item.get("name", ""))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", VI.FONT_TINY)
	name_label.add_theme_color_override("font_color", accent)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_label)
	var count := Label.new()
	count.text = "x%d" % int(item.get("count", 0))
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	count.add_theme_color_override("font_color", VI.GOLD)
	count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	count.add_theme_constant_override("outline_size", 6)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(count)
	panel.gui_input.connect(_on_slot_input.bind(String(item.get("id", ""))))
	return panel


func _make_empty_slot() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 230)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = VI.panel(0.35, true, VI.RADIUS_CARD)
	style.border_color = Color(VI.INK_DIM.r, VI.INK_DIM.g, VI.INK_DIM.b, 0.35)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _on_slot_input(event: InputEvent, item_id: String) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		_selected_item = item_id
		_build()


func _build_detail(entries: Array) -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	var item: Dictionary = {}
	for entry in entries:
		if String(entry["id"]) == _selected_item:
			item = entry
	_detail.add_theme_stylebox_override("panel", VI.panel(0.92, true, VI.RADIUS_PANEL))
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	if item.is_empty():
		label.text = "Toca una casilla para ver el objeto."
		label.add_theme_color_override("font_color", VI.INK_DIM)
	else:
		label.text = "%s  x%d\n%s\n%s" % [String(item["name"]), int(item["count"]), String(item["description"]),
			("Se consigue: %s" % String(item["obtained_from"])) if not String(item["obtained_from"]).is_empty() else ""]
		label.add_theme_color_override("font_color", VI.INK)
	_detail.add_child(label)


## Objetos que el jugador tiene, con cantidad mayor que cero, ya resueltos para
## pintar: { id, name, description, count, type, rarity, icon }. Ordenados por
## nombre para que la lista no cambie de sitio entre repintados.
func owned_items() -> Array:
	var out: Array = []
	for raw in DB.all_items():
		if not (raw is Dictionary):
			continue
		var data: Dictionary = raw
		var id := String(data.get("id", ""))
		if id.is_empty():
			continue
		var count := GameState.item_count(id)
		if count <= 0:
			continue
		out.append({
			"id": id,
			"name": String(data.get("name", id)),
			"description": String(data.get("description", "")),
			"count": count,
			"type": String(data.get("type", "")),
			"rarity": String(data.get("rarity", "")),
			"icon": String(data.get("icon", "")),
			"obtained_from": String(data.get("obtained_from", "")),
		})
	out.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
	return out


## Tarjeta de un objeto: icono, nombre, cantidad y descripcion. La cantidad manda
## (es lo que se viene a mirar), asi que va grande y en dorado.
func _make_card(item: Dictionary) -> Control:
	var rarity := String(item.get("rarity", ""))
	var accent: Color = VI.rarity_color(rarity) if not rarity.is_empty() else VI.BLUE

	var card := PanelContainer.new()
	var style: StyleBoxFlat = VI.panel(0.93, true, VI.RADIUS_PANEL)
	style.set_border_width_all(3)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	row.add_child(_make_icon(item))

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	row.add_child(box)

	var name_label := Label.new()
	name_label.text = String(item.get("name", ""))
	name_label.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	name_label.add_theme_color_override("font_color", accent)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "Cantidad: %d" % int(item.get("count", 0))
	count_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
	count_label.add_theme_color_override("font_color", VI.GOLD)
	box.add_child(count_label)

	var description := String(item.get("description", ""))
	if not description.is_empty():
		var description_label := Label.new()
		description_label.text = description
		description_label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		description_label.add_theme_color_override("font_color", VI.INK_SOFT)
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(description_label)

	# Tipo y rareza: dos datos que el catalogo ya trae y que ayudan a saber para
	# que sirve el objeto sin leer la descripcion entera.
	var parts := PackedStringArray()
	if not rarity.is_empty():
		parts.append(rarity)
	var type_text := String(item.get("type", ""))
	if not type_text.is_empty():
		parts.append(type_text)
	if parts.size() > 0:
		var meta := Label.new()
		meta.text = "  -  ".join(parts)
		meta.add_theme_font_size_override("font_size", VI.FONT_TINY)
		meta.add_theme_color_override("font_color", VI.INK_DIM)
		box.add_child(meta)

	return card


## Icono del objeto. El PNG lo aporta el jugador en la ruta que declare su JSON;
## mientras no exista, un marcador con la inicial para que la ficha siga leyendose.
func _make_icon(item: Dictionary) -> Control:
	var side := 116.0
	var path := String(item.get("icon", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var loaded = load(path)
		if loaded is Texture2D:
			var texture_rect := TextureRect.new()
			texture_rect.texture = loaded
			texture_rect.custom_minimum_size = Vector2(side, side)
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return texture_rect

	var rarity := String(item.get("rarity", ""))
	var accent: Color = VI.rarity_color(rarity) if not rarity.is_empty() else VI.BLUE
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(side, side)
	var style: StyleBoxFlat = VI.panel(0.88, true, VI.RADIUS_CHIP)
	style.set_border_width_all(3)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.9)
	holder.add_theme_stylebox_override("panel", style)

	var initial := Label.new()
	initial.text = _initial(String(item.get("name", "?")))
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_size_override("font_size", VI.FONT_BIG)
	initial.add_theme_color_override("font_color", accent)
	holder.add_child(initial)
	return holder


func _initial(text_value: String) -> String:
	var clean := text_value.strip_edges()
	if clean.is_empty():
		return "?"
	return clean.substr(0, 1).to_upper()


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", VI.FONT_BODY)
	label.add_theme_color_override("font_color", VI.INK_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	return label


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
