extends PanelContainer

const VI := preload("res://ui/visual_identity.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")

## Tarjeta de personaje FUERA del combate: COLECCION, EQUIPO y escaparate.
##
## Pinta datos estaticos del JSON (icono, nombre, tipo, rareza y nivel), no una
## unidad en combate. Por eso no conoce CombatUnit ni el estado de la batalla:
## aqui no hay HP ni SP que mostrar.
##
## IDENTIDAD DE RAREZA. La carta se construye por CAPAS, para que empiece a
## parecer una carta de un juego comercial y se pueda seguir ampliando despues:
##   1) fondo     -> color de fondo de la rareza (VI.rarity_bg)
##   2) marco     -> borde de la rareza, mas grueso cuanto mas alta (intensity)
##   3) brillo    -> resplandor del color de la rareza (glow)
##   4) arte      -> el retrato del personaje
##   5) franja    -> color de la rareza a la izquierda
##   6) etiqueta  -> R / SR / SSR / UR / LR con el tratamiento de su rareza
## Ninguna pantalla escribe un color de rareza: todo sale de ui/visual_identity.gd,
## asi que una rareza nueva aparece sola aqui.
##
## FORMA ACTUAL. El arte se pide con el id del personaje y el retrato resuelve
## solo su forma (SSR / UR / LR), de modo que un personaje evolucionado ensena el
## arte de su forma nueva sin que esta tarjeta sepa de evoluciones. Si esa forma
## todavia no tiene PNG, el retrato cae al arte base: se pueden ir metiendo las
## imagenes de una en una.
##
## PERSONAJE NO OBTENIDO. Si los datos traen owned = false, la tarjeta se pinta
## como silueta con "???" y no desvela el nombre: el sistema queda preparado para
## una coleccion con partes por descubrir.
##
## CONTRATO (no cambiar): senal pressed(data) y
## bind(data, selected, extra, compact). COLECCION llama bind(data, false, "", true)
## y EQUIPO llama bind(data, selected, extra, true) y conecta pressed.

signal pressed(data: Dictionary)

var data: Dictionary = {}
var _selected := false
var _frame := StyleBoxFlat.new()

@onready var stripe: ColorRect = $HBox/RarityStripe
@onready var portrait: Portrait = $HBox/Portrait
@onready var name_label: Label = $HBox/Info/TopRow/NameLabel
@onready var rarity_chip: Label = $HBox/Info/TopRow/RarityChip
@onready var type_label: Label = $HBox/Info/TypeLabel
@onready var meta_label: Label = $HBox/Info/MetaLabel


func _ready() -> void:
	# La tarjeta entera es el boton: sus hijos no interceptan el toque.
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	# Marco por defecto de la identidad visual: mientras nadie llame a bind() la
	# tarjeta ya tiene el aspecto de la casa, nunca un panel vacio.
	_frame = VI.card(VI.INK_DIM, _selected, "", true)
	add_theme_stylebox_override("panel", _frame)
	_ignore_mouse_on_children(self)


