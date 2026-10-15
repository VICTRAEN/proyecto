extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const ROSTER_CARD := preload("res://ui/roster_card.tscn")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")

## MUTACIONES: el RITUAL.
##
## Esto no es un formulario: tirar una mutacion es un momento. Por eso va en DOS
## PASOS, y es importante que se respete:
##
##   1) MUTAR (en la pantalla)  -> ABRE LA VENTANA. No tira nada, no cobra nada.
##   2) MUTAR (dentro de la ventana) -> ES EL QUE TIRA de verdad.
##
## Asi un toque accidental no puede gastar monedas: hay que confirmar dentro del
## ritual. El segundo boton es el unico que llama a GameState.roll_mutation.
##
## QUE SE ENSENA, Y QUE NO
## La ventana explica el BONUS DE MUTACION sobre las estadisticas BASE. La columna
## BASE es el personaje a su nivel y su forma, sin pasivas, sin links, sin lider y
## sin buffs de combate: eso se lee en la ficha, no aqui. Los numeros los resuelve
## GameState.mutation_stat_preview (que usa StatBlock), nunca esta pantalla.
##
## Sin informacion repetida: el estado actual se ve UNA vez, en la pantalla. La
## ventana ensena el coste, lo que puede salir, el boton real y el resultado. La
## comparacion solo aparece cuando el rango CAMBIA de verdad.

const STAT_ICONS := {
	"max_hp": "VIDA",
	"atk": "ATAQUE",
	"def": "DEFENSA",
	"speed": "VELOCIDAD",
	"crit_rate": "CRITICO",
	"dodge_rate": "ESQUIVA",
}

@onready var title_label: Label = $Margin/Main/Title
@onready var wallet_label: Label = $Margin/Main/Wallet
@onready var selector: HBoxContainer = $Margin/Main/SelectorScroll/Selector
@onready var focal: PanelContainer = $Margin/Main/Focal
@onready var mutate_button: Button = $Margin/Main/MutateButton
@onready var back_button: Button = $Margin/Main/BackButton

var _selected_id := ""
## Informe de la ultima tirada. Solo lo usa la ventana.
var _last_report: Dictionary = {}
## Rango que tenia el personaje ANTES de la tirada, para comparar de verdad.
var _rank_before := ""

# --- La ventana (se construye por codigo y vive encima de todo) ---
var _modal: Control = null
var _modal_body: VBoxContainer = null
var _modal_character: Label = null
var _modal_confirm: Button = null
var _modal_again: Button = null
var _modal_close: Button = null
var _modal_flash: ColorRect = null

var _focal_portrait: Portrait = null
var _focal_name: Label = null
var _focal_meta: Label = null
var _focal_stats: VBoxContainer = null
var _focal_mutation: VBoxContainer = null


func _ready() -> void:
	_apply_identity()
	mutate_button.pressed.connect(_on_mutate_pressed)
	back_button.pressed.connect(_back)
	_build_focal()
	_build_modal()
	# La pantalla se pinta sola al abrirse. App tambien llama a refresh() al
	# mostrarla, pero si por lo que sea no lo hace, aqui no queda vacia.
	refresh()


## Aspecto estatico. El verde toxico manda: es el color de "algo esta cambiando".
func _apply_identity() -> void:
	VI.style_title(title_label, VI.FONT_BIG)
	wallet_label.add_theme_color_override("font_color", VI.GOLD)
	wallet_label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	var frame: StyleBoxFlat = VI.panel(0.95, true, VI.RADIUS_PANEL)
	frame.set_border_width_all(4)
	frame.border_color = Color(VI.GREEN.r, VI.GREEN.g, VI.GREEN.b, 0.9)
	focal.add_theme_stylebox_override("panel", frame)
	mutate_button.custom_minimum_size = Vector2(0.0, VI.TOUCH * 1.25)
	back_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	VI.tint_button(mutate_button, VI.GREEN)
	VI.tint_button(back_button, VI.BLUE)
	mutate_button.add_theme_font_size_override("font_size", VI.FONT_BIG)


func refresh() -> void:
	_ensure_selection()
	wallet_label.text = "MONEDAS %d" % GameState.coins
	_build_selector()
	_build_focal_content()
	_update_mutate_button()


## Si no hay personaje elegido (o el que habia ya no se tiene) se coge el primero.
func _ensure_selection() -> void:
	if not _selected_id.is_empty() and GameState.is_owned(_selected_id):
		return
	var owned: Array = GameState.roster_data()
	_selected_id = String((owned[0] as Dictionary).get("id", "")) if not owned.is_empty() else ""
	_last_report = {}
	_rank_before = ""


