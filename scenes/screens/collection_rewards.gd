extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const Collections := preload("res://core/collections.gd")

## RECOMPENSAS DE COLECCION (v15). Una tarjeta por coleccion con su progreso, los tramos
## de recompensa (reclamables cuando se alcanzan) y que personajes faltan y DE DONDE se
## consiguen. Solo LEE GameState.collections: lo unico que paga es claim_tier().

var _kind := "series"
var _summary: Label
var _feedback: Label
var _list: VBoxContainer
var _tab_buttons: Dictionary = {}
var _claim_all: Button
var _expanded: Dictionary = {}


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	margin.add_child(main)
	var title := Label.new()
	title.text = "COLECCIONES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.screen_title(title, VI.VIOLET)
	main.add_child(title)
	_summary = Label.new()
	_summary.name = "Summary"
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.style_subtitle(_summary)
	main.add_child(_summary)
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 6)
	main.add_child(tabs)
	for kind in Collections.KINDS:
		if kind == "custom":
			continue
		var b := Button.new()
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 56)
		b.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		b.pressed.connect(_select_kind.bind(String(kind)))
		tabs.add_child(b)
		_tab_buttons[String(kind)] = b
	_claim_all = Button.new()
	_claim_all.name = "ClaimAll"
	_claim_all.custom_minimum_size = Vector2(0, 64)
	_claim_all.pressed.connect(_on_claim_all)
	main.add_child(_claim_all)
	_feedback = Label.new()
	_feedback.name = "Feedback"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	VI.style_note(_feedback)
	main.add_child(_feedback)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "VOLVER"
	back.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(back, VI.BLUE)
	back.pressed.connect(_back)
	main.add_child(back)
	refresh()


func refresh() -> void:
	_feedback.text = ""
	_rebuild()


func _select_kind(kind: String) -> void:
	_kind = kind
	_feedback.text = ""
	_rebuild()


func _rebuild() -> void:
	var gs = GameState
	_summary.text = "%d de %d colecciones completas" % [gs.collections.completed_count(), gs.collections.ids().size()]
	for kind in _tab_buttons:
		var b: Button = _tab_buttons[kind]
		var ready_n := 0
		for cid in gs.collections.ids():
			var st: Dictionary = gs.collections.state(String(cid))
			if String(st["kind"]) == kind:
				ready_n += int(st["ready"])
		b.text = "%s (%d)" % [String(Collections.KIND_LABELS[kind]), ready_n] if ready_n > 0 else String(Collections.KIND_LABELS[kind])
		b.button_pressed = kind == _kind
		VI.tint_button(b, VI.GOLD if kind == _kind else VI.INK_DIM)
	var total_ready: int = gs.collections.unclaimed_count()
	_claim_all.text = "RECLAMAR TODO (%d)" % total_ready if total_ready > 0 else "NADA PARA RECLAMAR"
	_claim_all.disabled = total_ready == 0
	VI.tint_button(_claim_all, VI.GREEN if total_ready > 0 else VI.INK_DIM)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for cid in gs.collections.ids():
		var st2: Dictionary = gs.collections.state(String(cid))
		if String(st2["kind"]) == _kind or (_kind == "event" and String(st2["kind"]) == "custom"):
			_list.add_child(_make_card(st2))


func _make_card(st: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Col_" + String(st["id"])
	var ready_n := int(st["ready"])
	var style := VI.panel(0.95, true, VI.RADIUS_CARD)
	var accent: Color = VI.GREEN if ready_n > 0 else (VI.GOLD if bool(st["complete"]) else VI.VIOLET)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_label := Label.new()
	name_label.text = String(st["name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
	name_label.add_theme_color_override("font_color", accent)
	head.add_child(name_label)
	var count := Label.new()
	count.text = "%d / %d" % [int(st["owned"]), int(st["total"])]
	count.add_theme_font_size_override("font_size", VI.FONT_BODY)
	count.add_theme_color_override("font_color", VI.GOLD if bool(st["complete"]) else VI.INK)
	head.add_child(count)
	var desc := Label.new()
	desc.text = String(st["description"])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", VI.FONT_TINY)
	desc.add_theme_color_override("font_color", VI.INK_SOFT)
	box.add_child(desc)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.max_value = maxf(1.0, float(st["total"]))
	bar.value = float(st["owned"])
	bar.show_percentage = false
	box.add_child(bar)
	for tier in st["tiers"]:
		box.add_child(_make_tier_row(String(st["id"]), tier))
	var missing: Array = st["missing"]
	if not missing.is_empty() or not (st["owned_list"] as Array).is_empty():
		var toggle := Button.new()
		toggle.name = "Toggle"
		toggle.text = "OCULTAR PERSONAJES" if _expanded.get(st["id"], false) else "VER PERSONAJES (%d faltan)" % missing.size()
		toggle.custom_minimum_size = Vector2(0, 52)
		toggle.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		VI.tint_button(toggle, VI.INK_DIM)
		toggle.pressed.connect(_toggle_expand.bind(String(st["id"])))
		box.add_child(toggle)
		if _expanded.get(st["id"], false):
			for m in st["owned_list"]:
				box.add_child(_line("OK  %s" % String(m["name"]), VI.GREEN))
			for m in missing:
				box.add_child(_line("Falta: %s  -  %s" % [String(m["name"]), String(m["sources"])], VI.INK_SOFT))
	return card


func _make_tier_row(collection_id: String, tier: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var text := Label.new()
	var need_text := "%d miembros" % int(tier["need"])
	if bool(tier["requires_event"]):
		need_text += " + evento completado"
	text.text = "%s: %s" % [need_text, String(tier["text"])]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", VI.FONT_TINY)
	text.add_theme_color_override("font_color", VI.GOLD if not bool(tier["claimed"]) else VI.INK_DIM)
	row.add_child(text)
	var b := Button.new()
	b.name = "Claim_" + String(tier["id"])
	b.custom_minimum_size = Vector2(150, 52)
	b.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	if bool(tier["claimed"]):
		b.text = "RECLAMADA"
		b.disabled = true
	elif bool(tier["reached"]):
		b.text = "RECLAMAR"
		b.pressed.connect(_on_claim.bind(collection_id, String(tier["id"])))
	else:
		b.text = "EN CURSO"
		b.disabled = true
	VI.tint_button(b, VI.GREEN if bool(tier["reached"]) and not bool(tier["claimed"]) else VI.INK_DIM)
	row.add_child(b)
	return row


func _line(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", VI.FONT_TINY)
	l.add_theme_color_override("font_color", color)
	return l


func _toggle_expand(collection_id: String) -> void:
	_expanded[collection_id] = not bool(_expanded.get(collection_id, false))
	_rebuild()


func _on_claim(collection_id: String, tier_id: String) -> void:
	var done: Dictionary = GameState.collections.claim_tier(collection_id, tier_id)
	_rebuild()
	_feedback.text = "%s: %s" % [String(done["name"]), String(done["text"])] if not done.is_empty() else "Esa recompensa ya se ha reclamado."


func _on_claim_all() -> void:
	var done: Array = GameState.collections.claim_all()
	_rebuild()
	_feedback.text = "%d recompensas reclamadas." % done.size() if not done.is_empty() else "No habia nada que reclamar."


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")
