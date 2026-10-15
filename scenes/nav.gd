extends Node

## Navegacion entre pantallas FUERA del combate.
##
## Es la pila de pantallas del juego (menu -> coleccion -> personaje...). Guarda
## SOLO el nombre de cada pantalla, no el nodo: la pila sobrevive aunque una
## pantalla se recargue, y volver atras es devolver el ultimo nombre.
##
## El combate no entra en esta pila: se abre aparte, encima, porque al terminar
## la batalla se vuelve a la pantalla anterior tal como estaba.

signal changed(screen: String)

const MAIN_MENU := "main_menu"

var _stack: Array = []


func initial(screen: String) -> void:
	_stack = [screen]
	changed.emit(current())


func push(screen: String) -> void:
	_stack.append(screen)
	changed.emit(current())


## Vuelve a la pantalla anterior. Devuelve false si ya estamos en la primera.
func pop() -> bool:
	if _stack.size() <= 1:
		return false
	_stack.pop_back()
	changed.emit(current())
	return true


func replace(screen: String) -> void:
	if _stack.is_empty():
		_stack = [screen]
	else:
		_stack[_stack.size() - 1] = screen
	changed.emit(current())


func current() -> String:
	if _stack.is_empty():
		return MAIN_MENU
	return String(_stack[_stack.size() - 1])


func depth() -> int:
	return _stack.size()


## El App es el ancestro que sabe abrir pantallas y combate. Se busca subiendo
## desde la pantalla, para que ninguna pantalla tenga que saber donde cuelga.
static func app_of(node: Node) -> Node:
	var current := node.get_parent()
	while current != null:
		if current.has_method("open_screen"):
			return current
		current = current.get_parent()
	return null
