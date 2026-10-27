extends StyleBox

## MARCO PREMIUM de la interfaz (esquinas anguladas + biselado metalico).
##
## Es el UNICO estilo de caja del juego: paneles, tarjetas, botones, chips y
## ventanas lo usan a traves de ui/visual_identity.gd (VI.panel, VI.card,
## VI.rarity_card, VI.tint_button...). Ninguna pantalla lo dibuja por su cuenta.
##
## Que dibuja, de abajo arriba:
##   1. sombra suave debajo
##   2. resplandor exterior (glow) del color del marco
##   3. relleno con degradado vertical (cuerpo oscuro, mas claro arriba)
##   4. brillo "glossy" en la mitad superior (botones)
##   5. luz interior que baja desde el borde
##   6. marco metalico BISELADO: cada lado se pinta mas claro o mas oscuro segun
##      mire a la luz (arriba-izquierda), con un degradado a lo ancho del marco
##   7. linea de luz del bisel interior y contorno oscuro exterior
##   8. gemas (cristales) en las esquinas cortadas
##
## Todo son poligonos de unos pocos vertices: no usa texturas ni shaders, escala
## a cualquier resolucion y cuesta una decena de comandos de dibujo por caja.
##
## Compatibilidad: expone la misma superficie que StyleBoxFlat para lo que las
## pantallas ya tocaban (border_color, bg_color, shadow_color, shadow_size,
## set_border_width_all, set_corner_radius_all). Asi las pantallas pueden seguir
## "teniendo" el borde de su acento sin conocer el bisel: border_color pinta TODO
## el metal del color del acento.

const LIGHT_DIR := Vector2(-0.7071, -0.7071)
## Cuanto se acorta el chaflan al meter el marco hacia dentro 1 px (2 - sqrt 2).
const CHAMFER_INSET := 0.5858

## Esquinas cortadas (bits): 1 arriba-izq, 2 arriba-der, 4 abajo-der, 8 abajo-izq.
const CORNERS_ALL := 15
const CORNERS_DIAGONAL := 5

@export var fill_top := Color(0.11, 0.075, 0.24, 0.92)
@export var fill_bottom := Color(0.05, 0.04, 0.13, 0.94)
@export var metal_light := Color(0.80, 0.74, 0.98, 1.0)
@export var metal_dark := Color(0.30, 0.24, 0.55, 1.0)
@export var edge_width := 3.0
@export var cut := 12.0
@export_flags("TL", "TR", "BR", "BL") var cut_corners := 15
@export var outline := Color(0.0, 0.0, 0.0, 0.60)
@export var inner_light := Color(1.0, 1.0, 1.0, 0.22)
@export var inner_glow := Color(0.0, 0.0, 0.0, 0.0)
@export var glow := Color(0.0, 0.0, 0.0, 0.0)
@export var glow_size := 0.0
@export var shadow := 0.45
@export var shadow_extent := 8.0
@export var shadow_dy := 4.0
@export var gloss := 0.0
@export var studs := false
@export var stud_color := Color(1.0, 0.86, 0.42, 1.0)

## --- Superficie compatible con StyleBoxFlat ---------------------------------

var border_color: Color:
	get:
		return metal_light
	set(value):
		tint_metal(value)

var bg_color: Color:
	get:
		return fill_top
	set(value):
		fill_top = value.lightened(0.06)
		fill_bottom = value.darkened(0.22)
		emit_changed()

var shadow_color: Color:
	get:
		return glow
	set(value):
		glow = value
		emit_changed()

var shadow_size: int:
	get:
		return int(glow_size)
	set(value):
		glow_size = float(value)
		emit_changed()


var shadow_offset: Vector2:
	get:
		return Vector2(0.0, shadow_dy)
	set(value):
		shadow_dy = value.y
		emit_changed()


func set_border_width_all(width: int) -> void:
	edge_width = float(width)
	emit_changed()


func set_corner_radius_all(radius: int) -> void:
	cut = float(radius) * 0.62
	emit_changed()


## Pinta todo el metal del marco con un acento: los lados que miran a la luz se
## aclaran y los que no, se oscurecen. Conserva el alfa del color recibido.
func tint_metal(accent: Color) -> void:
	metal_light = Color(accent.r, accent.g, accent.b, 1.0).lerp(Color.WHITE, 0.42)
	metal_dark = Color(accent.r, accent.g, accent.b, 1.0).darkened(0.58)
	metal_light.a = accent.a
	metal_dark.a = accent.a
	emit_changed()


