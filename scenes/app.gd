extends Node

const NAV := preload("res://scenes/nav.gd")
const BattleScene := preload("res://scenes/battle/battle.tscn")
const CombatUnit := preload("res://core/combat_unit.gd")
const BattleManager := preload("res://core/battle_manager.gd")
const Portrait := preload("res://ui/portrait.gd")
const VI := preload("res://ui/visual_identity.gd")
const Progression := preload("res://core/progression.gd")
const EvolutionFx := preload("res://ui/evolution_fx.gd")

## Raiz del juego. Es el unico sitio que decide QUE pantalla se esta viendo.
##
##   Root            -> pantallas fuera del combate. Una visible a la vez, y
##                      ninguna se reconstruye al cambiar: conservan su estado.
##   BattleContainer -> la batalla, por encima de las anteriores.
##
## Reglas:
##   - Fuera del combate se manda con Nav (pila de pantallas).
##   - El combate se abre POR ENCIMA y no entra en la pila: al terminar se
##     vuelve a la pantalla desde la que se entro, tal como estaba.
##   - Esc vuelve atras. Si hay una batalla en curso se pide confirmar antes de
##     abandonarla, para no perderla de un toque.

const SCREENS := {
	"main_menu": preload("res://scenes/screens/main_menu.tscn"),
	"collection": preload("res://scenes/screens/collection.tscn"),
	"team": preload("res://scenes/screens/team.tscn"),
	"stage_select": preload("res://scenes/screens/stage_select.tscn"),
	"summon": preload("res://scenes/screens/summon.tscn"),
	"missions": preload("res://scenes/screens/missions.tscn"),
	# HITO 2 de la historia: HISTORIA lista los mundos y MAPA DE MUNDO pinta los
	# niveles del mundo elegido. El combate que abre el mapa se abre POR ENCIMA y
	# no entra en la pila de navegacion.
	"history": preload("res://scenes/screens/history.tscn"),
	"world_map": preload("res://scenes/screens/world_map.tscn"),
	"events": preload("res://scenes/screens/events.tscn"),
	# TORRE: 25 pisos, equipo de 5 (3 activos + 2 reserva) propio de la torre.
	"tower": preload("res://scenes/screens/tower.tscn"),
	# INVENTARIO pinta los objetos que el jugador tiene de verdad (catalogo de
	# res://data/items + cantidades de GameState) y EVOLUCION hace las
	# evoluciones, con sus requisitos leidos del estado real de la partida.
	"inventory": preload("res://scenes/screens/inventory.tscn"),
	"evolution": preload("res://scenes/screens/evolution.tscn"),
	# MUTACIONES tira una mutacion a un personaje y AJUSTES guarda las
	# preferencias del dispositivo en user://settings.json.
	"mutations": preload("res://scenes/screens/mutations.tscn"),
	"settings": preload("res://scenes/screens/settings.tscn"),
	# TIENDA gasta monedas y gemas en articulos (res://data/shop). Es una pantalla
	# propia, con su fondo y su distribucion, no una lista generica.
	"shop": preload("res://scenes/screens/shop.tscn"),
}

var nav: NAV = null

@onready var root_node: Control = $Root
@onready var battle_container: Control = $BattleContainer

var _screens: Dictionary = {}
var _current := ""
var _battle: Node = null
## Verdadero cuando ya se ha pedido confirmacion una vez para cerrar el combate.
var _battle_quit_armed := false


func _ready() -> void:
	nav = NAV.new()
	nav.name = "Nav"
	add_child(nav)
	nav.changed.connect(_show_screen)

	for key in SCREENS.keys():
		var node: Control = SCREENS[key].instantiate()
		node.name = String(key)
		node.visible = false
		root_node.add_child(node)
		_screens[String(key)] = node

	nav.initial(NAV.MAIN_MENU)
	if DEBUG_NAV:
		_debug_walkthrough()
	if DEBUG_V08:
		_debug_v08()
	if DEBUG_V10:
		_debug_v10()
	if DEBUG_V12:
		_debug_v12()
	if DEBUG_V13:
		_debug_v13()
	if DEBUG_V14:
		_debug_v14()
	if DEBUG_V15:
		_debug_v15()
	if DEBUG_V16:
		_debug_v16()
	if DEBUG_V17:
		_start_hito_c()
	# Arnes del Hito C por linea de comandos. Lo que va detras de "--" son
	# argumentos del juego: --dbg17 (prueba completa), --dbg17-write (guarda los
	# ajustes de prueba y sale) y --dbg17-read (los comprueba en un proceso nuevo).
	var dbg_args := OS.get_cmdline_user_args()
	if dbg_args.has("--dbg17"):
		_start_hito_c()
	elif dbg_args.has("--dbg17-write"):
		_start_hito_c(false, true)
	elif dbg_args.has("--dbg17-read"):
		_start_hito_c(false, false)
	elif dbg_args.has("--dbg15"):
		_debug_v15()
	elif dbg_args.has("--dbg18"):
		_start_hito_d()
	elif dbg_args.has("--dbg21"):
		var hito_g: GDScript = load("res://scenes/debug/hito_g_checks.gd")
		var hito_g_node := Node.new()
		hito_g_node.set_script(hito_g)
		hito_g_node.name = "HitoGChecks"
		add_child(hito_g_node)
		hito_g_node.call_deferred("run", self)
	elif dbg_args.has("--dbg20"):
		var hito_f: GDScript = load("res://scenes/debug/hito_f_checks.gd")
		var hito_f_node := Node.new()
		hito_f_node.set_script(hito_f)
		hito_f_node.name = "HitoFChecks"
		add_child(hito_f_node)
		hito_f_node.call_deferred("run", self)
	elif dbg_args.has("--dbg19"):
		var hito_e: GDScript = load("res://scenes/debug/hito_e_checks.gd")
		var hito_e_node := Node.new()
		hito_e_node.set_script(hito_e)
		hito_e_node.name = "HitoEChecks"
		add_child(hito_e_node)
		hito_e_node.call_deferred("run", self)
	elif dbg_args.has("--motion"):
		var motion: GDScript = load("res://scenes/debug/motion_shots.gd")
		var motion_node := Node.new()
		motion_node.set_script(motion)
		add_child(motion_node)
		motion_node.call_deferred("run", self)
	elif dbg_args.has("--shots-g"):
		var shots_g: GDScript = load("res://scenes/debug/shots_g.gd")
		var shots_g_node := Node.new()
		shots_g_node.set_script(shots_g)
		add_child(shots_g_node)
		shots_g_node.call_deferred("run", self)
	elif dbg_args.has("--shots-f"):
		var shots_f: GDScript = load("res://scenes/debug/shots_f.gd")
		var shots_f_node := Node.new()
		shots_f_node.set_script(shots_f)
		add_child(shots_f_node)
		shots_f_node.call_deferred("run", self)
	elif dbg_args.has("--shots-e"):
		var shots_e: GDScript = load("res://scenes/debug/shots_e.gd")
		var shots_e_node := Node.new()
		shots_e_node.set_script(shots_e)
		add_child(shots_e_node)
		shots_e_node.call_deferred("run", self)
	elif dbg_args.has("--shots"):
		var shots: GDScript = load("res://scenes/debug/shots.gd")
		var shots_node := Node.new()
		shots_node.set_script(shots)
		add_child(shots_node)
		shots_node.call("run", self)


## Recorrido automatico de verificacion. SOLO para pruebas: en el juego normal
## DEBUG_NAV va en false. Cada paso imprime lo que ha comprobado, para poder
## leerlo en el panel de salida en vez de suponer que funciona.
const DEBUG_NAV := false

## Verificacion en ejecucion de V0.8: progresion, varios enemigos, eleccion de
## objetivo, area, soporte, misiones y guardado. Se ejecuta DENTRO del juego y va
## dejando en consola el resultado de cada comprobacion. En el juego normal va en
## false; se pone en true para pasar la prueba y se vuelve a poner en false.
const DEBUG_V08 := false

## Verificacion en ejecucion del HITO 2 de V1.0: links con efecto real, categorias
## y ficha por pestanas. Como las demas campanas, SOLO para pruebas: se pone en
## true para pasar la prueba y se vuelve a false antes de entregar.
const DEBUG_V10 := false

## Verificacion en ejecucion de V1.2: HISTORIA (los tres mundos, el mapa, las
## dificultades, el dialogo y el salto) contra los datos y el estado reales, con
## los MISMOS metodos que disparan los botones. Como las demas campanas, SOLO
## para pruebas: se pone en true para pasar la prueba y se vuelve a false.
const DEBUG_V12 := false

## Verificacion en ejecucion del HITO 3 de V1.2: el evento de Sakuta y Mai, su
## requisito de equipo, sus drops y la pantalla de EVENTOS. Como las demas
## campanas, SOLO para pruebas: se pone en true para pasar la prueba y se vuelve
## a false antes de entregar.
const DEBUG_V13 := false

## Verificacion en ejecucion del HITO de RAREZAS Y EVOLUCIONES: el sistema central
## de estilos, el arte por forma con su fallback, la evolucion con sus requisitos,
## la transicion y el arte que ensenan coleccion, equipo y combate. Como las demas,
## SOLO para pruebas.
const DEBUG_V14 := false

## Verificacion en ejecucion de los BUGS DEL EVENTO: la recompensa de personaje
## solo se puede reclamar con el progreso real superado, y el stage 3 es un 1 VS 1
## que pelea SOLO con Sakuta en su forma UR.
const DEBUG_V15 := false

## Verificacion en ejecucion del hito de EVOLUCION SAKUTA + INVENTARIO + GACHA:
## requisitos EXACTOS de las dos evoluciones especiales (25 uniformes; 3 fichas, sin vueltas
## al evento + 3 fichas), sin monedas; el inventario sumando y gastando; y las
## tiradas del gacha. Como las demas campanas, SOLO para pruebas.
const DEBUG_V16 := false

## Verificacion en ejecucion del HITO C: equipo con huecos, Leader Skill solo en
## la posicion 1, ajustes y su persistencia, audio sin archivos, mutaciones, los
## enemigos del evento y que ningun boton del menu este muerto. El arnes vive en
## res://scenes/debug/hito_c_checks.gd y usa las funciones REALES del juego.
## Ademas de ponerlo en true, se puede arrancar sin tocar nada con
##   --dbg17 / --dbg17-write / --dbg17-read   detras de "--".
const DEBUG_V17 := false


func _debug_walkthrough() -> void:
	await get_tree().process_frame
	print("[DBG] --- verificacion V0.5 ---")

	# 1) Navegacion: entrar en cada pantalla y volver.
	for screen in ["collection", "team", "summon", "missions"]:
		open_screen(screen)
		await get_tree().process_frame
		print("[DBG] pantalla %s -> %s" % [screen, _current])
	var steps := 0
	while go_back():
		steps += 1
		await get_tree().process_frame
	print("[DBG] volver atras: %d pasos, pantalla=%s" % [steps, _current])

	# 2) Nivel: subir 5 niveles debe subir las estadisticas. La unidad se
	#    construye igual que en combate, asi que este es el numero que se juega.
	var id := "gojo"
	var before := CombatUnit.new()
	before.setup(GameState.character_data(id), true, 0)
	print("[DBG] %s nivel %d: atk=%d def=%d hp=%d" % [
		id, before.level, int(before.attack()), int(before.defense()), int(before.max_hp())])
	GameState.set_level(id, GameState.level_of(id) + 5)
	var after := CombatUnit.new()
	after.setup(GameState.character_data(id), true, 0)
	print("[DBG] %s nivel %d: atk=%d def=%d hp=%d" % [
		id, after.level, int(after.attack()), int(after.defense()), int(after.max_hp())])

	# 3) XP: sumar experiencia sube de nivel sin tocar el nivel a mano.
	var gained := GameState.add_xp(id, 500)
	print("[DBG] +500 XP -> subidas=%d, nivel=%d, xp=%d/%d" % [
		gained, GameState.level_of(id), GameState.xp_of(id), GameState.xp_to_next(id)])

	# 4) Guardado: se borra el nivel de memoria, se relee del disco y debe
	#    volver el mismo. Esto es lo que comprueba que el progreso persiste.
	var level_in_file := GameState.level_of(id)
	GameState.progress[id] = { "level": 1, "xp": 0 }
	var loaded := GameState.load_game()
	var level_after_load := GameState.level_of(id)
	print("[DBG] guardado: leido=%s, nivel en disco=%d, tras recargar=%d -> %s" % [
		str(loaded), level_in_file, level_after_load,
		"OK" if level_in_file == level_after_load else "FALLO"])
	print("[DBG] roster=%d party=%s monedas=%d" % [
		GameState.roster.size(), str(GameState.party), GameState.coins])

	# 5) Ficha de personaje desde la coleccion.
	var collection_node = _screens.get("collection", null)
	if collection_node != null:
		var panel = collection_node.get_node_or_null("UnitInfoPanel")
		var ids: Array = DB.characters.keys()
		if panel != null and not ids.is_empty():
			var first := String(GameState.roster[0]) if not GameState.roster.is_empty() else String(ids[0])
			panel.call("open_for_data", GameState.character_data(first), false)
			await get_tree().process_frame
			print("[DBG] ficha de %s abierta (nivel %d)" % [first, GameState.level_of(first)])
			panel.call("close_panel")
			await get_tree().process_frame

	# 6) Coleccion y equipo con el roster completo. Es lo que comprueba que el
	#    sistema escala a muchos personajes sin tocar la interfaz: las pantallas
	#    se construyen solas a partir de los datos.
	print("[DBG] roster=%d personajes" % GameState.roster.size())
	var collection_check = _screens.get("collection", null)
	if collection_check != null:
		collection_check.call("refresh")
		var grid = collection_check.get_node_or_null("Margin/Main/Scroll/Grid")
		if grid != null:
			print("[DBG] coleccion pinta %d tarjetas" % grid.get_child_count())
	var team_check = _screens.get("team", null)
	if team_check != null:
		team_check.call("refresh")
		var pool = team_check.get_node_or_null("Margin/Main/Scroll/Pool")
		if pool != null:
			print("[DBG] equipo ofrece %d personajes" % pool.get_child_count())

	# 7) Combate con personajes NUEVOS, no con los cuatro de siempre: si esto
	#    abre, cualquier personaje del roster puede combatir sin codigo propio.
	GameState.party = ["goku", "yuno", "senku", "miku"]
	await get_tree().create_timer(0.2).timeout
	print("[DBG] abriendo combate con %s" % str(GameState.party))
	open_battle()

	# 7) Limpieza: el recorrido ha subido el nivel de un personaje solo para
	#    probarlo, asi que se deja el guardado como estaba (nivel 1). Se borra el
	#    archivo en vez de reescribirlo para no dejar rastro de la prueba.
	await get_tree().create_timer(0.4).timeout

	# 8) V0.7: el bucle completo. Se comprueba llamando a los MISMOS manejadores
	#    que disparan los botones, no copiando su logica.
	await _debug_v07()

	# 9) V0.7.1: EQUIPO y SALIR comprobados con CLICS REALES sobre el motor.
	await _debug_v071()

	GameState.delete_save()
	print("[DBG] guardado de prueba borrado; proxima partida empieza de cero")


