extends Control

const CombatUnit := preload("res://core/combat_unit.gd")
const StatBlock := preload("res://core/stat_block.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")
const VI := preload("res://ui/visual_identity.gd")
const FichaTabs := preload("res://ui/ficha_tabs.gd")
const DupeTab := preload("res://ui/dupe_tab.gd")
const EvolutionFx := preload("res://ui/evolution_fx.gd")

## Panel de informacion de una unidad.
##
## Es un OVERLAY: el combate sigue detras y sigue corriendo. Se abre tocando la
## tarjeta de una unidad y se cierra con el boton, tocando el fondo o con Esc.
##
## Lo estatico (nombre, tipo, pasivas, especial, categorias, links) sale del JSON
## del personaje y de la base de datos; los valores actuales salen del estado vivo
## de la unidad. El panel no conoce ninguna regla de combate: pinta datos que le
## llegan ya resueltos.
##
## El personaje INSPECCIONADO no es el personaje ACTIVO: abrir este panel no
## cambia el turno ni la seleccion.
##
## El MISMO panel sirve para dos cosas:
##   - en combate, la ficha de una unidad viva (con HP, SP, efectos y contadores);
##   - fuera de combate, la FICHA DE PERSONAJE (COLECCION), sin contadores de
##     batalla, pero con nivel, XP y rareza.
##
## CONTRATO (lo usan coleccion, equipo y combate): senal `closed`; is_open();
## open_for(unit, show_combat_stats := true); open_for_data(data,
## show_combat_stats := false); refresh(); close_panel(). La fila de PRUEBA con
## SUBIR NIVEL / ANADIR XP sigue aqui y sigue funcionando.
##
## V1.0 PESTANAS: el cuerpo se reparte en DATOS, HABILIDADES, LINKS, CATEGORIAS y
## BATALLA. La cabecera (retrato, nombre, tipo, rareza, nivel, vida) no cambia.
## El contenido de cada pestana que no depende de la batalla lo construye
## res://ui/ficha_tabs.gd: este archivo se queda con la orquestacion (abrir,
## refrescar, cerrar, progresion) y con la pestana BATALLA, que necesita su nodo
## de contadores ya existente.
##
## BASE y ACTUAL nunca se confunden: BASE es el valor de la unidad a su nivel sin
## mods; ACTUAL es el mismo valor con pasivas, links y buffs encima. El valor base
## no se sobrescribe en ningun sitio, porque los dos se leen por separado.
##
## El ROL del personaje no se muestra nunca: es una clasificacion de diseno.

signal closed
## El jugador cambio algo de la unidad (Dupe, nivel...): las pantallas que la muestran
## (la coleccion con sus contadores de copias) se repintan al momento.
signal changed

## Experiencia que suman los botones de prueba.
const XP_TEST_AMOUNT := 250

const GROUP_COLORS := {
	"ATAQUE": Color(1.0, 0.72, 0.45, 1.0),
	"DEFENSA": Color(0.6, 0.82, 1.0, 1.0),
	"APOYO": Color(0.62, 1.0, 0.75, 1.0),
}

const STATUS_LABELS := {
	"stun": "ATURDIDO",
	"taunt": "PROVOCA",
}

## Etiqueta de cada pestana. Las cinco se construyen siempre; BATALLA solo tiene
## contenido cuando hay una batalla detras (en la coleccion va vacia a proposito).
const TAB_DATOS := 0
const TAB_HABILIDADES := 1
const TAB_LINKS := 2
const TAB_CATEGORIAS := 3
const TAB_BATALLA := 4
const TAB_DUPES := 5

var unit: CombatUnit = null

