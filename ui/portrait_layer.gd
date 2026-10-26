extends Control

## Capa de dibujo de un Portrait. El retrato pinta el arte en una capa propia (para
## poder aplicarle el shader de iluminacion sin tocar el marco) y el marco en otra
## por encima. Solo delega: el dibujo real esta en Portrait.paint_art/paint_frame.

var portrait = null
var kind := "art"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if portrait == null:
		return
	if kind == "art":
		portrait.paint_art(self)
	else:
		portrait.paint_frame(self)
