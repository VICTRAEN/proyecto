extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")
const CardTile := preload("res://ui/card_tile.gd")
const RarityFx := preload("res://ui/rarity_fx.gd")
const Backdrop := preload("res://ui/reveal_backdrop.gd")
const DuoFallback := preload("res://ui/duo_fallback_fx.gd")

## REVELADO INDIVIDUAL de una invocacion, a pantalla completa.
##
## Es SOLO presentacion. Los resultados ya estan sorteados, cobrados y entregados
## (GameState.summon con stage_reveal=true) y viven en GameState.pending_reveal; esta
## pantalla los ensena de uno en uno leyendo reveal_current() y avanzando con
## reveal_advance(). Nada de aqui sortea, cobra ni concede: avanzar, saltar el
## video o repetir el toque no puede cambiar el estado del juego mas alla del indice.
##
## Flujo: carta 1/N -> toque -> carta 2/N ... -> N/N -> (x10) pantalla final con
## el RESUMEN (se abre solo, con VOLVER AL BANNER); (x1) el toque en la carta cierra.
## Si el personaje tiene "summon_cinematic" en su JSON (el duo David & Lucy), antes de
## su carta se reproduce la cinematica (video opcional, con alternativa si falta).
## La primera copia de la secuencia hace la cinematica completa; las demas, un
## revelado especial corto.
##
## Seguridad contra toques repetidos: _busy se pone en el mismo instante en que se
## acepta un toque y no se suelta hasta que la carta nueva esta puesta.

signal finished(summary: Dictionary)

const FADE_OUT := 0.12
const FADE_IN := 0.28
const INPUT_DELAY_MS := 150
const FALLBACK_SECONDS := 2.6
const VIDEO_START_GRACE := 1.5
const DEFAULT_VIDEO := "res://art/cinematics/david_lucy_summon.ogv"

var _phase := "boot"
var _busy := true
var _closed := false
var _ready_at_ms := 0
var _entry: Dictionary = {}
var _results: Array = []
var _total := 0
var _short_special := false

var _backdrop: Control = null
var _content: Control = null
var _counter: Label = null
var _hint: Label = null
var _flash: ColorRect = null
var _cin_layer: Control = null
var _video: VideoStreamPlayer = null
var _skip_button: Button = null
var _cin_done := true
var _cin_token := 0
var _cin_cfg: Dictionary = {}
## Registro de lo que ha pasado, para las pruebas ("card:<id>", "cinematic_video"...).
var fx_log: Array = []


static func start(host: Control) -> Control:
	var node: Control = (load("res://ui/summon_reveal.gd") as GDScript).new()
	node.name = "SummonReveal"
	host.add_child(node)
	node.call("begin")
	return node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 60
	focus_mode = Control.FOCUS_ALL
	_backdrop = Backdrop.new()
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_counter = Label.new()
	_counter.name = "Counter"
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.add_theme_font_size_override("font_size", VI.FONT_BIG)
	_counter.add_theme_color_override("font_color", VI.INK)
	_counter.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_counter.add_theme_constant_override("outline_size", 8)
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_counter)
	_counter.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_counter.offset_top = 44.0
	_counter.offset_bottom = 110.0
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	_hint.add_theme_color_override("font_color", VI.INK_SOFT)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -92.0
	_hint.offset_bottom = -34.0
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.z_index = 5


func _exit_tree() -> void:
	# Si la capa desaparece por un cambio de pantalla, el tema especial no se queda.
	if GameAudio != null and GameAudio.override_owner() == "summon":
		GameAudio.override_clear("summon")


## --- Entrada y estado ---------------------------------------------------------------

func begin() -> void:
	var pending: Dictionary = GameState.pending_reveal
	_results = (pending.get("results", []) as Array).duplicate(true)
	_total = _results.size()
	if _total == 0:
		_close()
		return
	_show_current()


func phase() -> String:
	return _phase


func is_busy() -> bool:
	return _busy


func current_id() -> String:
	return String(_entry.get("id", ""))


func counter_text() -> String:
	return _counter.text if _counter != null else ""


