extends Control
## Medallon circular de progreso (misiones, hitos). Dibuja un anillo que se llena
## y, dentro, el texto "x/y" o una marca de hecho. Sin texturas: todo es codigo.

var ratio := 0.0
var color := Color.WHITE
var label_text := ""
var done := false


func setup(new_ratio: float, new_color: Color, new_text: String, is_done: bool = false) -> void:
	ratio = clampf(new_ratio, 0.0, 1.0)
	color = new_color
	label_text = new_text
	done = is_done
	custom_minimum_size = Vector2(84, 84)
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 6.0
	draw_circle(c, r + 2.0, Color(0.05, 0.06, 0.12, 0.9))
	draw_arc(c, r, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.22), 8.0, true)
	if ratio > 0.0:
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * ratio, 48, color, 8.0, true)
	var font := get_theme_default_font()
	var text := "OK" if done else label_text
	var fs := 22 if text.length() <= 5 else 17
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2(c.x - ts.x / 2.0, c.y + ts.y / 4.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color if not done else VI_INK)

const VI_INK := Color(0.941, 0.957, 1.0, 1.0)