func _update_mutate_button() -> void:
	if _selected_id.is_empty():
		mutate_button.text = "MUTAR"
		mutate_button.disabled = true
		return
	mutate_button.text = "MUTAR  -  abrir el ritual"
	mutate_button.disabled = GameState.coins < DB.mutation_cost()


## --- Elige personaje (tira horizontal) ------------------------------------------

func _build_selector() -> void:
	_clear(selector)
	for raw_data in GameState.roster_data():
		var data: Dictionary = raw_data
		var id := String(data.get("id", ""))
		var mutation: Dictionary = GameState.mutation_report(id)
		var extra := "SIN MUTACION"
		if not mutation.is_empty():
			extra = "RANGO %s" % String(mutation.get("rank", "?"))
		var card = ROSTER_CARD.instantiate()
		selector.add_child(card)
		card.bind(data, id == _selected_id, extra, true)
		card.pressed.connect(_on_card_pressed)


func _on_card_pressed(data: Dictionary) -> void:
	if data.is_empty():
		return
	var id := String(data.get("id", ""))
	if id == _selected_id:
		return
	_selected_id = id
	_last_report = {}
	_rank_before = ""
	GameAudio.play("select")
	refresh()


## --- El foco: el personaje y sus stats BASE -------------------------------------

func _build_focal() -> void:
	# ALTAR del ritual: el personaje grande y centrado, nombre debajo y el resumen de
	# su mutacion. Es un sistema especial, no una ficha mas.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	focal.add_child(box)

	_focal_portrait = Portrait.new()
	_focal_portrait.custom_minimum_size = Vector2(0.0, 520.0)
	_focal_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_focal_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_focal_portrait)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	box.add_child(info)

	_focal_name = Label.new()
	_focal_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_focal_name.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	_focal_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_child(_focal_name)

	_focal_meta = Label.new()
	_focal_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.style_subtitle(_focal_meta)
	info.add_child(_focal_meta)

	_focal_stats = VBoxContainer.new()
	info.add_child(_focal_stats)

	box.add_child(HSeparator.new())

	_focal_mutation = VBoxContainer.new()
	_focal_mutation.add_theme_constant_override("separation", 6)
	box.add_child(_focal_mutation)


func _build_focal_content() -> void:
	_clear(_focal_stats)
	_clear(_focal_mutation)
	if _selected_id.is_empty():
		_focal_portrait.setup("", VI.INK_DIM, "short", "", "front", "")
		_focal_name.text = "Sin personajes"
		_focal_name.add_theme_color_override("font_color", VI.INK_DIM)
		_focal_meta.text = ""
		return

	var data := GameState.character_data(_selected_id)
	var tint: Color = TypeColors.color_for(String(data.get("type", "STR")))
	_focal_portrait.setup(_selected_id, tint, String(data.get("portrait_style", "short")),
		Portrait.art_path_from(data, "front"), "front", GameState.form_of(_selected_id))
	_focal_name.text = GameState.display_name(_selected_id)
	_focal_name.add_theme_color_override("font_color", tint)
	_focal_meta.text = "%s  -  NIVEL %d" % [
		GameState.rarity_of(_selected_id), GameState.level_of(_selected_id)]

	# En la pantalla solo va el RESUMEN de una linea; el detalle (stats base, pasiva
	# actual y resultado posible) vive en la ventana de mutacion, sin repetirse aqui.
	var report: Dictionary = GameState.mutation_report(_selected_id)
	var summary := Label.new()
	summary.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	if report.is_empty():
		summary.text = "Sin mutacion. Toca MUTAR para ver las opciones."
		summary.add_theme_color_override("font_color", VI.INK_SOFT)
		_focal_mutation.add_child(summary)
		return
	var rank_row := HBoxContainer.new()
	rank_row.add_theme_constant_override("separation", 12)
	_focal_mutation.add_child(rank_row)
	rank_row.add_child(_rank_badge(String(report.get("rank", "?"))))
	summary.text = _effects_text(report)
	summary.add_theme_color_override("font_color", VI.INK)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_row.add_child(summary)