func summary_visible() -> bool:
	return _phase == "summary"


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if pressed:
		accept_event()
		tap()


func _input(event: InputEvent) -> void:
	if _closed or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			get_viewport().set_input_as_handled()
			tap()


## Un toque / clic / Enter / Espacio. Solo hace algo si se esta mostrando una carta y
## no hay una transicion en marcha: el resto de toques se ignoran.
func tap() -> void:
	if _closed or _busy or _phase != "card":
		return
	if Time.get_ticks_msec() < _ready_at_ms:
		return
	_advance()


func _advance() -> void:
	_busy = true
	var tween := create_tween()
	tween.tween_property(_content, "modulate:a", 0.0, FADE_OUT / _speed())
	tween.tween_callback(func():
		if _closed:
			return
		var more: bool = GameState.reveal_advance()
		if more:
			_show_current()
		elif _total <= 1:
			_close()
		else:
			_show_end())


func _speed() -> float:
	return maxf(0.1, GameSettings.anim_speed_scale()) if GameSettings != null else 1.0


func _calm() -> bool:
	return GameSettings != null and GameSettings.reduce_motion()


func _show_current() -> void:
	_entry = GameState.reveal_current()
	if _entry.is_empty():
		_show_end() if _total > 1 else _close()
		return
	_busy = true
	var cin = DB.get_character(current_id()).get("summon_cinematic", {})
	_cin_cfg = cin if cin is Dictionary else {}
	_short_special = false
	if not _cin_cfg.is_empty():
		if bool(GameState.pending_reveal.get("cinematic_done", false)):
			_short_special = true
			fx_log.append("short_special")
			_present_card()
		else:
			_start_cinematic()
		return
	_present_card()


## --- Carta ----------------------------------------------------------------------------

