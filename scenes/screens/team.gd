extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const ROSTER_CARD := preload("res://ui/roster_card.tscn")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")
const CombatUnit := preload("res://core/combat_unit.gd")
const CARD_TILE := preload("res://ui/card_tile.gd")

## EQUIPO: elegir que personajes salen a combatir y en que posicion.
##
## GameState.party es la UNICA fuente de verdad: esta pantalla la lee y la
## modifica, y el combate lee esa misma lista. No existe una copia del equipo
## aqui, asi que lo que se ve arriba es literalmente con lo que se juega.
##
## HUECOS. El equipo tiene SIEMPRE 4 posiciones y una puede estar vacia. Un hueco
## es un estado legitimo: 1/4, 2/4 o incluso 0/4 son equipos validos. La pantalla
## ensena "HUECO LIBRE" en la posicion vacia y el contador "n/4" arriba.
##
## Flujo, pensado para movil y sin pasos de mas:
##   1) se elige una POSICION (los huecos de arriba, que se marcan en dorado);
##   2) se toca un personaje de la lista y entra en esa posicion AL MOMENTO.
## Tocar al personaje que YA ocupa la posicion elegida lo QUITA (la deja vacia).
## Si el personaje estaba en otra posicion, se MUEVE: nunca hay duplicados.
## El boton QUITAR POS. N hace lo mismo sin tener que buscarlo en la lista.
##
## COMBATIR. Cuantas unidades hacen falta NO es una regla fija: lo dice el modo de
## la batalla (GameState.team_problem / current_min_party_size). Un stage normal
## admite cualquier equipo con al menos una unidad.
##
## ASPECTO: la pantalla se viste con res://ui/visual_identity.gd. Aqui no se
## escribe ningun color ni tamano a mano: salen de los tokens y constructores.
##
## La ficha de abajo ensena rareza, nivel y estado en el equipo. El ROL de un
## personaje es un dato interno de diseno y no se pinta aqui.

## Ranura de equipo que se esta modificando.
var _selected_slot := 0
## Personaje cuya informacion se esta mostrando abajo.
var _focused_id := ""

@onready var title_label: Label = $Margin/Main/Title
@onready var lineup_title: Label = $Margin/Main/LineupTitle
@onready var lineup: GridContainer = $Margin/Main/Lineup
@onready var links_note: Label = $Margin/Main/LinksNote
@onready var slot_hint: Label = $Margin/Main/SlotHint
@onready var info_panel: PanelContainer = $Margin/Main/InfoPanel
@onready var scroll: ScrollContainer = $Margin/Main/Scroll
@onready var pool_title: Label = $Margin/Main/PoolTitle
@onready var pool: GridContainer = $Margin/Main/Scroll/Pool
@onready var back_button: Button = $Margin/Main/Buttons/BackButton
@onready var remove_button: Button = $Margin/Main/Buttons/RemoveButton
@onready var play_button: Button = $Margin/Main/Buttons/PlayButton
@onready var info_portrait: Portrait = $Margin/Main/InfoPanel/InfoRow/InfoPortrait
@onready var info_name: Label = $Margin/Main/InfoPanel/InfoRow/InfoBox/InfoName
@onready var info_meta: Label = $Margin/Main/InfoPanel/InfoRow/InfoBox/InfoMeta
@onready var info_stats: Label = $Margin/Main/InfoPanel/InfoRow/InfoBox/InfoStats


func _ready() -> void:
	_apply_identity()
	back_button.pressed.connect(_back)
	remove_button.pressed.connect(_on_remove_pressed)
	play_button.pressed.connect(_play)


## Aspecto estatico de la pantalla, en un solo sitio: el equipo arriba, el
## roster abajo y los botones al pie.
func _apply_identity() -> void:
	VI.style_title(title_label, VI.FONT_BIG)
	VI.style_title(lineup_title, VI.FONT_SMALL)
	VI.style_title(pool_title, VI.FONT_SMALL)
	VI.style_subtitle(slot_hint)
	# Aviso de links: una sola linea, en dorado cuando hay alguno encendido y
	# atenuada cuando no, para no competir con el resto de la pantalla.
	VI.style_note(links_note)
	info_panel.add_theme_stylebox_override("panel", VI.panel(0.9, true))
	scroll.add_theme_stylebox_override("panel", VI.panel(0.55, false))
	info_name.add_theme_font_size_override("font_size", VI.FONT_BODY)
	VI.style_subtitle(info_meta)
	info_stats.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	info_stats.add_theme_color_override("font_color", VI.INK)
	VI.tint_button(back_button, VI.BLUE)
	VI.tint_button(remove_button, VI.RED)
	VI.tint_button(play_button, VI.GOLD)
	back_button.custom_minimum_size = Vector2(0, VI.TOUCH)
	remove_button.custom_minimum_size = Vector2(0, VI.TOUCH)
	play_button.custom_minimum_size = Vector2(0, VI.TOUCH)


