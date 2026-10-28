extends RefCounted

const VI := preload("res://ui/visual_identity.gd")
const StatBlock := preload("res://core/stat_block.gd")
const FichaTabs := preload("res://ui/ficha_tabs.gd")

## Seccion DUPES de la ficha de personaje. Taller estatico (como ficha_tabs.gd): el
## panel le pide el Control y se lo coloca en su pestana. No calcula reglas: todo sale
## de GameState.dupe_status / dupe_stat_preview (los mismos numeros que usa el combate).
##
## Identidad propia: una fila de SEIS PIPS (Dupe 0..5) que se encienden en dorado,
## un contador de copias en cian y una tabla BASE / BONUS / ACTUAL / TRAS MEJORAR.
## Mejorar son dos pasos: CONSUMIR 1 COPIA abre una confirmacion y solo CONFIRMAR gasta.

const CYAN := Color(0.30, 0.86, 0.92, 1.0)


## `editable` false (en combate) deja la seccion en solo lectura.
## `confirming`: se esta mostrando la confirmacion. on_ask / on_confirm / on_cancel son
## los manejadores del panel; esta funcion no cambia ningun estado por si misma.
static func build(id: String, editable: bool, confirming: bool, on_ask: Callable, on_confirm: Callable, on_cancel: Callable) -> Control:
	var box := FichaTabs.section(12)
	box.name = "DupeBox"
	var status: Dictionary = GameState.dupe_status(id)
	var level := int(status.get("level", 0))
	var max_level := int(status.get("max_level", 0))
	var copies := int(status.get("copies", 0))

	box.add_child(FichaTabs.block_title("DUPES"))
	if max_level <= 0:
		box.add_child(FichaTabs.note("El sistema de Dupes no esta disponible."))
		return box
	box.add_child(FichaTabs.note("Las copias repetidas de ESTE personaje lo mejoran para siempre. No sirven para otros ni cambian su nivel, rareza o evolucion."))

	# Cabecera: DUPE n / max y pips.
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 14)
	box.add_child(head)
	var title := Label.new()
	title.name = "DupeLevelLabel"
	title.text = "DUPE %d / %d" % [level, max_level]
	title.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	title.add_theme_color_override("font_color", VI.GOLD if level > 0 else VI.INK_SOFT)
	head.add_child(title)
	var pips := HBoxContainer.new()
	pips.name = "DupePips"
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 8)
	box.add_child(pips)
	for i in range(1, max_level + 1):
		pips.add_child(_pip(i <= level, i))

	# Copias disponibles.
	var copies_row := HBoxContainer.new()
	copies_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(copies_row)
	var quality := String(status.get("quality", ""))
	var chip := _copies_chip("COPIAS %s DISPONIBLES: %d" % [quality, copies] if not quality.is_empty() else "COPIAS DISPONIBLES: %d" % copies, CYAN if copies > 0 else VI.INK_DIM)
	chip.name = "DupeCopies"
	copies_row.add_child(chip)
	# Libro de copias: total = disponibles + usadas (la unidad cuenta como una).
	var ledger_label := FichaTabs.note("Copias de este personaje: %s (la unidad cuenta como 1 usada)." % GameState.copy_ledger_text(id))
	ledger_label.name = "DupeLedger"
	box.add_child(ledger_label)

	# Tabla de estadisticas.
	var preview: Array = status.get("preview", [])
	if preview.is_empty():
		preview = GameState.dupe_stat_preview(id, level, level)
	var show_next := level < max_level
	var grid := GridContainer.new()
	grid.name = "DupeStats"
	grid.columns = 5 if show_next else 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	_cell(grid, "", VI.INK_DIM, VI.FONT_TINY, false)
	_cell(grid, "BASE", VI.INK_DIM, VI.FONT_TINY, true)
	_cell(grid, "BONUS", VI.INK_DIM, VI.FONT_TINY, true)
	_cell(grid, "ACTUAL", VI.INK_DIM, VI.FONT_TINY, true)
	if show_next:
		_cell(grid, "TRAS MEJORAR", CYAN, VI.FONT_TINY, true)
	for row in preview:
		var stat := String(row["stat"])
		var base_v := float(row["base"])
		var cur := float(row["current"])
		var nxt := float(row["next"])
		var bonus := cur - base_v
		_cell(grid, StatBlock.label(stat), VI.INK_DIM, VI.FONT_SMALL, false)
		_cell(grid, FichaTabs.stat_text(stat, base_v), VI.INK_SOFT, VI.FONT_SMALL, true)
		_cell(grid, _bonus_text(stat, bonus), VI.GOLD if absf(bonus) > 0.0001 else VI.INK_DIM, VI.FONT_SMALL, true)
		_cell(grid, FichaTabs.stat_text(stat, cur), VI.INK, VI.FONT_SMALL, true)
		if show_next:
			var improves := nxt > cur + 0.0001
			_cell(grid, FichaTabs.stat_text(stat, nxt), VI.GREEN if improves else VI.INK_DIM, VI.FONT_SMALL, true)

	# Mensaje y boton.
	var message := String(status.get("reason", ""))
	if level >= max_level:
		var maxed := Label.new()
		maxed.name = "DupeMessage"
		maxed.text = "DUPE MAXIMO ALCANZADO"
		maxed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		maxed.add_theme_font_size_override("font_size", VI.FONT_BODY)
		maxed.add_theme_color_override("font_color", VI.GOLD)
		box.add_child(maxed)
		# Copias SOBRANTES (ya no mejoran a este personaje): se pueden cambiar por monedas.
		var spare := GameState.dupe_overflow_copies(id)
		var rate := GameState.dupe_overflow_rate()
		if editable and spare > 0 and rate > 0:
			var gain := spare * rate
			if confirming:
				_confirm_row(box, "Convertir %d copia(s) sobrante(s) en %d monedas?\nNo se puede deshacer." % [spare, gain], on_confirm, on_cancel)
			else:
				box.add_child(FichaTabs.note("Te sobran %d copia(s): ya no pueden mejorar a este personaje." % spare))
				var convert := Button.new()
				convert.name = "DupeConvertButton"
				convert.text = "CONVERTIR %d COPIA(S)  >  +%d MONEDAS" % [spare, gain]
				convert.custom_minimum_size = Vector2(0, VI.TOUCH)
				VI.tint_button(convert, CYAN)
				convert.pressed.connect(on_ask)
				box.add_child(convert)
		return box
	if not editable:
		box.add_child(FichaTabs.note("Mejora los Dupes desde la ficha del personaje, fuera del combate."))
		return box
	var cost := int(status.get("cost", 1))
	if confirming and bool(status.get("ok", false)):
		_confirm_row(box, "Consumir %d copia(s) para subir a DUPE %d?\nEsta mejora es permanente." % [cost, level + 1], on_confirm, on_cancel)
		return box
	var button := Button.new()
	button.name = "DupeUpgradeButton"
	var ready := bool(status.get("ok", false))
	var eligible := bool(status.get("eligible", true))
	button.text = "CONSUMIR %d COPIA(S)  >  DUPE %d" % [cost, level + 1] if ready else ("SIN COPIAS SUFICIENTES" if eligible else "SOLO UNIDADES UR O LR")
	button.disabled = not ready
	button.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(button, VI.GOLD if ready else VI.INK_DIM)
	if ready:
		button.pressed.connect(on_ask)
	box.add_child(button)
	if not ready:
		var note := FichaTabs.note(message + (" Se consiguen invocando, en eventos, misiones y recompensas." if eligible else ""))
		note.name = "DupeMessage"
		box.add_child(note)
	return box