@onready var dim: ColorRect = $Dim
@onready var panel: PanelContainer = $Center/Panel
@onready var icon: Portrait = $Center/Panel/Margin/VBox/Header/Icon
@onready var kind_label: Label = $Center/Panel/Margin/VBox/Header/HeaderInfo/Kind
@onready var name_label: Label = $Center/Panel/Margin/VBox/Header/HeaderInfo/NameLabel
@onready var type_label: Label = $Center/Panel/Margin/VBox/Header/HeaderInfo/TypeLabel
@onready var hp_text: Label = $Center/Panel/Margin/VBox/Header/HeaderInfo/HpText
@onready var hp_bar: ProgressBar = $Center/Panel/Margin/VBox/HpBar
@onready var level_text: Label = $Center/Panel/Margin/VBox/LevelText
@onready var xp_bar: ProgressBar = $Center/Panel/Margin/VBox/XpBar
@onready var tabs: TabContainer = $Center/Panel/Margin/VBox/Scroll/Tabs
@onready var tab_datos: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/Tabs/TabDatos
@onready var tab_habilidades: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/Tabs/TabHabilidades
@onready var tab_links: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/Tabs/TabLinks
@onready var tab_categorias: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/Tabs/TabCategorias
@onready var tab_batalla: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/Tabs/TabBatalla
@onready var stats_list: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/Tabs/TabBatalla/StatsList
@onready var stats_title: Label = $Center/Panel/Margin/VBox/Scroll/Tabs/TabBatalla/StatsTitle
@onready var dev_row: HBoxContainer = $Center/Panel/Margin/VBox/DevRow
@onready var level_button: Button = $Center/Panel/Margin/VBox/DevRow/LevelButton
@onready var xp_button: Button = $Center/Panel/Margin/VBox/DevRow/XpButton
@onready var close_button: Button = $Center/Panel/Margin/VBox/CloseButton

var _closing := false
## false = ficha de personaje (COLECCION): sin batalla no hay contadores de
## combate que ensenar, asi que esa pestana se avisa en vez de mentir.
var _show_combat_stats := true
## Verdadero cuando el panel es una FICHA fuera de combate. Solo ahi tienen
## sentido el nivel, la XP y los botones de prueba de progresion.
var _is_ficha := false
## Datos del personaje que se esta mirando como ficha. Se guardan para poder
## reconstruir la vista despues de subir de nivel: el nivel ya no es fijo.
var _source_data: Dictionary = {}
## Pestana que el jugador tenia abierta. Se conserva al refrescar para que una
## accion no devuelva la vista al principio.
var _tab_index := TAB_DATOS
## Pestana DUPES (creada por codigo) y estado de su confirmacion de consumo.
var tab_dupes: VBoxContainer = null
var _dupe_confirming := false


func _ready() -> void:
	visible = false
	# Ventana premium: marco dorado biselado con gemas (el contenido no cambia).
	panel.add_theme_stylebox_override("panel", VI.window())
	dim.gui_input.connect(_on_dim_input)
	close_button.pressed.connect(close_panel)
	level_button.pressed.connect(_on_level_pressed)
	xp_button.pressed.connect(_on_xp_pressed)
	# Al tocar una pestana solo se recuerda cual esta abierta: el contenido ya
	# esta construido y no hace falta rehacerlo.
	tabs.tab_changed.connect(_on_tab_changed)
	_setup_tabs()
	resized.connect(_fit)
	panel.resized.connect(_on_panel_resized)
	_fit()


## Nombres de las cinco secciones. Se ponen aqui y no en la escena para que
## anadir una seccion nueva sea una linea.
func _setup_tabs() -> void:
	_rename_tab(TAB_DATOS, "DATOS")
	_rename_tab(TAB_HABILIDADES, "HABILIDADES")
	_rename_tab(TAB_LINKS, "LINKS")
	_rename_tab(TAB_CATEGORIAS, "CATEGORIAS")
	_rename_tab(TAB_BATALLA, "BATALLA")
	if tabs != null and tab_dupes == null:
		tab_dupes = VBoxContainer.new()
		tab_dupes.name = "TabDupes"
		tabs.add_child(tab_dupes)
		_rename_tab(TAB_DUPES, "DUPES")


func _rename_tab(index: int, title: String) -> void:
	if index < tabs.get_tab_count():
		tabs.set_tab_title(index, title)


func is_open() -> bool:
	return visible and unit != null


## Abre el panel sobre una unidad viva del combate. show_combat_stats se pone en
## false cuando el panel se usa como ficha de personaje, fuera de una batalla.
func open_for(new_unit: CombatUnit, show_combat_stats: bool = true) -> void:
	if new_unit == null:
		return
	unit = new_unit
	_dupe_confirming = false
	_show_combat_stats = show_combat_stats
	_is_ficha = not show_combat_stats
	# Una unidad de combate no es una ficha: los datos guardados de la ficha
	# anterior no deben reutilizarse aqui.
	if not _is_ficha:
		_source_data = {}
	visible = true
	# Se vuelve a la pestana que el jugador tenia abierta: subir de nivel o
	# inspeccionar en combate no debe devolver la ficha al principio.
	if tabs != null:
		tabs.current_tab = clampi(_tab_index, 0, maxi(0, tabs.get_tab_count() - 1))
	_fit()
	refresh()
	modulate.a = 0.0
	panel.scale = Vector2(0.94, 0.94)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.16)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Abre el panel como FICHA DE PERSONAJE, fuera de una batalla (COLECCION).
