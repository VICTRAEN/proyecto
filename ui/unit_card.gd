extends PanelContainer

const CombatUnit := preload("res://core/combat_unit.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")
const VisualIdentity := preload("res://ui/visual_identity.gd")
const ThemeFactory := preload("res://ui/theme_factory.gd")

## Tarjeta de una unidad en combate. Solo pinta; no decide nada.
##
## Muestra lo justo para reconocer a la unidad de un vistazo: ICONO, NOMBRE,
## TIPO, RAREZA, NIVEL, VIDA y SP. El marco lo decide la rareza y el borde el
## tipo. La clasificacion interna de diseno de la unidad NO se pinta en combate:
## no es un dato que el jugador use durante el turno y solo ensuciaba la tarjeta.
##
## Los colores salen de ui/visual_identity.gd (marco, rareza, vida) y de
## ui/type_colors.gd (el tipo). Aqui no hay ni un color suelto.

## La tarjeta avisa cuando el jugador la toca. No sabe quien la escucha.
signal card_pressed(target)

const SP_SLOTS := 3

var unit: CombatUnit = null
var prominent := false
## Varios rivales en pantalla: la tarjeta se hace estrecha para compartir la fila.
var compact := false

@onready var portrait: Portrait = $VBox/Top/Portrait
@onready var name_label: Label = $VBox/Top/Info/NameLabel
@onready var type_chip: Label = $VBox/Top/Info/Chips/TypeChip
@onready var rarity_chip: Label = $VBox/Top/Info/Chips/RarityChip
@onready var level_chip: Label = $VBox/Top/Info/Chips/LevelChip
@onready var hp_label: Label = $VBox/Top/Info/HpLabel
@onready var sp_row: HBoxContainer = $VBox/Top/Info/SpRow
@onready var hp_bar: ProgressBar = $VBox/HpBar

var _pips: Array = []
var _hp_band := -1
var _hp_tween: Tween = null
var _is_active := false
var _inspected := false
var _selectable := false


func _ready() -> void:
	# La tarjeta es interactiva: al tocarla se abre el panel de informacion. Para
	# que el toque llegue siempre a la tarjeta, sus hijos ignoran el raton.
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	resized.connect(_on_resized)
	sp_row.add_theme_constant_override("separation", 4)
	for i in SP_SLOTS:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(24, 22)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp_row.add_child(pip)
		_pips.append(pip)
	_ignore_mouse_on_children(self)


