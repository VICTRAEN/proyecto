extends Control

const NAV := preload("res://scenes/nav.gd")
const VI := preload("res://ui/visual_identity.gd")

## AJUSTES: audio, combate, interfaz y accesibilidad.
##
## Los valores viven en GameSettings (autoload) y se guardan en user://settings.json.
## Esta pantalla solo PINTA controles y le dice a GameSettings lo que el jugador
## toca; cada cambio se aplica al momento y se guarda solo (los sliders guardan al
## soltar o medio segundo despues del ultimo cambio, no en cada pixel).
##
## Las opciones se construyen por codigo a partir de una lista (ver _build_ui), asi
## que anadir una opcion nueva es una linea mas aqui y una entrada en GameSettings.
##
## Todos los controles miden al menos VI.TOUCH * 0.75 de alto: se pulsan con el dedo.

## Segundos que se espera tras el ultimo cambio de un slider antes de guardar.
const SAVE_DELAY := 0.5

@onready var main: VBoxContainer = $Margin/Main

var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
## key -> { valor: Button }
var _choice_buttons: Dictionary = {}
var _save_timer: Timer = null
var _back_button: Button = null


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(_save_now)
	add_child(_save_timer)
	_build_ui()


## Al entrar en la pantalla se vuelven a leer los valores (por si cambiaron).
func refresh() -> void:
	for key in _sliders.keys():
		var slider: HSlider = _sliders[key]
		slider.set_value_no_signal(roundf(GameSettings.volume(String(key)) * 100.0))
		_update_value_label(String(key), slider.value)
	for key in _choice_buttons.keys():
		_sync_choice(String(key))


## --- Construccion ---------------------------------------------------------------

func _build_ui() -> void:
	var title := Label.new()
	title.text = "AJUSTES"
	VI.style_title(title, VI.FONT_BIG)
	main.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Se guardan solos en este dispositivo."
	VI.style_subtitle(subtitle)
	main.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 16)
	scroll.add_child(list)

	var audio := _section(list, "AUDIO")
	_add_slider(audio, "Musica", "music_volume")
	_add_slider(audio, "Efectos", "sfx_volume")
	_add_slider(audio, "Sonidos de interfaz", "ui_volume")

	var combat := _section(list, "COMBATE")
	_add_choice(combat, "Velocidad de combate", "battle_speed", [["normal", "NORMAL"], ["fast", "RAPIDA"]])
	_add_choice(combat, "Velocidad de animaciones", "anim_speed", [["normal", "NORMAL"], ["fast", "RAPIDA"]])

	var interface := _section(list, "INTERFAZ")
	_add_choice(interface, "Tamano de texto e interfaz", "text_size", [["normal", "NORMAL"], ["large", "GRANDE"]])
	_add_choice(interface, "Numeros de dano", "show_damage", [[true, "SI"], [false, "NO"]])
	_add_choice(interface, "Indicadores de ventaja", "show_advantage", [[true, "SI"], [false, "NO"]])

	var access := _section(list, "ACCESIBILIDAD")
	_add_choice(access, "Animaciones reducidas", "reduce_motion", [[true, "SI"], [false, "NO"]])

	# DEV TOOLS (temporal): panel solo en compilaciones de depuracion. Ver res://dev/README.md
	if ResourceLoader.exists("res://dev/dev_tools.gd") and load("res://dev/dev_tools.gd").enabled():
		list.add_child(load("res://dev/dev_tools_panel.gd").new())

	var note := Label.new()
	note.text = "Tamano GRANDE agranda todo el juego (texto y botones)."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	VI.style_note(note)
	list.add_child(note)

	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "VOLVER"
	_back_button.custom_minimum_size = Vector2(0, VI.TOUCH)
	VI.tint_button(_back_button, VI.BLUE)
	_back_button.pressed.connect(_back)
	main.add_child(_back_button)

	refresh()


## Una seccion: titulo pequeno y un panel con sus filas. Devuelve el contenedor de filas.
func _section(parent: Control, title_text: String) -> VBoxContainer:
	var title := Label.new()
	title.text = title_text
	VI.style_title(title, VI.FONT_SMALL)
	parent.add_child(title)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", VI.panel(0.9, true))
	parent.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	panel.add_child(rows)
	return rows


func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", VI.FONT_BODY)
	label.add_theme_color_override("font_color", VI.INK)
	return label


## Fila con un slider 0-100%.
func _add_slider(parent: Control, text: String, key: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var label := _row_label(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var value_label := _row_label("")
	value_label.add_theme_color_override("font_color", VI.GOLD)
	head.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.custom_minimum_size = Vector2(0, VI.TOUCH * 0.6)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_slider_changed.bind(key))
	slider.drag_ended.connect(_on_slider_released.bind(key))
	box.add_child(slider)

	_sliders[key] = slider
	_value_labels[key] = value_label


## Fila con varias opciones excluyentes (NORMAL | RAPIDA, SI | NO...).
func _add_choice(parent: Control, text: String, key: String, options: Array) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	box.add_child(_row_label(text))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	var group := ButtonGroup.new()
	var buttons: Dictionary = {}
	for option in options:
		var value: Variant = (option as Array)[0]
		var button := Button.new()
		button.text = String((option as Array)[1])
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, VI.TOUCH * 0.75)
		button.set_meta("sfx", "select")
		button.pressed.connect(_on_choice_pressed.bind(key, value))
		row.add_child(button)
		buttons[value] = button
	_choice_buttons[key] = buttons


## --- Reacciones ------------------------------------------------------------------

func _on_slider_changed(value: float, key: String) -> void:
	GameSettings.set_value(key, value / 100.0, false)
	_update_value_label(key, value)
	_save_timer.start()


## Al soltar: se guarda ya y se oye un ejemplo del volumen elegido.
func _on_slider_released(_changed: bool, key: String) -> void:
	_save_now()
	match key:
		"sfx_volume":
			GameAudio.play("attack")
		"ui_volume":
			GameAudio.play("click")


func _on_choice_pressed(key: String, value: Variant) -> void:
	GameSettings.set_value(key, value)
	_sync_choice(key)


func _save_now() -> void:
	_save_timer.stop()
	GameSettings.save_settings()


func _update_value_label(key: String, value: float) -> void:
	var label: Label = _value_labels.get(key)
	if label != null:
		label.text = "%d%%" % int(round(value))


## Marca en dorado la opcion activa de una fila.
func _sync_choice(key: String) -> void:
	var buttons: Dictionary = _choice_buttons.get(key, {})
	var current: Variant = GameSettings.get_value(key)
	for value in buttons.keys():
		var button: Button = buttons[value]
		var active: bool = value == current
		button.set_pressed_no_signal(active)
		VI.tint_button(button, VI.GOLD if active else VI.INK_DIM)


func _back() -> void:
	_save_now()
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")
