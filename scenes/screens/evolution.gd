extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const ROSTER_CARD := preload("res://ui/roster_card.tscn")
const FichaTabs := preload("res://ui/ficha_tabs.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")
const EvolutionFx := preload("res://ui/evolution_fx.gd")

## EVOLUCION: elegir un personaje y evolucionarlo cuando de verdad cumpla TODOS
## los requisitos.
##
## Esta pantalla NO calcula ninguna regla. Pregunta a GameState:
##   can_evolve(id)         -> subir de rareza sin cambiar de personaje (SSR -> UR)
##   can_special_evolve(id) -> cambiar de personaje (Sakuta + Mai -> Sakuta -> LR)
## y esos dos informes traen ya el progreso REAL de cada requisito (nivel, objetos,
## monedas y veces que se ha completado un evento).
##
## Que personajes se pueden elegir tambien es un dato: sale de las rutas
## declaradas (res://data/evolutions/special.json y el bloque "evolution" de cada
## personaje). Anadir una evolucion nueva es anadir datos, no tocar esta pantalla.

@onready var title_label: Label = $Margin/Main/Title
@onready var subtitle_label: Label = $Margin/Main/Subtitle
@onready var selector_title: Label = $Margin/Main/Scroll/Content/SelectorTitle
@onready var grid: GridContainer = $Margin/Main/Scroll/Content/Grid
@onready var detail_box: VBoxContainer = $Margin/Main/Scroll/Content/DetailBox
@onready var back_button: Button = $Margin/Main/BackButton

## Personaje cuya evolucion se esta mirando.
var _selected_id := ""
## Personaje que se estaba evolucionando (para el arte de ANTES en la transicion).
var _last_from_id := ""


func _ready() -> void:
	_apply_identity()
	back_button.pressed.connect(_back)
	_make_selector_strip()


## El selector es una TIRA horizontal de una fila (no una lista vertical): asi el
## detalle ANTES > MATERIAL > DESPUES se ve entero sin tener que bajar pasando por
## decenas de personajes.
func _make_selector_strip() -> void:
	var content: VBoxContainer = grid.get_parent()
	var strip := ScrollContainer.new()
	strip.name = "SelectorStrip"
	strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip.custom_minimum_size = Vector2(0, 150)
	var index := grid.get_index()
	content.remove_child(grid)
	content.add_child(strip)
	content.move_child(strip, index)
	strip.add_child(grid)
	grid.columns = 999
	grid.size_flags_horizontal = Control.SIZE_FILL


## Aspecto estatico, con los tokens de la identidad visual.
func _apply_identity() -> void:
	VI.style_title(title_label, VI.FONT_BIG)
	VI.style_subtitle(subtitle_label)
	VI.style_title(selector_title, VI.FONT_SMALL)
	VI.tint_button(back_button, VI.BLUE)
	back_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)


func refresh() -> void:
	if _selected_id.is_empty() or not GameState.is_owned(_selected_id):
		_selected_id = _default_id()
	_build_selector()
	_build_detail()


## --- Seleccion ---------------------------------------------------------------

## Primer personaje que HOY puede evolucionar; si ninguno puede, el primero que
## tenga una ruta. Asi la pantalla siempre abre en algo util.
func _default_id() -> String:
	var candidates := eligible_ids()
	var first := ""
	for id in candidates:
		if first.is_empty():
			first = String(id)
		var check := _check_of(String(id))
		if bool(check.get("ok", false)):
			return String(id)
	return first


## Personajes del jugador que tienen alguna ruta de evolucion declarada.
func eligible_ids() -> Array:
	var out: Array = []
	for raw_id in GameState.roster:
		var id := String(raw_id)
		if id.is_empty():
			continue
		if _route_of(id).is_empty():
			continue
		out.append(id)
	return out