func _present_card() -> void:
	_phase = "card"
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var id := current_id()
	var data := GameState.character_data(id)
	# Lo que se revela es la COPIA que acaba de salir: siempre en su calidad INICIAL
	# (rareza base), aunque ya tengas ese personaje evolucionado. La unidad existente
	# ni se toca ni se muestra aqui.
	var rarity := GameState.base_rarity_of(id) if not data.is_empty() else String(_entry.get("rarity", "SR"))
	var special := not _cin_cfg.is_empty()
	var tint: Color = VI.rarity_color(rarity)
	var tint2: Color = VI.rarity_secondary(rarity)
	var type_tint: Color = TypeColors.color_for(String(data.get("type", "STR")))
	if special:
		tint = Color.html(String(_cin_cfg.get("accent", "#f5e642")))
		tint2 = Color.html(String(_cin_cfg.get("accent2", "#27e6d6")))
	(_backdrop as Backdrop).configure(rarity, tint, tint2, special)
	fx_log.append("card:%s" % id)

	var index := int(GameState.pending_reveal.get("index", 0))
	_counter.text = "%d/%d" % [index + 1, _total] if _total > 1 else ""
	_counter.visible = _total > 1
	var last := index >= _total - 1
	_hint.text = ("TOCA PARA FINALIZAR" if _total <= 1 or not last else "TOCA PARA TERMINAR") if last else "TOCA PARA CONTINUAR"
	_hint.visible = true

	var box := MarginContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("margin_left", 54)
	box.add_theme_constant_override("margin_right", 54)
	box.add_theme_constant_override("margin_top", 128)
	box.add_theme_constant_override("margin_bottom", 120)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 12)
	box.add_child(col)

	if special:
		var ribbon := Label.new()
		ribbon.text = String(_cin_cfg.get("ribbon", "UNIDAD INSIGNIA"))
		ribbon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ribbon.add_theme_font_size_override("font_size", VI.FONT_SECTION)
		ribbon.add_theme_color_override("font_color", tint)
		ribbon.add_theme_color_override("font_outline_color", tint2.darkened(0.5))
		ribbon.add_theme_constant_override("outline_size", 8)
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ribbon)

	var frame := PanelContainer.new()
	frame.name = "CardFrame"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := VI.rarity_card(rarity, false, true)
	if special:
		style = VI.special_card(tint, tint2)
	frame.add_theme_stylebox_override("panel", style)
	col.add_child(frame)
	var art := Portrait.new()
	art.name = "CardArt"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(art)
	art.setup(id, type_tint, String(data.get("portrait_style", "short")), Portrait.art_path_from(data, "front"), "front", rarity.to_lower())
	if rarity == "UR" or rarity == "LR":
		var fx := RarityFx.new()
		frame.add_child(fx)
		fx.setup(rarity)
	if art.provisional:
		var note := Label.new()
		note.text = "ARTE PROVISIONAL"
		note.add_theme_font_size_override("font_size", VI.FONT_TINY)
		note.add_theme_color_override("font_color", VI.INK_DIM)
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		note.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		note.grow_vertical = Control.GROW_DIRECTION_BEGIN
		note.offset_right = -14.0
		note.offset_bottom = -10.0
		frame.add_child(note)

	var badge := VI.rarity_badge(rarity, VI.FONT_SECTION)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(badge)
	var name_label := Label.new()
	name_label.name = "CardName"
	name_label.text = String(data.get("name", _entry.get("name", id)))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", VI.FONT_BIG + (6 if special else 0))
	name_label.add_theme_color_override("font_color", tint if special else VI.INK)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_constant_override("outline_size", 8)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)
	var title := String(data.get("title", ""))
	if not title.is_empty():
		var title_label := Label.new()
		title_label.text = title
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		title_label.add_theme_color_override("font_color", VI.INK_SOFT)
		title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(title_label)
	var chip := Label.new()
	chip.name = "NewChip"
	var is_new := bool(_entry.get("new", false))
	chip.text = "NUEVO" if is_new else "REPETIDO  +%d" % int(_entry.get("duplicates", 1))
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_theme_font_size_override("font_size", VI.FONT_BODY)
	chip.add_theme_color_override("font_color", VI.GREEN if is_new else VI.INK_SOFT)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(chip)

	# Entrada: la carta crece con rebote y la rareza se anuncia con un destello.
	box.pivot_offset = size * 0.5
	_content.modulate.a = 0.0
	box.scale = Vector2(0.86, 0.86)
	var tween := create_tween().set_parallel(true)
	var spd := _speed()
	tween.tween_property(_content, "modulate:a", 1.0, FADE_IN / spd)
	if not _calm():
		tween.tween_property(box, "scale", Vector2.ONE, 0.32 / spd).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		box.scale = Vector2.ONE
	var flash_alpha := 0.0
	match rarity:
		"SSR": flash_alpha = 0.55
		"UR": flash_alpha = 0.75
		"LR": flash_alpha = 0.9
	if special:
		flash_alpha = 0.95
	if flash_alpha > 0.0:
		_flash.color = Color(tint.r, tint.g, tint.b, flash_alpha) if not special else Color(1, 1, 1, flash_alpha)
		tween.tween_property(_flash, "color:a", 0.0, 0.5 / spd)
	if special and not _calm():
		_shake(box, 12.0 if not _short_special else 7.0)
	if rarity == "SR":
		GameAudio.play("select")
	else:
		GameAudio.play("evolution" if (special or rarity != "SSR") else "summon")
	_ready_at_ms = Time.get_ticks_msec() + INPUT_DELAY_MS
	# Se puede avanzar en cuanto la carta esta puesta; no hay que esperar a que acabe
	# el destello.
	get_tree().create_timer(0.1).timeout.connect(func():
		if not _closed and _phase == "card":
			_busy = false)


func _shake(node: Control, amount: float) -> void:
	var home := node.position
	var tw := create_tween()
	for i in 6:
		var dir := -1.0 if i % 2 == 0 else 1.0
		tw.tween_property(node, "position", home + Vector2(dir * amount * (1.0 - float(i) * 0.15), 0), 0.04)
	tw.tween_property(node, "position", home, 0.04)


## --- Cinematica del duo -----------------------------------------------------------------

