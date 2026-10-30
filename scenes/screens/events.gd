extends Control

const NAV := preload("res://scenes/nav.gd")
const SavedTeamsPanel := preload("res://ui/saved_teams_panel.gd")
const VI := preload("res://ui/visual_identity.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")

## Stage elegido por evento (id de evento -> id de stage). Solo es de pantalla.
var _selected_stage: Dictionary = {}

## EVENTOS: los eventos de tiempo limitado con sus stages.
##
## La lista sale de DB.all_events() y el estado de cada uno de
## GameState.event_status(id): una tarjeta por evento y, dentro, una tarjeta por
## stage con sus rivales, recompensas, objetos que suelta y requisitos. Anadir un
## evento es crear su JSON; esta pantalla no cambia y no hay ninguna rama del tipo
## "si el evento es el de Sakuta".
##
## QUIEN MANDA ES GameState:
##   - event_party_ready(event, stage, party) dice si el equipo puede entrar (un
##     stage puede pedir una unidad concreta) y devuelve el motivo si no.
##   - prepare_battle(BATTLE_EVENT, ...) fija los enemigos del combate.
##   - El combate paga XP, monedas y objetos por su cuenta (solo al ganar): aqui
##     no se calcula ninguna recompensa.
##   - claim_event_character(event) entrega la unidad del evento UNA sola vez.
##
## Los colores y los tamanos salen de res://ui/visual_identity.gd.

@onready var title_label: Label = $Margin/Main/Title
@onready var subtitle_label: Label = $Margin/Main/Subtitle
@onready var stock_label: Label = $Margin/Main/Stock
@onready var list: VBoxContainer = $Margin/Main/Scroll/List
@onready var feedback: Label = $Margin/Main/Feedback
@onready var back_button: Button = $Margin/Main/BackButton


func _ready() -> void:
	_apply_identity()
	back_button.pressed.connect(_back)


## Aspecto estatico, con los tokens de la identidad visual.
func _apply_identity() -> void:
	VI.screen_title(title_label, VI.MAGENTA)
	VI.style_subtitle(subtitle_label)
	VI.style_subtitle(stock_label)
	VI.style_title(feedback, VI.FONT_BODY)
	VI.tint_button(back_button, VI.BLUE)
	back_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)


## App llama a refresh() cada vez que muestra la pantalla: el evento puede haber
## avanzado en el combate y los estados tienen que reflejarlo.
func refresh() -> void:
	feedback.text = ""
	_build_stock()
	_build_list()


## Objetos que reparten los eventos, con lo que el jugador tiene de cada uno. Es
## lo que hace falta para saber si llega a los 25 uniformes, y sale de los datos:
## los ids salen de los "drops" de cada JSON y el nombre del catalogo de objetos.
func _build_stock() -> void:
	var totals: Dictionary = {}
	for event in DB.all_events():
		for stage in DB.event_stages(String((event as Dictionary).get("id", ""))):
			if not (stage is Dictionary):
				continue
			for drop in (stage as Dictionary).get("drops", []):
				if not (drop is Dictionary):
					continue
				var item_id := String((drop as Dictionary).get("item", ""))
				if not item_id.is_empty():
					totals[item_id] = GameState.item_count(item_id)
	if totals.is_empty():
		stock_label.text = ""
		return
	var parts := PackedStringArray()
	for item_id in totals.keys():
		parts.append("%s x%d" % [GameState.item_display_name(String(item_id)), int(totals[item_id])])
	stock_label.text = "Tus objetos de evento:  %s" % "   ".join(parts)


func _build_list() -> void:
	_clear(list)
	var events: Array = DB.all_events()
	subtitle_label.text = "Cada evento se puede repetir. La primera victoria paga; despues suelta sus objetos."
	if events.is_empty():
		var note := Label.new()
		note.text = "Todavia no hay eventos disponibles."
		note.add_theme_font_size_override("font_size", VI.FONT_BODY)
		note.add_theme_color_override("font_color", VI.INK_DIM)
		list.add_child(note)
		return
	for event in events:
		if not (event is Dictionary):
			continue
		var event_id := String((event as Dictionary).get("id", ""))
		list.add_child(_make_event_card(GameState.event_status(event_id)))


