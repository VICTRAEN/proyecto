extends RefCounted

## IDENTIDAD VISUAL del proyecto, en un unico sitio.
##
## Aqui viven los colores, los tamanos de texto, los radios y el estilo de las
## tarjetas. Las pantallas leen de aqui en lugar de inventarse colores propios:
## asi toda la interfaz parece disenada por la misma persona y cambiar el aspecto
## del juego es cambiar este archivo.
##
## Los colores de los TIPOS (STR, AGL, INT, TEQ, PHY) siguen en
## ui/type_colors.gd, que es su unica fuente. Aqui solo se usan.
##
## Regla: ningun color suelto en una pantalla. Si hace falta un color nuevo, se
## anade aqui con un nombre que diga para que sirve.

## --- Superficies ------------------------------------------------------------

## Fondo base del juego. Se ve detras de todo y da el tono "noche + neon".
const BG := Color(0.043, 0.051, 0.102, 1.0)
## Panel normal: semitransparente para que el fondo se intuya por debajo.
const PANEL := Color(0.078, 0.086, 0.169, 0.90)
## Panel solido: para lo que tapa de verdad (fichas, dialogos, resultado).
const PANEL_STRONG := Color(0.086, 0.094, 0.184, 0.97)
const PANEL_BORDER := Color(0.353, 0.416, 0.722, 0.85)

## --- Tinta ------------------------------------------------------------------

const INK := Color(0.941, 0.957, 1.0, 1.0)
const INK_SOFT := Color(0.678, 0.722, 0.878, 1.0)
const INK_DIM := Color(0.502, 0.545, 0.694, 1.0)

## --- Acentos ----------------------------------------------------------------

## Dorado: lo importante (titulos, el turno activo, subir de nivel, premios).
const GOLD := Color(1.0, 0.784, 0.337, 1.0)
## Azul: accion normal (botones, enlaces, barras de informacion).
const BLUE := Color(0.361, 0.471, 0.929, 1.0)
const GREEN := Color(0.349, 0.851, 0.522, 1.0)
const RED := Color(0.925, 0.318, 0.361, 1.0)
const VIOLET := Color(0.620, 0.451, 0.961, 1.0)

## --- Tipografia -------------------------------------------------------------

const FONT_TITLE := 62
const FONT_BIG := 40
const FONT_SECTION := 30
const FONT_BODY := 24
const FONT_SMALL := 20
const FONT_TINY := 17

## --- Formas -----------------------------------------------------------------

const RADIUS_PANEL := 22
const RADIUS_CARD := 18
const RADIUS_CHIP := 12
## Altura minima comoda para tocar con el dedo en movil vertical.
const TOUCH := 104.0

## --- Rarezas ----------------------------------------------------------------
## SISTEMA CENTRAL DE RAREZAS. Cada rareza define su identidad visual completa en
## un solo sitio: color principal, secundario, borde, brillo, fondo de carta,
## intensidad de efectos y si esta pensada para llevar animacion (por ahora la
## bandera "animated" queda declarada pero no se anima nada).
##
## Ninguna pantalla escribe un color de rareza: todas preguntan aqui. Anadir una
## rareza nueva es anadir una linea a este diccionario y una entrada a
## RARITY_ORDER, y aparece sola en tarjetas, coleccion, equipo y combate.
##
## Claves de cada entrada:
##   color     -> color principal (etiqueta, borde, nombre)
##   secondary -> segundo color, para degradados y detalles
##   border    -> color del marco de la carta
##   bg        -> fondo de la carta
##   glow      -> cuanto brilla (0..1). Escala sombras y resplandores.
##   intensity -> fuerza general del estilo (0..1). Escala marcos y franjas.
##   animated  -> reservado para cartas animadas (LR). Hoy solo se declara.
const RARITY := {
	"R": {
		"color": Color(0.639, 0.686, 0.804, 1.0),
		"secondary": Color(0.435, 0.478, 0.596, 1.0),
		"border": Color(0.478, 0.522, 0.643, 1.0),
		"bg": Color(0.086, 0.098, 0.157, 0.94),
		"glow": 0.0, "intensity": 0.0, "animated": false,
	},
	"SR": {
		"color": Color(0.443, 0.702, 1.0, 1.0),
		"secondary": Color(0.235, 0.400, 0.780, 1.0),
		"border": Color(0.443, 0.702, 1.0, 0.72),
		"bg": Color(0.070, 0.114, 0.204, 0.94),
		"glow": 0.22, "intensity": 0.25, "animated": false,
	},
	"SSR": {
		"color": Color(1.0, 0.784, 0.337, 1.0),
		"secondary": Color(0.925, 0.510, 0.180, 1.0),
		"border": Color(1.0, 0.784, 0.337, 0.85),
		"bg": Color(0.161, 0.118, 0.059, 0.95),
		"glow": 0.42, "intensity": 0.5, "animated": false,
	},
	"UR": {
		"color": Color(1.0, 0.435, 0.702, 1.0),
		"secondary": Color(0.702, 0.353, 0.980, 1.0),
		"border": Color(1.0, 0.435, 0.702, 0.92),
		"bg": Color(0.176, 0.078, 0.145, 0.95),
		"glow": 0.62, "intensity": 0.75, "animated": false,
	},
	"LR": {
		"color": Color(0.400, 0.949, 0.976, 1.0),
		"secondary": Color(1.0, 0.784, 0.337, 1.0),
		"border": Color(0.400, 0.949, 0.976, 0.95),
		"bg": Color(0.055, 0.157, 0.184, 0.96),
		"glow": 0.85, "intensity": 1.0, "animated": true,
	},
}
const RARITY_DEFAULT := Color(0.639, 0.686, 0.804, 1.0)
## Rarezas de PEOR a MEJOR. Es el orden que usan los filtros, las ordenaciones y
## el "es una forma superior?". Una rareza que no este aqui se queda al final.
const RARITY_ORDER := ["R", "SR", "SSR", "UR", "LR"]


