extends Control

## BANNER DE TITULO. Cabecera de pantalla con identidad propia: una placa
## angulada de marco dorado biselado, con una gema en el centro y dos "alas" de
## luz que se pierden hacia los lados. Debajo, un subtitulo opcional.
##
## Es el unico sitio que dibuja una cabecera de este estilo: las pantallas la
## crean con TitleBanner.make(...) y no dibujan ni una linea.
##
##   var banner := TitleBanner.make("INVOCAR", "Elige un banner", VI.MAGENTA)
##   column.add_child(banner)

const VI := preload("res://ui/visual_identity.gd")
const Frame := preload("res://ui/vi_frame.gd")

var accent := VI.GOLD
var _title: Label = null
var _subtitle: Label = null
var _plate: StyleBox = null
var _plate_h := 84.0
var _font_size := VI.FONT_BIG


static func make(title_text: String, subtitle_text: String = "", color: Color = VI.GOLD, font_size: int = VI.FONT_BIG) -> Control:
	var banner = load("res://ui/title_banner.gd").new()
	banner.setup(title_text, subtitle_text, color, font_size)
	return banner


## ADOPTA el Label de titulo que ya tiene una escena: lo sustituye en su sitio por
## una placa y el Label pasa a ser el texto de la placa. El script de la pantalla
## sigue escribiendo en SU label (title_label.text = ...) y la placa se ajusta sola.
static func adopt(label: Label, color: Color = VI.GOLD, font_size: int = VI.FONT_BIG) -> Control:
	var parent := label.get_parent()
	if parent == null:
		return null
	var index := label.get_index()
	var banner = load("res://ui/title_banner.gd").new()
	parent.add_child(banner)
	parent.move_child(banner, index)
	parent.remove_child(label)
	banner.name = "TitleBanner"
	banner.size_flags_horizontal = label.size_flags_horizontal
	banner.setup(label.text, "", color, font_size, label)
	return banner


func setup(title_text: String, subtitle_text: String = "", color: Color = VI.GOLD, font_size: int = VI.FONT_BIG, existing: Label = null) -> void:
	accent = color
	_font_size = font_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in get_children():
		if child != existing:
			child.queue_free()
	if existing != null:
		_title = existing
		if _title.get_parent() == null:
			add_child(_title)
	else:
		_title = Label.new()
		_title.text = title_text
	VI.style_title(_title, font_size)
	if color != VI.GOLD:
		_title.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.55))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_plate_h = float(font_size) * 1.55
	var total_h := _plate_h + 14.0
	if not subtitle_text.is_empty():
		_subtitle = Label.new()
		_subtitle.text = subtitle_text
		VI.style_subtitle(_subtitle)
		_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_subtitle)
		total_h += 34.0
	custom_minimum_size = Vector2(0.0, total_h)
	_plate = Frame.build({
		"fill_top": Color(0.17, 0.10, 0.34, 0.97),
		"fill_bottom": Color(0.05, 0.03, 0.14, 0.97),
		"metal_light": VI.METAL_GOLD_LIGHT if accent == VI.GOLD else accent.lerp(Color.WHITE, 0.5),
		"metal_dark": VI.METAL_GOLD_DARK if accent == VI.GOLD else accent.darkened(0.55),
		"edge_width": 4.0,
		"cut": 20.0,
		"cut_corners": Frame.CORNERS_ALL,
		"inner_glow": Color(accent.r, accent.g, accent.b, 0.45),
		"glow": Color(accent.r, accent.g, accent.b, 0.35),
		"glow_size": 10.0,
		"gloss": 0.35,
		"studs": true,
		"stud_color": accent,
		"shadow": 0.55,
	})
	resized.connect(_layout)
	if not _title.minimum_size_changed.is_connected(_layout):
		_title.minimum_size_changed.connect(_layout)
	_layout()


func _plate_rect() -> Rect2:
	var text_w := 240.0
	if _title != null:
		text_w = _title.get_combined_minimum_size().x
	var w := minf(size.x - 24.0, text_w + 150.0)
	return Rect2((size.x - w) * 0.5, 4.0, w, _plate_h)


func _layout() -> void:
	if _title == null:
		return
	# Titulos largos ("SELECCIONAR BATALLA"): se encoge la letra hasta que quepa en
	# una linea dentro de la placa, en vez de partirse en dos.
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var fs := _font_size
	_title.add_theme_font_size_override("font_size", fs)
	while fs > 26 and _title.get_combined_minimum_size().x + 150.0 > size.x - 24.0 and size.x > 0.0:
		fs -= 2
		_title.add_theme_font_size_override("font_size", fs)
	var r := _plate_rect()
	_title.position = r.position
	_title.size = r.size
	if _subtitle != null:
		_subtitle.position = Vector2(0.0, r.end.y + 8.0)
		_subtitle.size = Vector2(size.x, 28.0)
	queue_redraw()


func _draw() -> void:
	if _plate == null:
		return
	var r := _plate_rect()
	var mid_y := r.position.y + r.size.y * 0.5
	# Alas de luz: una linea que se desvanece hacia el borde, con rombos.
	for side in [-1, 1]:
		var x0: float = r.position.x - 6.0 if side < 0 else r.end.x + 6.0
		var x1: float = 8.0 if side < 0 else size.x - 8.0
		var steps := 14
		for k in steps:
			var t0 := float(k) / float(steps)
			var t1 := float(k + 1) / float(steps)
			var a := (1.0 - t0) * 0.9
			draw_line(Vector2(lerpf(x0, x1, t0), mid_y), Vector2(lerpf(x0, x1, t1), mid_y), Color(accent.r, accent.g, accent.b, a), 3.0)
		draw_line(Vector2(lerpf(x0, x1, 0.04), mid_y + 10.0), Vector2(lerpf(x0, x1, 0.55), mid_y + 10.0), Color(accent.r, accent.g, accent.b, 0.35), 1.5)
		var dx: float = x0 + (x1 - x0) * 0.16
		_diamond(Vector2(dx, mid_y), 9.0, accent)
	draw_style_box(_plate, r)
	# Gema central sobre el borde superior.
	_diamond(Vector2(r.position.x + r.size.x * 0.5, r.position.y - 1.0), 12.0, accent.lerp(Color.WHITE, 0.35))


func _diamond(center: Vector2, s: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -s), center + Vector2(s * 0.7, 0), center + Vector2(0, s), center + Vector2(-s * 0.7, 0)]), color.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -s), center + Vector2(s * 0.7, 0), center, center + Vector2(-s * 0.7, 0)]), color.lightened(0.25))
	draw_polyline(PackedVector2Array([center + Vector2(0, -s), center + Vector2(s * 0.7, 0), center + Vector2(0, s), center + Vector2(-s * 0.7, 0), center + Vector2(0, -s)]), Color(0, 0, 0, 0.6), 1.2, true)
