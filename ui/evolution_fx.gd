extends Control

const VI := preload("res://ui/visual_identity.gd")

## TRANSICION DE EVOLUCION. Es la pantalla que tapa el momento en que un personaje
## pasa de una forma a otra (SSR -> UR, UR -> LR).
##
## Es un solo sitio para toda la transicion: se construye por codigo, se cuelga del
## nodo que la pide, se pinta sola y se borra al terminar. Nadie mas dibuja un
## cambio de forma.
##
## Los colores salen del SISTEMA CENTRAL DE RAREZAS (res://ui/visual_identity.gd):
## la forma vieja entra con el color de su rareza y la nueva con el suyo, asi que
## una evolucion a UR se ve distinta de una a LR sin escribir nada aqui.
##
## No es una animacion compleja a proposito: fundido, el texto EVOLUCION, el antes
## y el despues y un destello del color de la forma nueva. Suficiente para que se
## entienda que ha pasado algo importante, y barato en movil.

const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")

var _from_id := ""
var _to_id := ""
var _old_art: Control = null
var _new_art: Control = null
var _flash: ColorRect = null
var _burst: CPUParticles2D = null

const HOLD_TIME := 0.55
const ENTER_TIME := 0.28
const EXIT_TIME := 0.42


## Pinta la transicion dentro de `host`. `from_form` y `to_form` son las rarezas o
## formas como texto ("SSR", "UR", "LR"); si alguna esta vacia se usa un "?".
static func play(host: Node, from_form: String, to_form: String, character_name: String = "", from_id: String = "", to_id: String = "") -> Control:
	if host == null or not is_instance_valid(host):
		return null
	var fx: Control = (load("res://ui/evolution_fx.gd") as GDScript).new()
	fx.name = "EvolutionFx"
	host.add_child(fx)
	fx.set("_from_id", String(from_id))
	fx.set("_to_id", String(to_id if not to_id.is_empty() else from_id))
	fx.call("_build", String(from_form), String(to_form), String(character_name))
	GameAudio.play("evolution")
	# Al ser el ULTIMO hijo queda por encima de todo lo demas, incluidos los
	# botones: mientras dura la transicion no se puede tocar nada debajo.
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return fx


func _build(from_form: String, to_form: String, character_name: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.02, 0.05, 0.90)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := VBoxContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 18)
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_theme_constant_override("separation", 18)

	# Aura: un disco de luz con el color de la forma nueva, centrado en pantalla.
	var rc: Color = VI.rarity_color(to_form)
	var aura := Panel.new()
	var disc := StyleBoxFlat.new()
	disc.bg_color = Color(rc.r, rc.g, rc.b, 0.09)
	disc.set_corner_radius_all(300)
	disc.shadow_color = Color(rc.r, rc.g, rc.b, 0.18)
	disc.shadow_size = 70
	aura.add_theme_stylebox_override("panel", disc)
	aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aura.custom_minimum_size = Vector2(600, 600)
	add_child(aura)
	aura.anchor_left = 0.5
	aura.anchor_right = 0.5
	aura.anchor_top = 0.5
	aura.anchor_bottom = 0.5
	aura.offset_left = -300.0
	aura.offset_right = 300.0
	aura.offset_top = -300.0
	aura.offset_bottom = 300.0
	aura.pivot_offset = Vector2(300, 300)

	if not character_name.is_empty():
		var who := Label.new()
		who.text = character_name.to_upper()
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		VI.style_subtitle(who)
		who.add_theme_font_size_override("font_size", VI.FONT_SECTION)
		center.add_child(who)

	var title := Label.new()
	title.text = "EVOLUCION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	VI.style_title(title, VI.FONT_BIG)
	center.add_child(title)

	# ARTE: el de la forma vieja se ve primero y el de la nueva sustituye al viejo en
	# el mismo sitio. Si una forma no tiene PNG propio, Portrait cae al arte base o a
	# la silueta: nunca falla por falta de arte.
	if not _from_id.is_empty():
		var stage := Control.new()
		stage.custom_minimum_size = Vector2(380, 440)
		stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		center.add_child(stage)
		_old_art = _make_art(_from_id, from_form)
		_new_art = _make_art(_to_id, to_form)
		stage.add_child(_old_art)
		stage.add_child(_new_art)
		_new_art.modulate = Color(1, 1, 1, 0)

	# El antes y el despues, cada uno con el color de su forma.
	var forms := HBoxContainer.new()
	forms.alignment = BoxContainer.ALIGNMENT_CENTER
	forms.add_theme_constant_override("separation", 20)
	center.add_child(forms)

	var old_label := Label.new()
	old_label.text = from_form if not from_form.is_empty() else "?"
	old_label.add_theme_font_size_override("font_size", VI.FONT_TITLE)
	old_label.add_theme_color_override("font_color", VI.rarity_color(from_form))
	old_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	old_label.add_theme_constant_override("outline_size", 8)
	forms.add_child(old_label)

	var arrow := Label.new()
	arrow.text = ">>"
	arrow.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	arrow.add_theme_color_override("font_color", VI.INK_DIM)
	forms.add_child(arrow)

	var new_label := Label.new()
	new_label.text = to_form if not to_form.is_empty() else "?"
	new_label.add_theme_font_size_override("font_size", VI.FONT_TITLE)
	new_label.add_theme_color_override("font_color", VI.rarity_color(to_form))
	new_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	new_label.add_theme_constant_override("outline_size", 8)
	new_label.modulate = Color(1, 1, 1, 0)
	forms.add_child(new_label)

	# El nombre de la forma nueva tampoco es siempre el mismo: se lee de los datos.
	var rarity := VI.rarity_entry(to_form)
	if not rarity.is_empty():
		var note := Label.new()
		note.text = "FORMA %s" % to_form
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		note.add_theme_color_override("font_color", VI.rarity_secondary(to_form))
		center.add_child(note)

	# Destello blanco a pantalla completa y rafaga de particulas del color nuevo.
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_burst = CPUParticles2D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 70
	_burst.lifetime = 1.1
	_burst.explosiveness = 1.0
	_burst.direction = Vector2(0, -1)
	_burst.spread = 180.0
	_burst.initial_velocity_min = 260.0
	_burst.initial_velocity_max = 620.0
	_burst.gravity = Vector2(0, 260)
	_burst.scale_amount_min = 4.0
	_burst.scale_amount_max = 10.0
	_burst.color = VI.rarity_color(to_form)
	add_child(_burst)
	_burst.position = Vector2(540, 800)
	_animate(aura, new_label)