static func rarity_entry(rarity: String) -> Dictionary:
	var entry = RARITY.get(rarity, null)
	if entry is Dictionary:
		return entry
	return {}


static func rarity_color(rarity: String) -> Color:
	var entry := rarity_entry(rarity)
	if entry.is_empty():
		return RARITY_DEFAULT
	return Color(entry["color"])


## Cuanto tiene que brillar el marco de una rareza (0 = nada). Sirve para que las
## rarezas altas se reconozcan de un vistazo sin montar un sistema de efectos.
static func rarity_glow(rarity: String) -> float:
	var entry := rarity_entry(rarity)
	if entry.is_empty():
		return 0.0
	return float(entry["glow"])


static func rarity_secondary(rarity: String) -> Color:
	var entry := rarity_entry(rarity)
	if entry.is_empty():
		return RARITY_DEFAULT
	return Color(entry.get("secondary", entry["color"]))


static func rarity_bg(rarity: String) -> Color:
	var entry := rarity_entry(rarity)
	if entry.is_empty():
		return PANEL
	return Color(entry.get("bg", PANEL))


static func rarity_border(rarity: String) -> Color:
	var entry := rarity_entry(rarity)
	if entry.is_empty():
		return PANEL_BORDER
	return Color(entry.get("border", PANEL_BORDER))


## Fuerza del estilo de una rareza (0..1). Escala marcos, franjas y resplandores,
## para que UR y LR se noten mas que un SR sin escribir numeros por pantalla.
static func rarity_intensity(rarity: String) -> float:
	var entry := rarity_entry(rarity)
	if entry.is_empty():
		return 0.0
	return float(entry.get("intensity", 0.0))


## Posicion de una rareza en el orden (mayor = mejor). Las desconocidas van al
## final, nunca fuera de la lista.
static func rarity_rank(rarity: String) -> int:
	var index := RARITY_ORDER.find(String(rarity))
	return index if index >= 0 else RARITY_ORDER.size()


## La forma `form` es SUPERIOR a la forma `base`? Lo usan las tarjetas para marcar
## un personaje evolucionado sin conocer ninguna rareza concreta.
static func is_form_upgrade(base: String, form: String) -> bool:
	if String(base).is_empty() or String(form).is_empty():
		return false
	return rarity_rank(form) > rarity_rank(base)


## Etiqueta de rareza lista para pegar en una carta, con el tratamiento que le toca
## a su rareza (tamano y contorno crecen con la intensidad).
static func rarity_badge(rarity: String, base_size: int = FONT_BODY) -> Label:
	var color := rarity_color(rarity)
	var intensity := rarity_intensity(rarity)
	var label := Label.new()
	label.text = String(rarity).to_upper()
	label.add_theme_font_size_override("font_size", base_size + int(round(intensity * 10.0)))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 5 + int(round(intensity * 4.0)))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## --- Constructores de estilo ------------------------------------------------

## Panel estandar de la interfaz.
static func panel(alpha: float = 0.90, border: bool = true, radius: int = RADIUS_PANEL) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, alpha)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	if border:
		style.set_border_width_all(2)
		style.border_color = PANEL_BORDER
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 4.0)
	return style