func _start_cinematic() -> void:
	_phase = "cinematic"
	_busy = true
	_cin_done = false
	_cin_token += 1
	var token := _cin_token
	_hint.visible = false
	_counter.visible = _total > 1
	# La presentacion normal queda detenida: la interfaz se oscurece y el tema especial
	# empieza ahora (si el archivo existe; si no, sigue la musica de la pantalla).
	var theme := String(_cin_cfg.get("theme", "david_lucy_theme"))
	GameAudio.override_start(theme, "summon")
	fx_log.append("cinematic_start")
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_cin_layer = Control.new()
	_cin_layer.name = "CinematicLayer"
	_cin_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cin_layer)
	_cin_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cin_layer.z_index = 3
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cin_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	create_tween().tween_property(dim, "color:a", 0.96, 0.3 / _speed())
	_skip_button = Button.new()
	_skip_button.name = "SkipCinematicButton"
	_skip_button.text = "SALTAR  >>"
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.custom_minimum_size = Vector2(300, 84)
	_skip_button.add_theme_font_size_override("font_size", VI.FONT_BODY)
	VI.tint_button(_skip_button, VI.BLUE)
	_cin_layer.add_child(_skip_button)
	_skip_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_skip_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skip_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skip_button.offset_top = -170.0
	_skip_button.offset_bottom = -86.0
	_skip_button.offset_left = -150.0
	_skip_button.offset_right = 150.0
	_skip_button.pressed.connect(skip_cinematic)

	var path := String(_cin_cfg.get("video", DEFAULT_VIDEO))
	var stream: Variant = null
	if ResourceLoader.exists(path):
		stream = load(path)
	if stream is VideoStream:
		_video = VideoStreamPlayer.new()
		_video.name = "CinematicVideo"
		_video.stream = stream
		_video.expand = true
		_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# El video es solo imagen: su pista de audio se silencia. La musica la
		# controla el sistema de audio del juego.
		_video.volume_db = -80.0
		_video.volume = 0.0
		_cin_layer.add_child(_video)
		_video.size = Vector2(size.x * 0.9, size.x * 0.9 * 9.0 / 16.0)
		_video.finished.connect(func(): if token == _cin_token: _end_cinematic())
		_video.play()
		fx_log.append("cinematic_video")
		# Si el video no arranca (formato roto, decodificador ausente) no se queda la
		# pantalla en negro: a los pocos instantes se pasa a la alternativa.
		get_tree().create_timer(VIDEO_START_GRACE).timeout.connect(func():
			if token != _cin_token or _cin_done:
				return
			# Un video sano ya esta en marcha y tiene su primer fotograma. Si no esta
			# reproduciendose o no ha producido imagen, se cambia a la alternativa.
			var tex: Texture2D = _video.get_video_texture() if _video != null and is_instance_valid(_video) else null
			if _video == null or not _video.is_playing() or tex == null or tex.get_size().x <= 1.0:
				_video_failed())
	else:
		_start_fallback()


func _process(_delta: float) -> void:
	# Encuadre del video: se ajusta a su proporcion real, centrado y grande.
	if _video != null and is_instance_valid(_video) and _video.is_playing():
		var tex := _video.get_video_texture()
		if tex != null and tex.get_size().x > 1.0:
			var vs := tex.get_size()
			var max_w := size.x * 0.94
			var max_h := size.y * 0.66
			var k := minf(max_w / vs.x, max_h / vs.y)
			_video.size = vs * k
			_video.position = Vector2((size.x - _video.size.x) * 0.5, (size.y - _video.size.y) * 0.46)


func _video_failed() -> void:
	if _cin_done:
		return
	if _video != null and is_instance_valid(_video):
		_video.stop()
		_video.queue_free()
		_video = null
	_start_fallback()


func _start_fallback() -> void:
	if _cin_done or _cin_layer == null:
		return
	fx_log.append("cinematic_fallback")
	var token := _cin_token
	var fx := DuoFallback.new()
	fx.name = "CinematicFallback"
	fx.accent = Color.html(String(_cin_cfg.get("accent", "#f5e642")))
	fx.accent2 = Color.html(String(_cin_cfg.get("accent2", "#27e6d6")))
	fx.title = String(_cin_cfg.get("title", "EDGERUNNERS"))
	fx.subtitle = String(_cin_cfg.get("subtitle", "DAVID MARTINEZ & LUCY"))
	_cin_layer.add_child(fx)
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var seconds := (FALLBACK_SECONDS if not _calm() else 0.9) / _speed()
	var tween := create_tween()
	tween.tween_property(fx, "progress", 1.0, seconds)
	tween.tween_callback(func(): if token == _cin_token: _end_cinematic())


