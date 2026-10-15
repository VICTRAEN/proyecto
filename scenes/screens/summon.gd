extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const CardTile := preload("res://ui/card_tile.gd")
const ROSTER_CARD := preload("res://ui/roster_card.tscn")
const SummonFx := preload("res://ui/summon_fx.gd")
const SummonReveal := preload("res://ui/summon_reveal.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")

## INVOCAR: el GACHA de verdad.
##
## Todo sale de los datos del banner (res://data/banners/<id>.json): el coste de
## una tirada, el de la decena y las PROBABILIDADES. Aqui no hay ningun numero de
## gacha escrito: cambiar el banner cambia el precio y las tasas.
##
## La tirada la hace GameState.summon(banner, count), que:
##   - cobra las gemas UNA vez y solo si llegan,
##   - hace `count` tiradas INDEPENDIENTES (cada posicion su propia probabilidad,
##     asi que una multi de 10 son 10 tiradas del 15% de SSR, no una),
##   - mete cada personaje por add_character, que es el mismo sitio que usa el
##     resto del juego (nuevo -> entra en el roster; repetido -> suma duplicado).
## La pantalla solo PINTA el informe que le devuelve.

@onready var main: VBoxContainer = $Margin/Main
@onready var banner_row: HBoxContainer = $Margin/Main/BannerRow
@onready var gems_label: Label = $Margin/Main/Coins
@onready var cost_label: Label = $Margin/Main/Cost
@onready var info_label: Label = $Margin/Main/Info
@onready var single_button: Button = $Margin/Main/Buttons/SingleButton
@onready var multi_button: Button = $Margin/Main/Buttons/MultiButton
@onready var back_button: Button = $Margin/Main/BackButton

## Banner en uso. Si el jugador no ha elegido ninguno, se coge el primero de los
## que hay en datos: el banner es un archivo, no una constante del script.
var _banner_id := ""
## Resumen de la ultima invocacion. Se conserva al repintar (antes refresh() lo pisaba).
var _summary_text := ""
var _results_scroll: ScrollContainer = null
var _results_grid: GridContainer = null
var _reveal: Control = null
var _animating := false


func _ready() -> void:
	_apply_identity()
	single_button.pressed.connect(_on_roll.bind(1))
	multi_button.pressed.connect(_on_roll.bind(10))
	back_button.pressed.connect(_back)
	_build_results_area()
	_build_stage()
	refresh()
	# Si el juego se cerro a mitad de una secuencia, se retoma donde se quedo: los
	# resultados ya estaban pagados y entregados, asi que no se tira ni se cobra nada.
	if GameState.has_pending_reveal():
		call_deferred("_begin_reveal")


func _apply_identity() -> void:
	VI.style_title($Margin/Main/Title, VI.FONT_BIG)
	VI.style_note($Margin/Main/BannerTitle)
	VI.style_subtitle(gems_label)
	VI.style_subtitle(cost_label)
	VI.style_note(info_label)
	VI.tint_button(single_button, VI.BLUE)
	VI.tint_button(multi_button, VI.GOLD)
	VI.tint_button(back_button, VI.BLUE)
	back_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)


## Zona de resultados, construida por codigo para no depender de la escena: una
## rejilla con scroll donde caen las cartas de la invocacion.
func _build_results_area() -> void:
	_results_scroll = ScrollContainer.new()
	_results_scroll.name = "ResultsScroll"
	_results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(_results_scroll)
	# Va justo antes de los botones: la rejilla crece y los botones quedan al pie.
	var buttons := main.get_node_or_null("Buttons")
	if buttons != null:
		main.move_child(_results_scroll, buttons.get_index())
	_results_grid = GridContainer.new()
	_results_grid.name = "ResultsGrid"
	_results_grid.columns = 5
	_results_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_grid.add_theme_constant_override("h_separation", 8)
	_results_grid.add_theme_constant_override("v_separation", 8)
	_results_scroll.add_child(_results_grid)


func refresh() -> void:
	if _banner_id.is_empty():
		_banner_id = _default_banner_id()
	var banner := DB.get_banner(_banner_id)
	gems_label.text = "GEMAS %d" % GameState.gems
	if banner.is_empty():
		cost_label.text = ""
		banner_row.visible = false
		info_label.text = "No hay ningun banner cargado en res://data/banners/."
		single_button.disabled = true
		multi_button.disabled = true
		return
	var single_cost := GameState.banner_cost(_banner_id, 1)
	var multi_cost := GameState.banner_cost(_banner_id, 10)
	var pulls := maxi(2, int(banner.get("multi_pulls", 10)))
	single_button.text = "x1 INVOCACION\n%d gemas" % single_cost
	multi_button.text = "x%d INVOCACIONES\n%d gemas" % [pulls, multi_cost]
	cost_label.text = "%s  -  %s" % [
		String(banner.get("name", _banner_id)),
		String(banner.get("description", "")),
	]
	# El boton se apaga si no llega, y ademas lo dice: no se finge un gacha.
	single_button.disabled = GameState.gems < single_cost
	multi_button.disabled = GameState.gems < multi_cost
	if not _summary_text.is_empty():
		info_label.text = _summary_text
	elif GameState.gems < single_cost:
		info_label.text = "Te faltan gemas para invocar."
	else:
		info_label.text = "Toca x1 o x%d. Cada posicion tira su propia probabilidad." % pulls
	_refresh_stage(banner)


