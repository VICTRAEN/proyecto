extends Control

const VI := preload("res://ui/visual_identity.gd")

## INFORMACION DE BANNER (v13). Ventana modal que ensena, para UN banner:
##   - la probabilidad real de cada rareza y las tasas propias (el duo);
##   - los personajes que pueden salir, con su probabilidad por tirada y hasta que
##     rareza pueden llegar (rareza maxima alcanzable);
##   - los destacados y las reglas del pity con el progreso actual.
## Todo se pide a GameState (banner_rate_table, banner_character_rate, pity_status,
## pity_rules_text): son las MISMAS funciones que usa summon(), asi que la
## informacion no puede contradecir a la logica.

signal closed

var banner_id := ""
var _body: VBoxContainer


static func open_on(host: Node, id: String) -> Control:
	var panel: Control = load("res://ui/banner_info_panel.gd").new()
	panel.name = "BannerInfoPanel"
	panel.banner_id = id
	host.add_child(panel)
	return panel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 50)
	add_child(margin)
	var window := PanelContainer.new()
	window.add_theme_stylebox_override("panel", VI.window(VI.GOLD, 0.98))
	margin.add_child(window)
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 18)
	window.add_child(inner)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	inner.add_child(col)
	var title := Label.new()
	title.name = "Title"
	title.text = "INFORMACION  -  %s" % String(DB.get_banner(banner_id).get("name", banner_id)).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.style_title(title, VI.FONT_BODY)
	col.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)
	var close := Button.new()
	close.name = "Close"
	close.text = "CERRAR"
	close.custom_minimum_size = Vector2(0, VI.TOUCH * 0.7)
	VI.tint_button(close, VI.BLUE)
	close.pressed.connect(func():
		closed.emit()
		queue_free())
	col.add_child(close)
	_fill()


func _line(text: String, color: Color = VI.INK, size: int = VI.FONT_SMALL) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_body.add_child(label)
	return label


static func pct(rate: float) -> String:
	var text := String.num(rate * 100.0, 2)
	if text.contains("."):
		text = text.rstrip("0").trim_suffix(".")
	return text + "%"


func _fill() -> void:
	var banner := DB.get_banner(banner_id)
	_line(String(banner.get("description", "")), VI.INK_SOFT)
	_line("Coste: %d gemas (x1)  -  %d gemas (x%d)" % [
		GameState.banner_cost(banner_id, 1), GameState.banner_cost(banner_id, 10),
		maxi(2, int(banner.get("multi_pulls", 10)))], VI.GOLD_LIGHT)
	_line("PROBABILIDAD POR TIRADA (cada tirada de una x10 es independiente)", VI.GOLD)
	for row in GameState.banner_rate_table(banner_id):
		var id := String(row["id"])
		var rarity := String(row["rarity"])
		if id.is_empty():
			var has_own := false
			for other in GameState.banner_rate_table(banner_id):
				if String(other["rarity"]) == rarity and not String(other["id"]).is_empty():
					has_own = true
			var label := "%s  %s" % [rarity, pct(float(row["rate"]) + _own_sum(rarity))]
			if has_own:
				label = "%s  %s en total   (resto del pool: %s)" % [rarity, pct(float(row["rate"]) + _own_sum(rarity)), pct(float(row["rate"]))]
			_line(label, VI.rarity_color(rarity))
		else:
			_line("      %s (tasa propia)  %s" % [GameState.display_name(id), pct(float(row["rate"]))], VI.rarity_color(rarity))
	_line("PITY", VI.GOLD)
	var st := GameState.pity_status(banner_id)
	_line(GameState.pity_rules_text(banner_id), VI.INK)
	if bool(st["enabled"]):
		_line("Progreso actual: %d/%d  -  la tirada %d seria la garantizada." % [
			int(st["counter"]), int(st["pulls"]), int(st["pulls"]) if int(st["until"]) == 1 else int(st["counter"]) + int(st["until"])], VI.GREEN)
	var featured: Array = banner.get("featured", [])
	if not featured.is_empty():
		var names := PackedStringArray()
		for id in featured:
			names.append(GameState.display_name(String(id)))
		_line("DESTACADOS: %s" % ", ".join(names), VI.GOLD)
	_line("PERSONAJES DISPONIBLES (probabilidad por tirada  -  rareza maxima alcanzable)", VI.GOLD)
	var pool := GameState.banner_pool(banner_id)
	var by_rarity: Dictionary = {}
	for id in pool:
		var rarity := String(DB.get_character(String(id)).get("rarity", ""))
		if not by_rarity.has(rarity):
			by_rarity[rarity] = []
		(by_rarity[rarity] as Array).append(String(id))
	var order: Array = VI.RARITY_ORDER.duplicate()
	order.reverse()
	for rarity in order:
		if not by_rarity.has(rarity):
			continue
		_line("%s  (%d personajes)" % [rarity, (by_rarity[rarity] as Array).size()], VI.rarity_color(String(rarity)))
		for id in by_rarity[rarity]:
			var tags := ""
			if featured.has(id):
				tags += "  * destacado"
			if (st["eligible"] as Array).has(id):
				tags += "  [cuenta para el pity]"
			_line("      %s  -  %s  -  llega a %s%s" % [
				GameState.display_name(String(id)), pct(GameState.banner_character_rate(banner_id, String(id))),
				GameState.max_reachable_rarity(String(id)), tags], VI.INK_SOFT, VI.FONT_TINY)
	_line("No salen de invocacion: formas evolucionadas (UR/LR de evolucion) ni unidades de evento gratuitas.", VI.INK_DIM, VI.FONT_TINY)


func _own_sum(rarity: String) -> float:
	var total := 0.0
	var featured := GameState.banner_featured_rates(banner_id)
	for id in featured.keys():
		if String(DB.get_character(String(id)).get("rarity", "")) == rarity:
			total += float(featured[id])
	return total
