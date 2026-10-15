extends Control

const VI := preload("res://ui/visual_identity.gd")

## ANIMACION DE INVOCACION (gacha). Se dibuja por codigo, sin assets:
##   1) la pantalla se oscurece  2) un portal de luz crece y gira con el color de la
##   MEJOR rareza que ha salido (SR azul, SSR dorado, UR rosa, LR cian)  3) el portal
##   tiembla  4) FLASH blanco: en ese instante se llama a `reveal` y salen las cartas
##   5) el velo se retira. Tocar la pantalla salta la secuencia.
## El resultado YA esta decidido por GameState.summon: esto solo lo escenifica.
## Con "animaciones reducidas" se queda en un flash corto.

var _tint := Color.WHITE
var _progress := 0.0
var _reveal: Callable = Callable()
var _revealed := false
var _flash: ColorRect = null
var _label: Label = null
var _tween: Tween = null
var best_rarity := ""


static func play(host: Control, best: String, reveal: Callable) -> Control:
	var fx: Control = (load("res://ui/summon_fx.gd") as GDScript).new()
	fx.name = "SummonFx"
	host.add_child(fx)
	fx.call("_start", best, reveal)
	GameAudio.play("summon")
	return fx


func _start(best: String, reveal: Callable) -> void:
	best_rarity = best
	_tint = VI.rarity_color(best if not best.is_empty() else "SR")
	_reveal = reveal
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 40
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.04, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label = Label.new()
	_label.text = "INVOCANDO..."
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", VI.FONT_BIG)
	_label.add_theme_color_override("font_color", _tint)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 10)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.size = Vector2(700, 80)
	_label.position = Vector2((1080 - 700) * 0.5, 1500)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var speed := maxf(0.1, GameSettings.anim_speed_scale())
	_tween = create_tween()
	if GameSettings.reduce_motion():
		_tween.tween_property(_flash, "color:a", 0.8, 0.08)
		_tween.tween_callback(_do_reveal)
		_tween.tween_property(_flash, "color:a", 0.0, 0.25)
		_tween.tween_callback(queue_free)
		return
	_tween.tween_property(dim, "color:a", 0.82, 0.25 / speed)
	_tween.parallel().tween_property(self, "_progress", 1.0, 1.1 / speed)
	# El portal tiembla justo antes del destello.
	for i in 6:
		_tween.tween_property(_label, "position:x", (1080 - 700) * 0.5 + (10.0 if i % 2 == 0 else -10.0), 0.04 / speed)
	_tween.tween_property(_flash, "color:a", 1.0, 0.1 / speed)
	_tween.tween_callback(_do_reveal)
	_tween.tween_property(_flash, "color:a", 0.0, 0.4 / speed)
	_tween.parallel().tween_property(dim, "color:a", 0.0, 0.4 / speed)
	_tween.tween_callback(queue_free)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5 + Vector2(0, -80)
	var t := Time.get_ticks_msec() / 1000.0
	var radius := 40.0 + 260.0 * _progress
	for i in 6:
		var k := float(i) / 6.0
		var c := Color(_tint.r, _tint.g, _tint.b, (0.5 - k * 0.07) * _progress)
		draw_arc(center, radius * (1.0 - k * 0.12), t * (1.0 + k), t * (1.0 + k) + TAU * 0.7, 48, c, 6.0 - k * 4.0)
	draw_circle(center, radius * 0.22, Color(1, 1, 1, 0.25 + 0.6 * _progress))
	# destellos que salen del centro
	for i in 10:
		var ang := TAU * float(i) / 10.0 + t * 0.6
		var from := center + Vector2(cos(ang), sin(ang)) * radius * 0.3
		var to := center + Vector2(cos(ang), sin(ang)) * radius * (0.55 + 0.45 * _progress)
		draw_line(from, to, Color(_tint.r, _tint.g, _tint.b, 0.7 * _progress), 4.0)


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if pressed:
		_skip()


## Saltar: el reveal ocurre ya y la capa se va.
func _skip() -> void:
	if _tween != null:
		_tween.kill()
	_do_reveal()
	queue_free()


func _do_reveal() -> void:
	if _revealed:
		return
	_revealed = true
	revealed_at = Time.get_ticks_msec()
	if _reveal.is_valid():
		_reveal.call()


var revealed_at := 0
