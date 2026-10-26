extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")
const WalletChip := preload("res://ui/wallet_chip.gd")

## MENU PRINCIPAL. Es la pantalla de entrada del juego y la mas cinematografica.
##
## Composicion (de arriba abajo):
##   - cartera (monedas y gemas) en dos placas con icono, a los lados
##   - logotipo del juego
##   - ESCAPARATE: el lider del equipo, de cuerpo entero, con su luz de contorno y
##     un resplandor de escenario, sobre la ciudad al atardecer
##   - placa con el nombre del lider
##   - JUGAR, grande y dorado, que late despacio
##   - rejilla de 4 x 3 mosaicos con icono semi-3D para el resto de destinos,
##     agrupados por funcion (contenido / bucle principal / gestion)
##
## INVOCAR y MISIONES llevan a pantallas que existen y se pueden recorrer; lo que
## todavia no hay no se inventa aqui. El estado del jugador (equipo, monedas) sale
## de GameState, no de esta pantalla.

@onready var status_label: Label = $Margin/Main/Status
@onready var footer_label: Label = $Margin/Main/Footer
@onready var main: VBoxContainer = $Margin/Main
@onready var play_button: Button = $Margin/Main/Actions/PlayButton
@onready var team_button: Button = $Margin/Main/Actions/MiddleRow/TeamButton
@onready var collection_button: Button = $Margin/Main/Actions/MiddleRow/CollectionButton
@onready var summon_button: Button = $Margin/Main/Actions/LowerRow/SummonButton
@onready var missions_button: Button = $Margin/Main/Actions/LowerRow/MissionsButton
@onready var history_button: Button = $Margin/Main/Actions/HistoryRow/HistoryButton
@onready var events_button: Button = $Margin/Main/Actions/EventsRow/EventsButton
@onready var evolution_button: Button = $Margin/Main/Actions/ProgressRow/EvolutionButton
@onready var inventory_button: Button = $Margin/Main/Actions/ProgressRow/InventoryButton
@onready var shop_button: Button = $Margin/Main/Actions/ExtraRow/ShopButton
@onready var mutations_button: Button = $Margin/Main/Actions/ExtraRow/MutationsButton
@onready var settings_button: Button = $Margin/Main/Actions/ExtraRow/SettingsButton

var _entrance: Tween = null
var _hero: Control = null
var _hero_portrait: Portrait = null
var _hero_name: Label = null
var _hero_tag: Label = null
var _coins_chip: Control = null
var _gems_chip: Control = null
var tower_button: Button = null


func _ready() -> void:
	play_button.pressed.connect(_play)
	team_button.pressed.connect(_goto.bind("team"))
	collection_button.pressed.connect(_goto.bind("collection"))
	summon_button.pressed.connect(_goto.bind("summon"))
	missions_button.pressed.connect(_goto.bind("missions"))
	history_button.pressed.connect(_goto.bind("history"))
	events_button.pressed.connect(_goto.bind("events"))
	# TORRE es contenido de desafio: nace en codigo y entra en la rejilla.
	tower_button = Button.new()
	tower_button.name = "TowerButton"
	tower_button.text = "TORRE"
	tower_button.pressed.connect(_goto.bind("tower"))
	evolution_button.pressed.connect(_goto.bind("evolution"))
	inventory_button.pressed.connect(_goto.bind("inventory"))
	shop_button.pressed.connect(_goto.bind("shop"))
	mutations_button.pressed.connect(_goto.bind("mutations"))
	settings_button.pressed.connect(_goto.bind("settings"))

	_rebuild_layout()
	_pulse_play()
	_entrance_animation()


## Mosaicos de la rejilla: [boton, icono, acento]. El ORDEN es el de lectura:
## primera fila = contenido, segunda = bucle principal, tercera = gestion.
func _tiles() -> Array:
	return [
		[history_button, "history", VI.VIOLET],
		[events_button, "events", VI.RED],
		[tower_button, "tower", VI.CYAN],
		[missions_button, "missions", VI.BLUE],
		[team_button, "team", VI.BLUE],
		[collection_button, "collection", VI.VIOLET],
		[summon_button, "summon", VI.MAGENTA],
		[shop_button, "shop", VI.GOLD],
		[evolution_button, "evolution", VI.GREEN],
		[mutations_button, "mutations", Color(0.25, 0.85, 0.70)],
		[inventory_button, "inventory", VI.INK_SOFT],
		[settings_button, "settings", VI.INK_SOFT],
	]