## extra: texto que anade quien la usa ("EN EQUIPO", "TOCA PARA PONER"...).
## compact: version reducida para la rejilla del equipo.
func bind(new_data: Dictionary, selected: bool = false, extra: String = "", compact: bool = false) -> void:
	data = new_data
	_selected = selected
	var icon_size := 96.0 if compact else 132.0
	portrait.custom_minimum_size = Vector2(icon_size, icon_size)
	name_label.add_theme_font_size_override("font_size", VI.FONT_SMALL if compact else VI.FONT_BODY)
	rarity_chip.add_theme_font_size_override("font_size", VI.FONT_TINY if compact else VI.FONT_SMALL)
	if data.is_empty():
		portrait.setup("", VI.INK_DIM, "short", "", "icon", "")
		name_label.text = "VACIO"
		name_label.add_theme_color_override("font_color", VI.INK_DIM)
		_set_rarity_chip("", VI.INK_DIM)
		type_label.text = ""
		meta_label.text = extra
		_update_frame(VI.INK_DIM, "")
		return

	var id := String(data.get("id", ""))
	var type := String(data.get("type", "?"))
	var tint: Color = TypeColors.color_for(type)
	var rarity := String(data.get("rarity", ""))
	var owned := bool(data.get("owned", true))

	# Un personaje que el jugador no tiene no ensena su identidad: silueta y ???.
	# El sistema queda listo para una coleccion con partes por descubrir.
	if not owned:
		portrait.setup("", VI.INK_DIM, String(data.get("portrait_style", "short")), "", "icon", "")
		name_label.text = "???"
		name_label.add_theme_color_override("font_color", VI.INK_DIM)
		_set_rarity_chip("???", VI.INK_DIM)
		type_label.text = "???"
		type_label.add_theme_color_override("font_color", VI.INK_DIM)
		meta_label.text = "NO OBTENIDO" if extra.is_empty() else "NO OBTENIDO  -  %s" % extra
		_update_frame(VI.INK_DIM, "")
		return

	# Ruta explicita del JSON si existe; si no, la convencion <id>/<ranura>.png.
	# La forma (SSR/UR/LR) la resuelve el propio retrato desde el estado del
	# jugador, asi que aqui no hay ninguna logica de evolucion.
	portrait.setup(id, tint, String(data.get("portrait_style", "short")), Portrait.art_path_from(data, "icon"), "icon", "")
	name_label.text = String(data.get("name", id))
	name_label.add_theme_color_override("font_color", tint)
	type_label.text = type
	type_label.add_theme_color_override("font_color", tint)

	# La rareza manda en el marco; el tipo sigue pintando el retrato, el nombre y
	# su etiqueta, asi que las dos cosas se leen sin confundirse.
	_set_rarity_chip(rarity, VI.rarity_color(rarity))

	var parts := PackedStringArray()
	parts.append("Nv. %d" % int(data.get("level", 1)))
	if _is_evolved_form():
		# Una forma evolucionada lo dice con la palabra del jugador, no con un
		# identificador interno.
		parts.append("EVOLUCIONADO")
	if not portrait.has_art():
		parts.append("sin icono")
	if not extra.is_empty():
		parts.append(extra)
	meta_label.text = "  -  ".join(parts)
	_update_frame(tint, rarity)


## El personaje esta en una forma superior a la de su JSON? Se compara la rareza
## efectiva con la base, sin conocer ninguna rareza concreta.
func _is_evolved_form() -> bool:
	var base := String(data.get("base_rarity", ""))
	var form := String(data.get("rarity", ""))
	return VI.is_form_upgrade(base, form)


## Etiqueta de la rareza: R / SR / SSR / UR / LR en su color, con un tamano y un
## contorno que crecen con la rareza. El tratamiento lo decide VisualIdentity.
func _set_rarity_chip(rarity: String, color: Color) -> void:
	rarity_chip.text = rarity if not rarity.is_empty() else "--"
	rarity_chip.add_theme_color_override("font_color", color)
	rarity_chip.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	if rarity.is_empty():
		rarity_chip.add_theme_constant_override("outline_size", 5)
		return
	# El contorno se engorda con la rareza: un LR se lee de un vistazo.
	rarity_chip.add_theme_constant_override("outline_size", 5 + int(round(VI.rarity_intensity(rarity) * 4.0)))


func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	_press_feedback()
	pressed.emit(data)
	accept_event()


func _press_feedback() -> void:
	pivot_offset = size * 0.5
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(0.97, 0.97), 0.07)
	tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Marco de la carta. Fondo, borde, brillo y grosor salen del sistema central de
## rarezas: una rareza alta se nota por su color, su marco y su resplandor.
func _update_frame(tint: Color, rarity: String) -> void:
	if rarity.is_empty():
		_frame = VI.card(tint, _selected, "", true)
		add_theme_stylebox_override("panel", _frame)
		_update_stripe("", tint)
		return
	_frame = VI.rarity_card(rarity, _selected, false)
	add_theme_stylebox_override("panel", _frame)
	_update_stripe(rarity, VI.rarity_color(rarity))


## Franja lateral de rareza: el color del marco, repetido a la izquierda. Es la
## senal que se sigue viendo cuando la lista esta scrolleada rapido.
func _update_stripe(rarity: String, tint: Color) -> void:
	var glow := VI.rarity_glow(rarity)
	var width: float = 8.0 + roundf(VI.rarity_intensity(rarity) * 6.0)
	stripe.custom_minimum_size = Vector2(width, 0.0)
	stripe.color = Color(tint.r, tint.g, tint.b, 0.55 + glow * 0.45)
	stripe.visible = true


func _ignore_mouse_on_children(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse_on_children(child)
