extends Control

## Pantalla de combate. Escucha al BattleManager (que es puramente logico) y
## traduce sus senales a tarjetas, numeros flotantes, barra de orden y registro.
## No calcula dano ni decide turnos.
##
## Informacion que se pinta: lo justo para jugar. El HUD solo saca VIDA, SP, el
## personaje ACTIVO, los botones de accion, el ORDEN DE ATAQUE y los RIVALES.
## Todo lo detallado (estadisticas, pasiva, especial, buffs/debuffs y los
## contadores de batalla) vive en la ficha (res://ui/unit_info_panel.tscn), que se
## abre tocando una tarjeta. La clasificacion interna de diseno de la unidad NO
## se pinta nunca: no es un dato de combate.
##
## V0.9:
##   - HUD aligerado: fuera los contadores de batalla y el exceso de texto.
##   - El personaje activo manda en la barra inferior: marco, indicador de turno
##     y nombre.
##   - El orden de ataque se lee de un golpe (quien ahora, quien va despues).
##   - Las tarjetas de combate muestran rareza y nivel (ui/unit_card).
##   - El resultado es una pantalla de recompensa (ui/result_panel.gd).
##
## V0.3:
##   - Tocar una tarjeta abre el panel de informacion de esa unidad.
##   - La barra de ORDEN DE ATAQUE muestra el orden real del combate, separada
##     del registro.
##   - El registro se colorea por tipo de evento.
## ACTIVO (el que tiene el turno) e INSPECCIONADO (el que mira el jugador) son
## dos estados distintos y se pintan con colores distintos.
##
## V0.4:
##   - Modo "elige objetivo": si la habilidad apunta a un unico rival o aliado y
##     hay donde elegir, el jugador toca la tarjeta que quiere (las candidatas se
##     encienden en verde). Con un unico candidato el combate elige por el.
##   - Al usar una habilidad o saltar una pasiva aparece un aviso con su nombre.
##   - Un critico se anuncia como tal, no como un numero mas.
## El color y el texto de los numeros de efecto los formatea core/stat_block.gd:
## la pantalla no decide como se escribe un modificador.

const UNIT_CARD := preload("res://ui/unit_card.tscn")
const UnitCard := preload("res://ui/unit_card.gd")
const Portrait := preload("res://ui/portrait.gd")
const BattleManager := preload("res://core/battle_manager.gd")
const CombatUnit := preload("res://core/combat_unit.gd")
const StatBlock := preload("res://core/stat_block.gd")
const TypeColors := preload("res://ui/type_colors.gd")
const OrderStrip := preload("res://ui/order_strip.gd")
const UnitInfoPanel := preload("res://ui/unit_info_panel.gd")
const ResultPanel := preload("res://ui/result_panel.gd")
## Identidad visual del proyecto: colores, tamanos y constructores de estilo. Es
## el unico sitio de donde salen los colores de esta pantalla.
const VisualIdentity := preload("res://ui/visual_identity.gd")
const NAV := preload("res://scenes/nav.gd")
const CombatFx := preload("res://ui/combat_fx.gd")

## Todo lo que ya existe en la identidad visual se toma de alli, para que el HUD
## no invente colores. Los dos avisos que no existen en ella (critico y
## desventaja de tipo) se quedan aqui con nombre propio porque solo los usa la
## notificacion flotante de un golpe.
const GOLD := VisualIdentity.GOLD
const DAMAGE_COLOR := VisualIdentity.INK
const HEAL_COLOR := VisualIdentity.GREEN
const EFFECT_COLOR := VisualIdentity.INK_SOFT
## Aviso de ventaja/desventaja de tipo: verde cuando el golpe pega mas y naranja
## apagado cuando pega menos. Es informacion del motor (hit.type_mult), no un
## calculo de la interfaz: el multiplicador nunca se ensena.
const ADVANTAGE_COLOR := VisualIdentity.GREEN
const DISADVANTAGE_COLOR := Color(0.95, 0.7, 0.5, 1.0)
const CRIT_COLOR := Color(1.0, 0.55, 0.2, 1.0)

## Se puede inspeccionar tambien al rival. La spec pide "cualquier aliado";
## mirar al enemigo es util, y poner esto en false lo desactiva.
const INSPECT_ENEMIES := true

## Color de cada tipo de linea del registro (bbcode, sin '#').
const LOG_COLORS := {
	"system": "b9c0d8",
	"damage": "ffd98c",
	"crit": "ff9a3d",
	"dodge": "b3d9ff",
	"heal": "8cff9e",
	"buff": "8ce6ff",
	"debuff": "f2a3f2",
	"status": "f2a3f2",
	"passive": "ffc757",
	"sp": "8ce6ff",
	"result": "ffc757",
}
const LOG_DEFAULT_COLOR := "b9c0d8"