## Rango en grande, con el color de la rareza mas alta cuanto mejor es el rango.
func _rank_badge(rank: String) -> Label:
	var badge := Label.new()
	badge.text = rank
	badge.custom_minimum_size = Vector2(96.0, 0.0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", VI.FONT_BIG)
	badge.add_theme_color_override("font_color", _rank_color(rank))
	return badge


## El color del rango sale de la identidad visual del juego: Z es lo mas alto.
func _rank_color(rank: String) -> Color:
	match rank:
		"Z":
			return VI.GOLD
		"SS", "S":
			return VI.rarity_color("UR")
		"A", "B":
			return VI.rarity_color("SSR")
		"C":
			return VI.rarity_color("SR")
		_:
			return VI.INK_SOFT


## "+10% ATAQUE  +10% VIDA"  -  y si es Z, ademas el ahorro de SP.
func _effects_text(report: Dictionary) -> String:
	var parts := PackedStringArray()
	for raw_stat in report.get("stats", []):
		var stat: Dictionary = raw_stat
		parts.append("%s %s" % [String(stat.get("text", "")), String(stat.get("label", ""))])
	var text := "  ".join(parts)
	var sp_cut := int(report.get("sp_reduction", 0))
	if sp_cut > 0:
		text += "\nSuper: -%d SP (minimo %d)" % [sp_cut, int(report.get("sp_cost_min", 1))]
	return text


func _value_text(entry: Dictionary, key: String) -> String:
	var value := float(entry.get(key, 0.0))
	if bool(entry.get("is_rate", false)):
		return "%d%%" % int(round(value * 100.0))
	return "%d" % int(round(value))


## --- LA VENTANA DEL RITUAL ------------------------------------------------------

func _build_modal() -> void:
	_modal = Control.new()
	_modal.name = "RitualModal"
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false
	add_child(_modal)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.04, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(margin)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame: StyleBoxFlat = VI.panel(0.98, true, VI.RADIUS_PANEL)
	frame.set_border_width_all(4)
	frame.border_color = Color(VI.GREEN.r, VI.GREEN.g, VI.GREEN.b, 0.95)
	frame.content_margin_left = 22.0
	frame.content_margin_right = 22.0
	frame.content_margin_top = 22.0
	frame.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", frame)
	margin.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var head := Label.new()
	head.text = "RITUAL DE MUTACION"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.style_title(head, VI.FONT_SECTION)
	head.add_theme_color_override("font_color", VI.GREEN)
	box.add_child(head)

	_modal_character = Label.new()
	_modal_character.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_character.add_theme_font_size_override("font_size", VI.FONT_BODY)
	box.add_child(_modal_character)

	_modal_body = VBoxContainer.new()
	_modal_body.add_theme_constant_override("separation", 10)
	box.add_child(_modal_body)

	_modal_confirm = Button.new()
	_modal_confirm.name = "ConfirmButton"
	_modal_confirm.custom_minimum_size = Vector2(0.0, VI.TOUCH * 1.2)
	_modal_confirm.add_theme_font_size_override("font_size", VI.FONT_BIG)
	VI.tint_button(_modal_confirm, VI.GREEN)
	_modal_confirm.pressed.connect(_on_confirm_mutation)
	box.add_child(_modal_confirm)

	_modal_again = Button.new()
	_modal_again.name = "AgainButton"
	_modal_again.text = "REPETIR EL RITUAL"
	_modal_again.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	_modal_again.visible = false
	VI.tint_button(_modal_again, VI.VIOLET)
	_modal_again.pressed.connect(_on_mutate_pressed)
	box.add_child(_modal_again)

	_modal_close = Button.new()
	_modal_close.name = "CloseButton"
	_modal_close.text = "CERRAR"
	_modal_close.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	VI.tint_button(_modal_close, VI.BLUE)
	_modal_close.pressed.connect(_close_modal)
	box.add_child(_modal_close)

	# Destello que acompana al resultado. Es un cambio de color, no un asset: se
	# puede sustituir por un efecto de verdad sin tocar la logica.
	_modal_flash = ColorRect.new()
	_modal_flash.color = Color(1, 1, 1, 0)
	_modal_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(_modal_flash)


## PASO 1: el boton de la pantalla. NO tira nada: abre la ventana.
func _on_mutate_pressed() -> void:
	if _selected_id.is_empty():
		return
	if GameState.coins < DB.mutation_cost() and not _modal_is_open():
		return
	_last_report = {}
	_open_ritual()


func _modal_is_open() -> bool:
	return _modal != null and _modal.visible


func _open_ritual() -> void:
	_build_ritual_intro()
	_modal_confirm.visible = true
	_modal_again.visible = false
	_modal.visible = true
	GameAudio.play("open")


func _close_modal() -> void:
	_modal.visible = false
	GameAudio.play("close")
	refresh()


## Lo que se ve ANTES de tirar: el personaje, sus stats BASE, la pasiva que aporta
## ahora y lo que puede salir. El resultado es AL AZAR, asi que "nueva mutacion"
## muestra los rangos posibles con su bonus (no se puede adelantar el resultado).
func _build_ritual_intro() -> void:
	_clear(_modal_body)
	var data := GameState.character_data(_selected_id)
	var tint: Color = TypeColors.color_for(String(data.get("type", "STR")))
	var rarity := GameState.rarity_of(_selected_id)
	var cost := DB.mutation_cost()
	_modal_character.text = ""
	_modal_character.visible = false
	_modal_confirm.text = "CONFIRMAR MUTACION  -  %d" % cost
	_modal_confirm.disabled = GameState.coins < cost

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	_modal_body.add_child(top)
	var art := Portrait.new()
	art.name = "RitualPortrait"
	art.custom_minimum_size = Vector2(300.0, 360.0)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(art)
	art.setup(_selected_id, tint, String(data.get("portrait_style", "short")),
		Portrait.art_path_from(data, "front"), "front", GameState.form_of(_selected_id))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	top.add_child(info)
	var name_label := Label.new()
	name_label.text = GameState.display_name(_selected_id)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	name_label.add_theme_color_override("font_color", tint)
	info.add_child(name_label)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 12)
	info.add_child(meta)
	meta.add_child(VI.rarity_badge(rarity, VI.FONT_BODY))
	var level := Label.new()
	level.text = "NIVEL %d" % GameState.level_of(_selected_id)
	level.add_theme_font_size_override("font_size", VI.FONT_BODY)
	level.add_theme_color_override("font_color", VI.INK_SOFT)
	meta.add_child(level)
	info.add_child(_section_title("STATS BASE"))
	var grid := GridContainer.new()
	grid.name = "BaseStats"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 3)
	info.add_child(grid)
	for entry in GameState.mutation_stat_preview(_selected_id):
		var stat: Dictionary = entry
		var stat_name := Label.new()
		stat_name.text = String(STAT_ICONS.get(String(stat["stat"]), String(stat["label"])))
		stat_name.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		stat_name.add_theme_color_override("font_color", VI.INK_SOFT)
		grid.add_child(stat_name)
		var stat_value := Label.new()
		stat_value.text = _value_text(stat, "base")
		stat_value.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		stat_value.add_theme_color_override("font_color", VI.INK)
		grid.add_child(stat_value)

	_modal_body.add_child(_section_title("PASIVA ACTUAL"))
	var report: Dictionary = GameState.mutation_report(_selected_id)
	var current := Label.new()
	current.name = "CurrentPassive"
	current.autowrap_mode = TextServer.AUTOWRAP_WORD
	current.add_theme_font_size_override("font_size", VI.FONT_BODY)
	if report.is_empty():
		current.text = "Sin mutacion: no aporta nada todavia."
		current.add_theme_color_override("font_color", VI.INK_DIM)
	else:
		current.text = "RANGO %s   %s" % [String(report.get("rank", "?")), _effects_text(report).replace("\n", "  ")]
		current.add_theme_color_override("font_color", _rank_color(String(report.get("rank", ""))))
	_modal_body.add_child(current)

	_modal_body.add_child(_section_title("NUEVA MUTACION"))
	var table := Label.new()
	table.name = "NewMutation"
	table.text = _odds_text()
	table.autowrap_mode = TextServer.AUTOWRAP_WORD
	table.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	table.add_theme_color_override("font_color", VI.INK)
	_modal_body.add_child(table)
	var note := Label.new()
	note.text = "El resultado es al azar y sustituye a la mutacion actual: solo hay una activa."
	note.add_theme_font_size_override("font_size", VI.FONT_TINY)
	note.add_theme_color_override("font_color", VI.INK_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_modal_body.add_child(note)


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", VI.FONT_TINY)
	label.add_theme_color_override("font_color", VI.GREEN)
	return label


## Estado actual en una linea, para saber si la tirada va a mejorar o empeorar.
func _state_text() -> String:
	var report: Dictionary = GameState.mutation_report(_selected_id)
	if report.is_empty():
		return "Ahora mismo NO tiene mutacion."
	return "Ahora mismo tiene RANGO %s: %s" % [
		String(report.get("rank", "?")), _effects_text(report).replace("\n", "  ")]


## Los rangos posibles, con su bonus, leidos del balance. No hay ningun numero
## escrito en esta pantalla.
func _odds_text() -> String:
	var parts := PackedStringArray()
	for raw in DB.mutation_ranks():
		var rank: Dictionary = raw
		parts.append("%s %s%%" % [String(rank.get("id", "?")), _trim_number(float(rank.get("bonus_percent", 0.0)))])
	return "Puede salir:  " + "   ".join(parts)


func _trim_number(value: float) -> String:
	if absf(value - roundf(value)) < 0.0001:
		return "%d" % int(round(value))
	return "%.1f" % value


## PASO 2: el boton REAL. Solo aqui se cobra y se tira.
func _on_confirm_mutation() -> void:
	if _selected_id.is_empty():
		return
	_rank_before = String(GameState.mutation_of(_selected_id).get("rank", ""))
	var report: Dictionary = GameState.roll_mutation(_selected_id)
	_last_report = report
	if bool(report.get("ok", false)):
		GameAudio.play("mutation")
	_show_result()


func _show_result() -> void:
	_clear(_modal_body)
	_modal_character.text = GameState.display_name(_selected_id)
	_modal_character.visible = true
	_modal_confirm.visible = false
	_modal_again.visible = true
	_modal_again.disabled = GameState.coins < DB.mutation_cost()

	if not bool(_last_report.get("ok", false)):
		var fail := Label.new()
		fail.text = String(_last_report.get("reason", "No se ha podido mutar."))
		fail.add_theme_font_size_override("font_size", VI.FONT_BODY)
		fail.add_theme_color_override("font_color", VI.RED)
		fail.autowrap_mode = TextServer.AUTOWRAP_WORD
		_modal_body.add_child(fail)
		_modal_again.visible = false
		return

	# El rango, enorme y protagonista: es lo que se viene a ver.
	var rank := String(_last_report.get("rank", "?"))
	var rank_label := Label.new()
	rank_label.text = "RANGO %s" % rank
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", VI.FONT_TITLE)
	rank_label.add_theme_color_override("font_color", _rank_color(rank))
	_modal_body.add_child(rank_label)

	var effects := Label.new()
	effects.text = _effects_text(_last_report)
	effects.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effects.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	effects.add_theme_color_override("font_color", VI.INK)
	effects.autowrap_mode = TextServer.AUTOWRAP_WORD
	_modal_body.add_child(effects)

	# Comparacion SOLO si el rango cambia de verdad. Si es el mismo, no hay nada
	# que comparar y no se ensena nada.
	var change := _rank_change_text()
	if not change.is_empty():
		var compare := Label.new()
		compare.text = change
		compare.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		compare.add_theme_font_size_override("font_size", VI.FONT_BODY)
		compare.add_theme_color_override("font_color", VI.GOLD)
		_modal_body.add_child(compare)

	_animate_reveal(rank_label, effects)


## "SUBE de D a A" / "BAJA de S a B". Vacio si el rango es el mismo.
func _rank_change_text() -> String:
	var now := String(_last_report.get("rank", ""))
	if _rank_before.is_empty() or now.is_empty() or now == _rank_before:
		return ""
	var delta := _rank_index(now) - _rank_index(_rank_before)
	if delta == 0:
		return ""
	return "%s de %s a %s" % ["SUBE" if delta > 0 else "BAJA", _rank_before, now]


func _rank_index(rank: String) -> int:
	var index := 0
	for raw in DB.mutation_ranks():
		if String((raw as Dictionary).get("id", "")) == rank:
			return index
		index += 1
	return -1


## Feedback: el rango entra creciendo y el panel da un destello. Sustituir esto por
## una animacion de verdad es cambiar SOLO esta funcion.
func _animate_reveal(rank_label: Control, effects: Control) -> void:
	await get_tree().process_frame
	# Repetir la tirada vuelve a montar la ventana y libera los nodos anteriores.
	# Sin esta comprobacion, la animacion de la tirada previa seguia viva y tocaba
	# un nodo ya liberado: el viaje de ida y vuelta por el arbol lo deja claro.
	if not is_instance_valid(rank_label) or not is_instance_valid(effects):
		return
	rank_label.pivot_offset = rank_label.size * 0.5
	rank_label.scale = Vector2(0.4, 0.4)
	rank_label.modulate = Color(1, 1, 1, 0)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(rank_label, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(rank_label, "modulate:a", 1.0, 0.2)
	effects.modulate = Color(1, 1, 1, 0)
	tween.tween_property(effects, "modulate:a", 1.0, 0.45).set_delay(0.2)
	if _modal_flash != null and is_instance_valid(_modal_flash):
		_modal_flash.color = Color(1, 1, 1, 0.35)
		var flash := create_tween()
		flash.tween_property(_modal_flash, "color:a", 0.0, 0.45)


func _back() -> void:
	# Si la ventana esta abierta, ESC/VOLVER cierra el ritual, no la pantalla.
	if _modal_is_open():
		_close_modal()
		return
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


## ESC cierra el ritual. Sin esto, una ventana modal a pantalla completa dejaria
## al jugador sin salida rapida.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _modal_is_open():
		_close_modal()
		get_viewport().set_input_as_handled()


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
