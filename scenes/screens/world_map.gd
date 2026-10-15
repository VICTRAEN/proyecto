extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")

## MAPA DE MUNDO. Un mundo de la historia pintado como un mapa: cada nivel en la
## posicion {x,y} (relativa 0..1) que trae su JSON, y una linea de conexion entre
## un nivel y su "next". Las lineas las dibuja res://ui/map_lines.gd por codigo.
##
## Todo sale de los datos y de GameState:
##   GameState.world_status(world_id)      -> los niveles del mundo con su estado
##   GameState.story_level_status(level_id) -> una dificultad por nivel
##   GameState.story_level_unlocked(id) / story_level_cleared(id)
## No hay ninguna rama del tipo "si el mundo es el numero 1": anadir un mundo o un
## nivel es crear/editar su JSON y el mapa los pinta solo.
##
## Estados de un nivel: SUPERADO (verde), DISPONIBLE (azul), BLOQUEADO (apagado) y
## el ACTUAL (el primero abierto sin superar) con marco dorado.
##
## Tocar un nivel abierto abre un PANEL de dificultad dentro de esta pantalla, con
## NORMAL / DIFICIL / EXTREMO, sus rivales y sus recompensas. Una dificultad de
## orden mayor solo se puede jugar si la de orden menor esta superada (el orden es
## el campo "order" del JSON). COMENZAR prepara la batalla y abre el combate: la
## XP y las monedas las paga el combate, esta pantalla no calcula recompensas.

@onready var title_label: Label = $Margin/Main/Title
@onready var subtitle_label: Label = $Margin/Main/Subtitle
@onready var legend: HBoxContainer = $Margin/Main/Legend
@onready var back_button: Button = $Margin/Main/BackButton
@onready var map_area: Control = $MapArea
@onready var panel_scrim: Control = $PanelScrim
@onready var level_panel: PanelContainer = $PanelScrim/Center/LevelPanel
@onready var panel_box: VBoxContainer = $PanelScrim/Center/LevelPanel/PanelBox
@onready var panel_title: Label = $PanelScrim/Center/LevelPanel/PanelBox/PanelTitle
@onready var panel_info: Label = $PanelScrim/Center/LevelPanel/PanelBox/PanelInfo
@onready var difficulty_list: VBoxContainer = $PanelScrim/Center/LevelPanel/PanelBox/DifficultyList
@onready var panel_feedback: Label = $PanelScrim/Center/LevelPanel/PanelBox/PanelFeedback
@onready var start_button: Button = $PanelScrim/Center/LevelPanel/PanelBox/PanelButtons/StartButton
@onready var close_button: Button = $PanelScrim/Center/LevelPanel/PanelBox/PanelButtons/CloseButton
@onready var dialogue_overlay: Control = $DialogueOverlay

var _world_id := ""
var _levels: Array = []
## Filas del panel: id de dificultad -> { state, accent, button }.
var _difficulty_rows: Dictionary = {}
var _selected_level_id := ""
var _selected_difficulty_id := ""


func _ready() -> void:
	_apply_identity()
	back_button.pressed.connect(_back)
	close_button.pressed.connect(_close_panel)
	start_button.pressed.connect(_on_start_pressed)
	dialogue_overlay.connect("finished", _on_dialogue_finished)
	resized.connect(_on_resized)


## Aspecto estatico. Los colores y los tamanos salen de la identidad visual.
func _apply_identity() -> void:
	VI.style_title(title_label, VI.FONT_BIG)
	VI.style_subtitle(subtitle_label)
	VI.style_title(panel_title, VI.FONT_SECTION)
	VI.style_subtitle(panel_info)
	VI.style_title(panel_feedback, VI.FONT_SMALL)
	VI.tint_button(back_button, VI.BLUE)
	VI.tint_button(close_button, VI.BLUE)
	VI.tint_button(start_button, VI.GOLD)
	back_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	close_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	start_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	var panel_style: StyleBoxFlat = VI.panel(0.97, true, VI.RADIUS_PANEL)
	panel_style.set_border_width_all(3)
	level_panel.add_theme_stylebox_override("panel", panel_style)
	var scrim_style: StyleBoxFlat = VI.panel(0.72, false, 0)
	panel_scrim.add_theme_stylebox_override("panel", scrim_style)
	_build_legend()