## La ruta de evolucion de un personaje, ya resuelta en datos:
##   { kind: "special"|"normal", check: {...}, to_name, to_form }
## Devuelve {} si ese personaje no tiene ninguna.
func _route_of(id: String) -> Dictionary:
	var key := String(id)
	if key.is_empty() or DB.get_character(key).is_empty():
		return {}
	if not GameState.is_owned(key):
		return {}
	var special: Dictionary = GameState.can_special_evolve(key)
	if not special.is_empty() and not String(special.get("to", "")).is_empty():
		return {
			"kind": "special",
			"check": special,
			"to_name": GameState.display_name(String(special.get("to", ""))),
			"to_form": String(special.get("to_rarity", "")),
		}
	var normal: Dictionary = GameState.can_evolve(key)
	if not normal.is_empty() and not String(normal.get("to", "")).is_empty():
		return {
			"kind": "normal",
			"check": normal,
			"to_name": GameState.display_name(key),
			"to_form": String(normal.get("to", "")),
		}
	return {}


func _check_of(id: String) -> Dictionary:
	var route := _route_of(id)
	if route.is_empty():
		return {}
	return route["check"]


func _build_selector() -> void:
	_clear(grid)
	var ids := eligible_ids()
	if ids.is_empty():
		selector_title.text = "NO HAY PERSONAJES EVOLUCIONABLES"
		var empty := Label.new()
		empty.text = "Ningun personaje de tu coleccion tiene una forma superior declarada."
		empty.add_theme_font_size_override("font_size", VI.FONT_BODY)
		empty.add_theme_color_override("font_color", VI.INK_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		grid.add_child(empty)
		return
	selector_title.text = "ELIGE UN PERSONAJE"
	for raw_id in ids:
		var id := String(raw_id)
		var check := _check_of(id)
		var ready := bool(check.get("ok", false))
		var extra := "LISTO PARA EVOLUCIONAR" if ready else "FALTAN REQUISITOS"
		var card = ROSTER_CARD.instantiate()
		grid.add_child(card)
		card.bind(GameState.character_data(id), id == _selected_id, extra, true)
		card.custom_minimum_size = Vector2(380, 0)
		card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		card.pressed.connect(_on_card_pressed)


func _on_card_pressed(data: Dictionary) -> void:
	if data.is_empty():
		return
	_selected_id = String(data.get("id", _selected_id))
	refresh()


## --- Detalle -----------------------------------------------------------------

func _build_detail() -> void:
	_clear(detail_box)
	if _selected_id.is_empty():
		subtitle_label.text = "Aqui veras los requisitos de la evolucion, uno por uno."
		return
	var route := _route_of(_selected_id)
	if route.is_empty():
		subtitle_label.text = ""
		return
	var check: Dictionary = route["check"]
	var ready := bool(check.get("ok", false))
	subtitle_label.text = "Los requisitos salen del estado real de tu partida."
	var from_form := GameState.rarity_of(_selected_id)
	var to_form := String(route["to_form"])
	var target_id := String(check.get("to", _selected_id)) if String(route["kind"]) == "special" else _selected_id

	# Cabecera: el camino completo SSR > UR > LR con la etapa actual marcada.
	detail_box.add_child(_rarity_path(from_form, to_form))

	# ANTES  >  MATERIAL  >  DESPUES, en una sola fila.
	var row := HBoxContainer.new()
	row.name = "EvolutionRow"
	row.add_theme_constant_override("separation", 10)
	detail_box.add_child(row)
	row.add_child(_form_panel("ANTES", _selected_id, from_form, GameState.display_name(_selected_id), "Nv. %d" % GameState.level_of(_selected_id)))
	row.add_child(_materials_panel(check))
	var after_level := "Nv. %d" % GameState.level_of(_selected_id)
	row.add_child(_form_panel("DESPUES", target_id, to_form, String(route["to_name"]), after_level))

	if String(route["kind"]) == "special":
		detail_box.add_child(FichaTabs.note("Cambia de personaje: es una forma nueva, no solo una rareza mas alta."))

	if ready:
		var ready_label := Label.new()
		ready_label.text = "LISTO PARA EVOLUCIONAR"
		ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ready_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
		ready_label.add_theme_color_override("font_color", VI.GREEN)
		detail_box.add_child(ready_label)
	else:
		var reason := String(check.get("reason", ""))
		if not reason.is_empty():
			detail_box.add_child(FichaTabs.note(reason))

	var button := Button.new()
	button.name = "EvolveButton"
	button.text = "EVOLUCIONAR" if ready else "EVOLUCIONAR  -  BLOQUEADO"
	button.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", VI.FONT_BODY)
	button.disabled = not ready
	VI.tint_button(button, VI.GOLD if ready else VI.INK_DIM)
	if ready:
		button.pressed.connect(_on_evolve_pressed)
	detail_box.add_child(button)


## SSR  >  UR  >  LR con la forma actual y la de destino resaltadas.
func _rarity_path(from_form: String, to_form: String) -> Control:
	var box := HBoxContainer.new()
	box.name = "RarityPath"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	var steps: Array = ["SSR", "UR", "LR"]
	for i in steps.size():
		var form := String(steps[i])
		var label := Label.new()
		label.text = form
		label.add_theme_font_size_override("font_size", VI.FONT_SECTION)
		var lit := form == from_form or form == to_form
		label.add_theme_color_override("font_color", VI.rarity_color(form) if lit else VI.INK_DIM)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 6 if lit else 0)
		box.add_child(label)
		if i < steps.size() - 1:
			var arrow := Label.new()
			arrow.text = ">"
			arrow.add_theme_color_override("font_color", VI.INK_DIM)
			box.add_child(arrow)
	return box