## Recompone el menu: la escena trae filas de botones pensadas para una pila
## vertical; aqui se sacan los botones de sus filas y se colocan en la rejilla, y
## el resto (cabecera, escaparate...) se construye con los componentes del estilo.
func _rebuild_layout() -> void:
	var margin: MarginContainer = $Margin
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 26)
	main.add_theme_constant_override("separation", 8)

	var subtitle: Label = main.get_node("Header/Subtitle")
	var title: Label = main.get_node("Header/Title")
	var spacer: Control = main.get_node("Spacer")
	var actions: Control = main.get_node("Actions")
	var buttons: Array = [play_button]
	for tile in _tiles():
		buttons.append(tile[0])
	for b in buttons:
		if b.get_parent() != null:
			b.get_parent().remove_child(b)
	status_label.get_parent().remove_child(status_label)
	footer_label.get_parent().remove_child(footer_label)
	subtitle.get_parent().remove_child(subtitle)
	title.get_parent().remove_child(title)
	for child in main.get_children():
		main.remove_child(child)
		child.queue_free()

	# --- Cartera: dos placas con icono, una a cada lado ---
	var wallet := HBoxContainer.new()
	wallet.name = "Wallet"
	wallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coins_chip = WalletChip.make("coin", GameState.coins, VI.GOLD)
	_gems_chip = WalletChip.make("gem", GameState.gems, VI.CYAN)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet.add_child(_coins_chip)
	wallet.add_child(gap)
	wallet.add_child(_gems_chip)
	main.add_child(wallet)

	# --- Logotipo (si falta el PNG, el titulo de texto de siempre) ---
	var logo_tex := load("res://art/ui/logo.png") if ResourceLoader.exists("res://art/ui/logo.png") else null
	if logo_tex is Texture2D:
		var logo := TextureRect.new()
		logo.name = "Logo"
		logo.texture = logo_tex
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(0, 150)
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		main.add_child(logo)
	else:
		VI.style_title(title, 72)
		main.add_child(title)
	VI.style_subtitle(subtitle)
	subtitle.add_theme_color_override("font_color", VI.GOLD_LIGHT)
	subtitle.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	main.add_child(subtitle)
	VI.style_note(status_label)
	status_label.add_theme_color_override("font_color", VI.INK_SOFT)
	status_label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	main.add_child(status_label)

	# --- Escaparate del lider ---
	_hero = Control.new()
	_hero.name = "Hero"
	_hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(_hero)
	_hero_portrait = Portrait.new()
	_hero_portrait.aura = 1.0
	_hero_portrait.rim_screen_px = 4.0
	_hero_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_portrait.transparent_frame = true
	_hero.add_child(_hero_portrait)
	_hero_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var plate := PanelContainer.new()
	plate.name = "LeaderPlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", VI.chip(VI.GOLD, 0.92))
	_hero.add_child(plate)
	plate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var plate_row := HBoxContainer.new()
	plate_row.add_theme_constant_override("separation", 14)
	plate_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(plate_row)
	_hero_tag = Label.new()
	_hero_tag.text = "LIDER"
	_hero_tag.add_theme_font_size_override("font_size", VI.FONT_TINY)
	_hero_tag.add_theme_color_override("font_color", VI.GOLD)
	plate_row.add_child(_hero_tag)
	_hero_name = Label.new()
	_hero_name.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	_hero_name.add_theme_color_override("font_outline_color", Color(0.04, 0, 0.1, 0.9))
	_hero_name.add_theme_constant_override("outline_size", 6)
	var bold := VI.font("bold")
	if bold != null:
		_hero_name.add_theme_font_override("font", bold)
	plate_row.add_child(_hero_name)

	# --- JUGAR ---
	VI.tint_button(play_button, VI.GOLD)
	play_button.custom_minimum_size = Vector2(0, 142)
	play_button.add_theme_font_size_override("font_size", 56)
	var play_icon := VI.icon("play")
	if play_icon != null:
		play_button.icon = play_icon
		play_button.expand_icon = true
		play_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		play_button.add_theme_constant_override("icon_max_width", 96)
		play_button.add_theme_constant_override("h_separation", 22)
	main.add_child(play_button)

	# --- Rejilla de mosaicos ---
	var grid := GridContainer.new()
	grid.name = "Tiles"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(grid)
	for tile in _tiles():
		var button: Button = tile[0]
		button.custom_minimum_size = Vector2(0, 150)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 25)
		VI.icon_button(button, String(tile[1]), tile[2], 84)
		grid.add_child(button)
	VI.style_note(footer_label)
	footer_label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	main.add_child(footer_label)