## EVENTO como CARTEL: banner con el personaje de la recompensa a un lado, chips
## con progreso y dificultad, y debajo un SELECTOR de stages (fichas 1-2-3) con el
## detalle del stage elegido. Una sola tarjeta de stage a la vez, no tres apiladas.
func _make_event_card(status: Dictionary) -> Control:
	var completed := bool(status.get("completed", false))
	var accent: Color = VI.GREEN if completed else VI.GOLD
	var event_id := String(status.get("id", ""))

	var card := PanelContainer.new()
	var banner_style := VI.panel(0.96, true, VI.RADIUS_PANEL)
	banner_style.border_color = Color(accent.r, accent.g, accent.b, 0.9)
	banner_style.set_border_width_all(3)
	banner_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.3)
	banner_style.shadow_size = 14
	card.add_theme_stylebox_override("panel", banner_style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)

	# --- Cartel: texto a la izquierda, arte a la derecha.
	var poster := HBoxContainer.new()
	poster.add_theme_constant_override("separation", 8)
	box.add_child(poster)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	poster.add_child(left)
	var tag := Label.new()
	tag.text = "EVENTO  -  COMPLETADO" if completed else "EVENTO LIMITADO"
	tag.add_theme_font_size_override("font_size", VI.FONT_TINY)
	tag.add_theme_color_override("font_color", VI.VIOLET)
	left.add_child(tag)
	var name_label := Label.new()
	name_label.text = String(status.get("name", ""))
	name_label.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	name_label.add_theme_color_override("font_color", accent)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	left.add_child(name_label)
	var description := Label.new()
	description.text = String(status.get("description", ""))
	description.add_theme_font_size_override("font_size", VI.FONT_TINY)
	description.add_theme_color_override("font_color", VI.INK_SOFT)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD
	left.add_child(description)
	# v14: historia corta y premio exclusivo del evento (ambos opcionales, del JSON).
	var story = status.get("story", [])
	if story is Array:
		for line in story:
			var story_line := Label.new()
			story_line.text = String(line)
			story_line.add_theme_font_size_override("font_size", VI.FONT_TINY)
			story_line.add_theme_color_override("font_color", VI.INK_DIM)
			story_line.autowrap_mode = TextServer.AUTOWRAP_WORD
			left.add_child(story_line)
	var completion = status.get("completion_reward", {})
	if completion is Dictionary and not (completion as Dictionary).is_empty():
		var parts := PackedStringArray()
		if int(completion.get("coins", 0)) > 0:
			parts.append("%d monedas" % int(completion["coins"]))
		if int(completion.get("gems", 0)) > 0:
			parts.append("%d gemas" % int(completion["gems"]))
		var comp_items = completion.get("items", {})
		if comp_items is Dictionary:
			for item_id in comp_items:
				parts.append("%s x%d" % [GameState.item_display_name(String(item_id)), int(comp_items[item_id])])
		var prize := Label.new()
		prize.text = "Premio por completar: %s" % ", ".join(parts)
		prize.add_theme_font_size_override("font_size", VI.FONT_TINY)
		prize.add_theme_color_override("font_color", VI.GOLD)
		prize.autowrap_mode = TextServer.AUTOWRAP_WORD
		left.add_child(prize)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	left.add_child(chips)
	_add_chip(chips, "STAGES %d/%d" % [int(status.get("stages_completed", 0)), int(status.get("stage_count", 0))], VI.BLUE)
	_add_chip(chips, "x%d COMPLETADO" % int(status.get("times_completed", 0)), VI.INK_DIM)
	var diffs := PackedStringArray()
	for st in status.get("stages", []):
		var d := String((st as Dictionary).get("difficulty", "NORMAL"))
		if not diffs.has(d):
			diffs.append(d)
	_add_chip(chips, " > ".join(diffs), VI.RED)
	var reward_id := String(status.get("character_reward", ""))
	if not reward_id.is_empty():
		var data: Dictionary = DB.get_character(reward_id)
		var art_holder := Control.new()
		art_holder.custom_minimum_size = Vector2(170, 230)
		poster.add_child(art_holder)
		var art := Portrait.new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_holder.add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.setup(reward_id, TypeColors.color_for(String(data.get("type", "STR"))),
			String(data.get("portrait_style", "short")), Portrait.art_path_from(data, "front"), "front", "")
		var badge := VI.rarity_badge(String(data.get("rarity", "SSR")), VI.FONT_SMALL)
		art_holder.add_child(badge)
		badge.position = Vector2(4, 0)

	_add_character_reward(box, status)

	# --- Selector de stages.
	var stages: Array = status.get("stages", [])
	var chosen := String(_selected_stage.get(event_id, ""))
	var valid := false
	for st in stages:
		if String((st as Dictionary).get("id", "")) == chosen:
			valid = true
	if not valid:
		chosen = ""
		for st in stages:
			var sd: Dictionary = st
			if bool(sd.get("unlocked", false)) and not bool(sd.get("completed", false)):
				chosen = String(sd.get("id", ""))
				break
		if chosen.is_empty() and not stages.is_empty():
			chosen = String((stages[stages.size() - 1] as Dictionary).get("id", ""))
	var tabs := HBoxContainer.new()
	tabs.name = "StageTabs"
	tabs.add_theme_constant_override("separation", 8)
	box.add_child(tabs)
	var chosen_stage: Dictionary = {}
	var n := 0
	for st in stages:
		var sd: Dictionary = st
		n += 1
		var sid := String(sd.get("id", ""))
		var is_sel := sid == chosen
		if is_sel:
			chosen_stage = sd
		tabs.add_child(_make_stage_tab(event_id, sd, n, is_sel))
	if not chosen_stage.is_empty():
		box.add_child(_make_stage_card(event_id, chosen_stage))
	return card