func _build_legend() -> void:
	for entry in [
		{ "text": "SUPERADO", "color": VI.GREEN },
		{ "text": "DISPONIBLE", "color": VI.BLUE },
		{ "text": "BLOQUEADO", "color": VI.INK_DIM },
		{ "text": "ACTUAL", "color": VI.GOLD },
	]:
		var label := Label.new()
		label.text = String(entry["text"])
		label.add_theme_font_size_override("font_size", VI.FONT_TINY)
		label.add_theme_color_override("font_color", entry["color"])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		legend.add_child(label)


## El mapa se repinta cada vez que App lo muestra: el combate puede haber
## desbloqueado el nivel siguiente.
func refresh() -> void:
	_close_panel()
	dialogue_overlay.call("hide_overlay")
	_world_id = _resolve_world()
	var status: Dictionary = {}
	if not _world_id.is_empty():
		status = GameState.world_status(_world_id)
	_fill_header(status)
	_build_levels(status)


## El mundo que se pinta: el que el jugador dejo elegido en HISTORIA
## (GameState.current_world_id). Si esta vacio o no esta desbloqueado se usa el
## primer mundo abierto, y se apunta para que volver a entrar devuelva aqui.
func _resolve_world() -> String:
	var chosen := String(GameState.current_world_id)
	if not chosen.is_empty() and GameState.world_unlocked(chosen):
		return chosen
	var first_open := ""
	for world in DB.all_worlds():
		if not (world is Dictionary):
			continue
		var id := String((world as Dictionary).get("id", ""))
		if GameState.world_unlocked(id):
			first_open = id
			break
	if chosen != first_open:
		if not first_open.is_empty():
			GameState.select_world(first_open)
		return first_open
	return chosen


func _fill_header(status: Dictionary) -> void:
	if status.is_empty():
		subtitle_label.text = "No hay ningun mundo disponible."
		return
	var genre := String(DB.get_world(String(status.get("id", ""))).get("genre", ""))
	var description := String(status.get("description", ""))
	var line := String(status.get("name", ""))
	if not genre.is_empty():
		line = "%s - %s" % [line, genre]
	subtitle_label.text = "%s\nSuperados %d de %d niveles" % [
		line,
		int(status.get("levels_completed", 0)),
		int(status.get("level_count", 0)),
	]
	if not description.is_empty():
		subtitle_label.tooltip_text = description


## Nodos de nivel: uno por nivel del mundo, con su posicion de los datos.
func _build_levels(status: Dictionary) -> void:
	# Se vacia el mapa antes de reconstruirlo, para que el control de dibujo no
	# se quede con fichas ya liberadas mientras se crean las nuevas.
	map_area.call("set_entries", [])
	for entry in _levels:
		var old: Control = entry.get("button")
		if old != null and is_instance_valid(old):
			map_area.remove_child(old)
			old.queue_free()
	_levels.clear()

	var levels: Array = status.get("levels", [])
	var state_by_id: Dictionary = {}
	for level in levels:
		if level is Dictionary:
			state_by_id[String((level as Dictionary).get("id", ""))] = level
	var current_id := _current_level_id(levels)
	for index in levels.size():
		var level = levels[index]
		if not (level is Dictionary):
			continue
		var level_id := String((level as Dictionary).get("id", ""))
		var unlocked := bool((level as Dictionary).get("unlocked", false))
		var cleared := bool((level as Dictionary).get("cleared", false))
		var is_current := level_id == current_id
		var accent := _level_accent(unlocked, cleared, is_current)
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = not unlocked
		button.text = str(index + 1) if unlocked else "?"
		button.add_theme_color_override("font_color", accent)
		button.add_theme_stylebox_override("normal", VI.card(accent, is_current, "", unlocked))
		button.add_theme_stylebox_override("hover", VI.card(accent, true, "", true))
		button.add_theme_stylebox_override("pressed", VI.card(accent, true, "", true))
		button.add_theme_stylebox_override("disabled", VI.card(VI.INK_DIM, false, "", false))
		var state_text := _level_state_text(unlocked, cleared, is_current)
		button.tooltip_text = "%s - %s" % [String((level as Dictionary).get("name", level_id)), state_text]
		if unlocked:
			button.pressed.connect(_on_level_pressed.bind(level_id))
		map_area.add_child(button)
		# La ficha lleva su posicion de los datos, su destino y el color de ese
		# destino: el control del mapa coloca las fichas y dibuja las lineas.
		_levels.append({
			"id": level_id,
			"position": (level as Dictionary).get("position", {}),
			"next": String((level as Dictionary).get("next", "")),
			"color": _link_color(String((level as Dictionary).get("next", "")), state_by_id),
			"button": button,
		})
	map_area.call("set_entries", _levels)


