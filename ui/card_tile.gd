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
		# "form_override": una COPIA se ve en su calidad inicial (p. ej. SSR) aunque la
		# unidad del jugador haya evolucionado y tenga otra forma.
		art.setup(id, tint, String(data.get("portrait_style", "short")), Portrait.art_path_from(data, "front"), "front", String(data.get("form_override", "")))
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

	# Circulo de COPIAS disponibles (x3) en la esquina: material que se puede consumir
	# como Dupe. Una sola carta por calidad y personaje: si la unidad esta en esa misma
	# calidad el contador va en su propia carta; si evoluciono, hay una carta de copias.
	var copies := int(data.get("copy_count", 0))
	if owned and copies > 0:
		var circle := PanelContainer.new()
		circle.name = "CopyBadge"
		circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var disc := StyleBoxFlat.new()
		disc.bg_color = Color(0.05, 0.30, 0.38, 0.97)
		disc.set_corner_radius_all(40)
		disc.set_border_width_all(3)
		disc.border_color = Color(0.45, 0.95, 1.0, 1.0)
		disc.shadow_color = Color(0.2, 0.9, 1.0, 0.5)
		disc.shadow_size = 8
		disc.content_margin_left = 9.0
		disc.content_margin_right = 9.0
		disc.content_margin_top = 2.0
		disc.content_margin_bottom = 2.0
		circle.add_theme_stylebox_override("panel", disc)
		var count_text := Label.new()
		count_text.name = "CopyCount"
		count_text.text = "×%d" % copies
		count_text.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		count_text.add_theme_color_override("font_color", Color.WHITE)
		count_text.add_theme_color_override("font_outline_color", Color(0, 0.1, 0.15, 0.9))
		count_text.add_theme_constant_override("outline_size", 4)
		count_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		circle.add_child(count_text)
		art_holder.add_child(circle)
		circle.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
		circle.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		circle.offset_right = -6.0
		circle.offset_left = -6.0 - 56.0
		circle.offset_top = 6.0

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
		if bool(data.get("copy_only", false)) or bool(data.get("is_copy", false)):
			parts.append("COPIAS")
		else:
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
