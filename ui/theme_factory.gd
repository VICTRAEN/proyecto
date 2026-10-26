extends RefCounted

## FABRICA DEL TEMA GLOBAL. Construye el Theme del juego a partir de VI (colores,
## marcos y tipografia), de modo que ui/theme.tres es un ARCHIVO GENERADO, no una
## segunda fuente de verdad:
##
##   godot --headless --path . --script res://tools/build_theme.gd
##
## regenera ui/theme.tres. El proyecto lo usa como tema por defecto
## (gui/theme/custom), asi que cualquier control, tenga o no tema propio en su
## escena, hereda botones, paneles, barras, sliders y scrollbars del juego.

const VI := preload("res://ui/visual_identity.gd")
const GRABBER := "res://assets/ui/slider_grabber.png"
const GRABBER_HOT := "res://assets/ui/slider_grabber_hot.png"


static func build() -> Theme:
	var theme := Theme.new()
	var font := VI.font("semibold")
	if font != null:
		theme.default_font = font
	theme.default_font_size = 27

	# --- Botones: los que no llaman a VI.tint_button salen en azul ---
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "Button", VI.button_frame(VI.BLUE, state))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", VI.INK)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", VI.GOLD_LIGHT)
	theme.set_color("font_disabled_color", "Button", Color(0.50, 0.48, 0.64, 1.0))
	theme.set_color("font_outline_color", "Button", Color(0.04, 0.0, 0.10, 0.70))
	theme.set_constant("outline_size", "Button", 5)
	theme.set_font_size("font_size", "Button", 31)
	var bold := VI.font("bold")
	if bold != null:
		theme.set_font("font", "Button", bold)

	# --- Etiquetas ---
	theme.set_color("font_color", "Label", VI.INK)
	theme.set_font_size("font_size", "Label", 27)

	# --- Desplegables ---
	for state in ["normal", "hover", "pressed", "disabled"]:
		var frame = VI.button_frame(VI.BLUE, state)
		frame.content_margin_top = 12.0
		frame.content_margin_bottom = 12.0
		frame.content_margin_left = 18.0
		frame.content_margin_right = 18.0
		theme.set_stylebox(state, "OptionButton", frame)
	theme.set_font_size("font_size", "OptionButton", 25)

	# --- Paneles ---
	theme.set_stylebox("panel", "PanelContainer", VI.panel())
	theme.set_stylebox("panel", "Panel", VI.panel())

	# --- Pestanas (ficha de personaje) ---
	theme.set_stylebox("tab_selected", "TabContainer", VI.tab_frame(true))
	theme.set_stylebox("tab_unselected", "TabContainer", VI.tab_frame(false))
	theme.set_stylebox("tab_hovered", "TabContainer", VI.tab_frame(false, true))
	theme.set_stylebox("tab_disabled", "TabContainer", VI.tab_frame(false))
	theme.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	theme.set_color("font_selected_color", "TabContainer", Color(0.22, 0.09, 0.0))
	theme.set_color("font_unselected_color", "TabContainer", VI.INK_SOFT)
	theme.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	theme.set_constant("side_margin", "TabContainer", 0)

	# --- Barras de progreso (vida, experiencia...) ---
	theme.set_stylebox("background", "ProgressBar", _bar_back())
	theme.set_stylebox("fill", "ProgressBar", bar_fill(Color(0.30, 0.90, 0.58)))
	theme.set_color("font_color", "ProgressBar", Color(1, 1, 1, 0))

	# --- Texto enriquecido ---
	theme.set_color("default_color", "RichTextLabel", VI.INK_SOFT)
	theme.set_font_size("normal_font_size", "RichTextLabel", 22)

	# --- Sliders de Ajustes ---
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.04, 0.03, 0.10, 1.0)
	track.set_corner_radius_all(6)
	track.set_border_width_all(2)
	track.border_color = Color(0.40, 0.34, 0.66, 1.0)
	track.content_margin_top = 6.0
	track.content_margin_bottom = 6.0
	theme.set_stylebox("slider", "HSlider", track)
	var area := StyleBoxFlat.new()
	area.bg_color = VI.GOLD
	area.set_corner_radius_all(6)
	area.content_margin_top = 6.0
	area.content_margin_bottom = 6.0
	theme.set_stylebox("grabber_area", "HSlider", area)
	var area_hot: StyleBoxFlat = area.duplicate()
	area_hot.bg_color = VI.GOLD_LIGHT
	theme.set_stylebox("grabber_area_highlight", "HSlider", area_hot)
	if ResourceLoader.exists(GRABBER):
		theme.set_icon("grabber", "HSlider", load(GRABBER))
		theme.set_icon("grabber_disabled", "HSlider", load(GRABBER))
	if ResourceLoader.exists(GRABBER_HOT):
		theme.set_icon("grabber_highlight", "HSlider", load(GRABBER_HOT))

	# --- Barras de desplazamiento: finas, doradas ---
	for kind in ["VScrollBar", "HScrollBar"]:
		var scroll := StyleBoxFlat.new()
		scroll.bg_color = Color(0.03, 0.02, 0.08, 0.55)
		scroll.set_corner_radius_all(8)
		theme.set_stylebox("scroll", kind, scroll)
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(0.74, 0.60, 0.98, 0.85)
		grab.set_corner_radius_all(8)
		theme.set_stylebox("grabber", kind, grab)
		var grab_hot: StyleBoxFlat = grab.duplicate()
		grab_hot.bg_color = VI.GOLD
		theme.set_stylebox("grabber_highlight", kind, grab_hot)
		theme.set_stylebox("grabber_pressed", kind, grab_hot)
	return theme


## Fondo de una barra: hueco oscuro con un filo cromado fino.
static func _bar_back() -> StyleBox:
	return VI.Frame.build({
		"fill_top": Color(0.02, 0.015, 0.06, 1.0),
		"fill_bottom": Color(0.06, 0.045, 0.14, 1.0),
		"metal_light": Color(0.62, 0.55, 0.86, 1.0),
		"metal_dark": Color(0.20, 0.16, 0.38, 1.0),
		"edge_width": 2.0,
		"cut": 5.0,
		"shadow": 0.0,
		"inner_glow": Color(0, 0, 0, 0),
		"margin_x": 0.0, "margin_y": 0.0,
	})


## Relleno de una barra: color liso con brillo en la mitad superior (glossy).
static func bar_fill(color: Color) -> StyleBox:
	return VI.Frame.build({
		"fill_top": color.lightened(0.28),
		"fill_bottom": color.darkened(0.22),
		"edge_width": 0.0,
		"cut": 5.0,
		"cut_corners": 15,
		"gloss": 0.7,
		"shadow": 0.0,
		"outline": Color(0, 0, 0, 0),
		"margin_x": 0.0, "margin_y": 0.0,
	})
