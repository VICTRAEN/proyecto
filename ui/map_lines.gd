extends Control

const VI := preload("res://ui/visual_identity.gd")

## MAPA DE MUNDO: colocacion de las fichas de nivel y lineas de conexion.
##
## Es el UNICO sitio que convierte las posiciones {x,y} relativas (0..1) de los
## datos en pixeles y el unico que dibuja las conexiones. La pantalla del mapa le
## pasa las fichas ya creadas con su posicion, su destino y su color, y este
## control las coloca y pinta las lineas entre ellas.
##
## Aqui no se lee ningun archivo ni se decide ninguna regla de desbloqueo: los
## colores llegan ya resueltos desde res://ui/visual_identity.gd.
##
## Todo se dibuja por CODIGO (draw_line / draw_circle), sin texturas ni recursos
## externos.

## Fichas a colocar: [{ id, position, next, color, button }]. El centro calculado
## se guarda en cada entrada, en la clave "center".
var _entries: Array = []
var _node_px := 100.0
var _line_width := 6.0
var _dot_radius := 7.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_relayout)


## Fichas del mapa. Se vuelve a colocar todo cada vez que cambia el tamano.
func set_entries(entries: Array) -> void:
	_entries = entries
	_relayout()


## Coloca las fichas y recalcula sus centros. Devuelve el tamano de ficha usado,
## que la pantalla necesita para los estilos de las tarjetas.
func layout_nodes() -> float:
	var area := size
	if area.x <= 2.0 or area.y <= 2.0:
		return _node_px
	# El tamano de ficha sale de la pantalla y nunca baja de lo que se puede
	# tocar con el dedo.
	_node_px = clampf(minf(area.x, area.y) * 0.17, VI.TOUCH, 150.0)
	var half := _node_px * 0.5
	for entry in _entries:
		if not (entry is Dictionary):
			continue
		var button: Button = (entry as Dictionary).get("button")
		if button == null or not is_instance_valid(button):
			continue
		var center := _clamped_point((entry as Dictionary).get("position"), half)
		(entry as Dictionary)["center"] = center
		button.size = Vector2(_node_px, _node_px)
		button.custom_minimum_size = Vector2(_node_px, _node_px)
		button.position = center - Vector2(half, half)
		button.add_theme_font_size_override(
			"font_size", int(clampf(_node_px * 0.42, float(VI.FONT_SMALL), float(VI.FONT_BIG)))
		)
	queue_redraw()
	return _node_px


func _relayout() -> void:
	if _entries.is_empty():
		queue_redraw()
		return
	layout_nodes()


## Centro de una ficha en pixeles, a partir de su posicion relativa {x,y}, sin
## dejar que la ficha se salga de la pantalla.
func _clamped_point(position_value, half: float) -> Vector2:
	var ratio := Vector2(0.5, 0.5)
	if position_value is Dictionary:
		ratio = Vector2(
			float((position_value as Dictionary).get("x", 0.5)),
			float((position_value as Dictionary).get("y", 0.5))
		)
	var area := size
	return Vector2(
		clampf(ratio.x * area.x, half, maxf(half, area.x - half)),
		clampf(ratio.y * area.y, half, maxf(half, area.y - half))
	)


func _draw() -> void:
	if _entries.is_empty():
		return
	_node_px = clampf(minf(size.x, size.y) * 0.17, VI.TOUCH, 150.0)
	_line_width = maxf(1.0, _node_px * 0.05)
	_dot_radius = maxf(2.0, _node_px * 0.06)
	var centers: Dictionary = {}
	for entry in _entries:
		if entry is Dictionary and (entry as Dictionary).has("center"):
			centers[String((entry as Dictionary).get("id", ""))] = (entry as Dictionary)["center"]
	for entry in _entries:
		if not (entry is Dictionary):
			continue
		var next_id := String((entry as Dictionary).get("next", ""))
		if next_id.is_empty() or not centers.has(next_id):
			continue
		var from_point: Vector2 = (entry as Dictionary).get("center", Vector2.ZERO)
		var to_point: Vector2 = centers[next_id]
		var color: Color = (entry as Dictionary).get("color", VI.INK_DIM)
		_draw_link(from_point, to_point, color)


## Un tramo. Se recorta para que la linea no se meta debajo de las fichas: nace y
## muere en su borde. Primero un trazo ancho y translucido y encima el fino, asi
## la linea se lee sobre cualquier fondo sin usar texturas.
func _draw_link(from_point: Vector2, to_point: Vector2, color: Color) -> void:
	var distance := from_point.distance_to(to_point)
	if distance <= _node_px:
		# Niveles pegados: una linea corta solo ensuciaria el mapa, asi que la
		# union se marca con un punto en el centro.
		draw_circle((from_point + to_point) * 0.5, _dot_radius, Color(color.r, color.g, color.b, 0.75))
		return
	var direction := (to_point - from_point) / distance
	var start_point := from_point + direction * (_node_px * 0.5)
	var end_point := to_point - direction * (_node_px * 0.5)
	draw_line(start_point, end_point, Color(color.r, color.g, color.b, 0.30), _line_width + 7.0, true)
	draw_line(start_point, end_point, color, _line_width, true)
