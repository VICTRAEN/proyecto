extends Node

## COMPROBACIONES EN EJECUCION DE LAS COPIAS (v8). SOLO para pruebas.
## Arranque:  godot --path . -- --dbg21   (escribe res://dbg21_resultados.txt)
## Usa las funciones, la Coleccion y el Inventario REALES. Guarda y restaura el guardado.
##
## Casos pedidos:
##   - Gojo UR + tres copias SSR: la unidad UR no se toca, las copias son material
##     aparte (una sola carta SSR x3), se consumen de una en una y al llegar a cero
##     la entrada desaparece.
##   - David & Lucy LR + una copia nueva: llega como SSR, se guarda aparte y se
##     consume despues como Dupe de la unidad LR.
##   - Una unidad SSR nunca recibe Dupes.
##   - La identidad es el id estable (no el nombre visible ni la rareza).
##   - Guardar/cargar: sin copias fantasma, sin contadores incorrectos.

const RESULTS_PATH := "res://dbg21_resultados.txt"
const COLLECTION := preload("res://scenes/screens/collection.tscn")
const INVENTORY := preload("res://scenes/screens/inventory.tscn")
const GOJO := "gojo"
const DUO := "david_lucy_duo"
const OTHER := "nagi"

var _app: Node = null
var _fails := 0
var _checks := 0


