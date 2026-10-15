extends Control
class_name ScreenBackground

## Fondo de pantalla REEMPLAZABLE.
##
## Busca una imagen en res://art/backgrounds/<slot>.png y la pinta cubriendo la
## pantalla sin deformarla. Si esa imagen no existe todavia, dibuja un fondo
## provisional por codigo, asi que el juego nunca se queda en negro ni se rompe
## por falta de arte.
##
## Para cambiar un fondo: mete el PNG con el nombre correcto y ya esta. No se
## toca ningun script ni ningun JSON. Ver res://art/backgrounds/README.md.
##
## El slot lo fija la escena que lo usa ("menu", "collection", "team", "stages",
## "battle", "results", "missions"). Anadir un slot nuevo es una entrada mas en
## PALETTES y, si hace falta, una escena que lo pida.

const DIR := "res://art/backgrounds"
const EXTS := [".png", ".jpg", ".jpeg", ".webp"]

## Nombre del fondo que se pide. Lo fija la escena.
@export var slot := ""
## Oscurecido que se pinta encima de la imagen para que la interfaz se lea
## siempre. 0 = sin oscurecer; 0.42 = el valor por defecto.
@export_range(0.0, 0.85, 0.01) var scrim := 0.42

## Colores del fondo provisional, por slot. top/mid/low son el cielo, glow el
## punto de luz y hill_a/hill_b las dos siluetas del terreno.
const PALETTES := {
	"menu": {
		"top": Color(0.11, 0.10, 0.28), "mid": Color(0.42, 0.20, 0.42),
		"low": Color(0.85, 0.45, 0.36), "glow": Color(1.0, 0.80, 0.52),
		"hill_a": Color(0.09, 0.08, 0.20), "hill_b": Color(0.05, 0.05, 0.13),
	},
	"collection": {
		"top": Color(0.08, 0.09, 0.26), "mid": Color(0.24, 0.15, 0.45),
		"low": Color(0.40, 0.24, 0.58), "glow": Color(0.72, 0.62, 1.0),
		"hill_a": Color(0.10, 0.08, 0.22), "hill_b": Color(0.05, 0.05, 0.14),
	},
	"team": {
		"top": Color(0.06, 0.12, 0.24), "mid": Color(0.14, 0.34, 0.42),
		"low": Color(0.52, 0.62, 0.44), "glow": Color(1.0, 0.92, 0.68),
		"hill_a": Color(0.07, 0.14, 0.18), "hill_b": Color(0.04, 0.08, 0.11),
	},
	"stages": {
		"top": Color(0.06, 0.10, 0.26), "mid": Color(0.18, 0.28, 0.55),
		"low": Color(0.44, 0.54, 0.78), "glow": Color(0.78, 0.90, 1.0),
		"hill_a": Color(0.08, 0.12, 0.26), "hill_b": Color(0.05, 0.07, 0.17),
	},
	"battle": {
		"top": Color(0.07, 0.07, 0.18), "mid": Color(0.24, 0.13, 0.35),
		"low": Color(0.60, 0.26, 0.42), "glow": Color(1.0, 0.74, 0.48),
		"hill_a": Color(0.09, 0.07, 0.16), "hill_b": Color(0.05, 0.04, 0.10),
	},
	"results": {
		"top": Color(0.09, 0.07, 0.16), "mid": Color(0.32, 0.22, 0.30),
		"low": Color(0.72, 0.52, 0.30), "glow": Color(1.0, 0.86, 0.48),
		"hill_a": Color(0.10, 0.08, 0.14), "hill_b": Color(0.06, 0.05, 0.10),
	},
	"missions": {
		"top": Color(0.07, 0.10, 0.20), "mid": Color(0.22, 0.24, 0.40),
		"low": Color(0.46, 0.50, 0.36), "glow": Color(0.92, 1.0, 0.72),
		"hill_a": Color(0.08, 0.11, 0.16), "hill_b": Color(0.05, 0.06, 0.11),
	},
	# EVENTOS: atardecer calido, distinto del resto para que un evento se
	# reconozca de un vistazo. Es solo el fondo provisional: si existe
	# res://art/backgrounds/events.png, manda el PNG.
	"events": {
		"top": Color(0.14, 0.06, 0.22), "mid": Color(0.46, 0.16, 0.38),
		"low": Color(0.86, 0.42, 0.42), "glow": Color(1.0, 0.82, 0.62),
		"hill_a": Color(0.12, 0.06, 0.18), "hill_b": Color(0.06, 0.04, 0.12),
	},
	# HISTORIA y MAPA: azul profundo de atlas, para que la historia se distinga
	# del menu y del resto de pantallas.
	"history": {
		"top": Color(0.05, 0.07, 0.20), "mid": Color(0.16, 0.20, 0.46),
		"low": Color(0.40, 0.46, 0.72), "glow": Color(0.82, 0.90, 1.0),
		"hill_a": Color(0.07, 0.09, 0.20), "hill_b": Color(0.04, 0.05, 0.13),
	},
	"map": {
		"top": Color(0.06, 0.10, 0.18), "mid": Color(0.20, 0.34, 0.40),
		"low": Color(0.52, 0.66, 0.54), "glow": Color(1.0, 0.94, 0.70),
		"hill_a": Color(0.08, 0.14, 0.17), "hill_b": Color(0.04, 0.08, 0.10),
	},
	# MOCHILA: tono de madera y cuero.
	"inventory": {
		"top": Color(0.12, 0.08, 0.06), "mid": Color(0.34, 0.22, 0.14),
		"low": Color(0.62, 0.44, 0.26), "glow": Color(1.0, 0.86, 0.62),
		"hill_a": Color(0.14, 0.09, 0.06), "hill_b": Color(0.07, 0.05, 0.04),
	},
	# MUTACIONES: verde toxico, el color de "algo esta cambiando".
	"mutation": {
		"top": Color(0.05, 0.13, 0.10), "mid": Color(0.14, 0.36, 0.24),
		"low": Color(0.44, 0.72, 0.38), "glow": Color(0.80, 1.0, 0.70),
		"hill_a": Color(0.06, 0.16, 0.12), "hill_b": Color(0.03, 0.08, 0.06),
	},
	# TIENDA: oro y brasa de puesto de mercado. Es el unico fondo calido con el
	# dorado como protagonista, para que la tienda se reconozca al instante.
	"shop": {
		"top": Color(0.16, 0.09, 0.04), "mid": Color(0.48, 0.26, 0.08),
		"low": Color(0.92, 0.68, 0.26), "glow": Color(1.0, 0.94, 0.72),
		"hill_a": Color(0.18, 0.10, 0.05), "hill_b": Color(0.08, 0.05, 0.03),
	},
	# TORRE: piedra fria y azul de altura. Se sube, asi que el fondo va hacia
	# arriba: oscuro abajo y luz arriba.
	"tower": {
		"top": Color(0.10, 0.12, 0.24), "mid": Color(0.24, 0.26, 0.42),
		"low": Color(0.52, 0.54, 0.68), "glow": Color(0.90, 0.94, 1.0),
		"hill_a": Color(0.10, 0.11, 0.20), "hill_b": Color(0.05, 0.05, 0.12),
	},
}
## Escenarios de combate provisionales. El stage los pide por nombre con su
## campo "background" del JSON, asi que dos batallas pueden verse distintas
## antes de que exista ningun PNG.
const BATTLE_PLAIN := {
	"top": Color(0.07, 0.11, 0.22), "mid": Color(0.34, 0.34, 0.30),
	"low": Color(0.72, 0.62, 0.40), "glow": Color(1.0, 0.92, 0.66),
	"hill_a": Color(0.10, 0.13, 0.16), "hill_b": Color(0.05, 0.07, 0.10),
}
const BATTLE_FOREST := {
	"top": Color(0.04, 0.12, 0.14), "mid": Color(0.12, 0.32, 0.24),
	"low": Color(0.40, 0.58, 0.34), "glow": Color(0.78, 1.0, 0.74),
	"hill_a": Color(0.06, 0.17, 0.14), "hill_b": Color(0.03, 0.09, 0.08),
}
const BATTLE_RUINS := {
	"top": Color(0.10, 0.07, 0.18), "mid": Color(0.32, 0.18, 0.34),
	"low": Color(0.56, 0.34, 0.38), "glow": Color(1.0, 0.78, 0.62),
	"hill_a": Color(0.12, 0.09, 0.18), "hill_b": Color(0.06, 0.05, 0.11),
}
const DEFAULT_PALETTE := {
	"top": Color(0.06, 0.07, 0.16), "mid": Color(0.18, 0.18, 0.36),
	"low": Color(0.42, 0.36, 0.52), "glow": Color(0.86, 0.88, 1.0),
	"hill_a": Color(0.08, 0.08, 0.16), "hill_b": Color(0.05, 0.05, 0.11),
}