## Pregunta + CANCELAR / CONFIRMAR. Los nombres de nodo son parte de la interfaz probada.
static func _confirm_row(box: Control, text: String, on_confirm: Callable, on_cancel: Callable) -> void:
	var ask := Label.new()
	ask.name = "DupeConfirmText"
	ask.text = text
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ask.add_theme_font_size_override("font_size", VI.FONT_BODY)
	ask.add_theme_color_override("font_color", VI.GOLD)
	box.add_child(ask)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var cancel := Button.new()
	cancel.name = "DupeCancelButton"
	cancel.text = "CANCELAR"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(cancel, VI.BLUE)
	cancel.pressed.connect(on_cancel)
	row.add_child(cancel)
	var ok := Button.new()
	ok.name = "DupeConfirmButton"
	ok.text = "CONFIRMAR"
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(ok, VI.GOLD)
	ok.pressed.connect(on_confirm)
	row.add_child(ok)


## Etiqueta redonda de una sola linea. No se usa FichaTabs.chip porque esa ajusta el texto
## a varias lineas y, dentro de una fila centrada, el contenedor la deja con ancho minimo
## (el texto salia letra a letra en vertical).
static func _copies_chip(text: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := VI.chip(color, 0.95)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	label.add_theme_color_override("font_color", color)
	panel.add_child(label)
	return panel


static func _pip(lit: bool, index: int) -> Control:
	var pip := PanelContainer.new()
	pip.custom_minimum_size = Vector2(46, 46)
	var style := StyleBoxFlat.new()
	style.bg_color = VI.GOLD if lit else Color(0.10, 0.12, 0.20, 1.0)
	style.border_color = VI.GOLD if lit else VI.INK_DIM
	style.set_border_width_all(3)
	style.set_corner_radius_all(23)
	pip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = str(index)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	label.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02, 1.0) if lit else VI.INK_DIM)
	pip.add_child(label)
	return pip


static func _bonus_text(stat: String, bonus: float) -> String:
	if absf(bonus) < 0.0001:
		return "-"
	return "+" + FichaTabs.stat_text(stat, bonus)


static func _cell(grid: GridContainer, text: String, color: Color, font_size: int, right: bool) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(label)