func _make_art(id: String, form_name: String) -> Control:
	var data := GameState.character_data(id)
	var tint: Color = TypeColors.color_for(String(data.get("type", "STR")))
	var art := Portrait.new()
	art.custom_minimum_size = Vector2(380, 440)
	art.size = Vector2(380, 440)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.pivot_offset = Vector2(190, 220)
	art.setup(id, tint, String(data.get("portrait_style", "short")),
		Portrait.art_path_from(data, "front"), "front", form_name)
	return art


func _animate(aura: Control, new_label: Label) -> void:
	var speed := maxf(0.1, GameSettings.anim_speed_scale())
	var calm := GameSettings.reduce_motion()
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	# 1) OSCURECER: la pantalla se apaga y se ve la forma VIEJA.
	tween.tween_property(self, "modulate:a", 1.0, ENTER_TIME / speed)
	tween.parallel().tween_property(aura, "scale", Vector2(1.25, 1.25), HOLD_TIME / speed).set_delay(ENTER_TIME / speed)
	# 2) TEMBLOR: el arte viejo vibra (se omite con animaciones reducidas).
	if _old_art != null and not calm:
		for i in 8:
			tween.tween_property(_old_art, "position", Vector2(randf_range(-14, 14), randf_range(-8, 8)), 0.04 / speed)
		tween.tween_property(_old_art, "position", Vector2.ZERO, 0.04 / speed)
	else:
		tween.tween_interval(HOLD_TIME / speed)
	# 3) FLASH + CAMBIO DE ARTE: en el pico del destello se cambia el arte.
	if _flash != null:
		tween.tween_property(_flash, "color:a", 1.0, 0.12 / speed)
	tween.tween_callback(_swap_art)
	if _flash != null:
		tween.tween_property(_flash, "color:a", 0.0, 0.5 / speed)
	# 4) NUEVA RAREZA: el texto entra y se queda un momento.
	new_label.pivot_offset = new_label.size * 0.5
	new_label.scale = Vector2(2.2, 2.2)
	tween.tween_property(new_label, "modulate:a", 1.0, 0.2 / speed)
	tween.parallel().tween_property(new_label, "scale", Vector2.ONE, 0.35 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.9 / speed)
	tween.tween_property(self, "modulate:a", 0.0, EXIT_TIME / speed)
	tween.tween_callback(queue_free)


## Momento del cambio: el arte viejo desaparece, el nuevo entra con un golpe de
## escala y salta la rafaga de particulas del color de la nueva rareza.
func _swap_art() -> void:
	if _old_art != null and is_instance_valid(_old_art):
		_old_art.modulate = Color(1, 1, 1, 0)
	if _new_art != null and is_instance_valid(_new_art):
		_new_art.modulate = Color(1, 1, 1, 1)
		_new_art.scale = Vector2(1.18, 1.18)
		create_tween().tween_property(_new_art, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _burst != null and not GameSettings.reduce_motion():
		_burst.emitting = true
	swapped = true


## Verdadero cuando el arte ya ha cambiado (lo usan las pruebas).
var swapped := false
