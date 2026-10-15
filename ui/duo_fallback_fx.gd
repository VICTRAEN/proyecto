extends Control

## TRANSICION ALTERNATIVA de la cinematica del duo: se usa cuando falta el video o
## no se puede reproducir (y como animacion de la copia repetida). No es un video:
## es una secuencia corta dibujada por codigo (barras de neon, escaneo, glitch y el
## titulo). `progress` (0..1) la dirige; quien la crea la anima con un Tween.

var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()
var accent := Color(0.96, 0.9, 0.26)
var accent2 := Color(0.15, 0.9, 0.84)
var title := "EDGERUNNERS"
var subtitle := "DAVID MARTINEZ & LUCY"
var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 2.0:
		return
	var p := progress
	# Barras horizontales que entran desde los lados.
	var bars := 7
	for i in bars:
		var delay := float(i) / float(bars) * 0.35
		var k := clampf((p - delay) / 0.4, 0.0, 1.0)
		var y := h * (0.22 + 0.56 * float(i) / float(bars - 1))
		var col := accent if i % 2 == 0 else accent2
		var from_left := i % 2 == 0
		var length := w * k
		var x0 := 0.0 if from_left else w - length
		draw_rect(Rect2(x0, y - 5.0, length, 10.0), Color(col.r, col.g, col.b, 0.85 * (1.0 - clampf((p - 0.8) / 0.2, 0.0, 1.0))))
	# Linea de escaneo vertical.
	var sx := w * clampf(p * 1.25, 0.0, 1.0)
	draw_rect(Rect2(sx - 3.0, 0, 6.0, h), Color(1, 1, 1, 0.5))
	# Titulo con glitch: se desplaza en rojo/cian y se estabiliza.
	if _font != null and p > 0.25:
		var a := clampf((p - 0.25) / 0.2, 0.0, 1.0)
		var jitter := (1.0 - clampf((p - 0.45) / 0.3, 0.0, 1.0)) * 16.0 * sin(p * 90.0)
		var fs := int(w * 0.105)
		var pos := Vector2(0, h * 0.47)
		draw_string(_font, pos + Vector2(jitter - 4.0, 0), title, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(accent2.r, accent2.g, accent2.b, a * 0.8))
		draw_string(_font, pos + Vector2(-jitter + 4.0, 3), title, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(1.0, 0.2, 0.4, a * 0.6))
		draw_string(_font, pos, title, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(accent.r, accent.g, accent.b, a))
		var fs2 := int(w * 0.045)
		draw_string(_font, pos + Vector2(0, h * 0.07), subtitle, HORIZONTAL_ALIGNMENT_CENTER, w, fs2, Color(1, 1, 1, a))
