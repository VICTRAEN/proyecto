extends Control

## Retrato de una unidad. Es el UNICO sitio del juego que decide como se encuadra
## una imagen de personaje: lo usan la coleccion, el equipo, la barra de orden, el
## panel de informacion, las tarjetas de combate y el rival. Ninguna pantalla
## escala imagenes por su cuenta, asi que todas ensenan el mismo encuadre.
##
## Tres ranuras por personaje, porque no son la misma imagen:
##   front -> visto de frente. Se usa cuando la unidad es el rival.
##   back  -> visto de espaldas. Se usa para las unidades del jugador.
##   icon  -> retrato de cara. Se usa en barras, coleccion y menus.
##
## Convencion de archivos. Dejar el .png aqui es todo lo que hace falta; ningun
## script cambia para sustituir un placeholder por arte real:
##   res://art/characters/<id>/front.png
##   res://art/characters/<id>/back.png
##   res://art/characters/<id>/icon.png
##
## El bloque "art" del JSON puede sobreescribir cada ranura con una ruta
## explicita. Si la ruta esta vacia se usa la convencion, y si el archivo tampoco
## existe se dibuja una silueta placeholder.
##
## ENCUADRE AUTOMATICO. El PNG no necesita estar recortado, centrado ni tener una
## proporcion concreta: al cargarlo se busca su area VISIBLE (los pixeles que no
## son transparentes), se ignora el margen vacio y se dibuja solo esa parte,
## centrada y escalada proporcionalmente dentro del hueco disponible. Asi una
## imagen con mucho aire alrededor, o muy alta y estrecha, se ve igual de bien que
## una ya preparada, sin deformar nunca y sin cortar la cabeza.
##
## El archivo NO se modifica: el recorte es solo de dibujo.
##
## "portrait_style" en el JSON solo afecta a esa silueta (spiky, short, long,
## ponytail). Cuando hay arte real, se ignora.

const ART_ROOT := "res://art/characters/"
const LEGACY_ART_DIR := "res://art/portraits/"
const SLOTS := ["front", "back", "icon"]
const DEFAULT_SLOT := "icon"
## Extensiones que se prueban, en orden. El PNG es lo normal; el resto existe para
## que una imagen ya preparada en otro formato no obligue a reconvertirla.
const EXTS := [".png", ".webp", ".jpg", ".jpeg"]

## Un pixel cuenta como visible si su alfa supera esto. Filtra halos casi
## invisibles que descuadrarian el encuadre.
const ALPHA_THRESHOLD := 0.06
## El area visible se busca muestreando como mucho esta rejilla (128x128). Con
## pasos grandes basta para encuadrar y el coste no depende del tamano del PNG.
const SCAN_SAMPLES := 128

## Area visible de cada PNG, ya calculada: ruta -> Rect2. El escaneo se hace UNA
## vez por imagen, no cada vez que se pinta una tarjeta.
static var _visible_cache := {}

var accent := Color(0.64, 0.68, 0.80, 1.0)
var style := "short"
var slot := DEFAULT_SLOT
## Forma de la unidad ("ssr", "ur", "lr"...). El arte de una forma evolucionada vive
## en su propia subcarpeta (res://art/characters/<id>/<forma>/<ranura>.png) y este
## campo es lo que hace que el juego la busque antes que el arte base.
var form := ""
var art_path := ""
var texture: Texture2D = null
## Parte del PNG que se dibuja (su area visible), en pixeles de la imagen.
var source_rect := Rect2()

const VI := preload("res://ui/visual_identity.gd")
const Frame := preload("res://ui/vi_frame.gd")
const LIGHT_SHADER := preload("res://ui/shaders/character_light.gdshader")
const Layer := preload("res://ui/portrait_layer.gd")