## Entrada suave: el menu aparece en vez de dar un salto seco al abrir el juego.
func _entrance_animation() -> void:
	# Solo opacidad: mover la posicion de un hijo de contenedor le quitaria el sitio
	# que el contenedor le reparte (el menu quedaria pegado al borde).
	main.modulate = Color(1, 1, 1, 0)
	if _entrance != null and _entrance.is_valid():
		_entrance.kill()
	_entrance = create_tween()
	_entrance.tween_property(main, "modulate:a", 1.0, 0.40)


## Latido lento y continuo del boton principal.
func _pulse_play() -> void:
	# El pivote se recalcula cuando el contenedor ya ha repartido el tamano: si no,
	# el latido se escala desde la esquina en lugar del centro.
	play_button.resized.connect(_update_play_pivot)
	_update_play_pivot()
	var tween := create_tween().set_loops()
	tween.tween_property(play_button, "scale", Vector2(1.015, 1.015), 1.1).set_trans(Tween.TRANS_SINE)
	tween.tween_property(play_button, "scale", Vector2.ONE, 1.1).set_trans(Tween.TRANS_SINE)


func _update_play_pivot() -> void:
	play_button.pivot_offset = play_button.size * 0.5


## ESCAPARATE: el lider del equipo (posicion 1) ocupa el hueco central del menu, de
## cuerpo entero. Cambia solo con el equipo. Sin lider, el primero del roster. Sin
## arte, la silueta del tipo.
func _refresh_hero() -> void:
	if _hero_portrait == null:
		return
	var id := GameState.party_leader_id()
	var is_leader := not id.is_empty()
	if id.is_empty() and not GameState.roster.is_empty():
		id = String(GameState.roster[0])
	var data := GameState.character_data(id)
	if data.is_empty():
		_hero_name.text = ""
		return
	var tint: Color = TypeColors.color_for(String(data.get("type", "STR")))
	_hero_portrait.setup(id, tint, String(data.get("portrait_style", "short")), Portrait.art_path_from(data, "front"), "front", "")
	_hero_name.text = String(data.get("name", id)).to_upper()
	_hero_name.add_theme_color_override("font_color", tint.lerp(Color.WHITE, 0.55))
	_hero_tag.text = "LIDER" if is_leader else "DESTACADO"


func refresh() -> void:
	_refresh_hero()
	if _coins_chip != null:
		_coins_chip.call("set_value", GameState.coins)
		_gems_chip.call("set_value", GameState.gems)
	status_label.text = "Equipo %d / %d      Personajes %d / %d" % [
		GameState.party.size(),
		GameState.PARTY_SIZE,
		GameState.owned_count(),
		GameState.total_count(),
	]
	var done := GameState.completed_stages.size()
	footer_label.text = "Batallas superadas: %d de %d" % [done, DB.all_stages().size()]


func _goto(screen: String) -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("open_screen"):
		app.call("open_screen", screen)


## JUGAR no salta directo al combate: pasa por la seleccion de batalla, que es
## donde se ve el enemigo, la dificultad, las recompensas y el equipo que llevas.
func _play() -> void:
	_goto("stage_select")