## Escaparate del banner: los personajes DESTACADOS que declara su JSON. Si el
## banner no destaca a nadie, se ensenan los primeros del pool.
## ESCENARIO DEL BANNER: el banner es el protagonista. Marquesina con su nombre y las
## tasas, los personajes DESTACADOS grandes de cuerpo entero con el marco de su
## rareza, y selector de banners arriba. Al invocar, las cartas ocupan su lugar.
var _stage: PanelContainer = null
var _stage_title: Label = null
var _stage_rates: Label = null
var _stage_row: HBoxContainer = null
var _tabs: HBoxContainer = null
var _show_stage_button: Button = null
var _has_results := false


func _build_stage() -> void:
	banner_row.visible = false
	# El espaciador "Grow" competia con el escenario por el alto libre y dejaba la
	# mitad de la pantalla vacia: ahora el escenario del banner ocupa todo.
	var grow := get_node_or_null("Margin/Main/Grow")
	if grow != null:
		grow.visible = false
	var index := banner_row.get_index()
	_tabs = HBoxContainer.new()
	_tabs.name = "BannerTabs"
	_tabs.add_theme_constant_override("separation", 8)
	main.add_child(_tabs)
	main.move_child(_tabs, index)
	_stage = PanelContainer.new()
	_stage.name = "BannerStage"
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_stage)
	main.move_child(_stage, index + 1)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_stage.add_child(v)
	_stage_title = Label.new()
	_stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_title.add_theme_font_size_override("font_size", VI.FONT_BIG)
	_stage_title.add_theme_color_override("font_color", VI.GOLD)
	_stage_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_stage_title.add_theme_constant_override("outline_size", 10)
	v.add_child(_stage_title)
	_stage_rates = Label.new()
	_stage_rates.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_rates.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	_stage_rates.add_theme_color_override("font_color", VI.INK_SOFT)
	v.add_child(_stage_rates)
	_stage_row = HBoxContainer.new()
	_stage_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_row.add_theme_constant_override("separation", 16)
	_stage_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_stage_row)
	_show_stage_button = Button.new()
	_show_stage_button.name = "ShowStageButton"
	_show_stage_button.text = "VER BANNER"
	_show_stage_button.custom_minimum_size = Vector2(0, 70)
	VI.tint_button(_show_stage_button, VI.VIOLET)
	_show_stage_button.pressed.connect(_on_show_stage)
	_show_stage_button.visible = false
	main.add_child(_show_stage_button)
	main.move_child(_show_stage_button, _stage.get_index() + 1)


func _on_show_stage() -> void:
	_has_results = false
	_summary_text = ""
	_clear_results()
	refresh()


