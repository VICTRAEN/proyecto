extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const ROSTER_CARD := preload("res://ui/roster_card.tscn")

## SELECCIONAR BATALLA: el paso entre el menu y el combate.
##
## Los stages salen de DB.all_stages() (res://data/stages/*.json), asi que anadir
## una batalla nueva es crear su JSON: esta pantalla no cambia y no hay ninguna
## lista de enemigos escrita aqui.
##
## El equipo que se lleva es GameState.party, el mismo que lee el combate. Aqui
## solo se muestra: no hay una segunda copia del equipo.
##
## V0.8: cada stage tiene estado, y el estado lo decide GameState, no la pantalla:
##   BLOQUEADO  -> no se puede empezar (su etapa anterior no esta ganada)
##   DISPONIBLE -> se puede empezar
##   COMPLETADO -> ya ganado; se puede repetir
## El desbloqueo es una cadena: el stage N pide el N-1 ganado.
##
## ASPECTO: cada boton de batalla se tinta con la identidad visual segun su
## estado (dorado el elegido, verde el ganado, azul el disponible, apagado el
## bloqueado). Ningun color se escribe aqui a mano.
##
## El ROL de un personaje es un dato interno de diseno y no se pinta aqui.

@onready var title_label: Label = $Margin/Main/Title
@onready var subtitle_label: Label = $Margin/Main/Subtitle
@onready var stage_list: VBoxContainer = $Margin/Main/Scroll/StageList
@onready var lineup: HBoxContainer = $Margin/Main/Lineup
@onready var team_hint: Label = $Margin/Main/TeamHint
@onready var back_button: Button = $Margin/Main/Buttons/BackButton
@onready var team_button: Button = $Margin/Main/Buttons/TeamButton
@onready var start_button: Button = $Margin/Main/Buttons/StartButton

var _selected_stage := ""


func _ready() -> void:
	_apply_identity()
	back_button.pressed.connect(_back)
	team_button.pressed.connect(_goto_team)
	start_button.pressed.connect(_start)


## Aspecto estatico de la pantalla: titulo, nota de apoyo y los tres botones del
## pie con su papel (volver, equipo, comenzar).
func _apply_identity() -> void:
	VI.screen_title(title_label, VI.GOLD)
	VI.style_subtitle(subtitle_label)
	VI.style_note(team_hint)
	VI.tint_button(back_button, VI.BLUE)
	VI.tint_button(team_button, VI.BLUE)
	VI.tint_button(start_button, VI.GOLD)
	for button in [back_button, team_button, start_button]:
		button.custom_minimum_size = Vector2(0, VI.TOUCH)


func refresh() -> void:
	_build_stages()
	_build_lineup()


## --- Batallas ---------------------------------------------------------------

func _build_stages() -> void:
	_clear(stage_list)
	var stages: Array = DB.all_stages()
	if stages.is_empty():
		var empty := Label.new()
		empty.text = "No hay batallas disponibles."
		empty.add_theme_font_size_override("font_size", VI.FONT_BODY)
		empty.add_theme_color_override("font_color", VI.INK_DIM)
		stage_list.add_child(empty)
		start_button.disabled = true
		return

	# Si el stage elegido no existe, no esta desbloqueado (o es la primera vez),
	# se elige el primer stage desbloqueado que siga pendiente: el jugador cae
	# donde toca continuar, no al principio de la lista.
	if not _selection_is_valid(stages):
		_selected_stage = _default_stage(stages)

	for stage in stages:
		var id := String(stage.get("id", ""))
		var unlocked: bool = GameState.stage_unlocked(id)
		var completed: bool = GameState.stage_completed(id)
		var selected := id == _selected_stage and unlocked
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 190)
		button.text = "%s\n%s   -   %s\n%s\nRecompensas: %d XP   %d monedas" % [
			String(stage.get("name", id)),
			String(stage.get("difficulty", "NORMAL")),
			_enemies_text(stage),
			_status_text(unlocked, completed),
			int(stage.get("xp_reward", 0)),
			int(stage.get("coin_reward", 0)),
		]
		button.add_theme_font_size_override("font_size", VI.FONT_BODY)
		button.toggle_mode = true
		button.disabled = not unlocked
		button.button_pressed = id == _selected_stage
		VI.tint_button(button, _stage_accent(unlocked, completed, selected))
		# El color del texto dice lo mismo que el marco: verde ganado, apagado
		# bloqueado, tinta normal disponible y dorado el elegido.
		button.add_theme_color_override("font_color", _stage_ink(unlocked, completed, selected))
		button.pressed.connect(_on_stage_pressed.bind(id))
		stage_list.add_child(button)

	start_button.disabled = not GameState.stage_unlocked(_selected_stage)
	start_button.text = "COMENZAR" if not start_button.disabled else "BLOQUEADO"