func refresh() -> void:
	# El equipo se normaliza ANTES de pintarlo: 4 posiciones, sin duplicados y
	# sin personajes que el jugador no tenga. Un equipo viejo con una lista corta
	# queda con huecos en vez de romper la pantalla.
	GameState.normalize_party()
	_selected_slot = clampi(_selected_slot, 0, maxi(0, GameState.party.size() - 1))
	if _focused_id.is_empty() and _selected_slot < GameState.party.size():
		_focused_id = String(GameState.party[_selected_slot])
	_build_lineup()
	_build_pool()
	_update_info()
	_update_hint()
	_update_links_note()
	_update_buttons()


## El contador y el estado del boton COMBATIR salen del equipo real y del modo de
## la batalla. Nada de "hacen falta 4" escrito aqui.
func _update_buttons() -> void:
	var occupied := _selected_slot < GameState.party.size() and not String(GameState.party[_selected_slot]).is_empty()
	remove_button.text = "QUITAR POS. %d" % (_selected_slot + 1)
	remove_button.disabled = not occupied
	var problem := GameState.team_problem()
	play_button.disabled = not problem.is_empty()
	if problem.is_empty():
		play_button.text = "COMBATIR"
	else:
		play_button.text = "COMBATIR  -  falta equipo"


## Aviso de sinergias. GameState.active_link_ids() es la MISMA lista que usa el
## combate al empezar la batalla, asi que lo que se lee aqui es exactamente lo
## que se va a aplicar. Una linea, sin listas largas.
func _update_links_note() -> void:
	var active: Array = GameState.active_link_ids()
	if active.is_empty():
		links_note.text = "LINKS ACTIVOS: 0  -  pon dos personajes que compartan un link"
		links_note.add_theme_color_override("font_color", VI.INK_DIM)
		return
	var names := PackedStringArray()
	for link_id in active:
		var link := DB.get_link(String(link_id))
		names.append(String(link.get("name", link_id)))
	links_note.text = "LINKS ACTIVOS: %d  -  %s" % [active.size(), ", ".join(names)]
	links_note.add_theme_color_override("font_color", VI.GOLD)


## --- Las cuatro posiciones (arriba) ----------------------------------------

func _build_lineup() -> void:
	_clear(lineup)
	# El contador "n/4" es la lectura rapida del equipo.
	lineup_title.text = "TU EQUIPO  -  %d/%d" % [GameState.party_count(), GameState.PARTY_SIZE]
	for i in GameState.party.size():
		var id := String(GameState.party[i])
		var selected := i == _selected_slot
		# Una posicion vacia no es un personaje: se pinta como HUECO LIBRE, que es
		# un estado del equipo y no un error.
		if id.is_empty():
			var empty := Button.new()
			empty.name = "EmptySlot%d" % i
			empty.text = "+\nHUECO\nPOS. %d" % (i + 1)
			empty.custom_minimum_size = Vector2(0, 250)
			empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			empty.add_theme_font_size_override("font_size", VI.FONT_SMALL)
			empty.add_theme_color_override("font_color", VI.GOLD if selected else VI.INK_DIM)
			VI.tint_button(empty, VI.GOLD if selected else VI.INK_DIM)
			# Una posicion vacia se puede elegir igual que una ocupada: es donde
			# va a caer el proximo personaje.
			empty.pressed.connect(_on_slot_pressed.bind({}, i))
			lineup.add_child(empty)
			continue
		# Slot grande de preparacion de combate: arte front, POS. N y, en la 1,
		# la marca de LIDER (su Leader Skill es el del equipo).
		var extra := "POS.%d" % (i + 1)
		if i == 0:
			extra = "LIDER"
		var card := CARD_TILE.new()
		card.art_height = 190.0
		card.name = "Slot%d" % i
		lineup.add_child(card)
		card.bind(GameState.character_data(id), selected, extra)
		card.pressed.connect(_on_slot_pressed.bind(i))


## --- La lista de personajes (abajo) ----------------------------------------