@onready var header_label: Label = $Margin/Main/TopBar/Header
@onready var round_label: Label = $Margin/Main/TopBar/RoundLabel
@onready var enemy_row: HBoxContainer = $Margin/Main/EnemyRow
@onready var order_panel: PanelContainer = $Margin/Main/OrderPanel
@onready var order_row: OrderStrip = $Margin/Main/OrderPanel/OrderBox/OrderRow
@onready var ally_grid: GridContainer = $Margin/Main/AllyGrid
@onready var log_panel: PanelContainer = $Margin/Main/LogPanel
@onready var log_view: RichTextLabel = $Margin/Main/LogPanel/Log
@onready var active_bar: PanelContainer = $Margin/Main/Bottom/ActiveBar
@onready var active_row: HBoxContainer = $Margin/Main/Bottom/ActiveBar/ActiveRow
@onready var active_portrait: Portrait = $Margin/Main/Bottom/ActiveBar/ActiveRow/ActivePortrait
@onready var active_name: Label = $Margin/Main/Bottom/ActiveBar/ActiveRow/ActiveInfo/ActiveName
@onready var active_hp: ProgressBar = $Margin/Main/Bottom/ActiveBar/ActiveRow/ActiveInfo/ActiveHpBar
@onready var active_sp: Label = $Margin/Main/Bottom/ActiveBar/ActiveRow/ActiveInfo/ActiveSp
@onready var action_hint: Label = $Margin/Main/Bottom/ActionHint
@onready var action_row: HBoxContainer = $Margin/Main/Bottom/ActionRow
@onready var attack_button: Button = $Margin/Main/Bottom/ActionRow/AttackButton
@onready var special_button: Button = $Margin/Main/Bottom/ActionRow/SpecialButton
@onready var cancel_button: Button = $Margin/Main/Bottom/ActionRow/CancelButton
## Salida del combate. En movil no hay tecla Esc, asi que este boton es la unica
## puerta de vuelta. El segundo vive en el resultado, porque el overlay que lo
## cubre no deja tocar el primero.
@onready var exit_button: Button = $ExitButton
@onready var result_exit_button: Button = $ResultOverlay/Center/ResultPanel/VBox/ButtonsRow/ExitButton
@onready var result_overlay: ColorRect = $ResultOverlay
@onready var result_panel: ResultPanel = $ResultOverlay/Center/ResultPanel
@onready var restart_button: Button = $ResultOverlay/Center/ResultPanel/VBox/ButtonsRow/RestartButton
@onready var info_panel: UnitInfoPanel = $UnitInfoPanel

var manager: BattleManager = null
## Token de esta batalla, que llega desde App al abrirla. Es lo que permite que
## las recompensas se cobren una sola vez aunque el resultado se abra dos veces.
var battle_token := 0
var cards: Dictionary = {}
var current_actor: CombatUnit = null
## Clave de la unidad que el jugador esta mirando ("" si ninguna). No es el
## personaje activo: se pueden ver los dos a la vez y no se pisan.
var inspected_key := ""

## Verdadero solo mientras la pantalla espera que el jugador pulse un boton.
## Evita que un doble toque en movil resuelva dos acciones.
var awaiting_input := false

## Habilidad ya elegida que esta esperando objetivo ("" si no se esta eligiendo).
var pending_kind := ""
## Unidades que el jugador puede tocar ahora mismo. Lo calcula el BattleManager.
var target_candidates: Array = []

## Confirmacion de salida, construida por codigo (ver _build_confirm_overlay).
var _confirm_overlay: ColorRect = null
var _confirm_cancel: Button = null
var _confirm_exit: Button = null
## Recompensas: se entregan UNA sola vez por batalla.
var _rewards_claimed := false
## Indicador "ATACANDO" de la barra inferior. Se construye por codigo para no
## depender del orden de los hijos de la escena.
var _active_badge: Label = null
## Marco dorado que acompana al retrato del personaje activo. Se construye por
## codigo dentro del propio retrato (es un hijo, no ocupa sitio en la fila).
var _active_frame: Panel = null


