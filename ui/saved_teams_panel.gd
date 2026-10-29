extends Control

const VI := preload("res://ui/visual_identity.gd")
const NAV := preload("res://scenes/nav.gd")

## EQUIPOS GUARDADOS (v12). Ventana modal sobre la pantalla EQUIPO.
##
## Toda la logica vive en GameState (saved_team_*): aqui solo se pinta y se pide.
## Un equipo guardado es una lista de ids. Si alguien ya no esta disponible, la
## ventana LO DICE y no toca el equipo activo; solo si el jugador pulsa
## "USAR IGUAL (con huecos)" se aplica sin ese personaje.
##
## Se usa para la batalla normal ("party", 4 puestos) y para la torre ("tower",
## 5 puestos: 3 activos + 2 reservas). El contenido que se va a jugar (historia,
## evento) se comprueba con GameState.content_problem_for y se ensena en cada fila.

signal team_applied(team_name: String)
signal edit_requested(team_id: int)
signal closed

var target := "party"
var _list: VBoxContainer
var _message: Label
var _name_edit: LineEdit
var _confirm_delete := -1
var _rename_id := -1
var _partial_id := -1
var _auto_proposal: Dictionary = {}
var _auto_button: Button
## Si la ventana se abre antes de un combate, se ofrece ajustar el equipo a mano.
var show_open_team_screen := false


## Abre la ventana encima de `host` (pantalla previa al combate o pantalla de equipo).
static func open_on(host: Node, team_target: String = "party", with_team_screen := false) -> Control:
	var panel: Control = load("res://ui/saved_teams_panel.gd").new()
	panel.name = "SavedTeamsPanel"
	panel.setup(team_target)
	panel.show_open_team_screen = with_team_screen
	host.add_child(panel)
	return panel


func setup(team_target: String = "party") -> void:
	target = team_target


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	add_child(margin)
	var window := PanelContainer.new()
	window.add_theme_stylebox_override("panel", VI.window(VI.GOLD, 0.98))
	margin.add_child(window)
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 18)
	window.add_child(inner)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	inner.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title.text = "EQUIPOS GUARDADOS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.style_title(title, VI.FONT_BODY)
	box.add_child(title)

	var requirement := Label.new()
	requirement.name = "Requirement"
	requirement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	requirement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.style_note(requirement)
	var req_text := GameState.content_requirement_text()
	requirement.text = ("Este combate: %s" % req_text) if not req_text.is_empty() else "Elige un equipo guardado o crea uno nuevo con tu equipo actual."
	box.add_child(requirement)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	_message = Label.new()
	_message.name = "Message"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	VI.style_note(_message)
	box.add_child(_message)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	box.add_child(save_row)
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.placeholder_text = "Nombre del equipo"
	_name_edit.max_length = GameState.SAVED_TEAM_NAME_MAX
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size = Vector2(0, 64)
	save_row.add_child(_name_edit)
	var save_button := _button("GUARDAR ACTUAL", VI.GREEN, _on_save_new)
	save_button.name = "SaveNew"
	save_row.add_child(save_button)

	var tools_row := HBoxContainer.new()
	tools_row.add_theme_constant_override("separation", 8)
	box.add_child(tools_row)
	_auto_button = _button("AUTO", VI.CYAN, _on_auto)
	_auto_button.name = "Auto"
	_auto_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_row.add_child(_auto_button)
	if show_open_team_screen:
		var adjust := _button("CREAR / AJUSTAR EQUIPO", VI.BLUE, _on_open_team_screen)
		adjust.name = "OpenTeamScreen"
		adjust.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tools_row.add_child(adjust)

	var close_button := _button("CERRAR", VI.BLUE, _close)
	close_button.name = "Close"
	box.add_child(close_button)
	_rebuild()


func _button(text: String, color: Color, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, VI.TOUCH * 0.6)
	button.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	VI.tint_button(button, color)
	button.pressed.connect(handler)
	return button


func _members_text(members: Array) -> String:
	var names := PackedStringArray()
	for raw_id in members:
		var key := String(raw_id)
		if key.is_empty():
			names.append("-")
		else:
			names.append(GameState.display_name(key))
	return "  /  ".join(names)


func _rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var teams := GameState.saved_team_list()
	var header := Label.new()
	header.text = "%d/%d equipos" % [teams.size(), GameState.SAVED_TEAM_MAX]
	VI.style_subtitle(header)
	_list.add_child(header)
	if teams.is_empty():
		var empty := Label.new()
		empty.text = "Aun no tienes equipos guardados."
		VI.style_note(empty)
		_list.add_child(empty)
	for team in teams:
		_list.add_child(_team_row(team))