## Se construye un CombatUnit temporal para poder pintar los mismos datos con el
## mismo codigo, pero sin HP ni SP reales: la cabecera se adapta y la pestana de
## estadisticas de combate se explica, porque ahi no hay batalla que contar.
func open_for_data(data: Dictionary, show_combat_stats: bool = false) -> void:
	if data.is_empty():
		return
	_source_data = data
	open_for(_make_preview(), show_combat_stats)
	# Fuera de combate la vida se muestra llena: no es una unidad viva, es su
	# ficha.
	hp_bar.value = hp_bar.max_value
	hp_text.text = "HP %d / %d" % [int(round(unit.max_hp())), int(round(unit.max_hp()))]


## Unidad de vista previa para la ficha: mismo objeto que en combate, pero sin
## batalla detras. El nivel se toma de GameState, que es quien lo sabe.
func _make_preview() -> CombatUnit:
	var data := _source_data
	var id := String(_source_data.get("id", ""))
	if not id.is_empty():
		var live := GameState.character_data(id)
		if not live.is_empty():
			data = live
	var preview := CombatUnit.new()
	preview.setup(data, true, -1)
	return preview


## Vuelve a pintar con el estado ACTUAL de la unidad. La pantalla de combate la
## llama despues de cada accion para que el panel no se quede con datos viejos:
## asi los buffs, las curaciones y los criticos modificadores se ven al dia.
func refresh() -> void:
	if unit == null:
		return
	_fill_header()
	_fill_level()
	_fill_datos()
	_fill_habilidades()
	_fill_links()
	_fill_categorias()
	_fill_dupes()
	_fill_effects()
	_fill_stats()


func close_panel() -> void:
	if not visible or _closing:
		return
	_closing = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.14)
	tween.tween_property(panel, "scale", Vector2(0.96, 0.96), 0.14)
	await tween.finished
	visible = false
	_closing = false
	unit = null
	_source_data = {}
	closed.emit()


func _fit() -> void:
	if panel == null:
		return
	# En movil el panel ocupa casi toda la pantalla; en una ventana ancha se
	# queda centrado con un ancho legible.
	var width := clampf(size.x * 0.94, 460.0, 780.0)
	var height := clampf(size.y * 0.90, 520.0, 1560.0)
	panel.custom_minimum_size = Vector2(width, height)


func _on_panel_resized() -> void:
	panel.pivot_offset = panel.size * 0.5


func _on_tab_changed(index: int) -> void:
	_tab_index = index


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


## --- Cabecera ---------------------------------------------------------------

func _fill_header() -> void:
	var tint: Color = TypeColors.color_for(unit.type)
	icon.setup(unit.id, tint, unit.portrait_style, unit.art_for("icon"), "icon")
	var rarity := String(unit.rarity)
	var where := "PERSONAJE" if _is_ficha else ("ALIADO" if unit.is_ally else "RIVAL")
	kind_label.text = where if rarity.is_empty() else "%s  -  %s" % [where, rarity]
	# La rareza tinta la cabecera: la forma actual (SSR / UR / LR) se lee de un
	# vistazo con el color de su rareza, que sale del sistema central.
	if not rarity.is_empty():
		kind_label.add_theme_color_override("font_color", VI.rarity_color(rarity))
		name_label.add_theme_color_override("font_color", VI.rarity_color(rarity))
	name_label.text = unit.display_name
	type_label.text = unit.type
	type_label.add_theme_color_override("font_color", tint)

	var maximum := maxf(1.0, unit.max_hp())
	hp_bar.max_value = maximum
	hp_bar.value = unit.hp
	hp_text.text = "HP %d / %d      SP %d / %d" % [
		int(round(unit.hp)),
		int(round(maximum)),
		unit.sp,
		CombatUnit.SP_MAX,
	]


