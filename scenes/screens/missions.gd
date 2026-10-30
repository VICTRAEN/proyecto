extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const RING := preload("res://ui/progress_ring.gd")

## MISIONES. Pantalla REAL de misiones: una tarjeta por mision con nombre,
## descripcion, progreso x / objetivo, recompensa y su estado.
##
## La lista sale de DB.all_missions() (res://data/missions/*.json) y de
## GameState.all_missions_state(): una mision nueva es crear su JSON, esta pantalla
## no cambia.
##
## El progreso NO se guarda como estado aparte: se calcula desde los contadores
## globales del jugador (victorias, combates jugados, personajes obtenidos). Lo
## unico que se guarda es si la recompensa ya se ha cobrado, para que una mision
## completada no pague dos veces.
##
## CONTRATO QUE NO SE PUEDE ROMPER: la verificacion de V0.8 llama a
## _on_claim_pressed(id: String) y despues lee el nodo "Margin/Main/Scroll/List"
## para contar tarjetas. Ese metodo y esa ruta existen tal cual.
##
## Una mision completada y ya cobrada lo sigue estando: no se puede reclamar de
## nuevo, y el boton lo dice.
##
## El ROL de un personaje es un dato interno de diseno y no se pinta aqui.

@onready var title_label: Label = $Margin/Main/Title
@onready var subtitle_label: Label = $Margin/Main/Subtitle
@onready var counters_label: Label = $Margin/Main/Counters
@onready var list: VBoxContainer = $Margin/Main/Scroll/List
@onready var feedback: Label = $Margin/Main/Feedback
@onready var back_button: Button = $Margin/Main/BackButton


## v14: pestanas. DIARIAS y SEMANALES salen de core/meta_progress.gd (se reinician
## solas por fecha), PERMANENTES son las de siempre y LOGROS lleva ademas los titulos.
const TABS := [["daily", "DIARIAS"], ["weekly", "SEMANALES"], ["permanent", "PERMANENTES"], ["achievements", "LOGROS"]]
var _tab := "daily"
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	_apply_identity()
	back_button.pressed.connect(_back)
	_build_tabs()


func _build_tabs() -> void:
	var row := HBoxContainer.new()
	row.name = "Tabs"
	row.add_theme_constant_override("separation", 6)
	var main_box := list.get_parent().get_parent()
	main_box.add_child(row)
	main_box.move_child(row, list.get_parent().get_index())
	for entry in TABS:
		var button := Button.new()
		button.text = String(entry[1])
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 56)
		button.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		button.pressed.connect(_select_tab.bind(String(entry[0])))
		row.add_child(button)
		_tab_buttons[String(entry[0])] = button


func _select_tab(tab: String) -> void:
	_tab = tab
	feedback.text = ""
	_build_list()
	_sync_tabs()


func _sync_tabs() -> void:
	for key in _tab_buttons:
		var button: Button = _tab_buttons[key]
		button.button_pressed = key == _tab
		var ready_n := _ready_count(String(key))
		var base := ""
		for entry in TABS:
			if entry[0] == key:
				base = String(entry[1])
		button.text = "%s (%d)" % [base, ready_n] if ready_n > 0 else base
		VI.tint_button(button, VI.GOLD if key == _tab else VI.INK_DIM)


func _ready_count(tab: String) -> int:
	var n := 0
	for m in _entries_for(tab):
		if bool(m["completed"]) and not bool(m["claimed"]):
			n += 1
	return n


func _entries_for(tab: String) -> Array:
	match tab:
		"daily":
			return GameState.meta.periodic_list("daily")
		"weekly":
			return GameState.meta.periodic_list("weekly")
		"achievements":
			var out: Array = []
			for id in GameState.meta.achievement_ids():
				var st: Dictionary = GameState.meta.achievement_state(String(id))
				st["kind"] = "achievement"
				# Un logro cumplido sin reclamar se puede cobrar; check lo marca.
				out.append(st)
			return out
	return GameState.all_missions_state()


## Aspecto estatico de la pantalla, con los tokens de la identidad visual.
func _apply_identity() -> void:
	VI.screen_title(title_label, VI.BLUE)
	VI.style_subtitle(subtitle_label)
	VI.style_subtitle(counters_label)
	VI.style_title(feedback, VI.FONT_BODY)
	VI.tint_button(back_button, VI.BLUE)
	back_button.custom_minimum_size = Vector2(0, VI.TOUCH)


func refresh() -> void:
	feedback.text = ""
	GameState.meta.check_achievements()
	_build_counters()
	_build_list()
	_sync_tabs()