## Tarjeta de una forma (ANTES o DESPUES): arte grande con el marco de su rareza,
## nombre y nivel. Si la forma aun no tiene PNG propio se ve el arte base o la silueta.
func _form_panel(title: String, id: String, form_name: String, display: String, level_text: String) -> Control:
	var data := GameState.character_data(id)
	var tint: Color = TypeColors.color_for(String(data.get("type", "STR")))
	var panel := PanelContainer.new()
	panel.name = title
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.add_theme_stylebox_override("panel", VI.rarity_card(form_name, title == "DESPUES", title == "DESPUES"))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", VI.FONT_TINY)
	head.add_theme_color_override("font_color", VI.INK_DIM)
	v.add_child(head)
	var art := Portrait.new()
	art.custom_minimum_size = Vector2(0.0, 250.0)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	art.setup(id, tint, String(data.get("portrait_style", "short")), Portrait.art_path_from(data, "front"), "front", form_name)
	var badge := VI.rarity_badge(form_name, VI.FONT_BODY)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(badge)
	var name_label := Label.new()
	name_label.text = display
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	name_label.add_theme_color_override("font_color", tint)
	v.add_child(name_label)
	var level := Label.new()
	level.text = level_text
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level.add_theme_font_size_override("font_size", VI.FONT_TINY)
	level.add_theme_color_override("font_color", VI.INK_SOFT)
	v.add_child(level)
	return panel