## Crea un marco a partir de un diccionario {propiedad: valor}. Las propiedades
## desconocidas se ignoran, asi que VI puede ampliarse sin romper nada.
static func build(props: Dictionary) -> StyleBox:
	var frame = load("res://ui/vi_frame.gd").new()
	for key in props.keys():
		var prop := String(key)
		if prop in frame:
			frame.set(prop, props[key])
	var margin_x: float = float(props.get("margin_x", 16.0))
	var margin_y: float = float(props.get("margin_y", 12.0))
	frame.content_margin_left = margin_x
	frame.content_margin_right = margin_x
	frame.content_margin_top = margin_y
	frame.content_margin_bottom = margin_y
	return frame


func _get_draw_rect(rect: Rect2) -> Rect2:
	var extra := maxf(glow_size, shadow_extent + shadow_dy)
	return rect.grow(extra)


## --- Dibujo -----------------------------------------------------------------

func _draw(ci: RID, rect: Rect2) -> void:
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var w := minf(edge_width, minf(rect.size.x, rect.size.y) * 0.25)
	var c := minf(cut, minf(rect.size.x, rect.size.y) * 0.45)
	var outer := _ring(rect, c)

	_draw_shadow(ci, rect, c)
	_draw_glow(ci, outer)

	# Cuerpo: degradado vertical sobre el poligono exterior (el marco lo tapa).
	var body_colors := PackedColorArray()
	for p in outer:
		var t := clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)
		body_colors.append(fill_top.lerp(fill_bottom, t))
	RenderingServer.canvas_item_add_polygon(ci, outer, body_colors)

	var inner_rect := rect.grow(-w)
	var inner_cut := maxf(c - CHAMFER_INSET * w, 0.01) if c > 0.5 else 0.0
	var inner := _ring(inner_rect, inner_cut)

	if gloss > 0.0:
		_draw_gloss(ci, inner, inner_rect)
	if inner_glow.a > 0.0:
		var closed := _closed(inner)
		for k in 3:
			var width := 12.0 - 4.5 * float(k)
			var col := Color(inner_glow.r, inner_glow.g, inner_glow.b, inner_glow.a * (0.18 + 0.12 * float(k)))
			RenderingServer.canvas_item_add_polyline(ci, closed, PackedColorArray([col]), width, true)

	if w > 0.05:
		_draw_metal(ci, outer, inner)
		if outline.a > 0.0:
			RenderingServer.canvas_item_add_polyline(ci, _closed(outer), PackedColorArray([outline]), 1.6, true)
		_draw_bevel_light(ci, inner)
		if studs:
			_draw_studs(ci, outer, w)


## Poligono del rectangulo con las esquinas cortadas segun cut_corners.
func _ring(r: Rect2, c: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	var cutting := c > 0.0
	if cutting and (cut_corners & 1) != 0:
		pts.append(Vector2(x0, y0 + c))
		pts.append(Vector2(x0 + c, y0))
	else:
		pts.append(Vector2(x0, y0))
	if cutting and (cut_corners & 2) != 0:
		pts.append(Vector2(x1 - c, y0))
		pts.append(Vector2(x1, y0 + c))
	else:
		pts.append(Vector2(x1, y0))
	if cutting and (cut_corners & 4) != 0:
		pts.append(Vector2(x1, y1 - c))
		pts.append(Vector2(x1 - c, y1))
	else:
		pts.append(Vector2(x1, y1))
	if cutting and (cut_corners & 8) != 0:
		pts.append(Vector2(x0 + c, y1))
		pts.append(Vector2(x0, y1 - c))
	else:
		pts.append(Vector2(x0, y1))
	return pts


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


func _draw_shadow(ci: RID, rect: Rect2, c: float) -> void:
	if shadow <= 0.0 or shadow_extent <= 0.0:
		return
	for i in 3:
		var grow := shadow_extent * float(i + 1) / 3.0
		var r := Rect2(rect.position + Vector2(0.0, shadow_dy), rect.size).grow(grow * 0.55)
		var pts := _ring(r, c + grow * 0.25)
		RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([Color(0.0, 0.0, 0.02, shadow * 0.17)]))


func _draw_glow(ci: RID, outer: PackedVector2Array) -> void:
	if glow.a <= 0.0 or glow_size <= 0.5:
		return
	var closed := _closed(outer)
	var steps := 5
	for k in steps:
		var width := glow_size * 2.0 * float(k + 1) / float(steps)
		RenderingServer.canvas_item_add_polyline(ci, closed, PackedColorArray([Color(glow.r, glow.g, glow.b, glow.a * 0.20)]), width, true)


