extends PanelContainer

## FICHA DE CARTERA: icono semi-3D + cantidad en una placa angulada. Sirve para
## monedas, gemas y cualquier otro recurso con icono (kind = nombre del icono).
## Cambiar el valor es set_value(); no hay que reconstruir nada.

const VI := preload("res://ui/visual_identity.gd")

var kind := "coin"
var _value_label: Label = null
var _icon: TextureRect = null
var _value := 0


static func make(icon_name: String, value: int, color: Color, icon_px: float = 46.0) -> PanelContainer:
	var chip = load("res://ui/wallet_chip.gd").new()
	chip.setup(icon_name, value, color, icon_px)
	return chip


func setup(icon_name: String, value: int, color: Color, icon_px: float = 46.0) -> void:
	kind = icon_name
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := VI.chip(color, 0.94)
	frame.content_margin_left = 12.0
	frame.content_margin_right = 18.0
	frame.content_margin_top = 4.0
	frame.content_margin_bottom = 4.0
	add_theme_stylebox_override("panel", frame)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = VI.icon_rect(icon_name, icon_px)
	row.add_child(_icon)
	_value_label = Label.new()
	_value_label.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	_value_label.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.72))
	_value_label.add_theme_color_override("font_outline_color", Color(0.04, 0.0, 0.10, 0.85))
	_value_label.add_theme_constant_override("outline_size", 5)
	var bold := VI.font("bold")
	if bold != null:
		_value_label.add_theme_font_override("font", bold)
	_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_value_label)
	set_value(value)


func set_value(value: int) -> void:
	_value = value
	if _value_label != null:
		_value_label.text = _format(value)


func value() -> int:
	return _value


## 12840 -> "12.840": separador de miles para leer de un vistazo.
static func _format(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if n < 0 else "") + out
