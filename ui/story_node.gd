extends Control
## NODO DE MUNDO del mapa de Historia. Cada fila es un tramo del camino: un
## medallon con el progreso del mundo, una placa con su nombre y un sendero
## punteado que baja hasta el nodo siguiente. Los nodos se alternan izquierda /
## derecha para que la pantalla sea un MAPA y no una lista.
##
## Todo se dibuja por codigo (sin texturas). Solo un mundo desbloqueado responde
## al toque. Senal: pressed(world_id).

const VI := preload("res://ui/visual_identity.gd")

signal pressed(world_id: String)

const ROW_H := 470.0
const NODE_R := 92.0

var status: Dictionary = {}
var index := 0
var has_next := false
var _unlocked := false
var _complete := false
var _accent := VI.BLUE
var _time := 0.0


func setup(new_status: Dictionary, new_index: int, next_exists: bool) -> void:
	status = new_status
	index = new_index
	has_next = next_exists
	_unlocked = bool(status.get("unlocked", false))
	var done := int(status.get("levels_completed", 0))
	var total := int(status.get("level_count", 0))
	_complete = _unlocked and total > 0 and done >= total
	_accent = VI.INK_DIM if not _unlocked else (VI.GREEN if _complete else VI.GOLD)
	custom_minimum_size = Vector2(0, ROW_H)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP if _unlocked else Control.MOUSE_FILTER_IGNORE
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build_plaque()
	set_process(_unlocked and not _complete)
	queue_redraw()


func _node_center() -> Vector2:
	var left := index % 2 == 0
	return Vector2(size.x * (0.22 if left else 0.78), ROW_H * 0.46)


func _next_center() -> Vector2:
	var left := (index + 1) % 2 == 0
	return Vector2(size.x * (0.22 if left else 0.78), ROW_H * 1.46)


func _build_plaque() -> void:
	var plaque := PanelContainer.new()
	plaque.name = "Plaque"
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := VI.panel(0.92, true, VI.RADIUS_CARD)
	st.border_color = Color(_accent.r, _accent.g, _accent.b, 0.85)
	st.set_border_width_all(2)
	plaque.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_child(v)
	var nm := Label.new()
	nm.text = String(status.get("name", ""))
	nm.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	nm.add_theme_color_override("font_color", _accent if _unlocked else VI.INK_SOFT)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(nm)
	var genre := String(DB.get_world(String(status.get("id", ""))).get("genre", ""))
	var meta := Label.new()
	var total := int(status.get("level_count", 0))
	meta.text = "%s  -  %d/%d niveles" % [genre, int(status.get("levels_completed", 0)), total]
	meta.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	meta.add_theme_color_override("font_color", VI.INK_SOFT)
	v.add_child(meta)
	var state := Label.new()
	state.text = "BLOQUEADO" if not _unlocked else ("COMPLETADO" if _complete else "ENTRAR  >")
	state.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	state.add_theme_color_override("font_color", _accent)
	v.add_child(state)
	add_child(plaque)
	plaque.custom_minimum_size = Vector2(0, 0)
	plaque.set_meta("w", 0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_plaque()
		queue_redraw()


func _place_plaque() -> void:
	var plaque := get_node_or_null("Plaque") as Control
	if plaque == null:
		return
	var left := index % 2 == 0
	var w := size.x * 0.46
	plaque.size = Vector2(w, 0)
	plaque.position = Vector2(size.x * 0.50 if left else size.x * 0.04, 0)
	plaque.reset_size()
	plaque.size.x = w
	plaque.position.y = _node_center().y - plaque.size.y / 2.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var c := _node_center()
	# Sendero punteado hasta el siguiente nodo (curva suave en S).
	if has_next:
		var n := _next_center()
		var prev_p := c
		var steps := 22
		var path_color := Color(_accent.r, _accent.g, _accent.b, 0.55) if _complete else Color(VI.INK_DIM.r, VI.INK_DIM.g, VI.INK_DIM.b, 0.5)
		for i in range(1, steps + 1):
			var t := float(i) / steps
			var p := Vector2(lerpf(c.x, n.x, t * t * (3.0 - 2.0 * t)), lerpf(c.y, n.y, t))
			if i % 2 == 0:
				draw_line(prev_p, p, path_color, 9.0, true)
			prev_p = p
	# Medallon.
	var done := int(status.get("levels_completed", 0))
	var total := maxi(1, int(status.get("level_count", 0)))
	if _unlocked and not _complete:
		var pulse := 0.5 + 0.5 * sin(_time * 3.0)
		draw_circle(c, NODE_R + 8.0 + pulse * 5.0, Color(_accent.r, _accent.g, _accent.b, 0.18))
	draw_circle(c, NODE_R, Color(0.06, 0.07, 0.15, 0.97))
	draw_arc(c, NODE_R - 7.0, 0.0, TAU, 48, Color(_accent.r, _accent.g, _accent.b, 0.25), 12.0, true)
	if _unlocked and done > 0:
		draw_arc(c, NODE_R - 7.0, -PI / 2.0, -PI / 2.0 + TAU * float(done) / float(total), 48, _accent, 12.0, true)
	var font := get_theme_default_font()
	var text := str(index + 1)
	var fs := 76
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	if not _unlocked:
		# Candado dibujado: cuerpo + arco.
		draw_rect(Rect2(c.x - 24, c.y - 6, 48, 38), VI.INK_DIM)
		draw_arc(c + Vector2(0, -8), 16.0, PI, TAU, 16, VI.INK_DIM, 7.0, true)
	elif _complete:
		draw_line(c + Vector2(-27, 3), c + Vector2(-8, 24), VI.GREEN, 12.0, true)
		draw_line(c + Vector2(-8, 24), c + Vector2(30, -21), VI.GREEN, 12.0, true)
	else:
		draw_string(font, Vector2(c.x - ts.x / 2.0, c.y + ts.y / 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, VI.INK)


func _gui_input(event: InputEvent) -> void:
	if not _unlocked:
		return
	var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if not tapped:
		return
	var pos: Vector2 = event.position
	var plaque := get_node_or_null("Plaque") as Control
	var on_plaque := plaque != null and Rect2(plaque.position, plaque.size).has_point(pos)
	if pos.distance_to(_node_center()) <= NODE_R + 10.0 or on_plaque:
		pressed.emit(String(status.get("id", "")))