## El nivel ACTUAL del mundo: el primero abierto que todavia no se ha superado.
## Si ya esta todo superado, el ultimo superado.
func _current_level_id(levels: Array) -> String:
	var last_cleared := ""
	for level in levels:
		if not (level is Dictionary):
			continue
		var id := String((level as Dictionary).get("id", ""))
		if not bool((level as Dictionary).get("cleared", false)):
			if bool((level as Dictionary).get("unlocked", false)):
				return id
			continue
		last_cleared = id
	return last_cleared


func _level_accent(unlocked: bool, cleared: bool, is_current: bool) -> Color:
	if is_current:
		return VI.GOLD
	if not unlocked:
		return VI.INK_DIM
	if cleared:
		return VI.GREEN
	return VI.BLUE


func _level_state_text(unlocked: bool, cleared: bool, is_current: bool) -> String:
	if is_current:
		return "AQUI - DISPONIBLE"
	if not unlocked:
		return "BLOQUEADO"
	if cleared:
		return "SUPERADO"
	return "DISPONIBLE"


## El color de un tramo es el estado del nivel AL QUE LLEVA, leido del estado que
## GameState da para ese nivel del mundo.
func _link_color(target_id: String, state_by_id: Dictionary) -> Color:
	if target_id.is_empty() or not state_by_id.has(target_id):
		return VI.INK_DIM
	var target: Dictionary = state_by_id[target_id]
	if not bool(target.get("unlocked", false)):
		return VI.INK_DIM
	if bool(target.get("cleared", false)):
		return VI.GREEN
	return VI.BLUE


func _on_resized() -> void:
	level_panel.custom_minimum_size = Vector2(clampf(size.x * 0.86, 320.0, 900.0), 0.0)
	# El mapa se recoloca con su propio tamano nuevo.
	map_area.call("layout_nodes")


## --- Panel de dificultad -----------------------------------------------------

func _on_level_pressed(level_id: String) -> void:
	var status: Dictionary = GameState.story_level_status(String(level_id))
	if status.is_empty() or not bool(status.get("unlocked", false)):
		return
	_selected_level_id = String(level_id)
	_selected_difficulty_id = ""
	panel_title.text = String(status.get("name", _selected_level_id))
	panel_info.text = "Superados %d de %d niveles del mundo. Elige la dificultad." % [
		int(status.get("difficulties_completed", 0)),
		int((status.get("difficulties", []) as Array).size()),
	]
	panel_feedback.text = ""
	_build_difficulties(status)
	_refresh_difficulty_styles()
	_refresh_start_button()
	panel_scrim.visible = true


func _close_panel() -> void:
	panel_scrim.visible = false
	_selected_difficulty_id = ""
	panel_feedback.text = ""


func _build_difficulties(status: Dictionary) -> void:
	for child in difficulty_list.get_children():
		difficulty_list.remove_child(child)
		child.queue_free()
	_difficulty_rows.clear()
	var previous_cleared := true
	for difficulty in status.get("difficulties", []):
		if not (difficulty is Dictionary):
			continue
		var difficulty_id := String((difficulty as Dictionary).get("id", ""))
		var state := "locked"
		if bool((difficulty as Dictionary).get("completed", false)):
			state = "completed"
		elif previous_cleared:
			state = "available"
		previous_cleared = state == "completed"
		var accent := _difficulty_accent(state)
		var button := Button.new()
		button.text = "%s\n%s\n+%d XP   +%d monedas\n%s" % [
			String((difficulty as Dictionary).get("name", difficulty_id.to_upper())),
			_enemies_text((difficulty as Dictionary).get("enemies", [])),
			int((difficulty as Dictionary).get("xp_reward", 0)),
			int((difficulty as Dictionary).get("coin_reward", 0)),
			_difficulty_state_text(state),
		]
		button.custom_minimum_size = Vector2(0.0, VI.TOUCH * 1.4)
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = state == "locked"
		button.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		button.add_theme_color_override("font_color", accent)
		difficulty_list.add_child(button)
		if state != "locked":
			button.pressed.connect(_on_difficulty_pressed.bind(difficulty_id))
		_difficulty_rows[difficulty_id] = {
			"state": state,
			"accent": accent,
			"button": button,
		}


