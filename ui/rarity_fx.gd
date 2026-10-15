extends Control
## Capa de EFECTOS de rareza que va encima de una carta o un retrato (solo UR y LR).
##   UR: destello rosa que barre la carta de vez en cuando y 3 chispas.
##   LR: doble marco dorado interior, barrido de luz cian/dorado mas frecuente,
##       esquinas con rombos y 7 estrellas que titilan. Es lo que la separa de un
##       vistazo del resto. Todo se dibuja por codigo (sin PNG nuevos).
## Respeta "animaciones reducidas": en ese caso dibuja el estado fijo, sin movimiento.

const VI := preload("res://ui/visual_identity.gd")

var rarity := "UR"
var _t := 0.0
var _seeds: Array = []


func setup(new_rarity: String) -> void:
	rarity = new_rarity
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	var n := 7 if rarity == "LR" else 3
	for i in n:
		_seeds.append(Vector3(randf(), randf(), randf() * 6.28))
	_t = randf() * 3.0
	set_process(not (GameSettings != null and GameSettings.reduce_motion()))
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var col: Color = VI.rarity_color(rarity)
	var sec: Color = VI.rarity_secondary(rarity)
	var r := Rect2(Vector2.ZERO, size)
	if rarity == "LR":
		# Doble marco: el exterior lo pone la carta; este es el interior dorado.
		draw_rect(r.grow(-7.0), Color(sec.r, sec.g, sec.b, 0.9), false, 3.0)
		draw_rect(r.grow(-12.0), Color(col.r, col.g, col.b, 0.45), false, 2.0)
		# Rombos en las cuatro esquinas.
		for c in [Vector2(10, 10), Vector2(size.x - 10, 10), Vector2(10, size.y - 10), Vector2(size.x - 10, size.y - 10)]:
			var d := 9.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), sec)
	_sweep(col if rarity == "UR" else sec, 4.0 if rarity == "LR" else 6.0)
	for s in _seeds:
		var tw := 0.5 + 0.5 * sin(_t * (2.4 if rarity == "LR" else 1.6) + s.z)
		var p := Vector2(s.x * size.x, s.y * size.y)
		var rad := (5.0 + 9.0 * tw) * (1.3 if rarity == "LR" else 1.0)
		var sc := Color(1, 1, 1, 0.25 + 0.7 * tw) if rarity == "LR" else Color(col.r, col.g, col.b, 0.2 + 0.6 * tw)
		draw_line(p - Vector2(rad, 0), p + Vector2(rad, 0), sc, 2.0)
		draw_line(p - Vector2(0, rad), p + Vector2(0, rad), sc, 2.0)
		draw_circle(p, 2.0, sc)


## Barrido diagonal de luz: cruza la carta cada `period` segundos.
func _sweep(col: Color, period: float) -> void:
	var phase := fmod(_t, period) / period
	if phase > 0.45:
		return
	var k := phase / 0.45
	var x := lerpf(-size.y * 0.3, size.x + size.y * 0.3, k)
	var w := size.x * 0.16
	var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w - size.y * 0.3, size.y), Vector2(x - size.y * 0.3, size.y)])
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.22))