## --- Progresion ------------------------------------------------------------

## Nivel y experiencia. La XP necesaria la calcula core/progression.gd, la misma
## formula que usa GameState al sumar experiencia: aqui no se calcula nada.
func _fill_level() -> void:
	var id := unit.id
	var level := int(unit.level)
	var xp := 0
	var needed := 0
	var tracked := not id.is_empty() and GameState.progress.has(id)
	if tracked:
		level = GameState.level_of(id)
		xp = GameState.xp_of(id)
		needed = GameState.xp_to_next(id)

	if needed <= 0:
		# Nivel maximo: la barra queda llena y no se promete mas XP.
		level_text.text = "NIVEL %d  (MAXIMO)" % level
		xp_bar.max_value = 1.0
		xp_bar.value = 1.0
	else:
		level_text.text = "NIVEL %d      %d / %d XP" % [level, xp, needed]
		xp_bar.max_value = float(needed)
		xp_bar.value = float(xp)

	# Los botones de prueba solo tienen sentido sobre un personaje del jugador.
	dev_row.visible = _is_ficha and tracked
	if dev_row.visible:
		var topped := GameState.is_max_level(id)
		level_button.disabled = topped
		xp_button.disabled = topped


## Boton de prueba: sube un nivel exacto. Se quitara cuando haya misiones que den
## experiencia de verdad.
func _on_level_pressed() -> void:
	if unit == null:
		return
	GameState.set_level(unit.id, GameState.level_of(unit.id) + 1)
	_reload_after_progress()


## Boton de prueba: suma experiencia y sube los niveles que correspondan.
func _on_xp_pressed() -> void:
	if unit == null:
		return
	GameState.add_xp(unit.id, XP_TEST_AMOUNT)
	_reload_after_progress()


## Rehace la vista previa con el nivel nuevo. El nivel cambia las estadisticas, y
## estas salen de StatBlock: por eso la ficha y el combate nunca pueden discrepar.
func _reload_after_progress() -> void:
	changed.emit()
	if unit == null:
		return
	if _source_data.is_empty():
		refresh()
		return
	unit = _make_preview()
	hp_bar.value = hp_bar.max_value
	hp_text.text = "HP %d / %d" % [int(round(unit.max_hp())), int(round(unit.max_hp()))]
	refresh()


## --- Datos del personaje ---------------------------------------------------

## El diccionario del personaje que la ficha esta mirando. En combate no hay
## "datos de ficha": se pide a GameState, que es la unica puerta a un personaje,
## y si no lo tiene se cae al JSON con el nivel de la unidad.
func _character_data() -> Dictionary:
	var id := unit.id
	if id.is_empty():
		return {}
	var data := GameState.character_data(id)
	if data.is_empty():
		return {}
	return data


## --- Pestanas -------------------------------------------------------------

func _fill_datos() -> void:
	_clear(tab_datos)
	var data := _character_data()
	var level := int(unit.level)
	var xp := 0
	var needed := 0
	if not unit.id.is_empty() and GameState.progress.has(unit.id):
		level = GameState.level_of(unit.id)
		xp = GameState.xp_of(unit.id)
		needed = GameState.xp_to_next(unit.id)
	tab_datos.add_child(FichaTabs.build_datos(unit, data, level, xp, needed))
	# Fuera de una batalla la ficha ensena ademas la MUTACION activa (o que no
	# tiene) y la EVOLUCION con sus requisitos. Dentro del combate no: ahi la
	# ficha cuenta la unidad que esta peleando, no su progreso.
	if _is_ficha:
		_fill_mutation()
		_fill_evolution()


