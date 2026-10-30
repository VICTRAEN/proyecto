extends RefCounted

const VI := preload("res://ui/visual_identity.gd")

## PRESENTACION DE JEFES E IMPACTOS (v14). Todo se dibuja por codigo, sin assets
## nuevos, y respeta AJUSTES igual que ui/combat_fx.gd: con "animaciones reducidas"
## no hay temblor ni particulas (solo texto y flash), y la velocidad acorta los
## tiempos. Cada capa se libera sola y NINGUNA bloquea el toque salvo la intro, que
## se salta tocando en cualquier sitio.

static func _speed() -> float:
	return maxf(0.1, GameSettings.anim_speed_scale()) if GameSettings != null else 1.0


static func _calm() -> bool:
	return GameSettings != null and GameSettings.reduce_motion()


static func color_of(data: Dictionary, fallback: Color) -> Color:
	var raw := String(data.get("color", ""))
	return Color.html(raw) if not raw.is_empty() and Color.html_is_valid(raw) else fallback


## INTRO DE JEFE: banda oscura, retrato del jefe que entra desde un lado, titulo,
## subtitulo y frase. Se cierra sola (≈2.6 s) o al tocar. on_done se llama UNA vez.
## Devuelve la capa (nombre "BossIntroLayer") o null si no hay donde pintarla.
static func intro(host: Control, boss_id: String, boss_art: String, info: Dictionary, on_done: Callable) -> Control:
	var finished := [false]
	var finish := func():
		if finished[0]:
			return
		finished[0] = true
		if on_done.is_valid():
			on_done.call()
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		finish.call()
		return null
	var speed := _speed()
	var accent := color_of(info, VI.GOLD)
	var W := host.size.x
	var H := host.size.y
	var layer := Control.new()
	layer.name = "BossIntroLayer"
	layer.z_index = 60
	layer.size = Vector2(W, H)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	# Franjas de cine arriba y abajo.
	var bars: Array = []
	for i in 2:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.95)
		bar.size = Vector2(W, H * 0.12)
		bar.position = Vector2(0, -H * 0.12 if i == 0 else H)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(bar)
		bars.append(bar)
	var art_w := W * 0.58
	var art_h := H * 0.46
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", VI.special_card(accent, accent))
	panel.size = Vector2(art_w, art_h)
	var portrait: Control = (load("res://ui/portrait.gd") as GDScript).new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(portrait)
	portrait.call("setup", boss_id, accent, "short", boss_art, "front", "")
	var home_x := (W - art_w) * 0.5
	panel.position = Vector2(W + 40.0, H * 0.2)
	layer.add_child(panel)
	var title := _label(String(info.get("title", "")).to_upper(), 64, Color(1, 0.97, 0.85, 1), accent, W, H * 0.69)
	var sub := _label(String(info.get("subtitle", "")), 34, accent, Color(0, 0, 0, 0.9), W, H * 0.77)
	var tag := _label(String(info.get("tagline", "")), 26, Color(0.9, 0.92, 1.0, 0.9), Color(0, 0, 0, 0.9), W, H * 0.83)
	var hint := _label("TOCA PARA SALTAR", 20, Color(1, 1, 1, 0.55), Color(0, 0, 0, 0.8), W, H * 0.91)
	for node in [title, sub, tag, hint]:
		node.modulate.a = 0.0
		layer.add_child(node)
	title.pivot_offset = Vector2(W * 0.5, 40)
	title.scale = Vector2(1.5, 1.5)
	var tween := layer.create_tween().set_parallel(true)
	tween.tween_property(dim, "color:a", 0.72, 0.25 / speed)
	tween.tween_property(bars[0], "position:y", 0.0, 0.25 / speed)
	tween.tween_property(bars[1], "position:y", H * 0.88, 0.25 / speed)
	tween.tween_property(panel, "position:x", home_x, 0.4 / speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(title, "modulate:a", 1.0, 0.2 / speed).set_delay(0.35 / speed)
	tween.tween_property(title, "scale", Vector2.ONE, 0.3 / speed).set_delay(0.35 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sub, "modulate:a", 1.0, 0.25 / speed).set_delay(0.6 / speed)
	tween.tween_property(tag, "modulate:a", 1.0, 0.3 / speed).set_delay(0.85 / speed)
	tween.tween_property(hint, "modulate:a", 1.0, 0.3 / speed).set_delay(1.0 / speed)
	var close := func():
		if not is_instance_valid(layer) or layer.has_meta("closing"):
			return
		layer.set_meta("closing", true)
		var out := layer.create_tween()
		out.tween_property(layer, "modulate:a", 0.0, 0.2 / speed)
		out.tween_callback(func():
			if is_instance_valid(layer):
				layer.queue_free()
			finish.call())
	layer.gui_input.connect(func(event: InputEvent):
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed):
			close.call())
	var timer := layer.create_tween()
	timer.tween_interval(2.6 / speed)
	timer.tween_callback(close)
	return layer


## Salta/cierra la intro desde fuera (boton ATRAS, fin del combate, pruebas).
static func skip_intro(host: Control) -> bool:
	if host == null or not is_instance_valid(host):
		return false
	var layer := host.get_node_or_null("BossIntroLayer")
	if layer == null or layer.has_meta("closing"):
		return false
	layer.gui_input.emit(_press())
	return true


static func _press() -> InputEvent:
	var e := InputEventMouseButton.new()
	e.pressed = true
	e.button_index = MOUSE_BUTTON_LEFT
	return e


