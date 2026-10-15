extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")

## MENU PRINCIPAL. Es la pantalla de entrada del juego.
##
## Jerarquia visual: un titulo grande arriba, la cartera del jugador en una ficha,
## y los botones abajo con JUGAR destacado en dorado. El resto de botones van en
## dos filas para que quepan comodos en movil vertical sin apelotonarse.
##
## INVOCAR y MISIONES llevan a pantallas que existen y se pueden recorrer; lo que
## todavia no hay (el gacha) no se inventa aqui.
##
## El estado del jugador (equipo, monedas) sale de GameState, no de esta pantalla.

@onready var coins_label: Label = $Margin/Main/Wallet/WalletRow/Coins
@onready var gems_label: Label = $Margin/Main/Wallet/WalletRow/Gems
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


func _ready() -> void:
	play_button.pressed.connect(_play)
	team_button.pressed.connect(_goto.bind("team"))
	collection_button.pressed.connect(_goto.bind("collection"))
	summon_button.pressed.connect(_goto.bind("summon"))
	missions_button.pressed.connect(_goto.bind("missions"))
	history_button.pressed.connect(_goto.bind("history"))
	events_button.pressed.connect(_goto.bind("events"))
	# TORRE comparte fila con EVENTOS: es contenido de desafio, no de gestion.
	var tower_button := Button.new()
	tower_button.name = "TowerButton"
	tower_button.text = "TORRE"
	tower_button.custom_minimum_size = events_button.custom_minimum_size
	tower_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tower_button.add_theme_font_size_override("font_size", 30)
	events_button.get_parent().add_child(tower_button)
	tower_button.pressed.connect(_goto.bind("tower"))
	VI.tint_button(tower_button, VI.GOLD)
	evolution_button.pressed.connect(_goto.bind("evolution"))
	inventory_button.pressed.connect(_goto.bind("inventory"))
	shop_button.pressed.connect(_goto.bind("shop"))
	mutations_button.pressed.connect(_goto.bind("mutations"))
	settings_button.pressed.connect(_goto.bind("settings"))

	# JUGAR es el boton principal: se le pone el dorado para que se vea sin
	# buscarlo y late despacio, que es lo que lleva la mirada al sitio correcto.
	VI.tint_button(history_button, VI.VIOLET)
	VI.tint_button(events_button, VI.RED)
	# EVOLUCION y INVENTARIO son las dos pantallas de progresion del jugador.
	VI.tint_button(evolution_button, VI.GREEN)
	VI.tint_button(inventory_button, VI.INK_SOFT)
	VI.tint_button(play_button, VI.GOLD)
	play_button.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82, 1.0))
	_pulse_play()

	_build_hero()
	_entrance_animation()


## Entrada suave: el menu aparece en vez de dar un salto seco al abrir el juego.
func _entrance_animation() -> void:
	main.modulate = Color(1, 1, 1, 0)
	main.position.y = 20.0
	if _entrance != null and _entrance.is_valid():
		_entrance.kill()
	_entrance = create_tween().set_parallel(true)
	_entrance.tween_property(main, "modulate:a", 1.0, 0.35)
	_entrance.tween_property(main, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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
var _hero: Control = null
var _hero_portrait: Portrait = null
var _hero_name: Label = null


func _build_hero() -> void:
	var spacer: Control = main.get_node_or_null("Spacer")
	if spacer == null:
		return
	_hero = VBoxContainer.new()
	_hero.name = "Hero"
	_hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(_hero)
	main.move_child(_hero, spacer.get_index())
	spacer.visible = false
	_hero_portrait = Portrait.new()
	_hero_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.add_child(_hero_portrait)
	_hero_name = Label.new()
	_hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_name.add_theme_font_size_override("font_size", VI.FONT_BODY)
	_hero_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hero_name.add_theme_constant_override("outline_size", 8)
	_hero.add_child(_hero_name)


func _refresh_hero() -> void:
	if _hero_portrait == null:
		return
	var id := GameState.party_leader_id()
	if id.is_empty() and not GameState.roster.is_empty():
		id = String(GameState.roster[0])
	var data := GameState.character_data(id)
	if data.is_empty():
		_hero_name.text = ""
		return
	var tint: Color = TypeColors.color_for(String(data.get("type", "STR")))
	_hero_portrait.setup(id, tint, String(data.get("portrait_style", "short")), Portrait.art_path_from(data, "front"), "front", "")
	_hero_name.text = String(data.get("name", id)).to_upper()
	_hero_name.add_theme_color_override("font_color", tint)


func refresh() -> void:
	_refresh_hero()
	coins_label.text = "MONEDAS %d" % GameState.coins
	gems_label.text = "GEMAS %d" % GameState.gems
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