## MUTACION. El texto de cada estadistica viene ya resuelto por GameState, asi que
## aqui no se calcula ningun porcentaje: se pinta lo que dice el informe.
func _fill_mutation() -> void:
	var id := unit.id
	if id.is_empty() or not GameState.is_owned(id):
		return
	tab_datos.add_child(FichaTabs.block_title("MUTACION"))
	var report: Dictionary = GameState.mutation_report(id)
	if report.is_empty():
		tab_datos.add_child(FichaTabs.note("Sin mutacion. Se puede tirar una en la pantalla MUTACIONES."))
		return
	var header := Label.new()
	header.text = "%s  -  %s" % [String(report.get("rank_name", "")), String(report.get("effect_name", ""))]
	header.add_theme_font_size_override("font_size", VI.FONT_BODY)
	header.add_theme_color_override("font_color", VI.rarity_color(String(report.get("rank", ""))))
	header.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab_datos.add_child(header)
	for raw_stat in report.get("stats", []):
		if not (raw_stat is Dictionary):
			continue
		var stat: Dictionary = raw_stat
		tab_datos.add_child(FichaTabs.note("%s   %s" % [
			String(stat.get("label", stat.get("stat", ""))),
			String(stat.get("text", "")),
		]))
	if int(report.get("sp_reduction", 0)) > 0:
		tab_datos.add_child(FichaTabs.note("ULTRA: la Super cuesta %d punto(s) de SP menos (minimo %d)." % [
			int(report.get("sp_reduction", 0)), int(report.get("sp_cost_min", 1))]))


## EVOLUCION. Se ensena la FORMA actual y la siguiente, con los requisitos uno por
## uno y el boton apagado mientras falte algo. Quien decide si se puede es
## GameState (can_evolve / can_special_evolve): la ficha no calcula reglas.
func _fill_evolution() -> void:
	var id := unit.id
	if id.is_empty() or not GameState.is_owned(id):
		return
	# Primero la evolucion ESPECIAL (cambia de personaje); si no hay, la normal
	# (cambia de rareza). Son datos: aqui no hay ningun personaje escrito.
	var special: Dictionary = GameState.can_special_evolve(id)
	var normal: Dictionary = GameState.can_evolve(id)
	if special.is_empty() and normal.is_empty():
		return
	var is_special := not special.is_empty() and String(special.get("to", "")) != ""
	if not is_special and String(normal.get("to", "")) == "":
		return
	var check: Dictionary = special if is_special else normal
	var current_form := String(unit.rarity)
	var next_form := String(check.get("to_rarity", "")) if is_special else String(check.get("to", ""))

	tab_datos.add_child(FichaTabs.block_title("EVOLUCION"))
	var form_label := Label.new()
	form_label.text = "%s   >   %s" % [
		current_form if not current_form.is_empty() else "?",
		next_form if not next_form.is_empty() else "?",
	]
	form_label.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	form_label.add_theme_color_override("font_color", VI.rarity_color(next_form))
	form_label.add_theme_constant_override("outline_size", 6)
	form_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	tab_datos.add_child(form_label)

	var ready := bool(check.get("ok", false))
	# Requisitos: nivel, monedas y objetos. El texto de cada uno dice el progreso
	# REAL (74 / 100) en lugar de solo el minimo.
	var level_have := int(check.get("level", 0))
	var level_need := int(check.get("level_required", 0))
	tab_datos.add_child(FichaTabs.note("Nivel: %d / %d" % [level_have, level_need]))
	var coins_have := int(check.get("coins", 0))
	var coins_need := int(check.get("coin_cost", 0))
	tab_datos.add_child(FichaTabs.note("Monedas: %d / %d" % [coins_have, coins_need]))
	for raw_cost in check.get("item_cost", []):
		if not (raw_cost is Dictionary):
			continue
		var cost: Dictionary = raw_cost
		var item_id := String(cost.get("item", ""))
		var amount := int(cost.get("amount", 1))
		tab_datos.add_child(FichaTabs.note("%s: %d / %d" % [
			GameState.item_display_name(item_id), GameState.item_count(item_id), amount]))

	if not ready:
		var reason := String(check.get("reason", ""))
		if not reason.is_empty():
			tab_datos.add_child(FichaTabs.note(reason))
		var blocked := Label.new()
		blocked.text = "NO SE CUMPLEN LOS REQUISITOS"
		blocked.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		blocked.add_theme_color_override("font_color", VI.INK_DIM)
		tab_datos.add_child(blocked)
	else:
		var ready_label := Label.new()
		ready_label.text = "EVOLUCIONABLE"
		ready_label.add_theme_font_size_override("font_size", VI.FONT_BODY)
		ready_label.add_theme_color_override("font_color", VI.GREEN)
		tab_datos.add_child(ready_label)

	var button := Button.new()
	button.text = "EVOLUCIONAR"
	button.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	button.add_theme_font_size_override("font_size", VI.FONT_BODY)
	button.disabled = not ready
	VI.tint_button(button, VI.GOLD if ready else VI.INK_DIM)
	if ready:
		button.pressed.connect(_on_evolve_pressed.bind(is_special))
	tab_datos.add_child(button)


