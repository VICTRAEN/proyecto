extends RefCounted

## IDENTIDAD VISUAL del proyecto, en un unico sitio.
##
## DIRECCION ARTISTICA: anime gacha premium, fantasia sci-fi. Violeta profundo y
## azul medianoche como base, magenta y dorado como acentos de lujo, cian y
## esmeralda como acentos de sistema. Paneles oscuros con marcos metalicos
## biselados (dorado y cromo), esquinas anguladas, gemas decorativas, botones
## con degradado, brillo y sombra, y luz cinematografica (ver ui/vi_frame.gd).
##
## Aqui viven los colores, los tamanos de texto, las formas y los constructores de
## estilo. Las pantallas leen de aqui en lugar de inventarse colores propios:
## cambiar el aspecto del juego es cambiar este archivo (el tema global,
## ui/theme.tres, se REGENERA desde aqui con tools/build_theme.gd).
##
## Los colores de los TIPOS (STR, AGL, INT, TEQ, PHY) siguen en
## ui/type_colors.gd, que es su unica fuente. Aqui solo se usan.
##
## Regla: ningun color suelto en una pantalla. Si hace falta un color nuevo, se
## anade aqui con un nombre que diga para que sirve.

const Frame := preload("res://ui/vi_frame.gd")

## --- Superficies ------------------------------------------------------------

## Fondo base del juego (azul medianoche con un punto de violeta).
const BG := Color(0.035, 0.028, 0.090, 1.0)
## Panel normal: violeta muy oscuro, semitransparente para intuir el fondo.
const PANEL := Color(0.082, 0.058, 0.185, 0.92)
## Panel solido: para lo que tapa de verdad (fichas, dialogos, resultado).
const PANEL_STRONG := Color(0.066, 0.046, 0.150, 0.98)
const PANEL_BORDER := Color(0.62, 0.52, 0.92, 0.88)

## --- Tinta ------------------------------------------------------------------
## Texto de alto contraste: blanco calido, lavanda clara y lavanda apagada. Todos
## se leen sobre los paneles oscuros (contraste > 4.5:1).

const INK := Color(0.98, 0.97, 1.0, 1.0)
const INK_SOFT := Color(0.82, 0.78, 0.96, 1.0)
const INK_DIM := Color(0.62, 0.58, 0.80, 1.0)

## --- Acentos ----------------------------------------------------------------

## Dorado: lo importante (titulos, el turno activo, subir de nivel, premios).
const GOLD := Color(1.0, 0.80, 0.34, 1.0)
const GOLD_LIGHT := Color(1.0, 0.93, 0.64, 1.0)
const GOLD_DARK := Color(0.62, 0.40, 0.08, 1.0)
## Magenta: el acento "de lujo" (invocar, UR, resplandores).
const MAGENTA := Color(1.0, 0.30, 0.74, 1.0)
## Cian: tecnologia y LR.
const CYAN := Color(0.32, 0.92, 1.0, 1.0)
## Azul: accion normal (botones, enlaces, barras de informacion).
const BLUE := Color(0.40, 0.48, 0.96, 1.0)
const GREEN := Color(0.30, 0.90, 0.58, 1.0)
const RED := Color(0.96, 0.32, 0.38, 1.0)
const VIOLET := Color(0.66, 0.46, 0.98, 1.0)

## Metales de los marcos: el lado que mira a la luz y el que no.
const METAL_GOLD_LIGHT := Color(1.0, 0.93, 0.62, 1.0)
const METAL_GOLD_DARK := Color(0.58, 0.36, 0.07, 1.0)
const METAL_CHROME_LIGHT := Color(0.90, 0.88, 1.0, 1.0)
const METAL_CHROME_DARK := Color(0.30, 0.25, 0.54, 1.0)

## --- Tipografia -------------------------------------------------------------
## Sans-serif moderna (Rajdhani, licencia OFL, en assets/fonts). Los titulos van en
## MAYUSCULAS (ver style_title).

