extends RefCounted
class_name ScreenFade

## Fundido de pantalla: evita el salto seco entre menu, pantallas y combate.
##
## Es una capa de color que se pinta por encima de todo, se pone opaca y se
## desvanece en un instante. No bloquea el toque (el jugador puede seguir
## pulsando) y se reutiliza el mismo nodo en cada transicion, asi que no se
## acumulan capas por mucho que se navegue.
##
## No guarda estado: se llama y ya. Uso: ScreenFade.play(self) al abrir algo.

const FADE_COLOR := Color(0.02, 0.02, 0.05, 1.0)
const FADE_TIME := 0.22
const NODE_NAME := "TransitionFade"


## Destello de fundido sobre la ventana de `host`. Si ya existe la capa, se
## reutiliza en lugar de crear otra.
static func play(host: Node, duration: float = FADE_TIME) -> void:
	if host == null:
		return
	var fade: ColorRect = null
	var existing := host.get_node_or_null(NODE_NAME)
	if existing is ColorRect:
		fade = existing
	else:
		fade = ColorRect.new()
		fade.name = NODE_NAME
		fade.color = FADE_COLOR
		# Nunca se come un toque: es decorativo.
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.add_child(fade)
	fade.visible = true
	fade.modulate.a = 1.0
	var tween := host.create_tween()
	tween.tween_property(fade, "modulate:a", 0.0, duration)
	tween.finished.connect(func() -> void: fade.visible = false)