func _on_difficulty_pressed(difficulty_id: String) -> void:
	if not _difficulty_rows.has(String(difficulty_id)):
		return
	_selected_difficulty_id = String(difficulty_id)
	panel_feedback.text = ""
	_refresh_difficulty_styles()
	_refresh_start_button()


func _refresh_difficulty_styles() -> void:
	for key in _difficulty_rows.keys():
		var row: Dictionary = _difficulty_rows[key]
		var button: Button = row["button"]
		var accent: Color = row["accent"]
		var selected := String(key) == _selected_difficulty_id
		var available := String(row["state"]) != "locked"
		button.add_theme_stylebox_override("normal", VI.card(accent, selected, "", available))
		button.add_theme_stylebox_override("hover", VI.card(accent, true, "", available))
		button.add_theme_stylebox_override("pressed", VI.card(accent, true, "", available))
		button.add_theme_stylebox_override("disabled", VI.card(VI.INK_DIM, false, "", false))


func _refresh_start_button() -> void:
	var state := String(_difficulty_rows.get(_selected_difficulty_id, {}).get("state", "locked"))
	start_button.disabled = state == "locked"


func _difficulty_accent(state: String) -> Color:
	if state == "completed":
		return VI.GREEN
	if state == "available":
		return VI.BLUE
	return VI.INK_DIM


func _difficulty_state_text(state: String) -> String:
	if state == "completed":
		return "COMPLETADO"
	if state == "available":
		return "DISPONIBLE"
	return "BLOQUEADA"


## Los rivales de una dificultad, leidos de sus datos. La pantalla NO tiene
## ninguna lista de enemigos: los pone GameState.prepare_battle.
func _enemies_text(enemies: Array) -> String:
	var names := PackedStringArray()
	for raw_id in enemies:
		var enemy_id := String(raw_id)
		var enemy: Dictionary = DB.enemies.get(enemy_id, {})
		names.append(String(enemy.get("name", enemy_id)))
	if names.is_empty():
		return "Sin rivales"
	return ", ".join(names)


## --- Arrancar la batalla -----------------------------------------------------

## COMENZAR. Si el nivel tiene dialogo y todavia no se ha superado, primero se
## cuenta la historia y al terminar (o al saltar) se abre el combate.
func _on_start_pressed() -> void:
	if _selected_level_id.is_empty() or _selected_difficulty_id.is_empty():
		return
	var state := String(_difficulty_rows.get(_selected_difficulty_id, {}).get("state", "locked"))
	if state == "locked":
		panel_feedback.text = "Supera antes la dificultad anterior de este nivel."
		return
	var status: Dictionary = GameState.story_level_status(_selected_level_id)
	var dialogue_id := String(status.get("dialogue", ""))
	if not dialogue_id.is_empty() and not bool(status.get("cleared", false)):
		panel_scrim.visible = false
		dialogue_overlay.call("present", dialogue_id, String(status.get("name", "")))
		return
	_begin_battle()


## El dialogo ha terminado (o el jugador lo ha saltado): ahora si, al combate.
func _on_dialogue_finished() -> void:
	dialogue_overlay.visible = false
	_begin_battle()


## Prepara la batalla de historia y abre el combate. prepare_battle es el unico
## sitio que fija los enemigos, y quien paga la XP y las monedas es el combate.
func _begin_battle() -> void:
	if _selected_level_id.is_empty() or _selected_difficulty_id.is_empty():
		return
	var prepared: bool = GameState.prepare_battle(GameState.BATTLE_STORY, {
		"level": _selected_level_id,
		"difficulty": _selected_difficulty_id,
	})
	if not prepared:
		panel_scrim.visible = true
		panel_feedback.text = "No se ha podido preparar esta batalla."
		return
	var app := NAV.app_of(self)
	if app != null and app.has_method("open_battle"):
		app.call("open_battle")


func _back() -> void:
	if panel_scrim.visible:
		_close_panel()
		return
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")