func _ready() -> void:
	manager = BattleManager.new()
	manager.name = "BattleManager"
	add_child(manager)
	manager.battle_started.connect(_on_battle_started)
	manager.round_started.connect(_on_round_started)
	manager.order_changed.connect(_on_order_changed)
	manager.turn_started.connect(_on_turn_started)
	manager.action_requested.connect(_on_action_requested)
	manager.action_resolved.connect(_on_action_resolved)
	manager.log_added.connect(_on_log_added)
	manager.battle_finished.connect(_on_battle_finished)
	manager.ultimate_started.connect(_on_ultimate_started)
	_build_ultimate_button()

	attack_button.pressed.connect(_on_attack_pressed)
	special_button.pressed.connect(_on_special_pressed)
	cancel_button.pressed.connect(_cancel_targeting)
	restart_button.pressed.connect(_on_restart_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	result_exit_button.pressed.connect(_on_result_continue)
	info_panel.closed.connect(_on_info_closed)
	_build_confirm_overlay()
	_apply_visual_identity()
	_build_active_badge()
	_build_active_frame()
	_polish_buttons()

	log_view.bbcode_enabled = true
	action_row.visible = false
	cancel_button.visible = false
	result_overlay.visible = false
	_set_active_unit(null)
	action_hint.text = ""

	_apply_stage_background()
	_show_stage_title()
	# El combate pelea con la PLANTILLA de la batalla (GameState.battle_party_data):
	# equipo normal, o UNA sola unidad cuando el stage es un 1 VS 1. La escena no
	# decide esto: lo fija GameState al preparar la batalla.
	manager.setup(GameState.battle_party_data(), GameState.enemy_data(), GameState.battle_reserve_data())
	manager.reserve_entered.connect(_on_reserve_entered)
	if manager.allies.is_empty() or manager.enemies.is_empty():
		_on_log_added("No se han podido cargar los datos de personajes o enemigos.", "system")
		return

	_build_cards()
	manager.start_battle()


## Escenario del combate. Si el stage trae "background" en su JSON, se usa ese
## nombre de fondo; si no, se queda el de por defecto ("battle"). Meter el PNG en
## res://art/backgrounds/ es todo lo necesario: aqui no se escribe ninguna ruta.
func _apply_stage_background() -> void:
	var bg = get_node_or_null("Background")
	if bg == null or not bg.has_method("show_slot"):
		return
	var stage: Dictionary = GameState.current_stage()
	var wanted := String(stage.get("background", ""))
	if not wanted.is_empty():
		bg.call("show_slot", wanted)


## Nombre de la batalla, en una linea discreta arriba. Antes ponia "ANIME BATTLE",
## que no dice nada en mitad de un combate: lo util es saber contra quien se juega.
func _show_stage_title() -> void:
	var stage: Dictionary = GameState.current_stage()
	var stage_name := String(stage.get("name", ""))
	header_label.text = stage_name.to_upper() if not stage_name.is_empty() else ""
	VisualIdentity.style_note(header_label)


func _build_cards() -> void:
	for unit in manager.allies:
		var card: UnitCard = UNIT_CARD.instantiate()
		ally_grid.add_child(card)
		card.bind(unit, false)
		card.card_pressed.connect(_on_card_pressed)
		cards[unit.source_key] = card
	# Con un solo rival manda el banner grande; con varios, las tarjetas se
	# reparten la fila en modo compacto. Quien decide cuantos rivales hay es el
	# BattleManager: la pantalla solo pregunta.
	var several := manager.enemies.size() > 1
	for unit in manager.enemies:
		var card: UnitCard = UNIT_CARD.instantiate()
		enemy_row.add_child(card)
		card.bind(unit, true, several)
		card.card_pressed.connect(_on_card_pressed)
		# En modo compacto la fila se estrecha: el nombre largo no debe desbordar.
		if several:
			card.name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card.type_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card.rarity_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card.level_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card.hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cards[unit.source_key] = card


## Una reserva entra en el puesto de un caido: su tarjeta ocupa el mismo hueco de
## la rejilla y la del caido desaparece.
func _on_reserve_entered(out_unit, in_unit, slot_index: int) -> void:
	var old_card = cards.get(out_unit.source_key, null)
	var card: UnitCard = UNIT_CARD.instantiate()
	ally_grid.add_child(card)
	card.bind(in_unit, false)
	card.card_pressed.connect(_on_card_pressed)
	cards[in_unit.source_key] = card
	if old_card != null:
		ally_grid.move_child(card, old_card.get_index())
		cards.erase(out_unit.source_key)
		old_card.queue_free()
	_spawn_banner("%s ENTRA" % in_unit.display_name, GOLD)
	_refresh_all()


func _refresh_all() -> void:
	for key in cards.keys():
		var unit := manager.find_unit(String(key))
		if unit == null:
			continue
		var card: UnitCard = cards[key]
		card.refresh()
		var is_active := current_actor != null and current_actor.source_key == unit.source_key
		card.set_active(is_active)
		card.set_inspected(unit.source_key == inspected_key)
		card.set_selectable(_is_candidate(unit))


func _alive_allies() -> int:
	var count := 0
	for unit in manager.allies:
		if unit.alive:
			count += 1
	return count


## Celebracion de victoria: el panel de recompensa se enciende un instante. Es lo
## unico que se anima del resultado, para que el ojo vaya al premio y no a un
## espectaculo.
func _celebrate_victory() -> void:
	if result_panel == null:
		return
	# Arranca cuando el panel ya ha terminado de entrar, para no pelearse con la
	# animacion de aparicion.
	var tween := create_tween()
	tween.tween_property(result_panel, "modulate", Color(GOLD.r, GOLD.g, GOLD.b, 1.0), 0.14).set_delay(0.34)
	tween.tween_property(result_panel, "modulate", Color(1, 1, 1, 1), 0.34)


func _on_battle_started() -> void:
	exit_button.visible = true
	_refresh_all()
	# Aviso BREVE de sinergias: los links activos ya estan aplicados a las
	# estadisticas de los aliados en este punto, asi que esto solo los anuncia.
	_show_link_notice()


## Resumen de una linea, en la banda alta de la pantalla, que se desvanece solo.
## Los nombres salen los links que el combate ha aplicado de verdad
## (manager.active_team_link_ids): la pantalla no calcula sinergias por su cuenta.
## No bloquea el toque (mouse_filter IGNORE) y los botones viven abajo, asi que no
## tapa nada.
func _show_link_notice() -> void:
	if manager == null:
		return
	var active: Array = manager.active_team_link_ids()
	if active.is_empty():
		return
	var names: Array = manager.active_team_link_names()
	var label := Label.new()
	label.text = "LINKS ACTIVOS  %s" % ", ".join(PackedStringArray(names))
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", GOLD)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 7)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 17
	label.size = Vector2(size.x, 34)
	label.position = Vector2(0, size.y * 0.115)
	add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(1.5)
	tween.finished.connect(label.queue_free)


func _on_round_started(round_number: int, _order_names: Array) -> void:
	round_label.text = "RONDA %d" % round_number
	# El orden ya tiene su propia zona en pantalla: el registro no lo repite.
	_on_log_added("Ronda %d." % round_number, "system")


## El orden real de la ronda, tal como lo calcula el combate.
func _on_order_changed(units: Array, cursor: int) -> void:
	order_row.show_order(units, cursor)


func _on_turn_started(unit: CombatUnit) -> void:
	current_actor = unit
	action_row.visible = false
	awaiting_input = false
	_clear_targeting()
	_refresh_all()
	_set_active_unit(unit)
	_pulse_active_portrait()
	if cards.has(unit.source_key):
		var card: UnitCard = cards[unit.source_key]
		card.bump()
	if unit.is_ally:
		action_hint.text = "Turno de %s" % unit.display_name
	else:
		action_hint.text = "Turno del enemigo..."


func _on_action_requested(unit: CombatUnit) -> void:
	current_actor = unit
	awaiting_input = true
	_clear_targeting()
	_refresh_all()
	_set_active_unit(unit)
	action_row.visible = true
	attack_button.visible = true
	special_button.visible = true
	action_hint.text = "Elige accion"
	attack_button.text = "ATAQUE BASICO"
	attack_button.disabled = not manager.can_use(unit, "basic")
	var special := unit.skill_by_kind("special")
	if special.is_empty():
		special_button.text = "SIN HABILIDAD"
		special_button.disabled = true
	else:
		var cost := int(special.get("cost", 0))
		special_button.text = "%s\nSP %d" % [String(special.get("name", "ESPECIAL")).to_upper(), cost]
		special_button.disabled = not manager.can_use(unit, "special")
	_refresh_ultimate_button(unit)
	_pulse(action_row)


func _on_action_resolved(payload: Dictionary) -> void:
	awaiting_input = false
	_clear_targeting()
	action_row.visible = false
	_refresh_all()
	_sync_active_bar()
	# Los contadores y los efectos cambian con cada accion: si el panel esta
	# abierto, se repinta con el estado nuevo (buffs, curaciones, criticos...).
	if info_panel.is_open():
		info_panel.refresh()
	_play_feedback(payload)


func _on_log_added(text: String, kind: String = "system") -> void:
	var color := String(LOG_COLORS.get(kind, LOG_DEFAULT_COLOR))
	log_view.append_text("[color=#%s]%s[/color]\n" % [color, text])


## Tocar una tarjeta hace una de dos cosas, nunca las dos:
##   - si se esta eligiendo objetivo, apunta a esa unidad;
##   - si no, abre su panel de informacion.
## Abrir el panel NO cambia el turno: el personaje inspeccionado y el activo son
## cosas distintas.
func _on_card_pressed(target: CombatUnit) -> void:
	if target == null:
		return
	if not pending_kind.is_empty():
		if _is_candidate(target):
			_confirm_target(target)
		return
	if not target.is_ally and not INSPECT_ENEMIES:
		return
	inspected_key = target.source_key
	_refresh_all()
	info_panel.open_for(target)


func _on_info_closed() -> void:
	inspected_key = ""
	_refresh_all()


func _on_battle_finished(victory: bool, rounds: int) -> void:
	# Si la ultimate que ha cerrado el combate aun se esta presentando, se espera a que
	# termine (maximo 4 s) para que el resultado no la pise.
	var waited := 0.0
	while _ult_fx_active and waited < 4.0 and is_inside_tree():
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	awaiting_input = false
	_clear_targeting()
	action_row.visible = false
	# El resultado manda: el panel de informacion se aparta.
	if info_panel.is_open():
		info_panel.close_panel()
	_sync_active_bar()
	_refresh_all()
	# El boton SALIR flotante vive por encima del resultado: se aparta para no
	# tapar la pantalla de recompensa, que trae su propio CONTINUAR.
	exit_button.visible = false
	action_hint.text = ""
	result_overlay.visible = true
	# La pantalla de resultado tiene su propio fondo, distinto del escenario del
	# combate. Es solo cambiar el nombre del slot: el archivo manda.
	var bg = get_node_or_null("Background")
	if bg != null and bg.has_method("show_slot"):
		bg.call("show_slot", "results")
	# El panel de resultado solo PINTA: el informe que recibe ya viene cobrado de
	# GameState, con XP, monedas, niveles y batallas nuevas.
	result_panel.present(
		victory,
		rounds,
		_alive_allies(),
		manager.allies.size(),
		_grant_rewards(victory)
	)
	# La musica de combate se corta, suena el jingle y despues entra la musica de
	# RESULTADOS (si el panel sigue en pantalla). Un solo reproductor de musica:
	# no hay forma de que dos pistas suenen a la vez.
	# La musica de RESULTADOS recupera la prioridad: el tema especial del combate se
	# suelta antes de cortar la musica.
	GameAudio.override_clear("battle")
	GameAudio.stop_music()
	GameAudio.play("victory" if victory else "defeat")
	if victory:
		_celebrate_victory()
	await get_tree().create_timer(1.9).timeout
	if is_inside_tree() and result_overlay.visible:
		GameAudio.play_music("results")


func _on_attack_pressed() -> void:
	_submit("basic")


func _on_special_pressed() -> void:
	_submit("special")


func _on_ultimate_pressed() -> void:
	_submit("ultimate")


## Boton de la ULTIMATE de forma (LR). Se construye por codigo junto al ESPECIAL y
## solo es visible para una unidad que la tiene en su forma actual.
var ultimate_button: Button = null
## Presentacion de la ultimate en curso (bloquea el cierre del resultado hasta que acaba).
var _ult_fx_active := false
## Cuantas ultimates de forma se han presentado en esta batalla (lo usan las pruebas).
var ultimate_fx_count := 0


func _build_ultimate_button() -> void:
	ultimate_button = Button.new()
	ultimate_button.name = "UltimateButton"
	ultimate_button.focus_mode = Control.FOCUS_NONE
	ultimate_button.visible = false
	ultimate_button.custom_minimum_size = special_button.custom_minimum_size
	ultimate_button.add_theme_font_size_override("font_size", special_button.get_theme_font_size("font_size"))
	ultimate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VisualIdentity.tint_button(ultimate_button, VisualIdentity.rarity_color("LR"))
	action_row.add_child(ultimate_button)
	action_row.move_child(ultimate_button, special_button.get_index() + 1)
	ultimate_button.pressed.connect(_on_ultimate_pressed)


## Textos de la ultimate sobre el boton: nombre, coste y si ya se uso.
func _refresh_ultimate_button(unit: CombatUnit) -> void:
	if ultimate_button == null:
		return
	if unit == null or not unit.is_ally or not unit.has_ultimate():
		ultimate_button.visible = false
		return
	var ult := unit.ultimate
	ultimate_button.visible = true
	if unit.ultimate_used:
		ultimate_button.text = "%s\nUSADA" % String(ult.get("name", "ULTIMATE")).to_upper()
		ultimate_button.disabled = true
	else:
		ultimate_button.text = "%s\nSP %d  -  1 VEZ" % [String(ult.get("name", "ULTIMATE")).to_upper(), int(ult.get("cost", 0))]
		ultimate_button.disabled = not manager.can_use(unit, "ultimate")


## La ultimate EMPIEZA: el tema del duo sustituye a la musica de combate (si existe el
## archivo) y se queda hasta el final del combate. override_start no reinicia la
## cancion si ya suena, asi que ni los efectos ni otra ultimate la reinician.
func _on_ultimate_started(_unit) -> void:
	GameAudio.override_start("david_lucy_theme", "battle")


func _on_restart_pressed() -> void:
	# Otra batalla con las mismas reglas, sin salir del combate. Si la escena se
	# juega suelta (sin el App alrededor), se recarga la escena.
	var app := NAV.app_of(self)
	if app != null and app.has_method("restart_battle"):
		app.call("restart_battle")
		return
	get_tree().reload_current_scene()


## --- Abandonar el combate --------------------------------------------------
## SALIR no cierra nada a la primera: pregunta, porque abandonar tira la batalla
## entera. En movil no hay tecla Esc, asi que este boton es la unica puerta de
## vuelta y conviene que no se dispare de un toque accidental.

func _on_exit_pressed() -> void:
	if _confirm_overlay == null:
		return
	_confirm_overlay.visible = true
	# Aparicion del dialogo: entra con un golpe suave de escala para que se note
	# que es una pregunta y no un cambio de pantalla.
	var panel := _confirm_overlay.get_node_or_null("Center/ConfirmPanel")
	if panel != null:
		_pulse(panel)
	show_hint("Pulsa SALIR para abandonar el combate")


func _cancel_abandon() -> void:
	if _confirm_overlay != null:
		_confirm_overlay.visible = false
	show_hint("Combate en curso")


func _confirm_abandon() -> void:
	if _confirm_overlay != null:
		_confirm_overlay.visible = false
	# Abandonar NO es victoria ni derrota: se marca la batalla como resuelta para
	# que no se entreguen recompensas y se cierra.
	_rewards_claimed = true
	_close_battle()


## CONTINUAR del resultado: la batalla ya esta resuelta, se cierra y se vuelve a
## la pantalla desde la que se entro, tal como estaba.
func _on_result_continue() -> void:
	_close_battle()


## Unico sitio que cierra la batalla. El App suelta el nodo entero, asi que no
## quedan turnos, timers ni senales vivas y la batalla siguiente se construye de
## cero: no hay dos combates ni dos UIs a la vez.
func _close_battle() -> void:
	awaiting_input = false
	_clear_targeting()
	var app := NAV.app_of(self)
	if app != null and app.has_method("close_battle"):
		app.call("close_battle")
		return
	# La escena jugada suelta (sin el App alrededor) se recarga.
	get_tree().reload_current_scene()


## Aviso corto en la linea de estado del combate. Lo usa el App para pedir
## confirmacion antes de abandonar una batalla en curso.
func show_hint(text: String) -> void:
	if action_hint == null:
		return
	action_hint.text = text


## Token de la batalla. Lo asigna App justo despues de crear el combate, antes
## de que pueda terminar ninguna batalla, asi que el resultado siempre tiene un
## token valido con el que pedir las recompensas.
func set_battle_token(token: int) -> void:
	battle_token = token


## --- Confirmacion de salida y recompensas ----------------------------------

## Dialogo de abandonar, construido por codigo y anadido AL FINAL del arbol de la
## batalla: al ser el ultimo hijo queda por encima de todo lo demas y sus botones
## reciben el toque (el contenedor Margin, que cubre la pantalla, ya no intercepta
## el clic porque su mouse_filter es IGNORE en la escena).
func _build_confirm_overlay() -> void:
	_confirm_overlay = ColorRect.new()
	_confirm_overlay.name = "ConfirmOverlay"
	_confirm_overlay.color = Color(0, 0, 0, 0.74)
	_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_overlay.visible = false
	add_child(_confirm_overlay)
	_confirm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "ConfirmPanel"
	panel.custom_minimum_size = Vector2(640, 0)
	panel.add_theme_stylebox_override("panel", VisualIdentity.panel(0.98))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "ABANDONAR COMBATE?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VisualIdentity.style_title(title, VisualIdentity.FONT_SECTION + 8)
	vbox.add_child(title)

	var body := Label.new()
	body.text = "Todo el progreso de esta batalla se perdera."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_theme_font_size_override("font_size", VisualIdentity.FONT_BODY)
	body.add_theme_color_override("font_color", VisualIdentity.INK_SOFT)
	vbox.add_child(body)

	# Botones grandes: en movil se pulsa con el dedo, no con un cursor.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	vbox.add_child(row)

	_confirm_cancel = _make_dialog_button("CANCELAR")
	_confirm_cancel.pressed.connect(_cancel_abandon)
	row.add_child(_confirm_cancel)

	_confirm_exit = _make_dialog_button("SALIR")
	VisualIdentity.tint_button(_confirm_exit, VisualIdentity.RED)
	_confirm_exit.pressed.connect(_confirm_abandon)
	row.add_child(_confirm_exit)


func _make_dialog_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(0, VisualIdentity.TOUCH + 12.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", VisualIdentity.FONT_SECTION)
	button.button_down.connect(_nudge.bind(button))
	return button


## Pide las recompensas de la batalla UNA sola vez y devuelve el informe que la
## pantalla de resultado pinta. El guardia _rewards_claimed impide una segunda
## entrega si esta funcion se volviera a disparar, y el token hace lo mismo en
## GameState: una batalla no paga dos veces. Quien paga es siempre
## GameState.grant_battle_rewards, nunca la interfaz.
func _grant_rewards(victory: bool) -> Dictionary:
	if _rewards_claimed:
		return { "xp": 0, "coins": 0, "characters": [], "granted": false, "unlocked": [] }
	_rewards_claimed = true
	var ids: Array = manager.participant_ids()
	return GameState.grant_battle_rewards(battle_token, ids, victory)


## --- Identidad visual del HUD ------------------------------------------------
## El HUD lee de ui/visual_identity.gd como cualquier otra pantalla: paneles,
## separaciones, tamanos de texto y acentos. Aqui no se inventa ningun color.

func _apply_visual_identity() -> void:
	VisualIdentity.style_title(header_label, VisualIdentity.FONT_SECTION)
	VisualIdentity.style_title(round_label, VisualIdentity.FONT_BIG)
	var order_style := VisualIdentity.panel(0.86, true, VisualIdentity.RADIUS_PANEL)
	order_style.content_margin_top = 8.0
	order_style.content_margin_bottom = 8.0
	order_panel.add_theme_stylebox_override("panel", order_style)
	var log_style := VisualIdentity.panel(0.80)
	log_style.content_margin_top = 8.0
	log_style.content_margin_bottom = 8.0
	log_panel.add_theme_stylebox_override("panel", log_style)
	active_bar.add_theme_stylebox_override("panel", VisualIdentity.panel(0.94))
	VisualIdentity.style_note(action_hint)


## Botones del turno: dorado el ataque basico y azul la habilidad, para que se
## distingan de un vistazo. El CANCELAR de la eleccion de objetivo se queda con el
## estilo del tema, porque es una salida, no una accion.
func _polish_buttons() -> void:
	VisualIdentity.tint_button(attack_button, VisualIdentity.GOLD)
	VisualIdentity.tint_button(special_button, VisualIdentity.BLUE)
	for button in [attack_button, special_button, cancel_button]:
		button.custom_minimum_size = Vector2(0, VisualIdentity.TOUCH)
		# Microanimacion: el boton responde al pulsarlo aunque la accion tarde.
		button.button_down.connect(_nudge.bind(button))


## Empujon corto de escala: confirmacion tactil inmediata. Se usa en los botones
## de accion y en el aviso de turno.
func _nudge(node: Control) -> void:
	if node == null:
		return
	node.pivot_offset = node.size * 0.5
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2(0.97, 0.97), 0.06)
	tween.tween_property(node, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## --- Elegir objetivo -------------------------------------------------------
## Solo se pide elegir cuando hay algo que decidir: si la habilidad apunta a un
## unico candidato vivo, el combate lo coge solo y el turno no se alarga con un
## toque de mas. Quien puede ser objetivo lo decide el BattleManager
## (candidates()), no la pantalla.

func _submit(kind: String) -> void:
	if not awaiting_input or current_actor == null:
		return
	var candidates := manager.candidates(current_actor, kind)
	if manager.needs_target(current_actor, kind) and candidates.size() > 1:
		_begin_targeting(kind, candidates)
		return
	_finish_submit(kind, "")


func _begin_targeting(kind: String, candidates: Array) -> void:
	pending_kind = kind
	target_candidates = candidates
	attack_button.visible = false
	special_button.visible = false
	if ultimate_button != null:
		ultimate_button.visible = false
	cancel_button.visible = true
	action_row.visible = true
	action_hint.text = "Elige objetivo"
	_refresh_all()


func _is_candidate(target: CombatUnit) -> bool:
	if pending_kind.is_empty() or target == null:
		return false
	for unit in target_candidates:
		if String(unit.source_key) == String(target.source_key):
			return true
	return false


func _confirm_target(target: CombatUnit) -> void:
	_finish_submit(pending_kind, target.source_key)


## Cancelar devuelve el turno al jugador: sigue siendo su turno y puede elegir
## otra accion.
func _cancel_targeting() -> void:
	if pending_kind.is_empty():
		return
	_clear_targeting()
	awaiting_input = true
	action_hint.text = "Elige accion"
	action_row.visible = true
	attack_button.visible = true
	special_button.visible = true
	_refresh_ultimate_button(current_actor)


func _clear_targeting() -> void:
	pending_kind = ""
	target_candidates = []
	if cancel_button != null:
		cancel_button.visible = false


func _finish_submit(kind: String, target_key: String) -> void:
	if not awaiting_input or current_actor == null:
		return
	awaiting_input = false
	_clear_targeting()
	action_row.visible = false
	manager.submit_action({ "kind": kind, "target_key": target_key })


## Indicador de turno de la barra inferior. Es lo que deja claro, sin leer el
## registro, quien esta actuando ahora mismo. Se apaga solo cuando el turno
## termina (la barra pasa a estado normal).
func _build_active_badge() -> void:
	var info := active_row.get_node_or_null("ActiveInfo")
	if info == null:
		return
	_active_badge = Label.new()
	_active_badge.name = "ActiveBadge"
	_active_badge.text = "TURNO ACTUAL"
	_active_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_active_badge.add_theme_font_size_override("font_size", 24)
	_active_badge.add_theme_color_override("font_color", GOLD)
	_active_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_active_badge.add_theme_constant_override("outline_size", 5)
	_active_badge.visible = false
	info.add_child(_active_badge)
	# Arriba del todo: el aviso se lee antes que el nombre.
	info.move_child(_active_badge, 0)


## Marco del personaje activo: un aro dorado DENTRO del retrato (es un hijo, no
## ocupa sitio en la fila) que se enciende cuando hay turno. Da al activo la
## presencia que antes solo tenia el texto.
func _build_active_frame() -> void:
	if active_portrait == null:
		return
	_active_frame = Panel.new()
	_active_frame.name = "ActiveFrame"
	_active_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_active_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(VisualIdentity.RADIUS_PANEL)
	style.set_border_width_all(4)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.95)
	style.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.10)
	style.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
	style.shadow_size = 18
	style.shadow_offset = Vector2.ZERO
	_active_frame.add_theme_stylebox_override("panel", style)
	active_portrait.add_child(_active_frame)
	_active_frame.visible = false


