extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")
const STORY_NODE := preload("res://ui/story_node.gd")

## HISTORIA: la lista de los mundos de la historia principal.
##
## Una tarjeta grande por mundo con su nombre, su genero/descripcion y los
## niveles superados (X/N). Los datos salen de DB.all_worlds() y de
## GameState.world_status(id): anadir un mundo es crear su JSON, esta pantalla no
## cambia y no hay ninguna rama del tipo "si el mundo es el numero 1".
##
## Un mundo bloqueado (sus requisitos no se cumplen todavia) se pinta apagado, se
## marca BLOQUEADO y no se puede abrir. Tocar un mundo abierto apunta ese mundo
## con GameState.select_world y abre el MAPA DE MUNDO, que es quien lo pinta.
##
## Los colores y los tamanos salen de res://ui/visual_identity.gd, nunca de aqui.

@onready var title_label: Label = $Margin/Main/Title
@onready var subtitle_label: Label = $Margin/Main/Subtitle
@onready var list: VBoxContainer = $Margin/Main/Scroll/List
@onready var back_button: Button = $Margin/Main/BackButton


func _ready() -> void:
	_apply_identity()
	back_button.pressed.connect(_back)


## Aspecto estatico de la pantalla, con los tokens de la identidad visual.
func _apply_identity() -> void:
	VI.style_title(title_label, VI.FONT_BIG)
	VI.style_subtitle(subtitle_label)
	VI.tint_button(back_button, VI.BLUE)
	back_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)


## La pantalla se repinta cada vez que App la muestra: el progreso puede haber
## cambiado en el combate y los estados tienen que reflejarlo.
func refresh() -> void:
	_build_list()


func _build_list() -> void:
	_clear(list)
	var worlds: Array = DB.all_worlds()
	subtitle_label.text = "%d mundos. Supera un mundo para abrir el siguiente." % worlds.size()
	if worlds.is_empty():
		list.add_child(_note("Todavia no hay mundos de historia."))
		return
	var index := 0
	for world in worlds:
		if not (world is Dictionary):
			continue
		var node := Control.new()
		node.set_script(STORY_NODE)
		list.add_child(node)
		node.call("setup", GameState.world_status(String((world as Dictionary).get("id", ""))), index, index < worlds.size() - 1)
		node.connect("pressed", _on_world_pressed)
		index += 1


func _state_text(unlocked: bool, complete: bool) -> String:
	if not unlocked:
		return "BLOQUEADO"
	if complete:
		return "COMPLETADO"
	return "EN CURSO"


func _action_text(unlocked: bool, complete: bool) -> String:
	if not unlocked:
		return "Sigue la historia del mundo anterior para abrirlo."
	if complete:
		return "Toca para repetir el mapa de este mundo."
	return "Toca para entrar en el mapa."


## Abrir un mundo es apuntarlo con GameState.select_world y abrir el mapa: el
## mapa lee el mundo elegido, asi que volver a entrar devuelve al jugador donde
## estaba.
func _on_world_pressed(world_id: String) -> void:
	if world_id.is_empty() or not GameState.world_unlocked(world_id):
		return
	GameState.select_world(world_id)
	var app := NAV.app_of(self)
	if app != null and app.has_method("open_screen"):
		app.call("open_screen", "world_map")


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", VI.FONT_BODY)
	label.add_theme_color_override("font_color", VI.INK_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	return label


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
