extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const ROSTER_CARD := preload("res://ui/roster_card.tscn")
const UnitInfoPanel := preload("res://ui/unit_info_panel.gd")
const CardTile := preload("res://ui/card_tile.gd")
const TitleBanner := preload("res://ui/title_banner.gd")
const ThemeFactory := preload("res://ui/theme_factory.gd")

## COLECCION: los personajes que TIENE el jugador, con filtros y ordenacion.
##
## La lista no se recorre en un orden fijo: filtrar y ordenar es rehacerla a
## partir de GameState.roster_data(). Con 4 personajes o con 150 el trabajo es el
## mismo y la rejilla no cambia, que es lo que se pedia para el futuro.
##
## Que personajes existen sale de GameState.roster, NO de DB.characters: el dia
## que haya invocaciones, un personaje que el jugador aun no tiene no debe salir
## en su coleccion. Los datos de cada uno (nombre, tipo, rareza, stats) siguen
## saliendo del JSON.
##
## Tocar una tarjeta abre su ficha completa: el mismo panel del combate, sin la
## seccion de estadisticas de batalla porque aqui no hay batalla.
##
## ASPECTO: la pantalla se viste con res://ui/visual_identity.gd (titulo, notas,
## panel de filtros, chips de filtro y boton de volver). No hay ningun color
## escrito aqui: todo sale de los tokens y constructores de la identidad visual.
##
## Esta pantalla ensena nombre, tipo, rareza y nivel. El ROL de un personaje es
## un dato interno de diseno y no se pinta en la interfaz de jugador.

const ALL := "TODOS"
## Rarezas de mejor a peor. Es el orden de los filtros y el criterio de la
## ordenacion por rareza; una rareza que no este aqui acaba al final.
const RARITY_ORDER := ["LR", "UR", "SSR", "SR", "R", "N"]

const SORT_RARITY := 0
const SORT_LEVEL := 1
const SORT_NAME := 2
const SORT_TYPE := 3

@onready var grid: GridContainer = $Margin/Main/Scroll/Grid
@onready var scroll: ScrollContainer = $Margin/Main/Scroll
@onready var count_label: Label = $Margin/Main/Header/Count
@onready var filters_panel: PanelContainer = $Margin/Main/FiltersPanel
@onready var filter_label: Label = $Margin/Main/FiltersPanel/FiltersBox/FilterLabel
@onready var rarity_row: HBoxContainer = $Margin/Main/FiltersPanel/FiltersBox/RarityRow
@onready var type_title: Label = $Margin/Main/FiltersPanel/FiltersBox/TypeTitle
@onready var type_row: HBoxContainer = $Margin/Main/FiltersPanel/FiltersBox/TypeRow
@onready var category_title: Label = $Margin/Main/FiltersPanel/FiltersBox/CategoryTitle
@onready var category_row: HBoxContainer = $Margin/Main/FiltersPanel/FiltersBox/CategoryRow
@onready var sort_label: Label = $Margin/Main/FiltersPanel/FiltersBox/SortRow/SortLabel
@onready var sort_option: OptionButton = $Margin/Main/FiltersPanel/FiltersBox/SortRow/SortOption
@onready var back_button: Button = $Margin/Main/BackButton
@onready var info_panel: UnitInfoPanel = $UnitInfoPanel

var _rarity_filter := ALL
var _type_filter := ALL
## Filtro de categoria. Guarda el NOMBRE visible, que es lo que el jugador toca;
## la traduccion a id la hace _category_matches leyendo GameState.
var _category_filter := ALL
## Nombres visibles de categoria por id, para no ensenar nunca el id crudo.
var _category_names: Dictionary = {}
var _sort_mode := SORT_RARITY
var _progress: ProgressBar = null


