extends PanelContainer

const CombatUnit := preload("res://core/combat_unit.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")
const VisualIdentity := preload("res://ui/visual_identity.gd")

## Ficha de una unidad dentro de la barra de ORDEN DE ATAQUE.
##
## Solo pinta: recibe la unidad, un estado ya decidido por la barra ("next",
## "done", "waiting", "dead") y su posicion en la ronda. No calcula el orden ni la
## velocidad.
##
## Se lee de un golpe:
##   next    -> borde dorado, brillo, la ficha crece y el aviso dice AHORA
##   waiting -> numero de turno (#3) y tamano normal: quien viene despues
##   done    -> ya ha actuado, apagada y sin numero que prometa un turno
##   dead    -> K.O. en rojo, casi transparente
## Todo el color sale de ui/visual_identity.gd y del color de tipo.

var unit: CombatUnit = null

## Ultimo estado pintado. Se guarda para animar SOLO cuando la ficha pasa a
## "le toca": bind() se llama varias veces dentro del mismo turno y sin esta
## guarda el pulso se repetiria en cada refresco.
var _last_state := ""

@onready var portrait: Portrait = $VBox/Portrait
@onready var name_label: Label = $VBox/NameLabel
@onready var marker: Label = $VBox/Marker

var _frame := StyleBoxFlat.new()


func _ready() -> void:
	_frame.set_corner_radius_all(VisualIdentity.RADIUS_CHIP + 2)
	add_theme_stylebox_override("panel", _frame)
	marker.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# El pivote se recalcula al cambiar de tamano: el pulso de "le toca" se
	# escala desde el centro de la ficha, no desde su esquina.
	resized.connect(_on_resized)


func bind(new_unit: CombatUnit, state: String, position_in_round: int = 0) -> void:
	unit = new_unit
	if unit == null:
		return
	var tint: Color = TypeColors.color_for(unit.type)
	portrait.setup(unit.id, tint, unit.portrait_style, unit.art_for("icon"), "icon")
	name_label.text = unit.display_name
	name_label.add_theme_color_override("font_color", tint)

	var is_next := state == "next"
	var is_dead := state == "dead"

	marker.visible = true
	marker.text = ""
	if is_next:
		marker.text = "AHORA"
		marker.add_theme_color_override("font_color", VisualIdentity.GOLD)
	elif is_dead:
		marker.text = "K.O."
		marker.add_theme_color_override("font_color", VisualIdentity.RED)
	elif state == "waiting" and position_in_round > 0:
		# El numero de la ronda dice quien va despues sin necesidad de flechas.
		marker.text = "#%d" % position_in_round
		marker.add_theme_color_override("font_color", VisualIdentity.INK_SOFT)
	else:
		marker.text = "-"
		marker.add_theme_color_override("font_color", VisualIdentity.INK_DIM)

	if is_next:
		_frame.set_border_width_all(4)
		_frame.border_color = VisualIdentity.GOLD
		_frame.bg_color = Color(tint.r * 0.28, tint.g * 0.26, tint.b * 0.36, 1.0)
		_frame.shadow_color = Color(VisualIdentity.GOLD.r, VisualIdentity.GOLD.g, VisualIdentity.GOLD.b, 0.50)
		_frame.shadow_size = 14
		_frame.shadow_offset = Vector2.ZERO
		modulate = Color(1, 1, 1, 1)
		scale = Vector2.ONE
	elif is_dead:
		_frame.set_border_width_all(2)
		_frame.border_color = Color(VisualIdentity.RED.r, VisualIdentity.RED.g, VisualIdentity.RED.b, 0.7)
		_frame.bg_color = Color(VisualIdentity.BG.r, VisualIdentity.BG.g, VisualIdentity.BG.b, 0.93)
		_frame.shadow_size = 0
		_frame.shadow_offset = Vector2.ZERO
		modulate = Color(1, 1, 1, 0.34)
		scale = Vector2.ONE
	else:
		# waiting y done comparten marco: solo cambia el brillo. Asi no hay dos
		# estados que se confundan con el dorado del turno.
		var waiting := state == "waiting"
		_frame.set_border_width_all(2)
		_frame.border_color = Color(tint.r, tint.g, tint.b, 0.60 if waiting else 0.35)
		_frame.bg_color = Color(VisualIdentity.PANEL.r, VisualIdentity.PANEL.g, VisualIdentity.PANEL.b, 0.90)
		_frame.shadow_size = 0
		_frame.shadow_offset = Vector2.ZERO
		modulate = Color(1, 1, 1, 1) if waiting else Color(1, 1, 1, 0.46)
		scale = Vector2.ONE

	var state_changed := state != _last_state
	_last_state = state
	if is_next and state_changed:
		_pulse()


func _on_resized() -> void:
	pivot_offset = size * 0.5


## Latido del turno: la ficha crece lo justo para que el ojo vaya a ella y vuelve.
func _pulse() -> void:
	pivot_offset = size * 0.5
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.10, 1.10), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.24).set_trans(Tween.TRANS_CUBIC)