func _team_row(team: Dictionary) -> Control:
	var team_id := int(team["id"])
	var status := GameState.saved_team_status(team_id)
	var panel := PanelContainer.new()
	panel.name = "Team%d" % team_id
	panel.add_theme_stylebox_override("panel", VI.panel(0.85, true))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	if _rename_id == team_id:
		var rename_row := HBoxContainer.new()
		var edit := LineEdit.new()
		edit.name = "RenameEdit"
		edit.text = String(team["name"])
		edit.max_length = GameState.SAVED_TEAM_NAME_MAX
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rename_row.add_child(edit)
		rename_row.add_child(_button("OK", VI.GOLD, _on_rename_ok.bind(team_id, edit)))
		box.add_child(rename_row)
	else:
		var name_label := Label.new()
		name_label.text = String(team["name"])
		name_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
		name_label.add_theme_color_override("font_color", VI.GOLD)
		box.add_child(name_label)

	var members := Label.new()
	members.text = _members_text(team["members"])
	members.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	members.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	box.add_child(members)

	# Estado: faltan personajes / no vale para el contenido / listo.
	var state := Label.new()
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_theme_font_size_override("font_size", VI.FONT_TINY)
	var lines := PackedStringArray()
	var missing: Array = status.get("missing", [])
	if not missing.is_empty():
		var names := PackedStringArray()
		for entry in missing:
			names.append("%s (%s)" % [String(entry["name"]), String(entry["reason"])])
		lines.append("NO DISPONIBLE: " + ", ".join(names))
	var usable: Array = status.get("available", [])
	if target == "party":
		var problem := GameState.content_problem_for(usable)
		if not problem.is_empty():
			lines.append("No vale para este combate: " + problem)
	if lines.is_empty():
		state.text = "Listo para usar"
		state.add_theme_color_override("font_color", VI.INK_DIM)
	else:
		state.text = "\n".join(lines)
		state.add_theme_color_override("font_color", VI.RED)
	box.add_child(state)

	if _partial_id == team_id:
		var warn := Label.new()
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.text = "Faltan personajes. Tu equipo actual NO se ha cambiado. Puedes usarlo igual, con huecos donde faltan."
		VI.style_note(warn)
		box.add_child(warn)
		var partial := _button("USAR IGUAL (con huecos)", VI.GOLD, _on_apply.bind(team_id, true))
		partial.name = "UsePartial"
		box.add_child(partial)

	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	box.add_child(row)
	var choose := _button("ELEGIR", VI.GOLD, _on_apply.bind(team_id, false))
	choose.name = "Choose"
	row.add_child(choose)
	row.add_child(_button("EDITAR", VI.BLUE, _on_edit.bind(team_id)))
	row.add_child(_button("RENOMBRAR", VI.BLUE, _on_rename.bind(team_id)))
	row.add_child(_button("DUPLICAR", VI.BLUE, _on_duplicate.bind(team_id)))
	var delete_text := "SEGURO? BORRAR" if _confirm_delete == team_id else "BORRAR"
	row.add_child(_button(delete_text, VI.RED, _on_delete.bind(team_id)))
	return panel


func _say(text: String) -> void:
	_message.text = text


func _on_apply(team_id: int, allow_partial: bool) -> void:
	var result := GameState.saved_team_apply(team_id, target, allow_partial)
	if bool(result["ok"]):
		_partial_id = -1
		team_applied.emit(String(result.get("name", "")))
		_close()
		return
	_partial_id = team_id
	_say(String(result["reason"]))
	_rebuild()


func _on_edit(team_id: int) -> void:
	var result := GameState.saved_team_apply(team_id, target, true)
	if not bool(result["ok"]):
		_say(String(result["reason"]))
		return
	edit_requested.emit(team_id)
	_close()


func _on_rename(team_id: int) -> void:
	_rename_id = team_id
	_confirm_delete = -1
	_rebuild()


func _on_rename_ok(team_id: int, edit: LineEdit) -> void:
	var result := GameState.saved_team_rename(team_id, edit.text)
	_say(String(result["reason"]))
	if bool(result["ok"]):
		_rename_id = -1
	_rebuild()


func _on_duplicate(team_id: int) -> void:
	var result := GameState.saved_team_duplicate(team_id)
	_say(String(result["reason"]) if not bool(result["ok"]) else "Equipo duplicado.")
	_rebuild()


func _on_delete(team_id: int) -> void:
	if _confirm_delete != team_id:
		_confirm_delete = team_id
		_say("Pulsa BORRAR otra vez para confirmar.")
		_rebuild()
		return
	_confirm_delete = -1
	GameState.saved_team_delete(team_id)
	_say("Equipo borrado.")
	_rebuild()


func _on_save_new() -> void:
	var result := GameState.saved_team_create(_name_edit.text, [], target)
	if bool(result["ok"]):
		_name_edit.text = ""
		_say("Equipo guardado.")
	else:
		_say(String(result["reason"]))
	_rebuild()


## AUTO: propone un equipo para este contenido (estadisticas, sinergias, requisitos)
## y lo ensena con sus motivos. Un segundo toque lo aplica; antes no se toca nada.
func _on_auto() -> void:
	if _auto_proposal.is_empty():
		var proposal := GameState.autoconfigure_team(target)
		if (proposal.get("members", []) as Array).is_empty():
			_say(String(proposal.get("reason", "No hay propuesta posible con tus personajes.")))
			return
		_auto_proposal = proposal
		_auto_button.text = "APLICAR PROPUESTA"
		_say("PROPUESTA: %s.  %s  (toca otra vez para aplicarla; despues podras cambiarla)" % [
			_members_text(proposal["members"]), "  ".join(PackedStringArray(proposal.get("parts", [])))])
		return
	GameState.apply_autoconfigured(_auto_proposal["members"], target)
	_auto_proposal = {}
	team_applied.emit("AUTO")
	_close()


func _on_open_team_screen() -> void:
	var app := NAV.app_of(self)
	closed.emit()
	if app != null and app.has_method("open_screen"):
		app.call("open_screen", "team")
	queue_free()


func _close() -> void:
	closed.emit()
	queue_free()