const FONT_PATH_BOLD := "res://assets/fonts/Rajdhani-Bold.ttf"
const FONT_PATH_SEMIBOLD := "res://assets/fonts/Rajdhani-SemiBold.ttf"
const FONT_PATH_MEDIUM := "res://assets/fonts/Rajdhani-Medium.ttf"

const FONT_TITLE := 66
const FONT_BIG := 44
const FONT_SECTION := 33
const FONT_BODY := 27
const FONT_SMALL := 22
const FONT_TINY := 19

static var _fonts := {}


## Fuente del juego. weight: "bold", "semibold" o "medium". Si el archivo falta se
## devuelve null y Godot usa su fuente por defecto: nunca falla por una fuente.
static func font(weight: String = "semibold") -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var path := FONT_PATH_SEMIBOLD
	if weight == "bold":
		path = FONT_PATH_BOLD
	elif weight == "medium":
		path = FONT_PATH_MEDIUM
	var loaded: Font = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Font:
			loaded = res
	_fonts[weight] = loaded
	return loaded


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
		"color": Color(0.70, 0.72, 0.84, 1.0),
		"secondary": Color(0.46, 0.48, 0.62, 1.0),
		"border": Color(0.52, 0.54, 0.68, 1.0),
		"bg": Color(0.082, 0.078, 0.150, 0.94),
		"glow": 0.0, "intensity": 0.0, "animated": false,
		# Marco: acero gris, sencillo, sin gemas.
		"metal_light": Color(0.82, 0.84, 0.92, 1.0), "metal_dark": Color(0.30, 0.31, 0.42, 1.0),
		"edge": 2.0, "cut": 8.0, "studs": false, "gloss": 0.0, "stud": Color(0.8, 0.82, 0.9, 1.0),
		"fill_top": Color(0.12, 0.11, 0.21, 0.94), "fill_bottom": Color(0.06, 0.055, 0.12, 0.96),
	},
	"SR": {
		"color": Color(0.46, 0.74, 1.0, 1.0),
		"secondary": Color(0.24, 0.42, 0.82, 1.0),
		"border": Color(0.46, 0.74, 1.0, 0.80),
		"bg": Color(0.062, 0.110, 0.210, 0.94),
		"glow": 0.22, "intensity": 0.25, "animated": false,
		# Marco: plata azulada.
		"metal_light": Color(0.82, 0.93, 1.0, 1.0), "metal_dark": Color(0.18, 0.32, 0.62, 1.0),
		"edge": 3.0, "cut": 10.0, "studs": false, "gloss": 0.0, "stud": Color(0.6, 0.85, 1.0, 1.0),
		"fill_top": Color(0.10, 0.17, 0.32, 0.94), "fill_bottom": Color(0.04, 0.07, 0.16, 0.96),
	},
	"SSR": {
		"color": Color(1.0, 0.80, 0.34, 1.0),
		"secondary": Color(0.94, 0.52, 0.18, 1.0),
		"border": Color(1.0, 0.80, 0.34, 0.90),
		"bg": Color(0.165, 0.115, 0.060, 0.95),
		"glow": 0.42, "intensity": 0.5, "animated": false,
		# Marco: oro pulido con gemas doradas en las esquinas.
		"metal_light": Color(1.0, 0.95, 0.66, 1.0), "metal_dark": Color(0.56, 0.34, 0.06, 1.0),
		"edge": 4.0, "cut": 12.0, "studs": true, "gloss": 0.0, "stud": Color(1.0, 0.84, 0.36, 1.0),
		"fill_top": Color(0.26, 0.17, 0.08, 0.95), "fill_bottom": Color(0.10, 0.065, 0.045, 0.97),
	},
	"UR": {
		"color": Color(1.0, 0.44, 0.72, 1.0),
		"secondary": Color(0.72, 0.36, 0.98, 1.0),
		"border": Color(1.0, 0.44, 0.72, 0.94),
		"bg": Color(0.180, 0.070, 0.150, 0.95),
		"glow": 0.62, "intensity": 0.75, "animated": false,
		# Marco: rosa a violeta, doble de grueso, con gemas magenta y brillo.
		"metal_light": Color(1.0, 0.78, 0.92, 1.0), "metal_dark": Color(0.46, 0.10, 0.52, 1.0),
		"edge": 5.0, "cut": 14.0, "studs": true, "gloss": 0.14, "stud": Color(1.0, 0.45, 0.82, 1.0),
		"fill_top": Color(0.30, 0.09, 0.26, 0.95), "fill_bottom": Color(0.11, 0.04, 0.13, 0.97),
	},
	"LR": {
		"color": Color(0.40, 0.95, 0.98, 1.0),
		"secondary": Color(1.0, 0.80, 0.34, 1.0),
		"border": Color(0.40, 0.95, 0.98, 0.96),
		"bg": Color(0.050, 0.155, 0.190, 0.96),
		"glow": 0.85, "intensity": 1.0, "animated": true,
		# Marco: PRISMATICO. Los lados iluminados son cian y los oscuros, dorados:
		# es la unica rareza con dos metales distintos a la vez.
		"metal_light": Color(0.72, 1.0, 1.0, 1.0), "metal_dark": Color(0.86, 0.58, 0.12, 1.0),
		"edge": 6.0, "cut": 16.0, "studs": true, "gloss": 0.20, "stud": Color(1.0, 0.86, 0.40, 1.0),
		"fill_top": Color(0.07, 0.26, 0.32, 0.96), "fill_bottom": Color(0.03, 0.08, 0.13, 0.98),
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


## --- Constructores de estilo ------------------------------------------------
## TODOS devuelven un marco premium (ui/vi_frame.gd). Aceptan los mismos retoques
## que un StyleBoxFlat (border_color, set_border_width_all, shadow_color...), asi
## que las pantallas pueden teñir el metal con su acento sin conocer el bisel.

## Chaflan de las esquinas para un radio "clasico": proporcional y acotado.
static func cut_for(radius: int) -> float:
	if radius <= 0:
		return 0.0
	return clampf(float(radius) * 0.62, 6.0, 20.0)


## Panel estandar de la interfaz: violeta oscuro con marco de cromo biselado.
static func panel(alpha: float = 0.90, border: bool = true, radius: int = RADIUS_PANEL) -> Frame:
	return Frame.build({
		"fill_top": Color(0.125, 0.088, 0.270, alpha),
		"fill_bottom": Color(0.050, 0.036, 0.130, alpha),
		"metal_light": METAL_CHROME_LIGHT,
		"metal_dark": METAL_CHROME_DARK,
		"edge_width": 3.0 if border else 0.0,
		"cut": cut_for(radius),
		"inner_glow": Color(0.62, 0.46, 1.0, 0.45) if border else Color(0, 0, 0, 0),
		"shadow": 0.5 if border else 0.0,
		"outline": Color(0, 0, 0, 0.6) if border else Color(0, 0, 0, 0),
		"margin_x": 16.0, "margin_y": 12.0,
	}) as Frame


## Marco de una carta (coleccion, equipo y combate). El color del tipo manda en
## el metal; la rareza anade brillo; el estado elegido lo pinta en dorado.
static func card(tint: Color, selected: bool = false, rarity: String = "", strong: bool = false) -> Frame:
	var glow := rarity_glow(rarity)
	var props := {
		"fill_top": Color(tint.r * 0.20 + 0.05, tint.g * 0.15 + 0.04, tint.b * 0.26 + 0.09, 0.94),
		"fill_bottom": Color(tint.r * 0.08 + 0.03, tint.g * 0.06 + 0.025, tint.b * 0.12 + 0.06, 0.96),
		"metal_light": Color(tint.r, tint.g, tint.b, 1.0).lerp(Color.WHITE, 0.45),
		"metal_dark": Color(tint.r, tint.g, tint.b, 1.0).darkened(0.60),
		"edge_width": 4.0 if strong else 3.0,
		"cut": float(RADIUS_CARD) * 0.62,
		"inner_glow": Color(tint.r, tint.g, tint.b, 0.35),
		"shadow": 0.45,
		"margin_x": 12.0, "margin_y": 10.0,
	}
	if glow > 0.0:
		var rc := rarity_color(rarity)
		props["glow"] = Color(rc.r, rc.g, rc.b, glow * 0.55)
		props["glow_size"] = 6.0 + glow * 12.0
	if selected:
		props["metal_light"] = METAL_GOLD_LIGHT
		props["metal_dark"] = METAL_GOLD_DARK
		props["edge_width"] = 5.0
		props["glow"] = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
		props["glow_size"] = 14.0
		props["studs"] = true
	return Frame.build(props) as Frame


## CARTA DE UNA RAREZA. Es el constructor que usan las tarjetas de personaje: el
## metal, el grosor, las gemas y el resplandor son los de su rareza. Sin seleccion,
## el estilo no depende de nadie mas: una carta SSR se ve como una SSR en cualquier
## pantalla (oro), una UR en rosa-violeta y una LR prismatica (cian y oro).
static func rarity_card(rarity: String, selected: bool = false, evolved: bool = false) -> Frame:
	var entry := rarity_entry(rarity)
	if entry.is_empty():
		entry = RARITY["R"]
	var color := rarity_color(rarity)
	var glow := rarity_glow(rarity)
	var props := {
		"fill_top": entry["fill_top"],
		"fill_bottom": entry["fill_bottom"],
		"metal_light": entry["metal_light"],
		"metal_dark": entry["metal_dark"],
		"edge_width": entry["edge"],
		"cut": entry["cut"],
		"studs": entry["studs"],
		"stud_color": entry["stud"],
		"gloss": entry["gloss"],
		"inner_glow": Color(color.r, color.g, color.b, 0.30 + 0.35 * rarity_intensity(rarity)),
		"margin_x": 12.0, "margin_y": 10.0,
	}
	if glow > 0.0:
		props["glow"] = Color(color.r, color.g, color.b, glow * 0.60)
		props["glow_size"] = 8.0 + glow * 16.0
	if evolved:
		props["glow"] = Color(color.r, color.g, color.b, maxf(0.45, glow) * 0.8)
		props["glow_size"] = 12.0 + glow * 18.0
		props["studs"] = true
		props["edge_width"] = float(entry["edge"]) + 1.0
	if selected:
		props["metal_light"] = METAL_GOLD_LIGHT
		props["metal_dark"] = METAL_GOLD_DARK
		props["edge_width"] = maxf(5.0, float(entry["edge"]))
		props["glow"] = Color(GOLD.r, GOLD.g, GOLD.b, 0.60)
		props["glow_size"] = 16.0
		props["studs"] = true
		props["stud_color"] = GOLD
	return Frame.build(props) as Frame


## Carta de una unidad INSIGNIA (el duo): metal de dos colores, gemas y un
## resplandor doble. Es la unica que no sale de la tabla de rarezas.
static func special_card(tint: Color, tint2: Color) -> Frame:
	return Frame.build({
		"fill_top": Color(0.05, 0.06, 0.13, 0.97),
		"fill_bottom": Color(0.02, 0.025, 0.06, 0.98),
		"metal_light": Color(tint.r, tint.g, tint.b, 1.0).lerp(Color.WHITE, 0.45),
		"metal_dark": Color(tint2.r, tint2.g, tint2.b, 1.0).darkened(0.25),
		"edge_width": 7.0,
		"cut": 16.0,
		"studs": true,
		"stud_color": tint2,
		"gloss": 0.18,
		"inner_glow": Color(tint2.r, tint2.g, tint2.b, 0.55),
		"glow": Color(tint2.r, tint2.g, tint2.b, 0.70),
		"glow_size": 26.0,
		"margin_x": 10.0, "margin_y": 10.0,
	}) as Frame


## Caja pequeña tipo etiqueta (chips de estado, contadores, rarezas).
static func chip(color: Color, alpha: float = 0.92) -> Frame:
	return Frame.build({
		"fill_top": Color(color.r * 0.36 + 0.04, color.g * 0.36 + 0.03, color.b * 0.40 + 0.07, alpha),
		"fill_bottom": Color(color.r * 0.14 + 0.02, color.g * 0.14 + 0.02, color.b * 0.18 + 0.05, alpha),
		"metal_light": Color(color.r, color.g, color.b, 1.0).lerp(Color.WHITE, 0.40),
		"metal_dark": Color(color.r, color.g, color.b, 1.0).darkened(0.55),
		"edge_width": 2.0,
		"cut": 6.0,
		"cut_corners": Frame.CORNERS_DIAGONAL,
		"shadow": 0.30, "shadow_extent": 4.0, "shadow_dy": 2.0,
		"margin_x": 10.0, "margin_y": 4.0,
	}) as Frame


## Etiqueta de rareza lista para pegar en una carta, con el tratamiento que le toca
## a su rareza (tamano y contorno crecen con la intensidad).
static func rarity_badge(rarity: String, base_size: int = FONT_BODY) -> Label:
	var color := rarity_color(rarity)
	var intensity := rarity_intensity(rarity)
	var label := Label.new()
	label.text = String(rarity).to_upper()
	label.add_theme_font_size_override("font_size", base_size + int(round(intensity * 10.0)))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override("outline_size", 5 + int(round(intensity * 4.0)))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Etiqueta de rareza lista para pegar en una carta.
static func rarity_chip(rarity: String) -> Label:
	var color := rarity_color(rarity)
	var label := Label.new()
	label.text = rarity
	label.add_theme_font_size_override("font_size", FONT_TINY)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Titulo de pantalla con el estilo de la casa: MAYUSCULAS, dorado, contorno
## oscuro y una sombra que le da relieve. El texto se pasa a mayusculas al
## aplicar el estilo (los titulos se ponen antes).
static func style_title(label: Label, size: int = FONT_BIG) -> void:
	label.text = label.text.to_upper()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", GOLD_LIGHT.lerp(GOLD, 0.45))
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.20, 0.95))
	label.add_theme_constant_override("outline_size", 9)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 4)
	var bold := font("bold")
	if bold != null:
		label.add_theme_font_override("font", bold)