## Verificacion en ejecucion del bucle de V0.7: seleccion de batalla, salir con
## confirmacion, recompensas sin duplicar y filtros de la coleccion.
func _debug_v07() -> void:
	# a) Batallas: los datos salen de data/stages y el combate usa sus enemigos.
	var stages: Array = DB.all_stages()
	print("[DBG7] batallas en data/stages: %d" % stages.size())
	if not stages.is_empty():
		var stage: Dictionary = stages[0]
		var sid := String(stage.get("id", ""))
		GameState.select_stage(sid)
		print("[DBG7] batalla %s -> enemigos=%d, premios=%d XP / %d monedas" % [
			sid, GameState.enemy_data().size(),
			int(stage.get("xp_reward", 0)), int(stage.get("coin_reward", 0))])

	# b) SALIR con confirmacion: primero cancelar (la batalla debe seguir viva) y
	#    despues confirmar (debe cerrarse de verdad, no solo ocultarse).
	var battle = _battle
	if battle == null:
		print("[DBG7] no hay batalla abierta: no se puede probar SALIR")
		return
	var ids: Array = []
	for unit in battle.get("manager").allies:
		ids.append(String(unit.id))
	var dialog = battle.get("_confirm_overlay")
	battle.call("_on_exit_pressed")
	await get_tree().process_frame
	print("[DBG7] SALIR pulsado -> dialogo visible=%s" % str(dialog.visible))
	battle.call("_cancel_abandon")
	await get_tree().process_frame
	print("[DBG7] CANCELAR -> dialogo visible=%s, batalla viva=%s" % [
		str(dialog.visible), str(_battle != null)])
	battle.call("_on_exit_pressed")
	await get_tree().process_frame
	battle.call("_confirm_abandon")
	await get_tree().create_timer(0.3).timeout
	print("[DBG7] SALIR confirmado -> batalla liberada=%s, pantalla=%s" % [
		str(_battle == null), _current])

	# c) Entrar y salir dos veces mas: no deben quedar batallas ni UIs colgadas.
	for i in 2:
		open_battle()
		await get_tree().create_timer(0.2).timeout
		var again = _battle
		if again == null:
			print("[DBG7] ciclo %d: la batalla no se abrio" % (i + 1))
			continue
		again.call("_on_exit_pressed")
		await get_tree().process_frame
		again.call("_confirm_abandon")
		await get_tree().create_timer(0.2).timeout
		var container := get_node_or_null("BattleContainer")
		var live := 0
		if container != null:
			for child in container.get_children():
				live += 1
		print("[DBG7] ciclo %d entrar/salir -> liberada=%s, nodos vivos en el contenedor=%d" % [
			i + 1, str(_battle == null), live])

	# d) Recompensas: la victoria entrega XP y monedas UNA sola vez; la derrota y
	#    el abandono no entregan nada.
	var coins_before := GameState.coins
	# El token es lo que ata la recompensa a UNA batalla: cobrar dos veces con el
	# mismo token debe ser imposible.
	var token := GameState.begin_battle()
	var first: Dictionary = GameState.grant_battle_rewards(token, ids, true)
	var coins_after_first := GameState.coins
	var second: Dictionary = GameState.grant_battle_rewards(token, ids, true)
	print("[DBG7] victoria: entregada=%s, xp=%d, monedas=%d" % [
		str(first.get("granted", false)), int(first.get("xp", 0)), int(first.get("coins", 0))])
	print("[DBG7] segunda entrega con el mismo token: entregada=%s (tiene que ser false)" % str(second.get("granted", false)))
	print("[DBG7] monedas %d -> %d y siguen %d tras el segundo intento (no puede subir)" % [
		coins_before, coins_after_first, GameState.coins])
	var defeat_token := GameState.begin_battle()
	var defeat: Dictionary = GameState.grant_battle_rewards(defeat_token, ids, false)
	print("[DBG7] derrota: entregada=%s, xp=%d, monedas=%d (tienen que ser 0)" % [
		str(defeat.get("granted", false)), int(defeat.get("xp", 0)), int(defeat.get("coins", 0))])

	# e) Coleccion: filtros y ordenacion, disparando los mismos manejadores que
	#    los botones.
	var collection = _screens.get("collection", null)
	if collection == null:
		return
	open_screen("collection")
	await get_tree().process_frame
	var grid = collection.get_node_or_null("Margin/Main/Scroll/Grid")
	print("[DBG7] coleccion sin filtro: %d tarjetas" % _grid_count(grid))
	collection.call("_on_rarity_selected", "UR")
	await get_tree().process_frame
	print("[DBG7] filtro UR: %d tarjetas" % _grid_count(grid))
	collection.call("_on_rarity_selected", "TODOS")
	collection.call("_on_type_selected", "INT")
	await get_tree().process_frame
	print("[DBG7] filtro tipo INT: %d tarjetas" % _grid_count(grid))
	collection.call("_on_type_selected", "TODOS")
	collection.call("_on_sort_selected", 2)
	await get_tree().process_frame
	var names: Array = []
	if grid != null:
		for card in grid.get_children():
			names.append(String(card.get("data").get("name", "?")))
	print("[DBG7] orden por nombre (4 primeros): %s" % str(names.slice(0, 4)))
	collection.call("_on_sort_selected", 0)


func _grid_count(grid: Node) -> int:
	if grid == null:
		return -1
	return grid.get_child_count()


func current_screen() -> String:
	return _current


func open_screen(screen: String) -> void:
	if not _screens.has(screen):
		push_error("App: pantalla desconocida '%s'." % screen)
		return
	nav.push(screen)


func go_back() -> bool:
	return nav.pop()


## --- Combate ---------------------------------------------------------------
## La batalla no depende de la pantalla que la abre: se construye aqui y se
## destruye aqui, asi que no hay que guardar nada para volver.

func open_battle() -> void:
	if _battle != null:
		return
	# El equipo vacio no entra a combatir. Lo que hace falta lo dice el MODO de la
	# batalla (GameState.team_problem), no una regla fija de la raiz: un stage
	# normal admite un equipo de una unidad, y un stage que pida un tamano lo
	# declara en su JSON.
	if not GameState.team_problem().is_empty():
		return
	_battle = BattleScene.instantiate()
	battle_container.add_child(_battle)
	battle_container.visible = true
	_battle_quit_armed = false
	# Token de la batalla: se lo queda el combate para pedir las recompensas una
	# sola vez. Cada batalla (incluido REINTENTAR) tiene el suyo.
	if _battle.has_method("set_battle_token"):
		_battle.call("set_battle_token", GameState.begin_battle())
	# El combate tambien entra con fundido: no aparece de golpe encima del menu.
	ScreenFade.play(self)
	_update_music()


## Otra batalla con las mismas reglas, sin salir del combate.
func restart_battle() -> void:
	close_battle()
	open_battle()


func close_battle() -> void:
	if _battle == null:
		return
	battle_container.remove_child(_battle)
	_battle.queue_free()
	_battle = null
	battle_container.visible = false
	_update_music()
	# La pantalla que abrio el combate se entera de que ha terminado (la torre
	# se repinta con su progreso nuevo).
	var shown = _screens.get(_current, null)
	if shown != null and shown.has_method("on_battle_closed"):
		shown.call("on_battle_closed")


## Pista de musica de cada pantalla. Sin archivo no suena nada (GameAudio lo tolera).
func _music_for(screen: String) -> String:
	match screen:
		"history", "world_map", "stage_select":
			return "history"
		"events", "tower":
			return "events"
	return "menu"


## Pide a la app que recalcule la musica que toca (la usan las capas que ponen un
## tema especial y lo sueltan al terminar).
func refresh_music() -> void:
	_update_music()


func _update_music() -> void:
	if GameAudio == null:
		return
	# Un tema ESPECIAL (duo David & Lucy) manda mientras su contexto sigue vivo: la
	# invocacion en la pantalla de invocar, o el combate en curso. Si el contexto
	# ya no existe (se cerro el combate, se cambio de pantalla) se suelta y vuelve la
	# musica normal, asi el tema nunca se queda sonando de mas.
	if GameAudio.override_active():
		var owner_name := GameAudio.override_owner()
		var alive := (owner_name == "battle" and _battle != null) or (owner_name == "summon" and _battle == null and _current == "summon")
		if alive and not GameAudio.current_music_path().is_empty():
			return
		GameAudio.override_clear()
	GameAudio.play_music("battle" if _battle != null else _music_for(_current))


func _show_screen(screen: String) -> void:
	_current = screen
	_update_music()
	# Salir de la torre devuelve links y Leader Skill al equipo normal de 4.
	if screen != "tower":
		GameState.reset_battle_context()
	for key in _screens.keys():
		var node: Control = _screens[key]
		node.visible = String(key) == screen
	# Cada pantalla se repinta al entrar: los datos pueden haber cambiado en otra
	# (por ejemplo, el equipo elegido en EQUIPO).
	var shown = _screens.get(screen, null)
	if shown != null and shown.has_method("refresh"):
		shown.call("refresh")
	# La pantalla nueva entra con un fundido corto en lugar de aparecer de golpe.
	ScreenFade.play(self)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _battle != null:
		if _battle_quit_armed:
			close_battle()
		else:
			_battle_quit_armed = true
			if _battle.has_method("show_hint"):
				_battle.call("show_hint", "Pulsa ESC otra vez para abandonar el combate")
				get_viewport().set_input_as_handled()
				return
		get_viewport().set_input_as_handled()
		return
	if nav.pop():
		get_viewport().set_input_as_handled()


## --- Verificacion V0.7.1: EQUIPO y SALIR con clics REALES --------------------
## Nada de llamar a las funciones a mano: se inyectan eventos de raton en la
## posicion real de cada boton con Input.parse_input_event. Si un boton no
## responde a un clic de verdad (porque otro nodo se lo come), esta prueba NO lo
## dara por bueno, que es exactamente lo que hay que detectar.


## Clic de raton completo (pulsar y soltar) en la posicion indicada.
##
## Se inyecta con push_input en el viewport, NO con Input.parse_input_event: el
## viewport usa el mismo espacio de coordenadas que Control.get_global_rect()
## (canvas), mientras que Input las interpreta como pantalla. Con stretch
## canvas_items esas dos no coinciden, y el clic aterrizaba en otro sitio.
func _click(pos: Vector2) -> void:
	var viewport := get_viewport()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	press.global_position = pos
	# in_local_coords = true: la posicion ya viene en coordenadas del lienzo,
	# que son las mismas que devuelve get_global_rect(). Sin esto, el viewport
	# la vuelve a transformar con el escalado de la ventana y el clic aterriza
	# en otro sitio (con el lienzo al doble de ancho, justo al lado).
	viewport.push_input(press, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pos
	release.global_position = pos
	viewport.push_input(release, true)


func _click_control(node: Control, label: String) -> void:
	if node == null:
		print("[DBG71] %s -> el nodo no existe" % label)
		return
	var rect := node.get_global_rect()
	print("[DBG71] %s -> visible=%s rect=%s centro=%s" % [
		label, str(node.is_visible_in_tree()), str(rect), str(rect.get_center())])
	_click(rect.get_center())


func _find_button(root: Node, text: String) -> Control:
	if root == null:
		return null
	for child in root.get_children():
		if child is Button and String((child as Button).text).find(text) >= 0:
			return child
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _has_duplicates(list: Array) -> bool:
	var seen: Array = []
	for item in list:
		if seen.has(item):
			return true
		seen.append(item)
	return false


## Nombres del equipo REAL que ha cargado el combate, leidos del BattleManager.
## Es la comprobacion de que la pantalla y el combate usan el mismo equipo.
func _battle_party_names() -> Array:
	var names: Array = []
	if _battle == null:
		return names
	var manager = _battle.get_node_or_null("BattleManager")
	if manager == null:
		return names
	for unit in manager.allies:
		names.append(unit.display_name)
	return names


func _debug_v071() -> void:
	print("[DBG71] --- verificacion V0.7.1 (equipo y salir con clics reales) ---")
	GameState.delete_save()
	GameState.roster = []
	GameState.party = []

	# --- EQUIPO -------------------------------------------------------------
	open_screen("team")
	await get_tree().process_frame
	await get_tree().process_frame
	var team = _screens.get("team", null)
	if team == null:
		print("[DBG71] no hay pantalla de equipo")
		return
	team.call("refresh")
	await get_tree().process_frame
	print("[DBG71] equipo inicial: %s" % str(GameState.party))

	# Clic REAL sobre la posicion 1 del equipo.
	var lineup = team.get_node_or_null("Margin/Main/Lineup")
	var slot0: Control = lineup.get_child(0) if lineup != null and lineup.get_child_count() > 0 else null
	_click_control(slot0, "clic en posicion 1")
	await get_tree().process_frame
	print("[DBG71] posicion seleccionada tras el clic: %d (tiene que ser 0)" % int(team.get("_selected_slot")))

	# Meter en la posicion 1 un personaje que NO esta en el equipo.
	var pool = team.get_node_or_null("Margin/Main/Scroll/Pool")
	var target := ""
	var target_card: Control = null
	for child in pool.get_children():
		var data: Dictionary = child.get("data")
		if not data.is_empty() and not GameState.party.has(String(data.get("id", ""))):
			target = String(data.get("id", ""))
			target_card = child
			break
	print("[DBG71] personaje libre elegido: %s" % target)
	_click_control(target_card, "clic en %s de la lista" % target)
	await get_tree().process_frame
	print("[DBG71] equipo tras el cambio: %s" % str(GameState.party))
	print("[DBG71] %s esta ahora en el equipo: %s (tiene que ser true)" % [target, str(GameState.party.has(target))])
	print("[DBG71] hay duplicados: %s (tiene que ser false)" % str(_has_duplicates(GameState.party)))

	# Intercambio: poner en la posicion 2 alguien que YA esta en el equipo.
	var occupied := String(GameState.party[0])
	team.set("_selected_slot", 1)
	team.call("refresh")
	await get_tree().process_frame
	var lineup_after = team.get_node_or_null("Margin/Main/Lineup")
	var slot1: Control = lineup_after.get_child(1) if lineup_after != null and lineup_after.get_child_count() > 1 else null
	_click_control(slot1, "clic en posicion 2")
	await get_tree().process_frame
	var swap_card: Control = null
	for child in pool.get_children():
		var data: Dictionary = child.get("data")
		if String(data.get("id", "")) == occupied:
			swap_card = child
			break
	_click_control(swap_card, "clic en %s (ya estaba en el equipo)" % occupied)
	await get_tree().process_frame
	print("[DBG71] tras intercambiar: %s (posicion 2 = %s)" % [str(GameState.party), occupied])
	print("[DBG71] hay duplicados tras intercambiar: %s (tiene que ser false)" % str(_has_duplicates(GameState.party)))

	# Persistencia real: se olvida el equipo de memoria y se relee del disco.
	var expected: Array = GameState.party.duplicate()
	GameState.party = []
	var loaded := GameState.load_game()
	print("[DBG71] guardado: leido=%s, equipo en disco=%s -> %s" % [
		str(loaded), str(GameState.party),
		"OK" if GameState.party == expected else "FALLO"])
	team.call("refresh")
	await get_tree().process_frame
	print("[DBG71] el equipo pintado coincide con el guardado: %s" % str(GameState.party == expected))

	# Volver y entrar otra vez: los cambios tienen que seguir.
	_click_control(team.get_node_or_null("Margin/Main/Buttons/BackButton"), "clic en VOLVER")
	await get_tree().process_frame
	print("[DBG71] tras VOLVER, pantalla=%s" % _current)
	open_screen("team")
	await get_tree().process_frame
	await get_tree().process_frame
	print("[DBG71] equipo al volver a entrar: %s" % str(GameState.party))

	# --- COMBATE: el equipo de la pantalla es con el que se juega -------------
	close_battle()
	await get_tree().create_timer(0.2).timeout
	open_battle()
	await get_tree().create_timer(0.4).timeout
	print("[DBG71] equipo guardado: %s" % str(GameState.party))
	print("[DBG71] aliados que han entrado al combate: %s" % str(_battle_party_names()))

	# --- SALIR con clic real, dos ciclos -------------------------------------
	for cycle in 2:
		if _battle == null:
			print("[DBG71] ciclo %d: no hay batalla abierta" % (cycle + 1))
			break
		_click_control(_battle.get_node_or_null("ExitButton"), "clic en SALIR")
		await get_tree().process_frame
		var dialog = _battle.get_node_or_null("ConfirmOverlay")
		print("[DBG71] ciclo %d: dialogo visible=%s (tiene que ser true)" % [
			cycle + 1, str(dialog != null and dialog.visible)])

		# CANCELAR: la batalla tiene que seguir viva y sin tocar el progreso.
		_click_control(_find_button(dialog, "CANCELAR"), "clic en CANCELAR")
		await get_tree().process_frame
		print("[DBG71] ciclo %d: tras CANCELAR, batalla viva=%s, dialogo=%s, monedas=%d" % [
			cycle + 1, str(_battle != null), str(dialog != null and dialog.visible), GameState.coins])

		# SALIR: confirmar y comprobar que se libera de verdad.
		_click_control(_battle.get_node_or_null("ExitButton"), "clic en SALIR otra vez")
		await get_tree().process_frame
		var dialog2 = _battle.get_node_or_null("ConfirmOverlay")
		_click_control(_find_button(dialog2, "SALIR"), "clic en SALIR del dialogo")
		await get_tree().create_timer(0.3).timeout
		var container := get_node_or_null("BattleContainer")
		var live := container.get_child_count() if container != null else 0
		print("[DBG71] ciclo %d: tras CONFIRMAR, batalla liberada=%s, nodos vivos=%d, pantalla=%s, monedas=%d" % [
			cycle + 1, str(_battle == null), live, _current, GameState.coins])
		if cycle == 0:
			open_battle()
			await get_tree().create_timer(0.4).timeout
			print("[DBG71] segunda batalla abierta sin duplicar nada: %s" % str(_battle != null))


## --- Verificacion V0.8: progresion, varios enemigos y misiones ----------------
## Se ejecuta DENTRO del juego y llama a los MISMOS manejadores que los botones,
## no a copias de su logica. Antes de tocar nada hace una copia del guardado del
## jugador y la restaura al final, para que pasar la prueba no le borre el
## progreso. Todo lo que comprueba se imprime con [DBG8] y el veredicto OK/FALLO.

const SAVE_BACKUP_PATH := "user://save_v08_backup.json"
## Archivo donde la prueba deja todos sus veredictos, en orden. Se borra al
## empezar para que una pasada no se mezcle con la anterior.
const RESULTS_PATH := "res://dbg8_resultados.txt"

func _debug_v08() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(RESULTS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULTS_PATH))
	print("[DBG8] --- verificacion V0.8 ---")
	if not _backup_save():
		print("[DBG8] AVISO: no habia guardado previo que copiar (partida nueva)")

	await _debug_v08_stages()
	await _debug_v08_battle()
	await _debug_v08_missions()
	await _debug_v08_save()

	_restore_save()
	print("[DBG8] --- fin de la verificacion V0.8 ---")


