extends RefCounted

const StatBlock := preload("res://core/stat_block.gd")
const BattleMath := preload("res://core/battle_math.gd")
const CombatUnit := preload("res://core/combat_unit.gd")
const VI := preload("res://ui/visual_identity.gd")
const TypeColors := preload("res://ui/type_colors.gd")

## Cuerpo de la FICHA DE PERSONAJE, repartido en secciones.
##
## Existe para que ui/unit_info_panel.gd no crezca hasta ser un archivo gigante:
## aqui vive la construccion de las cuatro secciones que no cambian nunca
## (DATOS, HABILIDADES, LINKS, CATEGORIAS). La quinta, BATALLA, la sigue montando
## el panel porque necesita su nodo de contadores ya existente.
##
## Este archivo NO es un nodo: es un taller. El panel le pide una seccion y recibe
## un Control listo para meter dentro del scroll que ya tiene.
##
## Reglas que respeta:
##   - Ningun dato escrito a mano. Todo sale de GameState, de DB o del JSON del
##     personaje, que ya vienen resueltos dentro del CombatUnit o de su diccionario.
##   - Ningun color suelto: los tokens salen de res://ui/visual_identity.gd y el
##     color de TIPO de res://ui/type_colors.gd.
##   - BASE y ACTUAL nunca se confunden: BASE es stats.base_value (el JSON
##     escalado por nivel, sin mods) y ACTUAL es el getter de la unidad, que pasa
##     por core/stat_block.gd. El valor base no se sobrescribe en ningun sitio.
##   - El ROL del personaje no se pinta: es una clasificacion de diseno.

## Atributos que se pintan como fila base/actual, en este orden.
const ATTR_ROWS := ["max_hp", "atk", "def", "speed", "crit_rate", "dodge_rate"]

## Separacion estandar entre bloques de una seccion.
const SECTION_SEPARATION := 8


## --- Constructores de bloque --------------------------------------------------

static func section(spacing: int = SECTION_SEPARATION) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", spacing)
	return box


## Titulo de una subseccion (dorado, con el estilo de la casa).
static func block_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	VI.style_title(label, VI.FONT_SMALL)
	return label


static func note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	VI.style_note(label)
	return label