func _ready() -> void:
	# Rejilla de una columna: las tarjetas de la coleccion son filas con icono,
	# nombre, tipo, rareza y nivel, y a este tamano se leen mejor asi.
	# COLECCION = parrilla de cartas: 3 columnas con el arte como protagonista.
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	_apply_identity()
	_compact_filters()
	back_button.pressed.connect(_back)
	_setup_sort()
	info_panel.changed.connect(_build)


## Todo el aspecto estatico de la pantalla, en un solo sitio. Los colores y
## tamanos salen de la identidad visual; aqui solo se decide que papel juega
## cada nodo.
func _apply_identity() -> void:
	# CABECERA: placa violeta con el titulo, el contador y una barra de progreso de
	# la coleccion (cuanto llevas de cuanto hay).
	var header: VBoxContainer = count_label.get_parent()
	var banner := TitleBanner.make("COLECCION", "", VI.VIOLET, VI.FONT_BIG)
	banner.name = "Title"
	header.add_child(banner)
	header.move_child(banner, 0)
	VI.style_subtitle(count_label)
	count_label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	_progress = ProgressBar.new()
	_progress.name = "CollectionProgress"
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 14)
	_progress.add_theme_stylebox_override("fill", ThemeFactory.bar_fill(VI.GOLD))
	header.add_child(_progress)
	filters_panel.add_theme_stylebox_override("panel", VI.panel(0.80, true))
	for label in [filter_label, type_title, category_title, sort_label]:
		VI.style_title(label, VI.FONT_SMALL)
	# La rejilla vive en un contenedor propio para que las tarjetas no se mezclen
	# con el fondo de la pantalla.
	scroll.add_theme_stylebox_override("panel", VI.panel(0.28, false))
	VI.tint_button(sort_option, VI.BLUE)
	VI.tint_button(back_button, VI.BLUE)
	back_button.custom_minimum_size = Vector2(0, VI.TOUCH)


## Filtros COMPACTOS: la rareza siempre a la vista (una fila) y el resto detras de un
## boton MAS FILTROS. Tipo y categoria van en filas que se desplazan de lado en vez
## de desbordar la pantalla. Antes el panel se comia toda la pantalla y las cartas
## quedaban aplastadas.
var _advanced: Array = []
var _filters_toggle: Button = null


func _compact_filters() -> void:
	var box: VBoxContainer = filters_panel.get_node("FiltersBox")
	for row: HBoxContainer in [type_row, category_row]:
		var holder := ScrollContainer.new()
		holder.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		holder.custom_minimum_size = Vector2(0, 74)
		var index: int = (row as Node).get_index()
		box.remove_child(row)
		box.add_child(holder)
		box.move_child(holder, index)
		holder.add_child(row)
		row.size_flags_horizontal = Control.SIZE_FILL
		_advanced.append(holder)
	var sort_row: Node = sort_label.get_parent()
	_advanced.append_array([type_title, category_title, sort_row])
	filter_label.text = "RAREZA"
	_filters_toggle = Button.new()
	_filters_toggle.name = "FiltersToggle"
	_filters_toggle.text = "MAS FILTROS"
	_filters_toggle.toggle_mode = true
	_filters_toggle.custom_minimum_size = Vector2(0, 64)
	_filters_toggle.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	VI.tint_button(_filters_toggle, VI.VIOLET)
	_filters_toggle.toggled.connect(_on_filters_toggled)
	box.add_child(_filters_toggle)
	_on_filters_toggled(false)


func _on_filters_toggled(open: bool) -> void:
	for node in _advanced:
		(node as Control).visible = open
	if _filters_toggle != null:
		_filters_toggle.text = "MENOS FILTROS" if open else "MAS FILTROS"


func refresh() -> void:
	_setup_filters()
	_build()


## --- Filtros y ordenacion --------------------------------------------------

func _setup_sort() -> void:
	sort_option.clear()
	sort_option.add_item("Rareza", SORT_RARITY)
	sort_option.add_item("Nivel", SORT_LEVEL)
	sort_option.add_item("Nombre", SORT_NAME)
	sort_option.add_item("Tipo", SORT_TYPE)
	sort_option.selected = 0
	sort_option.item_selected.connect(_on_sort_selected)