## Barra inferior: quien actua y como esta. Es la lectura principal durante el
## combate, asi que el retrato manda y el texto acompania: marco, indicador de
## turno, nombre, vida y SP. Nada mas.
func _set_active_unit(unit: CombatUnit) -> void:
	if _active_badge != null:
		_active_badge.visible = unit != null
	if _active_frame != null:
		_active_frame.visible = unit != null
	if unit == null:
		active_name.text = "Preparando el combate..."
		active_hp.max_value = 100.0
		active_hp.value = 0.0
		active_sp.text = ""
		active_portrait.setup("", VisualIdentity.INK_DIM, "short", "", "icon")
		active_bar.modulate = Color(1, 1, 1, 0.55)
		return

	active_bar.modulate = Color(1, 1, 1, 1)
	var tint: Color = TypeColors.color_for(unit.type)
	if _active_frame != null:
		# El aro dorado marca el turno; el color del TIPO lo pone el propio
		# retrato (ui/portrait.gd), asi que cambiar de personaje se ve sin leer
		# ningun texto.
		_active_frame.modulate = Color(1, 1, 1, 1)
	# El personaje del turno ocupa el hueco grande de la barra inferior. Si es del
	# jugador se ve de espaldas (es el que ataca al rival que tiene delante) y si
	# es el rival, de frente.
	var art_slot := "back" if unit.is_ally else "front"
	# La forma (SSR/UR/LR) viaja hasta el retrato: un personaje evolucionado
	# ensena el arte de su forma nueva, y si esa forma no tiene PNG se cae al
	# arte base sin romperse.
	active_portrait.setup(unit.id, tint, unit.portrait_style, unit.art_for(art_slot), art_slot, GameState.form_of(unit.id))
	active_name.text = unit.display_name

	var max_value := maxf(1.0, unit.max_hp())
	if is_equal_approx(active_hp.max_value, max_value):
		active_hp.value = unit.hp
	else:
		active_hp.max_value = max_value
		var tween := create_tween()
		tween.tween_property(active_hp, "value", unit.hp, 0.28).set_trans(Tween.TRANS_CUBIC)

	var sp_text := "SP %d / %d" % [unit.sp, CombatUnit.SP_MAX]
	if unit.statuses.size() > 0:
		sp_text += "    %s" % unit.status_text().to_upper()
	active_sp.text = sp_text