func _add_chip(parent: Control, text: String, color: Color) -> void:
	var chip := PanelContainer.new()
	var st := VI.panel(0.9, true, VI.RADIUS_CHIP)
	st.border_color = Color(color.r, color.g, color.b, 0.85)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)
	chip.add_child(l)
	parent.add_child(chip)


## Ficha del selector: numero del stage y su estado. Tocarla cambia el detalle.
func _make_stage_tab(event_id: String, stage: Dictionary, number: int, selected: bool) -> Control:
	var unlocked := bool(stage.get("unlocked", false))
	var completed := bool(stage.get("completed", false))
	var accent := _state_accent(unlocked, completed)
	var b := Button.new()
	b.name = "StageTab%d" % number
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 76)
	b.focus_mode = Control.FOCUS_NONE
	var mark := "OK" if completed else ("BLOQ." if not unlocked else String(stage.get("difficulty", "NORMAL")))
	b.text = "STAGE %d\n%s" % [number, mark]
	b.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	VI.tint_button(b, VI.GOLD if selected else accent)
	b.pressed.connect(_on_stage_tab_pressed.bind(event_id, String(stage.get("id", ""))))
	return b


func _on_stage_tab_pressed(event_id: String, stage_id: String) -> void:
	_selected_stage[event_id] = stage_id
	_build_list()


## Unidad que entrega el evento, con su estado. Si el evento no da personaje no se
## pinta nada; si ya se entrego, el boton lo dice y no vuelve a pagar.
func _add_character_reward(box: VBoxContainer, status: Dictionary) -> void:
	var reward_id := String(status.get("character_reward", ""))
	if reward_id.is_empty():
		return
	var event_id := String(status.get("id", ""))
	var claimed := bool(status.get("character_claimed", false))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	var text := Label.new()
	text.text = "Recompensa: %s" % GameState.display_name(reward_id)
	text.add_theme_font_size_override("font_size", VI.FONT_BODY)
	text.add_theme_color_override("font_color", VI.GOLD if not claimed else VI.INK_DIM)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	row.add_child(text)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	button.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	if claimed:
		button.text = "RECLAMADA"
		button.disabled = true
	else:
		button.text = "RECLAMAR"
		button.pressed.connect(_on_claim_pressed.bind(event_id))
	VI.tint_button(button, VI.GOLD if not claimed else VI.INK_DIM)
	row.add_child(button)


