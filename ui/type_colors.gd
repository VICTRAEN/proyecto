extends RefCounted

## Color de cada tipo, en un unico sitio.
##
## Lo usan el marco del retrato, el borde de la tarjeta y la barra de vida, para
## que no se desincronicen. Anadir un tipo nuevo es una entrada mas aqui y, si
## debe afectar al dano, otra en TYPE_ADVANTAGE de core/battle_math.gd.

const COLORS := {
	"STR": Color(0.96, 0.34, 0.36, 1.0),
	"AGL": Color(0.36, 0.86, 0.48, 1.0),
	"INT": Color(0.36, 0.62, 1.00, 1.0),
	"TEQ": Color(0.80, 0.44, 0.96, 1.0),
	"PHY": Color(1.00, 0.76, 0.28, 1.0),
}

const DEFAULT := Color(0.64, 0.68, 0.80, 1.0)


static func color_for(type_name: String) -> Color:
	return COLORS.get(type_name, DEFAULT)