func _sync_active_bar() -> void:
	if current_actor == null:
		return
	active_hp.max_value = maxf(1.0, current_actor.max_hp())
	active_hp.value = current_actor.hp
	active_sp.text = "SP %d / %d" % [current_actor.sp, CombatUnit.SP_MAX]


## El personaje del turno da un golpe de escala y su marco se enciende: es lo que
## deja claro quien esta actuando ahora mismo sin leer ningun texto, y vuelve solo
## a su tamano normal. No mueve el retrato de sitio, asi que no descuadra la fila.
func _pulse_active_portrait() -> void:
	if active_portrait == null:
		return
	active_portrait.pivot_offset = active_portrait.size * 0.5
	var tween := create_tween()
	tween.tween_property(active_portrait, "scale", Vector2(1.06, 1.06), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(active_portrait, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_CUBIC)
	if _active_badge != null:
		_active_badge.pivot_offset = _active_badge.size * 0.5
		_active_badge.scale = Vector2(0.9, 0.9)
		var badge_tween := create_tween()
		badge_tween.tween_property(_active_badge, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _active_frame != null:
		# Latido del aro: entra encendido desde casi transparente. modulate solo
		# puede atenuar, asi que el destello se hace subiendo desde abajo.
		_active_frame.modulate = Color(1, 1, 1, 0.35)
		var frame_tween := create_tween()
		frame_tween.tween_property(_active_frame, "modulate", Color(1, 1, 1, 1), 0.40).set_trans(Tween.TRANS_CUBIC)


## Empujon corto de escala. Se usa en los paneles que aparecen (dialogo de salida)
## para que la aparicion se note sin mover nada de sitio.
func _pulse(node: Control) -> void:
	if node == null:
		return
	node.pivot_offset = node.size * 0.5
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2(1.03, 1.03), 0.10)
	tween.tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC)