## ILUMINACION: el arte original se dibuja con un shader suave (cel-shading ligero,
## gradacion de color y luz de contorno del color del tipo). `lit` lo desactiva.
var lit := true
## Resplandor de ESCENARIO detras del personaje (0 = ninguno). Lo activan las
## presentaciones grandes (menu, ficha, invocacion); las tarjetas pequenas no.
var aura := 0.0
## Grosor aproximado del filo de luz, en pixeles de pantalla.
var rim_screen_px := 3.0
## Sin marco ni relleno: el personaje flota sobre el fondo (escaparates).
var transparent_frame := false
## Colocacion de sprites SUELTOS (combate): con true los pies quedan en el borde
## inferior del hueco (todos en la misma linea de suelo) en vez de centrados, y
## `width_slack` deja que un sprite ancho se pase un poco del ancho antes de encogerlo,
## para que las alturas de los personajes sean mas parecidas. Nunca deforma ni recorta.
var feet_down := false
var width_slack := 0.0

var _frame: StyleBox = null
var _art_layer: Control = null
var _frame_layer: Control = null
var _material: ShaderMaterial = null


func _ready() -> void:
	resized.connect(_refresh)
	_ensure_layers()
	_refresh()


func _ensure_layers() -> void:
	if _art_layer != null:
		return
	_art_layer = Layer.new()
	_art_layer.name = "ArtLayer"
	_art_layer.portrait = self
	_art_layer.kind = "art"
	add_child(_art_layer)
	_frame_layer = Layer.new()
	_frame_layer.name = "FrameLayer"
	_frame_layer.portrait = self
	_frame_layer.kind = "frame"
	add_child(_frame_layer)


func setup(character_id: String, tint: Color, portrait_style: String = "short", explicit_path: String = "", portrait_slot: String = DEFAULT_SLOT, portrait_form: String = "") -> void:
	accent = tint
	style = portrait_style if not portrait_style.is_empty() else "short"
	slot = portrait_slot if SLOTS.has(portrait_slot) else DEFAULT_SLOT
	form = String(portrait_form).to_lower()
	# Sin forma explicita se pregunta al estado del jugador cual es la forma ACTUAL
	# del personaje (su rareza efectiva). Asi todas las pantallas ensenan el arte
	# de la forma correcta sin que ninguna tenga que pasar la forma a mano, y una
	# unidad de combate o un enemigo (que no son personajes del roster) no rompen.
	if form.is_empty() and not character_id.is_empty():
		form = GameState.form_of(character_id)
	texture = null
	art_path = ""
	source_rect = Rect2()
	for candidate in _candidates(character_id, explicit_path):
		var loaded := _try_load(candidate)
		if loaded != null:
			texture = loaded
			art_path = candidate
			source_rect = visible_rect_for(candidate, loaded)
			break
	provisional = false
	if texture == null and not character_id.is_empty():
		var composed := _fallback_composite(character_id, slot)
		if composed != null:
			texture = composed
			art_path = "composite:" + character_id + ":" + slot
			source_rect = Rect2(Vector2.ZERO, composed.get_size())
			provisional = true
	_refresh()


## Verdadero si la imagen es una COMPOSICION PROVISIONAL (arte de otros personajes
## unido por el juego), no un retrato propio de la unidad.
var provisional := false
static var _composite_cache := {}


## Si una unidad (el duo) declara "art_fallback_ids" y aun no tiene PNG propio, se
## compone una imagen provisional con el arte de esos personajes lado a lado. NO
## escribe nada en disco ni toca los PNG: es solo una textura en memoria. Los
## retratos definitivos van en res://art/characters/david_lucy_duo/<forma>/<ranura>.png.
static func _fallback_composite(character_id: String, slot_name: String) -> Texture2D:
	var key := "%s|%s" % [character_id, slot_name]
	if _composite_cache.has(key):
		return _composite_cache[key]
	var ids = (DB.characters.get(character_id, {}) as Dictionary).get("art_fallback_ids", [])
	if not (ids is Array) or (ids as Array).size() < 2:
		return null
	var images: Array = []
	for raw in ids:
		var path := "%s%s/%s.png" % [ART_ROOT, String(raw), slot_name]
		if not ResourceLoader.exists(path):
			return null
		var tex = load(path)
		if not (tex is Texture2D):
			return null
		var img: Image = (tex as Texture2D).get_image()
		if img == null:
			return null
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		images.append(img)
	var height := 0
	for img in images:
		height = maxi(height, (img as Image).get_height())
	var total_w := 0
	var scaled: Array = []
	for img in images:
		var copy: Image = (img as Image).duplicate()
		var w := int(round(float(copy.get_width()) * float(height) / float(copy.get_height())))
		copy.resize(w, height, Image.INTERPOLATE_LANCZOS)
		scaled.append(copy)
		total_w += w
	# Se solapan un 12% para que se lean como pareja y no como dos fotos pegadas.
	var overlap := int(float(total_w) * 0.06)
	var canvas := Image.create(total_w - overlap * (scaled.size() - 1), height, false, Image.FORMAT_RGBA8)
	var x := 0
	for img in scaled:
		canvas.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(x, 0))
		x += img.get_width() - overlap
	var out := ImageTexture.create_from_image(canvas)
	_composite_cache[key] = out
	return out


