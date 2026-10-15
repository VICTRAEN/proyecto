extends Control

## FONDO del revelado individual. Se dibuja por codigo y cambia con la rareza:
##   SR   -> halo azul sobrio, sin rayos
##   SSR  -> rayos dorados que giran despacio
##   UR   -> rayos rosas mas densos, chispas y un anillo
##   LR   -> rayos cian/dorados, doble anillo y estrellas
##   duo  -> modo "neon": rejilla cyberpunk, barras amarillas y cian y glitch
## No tiene logica: solo pinta lo que `configure` le dice.

var tint := Color(0.4, 0.5, 0.9)
var tint2 := Color(1, 1, 1)
var rays := 0
var rings := 0
var neon := false
var _t := 0.0
var _seeds: Array = []


func configure(rarity: String, color: Color, color2: Color, neon_mode: bool = false) -> void:
	tint = color
	tint2 = color2
	neon = neon_mode
	match rarity:
		"SSR":
			rays = 10
			rings = 1
		"UR":
			rays = 16
			rings = 2
		"LR":
			rays = 22
			rings = 3
		_:
			rays = 0
			rings = 0
	if neon:
		rays = maxi(rays, 14)
		rings = maxi(rings, 2)
	_seeds.clear()
	for i in (28 if rarity == "LR" or neon else 12 if rarity == "UR" else 0):
		_seeds.append(Vector3(randf(), randf(), randf() * TAU))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(not (GameSettings != null and GameSettings.reduce_motion()))
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 2.0 or h < 2.0:
		return
	# Fondo: degradado vertical oscuro teñido de la rareza.
	var top := Color(0.02, 0.02, 0.05)
	var bottom := Color(tint.r * 0.22, tint.g * 0.22, tint.b * 0.22)
	var bands := 24
	for i in bands:
		var k := float(i) / float(bands - 1)
		draw_rect(Rect2(0, h * float(i) / float(bands), w, h / float(bands) + 1.0), top.lerp(bottom, k))
	var center := Vector2(w * 0.5, h * 0.42)
	# Halo central.
	for i in range(6, 0, -1):
		draw_circle(center, minf(w, h) * (0.12 + 0.07 * float(i)), Color(tint.r, tint.g, tint.b, 0.05 + 0.02 * float(7 - i)))
	if neon:
		_draw_grid(w, h)
	# Rayos giratorios.
	var calm := GameSettings != null and GameSettings.reduce_motion()
	var spin := 0.0 if calm else _t * (0.35 if not neon else 0.5)
	for i in rays:
		var a0 := spin + TAU * float(i) / float(rays)
		var a1 := a0 + TAU / float(rays) * 0.42
		var length := maxf(w, h) * 1.1
		var col := tint if i % 2 == 0 else tint2
		draw_colored_polygon(PackedVector2Array([
			center,
			center + Vector2(cos(a0), sin(a0)) * length,
			center + Vector2(cos(a1), sin(a1)) * length,
		]), Color(col.r, col.g, col.b, 0.10 if not neon else 0.13))
	# Anillos que laten.
	for r in rings:
		var pulse := 0.5 + 0.5 * sin(_t * 1.8 + float(r))
		draw_arc(center, minf(w, h) * (0.30 + 0.09 * float(r)) * (1.0 + 0.03 * pulse), 0.0, TAU, 96, Color(tint2.r, tint2.g, tint2.b, 0.25 + 0.2 * pulse), 3.0)
	# Chispas.
	for s in _seeds:
		var tw := 0.5 + 0.5 * sin(_t * 2.2 + s.z)
		var p := Vector2(s.x * w, fposmod(s.y * h - _t * 22.0 * (0.5 + s.x), h))
		draw_circle(p, 2.0 + 3.0 * tw, Color(1, 1, 1, 0.2 + 0.6 * tw))


func _draw_grid(w: float, h: float) -> void:
	var c := Color(tint2.r, tint2.g, tint2.b, 0.10)
	var step := 90.0
	var x := fposmod(_t * 14.0, step)
	while x < w:
		draw_line(Vector2(x, 0), Vector2(x, h), c, 1.5)
		x += step
	var y := fposmod(_t * 20.0, step)
	while y < h:
		draw_line(Vector2(0, y), Vector2(w, y), c, 1.5)
		y += step
	# Dos barras diagonales de neon que cruzan despacio.
	for k in 2:
		var off := fposmod(_t * 160.0 + float(k) * w * 0.7, w * 1.8) - w * 0.4
		var col := tint if k == 0 else tint2
		draw_line(Vector2(off, 0), Vector2(off - h * 0.35, h), Color(col.r, col.g, col.b, 0.22), 10.0)
