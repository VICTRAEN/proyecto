extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const PW := preload("res://ui/profile_widgets.gd")

## OBJETOS EQUIPABLES (X.2): inventario de objetos, equipar/retirar e invocacion de objetos.
##
## Cada objeto muestra SOLO: icono, nombre, rareza, descripcion y pasiva (mas quien lo
## lleva y los botones). No hay estadisticas ni ficha de personaje. Las reglas viven en
## GameState.equipment (core/equipment.gd); aqui solo se pinta y se llama a ella.
##
## Nodos estables: List, Feedback, Gems, SummonOne, SummonMulti, Item_<id>, Equip_<id>,
## Unequip_<id>, BackButton.

var _list: VBoxContainer
var _feedback: Label
var _gems: Label
var banner_id := "banner_objetos"


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	margin.add_child(main)
	var title := Label.new()
	title.text = "OBJETOS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(title)
	VI.screen_title(title, VI.GOLD)
	_gems = Label.new()
	_gems.name = "Gems"
	_gems.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gems.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	_gems.add_theme_color_override("font_color", VI.CYAN)
	main.add_child(_gems)
	_feedback = Label.new()
	_feedback.name = "Feedback"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	_feedback.add_theme_color_override("font_color", VI.GREEN)
	main.add_child(_feedback)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
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
	_gems.text = "%d gemas" % GameState.gems
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_build_summon_card()
	var ids: Array = GameState.equipment.owned_ids()
	var head := Label.new()
	head.text = "TUS OBJETOS (%d)" % ids.size()
	head.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	head.add_theme_color_override("font_color", VI.GOLD)
	_list.add_child(head)
	if ids.is_empty():
		var n := Label.new()
		n.text = "Todavia no tienes objetos. Consiguelos invocando aqui arriba o como recompensa rara de eventos."
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		n.add_theme_color_override("font_color", VI.INK_SOFT)
		_list.add_child(n)
	for id in ids:
		_list.add_child(_item_card(String(id)))


func _build_summon_card() -> void:
	var banner := DB.get_equipment_banner(banner_id)
	if banner.is_empty():
		return
	var card := PanelContainer.new()
	card.name = "SummonCard"
	card.add_theme_stylebox_override("panel", VI.window(VI.VIOLET, 0.96))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	col.add_child(_label(String(banner.get("name", "Banner de objetos")).to_upper(), VI.FONT_SECTION, VI.GOLD_LIGHT))
	col.add_child(_label(String(banner.get("description", "")), VI.FONT_SMALL, VI.INK_SOFT))
	var rates := GameState.equipment.banner_rates(banner_id)
	var parts: Array = []
	for r in GameState.equipment.RARITIES:
		if rates.has(r):
			parts.append("%s %s" % [r, _pct(float(rates[r]))])
	col.add_child(_label("Probabilidad por tirada:  " + "   ".join(parts), VI.FONT_TINY, VI.INK))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var cost: Dictionary = banner.get("cost", {})
	var multi := int(banner.get("multi_pulls", 10))
	for def in [["SummonOne", 1, int(cost.get("single", 0)), VI.BLUE], ["SummonMulti", multi, int(cost.get("multi", 0)), VI.GOLD]]:
		var b := Button.new()
		b.name = String(def[0])
		b.text = "x%d  -  %d gemas" % [int(def[1]), int(def[2])]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 84)
		b.add_theme_font_size_override("font_size", VI.FONT_BODY)
		VI.tint_button(b, def[3])
		b.pressed.connect(_on_summon.bind(int(def[1])))
		row.add_child(b)
	_list.add_child(card)