## Ruta declarada explicitamente en los datos de un personaje para una ranura, o
## "" para usar la convencion de carpetas (res://art/characters/<id>/<ranura>.png).
## Lo usan las pantallas que no tienen una unidad de combate (COLECCION, EQUIPO).
static func art_path_from(data: Dictionary, slot_name: String) -> String:
	var art = data.get("art", {})
	if art is Dictionary:
		return String(art.get(slot_name, ""))
	return ""


## Verdadero si esta ranura tiene un PNG real cargado (y no la silueta). Sirve
## para avisar de un asset que falta sin romper nada.
func has_art() -> bool:
	return texture != null


## Area visible de un PNG, con cache por ruta. Se puede llamar desde fuera para
## inspeccionar como queda encuadrada una imagen.
static func visible_rect_for(path: String, tex: Texture2D) -> Rect2:
	if path.is_empty() or tex == null:
		return Rect2()
	if _visible_cache.has(path):
		return _visible_cache[path]
	var rect := _scan_visible_rect(tex)
	_visible_cache[path] = rect
	return rect


## Busca el rectangulo que contiene el dibujo: primer y ultimo pixel visible en
## cada eje. Muestrea por pasos, asi que el coste es fijo aunque el PNG sea enorme.
static func _scan_visible_rect(tex: Texture2D) -> Rect2:
	var full := Rect2(Vector2.ZERO, tex.get_size())
	var image := tex.get_image()
	if image == null:
		return full
	if image.is_compressed():
		image.decompress()
	var tex_w := image.get_width()
	var tex_h := image.get_height()
	if tex_w <= 0 or tex_h <= 0:
		return full

	var step := maxi(1, int(ceil(float(maxi(tex_w, tex_h)) / float(SCAN_SAMPLES))))
	var min_x := tex_w
	var min_y := tex_h
	var max_x := -1
	var max_y := -1
	var y := 0
	while y < tex_h:
		var x := 0
		while x < tex_w:
			if image.get_pixel(x, y).a > ALPHA_THRESHOLD:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
			x += step
		y += step

	if max_x < min_x or max_y < min_y:
		# Imagen totalmente transparente: no hay nada que encuadrar.
		return full

	# Un paso de margen: el muestreo va por saltos y podria quedarse a un pixel
	# del borde real del dibujo. Se recorta al tamano de la imagen.
	var rect := Rect2(
		Vector2(float(min_x), float(min_y)),
		Vector2(float(max_x - min_x + 1), float(max_y - min_y + 1))
	).grow(float(step))
	rect.position.x = maxf(0.0, rect.position.x)
	rect.position.y = maxf(0.0, rect.position.y)
	rect.size.x = minf(rect.size.x, float(tex_w) - rect.position.x)
	rect.size.y = minf(rect.size.y, float(tex_h) - rect.position.y)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return full
	return rect