## Tarjeta de un stage. El estado se ve en el marco, en la etiqueta y en si el
## boton responde.
func _make_stage_card(event_id: String, stage: Dictionary) -> Control:
	var stage_id := String(stage.get("id", ""))
	var unlocked := bool(stage.get("unlocked", false))
	var completed := bool(stage.get("completed", false))
	var accent := _state_accent(unlocked, completed)

	var card := PanelContainer.new()
	var style := VI.card(accent, false, "", true)
	style.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)

	var name_label := Label.new()
	name_label.text = "%s   -   %s" % [
		String(stage.get("name", stage_id)),
		String(stage.get("difficulty", "NORMAL")),
	]
	name_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
	name_label.add_theme_color_override("font_color", accent)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	head.add_child(name_label)

	var state_label := Label.new()
	state_label.text = _state_text(unlocked, completed)
	state_label.add_theme_font_size_override("font_size", VI.FONT_TINY)
	state_label.add_theme_color_override("font_color", accent)
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(state_label)

	_add_line(box, "Rivales: %s" % _enemies_text(stage.get("enemies", [])), VI.INK_SOFT, VI.FONT_SMALL)
	_add_line(box, "Recompensa: %d XP   %d monedas" % [
		int(stage.get("xp_reward", 0)), int(stage.get("coin_reward", 0))], VI.INK, VI.FONT_SMALL)

	if int(stage.get("survive_rounds", 0)) > 0:
		_add_line(box, "SUPERVIVENCIA: aguanta %d rondas." % int(stage["survive_rounds"]), VI.RED, VI.FONT_SMALL)
	if bool(stage.get("boss", false)):
		_add_line(box, "JEFE con fases", VI.VIOLET, VI.FONT_SMALL)
	var excl = stage.get("first_clear_items", {})
	if excl is Dictionary and not (excl as Dictionary).is_empty():
		var excl_parts := PackedStringArray()
		for item_id in excl:
			excl_parts.append("%s x%d" % [GameState.item_display_name(String(item_id)), int(excl[item_id])])
		_add_line(box, "Primera victoria: %s" % ", ".join(excl_parts), VI.GOLD, VI.FONT_SMALL)
	var drops_text := _drops_text(stage.get("drops", []))
	if not drops_text.is_empty():
		_add_line(box, "Suelta al ganar: %s" % drops_text, VI.GOLD, VI.FONT_SMALL)

	# REQUISITO DE EQUIPO. Quien decide es GameState.event_party_ready, la MISMA
	# funcion que comprueba el combate: la pantalla solo pinta su veredicto y el
	# motivo. Asi el boton no puede dejar pasar algo que el juego luego rechace, y
	# el requisito (unidad concreta, forma UR, equipo de 1) sale del JSON.
	var gate: Dictionary = GameState.event_party_ready(event_id, stage_id, GameState.party)
	var gate_ok := bool(gate.get("ok", true))
	if not String(stage.get("requires_party_character", "")).is_empty():
		var required := String(stage.get("requires_party_character", ""))
		_add_line(box, "Requiere: %s" % _requirement_text(stage, required),
			VI.GREEN if gate_ok else VI.RED, VI.FONT_SMALL)
	if not gate_ok:
		_add_line(box, String(gate.get("reason", "")), VI.RED, VI.FONT_TINY)

	var clears := int(stage.get("clears", 0))
	if clears > 0:
		_add_line(box, "Superado %d veces" % clears, VI.INK_DIM, VI.FONT_TINY)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	button.add_theme_font_size_override("font_size", VI.FONT_BODY)
	button.focus_mode = Control.FOCUS_NONE
	var playable := unlocked and gate_ok
	if not unlocked:
		button.text = "BLOQUEADO"
		button.disabled = true
	elif not gate_ok:
		button.text = "EQUIPO NO VALIDO"
		button.disabled = true
	else:
		button.text = "JUGAR"
		button.pressed.connect(_on_play_pressed.bind(event_id, stage_id))
	VI.tint_button(button, VI.BLUE if playable else VI.INK_DIM)
	if unlocked:
		# v12: EQUIPO antes de combatir (equipo guardado, AUTO o uno hecho a mano).
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
		var team_button := Button.new()
		team_button.name = "TeamButton"
		team_button.text = "EQUIPO"
		team_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)
		team_button.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		team_button.focus_mode = Control.FOCUS_NONE
		VI.tint_button(team_button, VI.GOLD)
		team_button.pressed.connect(_on_team_pressed.bind(event_id, stage_id))
		row.add_child(team_button)
		box.add_child(row)
	else:
		box.add_child(button)

	return card