## Contadores globales del jugador, como CHIPS en una fila (no un parrafo). Son los
## mismos numeros que alimentan las misiones.
func _build_counters() -> void:
	counters_label.visible = false
	var old := counters_label.get_parent().get_node_or_null("CounterChips")
	if old != null:
		old.get_parent().remove_child(old)
		old.queue_free()
	var chips := HBoxContainer.new()
	chips.name = "CounterChips"
	chips.add_theme_constant_override("separation", 8)
	counters_label.get_parent().add_child(chips)
	counters_label.get_parent().move_child(chips, counters_label.get_index() + 1)
	var data := [
		["COMBATES", GameState.counter_value("combates_jugados"), VI.BLUE],
		["VICTORIAS", GameState.counter_value("victorias"), VI.GREEN],
		["PERSONAJES", "%d/%d" % [GameState.counter_value("personajes_obtenidos"), GameState.total_count()], VI.VIOLET],
		["MONEDAS", GameState.coins, VI.GOLD],
	]
	for entry in data:
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var st := VI.panel(0.9, true, VI.RADIUS_CHIP)
		st.border_color = Color(entry[2].r, entry[2].g, entry[2].b, 0.8)
		chip.add_theme_stylebox_override("panel", st)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		chip.add_child(v)
		var num := Label.new()
		num.text = str(entry[1])
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", VI.FONT_BODY)
		num.add_theme_color_override("font_color", entry[2])
		v.add_child(num)
		var cap := Label.new()
		cap.text = entry[0]
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_size_override("font_size", 13)
		cap.add_theme_color_override("font_color", VI.INK_DIM)
		v.add_child(cap)
		chips.add_child(chip)


## Misiones agrupadas por TIPO (campo "category" del JSON). Dentro de cada grupo
## primero las que se pueden RECLAMAR, luego las activas y al final las cobradas.
func _build_list() -> void:
	_clear(list)
	var missions: Array = _entries_for(_tab)
	if _tab == "achievements":
		list.add_child(_make_titles_row())
	elif _tab != "permanent":
		var period := "daily" if _tab == "daily" else "weekly"
		list.add_child(_make_reset_label(period))
	if missions.is_empty():
		var empty := Label.new()
		empty.text = "No hay misiones disponibles."
		empty.add_theme_font_size_override("font_size", VI.FONT_BODY)
		empty.add_theme_color_override("font_color", VI.INK_DIM)
		list.add_child(empty)
		return
	var groups := {}
	for mission in missions:
		var cat := String(mission.get("category", "GENERAL"))
		if not groups.has(cat):
			groups[cat] = []
		(groups[cat] as Array).append(mission)
	for cat in groups:
		var arr: Array = groups[cat]
		arr.sort_custom(func(x, y): return _order(x) < _order(y))
		var ready_n := 0
		for m in arr:
			if bool(m["completed"]) and not bool(m["claimed"]):
				ready_n += 1
		list.add_child(_make_header(String(cat), arr.size(), ready_n))
		for m in arr:
			list.add_child(_make_card(m))


func _order(m: Dictionary) -> int:
	if bool(m["claimed"]):
		return 2
	return 0 if bool(m["completed"]) else 1


func _make_header(cat: String, total: int, ready_n: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new()
	bar.color = VI.GOLD
	bar.custom_minimum_size = Vector2(6, 28)
	row.add_child(bar)
	var l := Label.new()
	l.text = cat
	l.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	l.add_theme_color_override("font_color", VI.INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var info := Label.new()
	info.text = "%d PARA RECLAMAR" % ready_n if ready_n > 0 else "%d misiones" % total
	info.add_theme_font_size_override("font_size", VI.FONT_TINY)
	info.add_theme_color_override("font_color", VI.GREEN if ready_n > 0 else VI.INK_DIM)
	row.add_child(info)
	return row


## Fila de mision: MEDALLON de progreso a la izquierda, nombre/descripcion/barra en
## el centro y a la derecha la recompensa con su boton. Tres estados distintos:
## activa (azul), lista (verde, brilla) y reclamada (apagada con OK).
func _make_card(mission: Dictionary) -> Control:
	var completed := bool(mission.get("completed", false))
	var claimed := bool(mission.get("claimed", false))
	var ready := completed and not claimed
	var accent := _state_accent(completed, claimed)
	var progress := int(mission.get("progress", 0))
	var target := maxi(1, int(mission.get("target", 1)))

	var card := PanelContainer.new()
	var style := VI.panel(0.95, true, VI.RADIUS_CARD)
	style.set_border_width_all(3 if ready else 2)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.9 if ready else 0.5)
	if ready:
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.40)
		style.shadow_size = 12
	card.add_theme_stylebox_override("panel", style)
	if claimed:
		card.modulate = Color(1, 1, 1, 0.6)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var ring := Control.new()
	ring.set_script(RING)
	row.add_child(ring)
	ring.call("setup", float(progress) / float(target), accent, "%d/%d" % [progress, target], claimed)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	row.add_child(mid)
	var title := Label.new()
	title.text = String(mission.get("name", ""))
	title.add_theme_font_size_override("font_size", VI.FONT_BODY)
	title.add_theme_color_override("font_color", accent if not claimed else VI.INK_SOFT)
	mid.add_child(title)
	var description := Label.new()
	description.text = String(mission.get("description", ""))
	description.add_theme_font_size_override("font_size", VI.FONT_TINY)
	description.add_theme_color_override("font_color", VI.INK_SOFT)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD
	mid.add_child(description)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.max_value = float(target)
	bar.value = float(progress)
	bar.show_percentage = false
	mid.add_child(bar)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.custom_minimum_size = Vector2(130, 0)
	row.add_child(right)
	var reward_coins := int(mission.get("reward_coins", 0))
	var reward_gems := int(mission.get("reward_gems", 0))
	var reward := Label.new()
	reward.text = "+%d monedas" % reward_coins
	if reward_gems > 0:
		reward.text += "\n+%d gemas" % reward_gems
	if not String(mission.get("title_name", "")).is_empty():
		reward.text += "\nTitulo: %s" % String(mission["title_name"])
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.add_theme_font_size_override("font_size", VI.FONT_TINY)
	reward.add_theme_color_override("font_color", VI.GOLD if not claimed else VI.INK_DIM)
	right.add_child(reward)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	if claimed:
		button.text = "RECLAMADA"
		button.disabled = true
	elif completed:
		button.text = "RECLAMAR"
		if String(mission.get("kind", "")) == "achievement":
			button.pressed.connect(_on_claim_achievement.bind(String(mission.get("id", ""))))
		else:
			button.pressed.connect(_on_claim_pressed.bind(String(mission.get("id", ""))))
	else:
		button.text = "EN CURSO"
		button.disabled = true
	VI.tint_button(button, VI.GREEN if ready else VI.INK_DIM)
	right.add_child(button)
	return card