## Orden de busqueda del arte de esta ranura: 1) ruta explicita del JSON,
## 2) convencion res://art/characters/<id>/<ranura>.png, 3) ruta antigua plana.
## Separar la busqueda aqui hace que anadir una convencion nueva sea tocar una
## sola lista.
func _candidates(character_id: String, explicit_path: String) -> Array:
	var paths: Array = []
	if not character_id.is_empty():
		var dirs := art_dirs(character_id)
		# 1) Arte de la FORMA actual (ssr/ur/lr): gana al arte base, asi un SSR
		#    evolucionado a UR ensena su arte de UR en cuanto el PNG existe. Se prueba
		#    en todas las carpetas posibles de la unidad (ver art_dirs).
		if not form.is_empty():
			for dir in dirs:
				paths.append("%s%s/%s.png" % [dir, form, slot])
		# 2) Ruta explicita del JSON (si la hay).
		if not explicit_path.is_empty():
			paths.append(explicit_path)
		# 3) Arte base de la unidad, sin forma.
		for dir in dirs:
			paths.append("%s%s.png" % [dir, slot])
		paths.append("%s%s.png" % [LEGACY_ART_DIR, character_id])
	elif not explicit_path.is_empty():
		paths.append(explicit_path)
	return paths


## Carpetas donde puede vivir el arte de una unidad, de la mas especifica a la mas
## antigua. El ID de la unidad (gojo_001) NO es su nombre visible: el nombre sale del
## JSON y el id solo ordena carpetas. Estructuras admitidas, todas a la vez:
##   res://art/characters/<familia>/<id>/<forma>/<ranura>.png   (recomendada)
##       p. ej. art/characters/gojo/gojo_001/ssr/front.png
##   res://art/characters/<id>/<forma>/<ranura>.png             (la de siempre)
## La familia es "art_family" del JSON o, si no la hay, el id sin su sufijo
## numerico (gojo_001 -> gojo). Los ids antiguos sin sufijo (gojo) siguen usando
## solo la carpeta plana: nada de lo existente se mueve ni se renombra.
static func art_dirs(character_id: String) -> Array:
	var dirs: Array = []
	var id := String(character_id)
	if id.is_empty():
		return dirs
	var family := family_of(id)
	if not family.is_empty() and family != id:
		dirs.append("%s%s/%s/" % [ART_ROOT, family, id])
	dirs.append("%s%s/" % [ART_ROOT, id])
	return dirs


## Familia de arte de una unidad: "art_family" del JSON o el id sin sufijo _NNN.
static func family_of(character_id: String) -> String:
	var id := String(character_id)
	var declared := ""
	if DB != null and DB.characters.has(id):
		declared = String((DB.characters[id] as Dictionary).get("art_family", ""))
	if not declared.is_empty():
		return declared
	var regex := RegEx.new()
	regex.compile("^(.+)_\\d+$")
	var found := regex.search(id)
	return found.get_string(1) if found != null else id


## Ruta del arte de una forma concreta. Es la convencion que documenta
## res://art/characters/README.md: <id>/<forma>/<ranura>.png
static func form_art_path(character_id: String, form_name: String, slot_name: String) -> String:
	if String(character_id).is_empty() or String(form_name).is_empty():
		return ""
	return "%s%s/%s/%s.png" % [ART_ROOT, character_id, form_name.to_lower(), slot_name]


## Hay arte propio para esa forma? Lo usan el README y la ficha para poder decir
## "esta forma tiene su propia imagen" sin cargar nada de mas.
static func form_art_exists(character_id: String, form_name: String, slot_name: String) -> bool:
	if String(character_id).is_empty() or String(form_name).is_empty():
		return false
	for dir in art_dirs(character_id):
		if ResourceLoader.exists("%s%s/%s.png" % [dir, form_name.to_lower(), slot_name]):
			return true
	return false


func _try_load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var loaded := load(path)
	if loaded is Texture2D:
		return loaded
	return null


func _refresh() -> void:
	_ensure_layers()
	_update_frame()
	queue_redraw()
	if _art_layer != null:
		_art_layer.queue_redraw()
		_frame_layer.queue_redraw()