func _draw_gloss(ci: RID, inner: PackedVector2Array, inner_rect: Rect2) -> void:
	var mid_y := inner_rect.position.y + inner_rect.size.y * 0.5
	var top_y := inner_rect.position.y
	var pts := PackedVector2Array()
	for p in inner:
		if p.y <= mid_y:
			pts.append(p)
	pts.append(Vector2(inner_rect.end.x, mid_y))
	pts.append(Vector2(inner_rect.position.x, mid_y))
	if pts.size() < 3:
		return
	var cols := PackedColorArray()
	for p in pts:
		var t := clampf((p.y - top_y) / maxf(mid_y - top_y, 1.0), 0.0, 1.0)
		cols.append(Color(1.0, 1.0, 1.0, gloss * 0.30 * (1.0 - t)))
	if _area(pts) < 0.5 or Geometry2D.triangulate_polygon(pts).is_empty():
		return
	RenderingServer.canvas_item_add_polygon(ci, pts, cols)


## Area de un poligono (formula del cordon). Se usa para no mandar al renderizador
## poligonos degenerados (rectangulos casi vacios, puntos alineados), que dan
## "triangulation failed".
static func _area(pts: PackedVector2Array) -> float:
	var total := 0.0
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		total += a.x * b.y - b.x * a.y
	return absf(total) * 0.5


## Marco metalico: un trapecio por lado, mas claro o mas oscuro segun mire a la
## luz, con el borde exterior un poco mas oscuro que el interior (da volumen).
func _draw_metal(ci: RID, outer: PackedVector2Array, inner: PackedVector2Array) -> void:
	var n := outer.size()
	for i in n:
		var j := (i + 1) % n
		var d := outer[j] - outer[i]
		if d.length() < 0.01:
			continue
		var normal := Vector2(d.y, -d.x).normalized()
		var lit := clampf(normal.dot(LIGHT_DIR) * 0.5 + 0.5, 0.0, 1.0)
		lit = lit * lit * (3.0 - 2.0 * lit)
		var base := metal_dark.lerp(metal_light, lit)
		var edge_col := base.darkened(0.16)
		var inner_col := base.lightened(0.10)
		var quad := PackedVector2Array([outer[i], outer[j], inner[j], inner[i]])
		if _area(quad) < 0.25 or Geometry2D.triangulate_polygon(quad).is_empty():
			continue
		RenderingServer.canvas_item_add_polygon(ci, quad, PackedColorArray([edge_col, edge_col, inner_col, inner_col]))


## Linea fina de luz en el borde interior de los lados que miran a la luz.
func _draw_bevel_light(ci: RID, inner: PackedVector2Array) -> void:
	if inner_light.a <= 0.0:
		return
	var n := inner.size()
	for i in n:
		var j := (i + 1) % n
		var d := inner[j] - inner[i]
		if d.length() < 0.5:
			continue
		var normal := Vector2(d.y, -d.x).normalized()
		var lit := normal.dot(LIGHT_DIR)
		# Los lados "interiores" miran al reves: la luz toca los que estan
		# opuestos a la luz exterior, asi el bisel parece hundido.
		if lit < -0.2:
			RenderingServer.canvas_item_add_line(ci, inner[i], inner[j], inner_light, 1.4, true)


func _draw_studs(ci: RID, outer: PackedVector2Array, w: float) -> void:
	var n := outer.size()
	var size := maxf(w * 1.5 + 2.0, 6.0)
	for i in n:
		var j := (i + 1) % n
		var d := outer[j] - outer[i]
		# Solo los chaflanes (segmentos diagonales).
		if absf(d.x) < 0.5 or absf(d.y) < 0.5:
			continue
		var center := (outer[i] + outer[j]) * 0.5
		var top := stud_color.lightened(0.35)
		var low := stud_color.darkened(0.45)
		RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([
			center + Vector2(0.0, -size), center + Vector2(size * 0.7, 0.0), center + Vector2(-size * 0.7, 0.0)
		]), PackedColorArray([top]))
		RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([
			center + Vector2(size * 0.7, 0.0), center + Vector2(0.0, size), center + Vector2(-size * 0.7, 0.0)
		]), PackedColorArray([low]))
		RenderingServer.canvas_item_add_polyline(ci, PackedVector2Array([
			center + Vector2(0.0, -size), center + Vector2(size * 0.7, 0.0), center + Vector2(0.0, size),
			center + Vector2(-size * 0.7, 0.0), center + Vector2(0.0, -size)
		]), PackedColorArray([Color(0.0, 0.0, 0.0, 0.7)]), 1.0, true)
