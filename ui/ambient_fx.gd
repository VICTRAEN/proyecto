extends Control

## AMBIENTE: unas pocas particulas de luz que flotan sobre el fondo (polvo de luz,
## brasas, destellos). Es un adorno barato: entre 14 y 28 puntos, se redibuja a
## 30 fps solo mientras la pantalla es visible, y con "animaciones reducidas"
## se pinta una vez y se queda quieto.
##
## Presets (los elige ScreenBackground segun el fondo):
##   motes  -> motas de luz que suben despacio (calido o frio segun `tint`)
##   embers -> brasas que suben mas rapido y parpadean
##   stars  -> destellos de 4 puntas que solo parpadean (no se mueven)

var mode := "motes"
var count := 20
var tint := Color(1.0, 0.88, 0.70, 1.0)
var tint2 := Color(1.0, 0.55, 0.85, 1.0)

var _parts: Array = []
var _t := 0.0
var _accum := 0.0


func setup(new_mode: String, new_count: int, color: Color, color2: Color) -> void:
	mode = new_mode
	count = clampi(new_count, 4, 40)
	tint = color
	tint2 = color2
	_seed()
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _parts.is_empty():
		_seed()


func _seed() -> void:
	_parts.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 + count * 31 + mode.length()
	for i in count:
		_parts.append({
			"x": rng.randf(),
			"y": rng.randf(),
			"speed": rng.randf_range(0.012, 0.035) * (2.2 if mode == "embers" else 1.0),
			"size": rng.randf_range(2.0, 6.5),
			"phase": rng.randf() * TAU,
			"sway": rng.randf_range(0.008, 0.03),
			"second": rng.randf() < 0.35,
		})


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if GameSettings != null and GameSettings.reduce_motion():
		return
	_accum += delta
	if _accum < 1.0 / 30.0:
		return
	_t += _accum
	_accum = 0.0
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0:
		return
	for p in _parts:
		var c: Color = tint2 if bool(p["second"]) else tint
		var tw := 0.5 + 0.5 * sin(_t * 1.6 + float(p["phase"]))
		var px := float(p["x"]) * w
		var py := float(p["y"]) * h
		if mode != "stars":
			var travel := fmod(float(p["y"]) - _t * float(p["speed"]) + 8.0, 1.0)
			py = travel * h
			px += sin(_t * 0.7 + float(p["phase"])) * float(p["sway"]) * w
		var s := float(p["size"]) * (0.7 + 0.6 * tw)
		var fade := 1.0
		if mode != "stars":
			fade = clampf(minf(py / (h * 0.15), (h - py) / (h * 0.15)), 0.0, 1.0)
		var a := (0.25 + 0.6 * tw) * fade
		if mode == "stars":
			var arm := s * 3.2
			draw_line(Vector2(px - arm, py), Vector2(px + arm, py), Color(c.r, c.g, c.b, a * 0.9), 1.6, true)
			draw_line(Vector2(px, py - arm), Vector2(px, py + arm), Color(c.r, c.g, c.b, a * 0.9), 1.6, true)
			draw_circle(Vector2(px, py), s * 0.7, Color(1, 1, 1, a))
		else:
			draw_circle(Vector2(px, py), s * 2.6, Color(c.r, c.g, c.b, a * 0.14))
			draw_circle(Vector2(px, py), s, Color(c.r, c.g, c.b, a))