var texture: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	reload()
	resized.connect(queue_redraw)


## Cambia el fondo que se muestra. Lo usan las escenas que reutilizan un mismo
## nodo para varias pantallas (por ejemplo, el resultado del combate).
func show_slot(new_slot: String) -> void:
	slot = new_slot
	reload()


## Vuelve a buscar la imagen. Se llama al arrancar; si el jugador mete un PNG
## nuevo, la siguiente vez que se abra la pantalla se usa.
func reload() -> void:
	texture = load_texture(slot)
	queue_redraw()


## Imagen del slot, o null si todavia no existe el archivo.
static func load_texture(slot_name: String) -> Texture2D:
	if slot_name.is_empty():
		return null
	for ext in EXTS:
		var path := "%s/%s%s" % [DIR, slot_name, ext]
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Texture2D:
				return res
	return null


## Hay imagen real para este slot (util para avisar en pantalla de que falta).
static func has_image(slot_name: String) -> bool:
	return load_texture(slot_name) != null


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return
	if texture != null:
		_draw_cover(w, h)
	else:
		_draw_placeholder(w, h)
	if scrim > 0.0:
		draw_rect(Rect2(0.0, 0.0, w, h), Color(0.02, 0.025, 0.06, scrim))
	# Degradado inferior: los botones y los paneles viven abajo y tienen que
	# leerse sobre cualquier imagen.
	var bands := 16
	for i in bands:
		var t := float(i) / float(bands)
		var band_h := (h * 0.45) / float(bands)
		var y := h - (h * 0.45) + band_h * float(i)
		draw_rect(Rect2(0.0, y, w, band_h + 1.0), Color(0.02, 0.02, 0.05, 0.035 + t * 0.30))