## make_prominent agranda la tarjeta: se usa para el enemigo, que debe dominar
## la parte alta de la pantalla.
##
## make_compact es para cuando hay VARIOS rivales: la tarjeta se hace estrecha y
## comparte la fila con las demas. Sin esto, tres banners de 600 px no caben en
## una pantalla vertical y se saldrian del marco. El combate avisa de cuantos
## rivales hay; la tarjeta no decide nada.
func bind(new_unit: CombatUnit, make_prominent: bool = false, make_compact: bool = false) -> void:
	unit = new_unit
	prominent = make_prominent
	compact = make_compact and make_prominent
	if compact:
		# Varios rivales: todas comparten el ancho de la fila.
		custom_minimum_size = Vector2(150, 0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait.custom_minimum_size = Vector2(0, 140)
		_apply_text_sizes(21, 17, 19)
	elif prominent:
		# Banner del rival: ancho acotado, centrado en su fila y SIN estirarse en
		# vertical. Antes se estiraba a toda la altura disponible y quedaba una
		# columna estrecha con un hueco enorme.
		custom_minimum_size = Vector2(600, 0)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		portrait.custom_minimum_size = Vector2(230, 250)
		_apply_text_sizes(34, 22, 26)
	else:
		# Las tarjetas de aliado llenan su columna de la rejilla: asi las cuatro
		# ocupan el ancho de la pantalla en lugar de apelotonarse a la izquierda.
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait.custom_minimum_size = Vector2(120, 132)
		_apply_text_sizes(25, 18, 22)
	var tint: Color = TypeColors.color_for(unit.type)
	# El rival se muestra de frente; las unidades del jugador, de espaldas.
	# FRONT en las casillas: la fila entera se ve de FRENTE porque es la
	# representacion del EQUIPO. El que esta peleando de verdad es el retrato
	# grande de la barra inferior, que va de ESPALDAS (BACK). Asi el mismo
	# personaje no parece salir dos veces igual durante el combate.
	var art_slot := "front"
	portrait.setup(unit.id, tint, unit.portrait_style, unit.art_for(art_slot), art_slot, GameState.form_of(unit.id))
	name_label.text = unit.display_name
	type_chip.text = unit.type
	type_chip.add_theme_color_override("font_color", tint)
	_apply_identity()
	refresh()


## Rareza, nivel y tipo: tres datos cortos, en una sola linea de etiquetas.
func _apply_identity() -> void:
	if unit == null:
		return
	var rarity := String(unit.rarity)
	rarity_chip.text = rarity if not rarity.is_empty() else "R"
	rarity_chip.add_theme_color_override("font_color", VisualIdentity.rarity_color(rarity))
	level_chip.text = "Nv. %d" % int(unit.level)
	level_chip.add_theme_color_override("font_color", VisualIdentity.INK_SOFT)


func _apply_text_sizes(name_size: int, chip_size: int, hp_size: int) -> void:
	name_label.add_theme_font_size_override("font_size", name_size)
	type_chip.add_theme_font_size_override("font_size", chip_size + 2)
	rarity_chip.add_theme_font_size_override("font_size", chip_size)
	level_chip.add_theme_font_size_override("font_size", chip_size)
	hp_label.add_theme_font_size_override("font_size", hp_size)


func refresh() -> void:
	if unit == null:
		return
	var maximum := unit.max_hp()
	hp_bar.max_value = maxf(1.0, maximum)
	if _hp_tween != null and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = create_tween()
	_hp_tween.tween_property(hp_bar, "value", unit.hp, 0.28).set_trans(Tween.TRANS_CUBIC)
	hp_label.text = "%d / %d" % [int(round(unit.hp)), int(round(maximum))]

	var ratio := unit.hp_ratio()
	# Barra con brillo: el color solo se reconstruye al cambiar de tramo de vida.
	var band := 2 if ratio > 0.5 else (1 if ratio > 0.25 else 0)
	if band != _hp_band:
		_hp_band = band
		var hp_color: Color = [VisualIdentity.RED, VisualIdentity.GOLD, VisualIdentity.GREEN][band]
		hp_bar.add_theme_stylebox_override("fill", ThemeFactory.bar_fill(hp_color))

	for i in _pips.size():
		var pip: Panel = _pips[i]
		var filled: bool = i < unit.sp
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(5)
		var tint: Color = TypeColors.color_for(unit.type)
		style.bg_color = tint if filled else VisualIdentity.BG
		style.set_border_width_all(1)
		style.border_color = Color(tint.r, tint.g, tint.b, 0.55)
		pip.add_theme_stylebox_override("panel", style)

	modulate = Color(1, 1, 1, 1) if unit.alive else Color(1, 1, 1, 0.45)
	_update_frame()


func set_active(is_active: bool) -> void:
	_is_active = is_active and unit != null and unit.alive
	_update_frame()


## Marca la tarjeta como "la que el jugador esta mirando". Es independiente de
## set_active: el personaje inspeccionado no tiene por que ser el del turno.
func set_inspected(is_inspected: bool) -> void:
	_inspected = is_inspected and unit != null
	_update_frame()


## Modo "elige objetivo": marca la tarjeta como candidata. Es un estado de la
## pantalla mientras dura la eleccion, no un estado de la unidad, y por eso manda
## sobre el marco de activo e inspeccionado.
func set_selectable(is_selectable: bool) -> void:
	_selectable = is_selectable and unit != null and unit.alive
	_update_frame()


## Aviso de "te toca": lo usa la pantalla de combate al comenzar un turno.
func bump() -> void:
	if unit == null or not unit.alive:
		return
	pivot_offset = size * 0.5
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.04, 1.04), 0.10)
	tween.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Tocar la tarjeta la marca y avisa hacia arriba. Vale para raton y para dedo:
## en movil, Godot emula el boton izquierdo a partir del toque.
func _on_gui_input(event: InputEvent) -> void:
	if unit == null:
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	_press_feedback()
	card_pressed.emit(unit)
	accept_event()


func _press_feedback() -> void:
	pivot_offset = size * 0.5
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(0.96, 0.96), 0.07)
	tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_resized() -> void:
	pivot_offset = size * 0.5


## Los hijos no interceptan el toque: la tarjeta entera es el boton.
func _ignore_mouse_on_children(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse_on_children(child)


## Destello breve sobre el retrato. Lo usa la pantalla de combate para dar
## feedback de golpe recibido. No toca modulate de la tarjeta, asi que no pelea
## con el estado de "muerto" que fija refresh().
func flash(tint: Color, strength: float = 0.85) -> void:
	if portrait == null:
		return
	portrait.modulate = Color(tint.r, tint.g, tint.b, strength)
	var tween := create_tween()
	tween.tween_property(portrait, "modulate", Color(1, 1, 1, 1), 0.38)


## El marco lo construye VisualIdentity (tipo + brillo de rareza) y aqui solo se
## sobreescribe el estado: elegido (dorado), candidato (verde de VI) o
## inspeccionado (azul de VI). Activo e inspeccionado siguen siendo distintos.
func _update_frame() -> void:
	if unit == null:
		add_theme_stylebox_override("panel", VisualIdentity.card(VisualIdentity.INK_DIM))
		return
	var tint: Color = TypeColors.color_for(unit.type)
	var rarity := String(unit.rarity)
	var style := VisualIdentity.card(tint, _is_active or _selectable, rarity, prominent)
	if _selectable:
		style.border_color = VisualIdentity.GREEN
		style.shadow_color = Color(VisualIdentity.GREEN.r, VisualIdentity.GREEN.g, VisualIdentity.GREEN.b, 0.55)
		style.shadow_size = 16
		style.shadow_offset = Vector2.ZERO
	elif _inspected and not _is_active:
		style.border_color = VisualIdentity.BLUE
		style.shadow_color = Color(VisualIdentity.BLUE.r, VisualIdentity.BLUE.g, VisualIdentity.BLUE.b, 0.45)
		style.shadow_size = 14
		style.shadow_offset = Vector2.ZERO
	add_theme_stylebox_override("panel", style)
