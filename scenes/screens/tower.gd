extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")
const ROSTER_CARD := preload("res://ui/roster_card.tscn")
const THEME := preload("res://ui/theme.tres")

## TORRE: el desafio vertical. Composicion propia, distinta de las pantallas de
## lista: una TORRE de pisos que se lee de arriba (jefe final) a abajo (piso 1),
## con el piso actual encendido, y debajo la formacion de 5 (3 ACTIVOS grandes y
## 2 RESERVAS pequenas). Todo sale de data/towers y de GameState: ningun piso,
## jefe ni personaje esta escrito aqui.
##
## Flujo: elegir equipo (tocar un puesto abre el selector) -> elegir piso (solo se
## puede entrar al piso actual o a uno ya alcanzado) -> COMBATIR. El combate se
## abre por encima y, al volver, la pantalla se repinta con el progreso nuevo.

const TOWER_ID_FALLBACK := "tower_001"

var tower_id := ""
var _selected_floor := 0
var _picking_slot := -1

var _title: Label
var _status: Label
var _floor_list: VBoxContainer
var _floor_scroll: ScrollContainer
var _active_row: HBoxContainer
var _reserve_row: HBoxContainer
var _fight_button: Button
var _hint: Label
var _picker: Control
var _picker_title: Label
var _picker_grid: GridContainer


func _ready() -> void:
	theme = THEME
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ScreenBackground.new()
	bg.slot = "tower"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	margin.add_child(main)

	_title = Label.new()
	_title.text = "TORRE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.style_title(_title, VI.FONT_BIG)
	_title.add_theme_color_override("font_color", VI.GOLD)
	main.add_child(_title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	VI.style_subtitle(_status)
	main.add_child(_status)

	_floor_scroll = ScrollContainer.new()
	_floor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_floor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(_floor_scroll)
	_floor_list = VBoxContainer.new()
	_floor_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_floor_list.add_theme_constant_override("separation", 6)
	_floor_scroll.add_child(_floor_list)

	main.add_child(_section_label("ACTIVOS  (combaten)"))
	_active_row = HBoxContainer.new()
	_active_row.add_theme_constant_override("separation", 10)
	main.add_child(_active_row)
	main.add_child(_section_label("RESERVA  (entran cuando cae un activo)"))
	_reserve_row = HBoxContainer.new()
	_reserve_row.add_theme_constant_override("separation", 10)
	main.add_child(_reserve_row)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	VI.style_note(_hint)
	main.add_child(_hint)

	_fight_button = Button.new()
	_fight_button.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(_fight_button, VI.GOLD)
	_fight_button.pressed.connect(_on_fight)
	main.add_child(_fight_button)

	var back := Button.new()
	back.text = "VOLVER"
	back.custom_minimum_size = Vector2(0, 80)
	VI.tint_button(back, VI.BLUE)
	back.pressed.connect(_on_back)
	main.add_child(back)

	_build_picker()


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	label.add_theme_color_override("font_color", VI.INK_SOFT)
	return label


func refresh() -> void:
	if tower_id.is_empty() or DB.get_tower(tower_id).is_empty():
		var towers: Array = DB.playable_towers()
		tower_id = String((towers[0] as Dictionary).get("id", "")) if not towers.is_empty() else TOWER_ID_FALLBACK
	GameState.normalize_tower_team()
	var status: Dictionary = GameState.tower_status(tower_id)
	var run := int(status.get("run_floor", 1))
	if _selected_floor <= 0 or _selected_floor > run:
		_selected_floor = run
	_title.text = String(status.get("name", "TORRE"))
	_status.text = "Piso actual %d / %d    Checkpoint %d    Mejor piso %d" % [
		run, int(status.get("floor_count", 0)), int(status.get("checkpoint", 0)), int(status.get("best_floor", 0))]
	_picker.visible = false
	_build_floors(status)
	_build_team()
	_update_fight_button()


## Hook del App: el combate de la torre ha terminado y se repinta con el progreso.
func on_battle_closed() -> void:
	GameState.reset_battle_context()
	# Tras el combate la seleccion salta al piso ACTUAL (el siguiente si se gano,
	# el del checkpoint si se perdio).
	_selected_floor = 0
	refresh()


func _build_floors(status: Dictionary) -> void:
	_clear(_floor_list)
	var floors: Array = status.get("floors", [])
	var run := int(status.get("run_floor", 1))
	var order: Array = floors.duplicate()
	order.reverse()
	var selected_row: Control = null
	for raw in order:
		var info: Dictionary = raw
		var number := int(info.get("floor", 0))
		var row := _make_floor_row(info, number == _selected_floor, number <= run, number == run)
		_floor_list.add_child(row)
		if number == _selected_floor:
			selected_row = row
	if selected_row != null:
		_scroll_to.call_deferred(selected_row)


func _scroll_to(row: Control) -> void:
	if is_instance_valid(row) and is_instance_valid(_floor_scroll):
		_floor_scroll.ensure_control_visible(row)


func _make_floor_row(info: Dictionary, selected: bool, open: bool, current: bool) -> Control:
	var number := int(info.get("floor", 0))
	var boss := bool(info.get("boss", false))
	var cleared := bool(info.get("cleared", false))
	var accent := VI.RED if boss else VI.BLUE
	if current:
		accent = VI.GOLD
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 96 if boss else 76)
	var box := VI.card(accent, selected, "", boss)
	panel.add_theme_stylebox_override("panel", box)
	panel.modulate = Color(1, 1, 1, 1.0 if open else 0.55)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)

	var num := Label.new()
	num.text = str(number)
	num.custom_minimum_size = Vector2(76, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", VI.FONT_BIG if boss else VI.FONT_SECTION)
	num.add_theme_color_override("font_color", accent)
	h.add_child(num)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(mid)
	var name_label := Label.new()
	name_label.text = String(info.get("name", "Piso %d" % number))
	name_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
	name_label.add_theme_color_override("font_color", VI.RED if boss else VI.INK)
	mid.add_child(name_label)
	var foes := Label.new()
	foes.text = _enemy_names(info.get("enemies", []))
	foes.add_theme_font_size_override("font_size", VI.FONT_TINY)
	foes.add_theme_color_override("font_color", VI.INK_DIM)
	foes.clip_text = true
	mid.add_child(foes)

	var right := Label.new()
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	if current:
		right.text = "ACTUAL"
		right.add_theme_color_override("font_color", VI.GOLD)
	elif cleared and open:
		right.text = "SUPERADO"
		right.add_theme_color_override("font_color", VI.GREEN)
	elif not open:
		right.text = "BLOQUEADO"
		right.add_theme_color_override("font_color", VI.INK_DIM)
	h.add_child(right)

	if open:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_floor_input.bind(number))
	return panel