## TRANSICION DE FASE: destello del color del jefe, onda desde su tarjeta, temblor
## y el nombre de la fase en grande. No tapa los botones (banda central, sin toque).
static func phase(host: Control, target: Control, banner: String, accent: Color) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	var speed := _speed()
	var calm := _calm()
	var layer := Control.new()
	layer.name = "PhaseLayer"
	layer.z_index = 40
	layer.size = host.size
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(layer)
	var flash := ColorRect.new()
	flash.color = Color(accent.r, accent.g, accent.b, 0.0)
	flash.size = host.size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	var text := _label(banner.to_upper(), 56, Color(1, 0.97, 0.88, 1), accent, host.size.x, host.size.y * 0.28)
	text.modulate.a = 0.0
	text.pivot_offset = Vector2(host.size.x * 0.5, 40)
	text.scale = Vector2(1.6, 1.6)
	layer.add_child(text)
	var tween := layer.create_tween().set_parallel(true)
	tween.tween_property(flash, "color:a", 0.45, 0.08 / speed)
	tween.tween_property(flash, "color:a", 0.0, 0.4 / speed).set_delay(0.1 / speed)
	tween.tween_property(text, "modulate:a", 1.0, 0.12 / speed)
	tween.tween_property(text, "scale", Vector2.ONE, 0.25 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(text, "modulate:a", 0.0, 0.35 / speed).set_delay(0.85 / speed)
	tween.finished.connect(layer.queue_free)
	if target != null and is_instance_valid(target):
		if not calm:
			ring(host, target.global_position + target.size * 0.5, accent, 260.0)
			var shake := preload("res://ui/combat_fx.gd")
			shake.screen_shake(host, 16.0)
		if target.has_method("flash"):
			target.call("flash", accent, 0.9)


## IMPACTO: destello + chispas que salen disparadas del punto golpeado. strong=true
## (critico / especial) lleva mas chispas y un anillo. En modo calmado: solo un
## destello corto sin particulas.
static func impact(host: Control, global_pos: Vector2, accent: Color, strong: bool = false) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	var speed := _speed()
	var origin := global_pos - host.global_position
	var glow := ColorRect.new()
	glow.color = Color(accent.r, accent.g, accent.b, 0.55)
	glow.size = Vector2(90, 90) if not strong else Vector2(150, 150)
	glow.pivot_offset = glow.size * 0.5
	glow.position = origin - glow.size * 0.5
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.z_index = 25
	host.add_child(glow)
	var gt := glow.create_tween().set_parallel(true)
	gt.tween_property(glow, "modulate:a", 0.0, 0.22 / speed)
	gt.tween_property(glow, "scale", Vector2(1.6, 1.6), 0.22 / speed)
	gt.finished.connect(glow.queue_free)
	if _calm():
		return
	var count := 14 if strong else 7
	for i in count:
		var spark := ColorRect.new()
		spark.color = Color(accent.r, accent.g, accent.b, 1.0).lightened(0.3)
		spark.size = Vector2(randf_range(4, 9), randf_range(10, 22) if strong else randf_range(6, 13))
		spark.pivot_offset = spark.size * 0.5
		spark.position = origin - spark.size * 0.5
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spark.z_index = 26
		var angle := randf() * TAU
		spark.rotation = angle + PI * 0.5
		host.add_child(spark)
		var dist := randf_range(60.0, 150.0 if strong else 100.0)
		var st := spark.create_tween().set_parallel(true)
		st.tween_property(spark, "position", spark.position + Vector2(cos(angle), sin(angle)) * dist, 0.32 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		st.tween_property(spark, "modulate:a", 0.0, 0.32 / speed)
		st.finished.connect(spark.queue_free)
	if strong:
		ring(host, global_pos, accent, 190.0)


## Anillo que se expande y se apaga (onda de impacto).
static func ring(host: Control, global_pos: Vector2, accent: Color, radius: float) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree() or _calm():
		return
	var speed := _speed()
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_border_width_all(6)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.9)
	style.set_corner_radius_all(int(radius))
	panel.add_theme_stylebox_override("panel", style)
	var start := 40.0
	panel.size = Vector2(start, start)
	panel.pivot_offset = panel.size * 0.5
	panel.position = global_pos - host.global_position - panel.size * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 24
	host.add_child(panel)
	var t := panel.create_tween().set_parallel(true)
	t.tween_property(panel, "scale", Vector2.ONE * (radius * 2.0 / start), 0.45 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "modulate:a", 0.0, 0.45 / speed)
	t.finished.connect(panel.queue_free)


## AMBIENTE de jefe: unas pocas brasas que suben despacio por detras del escenario.
## Se omite con animaciones reducidas. Devuelve la capa o null.
static func ambient(host: Control, accent: Color) -> Control:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree() or _calm():
		return null
	var layer := Control.new()
	layer.name = "BossAmbient"
	layer.size = host.size
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = -1
	host.add_child(layer)
	for i in 14:
		var ember := ColorRect.new()
		ember.color = Color(accent.r, accent.g, accent.b, 0.0)
		ember.size = Vector2(5, 5)
		ember.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(ember)
		var delay := randf() * 3.0
		var x := randf() * host.size.x
		ember.position = Vector2(x, host.size.y * randf_range(0.7, 1.0))
		var t := ember.create_tween().set_loops()
		t.tween_interval(delay)
		t.tween_callback(func(): ember.position = Vector2(x, host.size.y * randf_range(0.7, 1.0)))
		t.tween_property(ember, "color:a", 0.5, 0.6)
		t.parallel().tween_property(ember, "position:y", ember.position.y - 260.0, 3.2)
		t.tween_property(ember, "color:a", 0.0, 0.8)
	return layer


static func _label(text: String, font_size: int, color: Color, outline: Color, width: float, y: float) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", outline)
	label.add_theme_constant_override("outline_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(width, 80)
	label.position = Vector2(0, y)
	return label