## Los filtros solo ofrecen lo que existe de verdad en la coleccion: con cuatro
## personajes no tiene sentido un boton de una rareza que nadie tiene. Al anadir
## personajes, los botones aparecen solos.
func _setup_filters() -> void:
	var roster: Array = GameState.roster_data()
	var rarities := {}
	var types := {}
	var seen_categories := {}
	for data in roster:
		rarities[String(data.get("rarity", "R"))] = true
		types[String(data.get("type", "?"))] = true
		for raw_id in data.get("categories", []):
			seen_categories[String(raw_id)] = true

	var rarity_options: Array = [ALL]
	for rarity in RARITY_ORDER:
		if rarities.has(rarity):
			rarity_options.append(rarity)
	_build_filter_row(rarity_row, rarity_options, _rarity_filter, _on_rarity_selected)

	var type_list: Array = types.keys()
	type_list.sort()
	_build_filter_row(type_row, [ALL] + type_list, _type_filter, _on_type_selected)

	# Categorias: solo las que tiene de verdad la coleccion, con su NOMBRE
	# visible (DB.get_category). Nada de id crudos ni de filtros que no devuelven
	# nada. Si la categoria filtrada desaparece del roster, el filtro vuelve a
	# TODAS para que la lista no se quede vacia sin explicacion.
	_category_names = {}
	var category_names: Array = []
	for raw_id in seen_categories.keys():
		var category := DB.get_category(String(raw_id))
		var display := String(category.get("name", String(raw_id)))
		_category_names[String(raw_id)] = display
		if not category_names.has(display):
			category_names.append(display)
	category_names.sort()
	if _category_filter != ALL and not category_names.has(_category_filter):
		_category_filter = ALL
	_build_filter_row(category_row, [ALL] + category_names, _category_filter, _on_category_selected)


func _build_filter_row(row: HBoxContainer, options: Array, selected_value: String, handler: Callable) -> void:
	_clear(row)
	for option in options:
		var text := String(option)
		var button := Button.new()
		button.text = text
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if row == rarity_row else Control.SIZE_SHRINK_BEGIN
		# Toggle sin grupo: al pulsar se cambia el filtro y la fila se vuelve a
		# construir con el estado nuevo, asi que nunca hay dos encendidos.
		button.toggle_mode = true
		button.button_pressed = text == selected_value
		button.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		# El filtro encendido va en dorado (lo importante) y los demas en azul.
		VI.tint_button(button, VI.GOLD if text == selected_value else VI.BLUE)
		button.pressed.connect(handler.bind(text))
		row.add_child(button)


func _build() -> void:
	_clear(grid)
	var all: Array = GameState.roster_data()
	# COPIAS: material aparte de la unidad, siempre en su calidad inicial. Una sola carta
	# por calidad y personaje: si la unidad esta en esa calidad lleva el contador x N en
	# su propia carta; si evoluciono (Gojo UR + 3 SSR) hay una carta SSR x3 aparte.
	var merged_counts := {}
	var separate: Array = []
	for stack in GameState.copy_stacks():
		if bool(stack["merged"]):
			merged_counts[String(stack["id"])] = int(stack["count"])
		else:
			separate.append(stack)
	var shown: Array = []
	for data in all:
		data["copy_count"] = int(merged_counts.get(String(data.get("id", "")), 0))
		if _matches(data):
			shown.append(data)
	var units_shown := shown.size()
	for stack in separate:
		var pile: Dictionary = GameState.character_data(String(stack["id"]))
		if pile.is_empty():
			continue
		pile["rarity"] = String(stack["quality"])
		pile["form_override"] = String(stack["quality"]).to_lower()
		pile["copy_only"] = true
		pile["copy_count"] = int(stack["count"])
		if _matches(pile):
			shown.append(pile)
	_sort_list(shown)

	# Contador "obtenidos / total": el dia que exista el gacha, un personaje que
	# este en los datos pero no en el roster no aparece y ademas se nota aqui.
	if units_shown == all.size():
		count_label.text = "%d / %d personajes. Toca uno para ver su ficha." % [
			GameState.owned_count(), GameState.total_count()]
	else:
		count_label.text = "%d de %d mostrados  -  %d / %d obtenidos" % [
			units_shown, all.size(), GameState.owned_count(), GameState.total_count()]

	if _progress != null:
		_progress.max_value = maxi(1, GameState.total_count())
		_progress.value = GameState.owned_count()

	for data in shown:
		var card: PanelContainer = CardTile.new()
		grid.add_child(card)
		card.bind(data, false, "")
		card.pressed.connect(_on_card_pressed)