func _build_pool() -> void:
	_clear(pool)
	for data in GameState.roster_data():
		var id := String(data.get("id", ""))
		var pos := GameState.party.find(id)
		var extra := "LIBRE"
		if pos >= 0:
			extra = "EN EQUIPO  -  POS. %d" % (pos + 1)
		var card := CARD_TILE.new()
		card.art_height = 120.0
		pool.add_child(card)
		card.bind(data, id == _focused_id, "EQ.%d" % (pos + 1) if pos >= 0 else "")
		# La senal pressed YA manda los datos del personaje: no se le anade nada
		# mas. Anadir argumentos aqui daba un error de numero de argumentos y el
		# toque no hacia absolutamente nada.
		card.pressed.connect(_on_pool_pressed)


func _update_hint() -> void:
	var slot_name := _selected_slot + 1
	if _selected_slot < GameState.party.size() and not String(GameState.party[_selected_slot]).is_empty():
		slot_hint.text = "POSICION %d SELECCIONADA  -  toca a otro para cambiarlo, o al mismo para quitarlo" % slot_name
	else:
		slot_hint.text = "POSICION %d (HUECO LIBRE)  -  toca un personaje de abajo para ponerlo aqui" % slot_name


## --- Acciones ---------------------------------------------------------------

## Elegir la posicion que se va a cambiar. Con datos vacios (una posicion en
## hueco) la seleccion cambia igual: lo que importa es la POSICION, no el
## personaje que hubiera en ella.
func _on_slot_pressed(data: Dictionary, index: int) -> void:
	_selected_slot = index
	if not data.is_empty():
		_focused_id = String(data.get("id", ""))
	refresh()


func _on_pool_pressed(data: Dictionary) -> void:
	if data.is_empty():
		return
	_focused_id = String(data.get("id", ""))
	# Toda la logica de colocar/quitar/mover vive en GameState: aqui solo se pide.
	GameState.assign_party_slot(_selected_slot, _focused_id)
	refresh()


## QUITAR POS. N: deja vacia la posicion elegida. Es el mismo camino que tocar
## dos veces al personaje, asi que no hay dos formas distintas de vaciar un hueco.
func _on_remove_pressed() -> void:
	GameState.assign_party_slot(_selected_slot, "")
	_focused_id = ""
	refresh()


## --- Informacion del personaje elegido -------------------------------------

func _update_info() -> void:
	var id := _focused_id
	if id.is_empty() and _selected_slot < GameState.party.size():
		id = String(GameState.party[_selected_slot])
	if id.is_empty():
		info_portrait.setup("", VI.INK_DIM, "short", "", "icon")
		info_name.text = "HUECO LIBRE"
		info_name.add_theme_color_override("font_color", VI.INK_DIM)
		info_meta.text = "POSICION %d  -  toca un personaje para ponerlo aqui" % (_selected_slot + 1)
		info_stats.text = ""
		return
	var data := GameState.character_data(id)
	if data.is_empty():
		return
	var unit := CombatUnit.new()
	unit.setup(data, true, -1)
	var tint: Color = TypeColors.color_for(unit.type)
	info_portrait.setup(unit.id, tint, unit.portrait_style, unit.art_for("icon"), "icon")
	info_name.text = unit.display_name
	info_name.add_theme_color_override("font_color", tint)
	info_meta.text = "%s  -  NIVEL %d  -  %s" % [
		String(data.get("rarity", "R")), GameState.level_of(id), _status_text(id)]
	info_stats.text = "HP %d    ATQ %d    DEF %d    SPD %d\nCRITICO %d%%    ESQUIVA %d%%" % [
		int(round(unit.max_hp())),
		int(round(unit.attack())),
		int(round(unit.defense())),
		int(round(unit.speed())),
		int(round(unit.crit_rate() * 100.0)),
		int(round(unit.dodge_rate() * 100.0)),
	]


func _status_text(id: String) -> String:
	var pos := GameState.party.find(id)
	if pos >= 0:
		return "EN EQUIPO - POS. %d" % (pos + 1)
	return "LIBRE"


## COMBATIR no abre el combate si el equipo no vale para el modo: el aviso ya lo
## da team_problem(), asi que aqui solo se comprueba lo mismo que ve el jugador.
func _play() -> void:
	var problem := GameState.team_problem()
	if not problem.is_empty():
		slot_hint.text = problem
		return
	var app := NAV.app_of(self)
	if app != null and app.has_method("open_screen"):
		app.call("open_screen", "stage_select")


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