static func body_text(text: String, color: Color = VI.INK_SOFT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	label.add_theme_color_override("font_color", color)
	return label


## Fila de dos columnas: etiqueta a la izquierda, valor a la derecha.
static func key_value_row(key_text: String, value_text: String, value_color: Color = VI.INK) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var key := Label.new()
	key.text = key_text
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	key.add_theme_color_override("font_color", VI.INK_DIM)
	row.add_child(key)

	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_WORD
	value.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	value.add_theme_color_override("font_color", value_color)
	row.add_child(value)

	return row


## Un chip de una linea, del color que se le pase. Se usa para categoria y para
## el estado ACTIVO / INACTIVO de un link.
static func chip(text: String, color: Color, ratio: float = 0.30, alpha: float = 0.95) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(VI.RADIUS_CHIP)
	style.bg_color = Color(color.r * ratio, color.g * ratio, color.b * ratio, alpha)
	style.set_border_width_all(2)
	style.border_color = Color(color.r, color.g, color.b, 0.9)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", VI.FONT_TINY)
	label.add_theme_color_override("font_color", color)
	panel.add_child(label)

	return panel


static func stat_text(stat_name: String, value: float) -> String:
	if StatBlock.is_rate_stat(stat_name):
		return "%d%%" % int(round(value * 100.0))
	return str(int(round(value)))


## Texto de un efecto de link: "CRITICO +4%" o "VELOCIDAD +3%". El nombre de la
## stat y el formato del numero los decide core/stat_block.gd, que es el mismo
## sitio que los usa para el combate: aqui no se inventa ningun formato.
static func effect_text(effect: Dictionary) -> String:
	var stat_name := String(effect.get("stat", ""))
	return "%s %s" % [
		StatBlock.label(stat_name),
		StatBlock.mod_value_text(stat_name, String(effect.get("kind", "mult")), float(effect.get("value", 0.0))),
	]


## --- Seccion DATOS ------------------------------------------------------------

## Ficha "en crudo": identidad, progresion y las seis estadisticas con su valor
## BASE (sin mods) y su valor ACTUAL (base + pasivas + links + buffs).
## level/xp/needed los aporta el panel porque GameState es quien los sabe.
static func build_datos(unit: CombatUnit, data: Dictionary, level: int, xp: int, needed: int) -> Control:
	var box := section(10)

	box.add_child(block_title("IDENTIDAD"))
	box.add_child(key_value_row("NOMBRE", unit.display_name, VI.INK))
	box.add_child(key_value_row("TIPO", unit.type, TypeColors.color_for(unit.type)))
	box.add_child(key_value_row("RAREZA", unit.rarity, VI.rarity_color(unit.rarity)))
	if bool(data.get("evolved", false)):
		box.add_child(note("Forma evolucionada: su rareza efectiva es %s." % unit.rarity))
	var title_text := String(data.get("title", ""))
	if not title_text.is_empty():
		box.add_child(body_text(title_text))
	var genre := String(data.get("genre", ""))
	if not genre.is_empty():
		box.add_child(note(genre))

	box.add_child(block_title("PROGRESION"))
	box.add_child(key_value_row("NIVEL", "%d / %d" % [level, int(data.get("level_max", level))]))
	if needed <= 0:
		box.add_child(key_value_row("EXPERIENCIA", "nivel maximo", VI.GOLD))
	else:
		box.add_child(key_value_row("EXPERIENCIA", "%d / %d XP" % [xp, needed]))

	box.add_child(block_title("ESTADISTICAS"))
	box.add_child(note("BASE es el valor de la unidad a su nivel, sin nada aplicado. ACTUAL incluye pasivas, links y buffs."))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	_add_cell(grid, "", VI.INK_DIM, VI.FONT_TINY)
	_add_cell(grid, "BASE", VI.INK_DIM, VI.FONT_TINY, HORIZONTAL_ALIGNMENT_RIGHT)
	_add_cell(grid, "ACTUAL", VI.INK_DIM, VI.FONT_TINY, HORIZONTAL_ALIGNMENT_RIGHT)
	for stat_name in ATTR_ROWS:
		var base_text := stat_text(stat_name, unit.base_stat(stat_name))
		var current_text := stat_text(stat_name, current_value(unit, stat_name))
		_add_cell(grid, StatBlock.label(stat_name), VI.INK_DIM, VI.FONT_SMALL)
		_add_cell(grid, base_text, VI.INK_SOFT, VI.FONT_SMALL, HORIZONTAL_ALIGNMENT_RIGHT)
		# Un actual distinto del base se enciende en dorado: es la senal de que
		# algo (pasiva, link o buff) esta trabajando ahora mismo.
		_add_cell(grid, current_text, VI.GOLD if current_text != base_text else VI.INK, VI.FONT_SMALL, HORIZONTAL_ALIGNMENT_RIGHT)

	return box


## ACTUAL de una estadistica. Sale de las funciones de CombatUnit, que pasan por
## StatBlock: es el MISMO numero que usa el motor de combate. El critico, ademas,
## se lee de BattleMath.crit_chance, que es literalmente la tirada del dado.
static func current_value(unit: CombatUnit, stat_name: String) -> float:
	match stat_name:
		"max_hp":
			return unit.max_hp()
		"atk":
			return unit.attack()
		"def":
			return unit.defense()
		"speed":
			return unit.speed()
		"crit_rate":
			return BattleMath.crit_chance(unit)
		"dodge_rate":
			return unit.dodge_rate()
	if unit.stats == null:
		return 0.0
	return unit.stats.get_stat(stat_name)


## --- Seccion HABILIDADES ------------------------------------------------------

## TODAS las pasivas del personaje (un UR ensena dos: la mejorada y la extra) y su
## habilidad especial. Los textos salen del JSON; aqui no se escribe ninguna
## descripcion.
static func build_habilidades(unit: CombatUnit) -> Control:
	var box := section()
	# La lista sale de CombatUnit, que ya la trae resuelta: si un UR tiene DOS
	# pasivas activas, aqui salen las dos sin que nadie cuente cuantas hay.
	var passives := unit.passive_texts()
	var total := passives.size()
	var shown := 0
	for passive in passives:
		shown += 1
		# Con varias pasivas cada una se numera: sin numeros la segunda parecia
		# una repeticion de la primera.
		var heading := "PASIVA"
		if total > 1:
			heading = "PASIVA %d / %d" % [shown, total]
		box.add_child(block_title(heading))

		var name_label := Label.new()
		name_label.text = String(passive.get("name", ""))
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		name_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
		name_label.add_theme_color_override("font_color", VI.GOLD)
		box.add_child(name_label)

		var description := String(passive.get("description", ""))
		if not description.is_empty():
			box.add_child(body_text(description))

	if shown == 0:
		box.add_child(block_title("PASIVA"))
		box.add_child(note("Este personaje no tiene pasiva."))

	box.add_child(block_title("HABILIDAD ESPECIAL"))
	var special := unit.skill_info("special")
	if special.is_empty():
		box.add_child(note("Este personaje no tiene habilidad especial."))
		return box

	var special_name := Label.new()
	special_name.text = String(special.get("name", ""))
	special_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	special_name.add_theme_font_size_override("font_size", VI.FONT_BODY)
	special_name.add_theme_color_override("font_color", VI.BLUE)
	box.add_child(special_name)

	box.add_child(key_value_row("COSTE", "SP %d" % int(special.get("cost", 0)), VI.GOLD))
	box.add_child(key_value_row("OBJETIVO", String(special.get("target_label", ""))))
	var special_description := String(special.get("description", ""))
	if not special_description.is_empty():
		box.add_child(body_text(special_description))

	# ULTIMATE de forma (LR): solo aparece si la unidad la tiene en su forma actual.
	if unit.has_ultimate():
		var ult := unit.skill_info("ultimate")
		box.add_child(block_title("ULTIMATE  -  UNA VEZ POR COMBATE"))
		var ult_name := Label.new()
		ult_name.name = "UltimateName"
		ult_name.text = String(ult.get("name", ""))
		ult_name.autowrap_mode = TextServer.AUTOWRAP_WORD
		ult_name.add_theme_font_size_override("font_size", VI.FONT_BODY)
		ult_name.add_theme_color_override("font_color", VI.rarity_color("LR"))
		box.add_child(ult_name)
		box.add_child(key_value_row("COSTE", "SP %d" % int(ult.get("cost", 0)), VI.GOLD))
		box.add_child(key_value_row("OBJETIVO", String(ult.get("target_label", ""))))
		var ult_description := String(ult.get("description", ""))
		if not ult_description.is_empty():
			box.add_child(body_text(ult_description))

	return box


## --- Seccion LINKS ------------------------------------------------------------

## Todos los links del personaje, ACTIVOS o no. Los datos (nombre, descripcion,
## efectos, numero de portadores) los resuelve GameState.link_status; lo unico
## que se decide aqui es el color y si el texto va atenuado.
static func build_links(unit: CombatUnit, party_ids: Array) -> Control:
	var box := section(10)

	var status := GameState.link_status(unit.id)
	if status.is_empty():
		box.add_child(note("Este personaje no forma parte de ningun link."))
		return box

	var active_count := 0
	for link in status:
		if bool(link.get("active", false)):
			active_count += 1

	box.add_child(note("Un link se enciende cuando DOS personajes del equipo lo comparten. Activos ahora: %d / %d." % [active_count, status.size()]))

	for link in status:
		box.add_child(_link_card(link, unit, party_ids))

	return box


static func _link_card(link: Dictionary, unit: CombatUnit, party_ids: Array) -> Control:
	var active := bool(link.get("active", false))
	# ACTIVO en dorado y bien visible; INACTIVO en gris y atenuado. Es la unica
	# diferencia que el jugador necesita ver de un vistazo.
	var accent := VI.GOLD if active else VI.INK_DIM

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", VI.card(accent, false, "", active))

	var inner := section(6)
	card.add_child(inner)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	inner.add_child(header)

	var name_label := Label.new()
	name_label.text = String(link.get("name", link.get("id", "")))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
	name_label.add_theme_color_override("font_color", accent)
	header.add_child(name_label)

	header.add_child(chip("ACTIVO" if active else "INACTIVO", accent, 0.26 if active else 0.16, 0.95 if active else 0.75))

	var description := String(link.get("description", ""))
	if not description.is_empty():
		var description_label := body_text(description, VI.INK_SOFT if active else VI.INK_DIM)
		inner.add_child(description_label)

	for effect in link.get("effects", []):
		if effect is Dictionary:
			inner.add_child(body_text(effect_text(effect), accent if active else VI.INK_DIM))

	inner.add_child(note("En el equipo: %d." % int(link.get("holders", 0))))

	# Con quien se comparte. Barato de obtener y es justo lo que el jugador
	# necesita para decidir a quien poner al lado.
	var partners := link_partners(unit.id, String(link.get("id", "")), party_ids)
	if not partners.is_empty():
		inner.add_child(note("Lo comparte con: %s." % ", ".join(partners)))

	return card


## Nombres de los companeros de equipo que llevan el mismo link. Recorre
## GameState.party leyendo los links efectivos de cada personaje.
static func link_partners(id: String, link_id: String, party_ids: Array) -> Array:
	var names: Array = []
	for raw_id in party_ids:
		var partner := String(raw_id)
		if partner.is_empty() or partner == id:
			continue
		for raw_link in GameState.character_data(partner).get("links", []):
			if String(raw_link) == link_id:
				names.append(GameState.display_name(partner))
				break
	return names


## --- Seccion CATEGORIAS -------------------------------------------------------

## Chips con el NOMBRE visible de cada categoria (DB.get_category(id).name). Nunca
## se pinta el id crudo, que es un detalle de los datos.
static func build_categorias(categories: Array) -> Control:
	var box := section()
	box.add_child(block_title("CATEGORIAS"))
	if categories.is_empty():
		box.add_child(note("Este personaje no tiene categorias."))
		return box

	box.add_child(note("Las categorias agrupan personajes y alimentan los filtros de la coleccion."))

	# Dos columnas: en movil vertical un chip largo cabe sin desbordar el scroll.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	for raw_id in categories:
		var category_id := String(raw_id)
		var category := DB.get_category(category_id)
		var display := String(category.get("name", category_id))
		var entry := VBoxContainer.new()
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.add_theme_constant_override("separation", 2)
		entry.add_child(chip(display, VI.VIOLET))
		var description := String(category.get("description", ""))
		if not description.is_empty():
			var caption := note(description)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			entry.add_child(caption)
		grid.add_child(entry)

	return box


## --- Utilidades ---------------------------------------------------------------

static func _add_cell(grid: GridContainer, text: String, color: Color, font_size: int, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var cell := Label.new()
	cell.text = text
	cell.horizontal_alignment = align
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.autowrap_mode = TextServer.AUTOWRAP_WORD
	cell.add_theme_font_size_override("font_size", font_size)
	cell.add_theme_color_override("font_color", color)
	grid.add_child(cell)