## Evoluciona de verdad. La transicion la pinta EvolutionFx con los datos del
## informe; quien cambia el personaje es GameState, en un solo sitio.
func _on_evolve_pressed(is_special: bool) -> void:
	if unit == null or unit.id.is_empty():
		return
	var id := unit.id
	var before_form := String(unit.rarity)
	var report: Dictionary = GameState.evolve_special(id) if is_special else GameState.evolve(id)
	if report.is_empty():
		return
	# La ficha se rehace con la forma nueva y la transicion se cuenta encima.
	_source_data = GameState.character_data(id)
	_reload_after_progress()
	EvolutionFx.play(self, before_form, String(report.get("to_rarity", "")), unit.display_name)


func _fill_habilidades() -> void:
	_clear(tab_habilidades)
	tab_habilidades.add_child(FichaTabs.build_habilidades(unit))


func _fill_links() -> void:
	_clear(tab_links)
	var link_box := FichaTabs.build_links(unit, GameState.party)
	tab_links.add_child(link_box)
	# Dentro de una batalla, los links que cuentan son los DEL EQUIPO que ha
	# salido a combatir; fuera, los del equipo configurado en la pantalla EQUIPO.
	if not _is_ficha:
		# Informe de sinergias del equipo (solo los links ACTIVOS): nivel alcanzado,
		# que hace cada regla y A QUIEN beneficia. Bajo demanda: vive en la ficha, no
		# en la pantalla de combate.
		var active := 0
		var lines := PackedStringArray()
		for row in GameState.team_synergy_report():
			if not bool(row.get("active", false)):
				continue
			active += 1
			lines.append("%s  (Nv.%d/%d, %d portadores)" % [String(row["name"]).to_upper(), int(row["tier"]), int(row["tier_count"]), int(row["holders"])])
			for tier in row["tiers"]:
				if not bool(tier["reached"]):
					continue
				for rule in tier["rules"]:
					lines.append("  - %s: %s  [%s]" % [String(rule["name"]), String(rule["text"]), ", ".join(PackedStringArray(rule["who_names"]))])
		tab_links.add_child(FichaTabs.note("Links activos del equipo en combate: %d." % active))
		if not lines.is_empty():
			tab_links.add_child(FichaTabs.note("\n".join(lines)))


## --- DUPES -------------------------------------------------------------------------
func _fill_dupes() -> void:
	if tab_dupes == null or unit == null:
		return
	_clear(tab_dupes)
	# Solo se puede mejorar desde la FICHA (fuera del combate); en combate se ve el estado.
	tab_dupes.add_child(DupeTab.build(unit.id, _is_ficha, _dupe_confirming, _on_dupe_ask, _on_dupe_confirm, _on_dupe_cancel))


func _on_dupe_ask() -> void:
	_dupe_confirming = true
	_fill_dupes()


func _on_dupe_cancel() -> void:
	_dupe_confirming = false
	_fill_dupes()


## Gasta la copia. El estado cambia SOLO aqui (y dentro de GameState.dupe_upgrade, que
## valida y es atomica); el flag se apaga antes para que un doble toque no consuma dos.
func _on_dupe_confirm() -> void:
	if not _dupe_confirming or unit == null:
		return
	_dupe_confirming = false
	# En el Dupe maximo la unica accion posible es convertir las copias sobrantes.
	if GameState.dupe_level_of(unit.id) >= GameState.dupe_max_level():
		GameState.dupe_convert_overflow(unit.id)
	else:
		GameState.dupe_upgrade(unit.id)
	_reload_after_progress()


func _fill_categorias() -> void:
	_clear(tab_categorias)
	var categories: Array = unit.categories
	if categories.is_empty():
		categories = _character_data().get("categories", [])
	tab_categorias.add_child(FichaTabs.build_categorias(categories))