## Copia user://save.json para poder devolverlo intacto al terminar. Sin esto, la
## prueba escribiria encima del progreso real del jugador.
func _backup_save() -> bool:
	if not FileAccess.file_exists(GameState.SAVE_PATH):
		return false
	var text := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	var file := FileAccess.open(SAVE_BACKUP_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _restore_save() -> void:
	if FileAccess.file_exists(SAVE_BACKUP_PATH):
		var text := FileAccess.get_file_as_string(SAVE_BACKUP_PATH)
		var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(text)
			file.close()
		DirAccess.remove_absolute(SAVE_BACKUP_PATH)
		# El archivo ya esta devuelto, pero en memoria siguen los datos de la
		# prueba (equipo, monedas, stages). Se relee para que la sesion en curso
		# no quede con el estado de prueba.
		GameState.load_game()
		print("[DBG8] guardado del jugador restaurado tal como estaba")
	else:
		GameState.delete_save()
		print("[DBG8] no habia guardado previo: se deja la partida limpia")


## 1) STAGES: cadena de desbloqueo y datos distintos por batalla.
func _debug_v08_stages() -> void:
	GameState.delete_save()
	GameState.completed_stages = []
	GameState.counters = { "combates_jugados": 0, "victorias": 0, "derrotas": 0 }

	var stages: Array = DB.all_stages()
	print("[DBG8] stages cargados: %d" % stages.size())
	for stage in stages:
		var sid := String(stage.get("id", ""))
		print("[DBG8]   %s  %s  enemigos=%d  %d XP / %d monedas  desbloqueado=%s" % [
			sid,
			String(stage.get("name", "")),
			int((stage.get("enemies", []) as Array).size()),
			int(stage.get("xp_reward", 0)),
			int(stage.get("coin_reward", 0)),
			str(GameState.stage_unlocked(sid)),
		])

	var first_id := String(stages[0].get("id", ""))
	var second_id := String(stages[1].get("id", "")) if stages.size() > 1 else ""
	var third_id := String(stages[2].get("id", "")) if stages.size() > 2 else ""
	print("[DBG8] al empezar: %s abierto=%s | %s abierto=%s | %s abierto=%s" % [
		first_id, str(GameState.stage_unlocked(first_id)),
		second_id, str(GameState.stage_unlocked(second_id)),
		third_id, str(GameState.stage_unlocked(third_id)),
	])

	var unlocked: Array = GameState.mark_stage_completed(first_id)
	print("[DBG8] ganar %s desbloquea: %s -> %s" % [
		first_id, str(unlocked), "OK" if unlocked.has(second_id) else "FALLO"])

	# La pantalla de seleccion se repinta con el estado nuevo leyendo GameState.
	open_screen("stage_select")
	await get_tree().process_frame
	var select = _screens.get("stage_select", null)
	if select != null:
		select.call("refresh")
		await get_tree().process_frame
		var list = select.get_node_or_null("Margin/Main/Scroll/StageList")
		if list != null:
			print("[DBG8] pantalla de seleccion pinta %d batallas" % list.get_child_count())
			for index in list.get_child_count():
				var button: Button = list.get_child(index)
				print("[DBG8]   boton %d: deshabilitado=%s" % [index, str(button.disabled)])
	_mark("stage 2 desbloqueado tras ganar stage 1", GameState.stage_unlocked(second_id))
	_mark("stage 3 sigue bloqueado", not GameState.stage_unlocked(third_id))
	go_back()
	await get_tree().process_frame


## 2) COMBATE: elegir stage con varios enemigos, seleccionar objetivo, atacar,
## usar un area y usar un soporte. Se llama a los manejadores reales de la UI.
func _debug_v08_battle() -> void:
	var stages: Array = DB.all_stages()
	if stages.size() < 3:
		print("[DBG8] faltan stages para probar el combate con varios rivales")
		return
	var third: Dictionary = stages[2]
	var third_id := String(third.get("id", ""))
	GameState.select_stage(third_id)
	print("[DBG8] entrando en %s con %d rivales" % [third_id, GameState.enemy_data().size()])

	# Equipo de prueba con las piezas que hacen falta: un atacante de area (Mai,
	# target enemy_all) y un soporte de un solo aliado (Frieren, target ally).
	GameState.party = ["mai", "frieren", "gojo", "goku"]
	close_battle()
	await get_tree().create_timer(0.2).timeout
	open_battle()
	await get_tree().create_timer(0.6).timeout

	var battle = _battle
	if battle == null:
		print("[DBG8] FALLO: la batalla no se abrio")
		return
	var manager = battle.get_node_or_null("BattleManager")
	if manager == null:
		print("[DBG8] FALLO: no hay BattleManager")
		return

	print("[DBG8] aliados=%d  rivales=%d" % [manager.allies.size(), manager.enemies.size()])
	_mark("el combate carga los 3 rivales del stage", manager.enemies.size() == 3)
	# Sin esquiva durante la prueba: lo que se mide es la habilidad, no el dado.
	for unit in manager.allies + manager.enemies:
		unit.stats.add_mod("dodge_rate", "flat", -1.0, "dbg_v08", 0)
	var row = battle.get_node_or_null("Margin/Main/EnemyRow")
	if row != null:
		print("[DBG8] tarjetas de rival pintadas: %d" % row.get_child_count())

	# --- Objetivo, area y soporte, dirigidos por TURNOS REALES ---------------
	# Cada accion se lanza cuando el BattleManager pide el turno de un aliado y
	# se resuelve por el mismo camino que un boton de la interfaz. Asi lo que se
	# prueba es el combate de verdad, no una llamada al margen del turno.
	await _debug_v08_turns(battle, manager)

	# --- SALIR sigue funcionando ---
	var exit_button = battle.get_node_or_null("ExitButton")
	if exit_button != null:
		_click_control(exit_button, "clic en SALIR")
		await get_tree().process_frame
		var dialog = battle.get_node_or_null("ConfirmOverlay")
		print("[DBG8] SALIR -> dialogo visible=%s" % str(dialog != null and dialog.visible))
		battle.call("_cancel_abandon")
		await get_tree().process_frame
		_mark("CANCELAR mantiene la batalla viva", _battle != null)
		battle.call("_on_exit_pressed")
		await get_tree().process_frame
		battle.call("_confirm_abandon")
		await get_tree().create_timer(0.3).timeout
		_mark("SALIR confirmado libera la batalla", _battle == null)


## Objetivo, area y soporte se prueban DENTRO de turnos reales: se espera a que
## el BattleManager pida la accion de un aliado y se responde por el mismo camino
## que un boton de la interfaz (battle._finish_submit). Nada se resuelve al margen
## del turno: lo que se comprueba es el combate de verdad.
func _debug_v08_turns(battle, manager) -> void:
	var did_target := false
	var did_area := false
	var did_support := false
	var guard := 0
	while guard < 40:
		guard += 1
		if did_target and did_area and did_support:
			break
		var actor = await _wait_ally_turn(battle)
		if actor == null:
			print("[DBG8] se ha agotado la espera de turnos de aliado")
			break
		var special: Dictionary = actor.skill_by_kind("special")
		var spec := String(special.get("target", "")) if not special.is_empty() else ""
		if not did_target:
			did_target = true
			await _v08_target(battle, manager, actor)
			continue
		if not did_area and spec == "enemy_all":
			did_area = true
			await _v08_area(battle, manager, actor)
			continue
		if not did_support and (spec == "ally" or spec == "ally_lowest"):
			did_support = true
			await _v08_support(battle, manager, actor)
			continue
		# Turno que no hace falta para la prueba: se resuelve con un ataque basico
		# para que el combate avance hasta el siguiente aliado.
		battle.call("_finish_submit", "basic", "")
		await _wait_resolution(battle)
	print("[DBG8] prueba de turnos: objetivo=%s area=%s soporte=%s" % [
		str(did_target), str(did_area), str(did_support)])


## Espera a que el combate pida la accion de un aliado y devuelve esa unidad.
## Devuelve null si se agota la espera (el combate no llega o ya ha terminado).
func _wait_ally_turn(battle) -> CombatUnit:
	var waited := 0.0
	while waited < 25.0:
		var actor = battle.get("current_actor")
		if actor != null and actor.is_ally and bool(battle.get("awaiting_input")):
			return actor
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	return null


## Espera a que la accion enviada se resuelva: el combate deja de esperar entrada.
func _wait_resolution(battle) -> void:
	var waited := 0.0
	while waited < 9.0:
		await get_tree().create_timer(0.15).timeout
		waited += 0.15
		if not bool(battle.get("awaiting_input")):
			return


## Objetivo: con varios rivales el combate NO elige solo. Se apunta al SEGUNDO
## rival y se comprueba que el golpe va a ese y no al primero.
func _v08_target(battle, manager, actor) -> void:
	var candidates: Array = manager.candidates(actor, "basic")
	print("[DBG8] turno de %s: candidatos del ataque basico=%d" % [actor.display_name, candidates.size()])
	_mark("con varios rivales hay que elegir objetivo", manager.needs_target(actor, "basic") and candidates.size() > 1)
	if candidates.size() < 2:
		battle.call("_finish_submit", "basic", "")
		await _wait_resolution(battle)
		return
	var aim = candidates[1]
	var other = candidates[0]
	var aim_before := int(round(aim.hp))
	var other_before := int(round(other.hp))
	battle.call("_begin_targeting", "basic", candidates)
	await get_tree().process_frame
	var cancel_button = battle.get_node_or_null("Margin/Main/Bottom/ActionRow/CancelButton")
	var attack_button = battle.get_node_or_null("Margin/Main/Bottom/ActionRow/AttackButton")
	print("[DBG8] modo objetivo: CANCELAR visible=%s, ATAQUE oculto=%s" % [
		str(cancel_button != null and cancel_button.visible),
		str(attack_button != null and not attack_button.visible),
	])
	_mark("el modo objetivo ofrece CANCELAR y aparta los botones de accion",
		cancel_button != null and cancel_button.visible and attack_button != null and not attack_button.visible)
	battle.call("_confirm_target", aim)
	await _wait_resolution(battle)
	print("[DBG8] objetivo elegido %s: HP %d -> %d  |  %s: %d -> %d" % [
		aim.display_name, aim_before, int(round(aim.hp)),
		other.display_name, other_before, int(round(other.hp)),
	])
	_mark("el rival elegido recibe el golpe", int(round(aim.hp)) < aim_before or not aim.alive)
	_mark("el rival no elegido no recibe ese golpe", int(round(other.hp)) == other_before)


## Area: la especial de objetivo enemy_all debe tocar a TODOS los rivales vivos.
func _v08_area(battle, manager, actor) -> void:
	print("[DBG8] area con %s -> %s" % [
		actor.display_name, String(actor.skill_by_kind("special").get("name", ""))])
	actor.sp = CombatUnit.SP_MAX
	var before: Array = []
	for enemy in manager.enemies:
		before.append({ "unit": enemy, "hp": int(round(enemy.hp)) })
	battle.call("_finish_submit", "special", "")
	await _wait_resolution(battle)
	var touched := 0
	for entry in before:
		var enemy = entry["unit"]
		var was := int(entry["hp"])
		var now := int(round(enemy.hp))
		if not enemy.alive or now < was:
			touched += 1
		print("[DBG8]   %s: HP %d -> %d" % [enemy.display_name, was, now])
	print("[DBG8] el area ha tocado a %d de %d rivales" % [touched, before.size()])
	_mark("el area golpea a todos los rivales vivos", touched >= 2)


## Soporte: la especial de objetivo ally debe pedir eleccion y aplicar su efecto
## al aliado elegido.
func _v08_support(battle, manager, actor) -> void:
	var candidates: Array = manager.candidates(actor, "special")
	print("[DBG8] soporte %s -> %s | candidatos=%d" % [
		actor.display_name,
		String(actor.skill_by_kind("special").get("name", "")),
		candidates.size(),
	])
	_mark("el soporte ofrece elegir entre varios aliados",
		manager.needs_target(actor, "special") and candidates.size() > 1)
	if candidates.is_empty():
		battle.call("_finish_submit", "basic", "")
		await _wait_resolution(battle)
		return
	# Aliados heridos: sin dano previo la curacion no tendria efecto visible.
	for unit in manager.allies:
		if unit.alive:
			unit.hp = maxf(1.0, unit.max_hp() * 0.5)
	var chosen = candidates[0]
	var hp_before := int(round(chosen.hp))
	actor.sp = CombatUnit.SP_MAX
	battle.call("_finish_submit", "special", String(chosen.source_key))
	await _wait_resolution(battle)
	var hp_after := int(round(chosen.hp))
	var mods: Array = []
	for mod in chosen.stats.active_mods():
		mods.append(String(mod.get("stat", "")))
	print("[DBG8] soporte sobre %s: HP %d -> %d   mods=%s" % [
		chosen.display_name, hp_before, hp_after, str(mods)])
	_mark("el soporte cura al aliado elegido", hp_after > hp_before)
	_mark("el soporte deja su efecto en el aliado elegido", not mods.is_empty())


## 3) MISIONES: progreso desde los contadores globales y recompensa una sola vez.
func _debug_v08_missions() -> void:
	GameState.counters = { "combates_jugados": 0, "victorias": 0, "derrotas": 0 }
	GameState.missions_claimed = {}
	var missions: Array = DB.all_missions()
	print("[DBG8] misiones cargadas: %d" % missions.size())
	for mission in missions:
		var state: Dictionary = GameState.mission_state(String(mission.get("id", "")))
		print("[DBG8]   %s  %d/%d  completada=%s  reclamada=%s  premio=%d monedas" % [
			String(state.get("name", "")),
			int(state.get("progress", 0)),
			int(state.get("target", 0)),
			str(state.get("completed", false)),
			str(state.get("claimed", false)),
			int(state.get("reward_coins", 0)),
		])
	_mark("una mision recien empezada no esta completada",
		not bool(GameState.mission_state("mis_primera_victoria").get("completed", true)))

	# Se suben los contadores a mano y se comprueba que el progreso los sigue: el
	# progreso NO se guarda, se calcula.
	GameState.add_counter("victorias", 3)
	var first: Dictionary = GameState.mission_state("mis_primera_victoria")
	var warrior: Dictionary = GameState.mission_state("mis_guerrero")
	print("[DBG8] con 3 victorias: %s %d/%d completada=%s | %s %d/%d completada=%s" % [
		String(first.get("name", "")), int(first.get("progress", 0)), int(first.get("target", 0)), str(first.get("completed", false)),
		String(warrior.get("name", "")), int(warrior.get("progress", 0)), int(warrior.get("target", 0)), str(warrior.get("completed", false)),
	])
	_mark("las misiones siguen los contadores globales",
		bool(first.get("completed", false)) and bool(warrior.get("completed", false)))

	# Se reclama desde la MISMA funcion que llama el boton de la pantalla.
	open_screen("missions")
	await get_tree().process_frame
	var missions_screen = _screens.get("missions", null)
	var coins_before := GameState.coins
	if missions_screen != null:
		missions_screen.call("_on_claim_pressed", "mis_primera_victoria")
		await get_tree().process_frame
		var list = missions_screen.get_node_or_null("Margin/Main/Scroll/List")
		if list != null:
			print("[DBG8] misiones pintadas: %d tarjetas" % list.get_child_count())
	print("[DBG8] monedas %d -> %d" % [coins_before, GameState.coins])
	_mark("la mision completada paga su recompensa", GameState.coins == coins_before + 100)
	_mark("la mision queda marcada como reclamada",
		bool(GameState.mission_state("mis_primera_victoria").get("claimed", false)))

	# Segundo intento: no puede volver a pagar.
	var coins_after_first := GameState.coins
	if missions_screen != null:
		missions_screen.call("_on_claim_pressed", "mis_primera_victoria")
		await get_tree().process_frame
	print("[DBG8] segundo intento de cobro: monedas %d -> %d (no puede subir)" % [
		coins_after_first, GameState.coins])
	_mark("una mision no paga dos veces", GameState.coins == coins_after_first)
	go_back()
	await get_tree().process_frame


## 4) GUARDADO: stages, monedas, misiones y equipo sobreviven a cerrar y reabrir.
func _debug_v08_save() -> void:
	var stage_before: Array = GameState.completed_stages.duplicate()
	var claimed_before := bool(GameState.mission_state("mis_primera_victoria").get("claimed", false))
	var coins_before := GameState.coins
	var party_before: Array = GameState.party.duplicate()
	var stage_id_before := GameState.stage_id
	GameState.save_game()
	var saved := FileAccess.file_exists("user://save.json")

	# Se olvida todo en memoria y se relee del disco: eso es "cerrar y reabrir".
	GameState.completed_stages = []
	GameState.missions_claimed = {}
	GameState.coins = 0
	GameState.party = []
	GameState.stage_id = ""
	var loaded: bool = GameState.load_game()

	print("[DBG8] guardado: escrito=%s, releido=%s" % [str(saved), str(loaded)])
	print("[DBG8] stages ganados %s -> %s" % [str(stage_before), str(GameState.completed_stages)])
	print("[DBG8] monedas %d -> %d" % [coins_before, GameState.coins])
	print("[DBG8] equipo %s -> %s" % [str(party_before), str(GameState.party)])
	print("[DBG8] stage elegido %s -> %s" % [stage_id_before, GameState.stage_id])
	print("[DBG8] mision reclamada=%s -> %s" % [
		str(claimed_before),
		str(GameState.mission_state("mis_primera_victoria").get("claimed", false)),
	])
	_mark("el desbloqueo de stages persiste", GameState.completed_stages == stage_before)
	_mark("las monedas persisten", GameState.coins == coins_before)
	_mark("el equipo persiste", GameState.party == party_before)
	_mark("las misiones reclamadas persisten",
		bool(GameState.mission_state("mis_primera_victoria").get("claimed", false)) == claimed_before)


## Veredicto de una comprobacion, en una linea y con la misma forma siempre.
## Ademas de la consola se vuelca a un archivo del proyecto, porque el panel de
## salida solo guarda los ultimos mensajes y los primeros veredictos se pierden.
func _mark(label: String, ok: bool) -> void:
	var line := "[DBG8] %s -> %s" % [label, "OK" if ok else "FALLO"]
	print(line)
	_append_result(line)


func _append_result(line: String) -> void:
	var file := FileAccess.open(RESULTS_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(line)
	file.close()


## --- Verificacion V1.0 hito 2: links, categorias y ficha ----------------------
## Todo lo que comprueba se ejecuta DENTRO del juego y por los mismos caminos que
## usa un jugador (abrir una batalla de verdad, abrir la coleccion, tocar una
## tarjeta). Los veredictos van a consola y a un archivo, porque el panel de
## salida solo conserva los ultimos mensajes.

const RESULTS_PATH_V10 := "res://dbg10_resultados.txt"
const V10_STATS := ["max_hp", "atk", "def", "speed", "crit_rate", "dodge_rate"]


func _out10(text: String) -> void:
	print(text)
	var file := FileAccess.open(RESULTS_PATH_V10, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RESULTS_PATH_V10, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(text)
	file.close()


func _mark10(label: String, ok: bool) -> void:
	_out10("[DBG10] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _debug_v10() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists(RESULTS_PATH_V10):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULTS_PATH_V10))
	print("[DBG10] --- verificacion V1.0 hito 2 ---")
	if not _backup_save():
		print("[DBG10] AVISO: no habia guardado previo que copiar")

	await _debug_v10_links()
	await _debug_v10_categories()
	await _debug_v10_ficha()

	close_battle()
	await get_tree().create_timer(0.25).timeout
	_restore_save()
	_out10("[DBG10] --- fin de la verificacion V1.0 hito 2 ---")


## Pareja de personajes del roster que comparten un link DE VERDAD. Se busca en
## los datos: si los JSON cambian, la prueba encuentra otra pareja sola.
func _v10_find_pair() -> Dictionary:
	var holders: Dictionary = {}
	for raw_id in GameState.roster:
		var id := String(raw_id)
		for raw_link in GameState.character_data(id).get("links", []):
			var link_id := String(raw_link)
			if not holders.has(link_id):
				holders[link_id] = []
			holders[link_id].append(id)
	var link_ids: Array = holders.keys()
	link_ids.sort()
	for raw_link in link_ids:
		var ids: Array = holders[raw_link]
		if ids.size() >= 2:
			return { "link": String(raw_link), "a": String(ids[0]), "b": String(ids[1]) }
	return {}


## Abre una batalla REAL con el equipo indicado y devuelve las estadisticas que el
## combate tiene de verdad para el personaje pedido, mas los links que el
## BattleManager considera activos y de donde vienen los modificadores.
func _v10_probe(party_ids: Array, target_id: String) -> Dictionary:
	GameState.select_stage("stage_001")
	GameState.party = party_ids.duplicate()
	close_battle()
	await get_tree().create_timer(0.15).timeout
	open_battle()
	await get_tree().create_timer(0.55).timeout
	var out := {
		"ok": false,
		"actual": {},
		"link_mods": 0,
		"active_links": [],
		"enemy_link_mods": 0,
	}
	var battle = _battle
	if battle == null:
		return out
	var manager = battle.get_node_or_null("BattleManager")
	if manager == null:
		return out
	out["ok"] = true
	out["active_links"] = manager.call("active_team_link_ids")
	for unit in manager.allies:
		if String(unit.id) != target_id:
			continue
		for stat in V10_STATS:
			out["actual"][stat] = unit.stats.get_stat(stat)
		for mod in unit.stats.active_mods():
			if String(mod["source"]).begins_with("link:"):
				out["link_mods"] = int(out["link_mods"]) + 1
	for unit in manager.enemies:
		for mod in unit.stats.active_mods():
			if String(mod["source"]).begins_with("link:"):
				out["enemy_link_mods"] = int(out["enemy_link_mods"]) + 1
	return out


## PRUEBA OBLIGATORIA DE LINKS. El mismo personaje, medido dentro de batallas
## reales: solo, acompanado de alguien que comparte su link, otra vez solo y otra
## vez acompanado. Comprueba que el bonus aparece, que su tamano es el del JSON,
## que desaparece al quitar al companero y que no se acumula.
func _debug_v10_links() -> void:
	var pair := _v10_find_pair()
	if pair.is_empty():
		_mark10("hay una pareja de personajes del roster que comparte un link", false)
		return
	_mark10("hay una pareja de personajes del roster que comparte un link", true)
	var link_id: String = pair["link"]
	var a: String = pair["a"]
	var b: String = pair["b"]
	var link: Dictionary = DB.get_link(link_id)
	_out10("[DBG10] link de prueba '%s' (%s) con %s y %s" % [
		link_id, String(link.get("name", "")), a, b])

	# La estadistica que se mide la decide el PROPIO link: la primera que modifique.
	# Asi la prueba sigue valiendo si se rebalancean los efectos.
	var stat := ""
	for effect in link.get("effects", []):
		if String(effect.get("type", "")) == "stat_mod":
			stat = String(effect.get("stat", ""))
			break
	if stat.is_empty():
		_mark10("el link de prueba modifica alguna estadistica", false)
		return
	_mark10("el link de prueba modifica alguna estadistica", true)
	var expected_mult := 0.0
	for effect in link.get("effects", []):
		if String(effect.get("type", "")) != "stat_mod":
			continue
		if String(effect.get("stat", "")) != stat:
			continue
		if String(effect.get("kind", "mult")) == "mult":
			expected_mult += float(effect.get("value", 0.0))
	_out10("[DBG10] se mide %s; el JSON del link declara x%.3f" % [stat, 1.0 + expected_mult])

	var solo := await _v10_probe([a], a)
	if not bool(solo["ok"]):
		_mark10("la batalla de prueba se abre", false)
		return
	_mark10("la batalla de prueba se abre", true)
	var solo_value := float(solo["actual"].get(stat, 0.0))
	var with_company := await _v10_probe([a, b], a)
	var company_value := float(with_company["actual"].get(stat, 0.0))
	var solo_again := await _v10_probe([a], a)
	var solo_again_value := float(solo_again["actual"].get(stat, 0.0))
	var company_again := await _v10_probe([a, b], a)
	var company_again_value := float(company_again["actual"].get(stat, 0.0))

	_out10("[DBG10] %s: solo=%.2f | con %s=%.2f | otra vez solo=%.2f | otra vez con %s=%.2f" % [
		stat, solo_value, b, company_value, solo_again_value, b, company_again_value])
	_mark10("un link con un unico portador NO se activa",
		int(solo["link_mods"]) == 0 and not solo["active_links"].has(link_id))
	_mark10("con dos portadores el link SI se activa",
		int(with_company["link_mods"]) > 0 and with_company["active_links"].has(link_id))
	_mark10("el link sube de verdad la estadistica que usa el combate", company_value > solo_value)
	var ratio := company_value / maxf(0.001, solo_value)
	_mark10("el bonus aplicado coincide con el del JSON (x%.3f esperado, x%.3f medido)" % [
		1.0 + expected_mult, ratio], absf(ratio - (1.0 + expected_mult)) < 0.03)
	_mark10("el bonus desaparece al quitar al companero",
		absf(solo_again_value - solo_value) < 0.01)
	_mark10("el bonus NO se acumula al repetir la batalla",
		absf(company_again_value - company_value) < 0.01)
	_mark10("los enemigos NO reciben bonus de link",
		int(with_company["enemy_link_mods"]) == 0 and int(solo["enemy_link_mods"]) == 0)


## CATEGORIAS: que los 28 personajes carguen, que ninguna categoria referenciada
## falte y que el filtro de la coleccion responda de verdad.
func _debug_v10_categories() -> void:
	var ids: Array = DB.character_ids()
	_mark10("se cargan los 28 personajes", ids.size() >= 28)
	var missing: Array = []
	var multi := 0
	var by_category: Dictionary = {}
	for raw_id in ids:
		var id := String(raw_id)
		var categories: Array = DB.get_character(id).get("categories", [])
		if categories.is_empty():
			missing.append("%s sin categorias" % id)
			continue
		if categories.size() >= 2:
			multi += 1
		for raw_cat in categories:
			var cat := String(raw_cat)
			if DB.get_category(cat).is_empty():
				missing.append("%s -> %s" % [id, cat])
			by_category[cat] = int(by_category.get(cat, 0)) + 1
	_out10("[DBG10] categorias en uso: %d | personajes con varias: %d | ids rotos: %d %s" % [
		by_category.size(), multi, missing.size(), str(missing)])
	_mark10("todas las categorias de los 28 personajes existen", missing.is_empty())
	_mark10("hay personajes con varias categorias", multi >= 20)
	var shared := 0
	for cat in by_category.keys():
		if int(by_category[cat]) >= 2:
			shared += 1
	_mark10("hay categorias compartidas por varios personajes (base para Leader Skills)",
		shared >= 5)


## Todo el texto visible de un nodo, titulos de pestana incluidos. Comprueba que
## la ficha ensena un dato de verdad, sin depender de su jerarquia interna.
func _v10_collect_text(node: Node) -> Array:
	var out: Array = []
	if node is Label:
		out.append(node.text)
	elif node is RichTextLabel:
		out.append(node.text)
	elif node is TabContainer:
		for i in node.get_tab_count():
			out.append(node.get_tab_title(i))
	for child in node.get_children():
		out.append_array(_v10_collect_text(child))
	return out


## FICHA: se abre desde la COLECCION por el mismo camino que un toque y se
## comprueba que trae sus cinco secciones y que ensena nombre, links y categorias.
func _debug_v10_ficha() -> void:
	open_screen("collection")
	await get_tree().create_timer(0.35).timeout
	var col: Node = _screens.get("collection", null)
	if col == null:
		_mark10("la pantalla de coleccion existe", false)
		return
	_mark10("la pantalla de coleccion existe", true)

	var grid: Node = col.get_node_or_null("Margin/Main/Scroll/Grid")
	var all_cards := grid.get_child_count() if grid != null else -1
	var chosen := ""
	for data in GameState.roster_data():
		for raw_cat in data.get("categories", []):
			var cat: Dictionary = DB.get_category(String(raw_cat))
			if not cat.is_empty():
				chosen = String(cat.get("name", ""))
				break
		if not chosen.is_empty():
			break
	_mark10("hay una categoria con nombre para probar el filtro", not chosen.is_empty())
	if grid != null and col.has_method("_on_category_selected") and not chosen.is_empty():
		col.call("_on_category_selected", chosen)
		await get_tree().create_timer(0.25).timeout
		var filtered := grid.get_child_count()
		_out10("[DBG10] coleccion: %d tarjetas sin filtro, %d con la categoria '%s'" % [
			all_cards, filtered, chosen])
		_mark10("el filtro de categoria de la coleccion responde",
			filtered > 0 and filtered <= all_cards)
		col.call("_on_category_selected", "TODAS")
		await get_tree().create_timer(0.2).timeout

	var roster: Array = GameState.roster_data()
	if roster.is_empty():
		_mark10("la coleccion tiene personajes", false)
		return
	var first: Dictionary = roster[0]
	col.call("_on_card_pressed", first)
	await get_tree().create_timer(0.4).timeout
	var panel: Node = col.get_node_or_null("UnitInfoPanel")
	if panel == null or not panel.has_method("is_open"):
		_mark10("la ficha de personaje se abre desde la coleccion", false)
		return
	var opened := bool(panel.call("is_open"))
	_mark10("la ficha de personaje se abre desde la coleccion", opened)
	var tabs: Node = panel.get_node_or_null("Center/Panel/Margin/VBox/Scroll/Tabs")
	var tab_count: int = int(tabs.call("get_tab_count")) if tabs != null else -1
	_out10("[DBG10] ficha de %s: abierta=%s | pestanas=%d" % [
		String(first.get("name", "")), str(opened), tab_count])
	_mark10("la ficha trae sus cinco secciones (DATOS, HABILIDADES, LINKS, CATEGORIAS, BATALLA)",
		tab_count >= 5)

	# Se recorre cada pestana para que su contenido exista antes de leerlo.
	var texts: Array = []
	if tabs != null:
		for i in tabs.get_tab_count():
			tabs.current_tab = i
			await get_tree().process_frame
			texts.append_array(_v10_collect_text(tabs))
	texts.append_array(_v10_collect_text(panel))
	_mark10("la ficha ensena el nombre del personaje",
		texts.has(String(first.get("name", ""))))

	var links: Array = GameState.link_status(String(first.get("id", "")))
	var link_shown := false
	for entry in links:
		if texts.has(String(entry.get("name", ""))):
			link_shown = true
			break
	_out10("[DBG10] links de %s: %d" % [String(first.get("name", "")), links.size()])
	_mark10("la ficha ensena los links del personaje", link_shown)

	var cat_shown := false
	for raw_cat in first.get("categories", []):
		var cat: Dictionary = DB.get_category(String(raw_cat))
		if not cat.is_empty() and texts.has(String(cat.get("name", ""))):
			cat_shown = true
			break
	_mark10("la ficha ensena las categorias del personaje", cat_shown)

	panel.call("close_panel")
	await get_tree().create_timer(0.25).timeout
	_mark10("la ficha se cierra", not bool(panel.call("is_open")))


## --- Verificacion V1.2: HISTORIA Y MAPA --------------------------------------

## Verdadero cuando el overlay de dialogo avisa de que ha terminado. Vive en una
## variable de la instancia porque una lambda captura por valor y no dejaria ver
## el cambio desde fuera.
var _dbg12_finished := false


func _dbg12_on_finished() -> void:
	_dbg12_finished = true


const RESULTS_PATH_V12 := "res://dbg12_resultados.txt"


## Informe de la campana V1.2. Se vuelca a un archivo ademas de a la consola: el
## panel de salida solo conserva los ultimos mensajes y el veredicto de cada
## comprobacion se perderia.
func _out12(text: String) -> void:
	print(text)
	var file := FileAccess.open(RESULTS_PATH_V12, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RESULTS_PATH_V12, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(text)
	file.close()


## Marca de la campana V1.2, con el mismo formato que las demas: una linea por
## comprobacion diciendo si ha pasado o no.
func _mark12(label: String, ok: bool) -> void:
	_out12("[DBG12] %s -> %s" % [label, "OK" if ok else "FALLO"])


## Verificacion del HITO 2 jugada de verdad: abre las pantallas, dispara los
## MISMOS metodos que los botones y lee el estado resultante. No copia logica.
func _debug_v12() -> void:
	await get_tree().process_frame
	# El informe de una pasada anterior no debe mezclarse con el de esta.
	var fresh := FileAccess.open(RESULTS_PATH_V12, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out12("[DBG12] --- verificacion V1.2 (historia y mapa) ---")
	_backup_save()
	# La prueba de la HISTORIA tiene que empezar desde CERO para poder comprobar el
	# desbloqueo progresivo: con un guardado que ya tiene el mundo 1 superado, la
	# historia se salta (es correcto) y no habria nada que medir. Se trabaja sobre
	# el estado en memoria y el guardado del jugador se devuelve al terminar.
	GameState.delete_save()
	GameState.story_progress = {}
	GameState.completed_stages = []
	GameState.current_world_id = ""
	_out12("[DBG12] historia reiniciada solo para la prueba (el guardado se restaura al final)")

	# 1) MUNDOS: los tres estan en datos y solo el primero esta abierto.
	var worlds: Array = DB.all_worlds()
	_out12("[DBG12] mundos cargados: %d" % worlds.size())
	_mark12("hay tres mundos de historia", worlds.size() >= 3)
	for world in worlds:
		var wid := String((world as Dictionary).get("id", ""))
		_out12("[DBG12] mundo %s: abierto=%s, niveles=%d, superados=%d" % [
			wid,
			str(GameState.world_unlocked(wid)),
			int(GameState.world_status(wid).get("level_count", 0)),
			GameState.world_completed_levels(wid),
		])
	_mark12("el mundo 1 esta abierto", GameState.world_unlocked("world_001"))
	_mark12("el mundo 2 empieza bloqueado", not GameState.world_unlocked("world_002"))

	# 2) PANTALLA HISTORIA: una tarjeta por mundo.
	var history = _screens.get("history", null)
	open_screen("history")
	await get_tree().process_frame
	await get_tree().process_frame
	_mark12("la pantalla HISTORIA se abre", current_screen() == "history")
	if history != null:
		history.call("refresh")
		await get_tree().process_frame
		var list = history.get_node_or_null("Margin/Main/Scroll/List")
		var cards := _grid_count(list) if list != null else -1
		_out12("[DBG12] tarjetas de mundo pintadas: %d" % cards)
		_mark12("se pinta una tarjeta por mundo", cards == worlds.size())

	# 3) MAPA: se entra por la MISMA funcion que dispara la tarjeta.
	var map = _screens.get("world_map", null)
	if history == null or map == null:
		_mark12("existen las pantallas de historia y mapa", false)
		_restore_save()
		return
	history.call("_on_world_pressed", "world_001")
	await get_tree().process_frame
	await get_tree().process_frame
	_mark12("la tarjeta del mundo abre el MAPA", current_screen() == "world_map")
	_mark12("el mapa recuerda el mundo elegido", GameState.current_world_id == "world_001")

	map.call("refresh")
	await get_tree().process_frame
	await get_tree().process_frame
	var area = map.get_node_or_null("MapArea")
	var nodes := 0
	var locked := 0
	if area != null:
		for child in area.get_children():
			if child is Button:
				nodes += 1
				if bool((child as Button).disabled):
					locked += 1
	_out12("[DBG12] casillas en el mapa: %d (bloqueadas: %d)" % [nodes, locked])
	_mark12("el mapa pinta una casilla por nivel",
		nodes == int(GameState.world_status("world_001").get("level_count", 0)))
	_mark12("solo la primera casilla esta disponible", nodes > 0 and locked == nodes - 1)

	# 4) DIFICULTADES: al tocar el primer nivel sale el panel con las tres.
	map.call("_on_level_pressed", "world_001_01")
	await get_tree().process_frame
	var scrim = map.get_node_or_null("PanelScrim")
	var diff_list = map.get_node_or_null("PanelScrim/Center/LevelPanel/PanelBox/DifficultyList")
	var diff_buttons := _grid_count(diff_list) if diff_list != null else -1
	var diff_locked := 0
	if diff_list != null:
		for child in diff_list.get_children():
			if child is Button and bool((child as Button).disabled):
				diff_locked += 1
	_out12("[DBG12] dificultades en el panel: %d (bloqueadas: %d)" % [diff_buttons, diff_locked])
	_mark12("el panel de dificultad se abre", scrim != null and bool(scrim.visible))
	_mark12("el nivel ofrece NORMAL, DIFICIL y EXTREMO", diff_buttons == 3)
	_mark12("al empezar solo NORMAL esta disponible", diff_locked == 2)

	# 5) FLUJO COMPLETO: nivel -> dificultad -> DIALOGO -> SKIP -> COMBATE.
	map.call("_on_difficulty_pressed", "normal")
	await get_tree().process_frame
	var overlay = map.get_node_or_null("DialogueOverlay")
	_dbg12_finished = false
	if overlay != null:
		overlay.connect("finished", _dbg12_on_finished)
	map.call("_on_start_pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var overlay_visible := overlay != null and bool(overlay.visible)
	var first_text := ""
	if overlay != null:
		var text_label = overlay.get("text_label")
		if text_label != null:
			first_text = String(text_label.text)
		# Detalle para saber POR QUE el texto esta vacio si lo estuviera.
		var status_now: Dictionary = GameState.story_level_status("world_001_01")
		var dlg_id := String(status_now.get("dialogue", ""))
		_out12("[DBG12] dialogo del nivel='%s', lineas en datos=%d, y=index %d" % [
			dlg_id, DB.dialogue_lines(dlg_id).size(), int(overlay.call("current_index"))])
		_out12("[DBG12] nodo de texto=%s, longitudes: texto=%d, hablante=%d, contador=%d" % [
			str(text_label), first_text.length(),
			String(overlay.get_node_or_null("Margin/Box/Dialog/Speech/SpeechBox/SpeakerRow/Speaker").text).length() if overlay.get_node_or_null("Margin/Box/Dialog/Speech/SpeechBox/SpeakerRow/Speaker") != null else -1,
			String(overlay.get_node_or_null("Margin/Box/Dialog/Speech/SpeechBox/Counter").text).length() if overlay.get_node_or_null("Margin/Box/Dialog/Speech/SpeechBox/Counter") != null else -1,
		])
	_out12("[DBG12] overlay visible=%s, primera linea='%s'" % [str(overlay_visible), first_text.substr(0, 48)])
	_mark12("el dialogo sale antes del combate", overlay_visible)
	_mark12("el dialogo ensena el texto de la linea", not first_text.is_empty())
	_mark12("el combate no se abre hasta que el dialogo termina", _battle == null)
	if overlay != null:
		overlay.call("_on_skip_pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	_out12("[DBG12] tras SKIP: aviso=%s, combate abierto=%s, enemigos=%s" % [
		str(_dbg12_finished), str(_battle != null), str(GameState.current_stage_enemies)])
	_mark12("SKIP avisa de que el dialogo ha terminado", _dbg12_finished)
	_mark12("tras SKIP se abre el combate", _battle != null)
	_mark12("el combate trae los enemigos del nivel", GameState.current_stage_enemies.size() == 1)
	if _battle != null:
		var manager = _battle.get("manager")
		if manager != null:
			_out12("[DBG12] unidades en combate: %d aliados, %d rivales" % [
				int((manager.get("allies") as Array).size()),
				int((manager.get("enemies") as Array).size())])
	close_battle()
	await get_tree().process_frame
	_mark12("el combate se cierra y se vuelve al mapa",
		_battle == null and current_screen() == "world_map")

	# 6) CONTINUAR y SKIP del overlay, ya sin ningun nivel seleccionado: cerrar el
	#    panel primero evita que un dialogo vacio dispare una batalla.
	map.call("_close_panel")
	if overlay != null:
		overlay.call("present", "dlg_world_001_001", "world_001_01")
		await get_tree().process_frame
		var before := int(overlay.call("current_index"))
		overlay.call("_on_continue_pressed")
		await get_tree().process_frame
		var after := int(overlay.call("current_index"))
		var total := int(overlay.call("line_count"))
		_out12("[DBG12] CONTINUAR: linea %d -> %d de %d" % [before, after, total])
		_mark12("CONTINUAR avanza de linea", after == before + 1)
		overlay.call("_on_skip_pressed")
		await get_tree().process_frame
		_mark12("SKIP cierra el overlay", not bool(overlay.visible))
		# Un dialogo sin lineas no puede dejar el juego colgado.
		overlay.call("present", "", "")
		await get_tree().process_frame
		await get_tree().process_frame
		_mark12("un dialogo vacio se cierra solo", not bool(overlay.visible))

	# 7) DESBLOQUEO PROGRESIVO: se supera el mundo 1 con el MISMO metodo que paga
	#    el combate de historia, y eso tiene que abrir el mundo 2.
	for level in DB.story_levels("world_001"):
		GameState.complete_story_level(String((level as Dictionary).get("id", "")), "normal", [])
	_out12("[DBG12] mundo 1 superado: %d/%d" % [
		GameState.world_completed_levels("world_001"),
		int(GameState.world_status("world_001").get("level_count", 0))])
	_mark12("superar el mundo 1 abre el mundo 2", GameState.world_unlocked("world_002"))
	_mark12("el mundo 3 sigue bloqueado", not GameState.world_unlocked("world_003"))
	_mark12("el segundo nivel queda desbloqueado", GameState.story_level_unlocked("world_001_02"))
	_mark12("EXTREMO queda pendiente (solo se pago NORMAL)",
		not GameState.story_level_completed("world_001_01", "extreme"))
	# EXTREMO arrastra y paga las dificultades inferiores.
	var report: Dictionary = GameState.complete_story_level("world_001_02", "extreme", [])
	_out12("[DBG12] EXTREMO en world_001_02 paga AHORA: %s" % str(report.get("completed", [])))
	# El contrato es: al superar EXTREMO quedan superadas las TRES dificultades, y
	# cada una se paga UNA sola vez. NORMAL ya estaba pagada en este nivel, asi que
	# ahora le tocan DIFICIL y EXTREMO (dos), no tres: repetirla seria pagar dos
	# veces la misma dificultad.
	_mark12("EXTREMO deja superadas NORMAL, DIFICIL y EXTREMO",
		GameState.story_level_completed("world_001_02", "normal")
		and GameState.story_level_completed("world_001_02", "hard")
		and GameState.story_level_completed("world_001_02", "extreme"))
	_mark12("EXTREMO no vuelve a pagar la dificultad ya superada",
		(report.get("completed", []) as Array).size() == 2
		and not (report.get("completed", []) as Array).has("normal"))

	# 8) GUARDADO: el mundo elegido y el progreso de historia sobreviven.
	GameState.current_world_id = ""
	GameState.story_progress = {}
	var loaded: bool = GameState.load_game()
	_out12("[DBG12] guardado releido=%s, mundo elegido=%s, mundo 2 abierto=%s" % [
		str(loaded), GameState.current_world_id, str(GameState.world_unlocked("world_002"))])
	_mark12("el mundo elegido se guarda", GameState.current_world_id == "world_001")
	_mark12("el progreso de historia sobrevive al guardado", GameState.world_unlocked("world_002"))

	# 9) VOLVER: del mapa a HISTORIA y de ahi al menu.
	map.call("_back")
	await get_tree().process_frame
	_mark12("VOLVER devuelve a HISTORIA", current_screen() == "history")
	history.call("_back")
	await get_tree().process_frame
	_mark12("VOLVER devuelve al MENU", current_screen() == "main_menu")

	# 10) Lo de siempre: las pantallas antiguas siguen abriendose y pintando.
	for screen in ["collection", "team", "stage_select", "missions", "summon"]:
		open_screen(screen)
		await get_tree().process_frame
		await get_tree().process_frame
		var node = _screens.get(screen, null)
		var painted := 0
		if node != null and node.has_method("refresh"):
			node.call("refresh")
			await get_tree().process_frame
		var target = null
		if node != null:
			if screen == "collection":
				target = node.get_node_or_null("Margin/Main/Scroll/Grid")
			elif screen == "team":
				target = node.get_node_or_null("Margin/Main/Scroll/Pool")
			elif screen == "stage_select":
				target = node.get_node_or_null("Margin/Main/Scroll/StageList")
		if target != null:
			painted = _grid_count(target)
		_out12("[DBG12] pantalla %s abierta=%s, contenido=%d" % [
			screen, str(current_screen() == screen), painted])
		_mark12("la pantalla %s se abre" % screen, current_screen() == screen)
	while go_back():
		await get_tree().process_frame
	_out12("[DBG12] de vuelta en: %s" % current_screen())

	# 11) COMBATE SUELTO: el modo de siempre sigue arrancando con sus stages.
	GameState.select_stage(String((DB.all_stages()[0] as Dictionary).get("id", "")))
	open_battle()
	await get_tree().create_timer(1.2).timeout
	_out12("[DBG12] combate de stage abierto=%s, enemigos=%s" % [
		str(_battle != null), str(GameState.current_stage_enemies)])
	_mark12("el combate de siempre sigue abriendo", _battle != null)
	if _battle != null:
		close_battle()
		await get_tree().process_frame
	_mark12("el combate se cierra bien", _battle == null)

	# 12) SALIR del combate con CLICS REALES sobre el motor: el boton pregunta,
	#     CANCELAR no cierra nada y confirmar libera la batalla sin pagar nada.
	GameState.select_stage(String((DB.all_stages()[0] as Dictionary).get("id", "")))
	var coins_before_exit := GameState.coins
	open_battle()
	await get_tree().create_timer(0.8).timeout
	if _battle == null:
		_mark12("la batalla se abre para probar SALIR", false)
	else:
		_click_control(_battle.get_node_or_null("ExitButton"), "clic en SALIR")
		await get_tree().process_frame
		var dialog = _battle.get_node_or_null("ConfirmOverlay")
		_mark12("SALIR pregunta antes de abandonar", dialog != null and bool(dialog.visible))
		_click_control(_find_button(dialog, "CANCELAR"), "clic en CANCELAR")
		await get_tree().process_frame
		_mark12("CANCELAR deja el combate en curso",
			_battle != null and dialog != null and not bool(dialog.visible))
		_click_control(_battle.get_node_or_null("ExitButton"), "clic en SALIR otra vez")
		await get_tree().process_frame
		var dialog2 = _battle.get_node_or_null("ConfirmOverlay")
		_click_control(_find_button(dialog2, "SALIR"), "clic en SALIR del dialogo")
		await get_tree().create_timer(0.5).timeout
		var battle_container := get_node_or_null("BattleContainer")
		var live_nodes := battle_container.get_child_count() if battle_container != null else -1
		_out12("[DBG12] tras confirmar SALIR: batalla liberada=%s, nodos vivos=%d, pantalla=%s" % [
			str(_battle == null), live_nodes, current_screen()])
		_mark12("confirmar SALIR libera la batalla", _battle == null and live_nodes == 0)
		_mark12("abandonar no paga monedas", GameState.coins == coins_before_exit)

	# 13) RESULTADO: una victoria y una derrota REALES, con los dos bandos cayendo
	#     por el mismo motor de dano, para ver que el resultado sale, que paga y
	#     que una misma batalla no paga dos veces.
	GameState.select_stage(String((DB.all_stages()[0] as Dictionary).get("id", "")))
	var coins_before_win := GameState.coins
	open_battle()
	await get_tree().create_timer(0.8).timeout
	var win_token := int(GameState.battle_token)
	var won: bool = await _dbg12_finish_battle(false)
	_mark12("la victoria abre la pantalla de resultado", won)
	_mark12("la victoria paga monedas", GameState.coins > coins_before_win)
	var second_pay: Dictionary = GameState.grant_battle_rewards(win_token, [], true)
	_mark12("una batalla no paga dos veces", not bool(second_pay.get("granted", true)))
	close_battle()
	await get_tree().create_timer(0.3).timeout

	GameState.select_stage(String((DB.all_stages()[0] as Dictionary).get("id", "")))
	var coins_before_loss := GameState.coins
	open_battle()
	await get_tree().create_timer(0.8).timeout
	var lost: bool = await _dbg12_finish_battle(true)
	_mark12("la derrota abre la pantalla de resultado", lost)
	_mark12("la derrota no paga monedas", GameState.coins == coins_before_loss)
	close_battle()
	await get_tree().create_timer(0.3).timeout

	_restore_save()
	_out12("[DBG12] --- fin de la verificacion V1.2 ---")


## Empuja la batalla abierta hacia su final: mata a un bando entero con el MISMO
## motor de dano (take_damage) y va resolviendo turnos hasta que el combate
## termina. Devuelve true si el combate ha llegado a su fin. No es una simulacion
## aparte: usa el BattleManager de la escena de combate que hay abierta.
## --- Verificacion V1.2 HITO 3: EVENTOS ---------------------------------------
## Misma forma que las demas campanas: se ejecuta DENTRO del juego, llama a los
## MISMOS metodos que los botones y deja una linea OK/FALLO por comprobacion en
## res://dbg13_resultados.txt. Antes de tocar nada copia el guardado del jugador
## y lo restaura al final, asi que pasar la prueba no le borra el progreso.
const RESULTS_PATH_V13 := "res://dbg13_resultados.txt"


func _out13(text: String) -> void:
	print(text)
	var file := FileAccess.open(RESULTS_PATH_V13, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RESULTS_PATH_V13, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(text)
	file.close()


func _mark13(label: String, ok: bool) -> void:
	_out13("[DBG13] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _debug_v13() -> void:
	await get_tree().process_frame
	var fresh := FileAccess.open(RESULTS_PATH_V13, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out13("[DBG13] --- verificacion V1.2 hito 3 (eventos) ---")
	_backup_save()

	# 1) DATOS del evento: existe, tiene tres stages y sale de res://data/events.
	var events: Array = DB.all_events()
	_out13("[DBG13] eventos cargados: %d" % events.size())
	_mark13("hay al menos un evento", events.size() >= 1)
	var event_id := "event_sindromes_de_la_pubertad"
	var event: Dictionary = DB.get_event(event_id)
	_mark13("el evento SINDROMES DE LA PUBERTAD existe", not event.is_empty())
	_out13("[DBG13] evento '%s', stages=%d" % [
		String(event.get("name", "")), DB.event_stages(event_id).size()])
	_mark13("el evento tiene tres stages", DB.event_stages(event_id).size() == 3)

	# 2) PARTIDA LIMPIA: sin el personaje y sin haber jugado el evento.
	GameState.delete_save()
	GameState.event_progress = {}
	GameState.inventory = {}
	GameState.story_progress = {}
	GameState.party = ["goku", "vegeta", "deku", "lucy"]
	_mark13("el inventario empieza sin uniformes", GameState.item_count("rabbit_costume") == 0)

	# 3) REQUISITO DE EQUIPO: los stages 2 y 3 piden Sakuta + Mai en el equipo.
	var gate_without: Dictionary = GameState.event_party_ready(event_id, "evt_sdp_02", GameState.party)
	var gate_with: Dictionary = GameState.event_party_ready(event_id, "evt_sdp_02", ["sakuta_mai", "goku"])
	_out13("[DBG13] stage 2 sin Sakuta+Mai: ok=%s, motivo='%s'" % [
		str(gate_without.get("ok", false)), String(gate_without.get("reason", ""))])
	_mark13("el stage 2 se cierra sin Sakuta + Mai en el equipo", not bool(gate_without.get("ok", true)))
	_mark13("el stage 2 se abre con Sakuta + Mai en el equipo", bool(gate_with.get("ok", false)))
	_mark13("el stage 1 no pide ningun personaje",
		bool(GameState.event_party_ready(event_id, "evt_sdp_01", ["goku"]).get("ok", false)))

	# 4) DROP AL PERDER: sin victoria no se entrega nada.
	var before_loss := GameState.item_count("rabbit_costume")
	var loss_report: Dictionary = GameState.complete_event_stage(event_id, "evt_sdp_02", GameState.party)
	_out13("[DBG13] stage 2 jugado sin Sakuta+Mai: ok=%s, drops=%d" % [
		str(loss_report.get("ok", false)), (loss_report.get("drops", []) as Array).size()])
	_mark13("sin el requisito el stage no paga ni suelta objetos",
		GameState.item_count("rabbit_costume") == before_loss)
	_mark13("el stage 2 no queda superado sin el requisito",
		not GameState.event_stage_completed(event_id, "evt_sdp_02"))

	# 5) DROP AL GANAR: con el requisito cumplido, 1-3 uniformes al inventario.
	GameState.party = ["sakuta_mai", "goku", "vegeta", "deku"]
	var win_report: Dictionary = GameState.complete_event_stage(event_id, "evt_sdp_02", GameState.party)
	var drops: Array = win_report.get("drops", [])
	var dropped := GameState.item_count("rabbit_costume")
	_out13("[DBG13] stage 2 ganado: ok=%s, drops=%s, uniformes=%d" % [
		str(win_report.get("ok", false)), str(drops), dropped])
	_mark13("ganar el stage 2 suelta uniformes", dropped >= 1)
	_mark13("el drop respeta el rango 1-3 del JSON", dropped >= 1 and dropped <= 3)
	_mark13("el objeto del drop es uniforme de conejita",
		(drops as Array).is_empty() or String((drops[0] as Dictionary).get("item", "")) == "rabbit_costume")
	_mark13("el stage 2 queda superado", GameState.event_stage_completed(event_id, "evt_sdp_02"))

	# 6) DROPS AL REPETIR: el evento se puede repetir por objetos (el stage ya
	#    estaba superado) y el inventario sigue subiendo.
	var before_repeat := GameState.item_count("rabbit_costume")
	GameState.complete_event_stage(event_id, "evt_sdp_02", GameState.party)
	_out13("[DBG13] repetir el stage 2: uniformes %d -> %d" % [before_repeat, GameState.item_count("rabbit_costume")])
	_mark13("repetir el stage vuelve a soltar objetos", GameState.item_count("rabbit_costume") > before_repeat)

	# 7) RECOMPENSA DE PERSONAJE: se reclama una sola vez, y SOLO tras superar el
	#    stage 1 (regla vigente: antes bastaba con pulsar el boton).
	_mark13("sin superar el stage 1 NO se puede reclamar",
		not bool(GameState.claim_event_character(event_id).get("ok", true)))
	GameState.complete_event_stage(event_id, "evt_sdp_01", GameState.party)
	var claim: Dictionary = GameState.claim_event_character(event_id)
	_out13("[DBG13] reclamar el personaje del evento: ok=%s, id=%s, ya=%s" % [
		str(claim.get("ok", false)), String(claim.get("id", "")), str(claim.get("already", false))])
	_mark13("el evento entrega su personaje", bool(claim.get("ok", false)))
	_mark13("el personaje entregado esta en el roster", GameState.is_owned("sakuta_mai"))
	_mark13("el personaje se queda en el roster tras reclamarlo dos veces",
		GameState.roster.count("sakuta_mai") == 1)

	# 8) CONTADOR DE EVENTO COMPLETADO: los tres stages seguidos suman.
	# El stage 3 es Sakuta UR SOLO, 1 VS 1 (regla vigente): se monta ese equipo.
	GameState.add_character("sakuta")
	GameState.party = ["sakuta", "", "", ""]
	GameState.normalize_party()
	GameState.complete_event_stage(event_id, "evt_sdp_03", GameState.party)
	_out13("[DBG13] stages superados=%d/3, veces completado=%d, contador='%s'=%d" % [
		GameState.event_cleared_count(event_id),
		GameState.event_times_completed(event_id),
		String(DB.get_event(event_id).get("counter", "")),
		GameState.counter_value(String(DB.get_event(event_id).get("counter", "")))])
	_mark13("los tres stages quedan superados", GameState.event_cleared_count(event_id) == 3)
	_mark13("completar el evento entero sube su contador",
		GameState.counter_value("eventos_completados") >= 1)

	# 9) PANTALLA: se abre, pinta una tarjeta por evento y sus botones existen.
	var events_screen = _screens.get("events", null)
	open_screen("events")
	await get_tree().process_frame
	await get_tree().process_frame
	_mark13("la pantalla EVENTOS se abre", current_screen() == "events")
	if events_screen != null:
		events_screen.call("refresh")
		await get_tree().process_frame
		var list = events_screen.get_node_or_null("Margin/Main/Scroll/List")
		var cards := _grid_count(list) if list != null else -1
		_out13("[DBG13] tarjetas pintadas en EVENTOS: %d" % cards)
		_mark13("se pinta una tarjeta por evento", cards >= 1)

	# 10) GUARDADO: inventario, progreso del evento y personaje sobreviven.
	var stock_before := GameState.item_count("rabbit_costume")
	GameState.inventory = {}
	GameState.event_progress = {}
	GameState.roster = GameState.roster.filter(func(x): return String(x) != "sakuta_mai")
	var loaded: bool = GameState.load_game()
	_out13("[DBG13] guardado releido=%s, uniformes=%d, stages=%d, personaje=%s" % [
		str(loaded), GameState.item_count("rabbit_costume"),
		GameState.event_cleared_count(event_id), str(GameState.is_owned("sakuta_mai"))])
	_mark13("el inventario sobrevive al guardado", GameState.item_count("rabbit_costume") == stock_before)
	_mark13("el progreso del evento sobrevive al guardado", GameState.event_cleared_count(event_id) == 3)
	_mark13("el personaje del evento sobrevive al guardado", GameState.is_owned("sakuta_mai"))

	# 11) COMBATE DEL EVENTO: arranca con los enemigos del stage de su JSON.
	GameState.prepare_battle(GameState.BATTLE_EVENT, { "event": event_id, "stage": "evt_sdp_01" })
	open_battle()
	await get_tree().create_timer(1.0).timeout
	_out13("[DBG13] combate de evento abierto=%s, enemigos=%s" % [
		str(_battle != null), str(GameState.current_stage_enemies)])
	_mark13("el combate de evento arranca", _battle != null)
	if _battle != null:
		close_battle()
		await get_tree().create_timer(0.3).timeout
	await go_back()
	await get_tree().process_frame

	_restore_save()
	_out13("[DBG13] --- fin de la verificacion del hito 3 ---")


## --- Verificacion del HITO: rarezas, arte por forma y evolucion ---------------
## Se ejecuta DENTRO del juego y toca los MISMOS sistemas que la interfaz: el
## sistema central de rarezas, la busqueda de arte de ui/portrait.gd, StatBlock
## (donde se resuelve el multiplicador de forma) y GameState.evolve. No copia
## logica de ninguno.
const RESULTS_PATH_V14 := "res://dbg14_resultados.txt"


func _out14(text: String) -> void:
	print(text)
	var file := FileAccess.open(RESULTS_PATH_V14, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RESULTS_PATH_V14, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(text)
	file.close()


func _mark14(label: String, ok: bool) -> void:
	_out14("[DBG14] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _debug_v14() -> void:
	await get_tree().process_frame
	var fresh := FileAccess.open(RESULTS_PATH_V14, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out14("[DBG14] --- verificacion rarezas, arte por forma y evolucion ---")
	_backup_save()

	# 1) SISTEMA CENTRAL DE RAREZAS: las cinco formas y todos sus estilos.
	var forms: Array = VI.RARITY_ORDER
	_out14("[DBG14] rarezas definidas: %s" % str(forms))
	_mark14("estan las cinco formas (R, SR, SSR, UR, LR)", forms.size() == 5)
	var complete := true
	for rarity in forms:
		var entry: Dictionary = VI.rarity_entry(String(rarity))
		for key in ["color", "secondary", "border", "bg", "glow", "intensity", "animated"]:
			if not entry.has(key):
				complete = false
				_out14("[DBG14] a la rareza %s le falta '%s'" % [rarity, key])
	_mark14("cada rareza define color, secundario, borde, fondo, brillo e intensidad", complete)

	# La intensidad tiene que CRECER con la rareza: es lo que hace que un LR se
	# note mas que un SR sin que ninguna pantalla escriba numeros.
	var growing := true
	for i in range(1, forms.size()):
		if VI.rarity_intensity(String(forms[i])) < VI.rarity_intensity(String(forms[i - 1])):
			growing = false
	_mark14("el brillo y la intensidad crecen de R a LR", growing)
	_out14("[DBG14] intensidades: R=%.2f SR=%.2f SSR=%.2f UR=%.2f LR=%.2f" % [
		VI.rarity_intensity("R"), VI.rarity_intensity("SR"), VI.rarity_intensity("SSR"),
		VI.rarity_intensity("UR"), VI.rarity_intensity("LR")])

	# El marco de cada rareza es DISTINTO de verdad (no solo la etiqueta).
	var borders: Array = []
	for rarity in forms:
		var style := VI.rarity_card(String(rarity))
		borders.append(style.border_color.to_html(false))
	_out14("[DBG14] colores de borde por rareza: %s" % str(borders))
	var unique_borders := {}
	for b in borders:
		unique_borders[b] = true
	_mark14("cada rareza tiene su propio marco de carta", unique_borders.size() == forms.size())
	var evolved_style := VI.rarity_card("UR", false, true)
	_mark14("una forma evolucionada se viste distinto (borde secundario)",
		evolved_style.border_color.to_html(false) != VI.rarity_card("UR").border_color.to_html(false))
	_mark14("la comparacion de formas es correcta (SSR < UR < LR)",
		VI.is_form_upgrade("SSR", "UR") and VI.is_form_upgrade("UR", "LR") and not VI.is_form_upgrade("UR", "SSR"))

	# 2) ARTE POR FORMA: la convencion de carpetas.
	var ur_path: String = Portrait.form_art_path("gojo", "UR", "icon")
	var lr_path: String = Portrait.form_art_path("gojo", "LR", "icon")
	_out14("[DBG14] ruta del arte de forma UR: %s" % ur_path)
	_mark14("la convencion apunta a <id>/<forma>/<ranura>.png",
		ur_path == "res://art/characters/gojo/ur/icon.png" and lr_path == "res://art/characters/gojo/lr/icon.png")

	# 3) FALLBACK: sin PNG de la forma, se usa el arte base (y no se rompe).
	var probe: Control = Portrait.new()
	probe.name = "PortraitProbe"
	add_child(probe)
	# gojo no tiene carpeta ur/: el retrato tiene que caer al arte base.
	probe.call("setup", "gojo", Color.WHITE, "spiky", "", "icon", "UR")
	var probe_path := String(probe.get("art_path"))
	var probe_form := String(probe.get("form"))
	var has_real_art: bool = bool(probe.call("has_art"))
	_out14("[DBG14] retrato de gojo como UR: form='%s', arte='%s', tiene imagen=%s" % [
		probe_form, probe_path, str(has_real_art)])
	_mark14("la forma pedida llega al retrato", probe_form == "ur")
	_mark14("sin PNG de la forma cae al arte base", has_real_art and probe_path == "res://art/characters/gojo/icon.png")
	probe.queue_free()

	# 4) LA FORMA LLEGA A LAS PANTALLAS: form_of y el arte que pide cada una.
	GameState.rarities = {}
	_reset_gojo_to_base()
	# form_of devuelve la forma en minusculas ("ssr", "ur", "lr"), que es como se
	# llaman las carpetas de arte.
	_mark14("un personaje sin evolucionar esta en su forma base", GameState.form_of("gojo") == "ssr")
	var data_base: Dictionary = GameState.character_data("gojo")
	_mark14("el arte de la forma base es el suyo",
		Portrait.art_path_from(data_base, "icon") == "res://art/characters/gojo/icon.png")

	# 5) EVOLUCION: subir a nivel maximo, pagar y evolucionar.
	GameState.set_level("gojo", Progression.LEVEL_MAX)
	GameState.coins = 200000
	var can: Dictionary = GameState.can_evolve("gojo")
	_out14("[DBG14] puede evolucionar: ok=%s, motivo='%s'" % [str(can.get("ok", false)), String(can.get("reason", ""))])
	_mark14("con nivel maximo y monedas se puede evolucionar", bool(can.get("ok", false)))
	var multiplier := float(can.get("route", {}).get("stat_multiplier", 1.0))
	var before_atk := _atk_of("gojo")
	var report: Dictionary = GameState.evolve("gojo")
	_mark14("evolucionar devuelve informe", not report.is_empty())
	_mark14("la rareza cambia a la forma nueva", GameState.rarity_of("gojo") == "UR")
	_mark14("el sistema sabe que ha evolucionado", GameState.is_evolved("gojo"))
	_mark14("form_of devuelve la forma nueva", GameState.form_of("gojo") == "ur")
	_out14("[DBG14] forma=%s, multiplicador de forma=%.2f" % [GameState.form_of("gojo"), multiplier])

	# 6) ESTADISTICAS: el multiplicador de forma entra por StatBlock.
	var data_ur: Dictionary = GameState.character_data("gojo")
	var stat_mult := float(data_ur.get("stat_multiplier", 1.0))
	var after_atk := _atk_of("gojo")
	_out14("[DBG14] ATQ gojo base(SR/SSR)=%d  ->  forma UR nivel 1=%d (x%.2f)" % [
		int(round(before_atk)), int(round(after_atk)), stat_mult])
	_mark14("el multiplicador de forma sale de los datos", stat_mult > 1.0)
	# Comparacion HONESTA: evolucionar devuelve al nivel 1, asi que se compara la
	# forma nueva contra ELLA MISMA sin el multiplicador, a igual nivel. Si el
	# multiplicador no entrara por StatBlock, los dos numeros serian iguales.
	var plain: Dictionary = data_ur.duplicate(true)
	plain["stat_multiplier"] = 1.0
	var plain_unit := CombatUnit.new()
	plain_unit.setup(plain, true, -1)
	var plain_atk := plain_unit.attack()
	_out14("[DBG14] a nivel %d: forma nueva ATQ=%d, la misma forma sin multiplicador=%d" % [
		int(data_ur.get("level", 1)), int(round(after_atk)), int(round(plain_atk))])
	_mark14("la forma nueva pega mas fuerte que ella misma sin el multiplicador",
		after_atk > plain_atk)
	_mark14("y lo hace exactamente por el multiplicador de los datos",
		abs(after_atk - plain_atk * stat_mult) < 1.0)
	# Y el multiplicador NO se aplica a un personaje sin evolucionar.
	_mark14("un personaje sin evolucionar NO lleva multiplicador",
		abs(float(data_base.get("stat_multiplier", 1.0)) - 1.0) < 0.0001)
	# La mutacion no se pierde al evolucionar (regla del proyecto).
	GameState.mutations["gojo"] = {
		"rank": "B", "rank_name": "B", "bonus_percent": 4.0,
		"effect": "max_hp", "effect_name": "Vida", "effect_percent": 20.0,
		"stats": [{ "stat": "max_hp", "label": "VIDA MAX", "bonus": 0.04, "bonus_percent": 4.0, "kind": "mult", "text": "+4%" }],
		"sp_reduction": 0, "sp_cost_min": 1,
	}
	GameState.set_level("gojo", Progression.LEVEL_MAX)
	GameState.coins = 999999
	GameState.evolve("gojo")
	_mark14("la mutacion sobrevive a la evolucion", GameState.has_mutation("gojo"))

	# 7) ARTE DE LA FORMA DESPUES DE EVOLUCIONAR: sigue habiendo imagen.
	var data_evolved: Dictionary = GameState.character_data("gojo")
	var evolved_art: String = Portrait.art_path_from(data_evolved, "icon")
	_out14("[DBG14] arte que pide la ficha tras evolucionar: '%s'" % evolved_art)
	var probe2: Control = Portrait.new()
	add_child(probe2)
	probe2.call("setup", "gojo", Color.WHITE, "spiky", evolved_art, "icon", GameState.form_of("gojo"))
	var has_art_after: bool = bool(probe2.call("has_art"))
	var path_after := String(probe2.get("art_path"))
	probe2.queue_free()
	_out14("[DBG14] retrato tras evolucionar: arte='%s', tiene imagen=%s" % [path_after, str(has_art_after)])
	_mark14("tras evolucionar el retrato sigue teniendo imagen (arte de forma o base)", has_art_after)

	# 8) COLECCION Y EQUIPO pintan la forma nueva.
	var roster: Array = GameState.roster_data()
	var rarity_in_roster := ""
	for entry in roster:
		if String((entry as Dictionary).get("id", "")) == "gojo":
			rarity_in_roster = String((entry as Dictionary).get("rarity", ""))
	_mark14("la coleccion ve la forma evolucionada", rarity_in_roster == "UR")
	var party_rarity := ""
	for entry in GameState.party_data():
		if String((entry as Dictionary).get("id", "")) == "gojo":
			party_rarity = String((entry as Dictionary).get("rarity", ""))
	_mark14("el equipo ve la forma evolucionada", party_rarity == "UR" or not GameState.party.has("gojo"))

	# 9) COMBATE: la unidad que entra a combatir lleva la forma nueva y su arte de
	#    espaldas (back), que es el que usa el jugador.
	var fighter: CombatUnit = CombatUnit.new()
	fighter.setup(GameState.character_data("gojo"), true, 0)
	var back_probe: String = Portrait.form_art_path(fighter.id, fighter.rarity, "back")
	_out14("[DBG14] unidad en combate: rareza=%s, nivel=%d, arte de espaldas esperado=%s" % [
		fighter.rarity, fighter.level, back_probe])
	_mark14("la unidad de combate lleva la rareza evolucionada", fighter.rarity == "UR")

	# 10) GUARDADO: la forma sobrevive a cerrar y reabrir.
	GameState.save_game()
	GameState.rarities = {}
	var loaded: bool = GameState.load_game()
	_out14("[DBG14] guardado releido=%s, rareza tras recargar=%s" % [str(loaded), GameState.rarity_of("gojo")])
	_mark14("la forma evolucionada sobrevive al guardado", loaded and GameState.rarity_of("gojo") == "UR")
	_mark14("is_form_upgrade reconoce la forma guardada como superior",
		VI.is_form_upgrade(GameState.base_rarity_of("gojo"), GameState.rarity_of("gojo")))

	# 11) FICHA: la seccion de evolucion y mutacion se pintan donde toca.
	var collection = _screens.get("collection", null)
	if collection != null:
		var panel = collection.get_node_or_null("UnitInfoPanel")
		if panel != null:
			panel.call("open_for_data", GameState.character_data("miku"), false)
			await get_tree().process_frame
			var texts: Array = _v10_collect_text(panel)
			_mark14("la ficha ensena la seccion de MUTACION", texts.has("MUTACION"))
			_mark14("la ficha dice que no hay mutacion", texts.has("Sin mutacion. Se puede tirar una en la pantalla MUTACIONES."))
			panel.call("close_panel")
			await get_tree().process_frame
	# Y la seccion de EVOLUCION de un personaje que SI puede evolucionar.
	GameState.set_level("tanjiro", Progression.LEVEL_MAX)
	GameState.coins = 999999
	var can_tanjiro: Dictionary = GameState.can_evolve("tanjiro")
	_out14("[DBG14] tanjiro a nivel maximo: ok=%s, a=%s" % [
		str(can_tanjiro.get("ok", false)), String(can_tanjiro.get("to", ""))])
	if collection != null:
		var panel2 = collection.get_node_or_null("UnitInfoPanel")
		if panel2 != null:
			panel2.call("open_for_data", GameState.character_data("tanjiro"), false)
			await get_tree().process_frame
			var texts2: Array = _v10_collect_text(panel2)
			_mark14("la ficha ensena la seccion de EVOLUCION", texts2.has("EVOLUCION"))
			_mark14("la ficha ensena los requisitos con el progreso real",
				texts2.has("EVOLUCIONABLE") and texts2.has("Nivel: 100 / 100"))
			panel2.call("close_panel")
			await get_tree().process_frame

	# 12) TRANSICION: se construye y se pinta sin romper nada.
	var fx = EvolutionFx.play(self, "SSR", "UR", "Prueba")
	_mark14("la transicion de evolucion se crea", fx != null and is_instance_valid(fx))
	if fx != null:
		await get_tree().create_timer(0.3).timeout
		_mark14("la transicion se pinta encima y se retira sola",
			is_instance_valid(fx) and fx.visible)
		fx.queue_free()

	_restore_save()
	_out14("[DBG14] --- fin de la verificacion ---")


## Devuelve a gojo a su forma base (para que la prueba parta siempre del mismo
## estado, sin depender de lo que hubiera antes).
func _reset_gojo_to_base() -> void:
	GameState.rarities.erase("gojo")
	GameState.set_level("gojo", Progression.LEVEL_MAX)


## Ataque resuelto de un personaje, construyendo la MISMA unidad que entra al
## combate (es el numero que se juega, no una copia de la formula).
func _atk_of(id: String) -> float:
	var unit: CombatUnit = CombatUnit.new()
	unit.setup(GameState.character_data(id), true, 0)
	return unit.attack()


## --- Verificacion de los bugs del evento -------------------------------------

const EVENTO := "event_sindromes_de_la_pubertad"
const STAGE_1 := "evt_sdp_01"
const STAGE_3 := "evt_sdp_03"
const RESULTS_PATH_V15 := "res://dbg15_resultados.txt"


func _out15(text: String) -> void:
	print(text)
	var file := FileAccess.open(RESULTS_PATH_V15, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RESULTS_PATH_V15, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(text)
	file.close()


func _mark15(label: String, ok: bool) -> void:
	_out15("[DBG15] %s -> %s" % [label, "OK" if ok else "FALLO"])


## Los dos bugs que el jugador ha reportado, comprobados contra el estado REAL.
func _debug_v15() -> void:
	await get_tree().process_frame
	var fresh := FileAccess.open(RESULTS_PATH_V15, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out15("[DBG15] --- bugs del evento: recompensa bloqueada y stage 3 = 1 VS 1 ---")
	_backup_save()

	# Partida limpia: nadie ha superado nada y nadie tiene el personaje.
	GameState.event_progress = {}
	GameState.roster = GameState.STARTING_ROSTER.duplicate()
	GameState.rarities.erase("sakuta_mai")
	GameState.rarities.erase("sakuta")
	GameState.save_game()

	# --- BUG 1: la recompensa de personaje sin superar su stage -----------------
	_out15("[DBG15] stage 1 superado=%s, reclamado=%s" % [
		str(GameState.event_stage_completed(EVENTO, STAGE_1)),
		str(GameState.event_character_claimed(EVENTO))])
	_mark15("el evento empieza sin el stage 1 superado",
		not GameState.event_stage_completed(EVENTO, STAGE_1))
	var ready_before: Dictionary = GameState.event_reward_ready(EVENTO)
	_out15("[DBG15] reclamable antes de jugar: ok=%s, motivo='%s'" % [
		str(ready_before.get("ok", false)), String(ready_before.get("reason", ""))])
	_mark15("la recompensa NO es reclamable antes de superar el stage 1",
		not bool(ready_before.get("ok", true)))
	# El intento directo (lo que hacia el bug) tiene que ser rechazado.
	var cheat: Dictionary = GameState.claim_event_character(EVENTO)
	_out15("[DBG15] intento de reclamar sin progreso: ok=%s, motivo='%s'" % [
		str(cheat.get("ok", false)), String(cheat.get("reason", ""))])
	_mark15("reclamar a mano no entrega el personaje sin progreso",
		not bool(cheat.get("ok", false)))
	_mark15("y el personaje NO ha entrado en el roster",
		not GameState.is_owned("sakuta_mai"))

	# Ahora si: se supera el stage 1 por el mismo camino que el combate.
	GameState.complete_event_stage(EVENTO, STAGE_1, [])
	var ready_after: Dictionary = GameState.event_reward_ready(EVENTO)
	_out15("[DBG15] tras superar el stage 1: reclamable=%s" % str(ready_after.get("ok", false)))
	_mark15("superado el stage 1 la recompensa SI se puede reclamar",
		bool(ready_after.get("ok", false)))
	var claim: Dictionary = GameState.claim_event_character(EVENTO)
	_mark15("y entonces si se entrega", bool(claim.get("ok", false)))
	_mark15("el personaje esta en el roster", GameState.is_owned("sakuta_mai"))

	# --- BUG 2: el stage 3 es 1 VS 1 con Sakuta UR ------------------------------
	var gate_ssr: Dictionary = GameState.event_party_ready(EVENTO, STAGE_3, ["sakuta_mai", "gojo"])
	_out15("[DBG15] stage 3 con Sakuta+Mai SSR y companeros: ok=%s, motivo='%s'" % [
		str(gate_ssr.get("ok", false)), String(gate_ssr.get("reason", ""))])
	_mark15("el stage 3 RECHAZA a la forma SSR", not bool(gate_ssr.get("ok", true)))
	_mark15("el stage 3 RECHAZA llevar companeros",
		not bool(gate_ssr.get("ok", true)))

	# Sakuta en su forma UR (el personaje evolucionado).
	GameState.rarities["sakuta"] = "UR"
	var gate_ur_party: Dictionary = GameState.event_party_ready(EVENTO, STAGE_3, ["sakuta", "gojo", "miku"])
	_out15("[DBG15] stage 3 con Sakuta UR y companeros en el equipo: ok=%s" % str(gate_ur_party.get("ok", false)))
	# SIN ATAJOS: el combate lleva EXACTAMENTE el equipo que el jugador tiene en la
	# pantalla EQUIPO, con sus huecos. Es el GATE del stage el que rechaza un
	# equipo que no encaje en el 1 VS 1, no una plantilla que recorte por detras.
	if not GameState.is_owned("sakuta"):
		GameState.roster.append("sakuta")
	GameState.party = ["sakuta", "gojo", "miku", ""]
	GameState.normalize_party()
	GameState.prepare_battle(GameState.BATTLE_EVENT, { "event": EVENTO, "stage": STAGE_3 })
	var lineup: Array = GameState.battle_party_ids()
	_out15("[DBG15] equipo con el que COMBATE el stage 3: %s (%d unidad)" % [str(lineup), lineup.size()])
	# party_count() cuenta UNIDADES (los huecos no son personajes); party.size() es
	# siempre PARTY_SIZE. La comparacion correcta es contra las unidades.
	_mark15("el combate lleva EXACTAMENTE el equipo del jugador, sin recortarlo",
		lineup.size() == GameState.party_count() and lineup.size() == 3)
	var units: Array = GameState.battle_party_data()
	_mark15("esas unidades se cargan de verdad desde los datos",
		units.size() == lineup.size())

	var gate_solo: Dictionary = GameState.event_party_ready(EVENTO, STAGE_3, ["sakuta"])
	_out15("[DBG15] stage 3 solo con Sakuta UR: ok=%s" % str(gate_solo.get("ok", false)))
	_mark15("el stage 3 SI acepta a Sakuta UR", bool(gate_solo.get("ok", false)))

	# Y el stage 2 mantiene su requisito de siempre (Sakuta + Mai SSR).
	var gate_2: Dictionary = GameState.event_party_ready(EVENTO, "evt_sdp_02", ["sakuta_mai", "gojo"])
	_out15("[DBG15] stage 2 con Sakuta+Mai en el equipo: ok=%s" % str(gate_2.get("ok", false)))
	_mark15("el stage 2 sigue pidiendo a Sakuta+Mai y no el 1 VS 1",
		bool(gate_2.get("ok", false)))
	GameState.prepare_battle(GameState.BATTLE_EVENT, { "event": EVENTO, "stage": "evt_sdp_02" })
	_mark15("el stage 2 NO reduce el equipo a una unidad",
		GameState.battle_party_ids().size() == GameState.party_count())

	# El combate normal sigue llevando el equipo entero.
	GameState.select_stage(String((DB.all_stages()[0] as Dictionary).get("id", "")))
	_mark15("una batalla normal sigue llevando el equipo completo",
		GameState.battle_party_ids().size() == GameState.party_count())

	_restore_save()
	_out15("[DBG15] --- fin ---")


## Arranca la verificacion del hito de bugs del evento.
func _debug_v15_start() -> void:
	await _debug_v15()


const RESULTS_PATH_V16 := "res://dbg16_resultados.txt"


func _out16(text: String) -> void:
	print(text)
	var file := FileAccess.open(RESULTS_PATH_V16, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RESULTS_PATH_V16, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(text)
	file.close()


func _mark16(label: String, ok: bool) -> void:
	_out16("[DBG16] %s -> %s" % [label, "OK" if ok else "FALLO"])


## Cuantas unidades de un objeto pide una ruta de evolucion (0 si no lo pide).
func _route_item_amount(route: Dictionary, item_id: String) -> int:
	for raw_cost in route.get("item_cost", []):
		if raw_cost is Dictionary and String((raw_cost as Dictionary).get("item", "")) == item_id:
			return int((raw_cost as Dictionary).get("amount", 0))
	return 0


## Verificacion JUGADA del hito: la evolucion de Sakuta con sus requisitos exactos
## (25 uniformes; 3 fichas, sin exigir vueltas), sin monedas; el inventario
## sumando y gastando; y el gacha. Toca el guardado del jugador, asi que lo copia
## al empezar y lo devuelve al terminar.
func _debug_v16() -> void:
	await get_tree().process_frame
	var fresh := FileAccess.open(RESULTS_PATH_V16, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out16("[DBG16] --- evolucion Sakuta, inventario y gacha ---")
	_backup_save()

	# 1) INVENTARIO: se suma y se gasta por GameState, nunca a mano.
	GameState.inventory.erase("rabbit_costume")
	GameState.inventory.erase("mai_token")
	_mark16("el inventario queda a cero", GameState.item_count("rabbit_costume") == 0)
	GameState.add_item("rabbit_costume", 30)
	_mark16("sumar objetos sube la cantidad", GameState.item_count("rabbit_costume") == 30)
	_mark16("gastar mas de lo que hay no gasta nada", not GameState.remove_item("rabbit_costume", 31))
	_mark16("gastar lo justo deja el inventario a cero",
		GameState.remove_item("rabbit_costume", 30) and GameState.item_count("rabbit_costume") == 0)
	GameState.add_item("rabbit_costume", 30)
	GameState.add_item("mai_token", 5)

	# 2) EVOLUCION 1: Sakuta + Mai SSR -> Sakuta UR. Nivel 100 y 25 uniformes.
	var route1: Dictionary = {}
	for raw_route in DB.special_evolution_routes_from("sakuta_mai"):
		route1 = raw_route
		break
	_mark16("la ruta Sakuta + Mai -> Sakuta existe", not route1.is_empty())
	_out16("[DBG16] 1a ruta: nivel=%d monedas=%d objetos=%s" % [
		int(route1.get("level_required", 0)), int(route1.get("coin_cost", 0)), str(route1.get("item_cost", []))])
	_mark16("la 1a ruta NO cuesta monedas", int(route1.get("coin_cost", 0)) == 0)
	_mark16("la 1a ruta pide 25 uniformes", _route_item_amount(route1, "rabbit_costume") == 25)

	if not GameState.is_owned("sakuta_mai"):
		GameState.add_character("sakuta_mai")
	GameState.set_level("sakuta_mai", 50)
	_mark16("sin nivel 100 la evolucion esta bloqueada",
		not bool(GameState.can_special_evolve("sakuta_mai").get("ok", false)))
	GameState.set_level("sakuta_mai", 100)
	GameState.inventory.erase("rabbit_costume")
	_mark16("sin los 25 uniformes la evolucion esta bloqueada",
		not bool(GameState.can_special_evolve("sakuta_mai").get("ok", false)))
	GameState.add_item("rabbit_costume", 24)
	_mark16("con 24 uniformes sigue bloqueada",
		not bool(GameState.can_special_evolve("sakuta_mai").get("ok", false)))
	GameState.add_item("rabbit_costume", 1)
	_mark16("con nivel 100 y 25 uniformes se puede evolucionar",
		bool(GameState.can_special_evolve("sakuta_mai").get("ok", false)))

	var coins_before := GameState.coins
	var evo1: Dictionary = GameState.evolve_special("sakuta_mai")
	_mark16("la 1a evolucion devuelve informe", not evo1.is_empty())
	_mark16("y NO cobra ni una moneda", GameState.coins == coins_before)
	_mark16("consume exactamente los 25 uniformes", GameState.item_count("rabbit_costume") == 0)
	_mark16("ahora el jugador tiene a Sakuta", GameState.is_owned("sakuta"))
	_mark16("Sakuta es de rareza UR", GameState.rarity_of("sakuta") == "UR")

	# 3) EVOLUCION 2: Sakuta UR -> Sakuta + Mai LR. 3 fichas.
	var route2: Dictionary = {}
	for raw_route in DB.special_evolution_routes_from("sakuta"):
		route2 = raw_route
		break
	_mark16("la ruta Sakuta -> Sakuta + Mai LR existe", not route2.is_empty())
	# Regla vigente (el usuario la fijo): SOLO 3 fichas, sin exigir vueltas al evento.
	_mark16("NO exige vueltas del evento (solo las fichas)", int(route2.get("requires_event_clears", 0)) == 0)
	_mark16("pide 3 fichas doradas de Mai", _route_item_amount(route2, "mai_token") == 3)
	_mark16("la 2a ruta NO cuesta monedas", int(route2.get("coin_cost", 0)) == 0)

	GameState.inventory.erase("mai_token")
	_mark16("sin las 3 fichas la 2a evolucion esta bloqueada",
		not bool(GameState.can_special_evolve("sakuta").get("ok", false)))
	GameState.add_item("mai_token", 2)
	_mark16("con solo 2 fichas sigue bloqueada",
		not bool(GameState.can_special_evolve("sakuta").get("ok", false)))
	GameState.add_item("mai_token", 1)
	GameState.event_progress.erase("event_sindromes_de_la_pubertad")
	_mark16("con 3 fichas y 0 vueltas al evento SE puede evolucionar",
		bool(GameState.can_special_evolve("sakuta").get("ok", false)))

	coins_before = GameState.coins
	var evo2: Dictionary = GameState.evolve_special("sakuta")
	_mark16("la 2a evolucion devuelve informe", not evo2.is_empty())
	_mark16("y tampoco cobra monedas", GameState.coins == coins_before)
	_mark16("consume exactamente las 3 fichas", GameState.item_count("mai_token") == 0)
	_mark16("ahora el jugador tiene la forma LR", GameState.is_owned("sakuta_mai_lr"))
	_mark16("y es de rareza LR", GameState.rarity_of("sakuta_mai_lr") == "LR")

	# 4) GACHA: una multi de 10 sobre un banner de datos.
	var banner := ""
	var banners: Array = DB.all_banners()
	if not banners.is_empty():
		banner = String((banners[0] as Dictionary).get("id", ""))
	_mark16("hay un banner cargado de datos", not banner.is_empty())
	var rates: Dictionary = GameState.banner_rates(banner)
	_out16("[DBG16] probabilidades del banner: %s" % str(rates))
	_mark16("el banner declara 15%% de SSR por tirada", absf(float(rates.get("SSR", 0.0)) - 0.15) < 0.0001)
	var cost10 := GameState.banner_cost(banner, 10)
	GameState.gems = cost10 + 50
	var owned_before := GameState.owned_count()
	var pulled: Dictionary = GameState.summon(banner, 10)
	_mark16("la invocacion x10 devuelve informe", bool(pulled.get("ok", false)))
	_mark16("y devuelve EXACTAMENTE 10 resultados", (pulled.get("results", []) as Array).size() == 10)
	_mark16("cuesta lo que dice el banner", int(pulled.get("cost", 0)) == cost10)
	_mark16("las gemas se cobran una sola vez", GameState.gems == 50)
	_mark16("la coleccion no pierde personajes", GameState.owned_count() >= owned_before)
	var rarities := {}
	var already_owned := 0
	for entry in pulled.get("results", []):
		var hit: Dictionary = entry
		rarities[String(hit.get("rarity", ""))] = true
		if bool(hit.get("duplicate", false)):
			already_owned += 1
	_out16("[DBG16] rarezas salidas en la multi: %s (repetidos: %d)" % [str(rarities.keys()), already_owned])
	_mark16("cada resultado trae su rareza resuelta", rarities.size() >= 1)
	GameState.gems = 0
	_mark16("sin gemas no se puede invocar", not bool(GameState.summon(banner, 1).get("ok", false)))

	# 5) La pantalla de INVOCAR se pinta y revela las cartas del informe.
	GameState.gems = cost10 * 2
	open_screen("summon")
	await get_tree().process_frame
	await get_tree().process_frame
	var summon = _screens.get("summon", null)
	_mark16("la pantalla INVOCAR se abre", current_screen() == "summon")
	if summon != null:
		summon.call("_on_roll", 10)
		# Las cartas se revelan al final de la animacion de invocacion.
		await get_tree().create_timer(3.2).timeout
		var grid = summon.get_node_or_null("Margin/Main/ResultsScroll/ResultsGrid")
		var cards := _grid_count(grid) if grid != null else -1
		_out16("[DBG16] cartas pintadas en INVOCAR: %d" % cards)
		_mark16("la pantalla pinta una carta por resultado", cards == 10)
	go_back()
	await get_tree().process_frame

	# 6) COMBATE: la casilla de un aliado pide FRONT (la fila es la representacion
	#    del EQUIPO) mientras el retrato grande del turno pide BACK (el que pelea).
	#    Antes las dos pedian BACK y el mismo personaje parecia salir dos veces.
	var probe_unit: CombatUnit = CombatUnit.new()
	probe_unit.setup(GameState.character_data("gojo"), true, 0)
	var probe_card = load("res://ui/unit_card.tscn").instantiate()
	add_child(probe_card)
	await get_tree().process_frame
	probe_card.call("bind", probe_unit, false)
	await get_tree().process_frame
	var probe_portrait = probe_card.get("portrait")
	var card_slot := String(probe_portrait.get("slot"))
	_out16("[DBG16] ranura que pide una casilla del equipo: '%s'" % card_slot)
	_mark16("las casillas del equipo piden FRONT", card_slot == "front")
	probe_card.queue_free()

	# 7) GUARDADO: la forma LR y el inventario sobreviven.
	GameState.save_game()
	var gems_now := GameState.gems
	GameState.gems = 0
	GameState.roster.clear()
	var loaded: bool = GameState.load_game()
	_mark16("el guardado se relee", loaded)
	_mark16("la forma LR sobrevive al guardado", GameState.is_owned("sakuta_mai_lr"))
	_mark16("las gemas sobreviven al guardado", GameState.gems == gems_now)

	_restore_save()
	_out16("[DBG16] --- fin ---")


func _dbg12_finish_battle(kill_allies: bool) -> bool:
	if _battle == null:
		return false
	var manager = _battle.get("manager")
	if manager == null:
		return false
	var doomed: Array = manager.allies if kill_allies else manager.enemies
	for unit in doomed:
		unit.take_damage(999999.0)
	for i in 40:
		if _battle == null:
			return true
		var overlay = _battle.get_node_or_null("ResultOverlay")
		if overlay != null and bool(overlay.visible):
			return true
		manager.submit_action({ "kind": "basic" })
		await get_tree().create_timer(0.2).timeout
	return false


## --- ARNES DEL HITO C (DEBUG_V17) ---------------------------------------------
## El arnes vive en res://scenes/debug/hito_c_checks.gd y usa las funciones y los
## handlers REALES del juego (GameState, GameSettings, GameAudio y estas
## pantallas). Aqui solo se arranca; desde el juego normal no se toca nada.
##
##   --dbg17        prueba completa (sin pantalla sale con 0 si todo va bien y 1
##                  si hay algun FALLO)
##   --dbg17-write  primera ejecucion: escribe los ajustes de prueba y sale
##   --dbg17-read   segunda ejecucion: comprueba que se cargaron y los restaura

var _hito_c: Node = null


## Arranca el arnes del Hito C. Con run_full en false se ejecuta solo la parte de
## persistencia de los ajustes (write_mode decide si escribe o si comprueba).
## Se carga con load() a proposito: si el arnes tuviera un error de script, el
## juego normal tiene que seguir arrancando igual.
func _start_hito_c(run_full: bool = true, write_mode: bool = true) -> void:
	if _hito_c != null:
		return
	var script: GDScript = load("res://scenes/debug/hito_c_checks.gd")
	if script == null:
		push_error("App: no se pudo cargar el arnes del Hito C.")
		return
	_hito_c = script.new()
	_hito_c.name = "HitoCChecks"
	add_child(_hito_c)
	if run_full:
		_hito_c.call("run", self)
	else:
		_hito_c.call("run_persistence", write_mode)


## Arnes del Hito D (torre y reglas de Mai): godot --headless --path . -- --dbg18
var _hito_d: Node = null


func _start_hito_d() -> void:
	if _hito_d != null:
		return
	var script: GDScript = load("res://scenes/debug/hito_d_checks.gd")
	if script == null:
		push_error("App: no se pudo cargar el arnes del Hito D.")
		return
	_hito_d = script.new()
	_hito_d.name = "HitoDChecks"
	add_child(_hito_d)
	_hito_d.call("run", self)