func _enemy_names(ids: Variant) -> String:
	var names := PackedStringArray()
	if ids is Array:
		for id in ids:
			var data := DB.get_enemy(String(id))
			names.append(String(data.get("name", id)))
	return "  +  ".join(names)


func _on_floor_input(event: InputEvent, number: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_floor(number)
	elif event is InputEventScreenTouch and event.pressed:
		_select_floor(number)


func _select_floor(number: int) -> void:
	_selected_floor = number
	GameAudio.play("select")
	refresh()


## --- Equipo de torre -------------------------------------------------------

func _build_team() -> void:
	_clear(_active_row)
	_clear(_reserve_row)
	for i in GameState.TOWER_TEAM_SIZE:
		var active := i < GameState.TOWER_ACTIVE
		var slot := _make_slot(i, active)
		(_active_row if active else _reserve_row).add_child(slot)


func _make_slot(index: int, active: bool) -> Control:
	var id := String(GameState.tower_team[index]) if index < GameState.tower_team.size() else ""
	var data := GameState.character_data(id) if not id.is_empty() else {}
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 150 if active else 96)
	var tint := VI.INK_DIM
	var rarity := ""
	if not data.is_empty():
		tint = TypeColors.color_for(String(data.get("type", "STR")))
		rarity = String(data.get("rarity", ""))
	panel.add_theme_stylebox_override("panel", VI.card(tint, false, rarity))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	var size := 84.0 if active else 52.0
	var portrait := Portrait.new()
	portrait.custom_minimum_size = Vector2(size, size)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(portrait)
	portrait.setup(id, tint, String(data.get("portrait_style", "short")), Portrait.art_path_from(data, "icon"), "icon", "")
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", VI.FONT_SMALL if active else VI.FONT_TINY)
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if data.is_empty():
		label.text = "+ ACTIVO %d" % (index + 1) if active else "+ RESERVA %d" % (index - GameState.TOWER_ACTIVE + 1)
		label.add_theme_color_override("font_color", VI.INK_DIM)
	else:
		label.text = "%s  Nv.%d" % [String(data.get("name", id)), int(data.get("level", 1))]
		label.add_theme_color_override("font_color", tint)
	v.add_child(label)
	panel.gui_input.connect(_on_slot_input.bind(index))
	return panel