## Marco de una carta (coleccion, equipo y combate). El color del tipo manda en
## el borde; la rareza anade brillo; el estado elegido lo pinta en dorado.
static func card(tint: Color, selected: bool = false, rarity: String = "", strong: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_CARD)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	var glow := rarity_glow(rarity)
	if selected:
		style.set_border_width_all(4)
		style.border_color = GOLD
		style.bg_color = Color(tint.r * 0.22, tint.g * 0.20, tint.b * 0.28, 0.96)
		style.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
		style.shadow_size = 14
		style.shadow_offset = Vector2.ZERO
		return style
	style.set_border_width_all(3 if strong else 2)
	style.border_color = Color(tint.r, tint.g, tint.b, 0.55 + glow * 0.4)
	style.bg_color = Color(tint.r * 0.10, tint.g * 0.10, tint.b * 0.16, 0.92)
	if glow > 0.0:
		style.shadow_color = Color(rarity_color(rarity).r, rarity_color(rarity).g, rarity_color(rarity).b, glow * 0.5)
		style.shadow_size = int(6.0 + glow * 14.0)
		style.shadow_offset = Vector2.ZERO
	else:
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.40)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0.0, 3.0)
	return style


## CARTA DE UNA RAREZA. Es el constructor que usan las tarjetas de personaje: el
## fondo es el de la rareza, el borde es el suyo y se engorda con la intensidad, y
## el resplandor crece con el brillo. Sin seleccion, el estilo no depende de nadie
## mas: una carta SSR se ve como una SSR en cualquier pantalla.
static func rarity_card(rarity: String, selected: bool = false, evolved: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_CARD)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	var color := rarity_color(rarity)
	var intensity := rarity_intensity(rarity)
	var glow := rarity_glow(rarity)
	if selected:
		style.set_border_width_all(4)
		style.border_color = GOLD
		style.bg_color = rarity_bg(rarity).lerp(Color(GOLD.r, GOLD.g, GOLD.b, 1.0), 0.14)
		style.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.50)
		style.shadow_size = 16
		style.shadow_offset = Vector2.ZERO
		return style
	style.set_border_width_all(2 + int(round(intensity * 4.0)))
	style.border_color = rarity_border(rarity)
	style.bg_color = rarity_bg(rarity)
	if glow > 0.0:
		style.shadow_color = Color(color.r, color.g, color.b, glow * 0.55)
		style.shadow_size = int(8.0 + glow * 20.0)
		style.shadow_offset = Vector2.ZERO
	else:
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.40)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0.0, 3.0)
	# Una forma evolucionada anade un segundo borde del color secundario: la carta
	# se ve "vestida de otra manera" sin cambiar de forma.
	if evolved:
		style.set_border_width_all(1 + int(round(intensity * 3.0)))
		style.border_color = rarity_secondary(rarity)
		style.shadow_color = Color(color.r, color.g, color.b, maxf(0.45, glow))
		style.shadow_size = int(12.0 + glow * 22.0)
		style.shadow_offset = Vector2.ZERO
	return style


## Etiqueta de rareza lista para pegar en una carta.
static func rarity_chip(rarity: String) -> Label:
	var color := rarity_color(rarity)
	var label := Label.new()
	label.text = rarity
	label.add_theme_font_size_override("font_size", FONT_TINY)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Titulo de pantalla con el estilo de la casa (dorado, contorno negro).
static func style_title(label: Label, size: int = FONT_BIG) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", GOLD)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.88))
	label.add_theme_constant_override("outline_size", 9)


## Texto de apoyo bajo un titulo.
static func style_subtitle(label: Label) -> void:
	label.add_theme_font_size_override("font_size", FONT_SMALL)
	label.add_theme_color_override("font_color", INK_SOFT)


## Aviso de poco peso (notas, pistas, contadores).
static func style_note(label: Label) -> void:
	label.add_theme_font_size_override("font_size", FONT_TINY)
	label.add_theme_color_override("font_color", INK_DIM)


## Un boton que manda: se le pone el acento que toque sin tocar el tema global.
static func tint_button(button: Button, color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(color.r * 0.30, color.g * 0.30, color.b * 0.38, 0.97)
	normal.set_corner_radius_all(RADIUS_PANEL)
	normal.set_border_width_all(3)
	normal.border_color = Color(color.r, color.g, color.b, 0.95)
	normal.content_margin_top = 20.0
	normal.content_margin_bottom = 20.0
	normal.shadow_color = Color(color.r, color.g, color.b, 0.35)
	normal.shadow_size = 12
	normal.shadow_offset = Vector2(0.0, 5.0)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(color.r * 0.44, color.g * 0.44, color.b * 0.52, 1.0)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(color.r * 0.60, color.g * 0.60, color.b * 0.68, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
