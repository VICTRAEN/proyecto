extends Control
## Ilustracion de un articulo de tienda dibujada por codigo (no hay arte de
## objetos todavia). Tipos: coins, gems, materials, item. El personaje usa su
## Portrait, no esto. Cantidad de piezas segun "amount" para que 5000 monedas se
## vean como un monton mayor que 1000.

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
	draw_circle(c, minf(size.x, size.y) * 0.46, Color(tint.r, tint.g, tint.b, 0.13))
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