func _out(text: String) -> void:
	print(text)
	var file := FileAccess.open(RESULTS_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(text)
	file.close()


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	_out("[DBG21] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _frames(count: int = 2) -> void:
	for i in count:
		await get_tree().process_frame


## Deja a un personaje como unidad evolucionada (o no) con `copies` copias y Dupe `level`.
func _own(id: String, form: String, copies: int, level: int = 0) -> void:
	if not GameState.roster.has(id):
		GameState.roster.append(id)
	GameState.progress[id] = { "level": 1, "xp": 0 }
	if form.is_empty():
		GameState.rarities.erase(id)
	else:
		GameState.rarities[id] = form
	GameState.duplicates[id] = copies
	if level > 0:
		GameState.dupe_levels[id] = level
	else:
		GameState.dupe_levels.erase(id)


func _stack_of(id: String) -> Dictionary:
	for stack in GameState.copy_stacks():
		if String(stack["id"]) == id:
			return stack
	return {}


func _cards_of(screen: Node, id: String) -> Array:
	var out: Array = []
	var grid: GridContainer = screen.get("grid")
	for card in grid.get_children():
		if card.get("data") is Dictionary and String((card.get("data") as Dictionary).get("id", "")) == id:
			out.append(card)
	return out


func _find_label(node: Node, label_name: String) -> Label:
	if node is Label and node.name == label_name:
		return node
	for child in node.get_children():
		var found := _find_label(child, label_name)
		if found != null:
			return found
	return null


func run(app: Node) -> void:
	_app = app
	await _frames()
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_out("[DBG21] --- comprobaciones de COPIAS Y DUPES ENTRE CALIDADES ---")
	_app.call("_backup_save")
	_check_gojo_data()
	await _check_gojo_screens()
	_check_gojo_consume()
	_check_duo()
	_check_ssr_cannot_receive()
	_check_identity()
	_check_summon_quality()
	_check_save_load()
	_check_old_save()
	_check_evolution_keeps_copies()
	_app.call("_restore_save")
	_out("[DBG21] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## --- Gojo UR + tres copias SSR ------------------------------------------------------

func _check_gojo_data() -> void:
	_out("[DBG21] == GOJO UR + 3 COPIAS SSR (datos) ==")
	_own(GOJO, "UR", 0)
	var roster_before := GameState.roster.size()
	var reports: Array = []
	for i in 3:
		reports.append(GameState.add_character(GOJO))
	var all_ssr := true
	var none_new := true
	for r in reports:
		if String(r["rarity"]) != "SSR":
			all_ssr = false
		if bool(r["added"]) or not bool(r["duplicate"]):
			none_new = false
	_check("cada copia nueva llega en su calidad INICIAL (SSR), aunque Gojo ya sea UR", all_ssr)
	_check("ninguna copia entra al roster como personaje nuevo", none_new and GameState.roster.size() == roster_before and GameState.roster.count(GOJO) == 1)
	_check("la unidad existente sigue siendo UR (no se degrada)", GameState.rarity_of(GOJO) == "UR" and GameState.is_evolved(GOJO))
	_check("hay 3 copias guardadas aparte y ningun Dupe aplicado", GameState.duplicates_of(GOJO) == 3 and GameState.dupe_copies_available(GOJO) == 3 and GameState.dupe_level_of(GOJO) == 0)
	var stack := _stack_of(GOJO)
	_check("una sola pila de copias: calidad SSR, x3, aparte de la unidad", not stack.is_empty() and String(stack["quality"]) == "SSR" and int(stack["count"]) == 3 and not bool(stack["merged"]))
	var stacks_for_gojo := 0
	for s in GameState.copy_stacks():
		if String(s["id"]) == GOJO:
			stacks_for_gojo += 1
	_check("no hay pilas duplicadas del mismo personaje y calidad", stacks_for_gojo == 1)


func _check_gojo_screens() -> void:
	_out("[DBG21] == GOJO UR + 3 COPIAS SSR (Coleccion e Inventario) ==")
	var collection: Node = COLLECTION.instantiate()
	add_child(collection)
	await _frames(2)
	collection.call("refresh")
	await _frames(2)
	var cards := _cards_of(collection, GOJO)
	var unit_card: Node = null
	var pile_card: Node = null
	for c in cards:
		var d: Dictionary = c.get("data")
		if bool(d.get("copy_only", false)):
			pile_card = c
		else:
			unit_card = c
	_check("Coleccion: exactamente DOS cartas de Gojo (la unidad UR y la pila SSR)", cards.size() == 2 and unit_card != null and pile_card != null)
	if unit_card != null and pile_card != null:
		_check("la unidad se ve UR y sin contador", String((unit_card.get("data") as Dictionary).get("rarity", "")) == "UR" and _find_label(unit_card, "CopyCount") == null)
		var count_label := _find_label(pile_card, "CopyCount")
		_check("la pila se ve SSR con el circulo de copias x3", String((pile_card.get("data") as Dictionary).get("rarity", "")) == "SSR" and count_label != null and count_label.text == "×3")
	var inventory: Node = INVENTORY.instantiate()
	add_child(inventory)
	await _frames(2)
	inventory.call("refresh")
	await _frames(2)
	var entries: Array = inventory.call("copy_entries")
	var entry: Dictionary = {}
	for e in entries:
		if String((e as Dictionary).get("character_id", "")) == GOJO:
			entry = e
	_check("Inventario: aparece UNA entrada de copias de Gojo (SSR, x3)", not entry.is_empty() and int(entry["count"]) == 3 and String(entry["rarity"]) == "SSR")
	# Consumir UNA copia: contador inmediato en pantalla.
	var rep := GameState.dupe_upgrade(GOJO)
	collection.call("refresh")
	inventory.call("refresh")
	await _frames(2)
	var pile2: Node = null
	for c in _cards_of(collection, GOJO):
		if bool((c.get("data") as Dictionary).get("copy_only", false)):
			pile2 = c
	var label2 := _find_label(pile2, "CopyCount") if pile2 != null else null
	_check("al consumir una copia el contador de la Coleccion pasa a x2 al instante", bool(rep.get("done", false)) and label2 != null and label2.text == "×2")
	var entry2: Dictionary = {}
	for e in inventory.call("copy_entries"):
		if String((e as Dictionary).get("character_id", "")) == GOJO:
			entry2 = e
	_check("...y el del Inventario tambien (x2)", int(entry2.get("count", 0)) == 2)
	GameState.dupe_upgrade(GOJO)
	GameState.dupe_upgrade(GOJO)
	collection.call("refresh")
	inventory.call("refresh")
	await _frames(2)
	_check("con 0 copias la pila SSR desaparece de la Coleccion (queda solo la unidad UR)", _cards_of(collection, GOJO).size() == 1)
	var gone := true
	for e in inventory.call("copy_entries"):
		if String((e as Dictionary).get("character_id", "")) == GOJO:
			gone = false
	_check("con 0 copias la entrada desaparece del Inventario", gone)
	collection.queue_free()
	inventory.queue_free()


func _check_gojo_consume() -> void:
	_out("[DBG21] == GOJO: CONSUMIR COPIAS ==")
	_check("tras consumir las 3 copias: Dupe 3, 0 copias, la unidad sigue UR", GameState.dupe_level_of(GOJO) == 3 and GameState.dupe_copies_available(GOJO) == 0 and GameState.rarity_of(GOJO) == "UR")
	_check("sin copias no hay pila y consumir otra vez NO cambia nada", _stack_of(GOJO).is_empty())
	var snap := JSON.stringify([GameState.duplicates, GameState.dupe_levels])
	var again := GameState.dupe_upgrade(GOJO)
	_check("consumir sin copias se rechaza y no toca el estado", not bool(again.get("done", false)) and JSON.stringify([GameState.duplicates, GameState.dupe_levels]) == snap)
	# La unidad objetivo no se consume: sigue en el roster, con su nivel de personaje.
	_check("la unidad objetivo nunca se consume (sigue en el roster, una sola vez)", GameState.is_owned(GOJO) and GameState.roster.count(GOJO) == 1)


## --- David & Lucy LR + una copia nueva ----------------------------------------------

func _check_duo() -> void:
	_out("[DBG21] == DAVID & LUCY LR + COPIA SSR ==")
	_own(DUO, "LR", 0)
	var other_before := JSON.stringify([GameState.duplicates_of(GOJO), GameState.duplicates_of(OTHER)])
	var report := GameState.add_character(DUO)
	_check("la copia nueva de David & Lucy llega como SSR", String(report["rarity"]) == "SSR" and bool(report["duplicate"]) and not bool(report["added"]))
	_check("la unidad LR no se modifica ni se degrada", GameState.rarity_of(DUO) == "LR" and GameState.level_of(DUO) == 1 and GameState.dupe_level_of(DUO) == 0)
	var stack := _stack_of(DUO)
	_check("la copia se guarda como material independiente (pila SSR x1, no fusionada con la LR)", not stack.is_empty() and String(stack["quality"]) == "SSR" and int(stack["count"]) == 1 and not bool(stack["merged"]))
	var status := GameState.dupe_status(DUO)
	_check("la unidad LR puede recibir esa copia SSR (misma identidad por id)", bool(status["ok"]) and int(status["copies"]) == 1)
	var rep := GameState.dupe_upgrade(DUO)
	_check("consumirla sube la LR a Dupe 1 y gasta exactamente esa copia", bool(rep.get("done", false)) and GameState.dupe_level_of(DUO) == 1 and GameState.dupe_copies_available(DUO) == 0)
	_check("la unidad sigue LR y la pila desaparece", GameState.rarity_of(DUO) == "LR" and _stack_of(DUO).is_empty())
	_check("no se ha consumido ninguna copia de otros personajes", JSON.stringify([GameState.duplicates_of(GOJO), GameState.duplicates_of(OTHER)]) == other_before)
	# Mismo caso con una unidad UR.
	_own(DUO, "UR", 2)
	var rep_ur := GameState.dupe_upgrade(DUO)
	_check("una copia SSR tambien mejora a una unidad UR del mismo personaje", bool(rep_ur.get("done", false)) and GameState.dupe_level_of(DUO) == 1 and GameState.dupe_copies_available(DUO) == 1)


func _check_ssr_cannot_receive() -> void:
	_out("[DBG21] == SOLO UR O LR RECIBEN DUPES ==")
	_own(OTHER, "", 3)
	var snap := JSON.stringify([GameState.duplicates, GameState.dupe_levels])
	var status := GameState.dupe_status(OTHER)
	var rep := GameState.dupe_upgrade(OTHER)
	_check("una unidad SSR NO puede recibir Dupes (aunque tenga copias)", not bool(status["ok"]) and not bool(rep.get("done", false)) and GameState.rarity_of(OTHER) != "UR")
	_check("el intento no consume nada", JSON.stringify([GameState.duplicates, GameState.dupe_levels]) == snap and GameState.dupe_copies_available(OTHER) == 3)
	var stack := _stack_of(OTHER)
	_check("sus copias se conservan como pila fusionada con la unidad (se ven en su propia carta)", not stack.is_empty() and int(stack["count"]) == 3 and bool(stack["merged"]))
	_own(OTHER, "UR", 3)
	_check("al evolucionar a UR esas mismas copias ya se pueden consumir", bool(GameState.dupe_status(OTHER)["ok"]))
	var rep2 := GameState.dupe_upgrade(OTHER)
	_check("y se consume solo una", bool(rep2.get("done", false)) and GameState.dupe_copies_available(OTHER) == 2)
	_own(OTHER, "", 0)


## --- Identidad por id ---------------------------------------------------------------

func _check_identity() -> void:
	_out("[DBG21] == IDENTIDAD POR ID ESTABLE ==")
	_own(GOJO, "UR", 2)
	_own(OTHER, "UR", 2)
	# Se le pone a OTHER el mismo nombre visible que a GOJO: las copias NO se mezclan.
	var other_data: Dictionary = DB.get_character(OTHER)
	var original_name := String(other_data.get("name", ""))
	other_data["name"] = String(DB.get_character(GOJO).get("name", ""))
	var stacks := 0
	for s in GameState.copy_stacks():
		if String(s["id"]) == GOJO or String(s["id"]) == OTHER:
			stacks += 1
	var before_other := GameState.dupe_copies_available(OTHER)
	GameState.dupe_upgrade(GOJO)
	_check("dos personajes con el MISMO nombre visible tienen pilas separadas", stacks == 2)
	_check("mejorar uno no gasta copias del otro", GameState.dupe_copies_available(OTHER) == before_other and GameState.dupe_copies_available(GOJO) == 1)
	other_data["name"] = original_name
	_own(GOJO, "", 0)
	_own(OTHER, "", 0)


## --- Invocaciones con unidades evolucionadas -----------------------------------------

func _check_summon_quality() -> void:
	_out("[DBG21] == INVOCAR CON UNIDADES YA EVOLUCIONADAS ==")
	var banner_id := ""
	for raw in DB.all_banners():
		if bool((raw as Dictionary).get("enabled", true)) and String((raw as Dictionary).get("id", "")) != "banner_david_lucy":
			banner_id = String((raw as Dictionary).get("id", ""))
			break
	GameState.pending_reveal = {}
	var pool: Array = GameState.banner_pool(banner_id)
	# Todo el pool del banner en manos del jugador y ya en su forma superior (LR).
	for id in pool:
		_own(String(id), "LR", 0)
	var roster_before := GameState.roster.size()
	var dups_before := {}
	for id in pool:
		dups_before[String(id)] = GameState.duplicates_of(String(id))
	GameState.gems = 100000
	var results := 0
	var all_base := true
	var any_wrong := false
	for round in 3:
		var report := GameState.summon(banner_id, 10, false)
		for entry in report.get("results", []):
			results += 1
			var id := String((entry as Dictionary)["id"])
			if String((entry as Dictionary)["rarity"]) != GameState.base_rarity_of(id):
				all_base = false
			if bool((entry as Dictionary).get("new", false)):
				any_wrong = true
	var dups_after := 0
	var units_kept := true
	for id in pool:
		dups_after += GameState.duplicates_of(String(id)) - int(dups_before[String(id)])
		if GameState.rarity_of(String(id)) != "LR":
			units_kept = false
	_check("30 tiradas: cada resultado se entrega en su calidad inicial (la del banner), no en LR", results == 30 and all_base)
	_check("ninguna tirada crea una unidad nueva ni cambia el roster", not any_wrong and GameState.roster.size() == roster_before)
	_check("las unidades LR existentes no se modifican", units_kept)
	_check("las 30 copias quedan contadas como material (ni mas ni menos)", dups_after == 30)
	for id in pool:
		_own(String(id), "", 0)


## --- Guardado ------------------------------------------------------------------------

func _check_save_load() -> void:
	_out("[DBG21] == GUARDAR Y CARGAR ==")
	_own(GOJO, "UR", 5, 2)
	_own(DUO, "LR", 3, 1)
	GameState.save_game()
	# Estado FANTASMA en memoria que el archivo no tiene: tras cargar NO debe sobrevivir.
	GameState.duplicates[OTHER] = 7
	GameState.duplicates[GOJO] = 99
	GameState.rarities[OTHER] = "LR"
	GameState.dupe_levels[GOJO] = 5
	GameState.load_game()
	_check("cargar restaura las copias y los Dupes aplicados exactos", GameState.duplicates_of(GOJO) == 5 and GameState.dupe_level_of(GOJO) == 2 and GameState.dupe_copies_available(GOJO) == 3)
	_check("cargar restaura David & Lucy LR con su copia (3 - 1 gastada = 2)", GameState.rarity_of(DUO) == "LR" and GameState.dupe_level_of(DUO) == 1 and GameState.dupe_copies_available(DUO) == 2)
	_check("no reaparecen copias fantasma que el archivo no tenia", GameState.duplicates_of(OTHER) == 0 and not GameState.rarities.has(OTHER))
	# Consumir, guardar y recargar: el consumo no se deshace al reiniciar.
	GameState.dupe_upgrade(DUO)
	GameState.save_game()
	GameState.duplicates = {}
	GameState.dupe_levels = {}
	GameState.rarities = {}
	GameState.load_game()
	_check("una copia consumida NO reaparece tras reiniciar", GameState.dupe_level_of(DUO) == 2 and GameState.dupe_copies_available(DUO) == 1 and GameState.rarity_of(DUO) == "LR")
	GameState.load_game()
	GameState.load_game()
	_check("cargar varias veces no cambia nada", GameState.dupe_level_of(DUO) == 2 and GameState.dupe_copies_available(DUO) == 1 and GameState.duplicates_of(GOJO) == 5)
	# Un guardado con copias de un id que no esta en el roster no crea copias.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	# OTHER no esta en el roster (se le quita antes de guardar): sus copias en el archivo
	# no pueden dar copias reales.
	GameState.roster.erase(OTHER)
	GameState.save_game()
	parsed = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	(parsed as Dictionary)["duplicates"]["fantasma_no_en_roster"] = 4
	(parsed as Dictionary)["duplicates"][OTHER] = 6
	(parsed as Dictionary)["duplicates"][GOJO] = -3
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(parsed))
	f.close()
	GameState.load_game()
	_check("ids que no estan en el roster y cuentas negativas no producen copias", GameState.duplicates_of("fantasma_no_en_roster") == 0 and GameState.duplicates_of(OTHER) == 0 and GameState.duplicates_of(GOJO) >= GameState.dupe_level_of(GOJO))
	_own(GOJO, "", 0)
	_own(DUO, "", 0)


func _check_old_save() -> void:
	_out("[DBG21] == COMPATIBILIDAD CON PARTIDAS ANTERIORES ==")
	_own(GOJO, "UR", 4, 0)
	GameState.save_game()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	(parsed as Dictionary).erase("dupe_levels")
	(parsed as Dictionary)["version"] = 2
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(parsed))
	f.close()
	GameState.load_game()
	_check("una partida v2 sin dupe_levels carga: sus duplicados pasan a ser copias y Gojo sigue UR", GameState.duplicates_of(GOJO) == 4 and GameState.dupe_level_of(GOJO) == 0 and GameState.dupe_copies_available(GOJO) == 4 and GameState.rarity_of(GOJO) == "UR")
	var stack := _stack_of(GOJO)
	_check("esas copias se muestran como pila SSR x4 aparte de la unidad UR", not stack.is_empty() and int(stack["count"]) == 4 and String(stack["quality"]) == "SSR" and not bool(stack["merged"]))
	_own(GOJO, "", 0)


func _check_evolution_keeps_copies() -> void:
	_out("[DBG21] == EVOLUCIONAR CON COPIAS ==")
	_own(GOJO, "", 2)
	GameState.progress[GOJO] = { "level": 100, "xp": 0 }
	GameState.coins = 1000000
	var before := _stack_of(GOJO)
	_check("antes de evolucionar la pila SSR x2 va dentro de la carta de la unidad SSR", not before.is_empty() and bool(before["merged"]) and int(before["count"]) == 2)
	var evo := GameState.evolve(GOJO)
	_check("Gojo evoluciona a UR", not evo.is_empty() and GameState.rarity_of(GOJO) == "UR")
	var after := _stack_of(GOJO)
	_check("tras evolucionar las 2 copias siguen siendo SSR y ahora forman una pila aparte (sin perder ni duplicar)", not after.is_empty() and int(after["count"]) == 2 and String(after["quality"]) == "SSR" and not bool(after["merged"]) and GameState.duplicates_of(GOJO) == 2)
	_own(GOJO, "", 0)