func _matches(data: Dictionary) -> bool:
	if _rarity_filter != ALL and String(data.get("rarity", "R")) != _rarity_filter:
		return false
	if _type_filter != ALL and String(data.get("type", "?")) != _type_filter:
		return false
	if not _category_matches(data):
		return false
	return true


## El filtro de categoria se combina con los otros dos: un personaje sale solo si
## cumple los tres. La comparacion es por NOMBRE visible, que es lo que el boton
## ensena; el id se resuelve aqui con _category_names.
func _category_matches(data: Dictionary) -> bool:
	if _category_filter == ALL:
		return true
	for raw_id in data.get("categories", []):
		var key := String(raw_id)
		var display := String(_category_names.get(key, key))
		if display == _category_filter:
			return true
	return false


func _sort_list(list: Array) -> void:
	list.sort_custom(_compare)


## Comparador unico. El desempate (rareza y luego nombre) es lo que evita que la
## lista cambie de orden entre repintados cuando dos personajes empatan.
func _compare(a: Dictionary, b: Dictionary) -> bool:
	match _sort_mode:
		SORT_LEVEL:
			var la := int(a.get("level", 1))
			var lb := int(b.get("level", 1))
			if la != lb:
				return la > lb
		SORT_NAME:
			var na := String(a.get("name", ""))
			var nb := String(b.get("name", ""))
			if na != nb:
				return na < nb
		SORT_TYPE:
			var ta := String(a.get("type", ""))
			var tb := String(b.get("type", ""))
			if ta != tb:
				return ta < tb
		_:
			var ra := _rarity_rank(a)
			var rb := _rarity_rank(b)
			if ra != rb:
				return ra < rb

	var ra2 := _rarity_rank(a)
	var rb2 := _rarity_rank(b)
	if ra2 != rb2:
		return ra2 < rb2
	var na2 := String(a.get("name", ""))
	var nb2 := String(b.get("name", ""))
	if na2 != nb2:
		return na2 < nb2
	return int(a.get("level", 1)) > int(b.get("level", 1))


func _rarity_rank(data: Dictionary) -> int:
	var rarity := String(data.get("rarity", ""))
	var index := RARITY_ORDER.find(rarity)
	# Rareza desconocida: al final, nunca fuera de la lista.
	return index if index >= 0 else RARITY_ORDER.size()


## --- Acciones --------------------------------------------------------------

func _on_rarity_selected(value: String) -> void:
	_rarity_filter = value
	refresh()


func _on_type_selected(value: String) -> void:
	_type_filter = value
	refresh()


func _on_category_selected(value: String) -> void:
	_category_filter = value
	refresh()


func _on_sort_selected(index: int) -> void:
	_sort_mode = sort_option.get_item_id(index)
	_build()


func _on_card_pressed(data: Dictionary) -> void:
	if data.is_empty():
		return
	# Una pila de COPIAS abre la ficha de la unidad (es donde se consumen como Dupe).
	if bool(data.get("copy_only", false)):
		data = GameState.character_data(String(data.get("id", "")))
	info_panel.open_for_data(data, false)


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
