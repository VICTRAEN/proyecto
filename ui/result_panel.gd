extends PanelContainer

const VisualIdentity := preload("res://ui/visual_identity.gd")

## Pantalla de RESULTADO del combate, contada como pantalla de RECOMPENSA.
##
## Solo PINTA. Quien paga una batalla sigue siendo GameState.grant_battle_rewards,
## llamado desde la escena de combate; este panel recibe el informe ya cobrado y lo
## presenta: XP, monedas, que personajes han subido de nivel, y la batalla nueva
## que se ha desbloqueado. En la derrota no se inventa nada: se dice que no hay
## recompensas.
##
## Vive en su propio archivo para que la escena de combate no siga creciendo: la
## logica de combate no toca nada de aqui.

## Cuanto dura la aparicion del panel y el ritmo con que entran sus filas.
const ENTER_TIME := 0.24
const ROW_STEP := 0.07

var title: Label = null
var stage_label: Label = null
var info_label: Label = null
var rewards: VBoxContainer = null

var _rows: Array = []


func _ready() -> void:
	title = get_node_or_null("VBox/ResultLabel")
	stage_label = get_node_or_null("VBox/StageLabel")
	info_label = get_node_or_null("VBox/ResultInfo")
	rewards = get_node_or_null("VBox/Rewards")
	if title != null:
		VisualIdentity.style_title(title, VisualIdentity.FONT_TITLE)
	if stage_label != null:
		VisualIdentity.style_note(stage_label)
	if info_label != null:
		VisualIdentity.style_subtitle(info_label)
	# Panel solido: es lo que tapa el combate, asi que no deja traslucir nada.
	var style := VisualIdentity.panel(0.98)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	add_theme_stylebox_override("panel", style)


## Presenta el resultado. report es el informe de GameState.grant_battle_rewards:
## xp, coins, characters (name, xp, level_before, level_after) y unlocked (ids).
func present(victory: bool, rounds: int, alive: int, total: int, report: Dictionary) -> void:
	if title != null:
		title.text = "VICTORIA" if victory else "DERROTA"
		title.add_theme_color_override("font_color", VisualIdentity.GOLD if victory else VisualIdentity.RED)
	if stage_label != null:
		var stage: Dictionary = GameState.current_stage()
		var stage_name := String(stage.get("name", ""))
		stage_label.text = stage_name.to_upper() if not stage_name.is_empty() else ""
	if info_label != null:
		info_label.text = "Rondas: %d    En pie: %d / %d" % [rounds, alive, total]
	_clear_rows()
	if victory:
		_fill_victory(report)
	else:
		_fill_defeat()
	_play_entrance()


## Victoria: lo primero lo que se gana, despues quien sube de nivel y, si la
## victoria ha abierto la siguiente batalla, el aviso.
func _fill_victory(report: Dictionary) -> void:
	var xp := int(report.get("xp", 0))
	var coins := int(report.get("coins", 0))
	_add_row("XP OBTENIDA   +%d" % xp, VisualIdentity.GOLD, 34)
	_add_row("MONEDAS   +%d" % coins, VisualIdentity.GOLD, 30)

	var characters: Array = report.get("characters", [])
	for entry in characters:
		var name_text := String(entry.get("name", ""))
		var level_before := int(entry.get("level_before", 1))
		var level_after := int(entry.get("level_after", 1))
		if level_after > level_before:
			# Subida de nivel: se anuncia con el antes y el despues, que es lo que
			# el jugador quiere ver al terminar una batalla.
			_add_row(
				"%s    Nv. %d -> Nv. %d" % [name_text, level_before, level_after],
				VisualIdentity.GOLD,
				28,
				true
			)
		else:
			_add_row("%s    +%d XP" % [name_text, int(entry.get("xp", 0))], VisualIdentity.INK_SOFT, 24)

	# Objetos conseguidos (eventos y torres). El nombre ya viene resuelto en el
	# informe, asi que aqui no se lee ninguna clave del JSON.
	for entry in report.get("drops", []):
		if not (entry is Dictionary):
			continue
		_add_row(
			"%s   x%d" % [String(entry.get("name", "")), int(entry.get("amount", 0))],
			VisualIdentity.GOLD,
			26,
			true
		)

	# Lo que se acaba de abrir. El informe trae los NOMBRES ya resueltos, asi que
	# vale igual para una batalla suelta, un nivel de historia o un evento.
	var unlocked_names: Array = report.get("unlocked_names", [])
	if unlocked_names.is_empty():
		for raw_id in report.get("unlocked", []):
			var stage: Dictionary = DB.get_stage(String(raw_id))
			_add_row(
				"NUEVA BATALLA   %s" % String(stage.get("name", raw_id)).to_upper(),
				VisualIdentity.GREEN,
				28,
				true
			)
	else:
		for raw_name in unlocked_names:
			_add_row(
				"NUEVO   %s" % String(raw_name).to_upper(),
				VisualIdentity.GREEN,
				28,
				true
			)


## Derrota: sin premios y dicho claramente. No se muestran cifras a cero, porque
## un cero no es una recompensa.
func _fill_defeat() -> void:
	_add_row("Sin recompensas", VisualIdentity.INK_SOFT, 30)
	_add_row("La derrota no da XP ni monedas.", VisualIdentity.INK_DIM, 22)


func _clear_rows() -> void:
	if rewards == null:
		return
	for child in rewards.get_children():
		rewards.remove_child(child)
		child.queue_free()
	_rows = []


func _add_row(text: String, color: Color, font_size: int, highlight: bool = false) -> Label:
	if rewards == null:
		return null
	var row := Label.new()
	row.text = text
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_theme_font_size_override("font_size", font_size)
	row.add_theme_color_override("font_color", color)
	if highlight:
		# Las filas con premio (subida de nivel, batalla nueva) se leen de un
		# golpe: contorno oscuro y un latido al aparecer.
		row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		row.add_theme_constant_override("outline_size", 6)
	rewards.add_child(row)
	_rows.append(row)
	return row


## Aparicion: el panel entra con un golpe suave de escala y las filas van
## apareciendo de una en una, de arriba abajo. Es lo que hace que el premio se lea
## en orden (XP, monedas, niveles, batalla nueva) en vez de aparecer de golpe.
func _play_entrance() -> void:
	pivot_offset = size * 0.5
	modulate = Color(1, 1, 1, 0)
	scale = Vector2(0.94, 0.94)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, ENTER_TIME)
	tween.tween_property(self, "scale", Vector2.ONE, ENTER_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var index := 0
	for row in _rows:
		row.modulate = Color(1, 1, 1, 0)
		row.pivot_offset = row.size * 0.5
		row.scale = Vector2(0.92, 0.92)
		var delay := ENTER_TIME + ROW_STEP * float(index)
		var row_tween := create_tween().set_parallel(true)
		row_tween.tween_property(row, "modulate:a", 1.0, 0.22).set_delay(delay)
		row_tween.tween_property(row, "scale", Vector2.ONE, 0.26).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		index += 1