## Retroalimentacion visual: aviso de lo que se ha usado, destello en quien
## recibe, destello suave en quien actua, y numeros flotantes con el resultado.
func _play_feedback(payload: Dictionary) -> void:
	var hits: Array = payload.get("hits", [])
	var actor_key := String(payload.get("actor_key", ""))
	var kind := String(payload.get("kind", "basic"))
	var skill_name := String(payload.get("skill_name", ""))

	# Que se ha usado, antes que cuanto ha hecho: una Super o una pasiva se
	# anuncian con su nombre.
	if not skill_name.is_empty():
		if kind == "special":
			_spawn_banner(skill_name.to_upper(), GOLD)
		elif kind == "ultimate":
			pass
		elif kind == "passive":
			_spawn_banner("PASIVA  %s" % skill_name, Color(1.0, 0.86, 0.5, 1.0))

	if cards.has(actor_key):
		var actor_card: UnitCard = cards[actor_key]
		actor_card.flash(Color(0.7, 0.85, 1.0), 0.5)
	_play_action_fx(actor_key, kind, skill_name, hits)

	var stack := 0
	for hit in hits:
		var key := String(hit.get("target_key", ""))
		if not cards.has(key):
			continue
		var card: UnitCard = cards[key]
		var middle := card.global_position + card.size * 0.5 + Vector2(0, -34.0 * float(stack))
		match String(hit.get("kind", "")):
			"damage":
				if bool(hit.get("dodged", false)):
					_spawn_popup(middle, "ESQUIVA", EFFECT_COLOR)
					card.flash(EFFECT_COLOR, 0.6)
				else:
					var amount := int(round(float(hit.get("value", 0.0))))
					if bool(hit.get("crit", false)):
						# Un critico se anuncia: numero grande y etiqueta.
						_spawn_popup(middle, str(amount), CRIT_COLOR, 58)
						stack += 1
						_spawn_popup(
							card.global_position + card.size * 0.5 + Vector2(0, -34.0 * float(stack)),
							"CRITICO!",
							CRIT_COLOR,
							40
						)
					else:
						_spawn_popup(middle, str(amount), DAMAGE_COLOR)
					# Ventaja o desventaja de tipo: el multiplicador sale del
					# motor de dano (hit.type_mult) y aqui solo se avisa. El
					# jugador nunca ve el numero, solo el aviso.
					var type_mult := float(hit.get("type_mult", 1.0))
					if not is_equal_approx(type_mult, 1.0):
						stack += 1
						var advantage := type_mult > 1.0
						_spawn_popup(
							card.global_position + card.size * 0.5 + Vector2(0, -34.0 * float(stack)),
							"VENTAJA DE TIPO!" if advantage else "DESVENTAJA DE TIPO",
							ADVANTAGE_COLOR if advantage else DISADVANTAGE_COLOR,
							34
						)
					card.flash(Color(1.0, 0.35, 0.35), 0.9)
			"heal":
				var healed := int(round(float(hit.get("value", 0.0))))
				if healed > 0:
					_spawn_popup(middle, "+%d HP" % healed, HEAL_COLOR)
					card.flash(HEAL_COLOR, 0.7)
			"stat_mod":
				var stat_name := String(hit.get("stat", ""))
				# Mismo formateo que el panel y el registro: lo decide StatBlock.
				_spawn_popup(
					middle,
					"%s %s" % [
						StatBlock.label(stat_name),
						StatBlock.mod_value_text(
							stat_name,
							String(hit.get("mod_kind", "mult")),
							float(hit.get("value", 0.0))
						),
					],
					EFFECT_COLOR
				)
			"status":
				_spawn_popup(middle, String(hit.get("value", "")).to_upper(), Color(0.95, 0.6, 0.95, 1.0))
			"sp_gain":
				pass
		stack += 1


