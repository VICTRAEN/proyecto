extends Control
## Ilustracion de un articulo de tienda. Usa los iconos semi-3D de
## res://art/ui/icons/ (provisionales, reemplazables por arte final) y, si falta
## alguno, el dibujo por codigo de siempre. Tipos: coins, gems, materials, item. El personaje usa su
## Portrait, no esto. Cantidad de piezas segun "amount" para que 5000 monedas se
## vean como un monton mayor que 1000.

const VI := preload("res://ui/visual_identity.gd")

var kind := "coins"
var amount := 1
var tint := Color(1.0, 0.784, 0.337)


func setup(new_kind: String, new_amount: int, new_tint: Color) -> void:
	kind = new_kind
	amount = new_amount
	tint = new_tint
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	# Halo: luz suave del color del articulo detras del icono (no un disco plano).
	var radius := minf(size.x, size.y) * 0.52
	for i in 6:
		var k := float(i) / 6.0
		draw_circle(c, radius * (1.0 - k * 0.8), Color(tint.r, tint.g, tint.b, 0.045 + 0.025 * k))
	var icon_name := _icon_for(kind)
	var tex := VI.icon(icon_name)
	if tex == null:
		_draw_fallback(c)
		return
	var base := minf(size.y * 0.92, 104.0)
	match kind:
		"coins":
			var piles := 1 if amount < 1500 else (3 if amount < 10000 else 5)
			_fan(tex, c, piles, base)
		"gems":
			_fan(tex, c, 1 if amount < 300 else 3, base)
		_:
			_put(tex, c, base)


## Icono segun el tipo de articulo.
func _icon_for(item_kind: String) -> String:
	match item_kind:
		"coins":
			return "coin"
		"gems":
			return "gem"
		"materials":
			return "inventory"
	return "crystal"


## n iconos en abanico: el del centro delante y mas grande.
func _fan(tex: Texture2D, c: Vector2, n: int, base: float) -> void:
	var mid := (n - 1) / 2.0
	var order := range(n)
	order.sort_custom(func(a, b): return absf(a - mid) > absf(b - mid))
	for i in order:
		var d := float(i) - mid
		var scale := 1.0 - absf(d) * 0.13
		var p := c + Vector2(d * base * 0.46, absf(d) * base * 0.08)
		_put(tex, p, base * scale)


func _put(tex: Texture2D, center: Vector2, px: float) -> void:
	# Sombra de contacto bajo el icono para que no flote sobre el halo.
	draw_circle(center + Vector2(0, px * 0.40), px * 0.30, Color(0, 0, 0, 0.18))
	draw_texture_rect(tex, Rect2(center - Vector2(px, px) * 0.5, Vector2(px, px)), false)


func _draw_fallback(c: Vector2) -> void:
	match kind:
		"coins":
			var piles := 1 if amount < 1500 else (3 if amount < 10000 else 5)
			for i in piles:
				var off := Vector2((i - (piles - 1) / 2.0) * 34.0, (i % 2) * -10.0 + 10.0)
				for h in 3:
					var p := c + off + Vector2(0, -h * 9.0)
					draw_circle(p, 24.0, Color(0.55, 0.38, 0.08))
					draw_circle(p + Vector2(0, -2), 22.0, tint)
					draw_arc(p + Vector2(0, -2), 14.0, 0, TAU, 20, Color(0.7, 0.5, 0.1), 2.0)
		"gems":
			var n := 1 if amount < 300 else 3
			for i in n:
				var o := c + Vector2((i - (n - 1) / 2.0) * 44.0, (i % 2) * 14.0 - 4.0)
				var pts := PackedVector2Array([o + Vector2(0, -34), o + Vector2(26, -8), o + Vector2(0, 30), o + Vector2(-26, -8)])
				draw_colored_polygon(pts, Color(0.35, 0.8, 1.0))
				draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.85, 0.97, 1.0), 3.0)
				draw_line(o + Vector2(-26, -8), o + Vector2(26, -8), Color(0.85, 0.97, 1.0, 0.7), 2.0)
		"materials":
			for i in 3:
				var o := c + Vector2((i - 1) * 40.0, (i % 2) * -14.0 + 8.0)
				draw_rect(Rect2(o - Vector2(22, 20), Vector2(44, 40)), Color(0.55, 0.4, 0.25))
				draw_rect(Rect2(o - Vector2(22, 20), Vector2(44, 40)), Color(0.85, 0.7, 0.45), false, 3.0)
				draw_line(o - Vector2(22, 0), o + Vector2(22, 0), Color(0.85, 0.7, 0.45), 2.0)
		_:
			var o := c
			draw_rect(Rect2(o - Vector2(28, 22), Vector2(56, 44)), Color(tint.r * 0.5, tint.g * 0.5, tint.b * 0.5))
			draw_rect(Rect2(o - Vector2(28, 22), Vector2(56, 44)), tint, false, 3.0)
			draw_line(o + Vector2(0, -22), o + Vector2(0, 22), tint, 3.0)