## Texto legible del requisito de equipo de un stage, con lo que pide el JSON:
## la unidad, su forma (si la pide) y si el equipo tiene que ser SOLO esa unidad.
func _requirement_text(stage: Dictionary, character_id: String) -> String:
	var text := GameState.display_name(character_id)
	var rarity := String(stage.get("requires_party_rarity", ""))
	if not rarity.is_empty():
		text += " (%s)" % rarity
	if bool(stage.get("requires_party_solo", false)):
		text += "  -  1 VS 1: solo esa unidad, sin companeros"
	return text


func _add_line(box: VBoxContainer, text: String, color: Color, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(label)


func _state_accent(unlocked: bool, completed: bool) -> Color:
	if not unlocked:
		return VI.INK_DIM
	if completed:
		return VI.GREEN
	return VI.BLUE


func _state_text(unlocked: bool, completed: bool) -> String:
	if not unlocked:
		return "BLOQUEADO"
	if completed:
		return "SUPERADO"
	return "DISPONIBLE"


## Rivales de un stage, con el nombre de los datos. Empieza a estar disponible en
## cuanto el stage esta desbloqueado; no hay ninguna lista escrita aqui.
func _enemies_text(enemies: Array) -> String:
	var names := PackedStringArray()
	for raw_id in enemies:
		var enemy: Dictionary = DB.get_enemy(String(raw_id))
		names.append(String(enemy.get("name", String(raw_id))))
	if names.is_empty():
		return "Sin rivales"
	return "%d: %s" % [names.size(), ", ".join(names)]


## Objetos que suelta un stage, con su rango y sin repetir el nombre si el mismo
## objeto aparece en varias entradas.
func _drops_text(drops: Array) -> String:
	var parts := PackedStringArray()
	for drop in drops:
		if not (drop is Dictionary):
			continue
		var item_id := String((drop as Dictionary).get("item", ""))
		if item_id.is_empty():
			continue
		var low := int((drop as Dictionary).get("min", 1))
		var high := int((drop as Dictionary).get("max", low))
		var label := "%s x%d-%d" % [GameState.item_display_name(item_id), low, high] if high > low else "%s x%d" % [GameState.item_display_name(item_id), low]
		if not parts.has(label):
			parts.append(label)
	return ", ".join(parts)


## --- Acciones ----------------------------------------------------------------

## JUGAR. Primero pregunta a GameState si el equipo puede entrar (un stage puede
## pedir una unidad concreta): si no puede, se dice el motivo y NO se abre nada.
## Despues prepare_battle fija los enemigos y se abre el combate. La pantalla no
## calcula recompensas: las paga el combate al terminar.
func _on_play_pressed(event_id: String, stage_id: String) -> void:
	var gate: Dictionary = GameState.event_party_ready(event_id, stage_id, GameState.party)
	if not bool(gate.get("ok", false)):
		feedback.text = String(gate.get("reason", "No puedes entrar a ese stage."))
		return
	var prepared: bool = GameState.prepare_battle(GameState.BATTLE_EVENT, {
		"event": event_id,
		"stage": stage_id,
	})
	if not prepared:
		feedback.text = "No se ha podido preparar esta batalla."
		return
	feedback.text = ""
	var app := NAV.app_of(self)
	if app != null and app.has_method("open_battle"):
		app.call("open_battle")


## EQUIPO antes de un stage de evento: se fija el origen para que la ventana compare
## cada equipo guardado con lo que pide ESTE stage (unidad concreta, forma, 1 VS 1).
func _on_team_pressed(event_id: String, stage_id: String) -> void:
	GameState.prepare_battle(GameState.BATTLE_EVENT, { "event": event_id, "stage": stage_id })
	var panel := SavedTeamsPanel.open_on(self, "party", true)
	panel.closed.connect(refresh)


## RECLAMAR la unidad del evento. GameState.claim_event_character es el unico
## sitio que la entrega, y solo la entrega una vez.
func _on_claim_pressed(event_id: String) -> void:
	var result: Dictionary = GameState.claim_event_character(event_id)
	refresh()
	var name_text := String(result.get("name", ""))
	var reason := String(result.get("reason", ""))
	feedback.text = ("%s: %s" % [name_text, reason]) if not name_text.is_empty() else reason


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
