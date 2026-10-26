extends PanelContainer

const VI := preload("res://ui/visual_identity.gd")
const Portrait := preload("res://ui/portrait.gd")
const RarityFx := preload("res://ui/rarity_fx.gd")
const TypeColors := preload("res://ui/type_colors.gd")

## CARTA VERTICAL de la COLECCION: el personaje es el protagonista. Arte de cuerpo
## entero (ranura front) en un marco de rareza, la rareza como chapa en la esquina y
## nombre + nivel debajo. Misma interfaz que ui/roster_card: senal pressed(data) y
## bind(data, selected, extra). Sin PNG se ve la silueta del color del tipo.
##
## LA RAREZA SE NOTA: SR sencilla, SSR dorada con brillo, UR rosa con mas borde y LR
## cian/dorada con halo animado (lo pinta VI.rarity_card). Un personaje no obtenido
## se ve como silueta con "???".

signal pressed(data: Dictionary)

var data: Dictionary = {}
var _frame = null
var _glow_tween: Tween = null
## Alto del arte: la coleccion usa 250; el equipo, mas pequeno en la lista.
var art_height := 250.0


func bind(new_data: Dictionary, selected: bool = false, extra: String = "") -> void:
	data = new_data
	for child in get_children():
		remove_child(child)
		child.queue_free()
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var owned := bool(data.get("owned", true))
	var id := String(data.get("id", ""))
	var rarity := String(data.get("rarity", "R")) if owned else ""
	var tint: Color = TypeColors.color_for(String(data.get("type", "STR"))) if owned else VI.INK_DIM
	_frame = VI.rarity_card(rarity, selected, false)
	_frame.content_margin_left = 6
	_frame.content_margin_right = 6
	_frame.content_margin_top = 6
	_frame.content_margin_bottom = 8
	add_theme_stylebox_override("panel", _frame)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

	var art_holder := Control.new()
	art_holder.custom_minimum_size = Vector2(0, art_height)
	art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art_holder)
	var art := Portrait.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_holder.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if owned:
		art.setup(id, tint, String(data.get("portrait_style", "short")), Portrait.art_path_from(data, "front"), "front", "")
	else:
		art.setup("", VI.INK_DIM, String(data.get("portrait_style", "short")), "", "front", "")

	var badge := VI.rarity_badge(rarity if owned else "?", VI.FONT_BODY)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_holder.add_child(badge)
	badge.position = Vector2(8, 4)
	if owned and VI.rarity_rank(rarity) >= VI.rarity_rank("UR"):
		_start_glow()
		var fx := Control.new()
		fx.set_script(RarityFx)
		art_holder.add_child(fx)
		fx.call("setup", rarity)

	var name_label := Label.new()
	name_label.text = String(data.get("name", id)) if owned else "???"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	name_label.add_theme_color_override("font_color", tint)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_label)
	var meta := Label.new()
	var parts := PackedStringArray()
	if owned:
		parts.append(String(data.get("type", "")))
		parts.append("Nv.%d" % int(data.get("level", 1)))
	else:
		parts.append("NO OBTENIDO")
	if not extra.is_empty():
		parts.append(extra)
	meta.text = "  ".join(parts)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.clip_text = true
	meta.add_theme_font_size_override("font_size", VI.FONT_TINY)
	meta.add_theme_color_override("font_color", VI.INK_SOFT)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(meta)


## Halo que respira en UR y LR: es lo que las separa de un vistazo del resto.
func _start_glow() -> void:
	if GameSettings != null and GameSettings.reduce_motion():
		return
	if _glow_tween != null:
		_glow_tween.kill()
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(self, "modulate", Color(1.12, 1.12, 1.12, 1.0), 1.0).set_trans(Tween.TRANS_SINE)
	_glow_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 1.0).set_trans(Tween.TRANS_SINE)


func _gui_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		pressed.emit(data)