## Panel central: nivel, materiales (cantidad que tienes / que pide, con barra) y coste.
func _materials_panel(check: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "MATERIAL"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", VI.panel(0.92))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := Label.new()
	head.text = "MATERIAL"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", VI.FONT_TINY)
	head.add_theme_color_override("font_color", VI.INK_DIM)
	v.add_child(head)
	_add_requirement_to(v, "Nivel", int(check.get("level", 0)), int(check.get("level_required", 0)))
	for raw_cost in check.get("item_cost", []):
		if not (raw_cost is Dictionary):
			continue
		var cost: Dictionary = raw_cost
		var item_id := String(cost.get("item", ""))
		_add_requirement_to(v, GameState.item_display_name(item_id), GameState.item_count(item_id), int(cost.get("amount", 1)))
	var coin_cost := int(check.get("coin_cost", 0))
	if coin_cost > 0:
		_add_requirement_to(v, "Monedas", int(check.get("coins", 0)), coin_cost)
	else:
		var free := Label.new()
		free.text = "Coste: 0 monedas"
		free.add_theme_font_size_override("font_size", VI.FONT_TINY)
		free.add_theme_color_override("font_color", VI.INK_SOFT)
		v.add_child(free)
	var clears_required := int(check.get("event_clears_required", 0))
	if clears_required > 0:
		var event_id := String(check.get("event_id", ""))
		_add_requirement_to(v, String(DB.get_event(event_id).get("name", event_id)), int(check.get("event_clears", 0)), clears_required)
	return panel


## Un requisito con barra: "Uniforme de conejita  7 / 25". Verde si se cumple.
func _add_requirement_to(box: VBoxContainer, label_text: String, have: int, need: int) -> void:
	if need <= 0:
		return
	var ok := have >= need
	var label := Label.new()
	label.text = "%s   %d / %d" % [label_text, have, need]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", VI.FONT_TINY)
	label.add_theme_color_override("font_color", VI.GREEN if ok else VI.RED)
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0.0, 14.0)
	bar.max_value = float(need)
	bar.value = float(mini(have, need))
	bar.show_percentage = false
	bar.modulate = VI.GREEN if ok else VI.RED
	box.add_child(bar)


## Una linea de requisito. Si el minimo es 0 no se pinta (esa ruta no lo pide).
func _add_requirement(label_text: String, have: int, need: int, as_percent: bool) -> void:
	if need <= 0:
		return
	var ok := have >= need
	var row := Label.new()
	row.text = "%s:   %d / %d   %s" % [label_text, have, need, "OK" if ok else "FALTA"]
	row.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	row.add_theme_color_override("font_color", VI.GREEN if ok else VI.RED)
	row.autowrap_mode = TextServer.AUTOWRAP_WORD
	detail_box.add_child(row)


## --- Evolucionar -------------------------------------------------------------

## Evoluciona de verdad. Quien cambia el personaje es GameState (evolve /
## evolve_special), que vuelve a comprobar los requisitos por su cuenta: la
## pantalla no puede saltarselos aunque el boton estuviera mal pintado.
func _on_evolve_pressed() -> void:
	if _selected_id.is_empty():
		return
	var route := _route_of(_selected_id)
	if route.is_empty():
		return
	var check: Dictionary = route["check"]
	if not bool(check.get("ok", false)):
		return
	var id := _selected_id
	_last_from_id = id
	var before_form := GameState.rarity_of(id)
	var is_special := String(route["kind"]) == "special"
	var report: Dictionary = GameState.evolve_special(id) if is_special else GameState.evolve(id)
	if report.is_empty():
		subtitle_label.text = "No se ha podido evolucionar."
		refresh()
		return
	# El personaje nuevo (si cambia de personaje) pasa a ser el elegido, para que
	# el jugador pueda encadenar la siguiente evolucion sin buscarlo otra vez.
	_selected_id = String(report.get("id", id))
	refresh()
	show_completed(report, before_form)


## Aviso de evolucion completada. La transicion la pinta EvolutionFx; el texto se
## queda debajo para que el resultado siga leyendose cuando el efecto termina.
func show_completed(report: Dictionary, before_form: String) -> void:
	var after_form := String(report.get("to_rarity", ""))
	var name_text := String(report.get("name", ""))
	var banner := Label.new()
	banner.text = "EVOLUCION COMPLETADA\n%s   >   %s\n%s" % [before_form, after_form, name_text]
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", VI.FONT_BODY)
	banner.add_theme_color_override("font_color", VI.GOLD)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	banner.add_theme_constant_override("outline_size", 6)
	detail_box.add_child(banner)
	subtitle_label.text = "Evolucion aplicada y guardada."
	EvolutionFx.play(self, before_form, after_form, name_text, String(report.get("from", _last_from_id)), String(report.get("id", _selected_id)))


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
