extends HBoxContainer

const CHIP_SCENE := preload("res://ui/order_chip.tscn")
const CombatUnit := preload("res://core/combat_unit.gd")
const VisualIdentity := preload("res://ui/visual_identity.gd")

## Barra de ORDEN DE ATAQUE.
##
## Pinta el orden REAL que calcula BattleManager: recibe la lista de unidades de
## la ronda y el indice de quien actua. No ordena nada por su cuenta, asi que si
## el combate reordena (velocidad, muertes) la barra sigue siendo fiel.
##
## Estados de cada ficha (ver ui/order_chip.gd):
##   next    -> le toca ahora (dorada, late, aviso "AHORA")
##   done    -> ya ha actuado en esta ronda (apagada)
##   waiting -> todavia tiene turno, con su numero de ronda (#2, #3...)
##   dead    -> fuera de combate
##
## Esto es informacion separada del registro de texto: el log cuenta lo que ha
## pasado y esta barra quien va a actuar. La lectura es: quien ataca AHORA, quien
## va DESPUES (los numeros) y quien ya ha pasado (las apagadas).

var _chips: Array = []
var _keys: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 3)


func show_order(units: Array, cursor: int) -> void:
	if not _same_units(units):
		_rebuild(units)
	for i in _chips.size():
		var unit: CombatUnit = units[i]
		# La posicion es la de la ronda (1, 2, 3...): es lo que dice de un golpe
		# quien va despues de quien sin escribir ningun texto mas.
		_chips[i].bind(unit, _state_for(unit, i, cursor), i + 1)


func _state_for(unit: CombatUnit, index: int, cursor: int) -> String:
	if not unit.alive:
		return "dead"
	if index == cursor:
		return "next"
	if index < cursor:
		return "done"
	return "waiting"


## Solo se reconstruye cuando cambia la lista de unidades (ronda nueva o muerte).
## Dentro de la misma ronda se reutilizan las fichas y solo cambian de estado.
func _same_units(units: Array) -> bool:
	if _keys.size() != units.size():
		return false
	for i in units.size():
		if String(_keys[i]) != String(units[i].source_key):
			return false
	return true


func _rebuild(units: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_chips = []
	_keys = []
	for i in units.size():
		if i > 0:
			add_child(_make_arrow())
		var chip = CHIP_SCENE.instantiate()
		add_child(chip)
		_chips.append(chip)
		_keys.append(String(units[i].source_key))


## Flecha entre fichas: refuerza la lectura como secuencia. El color es el dorado
## de la identidad visual, el mismo del turno activo.
func _make_arrow() -> Label:
	var arrow := Label.new()
	arrow.text = ">"
	arrow.add_theme_font_size_override("font_size", 26)
	arrow.add_theme_color_override("font_color", VisualIdentity.GOLD)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return arrow