func _refresh_stage(banner: Dictionary) -> void:
	_stage.visible = not _has_results
	_results_scroll.visible = _has_results
	_show_stage_button.visible = _has_results
	_stage_title.text = String(banner.get("name", _banner_id)).to_upper()
	var rates := GameState.banner_rates(_banner_id)
	var parts := PackedStringArray()
	var order: Array = VI.RARITY_ORDER.duplicate()
	order.reverse()
	var featured_rates := GameState.banner_featured_rates(_banner_id)
	for rarity in order:
		if rates.has(rarity):
			var text := "%s %s%%" % [rarity, _pct(float(rates[rarity]))]
			# Tasas propias dentro de la rareza (el duo en su banner), claramente dichas.
			for fid in featured_rates.keys():
				if String(DB.get_character(String(fid)).get("rarity", "")) == String(rarity):
					text += " (%s %s%%)" % [GameState.display_name(String(fid)), _pct(float(featured_rates[fid]))]
			parts.append(text)
	_stage_rates.text = "Probabilidad por tirada:   " + "    ".join(parts)
	# Presentacion propia del banner: "theme" en su JSON (color y lema). Un banner
	# sin tema usa el marco dorado de siempre.
	var theme = banner.get("theme", {})
	var themed: bool = theme is Dictionary and not (theme as Dictionary).is_empty()
	var accent: Color = Color.html(String((theme as Dictionary).get("accent", "#ffc856"))) if themed else VI.GOLD
	var accent2: Color = Color.html(String((theme as Dictionary).get("accent2", "#27e6d6"))) if themed else VI.GOLD
	_stage_title.add_theme_color_override("font_color", accent)
	if themed:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.04, 0.09, 0.96)
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(6)
		sb.border_color = accent
		sb.shadow_color = Color(accent2.r, accent2.g, accent2.b, 0.55)
		sb.shadow_size = 26
		sb.set_content_margin_all(14)
		_stage.add_theme_stylebox_override("panel", sb)
		_stage_title.text = "%s\n%s" % [String((theme as Dictionary).get("tagline", "")), _stage_title.text]
	else:
		_stage.add_theme_stylebox_override("panel", VI.rarity_card("SSR", false, true))
	for child in _stage_row.get_children():
		_stage_row.remove_child(child)
		child.queue_free()
	var ids: Array = banner.get("featured", [])
	if ids.is_empty():
		ids = GameState.banner_pool(_banner_id).slice(0, 2)
	var shown := 0
	for raw_id in ids:
		if shown >= 2:
			break
		var data := GameState.character_data(String(raw_id))
		if data.is_empty():
			continue
		var tint: Color = TypeColors.color_for(String(data.get("type", "STR")))
		var rarity := String(data.get("rarity", "SSR"))
		var holder := PanelContainer.new()
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_theme_stylebox_override("panel", VI.rarity_card(rarity, false, false))
		var col := VBoxContainer.new()
		holder.add_child(col)
		var art := Portrait.new()
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		art.custom_minimum_size = Vector2(0, 380 if ids.size() > 1 else 560)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(art)
		art.setup(String(raw_id), tint, String(data.get("portrait_style", "short")), Portrait.art_path_from(data, "front"), "front", "")
		var badge := VI.rarity_badge(rarity, VI.FONT_BODY)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(badge)
		var name_label := Label.new()
		name_label.text = String(data.get("name", raw_id))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
		name_label.add_theme_color_override("font_color", tint)
		col.add_child(name_label)
		var feat := Label.new()
		feat.text = "DESTACADO"
		feat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		feat.add_theme_font_size_override("font_size", VI.FONT_TINY)
		feat.add_theme_color_override("font_color", VI.GOLD)
		col.add_child(feat)
		_stage_row.add_child(holder)
		shown += 1
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	for raw in DB.all_banners():
		var b: Dictionary = raw
		var tab := Button.new()
		tab.text = String(b.get("name", b.get("id", ""))).to_upper()
		tab.toggle_mode = true
		tab.button_pressed = String(b.get("id", "")) == _banner_id
		tab.clip_text = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, 64)
		tab.add_theme_font_size_override("font_size", VI.FONT_TINY)
		VI.tint_button(tab, VI.GOLD if tab.button_pressed else VI.BLUE)
		tab.pressed.connect(_on_banner_tab.bind(String(b.get("id", ""))))
		_tabs.add_child(tab)


## 7.0 -> "7", 15.5 -> "15.5": porcentaje legible sin ceros de sobra.
func _pct(rate: float) -> String:
	var text := String.num(rate * 100.0, 1)
	return text.trim_suffix(".0")


func _rate_total(rates: Dictionary) -> float:
	var total := 0.0
	for key in rates.keys():
		total += float(rates[key])
	return total


func _on_banner_tab(banner_id: String) -> void:
	if banner_id == _banner_id:
		refresh()
		return
	_banner_id = banner_id
	_has_results = false
	_summary_text = ""
	_clear_results()
	refresh()


func _build_featured(banner: Dictionary) -> void:
	for child in banner_row.get_children():
		banner_row.remove_child(child)
		child.queue_free()
	var ids: Array = banner.get("featured", [])
	if ids.is_empty():
		ids = GameState.banner_pool(_banner_id).slice(0, 2)
	var shown := 0
	for raw_id in ids:
		if shown >= 2:
			break
		var data := GameState.character_data(String(raw_id))
		if data.is_empty():
			continue
		var card = ROSTER_CARD.instantiate()
		banner_row.add_child(card)
		card.bind(data, false, "DESTACADO", true)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shown += 1
	banner_row.visible = shown > 0


func _default_banner_id() -> String:
	var banners: Array = DB.all_banners()
	if banners.is_empty():
		return ""
	return String((banners[0] as Dictionary).get("id", ""))