## Efectos y sonido de la accion. Ataque normal = paso adelante + golpe en los
## objetivos; ESPECIAL = secuencia de ulti (oscurecer, lineas, zoom, flash, temblor).
## Los sonidos salen del catalogo de audio (sin archivo = silencio, sin error).
func _play_action_fx(actor_key: String, kind: String, skill_name: String, hits: Array) -> void:
	var target_cards: Array = []
	var any_crit := false
	var any_heal := false
	for hit in hits:
		var key := String(hit.get("target_key", ""))
		if cards.has(key) and not target_cards.has(cards[key]):
			var is_damage := String(hit.get("kind", "")) == "damage"
			if is_damage:
				target_cards.append(cards[key])
		if bool(hit.get("crit", false)):
			any_crit = true
		if String(hit.get("kind", "")) == "heal":
			any_heal = true
	var actor: CombatUnit = manager.find_unit(actor_key) if manager != null else null
	var tint: Color = TypeColors.color_for(actor.type) if actor != null else GOLD
	var actor_node: Control = active_portrait if actor != null and current_actor != null and current_actor.source_key == actor_key else null
	if kind == "ultimate":
		_play_form_ultimate(actor, skill_name, target_cards, hits)
	elif kind == "special":
		GameAudio.play("special")
		CombatFx.ultimate(self, actor_node, skill_name, tint, target_cards)
	elif kind == "basic":
		GameAudio.play("critical" if any_crit else "attack")
		CombatFx.attack(actor_node, target_cards, any_crit)
	if any_heal:
		GameAudio.play("heal")
	fx_played += 1


