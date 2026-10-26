extends Control

const VI := preload("res://ui/visual_identity.gd")
const PORTRAIT := preload("res://ui/portrait.gd")

## OVERLAY DE DIALOGO. Cuenta las lineas de un dialogo de res://data/dialogues/
## encima de la pantalla que lo abre.
##
## Una linea del JSON trae: speaker (quien habla), portrait (id del personaje para
## el retrato, puede venir vacio), text (lo que dice) y background (escenario).
## Las lineas se piden con DB.dialogue_lines(id), nunca se escriben aqui.
##
## CONTINUAR avanza a la linea siguiente; SKIP cierra el dialogo entero. En los
## dos casos (y tambien si el dialogo no tiene ninguna linea) se emite "finished":
## quien lo abrio decide que hacer despues. El MAPA DE MUNDO abre la batalla ahi.
##
## El retrato lo pinta res://ui/portrait.gd, que dibuja la silueta si el PNG del
## personaje todavia no existe: un dialogo sin arte no se rompe.

signal finished

## Nodos del overlay. Se resuelven POR NOMBRE al arrancar (ver _resolve_nodes), no
## con una ruta escrita a mano: el overlay se instancia dentro de otra pantalla y
## su jerarquia interna puede cambiar sin que el dialogo deba dejar de funcionar.
var speaker_label: Label = null
var portrait_holder: Control = null
var text_label: Label = null
var counter_label: Label = null
var continue_button: Button = null
var skip_button: Button = null
var _panel: PanelContainer = null
var _scrim: PanelContainer = null

var _lines: Array = []
var _index := 0
var _portrait: Control = null
var _closing := false
## De donde viene el dialogo (por ejemplo, el nombre del nivel). Se usa como
## nombre del hablante cuando la linea no trae uno.
var _context := ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_resolve_nodes()
	_apply_identity()
	if continue_button != null:
		continue_button.pressed.connect(_on_continue_pressed)
	if skip_button != null:
		skip_button.pressed.connect(_on_skip_pressed)


## Busca sus propios nodos POR NOMBRE dentro del arbol del overlay. Asi el dialogo
## sigue funcionando aunque cambie la jerarquia interna de la escena, y ninguna
## ruta equivocada puede tumbar la pantalla que lo instancia.
func _resolve_nodes() -> void:
	speaker_label = _node_named("Speaker") as Label
	portrait_holder = _node_named("PortraitHolder") as Control
	text_label = _node_named("Text") as Label
	counter_label = _node_named("Counter") as Label
	continue_button = _node_named("ContinueButton") as Button
	skip_button = _node_named("SkipButton") as Button
	var box := _node_named("Box")
	_panel = box as PanelContainer if box is PanelContainer else null
	var scrim := _node_named("Scrim")
	_scrim = scrim as PanelContainer if scrim is PanelContainer else null


func _node_named(node_name: String) -> Node:
	return find_child(node_name, true, false)


## Aspecto estatico, con los tokens de la identidad visual. Todo va con guarda:
## un nodo que falte deja esa linea sin pintar en vez de romper el dialogo.
func _apply_identity() -> void:
	if speaker_label != null:
		VI.style_title(speaker_label, VI.FONT_SECTION)
	if counter_label != null:
		VI.style_subtitle(counter_label)
	if text_label != null:
		text_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
		text_label.add_theme_color_override("font_color", VI.INK)
	if continue_button != null:
		VI.tint_button(continue_button, VI.GOLD)
		continue_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	if skip_button != null:
		VI.tint_button(skip_button, VI.BLUE)
		skip_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)

	if _panel != null:
		var style := VI.panel(0.97, true, VI.RADIUS_PANEL)
		style.set_border_width_all(3)
		_panel.add_theme_stylebox_override("panel", style)
	if _scrim != null:
		_scrim.add_theme_stylebox_override("panel", VI.panel(0.80, false, 0))

	# Retrato: la MISMA clase que usan la coleccion, el equipo y el combate, para
	# que el encuadre de una cara sea identico en todo el juego.
	if _portrait == null and portrait_holder != null:
		_portrait = PORTRAIT.new()
		_portrait.name = "Portrait"
		_portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait_holder.add_child(_portrait)


## Abre el overlay con un dialogo. Acepta un id (se leen sus lineas con DB) o una
## lista de lineas ya cargada. Una lista vacia NO rompe nada: se emite "finished"
## sin pintar ninguna linea, que es lo que espera quien abre la batalla.
func present(dialogue_id: String, context: String = "") -> void:
	_lines = DB.dialogue_lines(String(dialogue_id)) if not String(dialogue_id).is_empty() else []
	_context = String(context)
	_index = 0
	_closing = false
	visible = true
	if _lines.is_empty():
		# Sin texto no hay nada que contar: se cierra y se avisa igual.
		call_deferred("_finish")
		return
	_render()


## Lista de lineas ya cargada (mismo formato que el JSON del dialogo).
func present_lines(lines: Array, context: String = "") -> void:
	_lines = lines
	_context = String(context)
	_index = 0
	_closing = false
	visible = true
	if _lines.is_empty():
		call_deferred("_finish")
		return
	_render()


func hide_overlay() -> void:
	visible = false
	_lines = []
	_index = 0
	_closing = false


func line_count() -> int:
	return _lines.size()


func current_index() -> int:
	return _index


## Pinta la linea en la que estamos.
func _render() -> void:
	var line = _lines[_index]
	var speaker := ""
	var portrait_id := ""
	var text := ""
	if line is Dictionary:
		speaker = String((line as Dictionary).get("speaker", ""))
		portrait_id = String((line as Dictionary).get("portrait", ""))
		text = String((line as Dictionary).get("text", ""))
	else:
		# Una linea escrita como texto suelto tambien se puede contar.
		text = String(line)
	if speaker.is_empty():
		speaker = _context if not _context.is_empty() else "NARRADOR"
	if speaker_label != null:
		speaker_label.text = speaker
	if text_label != null:
		text_label.text = text
	if counter_label != null:
		counter_label.text = "%d / %d" % [_index + 1, _lines.size()]
	if continue_button != null:
		continue_button.text = "CONTINUAR" if _index + 1 < _lines.size() else "CONTINUAR  >>"
	# Sin id de retrato se pide una silueta vacia: portrait.gd la dibuja.
	if _portrait != null and _portrait.has_method("setup"):
		_portrait.call("setup", portrait_id, VI.GOLD, "short", "", "icon")


func _on_continue_pressed() -> void:
	_index += 1
	if _index >= _lines.size():
		_finish()
		return
	_render()


## SKIP cierra el dialogo entero, sin contar el resto de lineas.
func _on_skip_pressed() -> void:
	_finish()


func _finish() -> void:
	if _closing:
		return
	_closing = true
	visible = false
	_lines = []
	_index = 0
	finished.emit()