## Marco fino y anguloso del color del tipo. No lleva sombra ni brillo propios: las
## tarjetas y los paneles que lo rodean ya los ponen.
func _update_frame() -> void:
	var cut := clampf(minf(size.x, size.y) * 0.07, 5.0, 18.0)
	_frame = Frame.build({
		"fill_top": Color(accent.r, accent.g, accent.b, 0.13),
		"fill_bottom": Color(accent.r, accent.g, accent.b, 0.04),
		"metal_light": Color(accent.r, accent.g, accent.b, 0.95).lerp(Color.WHITE, 0.35),
		"metal_dark": Color(accent.r, accent.g, accent.b, 0.85).darkened(0.45),
		"edge_width": 2.5,
		"cut": cut,
		"cut_corners": Frame.CORNERS_ALL,
		"shadow": 0.0,
		"outline": Color(0, 0, 0, 0.35),
		"inner_light": Color(1, 1, 1, 0.0),
	})


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return
	# Relleno suave del hueco (se ve debajo del arte y de la silueta).
	if _frame != null and not transparent_frame:
		draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	if aura > 0.0:
		_draw_aura(w, h)
	if texture == null:
		_draw_silhouette(w, h)


## Resplandor de escenario: disco radial del color del tipo detras del personaje y
## una elipse de luz en el suelo. Son circulos concentricos con alfa bajo.
func _draw_aura(w: float, h: float) -> void:
	var center := Vector2(w * 0.5, h * 0.46)
	var radius := minf(w, h * 0.62) * 0.62
	var warm := accent.lerp(Color(1.0, 0.92, 0.8), 0.45)
	for i in range(9, 0, -1):
		var k := float(i) / 9.0
		draw_circle(center, radius * (0.25 + 0.75 * k), Color(warm.r, warm.g, warm.b, 0.045 * aura * (1.2 - k)))
	var floor_c := Vector2(w * 0.5, h * 0.93)
	for i in range(6, 0, -1):
		var k := float(i) / 6.0
		_draw_ellipse(floor_c, Vector2(w * 0.40 * k, h * 0.035 * k), Color(accent.r, accent.g, accent.b, 0.07 * aura * (1.1 - k)))


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)


## Capa del arte (la llama portrait_layer.gd). Dibuja el PNG con el shader de luz.
func paint_art(canvas: CanvasItem) -> void:
	if texture == null:
		canvas.material = null
		return
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return
	var fitted := _fitted_rect()
	if lit:
		if _material == null:
			_material = ShaderMaterial.new()
			_material.shader = LIGHT_SHADER
		var rim := accent.lerp(Color.WHITE, 0.55)
		_material.set_shader_parameter("rim_color", rim)
		_material.set_shader_parameter("rim_px", clampf(rim_screen_px / maxf(fitted[2], 0.0001), 1.0, 60.0))
		canvas.material = _material
	else:
		canvas.material = null
	canvas.draw_texture_rect_region(texture, fitted[0], fitted[1])


func paint_frame(canvas: CanvasItem) -> void:
	if transparent_frame:
		return
	if _frame != null and texture != null:
		# El relleno ya se pinto debajo del arte: aqui solo el marco, con el centro
		# transparente.
		var edge := Frame.build({
			"fill_top": Color(0, 0, 0, 0), "fill_bottom": Color(0, 0, 0, 0),
			"metal_light": _frame.metal_light, "metal_dark": _frame.metal_dark,
			"edge_width": _frame.edge_width, "cut": _frame.cut, "shadow": 0.0,
			"outline": _frame.outline, "inner_light": Color(1, 1, 1, 0.0),
		})
		canvas.draw_style_box(edge, Rect2(Vector2.ZERO, size))
	elif _frame != null:
		canvas.draw_style_box(_frame, Rect2(Vector2.ZERO, size))


## Rectangulo donde se dibuja el area visible del PNG, escalada proporcionalmente y
## centrada en el hueco: [destino, origen, escala]. La escala es la misma en los
## dos ejes (se coge la menor), asi que la imagen nunca se deforma, y al usar el
## area visible el personaje ocupa el maximo espacio disponible sin quedar cortado.
func _fitted_rect() -> Array:
	var source := source_rect
	if source.size.x <= 1.0 or source.size.y <= 1.0:
		source = Rect2(Vector2.ZERO, texture.get_size())
	var scale := minf(size.x * (1.0 + width_slack) / maxf(source.size.x, 1.0), size.y / maxf(source.size.y, 1.0))
	var drawn := source.size * scale
	var position := Vector2((size.x - drawn.x) * 0.5, (size.y - drawn.y) * 0.5)
	if feet_down:
		position.y = size.y - drawn.y
	return [Rect2(position, drawn), source, scale]