## Invoca. Quien cobra, tira y guarda es GameState.summon; aqui solo se decide
## cuantas tiradas se piden y se ensena el informe.
func _on_roll(count: int) -> void:
	_summary_text = ""
	_clear_results()
	if _banner_id.is_empty():
		info_label.text = "No hay ningun banner disponible."
		return
	# Mientras haya una secuencia de revelado (o una animacion) en marcha no se acepta
	# otra invocacion: ni por el boton ni llamando a esta funcion.
	if _sequence_active():
		return
	var report: Dictionary = GameState.summon(_banner_id, count, true)
	if not bool(report.get("ok", false)):
		info_label.text = String(report.get("reason", "No se ha podido invocar."))
		refresh()
		return
	# La tirada YA esta hecha, cobrada y guardada junto a su secuencia pendiente; la
	# animacion solo la escenifica y despues se revelan los resultados UNO A UNO.
	_set_buttons_locked(true)
	var best := _best_rarity(report)
	_animating = true
	SummonFx.play(self, best, func():
		_animating = false
		_begin_reveal())


## Hay una animacion de invocacion o un revelado en marcha?
func _sequence_active() -> bool:
	return _animating or (_reveal != null and is_instance_valid(_reveal)) or GameState.has_pending_reveal()


## Abre el revelado individual a pantalla completa con los resultados ya fijados.
func _begin_reveal() -> void:
	if _reveal != null and is_instance_valid(_reveal):
		return
	_set_buttons_locked(true)
	_reveal = SummonReveal.start(self)
	if _reveal != null and is_instance_valid(_reveal):
		_reveal.finished.connect(_on_reveal_finished)


func _on_reveal_finished(summary: Dictionary) -> void:
	_reveal = null
	var count := int(summary.get("count", 0))
	if count > 0:
		_summary_text = "%d tiradas  -  %d gemas  -  %d nuevos, %d repetidos" % [
			count, int(summary.get("cost", 0)),
			int(summary.get("new_count", 0)), int(summary.get("duplicate_count", 0))]
	_set_buttons_locked(false)


## Mejor rareza del informe (la que manda en el color del portal).
func _best_rarity(report: Dictionary) -> String:
	var best := ""
	for entry in report.get("results", []):
		if not (entry is Dictionary):
			continue
		var rarity := String((entry as Dictionary).get("rarity", ""))
		if best.is_empty() or VI.rarity_rank(rarity) > VI.rarity_rank(best):
			best = rarity
	return best


func _set_buttons_locked(locked: bool) -> void:
	single_button.disabled = locked
	multi_button.disabled = locked
	if not locked:
		refresh()


## Pinta las cartas del informe y las va revelando una a una: es la secuencia de
## invocacion. Cada carta trae su personaje, su rareza, su imagen y su nombre, y
## la rareza se nota porque la carta se viste con su color.
func _show_results(report: Dictionary) -> void:
	_has_results = true
	var results: Array = report.get("results", [])
	var index := 0
	for entry in results:
		if not (entry is Dictionary):
			continue
		var data := GameState.character_data(String((entry as Dictionary).get("id", "")))
		if data.is_empty():
			continue
		# Cartas verticales como en la coleccion (arte front, marco de rareza y los
		# efectos de UR/LR): el resultado de una tirada se SIENTE segun lo que sale.
		var card: PanelContainer = CardTile.new()
		card.art_height = 400.0
		_results_grid.add_child(card)
		var extra := "NUEVO" if bool((entry as Dictionary).get("new", false)) else "REP."
		card.bind(data, false, extra)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# La carta espera su turno antes de aparecer.
		card.modulate.a = 0.0
		card.pivot_offset = Vector2(100.0, 250.0)
		card.scale = Vector2(0.9, 0.9)
		var tween := create_tween().set_parallel(true)
		var delay := 0.06 * float(index)
		tween.tween_property(card, "modulate:a", 1.0, 0.18).set_delay(delay)
		tween.tween_property(card, "scale", Vector2.ONE, 0.24).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		index += 1
	# Bestia de resumen: cuantas tiradas, cuanto ha costado y que ha salido.
	var best := ""
	for entry in results:
		if not (entry is Dictionary):
			continue
		var rarity := String((entry as Dictionary).get("rarity", ""))
		if VI.rarity_rank(rarity) >= VI.rarity_rank("SSR"):
			best = String((entry as Dictionary).get("name", ""))
			break
	var summary := "%d tiradas  -  %d gemas  -  %d nuevos, %d repetidos" % [
		int(report.get("count", 0)),
		int(report.get("cost", 0)),
		int(report.get("new_count", 0)),
		int(report.get("duplicate_count", 0)),
	]
	if not best.is_empty():
		summary += "   -   SSR: %s" % best
	_summary_text = summary
	info_label.text = summary
	_refresh_stage(DB.get_banner(_banner_id))


func _clear_results() -> void:
	if _results_grid == null:
		return
	for child in _results_grid.get_children():
		_results_grid.remove_child(child)
		child.queue_free()


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")