## Saltar: pasa directo al revelado del duo. No toca el estado del juego salvo marcar
## que la cinematica ya se ha visto (para que las copias no la repitan).
func skip_cinematic() -> void:
	if _phase != "cinematic" or _cin_done:
		return
	fx_log.append("cinematic_skipped")
	_end_cinematic()


func _end_cinematic() -> void:
	if _cin_done or _closed:
		return
	_cin_done = true
	_cin_token += 1
	if _video != null and is_instance_valid(_video):
		_video.stop()
	_video = null
	if _cin_layer != null:
		_cin_layer.queue_free()
		_cin_layer = null
	_skip_button = null
	GameState.reveal_mark_cinematic()
	fx_log.append("cinematic_end")
	_present_card()


## --- Final y resumen ---------------------------------------------------------------------

func _show_end() -> void:
	# v11: ya no hay pantalla intermedia (VER RESUMEN / VOLVER AL BANNER). Al terminar
	# la secuencia se abre DIRECTAMENTE el resumen, y desde el el jugador decide.
	_phase = "end"
	_busy = true
	_content.modulate.a = 1.0
	(_backdrop as Backdrop).configure("SR", VI.BLUE, VI.GOLD, false)
	_hint.visible = false
	_show_summary()
	_busy = false


func _show_summary() -> void:
	if _phase != "end":
		return
	_phase = "summary"
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_counter.text = "RESUMEN"
	var box := MarginContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("margin_left", 30)
	box.add_theme_constant_override("margin_right", 30)
	box.add_theme_constant_override("margin_top", 128)
	box.add_theme_constant_override("margin_bottom", 40)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	box.add_child(col)
	# Los datos de la invocacion (antes estaban en la pantalla intermedia).
	var info := Label.new()
	info.name = "EndInfo"
	info.text = "%d tiradas  -  %d gemas  -  %d nuevos, %d repetidos" % [
		_total, int(GameState.pending_reveal.get("cost", 0)),
		int(GameState.pending_reveal.get("new_count", 0)), int(GameState.pending_reveal.get("duplicate_count", 0))]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", VI.FONT_BODY)
	info.add_theme_color_override("font_color", VI.INK_SOFT)
	col.add_child(info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "SummaryGrid"
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for entry in _results:
		var data := GameState.character_data(String((entry as Dictionary).get("id", "")))
		if data.is_empty():
			continue
		# La carta del resumen es la COPIA recibida: calidad inicial, no la de la unidad.
		var quality := GameState.base_rarity_of(String(data.get("id", "")))
		data["rarity"] = quality
		data["form_override"] = quality.to_lower()
		if not bool((entry as Dictionary).get("new", false)):
			data["is_copy"] = true
		var card: PanelContainer = CardTile.new()
		card.art_height = 250.0
		grid.add_child(card)
		card.bind(data, false, "NUEVO" if bool((entry as Dictionary).get("new", false)) else "REP.")
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := Button.new()
	back.name = "ReturnButton"
	back.text = "VOLVER AL BANNER"
	back.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(back, VI.BLUE)
	back.pressed.connect(_close)
	col.add_child(back)


## Cierra la secuencia: suelta el tema especial, deja que la pantalla recupere su
## musica y entrega el resumen. Es idempotente.
func _close() -> void:
	if _closed:
		return
	_closed = true
	_phase = "closed"
	_cin_token += 1
	if _video != null and is_instance_valid(_video):
		_video.stop()
	var summary: Dictionary = GameState.reveal_finish()
	if GameAudio.override_owner() == "summon":
		GameAudio.override_clear("summon")
	var app := NAV.app_of(self)
	if app != null and app.has_method("refresh_music"):
		app.call("refresh_music")
	finished.emit(summary)
	queue_free()