## Pestana BATALLA: los contadores de esta batalla y los efectos vivos. Fuera de
## combate no hay nada que contar y se dice, en vez de ensenar ceros enganosos.
func _fill_stats() -> void:
	_clear(stats_list)
	if not _show_combat_stats or unit.battle == null:
		stats_title.text = "SIN BATALLA"
		stats_list.add_child(FichaTabs.note("Los contadores de batalla solo existen mientras se combate."))
		stats_list.add_child(FichaTabs.note("Aqui se ven el dano hecho y recibido, los golpes, los criticos, las esquivas y las curaciones de esta unidad."))
		return
	stats_title.text = "ESTADISTICAS DE COMBATE"
	for group in unit.battle.rows():
		var header := Label.new()
		header.text = String(group["group"])
		header.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		header.add_theme_color_override("font_color", GROUP_COLORS.get(String(group["group"]), VI.GOLD))
		stats_list.add_child(header)

		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 4)
		stats_list.add_child(grid)
		for item in group["items"]:
			_add_row(String(item["label"]), str(int(item["value"])), grid)


## Efectos vivos. Se cuelga de la pestana BATALLA porque son estado de la
## batalla, no del personaje: un buff no tiene sentido fuera de un combate.
func _fill_effects() -> void:
	var effects := unit.active_effects()
	if effects.is_empty():
		return
	stats_list.add_child(FichaTabs.block_title("EFECTOS ACTIVOS"))
	for effect in effects:
		stats_list.add_child(_make_effect_row(effect))


## --- Construccion de filas -------------------------------------------------

func _add_row(label_text: String, value_text: String, grid: GridContainer) -> void:
	var target := grid
	var name_cell := Label.new()
	name_cell.text = label_text
	name_cell.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	name_cell.add_theme_color_override("font_color", VI.INK_DIM)
	name_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.add_child(name_cell)

	var value_cell := Label.new()
	value_cell.text = value_text
	value_cell.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	value_cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.add_child(value_cell)


func _make_effect_row(effect: Dictionary) -> Control:
	var positive := bool(effect.get("positive", true))
	var color := VI.BLUE if positive else VI.RED
	var detail := _effect_value_text(effect)

	var row := PanelContainer.new()
	var style := VI.chip(color, 0.88)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", style)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	row.add_child(line)

	# Icono del efecto: marca de signo con el color del tipo de efecto.
	var badge := Label.new()
	badge.text = "+" if positive else "-"
	badge.add_theme_font_size_override("font_size", 26)
	badge.add_theme_color_override("font_color", color)
	badge.custom_minimum_size = Vector2(28, 0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(badge)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	line.add_child(texts)

	var title := Label.new()
	title.text = detail
	title.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	title.add_theme_color_override("font_color", color)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	texts.add_child(title)

	var subtitle := Label.new()
	subtitle.text = _effect_duration_text(effect)
	subtitle.add_theme_font_size_override("font_size", VI.FONT_TINY)
	subtitle.add_theme_color_override("font_color", VI.INK_DIM)
	texts.add_child(subtitle)

	return row


## "DEFENSA +45%" para multiplicadores, "ATAQUE +20" para valores absolutos y
## "CRITICO +20%" para probabilidades. El numero lo formatea StatBlock, el mismo
## sitio que alimenta el registro del combate, asi que las dos pantallas nunca
## dicen cosas distintas del mismo efecto.
func _effect_value_text(effect: Dictionary) -> String:
	var key := String(effect.get("key", ""))
	match String(effect.get("source_kind", "")):
		"status":
			return String(STATUS_LABELS.get(key, key.to_upper()))
		"shield":
			return "ESCUDO %d" % int(round(float(effect.get("value", 0.0))))
		"periodic":
			var names := { "bleed": "SANGRADO", "burn": "QUEMADURA", "poison": "VENENO", "regen": "REGENERACION" }
			return "%s %d por turno" % [String(names.get(key, key.to_upper())), int(round(float(effect.get("value", 0.0))))]
		"undying":
			return "ULTIMO ALIENTO (sobrevive a un golpe mortal)"
	return "%s %s" % [
		StatBlock.label(key),
		StatBlock.mod_value_text(
			key,
			String(effect.get("mod_kind", "mult")),
			float(effect.get("value", 0.0))
		),
	]


func _effect_duration_text(effect: Dictionary) -> String:
	var turns := int(effect.get("turns", 0))
	var duration := "permanente"
	if turns == 1:
		duration = "1 turno restante"
	elif turns > 1:
		duration = "%d turnos restantes" % turns
	var origin := String(effect.get("origin", ""))
	if origin.is_empty():
		return duration
	return "%s  -  %s" % [origin, duration]


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