func _draw_silhouette(w: float, h: float) -> void:
	# Todo se dibuja dentro de un cuadrado centrado en el control. Asi la figura
	# no se deforma cuando el hueco es mas ancho que alto (por ejemplo en la
	# vista de juego del editor, que no es vertical).
	var s := minf(w, h)
	var ox := (w - s) * 0.5
	var oy := (h - s) * 0.5
	var body := Color(0.05, 0.06, 0.11, 0.94)
	var rim := Color(accent.r, accent.g, accent.b, 0.85)
	var center := Vector2(ox + s * 0.5, oy + s * 0.46)

	# Halo detras del personaje.
	for i in range(7, 0, -1):
		var radius := s * (0.18 + 0.05 * float(i))
		var alpha := 0.05 * float(8 - i)
		draw_circle(center, radius, Color(accent.r, accent.g, accent.b, alpha))

	var head_center := Vector2(ox + s * 0.5, oy + s * 0.40)
	var head_radius := s * 0.16
	var shoulder_top := oy + s * 0.60

	match style:
		"spiky":
			draw_colored_polygon(PackedVector2Array([
				head_center + Vector2(-head_radius, -head_radius * 0.2),
				head_center + Vector2(-head_radius * 0.55, -head_radius * 1.95),
				head_center + Vector2(-head_radius * 0.05, -head_radius * 0.95),
				head_center + Vector2(head_radius * 0.5, -head_radius * 2.05),
				head_center + Vector2(head_radius, -head_radius * 0.3),
			]), body)
		"long":
			draw_colored_polygon(PackedVector2Array([
				head_center + Vector2(-head_radius * 1.15, -head_radius * 0.95),
				head_center + Vector2(head_radius * 1.15, -head_radius * 0.95),
				head_center + Vector2(head_radius * 1.4, head_radius * 2.5),
				head_center + Vector2(-head_radius * 1.4, head_radius * 2.5),
			]), body)
		"ponytail":
			draw_colored_polygon(PackedVector2Array([
				head_center + Vector2(-head_radius * 1.05, -head_radius * 0.75),
				head_center + Vector2(head_radius * 1.05, -head_radius * 0.75),
				head_center + Vector2(head_radius * 0.92, head_radius * 0.75),
				head_center + Vector2(-head_radius * 0.92, head_radius * 0.75),
			]), body)
			draw_colored_polygon(PackedVector2Array([
				head_center + Vector2(head_radius * 0.85, -head_radius * 0.35),
				head_center + Vector2(head_radius * 2.0, head_radius * 1.15),
				head_center + Vector2(head_radius * 1.25, head_radius * 1.7),
			]), body)
		_:
			draw_circle(head_center + Vector2(0.0, -head_radius * 0.28), head_radius * 1.09, body)

	# Hombros.
	draw_colored_polygon(PackedVector2Array([
		Vector2(ox + s * 0.05, oy + s),
		Vector2(ox + s * 0.15, shoulder_top + head_radius * 0.55),
		Vector2(ox + s * 0.36, shoulder_top),
		Vector2(ox + s * 0.64, shoulder_top),
		Vector2(ox + s * 0.85, shoulder_top + head_radius * 0.55),
		Vector2(ox + s * 0.95, oy + s),
	]), body)

	# Cabeza encima del pelo, para que el pelo quede por detras.
	draw_circle(head_center, head_radius, body)
	draw_arc(head_center, head_radius, 0.0, TAU, 40, rim, 2.5, true)
	draw_line(
		Vector2(ox + s * 0.36, shoulder_top),
		Vector2(ox + s * 0.64, shoulder_top),
		Color(rim.r, rim.g, rim.b, 0.5),
		3.0
	)