## Acento del marco de una batalla segun su estado.
func _stage_accent(unlocked: bool, completed: bool, selected: bool) -> Color:
	if not unlocked:
		return VI.INK_DIM
	if selected:
		return VI.GOLD
	if completed:
		return VI.GREEN
	return VI.BLUE


## Color del texto de una batalla segun su estado.
func _stage_ink(unlocked: bool, completed: bool, selected: bool) -> Color:
	if not unlocked:
		return VI.INK_DIM
	if selected:
		return VI.GOLD
	if completed:
		return VI.GREEN
	return VI.INK


func _status_text(unlocked: bool, completed: bool) -> String:
	if not unlocked:
		return "BLOQUEADO"
	if completed:
		return "COMPLETADO"
	return "DISPONIBLE"


## El stage elegido sigue siendo valido solo si existe y esta desbloqueado.
func _selection_is_valid(stages: Array) -> bool:
	if _selected_stage.is_empty():
		return false
	for stage in stages:
		if String(stage.get("id", "")) == _selected_stage:
			return GameState.stage_unlocked(_selected_stage)
	return false


## Primer stage pendiente desbloqueado; si ya estan todos ganados, el ultimo.
func _default_stage(stages: Array) -> String:
	var first_unlocked := ""
	for stage in stages:
		var id := String(stage.get("id", ""))
		if not GameState.stage_unlocked(id):
			continue
		if first_unlocked.is_empty():
			first_unlocked = id
		if not GameState.stage_completed(id):
			return id
	return first_unlocked


func _enemies_text(stage: Dictionary) -> String:
	var names := PackedStringArray()
	for enemy_id in stage.get("enemies", []):
		var enemy: Dictionary = DB.get_enemy(String(enemy_id))
		names.append(String(enemy.get("name", enemy_id)))
	if names.is_empty():
		return "Sin enemigos"
	return "%d: %s" % [names.size(), ", ".join(names)]


## --- Equipo -----------------------------------------------------------------

func _build_lineup() -> void:
	_clear(lineup)
	for data in GameState.party_data():
		var card = ROSTER_CARD.instantiate()
		lineup.add_child(card)
		card.bind(data, false, "", true)
	team_hint.text = "Tu equipo: %d personajes. Se puede cambiar antes de empezar." % GameState.party.size()


## --- Acciones ---------------------------------------------------------------

func _on_stage_pressed(id: String) -> void:
	if not GameState.stage_unlocked(id):
		return
	_selected_stage = id
	# Elegir batalla queda guardado: al volver al juego sigue la misma.
	GameState.select_stage(id)
	refresh()


func _start() -> void:
	var app := NAV.app_of(self)
	if app == null:
		return
	if _selected_stage.is_empty():
		return
	# Ultima defensa: la pantalla no deja elegir un stage bloqueado, y el combate
	# tampoco se abre con uno.
	if not GameState.stage_unlocked(_selected_stage):
		return
	GameState.select_stage(_selected_stage)
	if app.has_method("open_battle"):
		app.call("open_battle")


func _goto_team() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("open_screen"):
		app.call("open_screen", "team")


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