static func _pct(rate: float) -> String:
	var v := rate * 100.0
	return "%d%%" % int(round(v)) if absf(v - round(v)) < 0.005 else "%.1f%%" % v


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Icono del objeto: su PNG si existe; si no, un recuadro de reserva con la rareza.
static func icon_node(item_id: String, size: float) -> Control:
	var rarity := GameState.equipment.rarity_of(item_id)
	var path := String(DB.get_equipment(item_id).get("icon", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var t := TextureRect.new()
		t.texture = load(path) as Texture2D
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(size, size)
		return t
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(size, size)
	box.add_theme_stylebox_override("panel", VI.card(VI.rarity_color(rarity)))
	var l := Label.new()
	l.text = GameState.equipment.name_of(item_id).substr(0, 1).to_upper()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	box.add_child(l)
	return box


func _item_card(id: String) -> Control:
	var eq = GameState.equipment
	var data: Dictionary = DB.get_equipment(id)
	var rarity: String = eq.rarity_of(id)
	var card := PanelContainer.new()
	card.name = "Item_%s" % id
	card.add_theme_stylebox_override("panel", VI.card(VI.rarity_color(rarity)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(icon_node(id, 120))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var n: int = eq.count_of(id)
	col.add_child(_label("%s%s" % [String(data.get("name", id)), ("  x%d" % n) if n > 1 else ""], VI.FONT_BODY, VI.INK))
	var rar := _label("%s   -   %s" % [rarity, String(data.get("anime", ""))], VI.FONT_SMALL, VI.rarity_color(rarity))
	rar.name = "Rarity"
	col.add_child(rar)
	col.add_child(_label(String(data.get("description", "")), VI.FONT_TINY, VI.INK_SOFT))
	var passive: Dictionary = data.get("passive", {})
	var pas := _label("PASIVA - %s: %s" % [String(passive.get("name", "")), String(passive.get("description", ""))], VI.FONT_TINY, VI.CYAN)
	pas.name = "Passive"
	col.add_child(pas)
	var holders: Array = eq.holders_of(id)
	var who := PackedStringArray()
	for h in holders:
		who.append(GameState.display_name(String(h)))
	var holder_label := _label("Equipado en: %s" % ", ".join(who) if not who.is_empty() else "Sin equipar", VI.FONT_TINY, VI.GOLD if not who.is_empty() else VI.INK_DIM)
	holder_label.name = "Holders"
	col.add_child(holder_label)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	col.add_child(btns)
	var eb := Button.new()
	eb.name = "Equip_%s" % id
	eb.text = "EQUIPAR"
	eb.custom_minimum_size = Vector2(0, 64)
	eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eb.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	VI.tint_button(eb, VI.GREEN)
	eb.pressed.connect(_pick_character.bind(id))
	btns.add_child(eb)
	for h in holders:
		var ub := Button.new()
		ub.name = "Unequip_%s" % id if holders.size() == 1 else "Unequip_%s_%s" % [id, h]
		ub.text = "RETIRAR (%s)" % GameState.display_name(String(h))
		ub.custom_minimum_size = Vector2(0, 64)
		ub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ub.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		VI.tint_button(ub, VI.VIOLET)
		ub.pressed.connect(_on_unequip.bind(String(h)))
		btns.add_child(ub)
	return card


func _pick_character(item_id: String) -> void:
	var opts: Array = []
	var ordered: Array = []
	for c in GameState.party:
		if String(c) != "" and GameState.is_owned(String(c)) and not ordered.has(String(c)):
			ordered.append(String(c))
	for c in GameState.roster:
		if not ordered.has(String(c)):
			ordered.append(String(c))
	for c in ordered:
		var cur: String = GameState.equipment.item_of(String(c))
		var label := GameState.display_name(String(c))
		if not cur.is_empty():
			label += "   (lleva %s)" % GameState.equipment.name_of(cur)
		var check: Dictionary = GameState.equipment.can_equip(String(c), item_id)
		if not bool(check["ok"]):
			label += "   [no disponible]"
		opts.append({ "key": String(c), "label": label, "selected": cur == item_id })
	PW.open_picker(self, "EQUIPAR %s EN..." % GameState.equipment.name_of(item_id).to_upper(), opts, func(key):
		var res: Dictionary = GameState.equipment.equip(key, item_id)
		if bool(res["ok"]):
			GameState.save_game()
			refresh()
			_feedback.text = "%s ahora lleva %s." % [GameState.display_name(key), GameState.equipment.name_of(item_id)]
		else:
			_feedback.text = String(res["reason"]))


func _on_unequip(character_id: String) -> void:
	GameState.equipment.unequip(character_id)
	GameState.save_game()
	refresh()
	_feedback.text = "%s ya no lleva objeto." % GameState.display_name(character_id)


func _on_summon(count: int) -> void:
	var report: Dictionary = GameState.equipment.summon(banner_id, count)
	if not bool(report["ok"]):
		_feedback.text = String(report["reason"])
		return
	var names := PackedStringArray()
	for id in report["results"]:
		names.append("%s (%s)%s" % [GameState.equipment.name_of(String(id)), GameState.equipment.rarity_of(String(id)), " NUEVO" if (report["new"] as Array).has(id) else ""])
	refresh()
	_feedback.text = "Obtenido: " + ", ".join(names)


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")