## Color del estado de una mision: verde lo cobrable, apagado lo ya cobrado, azul
## lo que sigue en curso.
func _state_accent(completed: bool, claimed: bool) -> Color:
	if claimed:
		return VI.INK_DIM
	if completed:
		return VI.GREEN
	return VI.BLUE


func _state_text(completed: bool, claimed: bool) -> String:
	if claimed:
		return "COMPLETADA"
	if completed:
		return "COMPLETADA  -  listo para reclamar"
	return "ACTIVA"


## Cobra la mision. GameState.claim_mission es el unico sitio que paga: si la
## mision ya estaba cobrada devuelve vacio y aqui no pasa nada.
func _on_claim_pressed(id: String) -> void:
	var result: Dictionary = GameState.claim_mission(id)
	if result.is_empty():
		feedback.text = "Esa recompensa ya se ha reclamado."
		refresh()
		return
	var parts := PackedStringArray()
	var coins_earned := int(result.get("coins", 0))
	var gems_earned := int(result.get("gems", 0))
	if coins_earned > 0:
		parts.append("%d monedas" % coins_earned)
	if gems_earned > 0:
		parts.append("%d gemas" % gems_earned)
	refresh()
	feedback.text = "%s reclamada: %s" % [String(result.get("name", "Mision")), ", ".join(parts)]


## Cobra un logro: el unico sitio que paga es meta.claim_achievement.
func _on_claim_achievement(id: String) -> void:
	var result: Dictionary = GameState.meta.claim_achievement(id)
	if result.is_empty():
		feedback.text = "Ese logro ya se ha reclamado."
		refresh()
		return
	refresh()
	feedback.text = "%s reclamado: %d monedas, %d gemas" % [String(result.get("name", "Logro")), int(result.get("coins", 0)), int(result.get("gems", 0))]


func _make_reset_label(period: String) -> Control:
	var l := Label.new()
	var left := GameState.meta.seconds_left(period)
	var hours := left / 3600
	l.text = "Se reinicia en %dd %dh" % [hours / 24, hours % 24] if period == "weekly" else "Se reinicia en %dh %dmin" % [hours, (left % 3600) / 60]
	l.add_theme_font_size_override("font_size", VI.FONT_TINY)
	l.add_theme_color_override("font_color", VI.INK_DIM)
	return l


## Titulos conseguidos: el equipado se muestra en dorado; tocar otro lo equipa.
func _make_titles_row() -> Control:
	var box := VBoxContainer.new()
	box.name = "TitlesRow"
	var head := Label.new()
	head.text = "TITULO: %s" % GameState.meta.equipped_title_name()
	head.add_theme_font_size_override("font_size", VI.FONT_BODY)
	head.add_theme_color_override("font_color", VI.GOLD)
	box.add_child(head)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	box.add_child(flow)
	var catalog: Dictionary = GameState.meta.title_catalog()
	for id in GameState.meta.owned_titles():
		var b := Button.new()
		b.text = String(catalog.get(id, id))
		b.add_theme_font_size_override("font_size", VI.FONT_TINY)
		b.custom_minimum_size = Vector2(0, 44)
		VI.tint_button(b, VI.GOLD if id == GameState.meta.equipped_title() else VI.INK_DIM)
		b.pressed.connect(_on_equip_title.bind(String(id)))
		flow.add_child(b)
	return box


func _on_equip_title(id: String) -> void:
	if GameState.meta.equip_title(id):
		GameState.save_game()
	_build_list()


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
