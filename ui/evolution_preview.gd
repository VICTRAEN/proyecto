extends RefCounted

## Tabla de ESTADISTICAS PREVISTAS de una evolucion (v15). Compartida por la pantalla
## EVOLUCION y la ficha del personaje: las dos ensenan exactamente lo mismo. Los numeros
## salen de core/preview.gd (las mismas estadisticas que usa el combate).

const VI := preload("res://ui/visual_identity.gd")
const Preview := preload("res://core/preview.gd")


## Devuelve un Control (vacio si el personaje no tiene evolucion posible).
static func make(gs, id: String) -> Control:
	var preview: Dictionary = Preview.evolution_preview(gs, id)
	var box := VBoxContainer.new()
	box.name = "StatPreview"
	if preview.is_empty():
		return box
	var head := Label.new()
	head.text = "ESTADISTICAS PREVISTAS"
	head.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	head.add_theme_color_override("font_color", VI.GOLD)
	box.add_child(head)
	var grid := GridContainer.new()
	grid.name = "PreviewGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	box.add_child(grid)
	for title in ["", "AHORA", "TRAS EVOLUCIONAR (Nv. %d)" % int(preview["after_level"]), "AL NIVEL %d" % int(preview["max_level"])]:
		var h := Label.new()
		h.text = title
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_theme_font_size_override("font_size", VI.FONT_TINY)
		h.add_theme_color_override("font_color", VI.INK_DIM)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(h)
	for r in preview["rows"]:
		var cells := [String(r["label"]), String(r["now_text"]), "%s  (%s)" % [String(r["after_now_text"]), String(r["delta_text"])], String(r["after_max_text"])]
		for i in cells.size():
			var l := Label.new()
			l.text = String(cells[i])
			l.add_theme_font_size_override("font_size", VI.FONT_TINY)
			l.add_theme_color_override("font_color", VI.INK if i != 3 else VI.GREEN)
			grid.add_child(l)
	var note := Label.new()
	note.text = String(preview["note"])
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", VI.FONT_TINY)
	note.add_theme_color_override("font_color", VI.INK_DIM)
	box.add_child(note)
	return box