func _on_slot_input(event: InputEvent, index: int) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if pressed:
		_open_picker(index)


func _build_picker() -> void:
	_picker = Control.new()
	_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.visible = false
	add_child(_picker)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 120)
	margin.add_theme_constant_override("margin_bottom", 120)
	_picker.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", VI.panel(0.98))
	margin.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_picker_title = Label.new()
	_picker_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.style_title(_picker_title, VI.FONT_SECTION)
	v.add_child(_picker_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_picker_grid = GridContainer.new()
	_picker_grid.columns = 2
	_picker_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_grid.add_theme_constant_override("h_separation", 10)
	_picker_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_picker_grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var clear_button := Button.new()
	clear_button.text = "QUITAR"
	clear_button.custom_minimum_size = Vector2(0, 80)
	clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VI.tint_button(clear_button, VI.RED)
	clear_button.pressed.connect(_on_pick.bind(""))
	row.add_child(clear_button)
	var close_button := Button.new()
	close_button.text = "CERRAR"
	close_button.custom_minimum_size = Vector2(0, 80)
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VI.tint_button(close_button, VI.BLUE)
	close_button.pressed.connect(_close_picker)
	row.add_child(close_button)


func _open_picker(index: int) -> void:
	_picking_slot = index
	var active := index < GameState.TOWER_ACTIVE
	_picker_title.text = ("ACTIVO %d" % (index + 1)) if active else ("RESERVA %d" % (index - GameState.TOWER_ACTIVE + 1))
	_clear(_picker_grid)
	for raw in GameState.roster_data():
		var data: Dictionary = raw
		var id := String(data.get("id", ""))
		var taken := GameState.tower_team.has(id)
		var card: Control = ROSTER_CARD.instantiate()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_picker_grid.add_child(card)
		card.bind(data, taken, "EN LA TORRE" if taken else "", true)
		card.pressed.connect(_on_pick_data)
	_picker.visible = true
	GameAudio.play("open")


func _on_pick_data(data: Dictionary) -> void:
	_on_pick(String(data.get("id", "")))


func _on_pick(id: String) -> void:
	if _picking_slot < 0:
		return
	GameState.assign_tower_slot(_picking_slot, id)
	GameAudio.play("equip" if not id.is_empty() else "remove")
	_close_picker()
	refresh()


func _close_picker() -> void:
	_picker.visible = false
	_picking_slot = -1


## --- Combate ----------------------------------------------------------------

func _update_fight_button() -> void:
	var problem := GameState.tower_team_problem(tower_id, _selected_floor)
	_fight_button.disabled = not problem.is_empty()
	_fight_button.text = "COMBATIR PISO %d" % _selected_floor
	_hint.text = problem if not problem.is_empty() else "Equipo: %d / %d  (%d activos, %d en reserva)" % [
		GameState.tower_team_count(), GameState.TOWER_TEAM_SIZE,
		GameState.tower_active_ids().size(), GameState.tower_reserve_ids().size()]


func _on_fight() -> void:
	if not GameState.prepare_tower_battle(tower_id, _selected_floor):
		_update_fight_button()
		return
	GameAudio.play("click")
	var app := NAV.app_of(self)
	if app != null and app.has_method("open_battle"):
		app.call("open_battle")


func _on_back() -> void:
	GameAudio.play("back")
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