## Pinta la imagen cubriendo la pantalla y recortando el sobrante: nunca se
## deforma, aunque la proporcion no coincida.
func _draw_cover(w: float, h: float) -> void:
	var tex_size := texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var target_aspect := w / h
	var tex_aspect := tex_size.x / tex_size.y
	var src: Rect2
	if tex_aspect > target_aspect:
		var crop_w := tex_size.y * target_aspect
		src = Rect2((tex_size.x - crop_w) * 0.5, 0.0, crop_w, tex_size.y)
	else:
		var crop_h := tex_size.x / target_aspect
		src = Rect2(0.0, (tex_size.y - crop_h) * 0.5, tex_size.x, crop_h)
	draw_texture_rect_region(texture, Rect2(0.0, 0.0, w, h), src)


## Fondo provisional dibujado: cielo en tres franjas, un punto de luz y dos
## siluetas de terreno. Es barato (solo se redibuja al cambiar de tamano) y da
## el tono de cada pantalla sin necesitar arte.
func _draw_placeholder(w: float, h: float) -> void:
	var pal: Dictionary = PALETTES.get(slot, DEFAULT_PALETTE)
	var top: Color = pal["top"]
	var mid: Color = pal["mid"]
	var low: Color = pal["low"]
	var glow: Color = pal["glow"]
	var horizon := h * 0.62

	draw_rect(Rect2(0.0, 0.0, w, horizon * 0.55), top)
	draw_rect(Rect2(0.0, horizon * 0.55, w, horizon * 0.30), mid.lerp(top, 0.25))
	draw_rect(Rect2(0.0, horizon * 0.85, w, horizon * 0.15 + 1.0), low.lerp(mid, 0.2))

	var sun := Vector2(w * 0.5, horizon * 0.88)
	for i in range(10, 0, -1):
		var radius := w * 0.05 * float(i)
		draw_circle(sun, radius, Color(glow.r, glow.g, glow.b, 0.028 * float(11 - i)))
	draw_circle(sun, w * 0.055, Color(glow.r, glow.g, glow.b, 0.85))

	_hills(w, h, horizon, pal["hill_a"], 0.16, 1.0)
	_hills(w, h, horizon, pal["hill_b"], 0.30, -0.7)
	draw_rect(Rect2(0.0, horizon + (h - horizon) * 0.55, w, h), pal["hill_b"])


## Silueta de montanas. phase desfasa la forma para que las dos capas no se
## superpongan igual en todas las pantallas.
func _hills(w: float, h: float, horizon: float, color: Color, height_ratio: float, phase: float) -> void:
	var points := PackedVector2Array()
	points.append(Vector2(0.0, h))
	var steps := 9
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := w * t
		var wave := sin(t * 3.1 + phase) * 0.5 + sin(t * 7.3 + phase * 2.0) * 0.3
		var y := horizon - h * height_ratio * (0.55 + wave * 0.45)
		points.append(Vector2(x, y))
	points.append(Vector2(w, h))
	draw_colored_polygon(points, color)
