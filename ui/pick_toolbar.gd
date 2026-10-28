class_name PickToolbar
extends VBoxContainer

## BARRA DE BUSQUEDA Y FILTROS para elegir personajes (v11). La usan EVOLUCION y
## MUTACIONES. No conoce ninguna regla del juego: solo guarda el texto buscado y el
## filtro activo, y avisa con `changed` para que la pantalla vuelva a pintar su lista.
##   - Buscador: coincide con cualquier parte del nombre, sin importar mayusculas ni
##     acentos basicos.
##   - Filtros: botones de una fila (el activo en dorado). La pantalla decide cuales.
##   - Contador: una linea con "3 LISTOS de 12" (o lo que la pantalla ponga).

const VI := preload("res://ui/visual_identity.gd")

signal changed

var query := ""
var filter_key := "all"
var _filters: Array = []
var _search: LineEdit = null
var _row: HBoxContainer = null
var _count: Label = null
var _buttons: Dictionary = {}


## filters: [{ "key": "ready", "label": "LISTOS" }, ...]; el primero es el de por defecto.
func setup(filters: Array, placeholder: String = "Buscar personaje...") -> void:
	name = "PickToolbar"
	add_theme_constant_override("separation", 8)
	_filters = filters
	if not filters.is_empty() and not _has_key(filter_key):
		filter_key = String((filters[0] as Dictionary)["key"])
	_search = LineEdit.new()
	_search.name = "SearchBox"
	_search.placeholder_text = placeholder
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0, 56)
	_search.add_theme_font_size_override("font_size", VI.FONT_BODY)
	_search.text_changed.connect(_on_text_changed)
	add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.name = "FilterScroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 60)
	add_child(scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	scroll.add_child(_row)
	for entry in filters:
		var key := String((entry as Dictionary)["key"])
		var button := Button.new()
		button.name = "Filter_%s" % key
		button.text = String((entry as Dictionary)["label"])
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 52)
		button.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		button.pressed.connect(_on_filter_pressed.bind(key))
		_row.add_child(button)
		_buttons[key] = button
	_count = Label.new()
	_count.name = "CountLabel"
	_count.add_theme_font_size_override("font_size", VI.FONT_TINY)
	_count.add_theme_color_override("font_color", VI.INK_SOFT)
	add_child(_count)
	_paint()


func _has_key(key: String) -> bool:
	for entry in _filters:
		if String((entry as Dictionary)["key"]) == key:
			return true
	return false


func set_count_text(text: String) -> void:
	if _count != null:
		_count.text = text


## Pone el filtro por codigo (lo usan las pruebas y las pantallas al abrir).
func select_filter(key: String) -> void:
	if not _has_key(key):
		return
	filter_key = key
	_paint()
	changed.emit()


func set_query(text: String) -> void:
	query = text
	if _search != null and _search.text != text:
		_search.text = text
	changed.emit()


## Coincide el nombre con lo buscado? (vacio = todo coincide)
func text_matches(display_name: String) -> bool:
	var q := _fold(query.strip_edges())
	if q.is_empty():
		return true
	return _fold(display_name).contains(q)


static func _fold(text: String) -> String:
	var t := text.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ñ", "n"], ["ü", "u"]]:
		t = t.replace(pair[0], pair[1])
	return t


func _on_text_changed(text: String) -> void:
	query = text
	changed.emit()


func _on_filter_pressed(key: String) -> void:
	filter_key = key
	_paint()
	changed.emit()


func _paint() -> void:
	for key in _buttons.keys():
		var button: Button = _buttons[key]
		VI.tint_button(button, VI.GOLD if String(key) == filter_key else VI.BLUE)
