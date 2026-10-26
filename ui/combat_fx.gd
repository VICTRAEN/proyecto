extends RefCounted

const VI := preload("res://ui/visual_identity.gd")

## EFECTOS DE COMBATE 2D, sin assets: movimiento, flash, temblor, lineas de velocidad
## y texto. Todo se dibuja por codigo, asi que sustituirlo por arte real es cambiar
## SOLO este archivo. Respeta AJUSTES: con "animaciones reducidas" se omiten el
## temblor y el zoom (queda el flash y el texto), y la velocidad de animacion los
## acorta. Cada efecto se libera solo; ninguno bloquea el toque.

static func _speed() -> float:
	return maxf(0.1, GameSettings.anim_speed_scale()) if GameSettings != null else 1.0


static func _calm() -> bool:
	return GameSettings != null and GameSettings.reduce_motion()


## ATAQUE NORMAL: el atacante da un paso hacia delante y vuelve; cada objetivo
## recibe un golpe corto (empujon + destello). Un critico golpea mas fuerte.
static func attack(actor: Control, targets: Array, critical: bool = false) -> void:
	var speed := _speed()
	if actor != null and is_instance_valid(actor) and not _calm():
		var home := actor.position
		var tween := actor.create_tween()
		tween.tween_property(actor, "position", home + Vector2(0, -26), 0.08 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(actor, "position", home, 0.14 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for raw in targets:
		var target: Control = raw
		if target == null or not is_instance_valid(target):
			continue
		hit_shake(target, 22.0 if critical else 12.0)


## Empujon horizontal rapido de un control (tarjeta golpeada).
static func hit_shake(node: Control, amount: float = 12.0) -> void:
	if _calm() or node == null or not is_instance_valid(node):
		return
	var speed := _speed()
	var home := node.position
	var tween := node.create_tween()
	for i in 4:
		var dir := -1.0 if i % 2 == 0 else 1.0
		tween.tween_property(node, "position", home + Vector2(dir * amount * (1.0 - float(i) * 0.2), 0), 0.04 / speed)
	tween.tween_property(node, "position", home, 0.04 / speed)


## ULTI / ATAQUE ESPECIAL: mucho mas grande que el normal. Secuencia:
##   1) la pantalla se OSCURECE   2) lineas de VELOCIDAD cruzan la pantalla
##   3) el retrato del atacante hace ZOOM   4) FLASH blanco   5) TEMBLOR de la
##   escena y banda con el NOMBRE de la habilidad.
## `host` es la pantalla de combate; `portrait` el retrato activo (puede ser null).
static func ultimate(host: Control, portrait: Control, skill_name: String, tint: Color, targets: Array) -> void:
	if host == null or not is_instance_valid(host):
		return
	var speed := _speed()
	var calm := _calm()
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 30
	host.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var band := ColorRect.new()
	band.color = Color(tint.r * 0.35, tint.g * 0.35, tint.b * 0.35, 0.0)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size = Vector2(host.size.x, 150)
	band.position = Vector2(0, host.size.y * 0.36)
	layer.add_child(band)

	var lines: Array = []
	if not calm:
		for i in 14:
			var line := ColorRect.new()
			line.color = Color(1, 1, 1, 0.0)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.size = Vector2(host.size.x * 1.4, randf_range(3.0, 9.0))
			line.rotation = deg_to_rad(-12.0)
			line.position = Vector2(-host.size.x * 0.2, randf() * host.size.y)
			layer.add_child(line)
			lines.append(line)

	var title := Label.new()
	title.text = skill_name.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 78)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.75, 1))
	title.add_theme_color_override("font_outline_color", tint)
	title.add_theme_constant_override("outline_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size = band.size
	title.position = band.position
	title.pivot_offset = band.size * 0.5
	title.modulate = Color(1, 1, 1, 0)
	title.scale = Vector2(1.8, 1.8)
	layer.add_child(title)

	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var tween := layer.create_tween()
	# 1) oscurecer
	tween.tween_property(dim, "color:a", 0.62, 0.18 / speed)
	tween.parallel().tween_property(band, "color:a", 0.85, 0.18 / speed)
	# 2) lineas de velocidad
	for raw in lines:
		var line: ColorRect = raw
		tween.parallel().tween_property(line, "color:a", 0.5, 0.12 / speed)
		tween.parallel().tween_property(line, "position:x", line.position.x + host.size.x * 0.35, 0.5 / speed)
	# texto de la habilidad con golpe de escala
	tween.parallel().tween_property(title, "modulate:a", 1.0, 0.12 / speed)
	tween.parallel().tween_property(title, "scale", Vector2.ONE, 0.26 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 3) zoom del atacante
	if portrait != null and is_instance_valid(portrait) and not calm:
		portrait.pivot_offset = portrait.size * 0.5
		var zoom := portrait.create_tween()
		zoom.tween_property(portrait, "scale", Vector2(1.22, 1.22), 0.2 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		zoom.tween_interval(0.35 / speed)
		zoom.tween_property(portrait, "scale", Vector2.ONE, 0.2 / speed)
	tween.tween_interval(0.3 / speed)
	# 4) flash blanco en el impacto + 5) temblor de la escena y golpe a los objetivos
	tween.tween_property(flash, "color:a", 0.9, 0.07 / speed)
	tween.tween_callback(func():
		if not calm and is_instance_valid(host):
			screen_shake(host, 26.0)
		for raw_target in targets:
			if raw_target != null and is_instance_valid(raw_target):
				hit_shake(raw_target, 30.0))
	tween.tween_property(flash, "color:a", 0.0, 0.3 / speed)
	tween.parallel().tween_property(dim, "color:a", 0.0, 0.4 / speed)
	tween.parallel().tween_property(layer, "modulate:a", 0.0, 0.35 / speed)
	tween.tween_callback(layer.queue_free)


## Temblor de toda la escena: se mueve el host y vuelve a su sitio.
static func screen_shake(host: Control, amount: float = 20.0) -> void:
	if _calm() or host == null or not is_instance_valid(host):
		return
	var speed := _speed()
	var home := host.position
	var tween := host.create_tween()
	for i in 7:
		var k := 1.0 - float(i) / 7.0
		tween.tween_property(host, "position", home + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * k, 0.035 / speed)
	tween.tween_property(host, "position", home, 0.035 / speed)


## ULTIMATE DE FORMA (EDGERUNNERS: ULTIMATE del duo LR). Mucho mas larga y vistosa que
## la ulti normal: letterbox cinematografico, oscurecimiento, los DOS protagonistas
## entran a pantalla desde los lados, nombre de la habilidad con glitch, carga con
## parpadeo, IMPACTO (flash + temblor + golpe en cada rival), y al final las lineas de
## potenciacion/debilitacion aplicadas. Todo por codigo, sin assets nuevos.
##   notes: [ { "text": "...", "color": Color } ]  (buffs/debuffs que se anuncian)
##   on_done se llama UNA vez al terminar o al saltarla tocando la pantalla; nunca
##   queda la capa bloqueando el combate.
static func edgerunners(host: Control, skill_name: String, accent: Color, accent2: Color, hero_ids: Array, targets: Array, notes: Array, on_done: Callable) -> Control:
	var finished := [false]
	if host == null or not is_instance_valid(host):
		if on_done.is_valid():
			on_done.call()
		return null
	var speed := _speed()
	var calm := _calm()
	var layer := Control.new()
	layer.name = "UltimateLayer"
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.z_index = 40
	host.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var W := host.size.x
	var H := host.size.y
	var finish := func():
		if finished[0]:
			return
		finished[0] = true
		if on_done.is_valid():
			on_done.call()
		if is_instance_valid(layer):
			layer.queue_free()
	layer.tree_exited.connect(finish)
	layer.gui_input.connect(func(event: InputEvent):
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			finish.call())

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Letterbox: dos bandas negras que entran desde arriba y abajo.
	var top_bar := ColorRect.new()
	top_bar.color = Color(0, 0, 0, 1)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.size = Vector2(W, H * 0.12)
	top_bar.position = Vector2(0, -H * 0.12)
	layer.add_child(top_bar)
	var bottom_bar := ColorRect.new()
	bottom_bar.color = Color(0, 0, 0, 1)
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.size = Vector2(W, H * 0.12)
	bottom_bar.position = Vector2(0, H)
	layer.add_child(bottom_bar)
	# Lineas de velocidad de neon.
	var lines: Array = []
	if not calm:
		for i in 16:
			var line := ColorRect.new()
			var col := accent if i % 2 == 0 else accent2
			line.color = Color(col.r, col.g, col.b, 0.0)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.size = Vector2(W * 1.4, randf_range(3.0, 10.0))
			line.rotation = deg_to_rad(-14.0)
			line.position = Vector2(-W * 0.2, randf() * H)
			layer.add_child(line)
			lines.append(line)
	# Los dos protagonistas.
	var heroes: Array = []
	var hero_w := W * 0.44
	var hero_h := H * 0.40
	for i in hero_ids.size():
		var hero := PanelContainer.new()
		hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero.add_theme_stylebox_override("panel", VI.special_card(accent if i == 0 else accent2, accent if i == 0 else accent2))
		hero.size = Vector2(hero_w, hero_h)
		var art: Control = (load("res://ui/portrait.gd") as GDScript).new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero.add_child(art)
		art.call("setup", String(hero_ids[i]), accent if i == 0 else accent2, "short", "", "front", "")
		var home_x := W * 0.04 if i == 0 else W * 0.52
		hero.position = Vector2(-hero_w - 40.0 if i == 0 else W + 40.0, H * 0.27)
		hero.set_meta("home_x", home_x)
		layer.add_child(hero)
		heroes.append(hero)
	var title := Label.new()
	title.text = skill_name.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 74)
	title.add_theme_color_override("font_color", Color(1, 0.97, 0.78, 1))
	title.add_theme_color_override("font_outline_color", accent2)
	title.add_theme_constant_override("outline_size", 18)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size = Vector2(W, 190)
	title.position = Vector2(0, H * 0.70)
	title.pivot_offset = Vector2(W * 0.5, 95)
	title.modulate = Color(1, 1, 1, 0)
	title.scale = Vector2(2.0, 2.0)
	layer.add_child(title)
	# Tajos del impacto.
	var slashes: Array = []
	for i in 3:
		var slash := ColorRect.new()
		slash.color = Color(1, 1, 1, 0)
		slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slash.size = Vector2(W * 1.5, 12.0 - float(i) * 3.0)
		slash.pivot_offset = slash.size * 0.5
		slash.position = Vector2(-W * 0.25, H * 0.45 + float(i - 1) * 46.0)
		slash.rotation = deg_to_rad(-26.0 + float(i) * 22.0)
		slash.scale = Vector2(0.0, 1.0)
		layer.add_child(slash)
		slashes.append(slash)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Avisos de buffs/debuffs: salen DESPUES del impacto, uno bajo otro.
	var note_labels: Array = []
	for i in notes.size():
		var note: Dictionary = notes[i]
		var label := Label.new()
		label.text = String(note.get("text", ""))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 44)
		label.add_theme_color_override("font_color", note.get("color", Color.WHITE))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		label.add_theme_constant_override("outline_size", 10)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size = Vector2(W, 60)
		label.position = Vector2(0, H * 0.20 + float(i) * 62.0)
		label.modulate = Color(1, 1, 1, 0)
		layer.add_child(label)
		note_labels.append(label)

	var spd := speed * (1.8 if calm else 1.0)
	var tw := layer.create_tween()
	# 1) preparacion: oscurece y entran las bandas
	tw.tween_property(dim, "color:a", 0.80, 0.25 / spd)
	tw.parallel().tween_property(top_bar, "position:y", 0.0, 0.25 / spd)
	tw.parallel().tween_property(bottom_bar, "position:y", H * 0.88, 0.25 / spd)
	# 2) los dos protagonistas entran desde los lados
	for raw in heroes:
		var hero: Control = raw
		tw.parallel().tween_property(hero, "position:x", float(hero.get_meta("home_x")), 0.45 / spd).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12 / spd)
	for raw in lines:
		var line: ColorRect = raw
		tw.parallel().tween_property(line, "color:a", 0.45, 0.2 / spd)
		tw.parallel().tween_property(line, "position:x", line.position.x + W * 0.3, 0.9 / spd)
	# 3) nombre de la habilidad
	tw.tween_property(title, "modulate:a", 1.0, 0.12 / spd)
	tw.parallel().tween_property(title, "scale", Vector2.ONE, 0.28 / spd).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 4) carga: parpadeo de la pantalla antes del golpe
	for i in 3:
		tw.tween_property(flash, "color", Color(accent.r, accent.g, accent.b, 0.35), 0.05 / spd)
		tw.tween_property(flash, "color", Color(accent.r, accent.g, accent.b, 0.0), 0.07 / spd)
	tw.tween_interval(0.12 / spd)
	# 5) IMPACTO
	tw.tween_property(flash, "color", Color(1, 1, 1, 0.95), 0.06 / spd)
	for raw in slashes:
		var slash: ColorRect = raw
		tw.parallel().tween_property(slash, "color:a", 0.95, 0.04 / spd)
		tw.parallel().tween_property(slash, "scale:x", 1.0, 0.1 / spd)
	tw.tween_callback(func():
		if not calm and is_instance_valid(host):
			screen_shake(host, 34.0)
		for raw_target in targets:
			if raw_target != null and is_instance_valid(raw_target):
				hit_shake(raw_target, 34.0))
	tw.tween_property(flash, "color:a", 0.0, 0.35 / spd)
	for raw in slashes:
		var slash: ColorRect = raw
		tw.parallel().tween_property(slash, "color:a", 0.0, 0.3 / spd)
	# 6) las potenciaciones/debilitaciones quedan a la vista
	for raw in note_labels:
		var label: Label = raw
		tw.parallel().tween_property(label, "modulate:a", 1.0, 0.18 / spd).set_delay(0.1 / spd)
	tw.tween_interval(0.55 / spd)
	# 7) la interfaz vuelve
	tw.tween_property(layer, "modulate:a", 0.0, 0.3 / spd)
	tw.tween_callback(finish)
	return layer