## Presentacion cinematografica de la ultimate de forma: colores, protagonistas y
## avisos salen de los DATOS del personaje (summon_cinematic / art_fallback_ids y los
## efectos de la ultimate), no de este script.
func _play_form_ultimate(actor: CombatUnit, skill_name: String, target_cards: Array, hits: Array) -> void:
	GameAudio.play("special")
	GameAudio.play("evolution")
	var cfg = DB.get_character(actor.id).get("summon_cinematic", {}) if actor != null else {}
	var accent := Color.html(String((cfg as Dictionary).get("accent", "#f5e642"))) if cfg is Dictionary and not (cfg as Dictionary).is_empty() else GOLD
	var accent2 := Color.html(String((cfg as Dictionary).get("accent2", "#27e6d6"))) if cfg is Dictionary and not (cfg as Dictionary).is_empty() else Color(0.4, 0.9, 1.0)
	var heroes: Array = DB.get_character(actor.id).get("art_fallback_ids", []) if actor != null else []
	if heroes.size() < 2 and actor != null:
		heroes = [actor.id, actor.id]
	var notes: Array = []
	if actor != null:
		for effect in actor.ultimate.get("effects", []):
			if not (effect is Dictionary) or String(effect.get("type", "")) != "stat_mod":
				continue
			var value := float(effect.get("value", 0.0))
			var who := "EQUIPO" if String(effect.get("target", "")).begins_with("ally") else "RIVALES"
			notes.append({
				"text": "%s  %s %s  (%d turnos)" % [who, StatBlock.label(String(effect.get("stat", ""))), StatBlock.mod_value_text(String(effect.get("stat", "")), String(effect.get("kind", "mult")), value), int(effect.get("turns", 0))],
				"color": HEAL_COLOR if value >= 0.0 else Color(1.0, 0.45, 0.5),
			})
	_ult_fx_active = true
	ultimate_fx_count += 1
	CombatFx.edgerunners(self, skill_name, accent, accent2, heroes, target_cards, notes, func(): _ult_fx_active = false)


## Cuantos efectos de accion se han lanzado (lo usan las pruebas).
var fx_played := 0


func _spawn_popup(origin: Vector2, text: String, color: Color, font_size: int = 44) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 7)
	label.horizontal_alignment = 1
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 20
	label.position = origin - Vector2(90, 34)
	label.custom_minimum_size = Vector2(180, 0)
	add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 120.0, 0.85)
	tween.tween_property(label, "modulate:a", 0.0, 0.85).set_delay(0.15)
	tween.finished.connect(label.queue_free)


## Aviso grande y breve con el nombre de la habilidad o de la pasiva. No bloquea
## el toque (la interfaz sigue siendo jugable mientras se desvanece).
func _spawn_banner(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 52)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	label.add_theme_constant_override("outline_size", 9)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 18
	label.size = Vector2(size.x, 80)
	label.position = Vector2(0, size.y * 0.30)
	label.pivot_offset = Vector2(size.x * 0.5, 40)
	add_child(label)
	label.scale = Vector2(0.9, 0.9)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.75)
	tween.finished.connect(label.queue_free)