## Texto de apoyo bajo un titulo.
static func style_subtitle(label: Label) -> void:
	label.add_theme_font_size_override("font_size", FONT_SMALL)
	label.add_theme_color_override("font_color", INK_SOFT)


## Aviso de poco peso (notas, pistas, contadores).
static func style_note(label: Label) -> void:
	label.add_theme_font_size_override("font_size", FONT_TINY)
	label.add_theme_color_override("font_color", INK_DIM)


## Mezcla un acento con el tono del boton: el oro usa metal dorado y el resto,
## cromo teñido del acento.
static func _is_gold(color: Color) -> bool:
	return color.r > 0.8 and color.g > 0.62 and color.b < 0.5


## Estilos de un boton para un estado: "normal", "hover", "pressed", "disabled".
static func button_frame(color: Color, state: String = "normal") -> Frame:
	var gold := _is_gold(color)
	var light := METAL_GOLD_LIGHT if gold else Color(color.r, color.g, color.b, 1.0).lerp(METAL_CHROME_LIGHT, 0.55)
	var dark := METAL_GOLD_DARK if gold else Color(color.r, color.g, color.b, 1.0).darkened(0.55)
	var top := Color(color.r * 0.78 + 0.06, color.g * 0.78 + 0.05, color.b * 0.80 + 0.08, 0.98)
	var bottom := Color(color.r * 0.30, color.g * 0.28, color.b * 0.34 + 0.04, 0.98)
	if gold:
		# El oro NO sale de oscurecer el color (queda caqui): degradado propio, del
		# ambar vivo de arriba al naranja profundo de abajo, como un lingote pulido.
		top = Color(1.0, 0.82, 0.32, 0.98)
		bottom = Color(0.66, 0.34, 0.07, 0.98)
	var props := {
		"fill_top": top, "fill_bottom": bottom,
		"metal_light": light, "metal_dark": dark,
		"edge_width": 3.0,
		"cut": 12.0,
		"inner_glow": Color(color.r, color.g, color.b, 0.45),
		"glow": Color(color.r, color.g, color.b, 0.30), "glow_size": 7.0,
		"gloss": 0.55,
		"shadow": 0.55, "shadow_extent": 9.0, "shadow_dy": 5.0,
		"studs": false,
		"margin_x": 26.0, "margin_y": 20.0,
	}
	match state:
		"hover":
			props["fill_top"] = top.lightened(0.18)
			props["fill_bottom"] = bottom.lightened(0.20)
			props["glow"] = Color(color.r, color.g, color.b, 0.50)
			props["glow_size"] = 11.0
			props["gloss"] = 0.75
		"pressed":
			props["fill_top"] = bottom.lightened(0.10)
			props["fill_bottom"] = top.darkened(0.10)
			props["gloss"] = 0.0
			props["shadow_dy"] = 1.0
			props["shadow_extent"] = 4.0
			props["glow_size"] = 3.0
			props["margin_y"] = 22.0
		"disabled":
			props["fill_top"] = Color(0.15, 0.13, 0.24, 0.92)
			props["fill_bottom"] = Color(0.08, 0.07, 0.14, 0.92)
			props["metal_light"] = Color(0.44, 0.42, 0.56, 1.0)
			props["metal_dark"] = Color(0.18, 0.16, 0.28, 1.0)
			props["inner_glow"] = Color(0, 0, 0, 0)
			props["glow"] = Color(0, 0, 0, 0)
			props["glow_size"] = 0.0
			props["gloss"] = 0.0
			props["shadow"] = 0.25
	return Frame.build(props) as Frame


