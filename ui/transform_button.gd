extends Control

## BOTON DE TRANSFORMACION (X.5): circular, con un icono dibujado por codigo (rayos giratorios,
## aro de energia y destello). Si la transformacion declara "icon" (PNG), se dibuja ese icono dentro
## del circulo; si no, un glifo de estrella evolutiva. Nombre estable del nodo: TransformButton.

signal pressed

const RAYS := 12
const TAU_F := TAU

var accent := Color(1.0, 0.80, 0.34, 1.0)
var accent2 := Color(1.0, 0.30, 0.74, 1.0)
var icon: Texture2D = null
var label_text := "TRANSFORMAR"
## "star" (transformacion) o "dome" (dominio: una cupula con su barrera).
var glyph := "star"
var disabled := false:
	set(value):
		disabled = value
		queue_redraw()
var _time := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(150, 150)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	visibility_changed.connect(func(): set_process(is_visible_in_tree()))


func configure(color_a: Color, color_b: Color, new_icon: Texture2D, text: String = "TRANSFORMAR", new_glyph: String = "star") -> void:
	glyph = new_glyph
	accent = color_a
	accent2 = color_b
	icon = new_icon
	label_text = text
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.distance_to(center) <= radius:
			pressed.emit()
			accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		if event.position.distance_to(center) <= radius:
			pressed.emit()
			accept_event()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 4.0
	var pulse := 0.5 + 0.5 * sin(_time * 3.2)
	var a := accent
	var b := accent2
	if disabled:
		a = a.darkened(0.6)
		b = b.darkened(0.6)
	# Halo exterior que respira.
	for i in 6:
		var k := float(i) / 6.0
		draw_circle(center, radius * (1.0 - k * 0.04) + 6.0 * pulse * (1.0 - k), Color(a.r, a.g, a.b, 0.05 + 0.03 * pulse))
	# Rayos giratorios (dos capas en sentido contrario).
	for layer in 2:
		var dir := 1.0 if layer == 0 else -1.0
		var rot := _time * (0.9 if layer == 0 else 1.4) * dir
		var reach := radius * (1.0 if layer == 0 else 0.82)
		var col := a if layer == 0 else b
		for i in RAYS:
			var ang := rot + TAU_F * float(i) / float(RAYS)
			var tip := center + Vector2(cos(ang), sin(ang)) * reach
			var left := center + Vector2(cos(ang - 0.11), sin(ang - 0.11)) * radius * 0.46
			var right := center + Vector2(cos(ang + 0.11), sin(ang + 0.11)) * radius * 0.46
			draw_colored_polygon(PackedVector2Array([left, tip, right]), Color(col.r, col.g, col.b, 0.55 if layer == 0 else 0.4))
	# Disco central con degradado radial aproximado.
	for i in 10:
		var k2 := float(i) / 9.0
		var c := a.lerp(b, k2)
		draw_circle(center, radius * (0.66 - 0.5 * k2 * 0.9), Color(c.r * (0.35 + 0.5 * k2), c.g * (0.25 + 0.5 * k2), c.b * (0.4 + 0.5 * k2), 1.0))
	# Aro de energia con arcos que giran.
	draw_arc(center, radius * 0.7, 0.0, TAU_F, 64, Color(1, 1, 1, 0.9 if not disabled else 0.3), 4.0, true)
	for i in 3:
		var start := _time * 2.0 + TAU_F * float(i) / 3.0
		draw_arc(center, radius * 0.78, start, start + 0.9, 20, Color(b.r, b.g, b.b, 0.95), 6.0, true)
	# Icono: PNG de la transformacion o glifo de estrella evolutiva.
	if icon != null:
		var side := radius * 1.05
		draw_texture_rect(icon, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), false, Color(1, 1, 1, 0.3 if disabled else 1.0))
	elif glyph == "dome":
		# Cupula del dominio: arco exterior, arco interior y suelo, con un nucleo que late.
		var floor_y := center.y + radius * 0.22
		draw_arc(Vector2(center.x, floor_y), radius * 0.40, PI, TAU_F, 32, Color(1, 1, 1, 0.95 if not disabled else 0.35), 4.0, true)
		draw_arc(Vector2(center.x, floor_y), radius * 0.26, PI, TAU_F, 32, Color(1, 1, 1, 0.7 if not disabled else 0.3), 3.0, true)
		draw_line(Vector2(center.x - radius * 0.46, floor_y), Vector2(center.x + radius * 0.46, floor_y), Color(1, 1, 1, 0.9 if not disabled else 0.35), 4.0, true)
		draw_circle(Vector2(center.x, floor_y - radius * 0.13), radius * 0.07 * (1.0 + 0.5 * pulse), Color(b.r, b.g, b.b, 1.0))
		for k in 3:
			var ang3 := PI + PI * float(k + 1) / 4.0
			draw_line(Vector2(center.x, floor_y) + Vector2(cos(ang3), sin(ang3)) * radius * 0.26, Vector2(center.x, floor_y) + Vector2(cos(ang3), sin(ang3)) * radius * 0.40, Color(1, 1, 1, 0.6), 2.0, true)
	else:
		var star := PackedVector2Array()
		for i in 8:
			var ang2 := -PI / 2.0 + TAU_F * float(i) / 8.0
			var r2 := radius * (0.44 if i % 2 == 0 else 0.15)
			star.append(center + Vector2(cos(ang2), sin(ang2)) * r2)
		draw_colored_polygon(star, Color(1, 1, 1, 0.95 if not disabled else 0.35))
		draw_circle(center, radius * 0.1 * (1.0 + 0.4 * pulse), Color(a.r, a.g, a.b, 1.0))
		# Chevrones ascendentes (evolucion).
		for j in 2:
			var y := center.y + radius * (0.5 - 0.12 * float(j))
			draw_polyline(PackedVector2Array([Vector2(center.x - radius * 0.16, y), Vector2(center.x, y - radius * 0.1), Vector2(center.x + radius * 0.16, y)]), Color(1, 1, 1, 0.8), 3.0, true)
	# Texto en la franja inferior.
	var font := ThemeDB.fallback_font
	var fsize := 17
	var text_w := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize).x
	draw_string(font, Vector2(center.x - text_w * 0.5, size.y - 4.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 1, 1, 0.95 if not disabled else 0.4), 2)