## Un boton que manda: se le pone el acento que toque sin tocar el tema global.
## Degradado con brillo, marco biselado, luz interior y sombra. El texto es blanco
## con contorno oscuro para leerse sobre cualquier acento.
static func tint_button(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("normal", button_frame(color, "normal"))
	button.add_theme_stylebox_override("hover", button_frame(color, "hover"))
	button.add_theme_stylebox_override("pressed", button_frame(color, "pressed"))
	button.add_theme_stylebox_override("disabled", button_frame(color, "disabled"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", GOLD_LIGHT)
	button.add_theme_color_override("font_disabled_color", Color(0.50, 0.48, 0.64, 1.0))
	if _is_gold(color):
		# Sobre oro claro el contorno ha de ser marron oscuro y grueso para que el
		# blanco se lea (contraste alto sin depender de un texto negro).
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_outline_color", Color(0.30, 0.12, 0.0, 0.95))
		button.add_theme_constant_override("outline_size", 7)
	else:
		button.add_theme_color_override("font_outline_color", Color(0.04, 0.0, 0.10, 0.70))
		button.add_theme_constant_override("outline_size", 5)
	var bold := font("bold")
	if bold != null:
		button.add_theme_font_override("font", bold)


## --- Iconos semi-3D -----------------------------------------------------------
## Iconos de interfaz en res://art/ui/icons/<nombre>.png (ver su README). Si el
## archivo no existe se devuelve null y el llamador dibuja sin icono: ninguna
## pantalla falla por un icono que falte.

const ICON_DIR := "res://art/ui/icons/"
static var _icons := {}


static func icon(icon_name: String) -> Texture2D:
	if _icons.has(icon_name):
		return _icons[icon_name]
	var tex: Texture2D = null
	var path := "%s%s.png" % [ICON_DIR, icon_name]
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			tex = res
	_icons[icon_name] = tex
	return tex


static func has_icon(icon_name: String) -> bool:
	return icon(icon_name) != null


## Icono listo para colgar de un contenedor, cuadrado de `px` pixeles.
static func icon_rect(icon_name: String, px: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = icon(icon_name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(px, px)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Boton de icono + texto (icono arriba, texto debajo), con el acento dado.
static func icon_button(button: Button, icon_name: String, color: Color, icon_px: int = 84) -> void:
	tint_button(button, color)
	var tex := icon(icon_name)
	if tex != null:
		button.icon = tex
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_constant_override("icon_max_width", icon_px)
		button.add_theme_constant_override("h_separation", 0)


## Boton ancho de icono a la IZQUIERDA y texto centrado (JUGAR, invocaciones...).
static func icon_button_side(button: Button, icon_name: String, color: Color, icon_px: int = 72) -> void:
	tint_button(button, color)
	var tex := icon(icon_name)
	if tex != null:
		button.icon = tex
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", icon_px)
		button.add_theme_constant_override("h_separation", 12)


## TITULO DE PANTALLA: sustituye el Label de titulo de una escena por la placa de
## cabecera (ui/title_banner.gd) con el acento de la pantalla. El Label sigue siendo
## el de la escena: el script que lo escribe no cambia. Se carga en tiempo de
## ejecucion (no con preload) porque la placa tambien usa esta identidad.
static func screen_title(label: Label, accent: Color = GOLD, font_size: int = FONT_BIG) -> Control:
	label.text = label.text.to_upper()
	var banner_script: GDScript = load("res://ui/title_banner.gd")
	return banner_script.adopt(label, accent, font_size)


## VENTANA / MODAL: la caja de fichas, confirmaciones y resultados. Violeta casi
## opaco (el telon de detras ya apaga la pantalla), marco dorado biselado con gemas
## en las cuatro esquinas y una luz suave del acento.
static func window(accent: Color = GOLD, alpha: float = 0.97) -> Frame:
	var gold := _is_gold(accent)
	return Frame.build({
		"fill_top": Color(0.15, 0.10, 0.31, alpha),
		"fill_bottom": Color(0.05, 0.035, 0.14, alpha),
		"metal_light": METAL_GOLD_LIGHT if gold else accent.lerp(Color.WHITE, 0.5),
		"metal_dark": METAL_GOLD_DARK if gold else accent.darkened(0.55),
		"edge_width": 5.0, "cut": 22.0,
		"studs": true, "stud_color": GOLD_LIGHT if gold else accent,
		"gloss": 0.0,
		"inner_glow": Color(accent.r, accent.g, accent.b, 0.32),
		"glow": Color(accent.r, accent.g, accent.b, 0.35), "glow_size": 16.0,
		"shadow": 0.65, "shadow_extent": 14.0, "shadow_dy": 8.0,
		"margin_x": 18.0, "margin_y": 16.0,
	}) as Frame


## Pestana de un TabContainer: la elegida en oro, las demas en cromo apagado.
static func tab_frame(selected: bool, hover: bool = false) -> Frame:
	var props := {
		"edge_width": 2.0, "cut": 8.0, "cut_corners": 3,
		"shadow": 0.0, "outline": Color(0, 0, 0, 0.5),
		"margin_x": 10.0, "margin_y": 8.0,
	}
	if selected:
		props["fill_top"] = Color(1.0, 0.80, 0.32, 0.98)
		props["fill_bottom"] = Color(0.66, 0.34, 0.07, 0.98)
		props["metal_light"] = METAL_GOLD_LIGHT
		props["metal_dark"] = METAL_GOLD_DARK
		props["gloss"] = 0.5
	else:
		var lift := 0.08 if hover else 0.0
		props["fill_top"] = Color(0.18 + lift, 0.13 + lift, 0.36 + lift, 0.95)
		props["fill_bottom"] = Color(0.08, 0.06, 0.20, 0.95)
		props["metal_light"] = METAL_CHROME_LIGHT
		props["metal_dark"] = METAL_CHROME_DARK
		props["gloss"] = 0.15
	return Frame.build(props) as Frame
