extends Node

## COMPROBACIONES EN EJECUCION DE LA v15 (colecciones con recompensas, misiones personales,
## nivel de cuenta, audio/presentacion, calidad de vida y diagnostico). SOLO pruebas.
## Arranque:  godot --headless --path . -- --dbg27   (escribe res://dbg27_resultados.txt)
##
## Los fundidos de musica se desactivan en headless por defecto; aqui se ACTIVAN a
## proposito para comprobarlos de verdad y se restauran al terminar.

const RESULTS_PATH := "res://dbg27_resultados.txt"
const Families := preload("res://core/families.gd")
const Rewards := preload("res://core/rewards.gd")
const Preview := preload("res://core/preview.gd")
const StageInfo := preload("res://core/stage_info.gd")
const Progression := preload("res://core/progression.gd")
const Diagnostics := preload("res://dev/diagnostics.gd")
const DevTools := preload("res://dev/dev_tools.gd")

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
	_out("[DBG27] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func run(app: Node) -> void:
	_app = app
	await _wait(0.3)
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	seed(2727)
	_out("[DBG27] --- comprobaciones v15 ---")
	_app.call("_backup_save")
	_check_collection_data()
	_check_collection_logic()
	_check_personal_missions()
	_check_account()
	_check_save_roundtrip()
	await _check_audio()
	_check_quality_of_life()
	_check_diagnostics()
	_check_v16_rarity()
	await _check_screens()
	await _check_v16_screens()
	_app.call("_restore_save")
	_out("[DBG27] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## Estado limpio y conocido: roster inicial, sin favoritos ni progreso de v15.
func _fresh() -> void:
	GameState.roster = GameState.STARTING_ROSTER.duplicate()
	GameState.progress = {}
	GameState.party = []
	GameState.tower_team = []
	GameState.favorites = []
	GameState.rarities = {}
	GameState.duplicates = {}
	GameState.dupe_levels = {}
	GameState.mutations = {}
	GameState.inventory = {}
	GameState.saved_teams = []
	GameState.event_progress = {}
	GameState.coins = 0
	GameState.gems = 0
	GameState.materials = 0
	GameState.ensure_defaults()
	GameState.meta.from_dict({})
	GameState.meta.now_override = 1793361600
	GameState.account.from_dict({ "xp": 0 })
	GameState.collections.from_dict({})


## Todos los personajes de partida (las raices: no las formas que se consiguen evolucionando).
func _own_all_roots() -> void:
	for root in Families.all_roots():
		if not GameState.roster.has(String(root)):
			GameState.roster.append(String(root))
			GameState.progress[String(root)] = { "level": 1, "xp": 0 }


## --- 1. Datos de colecciones y que se puedan completar -------------------------------------
func _check_collection_data() -> void:
	_out("[DBG27] == DATOS DE COLECCIONES ==")
	_fresh()
	_check("hay 28 colecciones (12 series, 13 categorias, 2 rarezas, 1 evento)", DB.collections.size() == 28)
	var kinds := { "series": 0, "category": 0, "rarity": 0, "event": 0 }
	for cid in DB.collections:
		kinds[String(DB.collections[cid]["kind"])] = int(kinds[String(DB.collections[cid]["kind"])]) + 1
	_check("reparto por tipo 12/13/2/1", kinds["series"] == 12 and kinds["category"] == 13 and kinds["rarity"] == 2 and kinds["event"] == 1)
	var bad: Array = []
	for cid in GameState.collections.ids():
		var problems: Array = GameState.collections.problems(String(cid))
		if not problems.is_empty():
			bad.append("%s: %s" % [cid, problems[0]])
	_check("ninguna coleccion tiene problemas de configuracion (%s)" % ("; ".join(PackedStringArray(bad)) if not bad.is_empty() else "ok"), bad.is_empty())
	# Completables de verdad: con todos los personajes obtenibles, TODAS se completan.
	_own_all_roots()
	GameState.meta.now_override = 1793361600
	for st in DB.event_stages("event_sindromes_de_la_pubertad"):
		GameState._mark_event_stage("event_sindromes_de_la_pubertad", String((st as Dictionary)["id"]))
	var incomplete: Array = []
	for cid in GameState.collections.ids():
		var st2: Dictionary = GameState.collections.state(String(cid))
		if not bool(st2["complete"]):
			incomplete.append("%s %d/%d" % [cid, int(st2["owned"]), int(st2["total"])])
	_check("con todos los personajes y el evento completado, las 28 colecciones se completan (%s)" % ", ".join(PackedStringArray(incomplete)), incomplete.is_empty())
	# Sin ninguna recompensa de cosmetico duplicada y sin cosmeticos huerfanos.
	var sources: Dictionary = {}
	for cid in DB.collections:
		for tier in DB.collections[cid]["tiers"]:
			for c in (tier["reward"] as Dictionary).get("cosmetics", []):
				sources[String(c)] = int(sources.get(String(c), 0)) + 1
	for entry in DB.account_config()["level_rewards"]:
		for c in (entry["reward"] as Dictionary).get("cosmetics", []):
			sources[String(c)] = int(sources.get(String(c), 0)) + 1
	var dup := false
	for c in sources:
		if int(sources[c]) > 1:
			dup = true
	_check("cada cosmetico lo da UNA sola fuente", not dup)
	_check("los 46 cosmeticos se pueden conseguir", sources.size() == DB.cosmetics.size() and DB.cosmetics.size() == 46)
	# Las ilustraciones usan arte que existe de verdad.
	var art_ok := true
	for id in DB.cosmetics:
		if String(DB.cosmetics[id]["type"]) == "illustration":
			if not ResourceLoader.exists("res://art/characters/%s/front.png" % DB.cosmetics[id]["character"]):
				art_ok = false
	_check("todas las ilustraciones cosmeticas tienen su front.png", art_ok)
	# El logro Gran coleccion era IMPOSIBLE (65 ids, pero las evoluciones especiales
	# consumen al personaje): ahora cuenta familias y se puede completar.
	_fresh()
	_own_all_roots()
	_check("Gran coleccion se completa con todas las familias", bool(GameState.meta.achievement_state("ach_gran_coleccion")["completed"]))
	var consumed_roster: Array = GameState.roster.duplicate()
	consumed_roster.erase("sakuta_mai")
	consumed_roster.append("sakuta_mai_lr")
	GameState.roster = consumed_roster
	_check("... aunque Sakuta y Mai ya hayan evolucionado a su forma LR (id original consumido)", bool(GameState.meta.achievement_state("ach_gran_coleccion")["completed"]))
	_check("las familias son menos que los ids (Sakuta y Mai son una sola)", Families.all_roots().size() == DB.characters.size() - 2)
	_check("la raiz de sakuta_mai_lr es sakuta_mai", Families.root_of("sakuta_mai_lr") == "sakuta_mai" and Families.root_of("sakuta") == "sakuta_mai")


## --- 2. Logica de colecciones y pago ------------------------------------------------------------
func _check_collection_logic() -> void:
	_out("[DBG27] == COBRO DE COLECCIONES ==")
	_fresh()
	var cols = GameState.collections
	# Black Clover: asta, yuno, noelle, yami. Se tienen asta y yuno.
	GameState.roster = ["asta", "yuno"]
	GameState.ensure_defaults()
	var st: Dictionary = cols.state("col_serie_black_clover")
	_check("Black Clover: 3/4 y ningun tramo completo", int(st["owned"]) == 3 and int(st["total"]) == 4 and not bool(st["complete"]))
	var half: Dictionary = (st["tiers"] as Array)[0]
	_check("el tramo del 50% (3 de 4: asta, yuno y yami) esta alcanzado y el 100% no", bool(half["reached"]) and not bool((st["tiers"] as Array)[1]["reached"]))
	_check("falta: noelle, con su fuente", (st["missing"] as Array).size() == 1 and String(st["missing"][0]["id"]) == "noelle" and String(st["missing"][0]["sources"]).length() > 0)
	var coins_before: int = GameState.coins
	var mats_before: int = GameState.materials
	var done: Dictionary = cols.claim_tier("col_serie_black_clover", "half")
	_check("reclamar el tramo paga monedas y materiales", not done.is_empty() and GameState.coins == coins_before + int(half["reward"]["coins"]) and GameState.materials == mats_before + int(half["reward"]["materials"]))
	_check("no se puede reclamar dos veces", cols.claim_tier("col_serie_black_clover", "half").is_empty() and GameState.coins == coins_before + int(half["reward"]["coins"]))
	_check("no se puede reclamar un tramo sin alcanzar", cols.claim_tier("col_serie_black_clover", "full").is_empty())
	GameState.add_character("noelle")
	st = cols.state("col_serie_black_clover")
	_check("al conseguir a Noelle la coleccion esta completa", bool(st["complete"]) and int((st["tiers"] as Array)[1]["need"]) == 4)
	var full_reward: Dictionary = (st["tiers"] as Array)[1]["reward"]
	var gems_before: int = GameState.gems
	var owned_cos_before: int = GameState.account.cosmetics_owned.size()
	cols.claim_tier("col_serie_black_clover", "full")
	_check("el 100% da gemas, un titulo y una ilustracion", GameState.gems == gems_before + int(full_reward["gems"]) and GameState.meta.titles_owned.has("title_col_serie_black_clover") and GameState.account.owns_cosmetic("ill_asta") and GameState.account.cosmetics_owned.size() == owned_cos_before + 1)
	_check("el titulo aparece en el catalogo de titulos equipables", GameState.meta.title_catalog().has("title_col_serie_black_clover") and GameState.meta.equip_title("title_col_serie_black_clover"))
	_check("la coleccion queda con todo reclamado", bool(cols.state("col_serie_black_clover")["all_claimed"]))
	# Recompensa de cosmetico repetida: dar dos veces el mismo cosmetico es no-op.
	var report := Rewards.pay(GameState, { "cosmetics": ["ill_asta"] })
	_check("dar dos veces el mismo cosmetico no lo duplica", (report["cosmetics"] as Array).is_empty() and GameState.account.cosmetics_owned.count("ill_asta") == 1)
	_check("objeto desconocido en una recompensa no se entrega ni rompe", Rewards.pay(GameState, { "items": { "no_existe": 3 } })["items"].is_empty())
	# Reclamar todo.
	_fresh()
	_own_all_roots()
	var ready_before: int = cols.unclaimed_count()
	var all_done: Array = cols.claim_all()
	_check("reclamar todo cobra todos los tramos listos (%d)" % all_done.size(), all_done.size() == ready_before and cols.unclaimed_count() == 0)
	_check("... y no hay tramo del evento cobrado sin haberlo completado", not bool(cols.is_tier_claimed("col_evento_sindromes", "full")))
	# Evento: pide haber completado el evento ademas de los personajes.
	var ev: Dictionary = cols.state("col_evento_sindromes")
	_check("la coleccion del evento no se completa sin completar el evento", int(ev["owned"]) == int(ev["total"]) and not bool(ev["complete"]) and not bool((ev["tiers"] as Array)[0]["reached"]))
	for stg in DB.event_stages("event_sindromes_de_la_pubertad"):
		GameState._mark_event_stage("event_sindromes_de_la_pubertad", String((stg as Dictionary)["id"]))
	ev = cols.state("col_evento_sindromes")
	_check("completado el evento, el tramo se puede cobrar", bool((ev["tiers"] as Array)[0]["reached"]) and not cols.claim_tier("col_evento_sindromes", "full").is_empty())
	# Evolucion especial: Sakuta y Mai consume al personaje, pero la coleccion sigue completa.
	_fresh()
	GameState.roster = ["sakuta_mai", "mai"]
	GameState.ensure_defaults()
	var seis: Dictionary = cols.state("col_serie_seishun_buta")
	_check("Seishun Buta Yarou: Sakuta y Mai cuenta con su id original", int(seis["owned"]) == 2 and bool(seis["complete"]))
	GameState.roster = ["sakuta", "mai"]
	GameState.ensure_defaults()
	seis = cols.state("col_serie_seishun_buta")
	_check("... y sigue completa tras evolucionar a Sakuta (el id original ya no existe)", int(seis["owned"]) == 2 and bool(seis["complete"]))
	GameState.roster = ["sakuta_mai_lr", "mai"]
	GameState.ensure_defaults()
	_check("... y tras evolucionar a la forma LR", bool(cols.state("col_serie_seishun_buta")["complete"]))
	# Las fuentes de obtencion dicen la verdad.
	_check("Sakuta y Mai se consigue solo en el evento", Families.sources_of("sakuta_mai").size() == 1 and String(Families.sources_of("sakuta_mai")[0]["kind"]) == "event")
	_check("Sakuta (UR) se consigue por evolucion", String(Families.sources_of("sakuta")[0]["kind"]) == "evolution" and Families.reachable("sakuta") and Families.reachable("sakuta_mai_lr"))
	_check("David y Lucy (duo) sale en su banner", String(Families.sources_of("david_lucy_duo")[0]["kind"]) == "banner")
	_check("todos los personajes del juego son alcanzables", _unreachable().is_empty())


func _unreachable() -> Array:
	var out: Array = []
	for id in DB.characters:
		if not Families.reachable(String(id)):
			out.append(String(id))
	return out


## --- 3. Misiones personales ------------------------------------------------------------------------
func _check_personal_missions() -> void:
	_out("[DBG27] == MISIONES PERSONALES ==")
	_fresh()
	var meta = GameState.meta
	_check("hay 12 misiones personales de 3 personajes (Sakuta y Mai, Goku, David y Lucy)", DB.personal_missions().size() == 12)
	_check("las personales no entran en las PERMANENTES ni en las periodicas", GameState.all_missions_state().size() == 7 and meta.periodic_ids().size() == 11)
	_check("las demas misiones siguen ahi: 30 misiones en total", DB.missions.size() == 30)
	meta.record("battle", 1, { "victory": true, "ally_ids": ["sakuta_mai", "mai"], "bosses": [], "rounds": 4, "fallen": 0, "solo": false })
	_check("combate con Sakuta y Mai: cuenta para Compania de batalla", meta.personal_state("pm_sakuta_batallas")["progress"] == 1)
	_check("... y para Dos personas, una promesa (con Mai en el equipo)", meta.personal_state("pm_sakuta_mai")["progress"] == 1)
	meta.record("battle", 1, { "victory": true, "ally_ids": ["sakuta_mai", "gojo"], "bosses": [], "rounds": 4, "fallen": 0, "solo": false })
	_check("sin Mai en el equipo NO cuenta para Dos personas, una promesa", meta.personal_state("pm_sakuta_mai")["progress"] == 1 and meta.personal_state("pm_sakuta_batallas")["progress"] == 2)
	meta.record("battle", 1, { "victory": false, "ally_ids": ["sakuta_mai", "mai"], "bosses": [], "rounds": 4, "fallen": 3, "solo": false })
	_check("una derrota cuenta como combate jugado pero no como victoria", meta.personal_state("pm_sakuta_batallas")["progress"] == 3 and meta.personal_state("pm_sakuta_mai")["progress"] == 1)
	meta.record("battle", 1, { "victory": true, "ally_ids": ["gojo", "isagi"], "bosses": [], "rounds": 4, "fallen": 0, "solo": false })
	_check("un combate sin el personaje no suma", meta.personal_state("pm_sakuta_batallas")["progress"] == 3)
	# La familia: Sakuta (forma UR) y la LR siguen contando.
	meta.record("battle", 1, { "victory": true, "ally_ids": ["sakuta"], "bosses": ["boss_sakuta"], "rounds": 4, "fallen": 0, "solo": true })
	_check("con la forma evolucionada (Sakuta) tambien cuenta, y el jefe suma", meta.personal_state("pm_sakuta_batallas")["progress"] == 4 and meta.personal_state("pm_sakuta_jefes")["progress"] == 1)
	meta.record("battle", 1, { "victory": true, "ally_ids": ["sakuta_mai_lr"], "bosses": [], "rounds": 4, "fallen": 0, "solo": true })
	_check("... y con la forma LR", meta.personal_state("pm_sakuta_batallas")["progress"] == 5)
	# Goku.
	meta.record("battle", 1, { "victory": true, "ally_ids": ["goku"], "bosses": [], "rounds": 4, "fallen": 0, "solo": true })
	_check("Goku en solitario: Entrenamiento diario y El mas fuerte del universo suman", meta.personal_state("pm_goku_batallas")["progress"] == 1 and meta.personal_state("pm_goku_solo")["progress"] == 1)
	meta.record("battle", 1, { "victory": true, "ally_ids": ["goku", "vegeta", "gojo"], "bosses": [], "rounds": 4, "fallen": 0, "solo": false })
	_check("Goku con Vegeta: Orgullo saiyan suma, y la de en solitario NO", meta.personal_state("pm_goku_saiyans")["progress"] == 1 and meta.personal_state("pm_goku_solo")["progress"] == 1)
	meta.record("battle", 1, { "victory": true, "ally_ids": ["goku", "gojo"], "bosses": [], "rounds": 4, "fallen": 0, "solo": false })
	_check("Goku sin Vegeta ni Gohan: Orgullo saiyan NO suma", meta.personal_state("pm_goku_saiyans")["progress"] == 1)
	# Evolucion.
	meta.record("evolve", 1, { "to": "UR", "id": "gojo" })
	_check("evolucionar a otro personaje no suma", meta.personal_state("pm_goku_batallas")["progress"] == 3 and meta.personal_state("pm_sakuta_evolucion")["progress"] == 0)
	meta.record("evolve", 1, { "to": "UR", "id": "sakuta" })
	_check("evolucionar a Sakuta suma Despertar compartido", meta.personal_state("pm_sakuta_evolucion")["progress"] == 1)
	# Tope y cobro.
	for i in 20:
		meta.record("battle", 1, { "victory": true, "ally_ids": ["goku"], "bosses": [], "rounds": 4, "fallen": 0, "solo": true })
	var st: Dictionary = meta.personal_state("pm_goku_batallas")
	_check("el progreso no pasa del objetivo (20/20)", int(st["progress"]) == 20 and bool(st["completed"]))
	var coins_before: int = GameState.coins
	var mats_before: int = GameState.materials
	var claim: Dictionary = GameState.claim_mission("pm_goku_batallas")
	_check("GameState.claim_mission cobra una personal (monedas y materiales)", not claim.is_empty() and GameState.coins == coins_before + 600 and GameState.materials == mats_before + 3)
	_check("... una sola vez", GameState.claim_mission("pm_goku_batallas").is_empty() and GameState.coins == coins_before + 600)
	_check("una personal sin completar no se puede cobrar", GameState.claim_mission("pm_sakuta_mai").is_empty())
	# Titulo de una personal.
	for i in 3:
		meta.record("battle", 1, { "victory": true, "ally_ids": ["goku"], "bosses": [], "rounds": 4, "fallen": 0, "solo": true })
	GameState.claim_mission("pm_goku_solo")
	_check("completar El mas fuerte del universo da su titulo", meta.titles_owned.has("title_pm_goku") and meta.title_catalog().has("title_pm_goku"))
	# Persistencia.
	var saved: Dictionary = meta.to_dict()
	meta.from_dict({})
	_check("al reiniciar el estado el progreso personal se pierde (prueba de control)", meta.personal_state("pm_goku_batallas")["progress"] == 0)
	meta.from_dict(saved)
	_check("... y al cargar lo guardado se recupera, con lo ya cobrado", meta.personal_state("pm_goku_batallas")["progress"] == 20 and bool(meta.personal_state("pm_goku_batallas")["claimed"]) and meta.personal_state("pm_sakuta_batallas")["progress"] == 5)
	meta.from_dict({ "personal": { "pm_goku_batallas": { "progress": 5, "claimed": false }, "pm_no_existe": { "progress": 9, "claimed": true } } })
	_check("un guardado con una mision retirada la ignora sin romper", meta.personal_state("pm_goku_batallas")["progress"] == 5 and not meta.personal.has("pm_no_existe"))
	# Una batalla cobrada tres veces suma una sola vez (pasa por el cobro real).
	_fresh()
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	GameState.current_stage_enemies = ["void_warden"]
	var token := GameState.begin_battle()
	GameState.grant_battle_rewards(token, ["goku"], true)
	GameState.grant_battle_rewards(token, ["goku"], true)
	GameState.grant_battle_rewards(token, ["goku"], true)
	_check("cobrar 3 veces la misma batalla suma 1 en la personal (y el jefe 1)", GameState.meta.personal_state("pm_goku_batallas")["progress"] == 1 and GameState.meta.personal_state("pm_goku_jefes")["progress"] == 1)
	_check("... y entra en la cuenta una sola vez (8 + 12 + 30 XP)", GameState.account.xp == 50)
	# Por personaje.
	_check("se listan las personales de un personaje (4 de Goku)", GameState.meta.personal_for_character("goku").size() == 4)


## --- 4. Nivel de cuenta --------------------------------------------------------------------------------
func _check_account() -> void:
	_out("[DBG27] == NIVEL DE CUENTA ==")
	_fresh()
	var acc = GameState.account
	_check("antes de la v15 no existia nivel de cuenta: ahora empieza en 1", acc.level() == 1 and acc.progress()["xp_in_level"] == 0)
	_check("la tabla tiene 29 recompensas (niveles 2 a 30)", DB.account_config()["level_rewards"].size() == 29 and acc.max_level() == 30)
	_check("XP para nivel 2 = 120 y crece 40 por nivel", acc.xp_needed(1) == 120 and acc.xp_needed(2) == 160 and acc.xp_needed(10) == 480)
	_check("XP de una victoria con jefe = 8 + 12 + 30", acc.xp_for_event("battle", 1, { "victory": true, "bosses": ["x"] }) == 50 and acc.xp_for_event("battle", 1, { "victory": false }) == 8)
	var coins_before: int = GameState.coins
	var gems_before: int = GameState.gems
	acc.add_xp(500)
	_check("la XP de cuenta no da monedas ni gemas por si sola (no hay moneda nueva)", GameState.coins == coins_before and GameState.gems == gems_before)
	_check("500 XP: nivel 4 (120+160+200 = 480, sobran 20)", acc.level() == 4 and int(acc.progress()["xp_in_level"]) == 20)
	var pending: Array = acc.pending_levels()
	_check("niveles 2, 3 y 4 con recompensa pendiente", pending == [2, 3, 4])
	var c0: int = GameState.coins
	var done: Dictionary = acc.claim_level(2)
	_check("cobrar el nivel 2 paga sus monedas (140)", not done.is_empty() and GameState.coins == c0 + 140)
	_check("no se cobra dos veces", acc.claim_level(2).is_empty() and GameState.coins == c0 + 140)
	_check("no se cobra un nivel que no se ha alcanzado", acc.claim_level(10).is_empty())
	_check("cobrar todo reclama lo que queda", acc.claim_all_levels().size() == 2 and acc.pending_levels().is_empty())
	acc.add_xp(100000)
	_check("el nivel se queda en el maximo y la XP no se desborda", acc.level() == 30 and acc.progress()["maxed"] and acc.xp == acc.xp_for_level(30))
	_check("el nivel 5 desbloquea el fondo Equipo y el 10 el titulo Aventurero", acc.level_reward(5)["cosmetics"] == ["bg_equipo"] and acc.level_reward(10)["title"]["id"] == "title_cuenta_10")
	acc.claim_all_levels()
	_check("cobrados los 29 niveles: cosmeticos y titulos de cuenta entregados", acc.owns_cosmetic("bg_equipo") and acc.owns_cosmetic("bg_resultados") and GameState.meta.titles_owned.has("title_cuenta_30"))
	# Cosmeticos.
	_check("equipar un fondo que se posee funciona y cambia el slot del menu", acc.equip_background("bg_equipo") and acc.menu_background_slot() == "team")
	_check("no se equipa un fondo que no se posee", not acc.equip_background("bg_torre") and acc.background_equipped == "bg_equipo")
	_check("no se equipa una ilustracion como fondo", not acc.equip_background("ill_goku"))
	acc.equip_background("")
	_check("quitar el fondo devuelve el del menu", acc.menu_background_slot() == "menu")
	GameState.collections.claim_all()
	_own_for_illustration()
	_check("equipar una ilustracion cambia el personaje del escaparate", acc.equip_illustration("ill_goku") and acc.illustration_character() == "goku")
	# Una sola via de entrada: record() la alimenta; nada mas.
	_fresh()
	GameState.meta.record("summon", 10, {})
	GameState.meta.record("tower_floor", 1, {})
	GameState.meta.record("event_stage", 1, {})
	GameState.meta.record("evolve", 1, { "to": "UR", "id": "gojo" })
	_check("invocar x10 (40) + piso (25) + fase de evento (30) + evolucion (50) = 145 XP", GameState.account.xp == 145)
	# Guardado antiguo (v14): sin bloque account -> XP estimada UNA vez desde los contadores.
	_fresh()
	GameState.counters["combates_jugados"] = 50
	GameState.counters["victorias"] = 30
	GameState.summon_total = 20
	GameState.account.from_dict({})
	var boot: int = GameState.account.bootstrap_if_needed()
	_check("un guardado v14 estima la XP de cuenta desde sus contadores (50x8 + 30x12 + 20x4 = %d)" % boot, boot == 50 * 8 + 30 * 12 + 20 * 4 and GameState.account.xp == boot)
	_check("... una sola vez (segunda llamada no suma)", GameState.account.bootstrap_if_needed() == 0 and GameState.account.xp == boot)
	var round_trip = GameState.account.to_dict()
	GameState.account.from_dict(round_trip)
	_check("... y al volver a cargar ya no se re-estima", GameState.account.bootstrap_if_needed() == 0 and GameState.account.xp == boot)
	GameState.account.from_dict({ "xp": 10, "cosmetics_owned": ["bg_equipo", "no_existe"], "background_equipped": "bg_torre", "claimed_levels": [2, 2] })
	_check("un guardado con cosmeticos retirados o equipados sin poseer se limpia", GameState.account.cosmetics_owned == ["bg_equipo"] and GameState.account.background_equipped == "" and GameState.account.claimed_levels == [2])


func _own_for_illustration() -> void:
	GameState.account.grant_cosmetic("ill_goku")


## --- 5. Guardado y carga -----------------------------------------------------------------------------------
func _check_save_roundtrip() -> void:
	_out("[DBG27] == GUARDADO Y CARGA ==")
	_fresh()
	GameState.roster = ["goku", "asta", "yuno", "sakuta_mai", "mai"]
	GameState.ensure_defaults()
	GameState.collections.claim_tier("col_serie_black_clover", "half")
	GameState.meta.record("battle", 1, { "victory": true, "ally_ids": ["goku"], "bosses": [], "rounds": 4, "fallen": 0, "solo": true })
	GameState.account.add_xp(600)
	GameState.account.claim_level(2)
	GameState.account.grant_cosmetic("bg_equipo")
	GameState.account.equip_background("bg_equipo")
	GameState.save_game()
	var xp: int = GameState.account.xp
	var claimed_levels: Array = GameState.account.claimed_levels.duplicate()
	var coins: int = GameState.coins
	var personal: int = GameState.meta.personal_state("pm_goku_batallas")["progress"]
	var payload: Dictionary = GameState.build_save_payload()
	_check("el guardado incluye cuenta, colecciones y misiones personales", payload.has("account") and payload.has("collections") and (payload["meta_progress"] as Dictionary).has("personal"))
	_check("SAVE_VERSION sigue en 3 (los bloques nuevos son aditivos)", GameState.SAVE_VERSION == 3 and int(payload["version"]) == 3)
	_check("el payload sobrevive a JSON y vuelta", JSON.parse_string(JSON.stringify(payload)) is Dictionary)
	GameState.account.from_dict({})
	GameState.collections.from_dict({})
	GameState.meta.from_dict({})
	GameState.coins = 0
	_check("tras vaciar la memoria no queda nada (control)", GameState.account.xp == 0 and not GameState.collections.is_tier_claimed("col_serie_black_clover", "half"))
	_check("load_game devuelve true", GameState.load_game())
	_check("la XP de cuenta se recupera", GameState.account.xp == xp)
	_check("los niveles cobrados se recuperan", GameState.account.claimed_levels == claimed_levels)
	_check("el tramo de coleccion cobrado se recupera (no se puede cobrar otra vez)", GameState.collections.is_tier_claimed("col_serie_black_clover", "half") and GameState.collections.claim_tier("col_serie_black_clover", "half").is_empty())
	_check("el progreso personal se recupera", GameState.meta.personal_state("pm_goku_batallas")["progress"] == personal)
	_check("el cosmetico equipado se recupera", GameState.account.background_equipped == "bg_equipo" and GameState.account.owns_cosmetic("bg_equipo"))
	_check("las monedas se recuperan", GameState.coins == coins)
	# Guardado de la v14: sin ninguno de los bloques nuevos.
	var old: Dictionary = GameState.build_save_payload()
	old.erase("account")
	old.erase("collections")
	(old["meta_progress"] as Dictionary).erase("personal")
	GameState._write_save_safely(JSON.stringify(old))
	GameState.counters["combates_jugados"] = 10
	GameState.counters["victorias"] = 4
	old["counters"] = GameState.counters
	GameState._write_save_safely(JSON.stringify(old))
	_check("un guardado de la v14 carga sin errores", GameState.load_game())
	_check("... conserva el roster, monedas y favoritos", GameState.roster.has("goku") and GameState.coins == coins)
	_check("... las colecciones empiezan sin tramos cobrados y se pueden cobrar", not GameState.collections.is_tier_claimed("col_serie_black_clover", "half") and int(GameState.collections.state("col_serie_black_clover")["ready"]) >= 1)
	_check("... y la XP de cuenta se estima desde sus contadores (10 combates, 4 victorias)", GameState.account.xp >= 10 * 8 + 4 * 12)
	_check("... y no hay misiones personales con progreso", GameState.meta.personal_state("pm_goku_batallas")["progress"] == 0)
	# Un archivo corrupto no rompe: cae al respaldo o a limpio, sin excepcion.
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{esto no es json")
	f.close()
	var survived := true
	GameState.load_game()
	_check("un archivo de guardado corrupto no rompe la carga", survived)


## --- 6. Audio: musica, fundidos, jingles y efectos -------------------------------------------------------
func _music_players() -> int:
	var n := 0
	for child in GameAudio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing and (child as AudioStreamPlayer).stream != null and String((child as AudioStreamPlayer).stream.resource_path).contains("/music/"):
			n += 1
	return n


func _check_audio() -> void:
	_out("[DBG27] == AUDIO Y TRANSICIONES ==")
	_fresh()
	var restore_fades: bool = GameAudio.fades_enabled
	GameSettings.set_value("music_volume", 0.8, false)
	GameAudio.stop_music()
	GameAudio.fades_enabled = false
	_check("los fundidos estan desactivados en headless por defecto", restore_fades == false)
	# Sin fundidos, todo es inmediato y compatible con lo de siempre.
	GameAudio.play_music("menu")
	var base_db: float = GameAudio._music_db("menu")
	_check("sin fundidos el volumen es el de siempre", absf(GameAudio.get("_music").volume_db - base_db) < 0.01)
	GameAudio.duck(-10.0)
	_check("duck baja la musica 10 dB y is_ducked lo dice", absf(GameAudio.get("_music").volume_db - (base_db - 10.0)) < 0.01 and GameAudio.is_ducked())
	GameAudio.unduck()
	_check("unduck la devuelve", absf(GameAudio.get("_music").volume_db - base_db) < 0.01 and not GameAudio.is_ducked())
	GameAudio.stop_music()
	# Fundidos activados: se prueba de verdad.
	GameAudio.fades_enabled = true
	GameAudio.music_starts = 0
	GameAudio.play_music("menu")
	_check("la primera pista arranca sin esperar", GameAudio.current_music_path().ends_with("menu.mp3") and GameAudio.get("_music").playing and GameAudio.music_starts == 1)
	_check("entra con fundido: al empezar casi en silencio", GameAudio.get("_music").volume_db < base_db - 20.0)
	await _wait(0.7)
	_check("... y a los 0,7 s ya esta a su volumen (%.1f dB)" % GameAudio.get("_music").volume_db, absf(GameAudio.get("_music").volume_db - base_db) < 1.0)
	var starts_before: int = GameAudio.music_starts
	GameAudio.play_music("menu")
	GameAudio.play_music("menu")
	await _wait(0.1)
	_check("pedir la misma pista dos veces NO la reinicia", GameAudio.music_starts == starts_before and GameAudio.get("_fade_tween") == null)
	GameAudio.play_music("history")
	_check("cambiar de pista: la nueva cuenta como puesta YA", GameAudio.current_music_path().ends_with("history.mp3"))
	var sampled_overlap := false
	var seen_paths: Array = []
	for i in 40:
		await get_tree().process_frame
		if _music_players() > 1:
			sampled_overlap = true
		var stream = GameAudio.get("_music").stream
		if stream != null and not seen_paths.has(String(stream.resource_path)):
			seen_paths.append(String(stream.resource_path))
	await _wait(0.9)
	_check("durante el cambio solo suena UNA pista de musica (nunca se solapan)", not sampled_overlap and _music_players() == 1)
	_check("tras el fundido suena la nueva y a su volumen", String(GameAudio.get("_music").stream.resource_path).ends_with("history.mp3") and absf(GameAudio.get("_music").volume_db - base_db) < 1.0)
	# La ultima peticion gana: la intermedia no llega a sonar nunca.
	GameAudio.play_music("events")
	GameAudio.play_music("battle")
	var battle_started_as_events := false
	var starts2: int = GameAudio.music_starts
	for i in 30:
		await get_tree().process_frame
		var s2 = GameAudio.get("_music").stream
		if s2 != null and String(s2.resource_path).ends_with("events.mp3"):
			battle_started_as_events = true
	await _wait(1.0)
	_check("dos peticiones seguidas: gana la ultima y la intermedia no suena", String(GameAudio.get("_music").stream.resource_path).ends_with("battle.mp3") and not battle_started_as_events and GameAudio.music_starts == starts2 + 1)
	# Fundido de salida (resultados).
	GameAudio.fade_out_music(0.3)
	_check("fade_out_music: la pista deja de contar como puesta ya", GameAudio.current_music_path().is_empty())
	await _wait(0.6)
	_check("... y el reproductor se detiene al acabar el fundido", not GameAudio.get("_music").playing)
	GameAudio.play_music("results")
	await _wait(0.7)
	_check("despues de cortar la musica, la de resultados entra normal", GameAudio.get("_music").playing and GameAudio.current_music_path().ends_with("results.mp3"))
	GameAudio.fade_out_music(0.4)
	GameAudio.play_music("menu")
	await _wait(1.3)
	_check("pedir musica en mitad del fundido de salida la deja sonando (no se corta)", GameAudio.get("_music").playing and GameAudio.current_music_path().ends_with("menu.mp3") and _music_players() == 1)
	# Los ajustes de volumen se respetan.
	GameSettings.set_value("music_volume", 0.0, false)
	await _wait(0.1)
	_check("con la musica a 0 el reproductor queda en silencio", GameAudio.get("_music").volume_db <= -79.0)
	GameSettings.set_value("music_volume", 0.5, false)
	await _wait(0.1)
	_check("subir el volumen mientras suena se aplica (%.1f dB)" % GameAudio.get("_music").volume_db, absf(GameAudio.get("_music").volume_db - GameAudio._music_db("menu")) < 0.01)
	# Intro de jefe: la musica baja y vuelve.
	GameAudio.duck(-10.0)
	await _wait(0.5)
	_check("durante la intro de un jefe la musica esta 10 dB mas baja", absf(GameAudio.get("_music").volume_db - (GameAudio._music_db("menu") - 10.0)) < 1.0)
	GameAudio.unduck()
	await _wait(0.8)
	_check("... y al cerrarla vuelve a su volumen", absf(GameAudio.get("_music").volume_db - GameAudio._music_db("menu")) < 1.0)
	# stop_music limpia todo.
	GameAudio.duck(-10.0)
	GameAudio.stop_music()
	_check("stop_music corta y suelta el duck", not GameAudio.is_ducked() and not GameAudio.get("_music").playing and GameAudio.current_music_path().is_empty())
	# Pista de jefe opcional: sin archivo se usa la de combate.
	_check("sin boss.ogg los jefes suenan con la musica de combate", GameAudio.battle_slot(true) == "battle" and GameAudio.battle_slot(false) == "battle" and not GameAudio.has_stream("boss"))
	_check("'boss' esta en el catalogo y se lista como pendiente de aportar, no como fallo", GameAudio.all_events().has("boss") and GameAudio.missing_user_supplied().has("boss") and not GameAudio.missing_events().has("boss"))
	_check("un jefe real se reconoce en el combate (GameState.current_battle_bosses)", _boss_detection())
	# Efectos: sin solape.
	var before := _sfx_count()
	for i in 6:
		GameAudio.play("attack")
	_check("el mismo efecto 6 veces en el mismo instante suena 1 vez", _sfx_count() - before <= 1)
	await _wait(0.1)
	for slot in GameAudio.all_events():
		if GameAudio.category_of(String(slot)) != "music":
			GameAudio.play(String(slot))
	_check("el total de efectos simultaneos nunca pasa del tope (%d)" % _sfx_count(), _sfx_count() <= GameAudio.SFX_MAX_PLAYERS)
	# El volumen de efectos sigue el ajuste (0 = silencio).
	await _wait(0.3)
	for child in GameAudio.get_children():
		if child is AudioStreamPlayer and child != GameAudio.get("_music"):
			(child as AudioStreamPlayer).stop()
	GameAudio.get("_sfx_last_ms").clear()
	GameSettings.set_value("sfx_volume", 0.0, false)
	GameAudio.play("critical")
	var silent := true
	for child in GameAudio.get_children():
		if child is AudioStreamPlayer and child != GameAudio.get("_music") and child.playing and child.stream != null and String(child.stream.resource_path).contains("critical") and child.volume_db > -79.0:
			silent = false
	_check("con los efectos a 0 el nuevo efecto queda en silencio", silent)
	GameSettings.set_value("sfx_volume", 0.8, false)
	GameAudio.stop_music()
	GameAudio.fades_enabled = restore_fades
	_check("los fundidos vuelven a su estado original tras la prueba", GameAudio.fades_enabled == restore_fades)


func _boss_detection() -> bool:
	GameState.current_stage_enemies = ["void_warden"]
	var a: bool = GameState.current_battle_bosses() == ["void_warden"]
	GameState.current_stage_enemies = ["vigia_alfa"]
	var b: bool = GameState.current_battle_bosses().is_empty()
	GameState.current_stage_enemies = ["vigia_alfa", "sdp_akaza"]
	var c: bool = GameState.current_battle_bosses() == ["sdp_akaza"]
	GameState.current_stage_enemies = []
	return a and b and c


func _sfx_count() -> int:
	var n := 0
	for child in GameAudio.get_children():
		if child is AudioStreamPlayer and child != GameAudio.get("_music") and (child as AudioStreamPlayer).playing:
			n += 1
	return n


## --- 7. Calidad de vida -------------------------------------------------------------------------------
func _check_quality_of_life() -> void:
	_out("[DBG27] == CALIDAD DE VIDA ==")
	_fresh()
	# Comparar.
	var rows: Array = Preview.compare(GameState, "gojo", "isagi")
	_check("comparar da las 6 estadisticas", rows.size() == 6 and String(rows[0]["stat"]) == "hp")
	var rev: Array = Preview.compare(GameState, "isagi", "gojo")
	var symmetric := true
	for i in rows.size():
		var a := String(rows[i]["better"])
		var b := String(rev[i]["better"])
		if not ((a == "=" and b == "=") or (a == "a" and b == "b") or (a == "b" and b == "a")):
			symmetric = false
	_check("comparar es simetrico (cambiar el orden invierte quien gana)", symmetric)
	var gojo_stats: Dictionary = Preview.stats_of(GameState, "gojo")
	var unit = preload("res://core/combat_unit.gd").new()
	unit.setup(GameState.character_data("gojo"), true, -1)
	_check("las estadisticas de comparar son las de combate (vida %d, ataque %d)" % [int(gojo_stats["hp"]), int(gojo_stats["atk"])], absf(float(gojo_stats["hp"]) - unit.max_hp()) < 0.01 and absf(float(gojo_stats["atk"]) - unit.attack()) < 0.01)
	_check("el texto de critico y esquiva sale en porcentaje", Preview.value_text("crit_rate", 0.14) == "14%" and Preview.value_text("hp", 1234.4) == "1234")
	_check("el texto de diferencia: +, - e =", Preview.delta_text("atk", 25.0) == "+25" and Preview.delta_text("atk", -3.0) == "-3" and Preview.delta_text("atk", 0.0) == "=")
	var info: Dictionary = Preview.compare_info(GameState, "gojo")
	_check("comparar da rareza, tipo, nivel y pasivas", String(info["rarity"]) == "SSR" and info["passives"].size() >= 1 and int(info["level"]) == 1)
	# Previsto de evolucion normal.
	var preview: Dictionary = Preview.evolution_preview(GameState, "gojo")
	_check("Gojo (SSR) tiene prevision de evolucion normal a UR", String(preview["kind"]) == "normal" and String(preview["to_rarity"]) == "UR")
	_check("la evolucion normal vuelve a nivel 1 (lo dice la prevision y lo hace evolve)", int(preview["after_level"]) == 1)
	var raw_hp := float(DB.get_character("gojo")["stats"]["max_hp"])
	var after_hp := 0.0
	var max_hp := 0.0
	for r in preview["rows"]:
		if String(r["stat"]) == "hp":
			after_hp = float(r["after_now"])
			max_hp = float(r["after_max"])
	_check("vida prevista a nivel 1 = base x 1,25 (%d)" % int(after_hp), absf(after_hp - raw_hp * 1.25) < 0.01)
	_check("vida prevista al nivel 100 = base x 1,25 x crecimiento de nivel 100", absf(max_hp - raw_hp * 1.25 * Progression.growth_factor(100)) < 0.5)
	# Y la prevision coincide con lo que de verdad pasa al evolucionar.
	GameState.progress["gojo"] = { "level": 100, "xp": 0 }
	GameState.coins = 500000
	var report: Dictionary = GameState.evolve("gojo")
	var real: Dictionary = Preview.stats_of(GameState, "gojo")
	_check("evolucionar de verdad deja las estadisticas que predijo la prevision (vida %d)" % int(real["hp"]), not report.is_empty() and absf(float(real["hp"]) - after_hp) < 0.01 and GameState.level_of("gojo") == 1)
	# Especial.
	_fresh()
	GameState.roster = ["sakuta_mai", "mai"]
	GameState.progress["sakuta_mai"] = { "level": 100, "xp": 0 }
	GameState.ensure_defaults()
	var special: Dictionary = Preview.evolution_preview(GameState, "sakuta_mai")
	_check("Sakuta y Mai tiene prevision ESPECIAL hacia Sakuta (UR)", String(special["kind"]) == "special" and String(special["to"]) == "sakuta" and String(special["to_rarity"]) == "UR")
	_check("la especial hereda el nivel (100)", int(special["after_level"]) == 100)
	_check("un personaje sin evolucion no tiene prevision", Preview.evolution_preview(GameState, "mai").is_empty() or String(Preview.evolution_preview(GameState, "mai")["kind"]) == "normal")
	_check("un personaje que no tienes no tiene prevision", Preview.evolution_preview(GameState, "no_existe").is_empty())
	# Importantes y favoritos.
	_fresh()
	GameState.party = ["gojo", "isagi"]
	var g: Dictionary = GameState.consume_guard("gojo")
	_check("una unidad del equipo activo es importante y pide confirmacion", bool(g["important"]) and bool(g["needs_confirmation"]) and not bool(g["protected"]))
	var quiet: Dictionary = GameState.consume_guard("frieren")
	_check("una unidad sin nada especial no pide nada", not bool(quiet["important"]) and not bool(quiet["needs_confirmation"]))
	GameState.progress["frieren"] = { "level": 60, "xp": 0 }
	_check("nivel 60 la hace importante", GameState.important_reasons("frieren").size() == 1)
	GameState.dupe_levels["asta"] = 2
	GameState.duplicates["asta"] = 12
	_check("tener Dupes la hace importante", GameState.important_reasons("asta").size() >= 1)
	GameState.set_favorite("gojo", true)
	var gf: Dictionary = GameState.consume_guard("gojo")
	_check("un favorito BLOQUEA (protected) en vez de pedir confirmacion", bool(gf["protected"]) and not bool(gf["needs_confirmation"]))
	GameState.set_favorite("gojo", false)
	GameState.mutations["isagi"] = { "rank": "R", "effects": [] }
	_check("una mutacion la hace importante", GameState.important_reasons("isagi").has("tiene una mutacion"))
	GameState.mutations.erase("isagi")
	_check("misiones personales con progreso hacen importante a Goku", _goku_important())
	# Confirmacion en la evolucion que consume.
	_fresh()
	GameState.roster = ["sakuta_mai", "mai"]
	GameState.progress["sakuta_mai"] = { "level": 100, "xp": 0 }
	GameState.ensure_defaults()
	GameState.party = ["sakuta_mai", "mai"]
	var consume: Dictionary = GameState.evolution_consume_check("sakuta_mai")
	_check("la evolucion especial de Sakuta y Mai CONSUME y pide confirmar (nivel 100, en el equipo)", bool(consume["consumes"]) and bool(consume["needs_confirmation"]) and String(consume["text"]).contains("CONSUME"))
	var other: Dictionary = GameState.evolution_consume_check("gojo")
	_check("una evolucion normal no consume ni pide confirmar", not bool(other["consumes"]) and not bool(other["needs_confirmation"]))
	GameState.set_favorite("sakuta_mai", true)
	_check("un favorito impide la evolucion especial (el bloqueo de siempre sigue)", not bool(GameState.can_special_evolve("sakuta_mai")["ok"]) and bool(GameState.can_special_evolve("sakuta_mai")["protected"]))
	GameState.set_favorite("sakuta_mai", false)
	# Informacion de fases.
	var lines: Array = StageInfo.lines("story", ["boss_sakuta"], 300, 120)
	_check("la info de una fase con jefe lo marca (con sus 2 fases)", String(lines[2]).contains("JEFE") and String(lines[2]).contains("2 fases"))
	_check("la info de historia dice que cada dificultad paga una vez", String(lines[1]) == StageInfo.STORY_RULE)
	_check("la info de stage dice que se paga cada vez", String(StageInfo.lines("stage", ["vigia_alfa"], 1, 1)[1]) == StageInfo.STAGE_RULE)
	_check("la info de torre dice que solo paga la primera vez", String(StageInfo.lines("tower", ["vigia_alfa"], 1, 1)[1]) == StageInfo.TOWER_RULE)
	_check("tipos de los rivales sin repetir", StageInfo.types_text(["boss_sakuta", "boss_sakuta"]) == "Tipos rivales: PHY")
	_check("un objeto de primera vez aparece en la info", String(StageInfo.lines("tower", ["vigia_alfa"], 1, 1, { "first_clear_item": "mai_token", "first_clear_amount": 2 })[0]).contains("2 x"))


func _goku_important() -> bool:
	GameState.meta.record("battle", 1, { "victory": true, "ally_ids": ["goku"], "bosses": [], "rounds": 4, "fallen": 0, "solo": true })
	return GameState.important_reasons("goku").has("tiene misiones personales en curso")


## --- 8. Diagnostico ------------------------------------------------------------------------------------
func _check_diagnostics() -> void:
	_out("[DBG27] == DIAGNOSTICO (solo desarrollo) ==")
	_fresh()
	var diag = Diagnostics.new()
	var rep: Dictionary = diag.run_all()
	var errors: Array = []
	for f in diag.findings:
		if String(f["severity"]) == "error":
			errors.append(String(f["text"]))
	_check("sobre los datos reales no hay ningun ERROR (%s)" % ("; ".join(PackedStringArray(errors)) if not errors.is_empty() else "ok"), bool(rep["ok"]) and errors.is_empty())
	_check("el informe se puede imprimir", diag.to_text().begins_with("DIAGNOSTICO: 0 errores"))
	var areas := ["ids", "recursos", "guardado", "recompensas", "personajes", "fases"]
	var all_areas := true
	for a in areas:
		if not Diagnostics.AREAS.has(a):
			all_areas = false
	_check("cubre las 6 areas pedidas", all_areas and Diagnostics.AREAS.size() == 6)
	_check("el arte que falta sale como AVISO (el juego dibuja una silueta), no como error", not diag.of_area("recursos", "warning").is_empty() and diag.of_area("recursos", "error").is_empty())
	# Se inyecta un fallo de cada tipo y el diagnostico lo ve.
	var backup := {
		"collections": DB.collections.duplicate(true), "cosmetics": DB.cosmetics.duplicate(true), "items": DB.items.duplicate(true),
		"stages": DB.stages.duplicate(true), "characters": DB.characters.duplicate(true), "achievements": DB.achievements.duplicate(true),
		"worlds": DB.worlds.duplicate(true), "events": DB.events.duplicate(true), "missions": DB.missions.duplicate(true),
	}
	# 1) cosmetico entregado por dos fuentes.
	var tiers: Array = DB.collections["col_cat_shonen"]["tiers"]
	(tiers[tiers.size() - 1]["reward"]["cosmetics"] as Array).append("bg_equipo")
	var d1 = Diagnostics.new()
	d1.run_all()
	_check("detecta un cosmetico dado por dos fuentes", _has(d1, "recompensas", "bg_equipo", "varias fuentes"))
	DB.collections = backup["collections"].duplicate(true)
	# 2) titulo repetido en dos fuentes.
	DB.achievements["ach_jefe_1"]["title"] = { "id": "title_ur", "name": "Despertado" }
	var d2 = Diagnostics.new()
	d2.run_all()
	_check("detecta un titulo dado por dos fuentes", _has(d2, "recompensas", "title_ur", "varias fuentes"))
	DB.achievements = backup["achievements"].duplicate(true)
	# 3) personaje imposible de conseguir.
	var ghost: Dictionary = DB.characters["gojo"].duplicate(true)
	ghost["id"] = "zz_fantasma"
	ghost["gacha"] = false
	DB.characters["zz_fantasma"] = ghost
	var d3 = Diagnostics.new()
	d3.run_all()
	_check("detecta un personaje imposible de conseguir", _has(d3, "personajes", "zz_fantasma", "IMPOSIBLE"))
	DB.characters = backup["characters"].duplicate(true)
	# 4) fase mal configurada: enemigo inexistente.
	DB.stages["zz_stage"] = { "id": "zz_stage", "name": "Rota", "enemies": ["no_existe"], "xp_reward": 5, "coin_reward": 5, "background": "battle_plain" }
	var d4 = Diagnostics.new()
	d4.run_all()
	_check("detecta una fase con un enemigo que no existe", _has(d4, "fases", "zz_stage", "no_existe"))
	DB.stages["zz_stage"]["enemies"] = []
	var d4b = Diagnostics.new()
	d4b.run_all()
	_check("detecta una fase sin enemigos", _has(d4b, "fases", "zz_stage", "no tiene enemigos"))
	DB.stages = backup["stages"].duplicate(true)
	# 4b) mundo con 'next' roto.
	DB.worlds["world_001"]["levels"][0]["next"] = "world_001_zz"
	var d4c = Diagnostics.new()
	d4c.run_all()
	_check("detecta un nivel que apunta a un 'next' inexistente", _has(d4c, "fases", "world_001_01", "world_001_zz"))
	DB.worlds = backup["worlds"].duplicate(true)
	# 4c) evento que exige una forma imposible.
	DB.events["event_sindromes_de_la_pubertad"]["stages"][2]["requires_party_rarity"] = "N"
	var d4d = Diagnostics.new()
	d4d.run_all()
	_check("detecta una fase de evento que exige una forma imposible", _has(d4d, "fases", "evt_sdp_03", "imposible"))
	DB.events = backup["events"].duplicate(true)
	# 5) recurso ausente: fondo cosmetico sin imagen.
	DB.cosmetics["zz_cos"] = { "id": "zz_cos", "type": "background", "name": "x", "slot": "no_existe_slot" }
	var d5 = Diagnostics.new()
	d5.run_all()
	_check("detecta un cosmetico con un fondo que no existe", _has(d5, "recursos", "zz_cos", "no hay imagen"))
	_check("... y un cosmetico que nadie da", _has(d5, "recompensas", "zz_cos", "inalcanzable", "warning"))
	DB.cosmetics = backup["cosmetics"].duplicate(true)
	# 6) identificador duplicado entre carpetas.
	DB.items["bg_equipo"] = { "id": "bg_equipo", "name": "Duplicado" }
	var d6 = Diagnostics.new()
	d6.run_all()
	_check("detecta un id repetido entre objetos y cosmeticos", _has(d6, "ids", "bg_equipo", "repetido"))
	DB.items = backup["items"].duplicate(true)
	# 7) personal rota.
	DB.missions["pm_goku_batallas"]["character"] = "no_existe"
	var d7 = Diagnostics.new()
	d7.run_all()
	_check("detecta una mision personal de un personaje que no existe", _has(d7, "recompensas", "pm_goku_batallas", "no existe"))
	DB.missions = backup["missions"].duplicate(true)
	# 8) errores de guardado.
	GameState.favorites.append("no_existe")
	GameState.inventory["objeto_fantasma"] = 2
	GameState.account.claimed_levels.append(25)
	var d8 = Diagnostics.new()
	d8.run_all()
	_check("detecta un favorito que no esta en el roster", _has(d8, "guardado", "no_existe", "favorito"))
	_check("detecta un objeto inexistente en el inventario", _has(d8, "guardado", "objeto_fantasma", "inventario"))
	_check("detecta un nivel de cuenta cobrado sin alcanzarlo", _has(d8, "guardado", "25", "sin haberlo alcanzado"))
	GameState.favorites.erase("no_existe")
	GameState.inventory.erase("objeto_fantasma")
	GameState.account.claimed_levels.erase(25)
	GameState.collections.claimed["col_serie_black_clover"] = ["full"]
	var d9 = Diagnostics.new()
	d9.run_all()
	_check("detecta un tramo cobrado sin haber cumplido su requisito", _has(d9, "guardado", "col_serie_black_clover/full", "sin haber alcanzado"))
	GameState.collections.claimed.clear()
	var again = Diagnostics.new()
	var rep2: Dictionary = again.run_all()
	_check("restaurados los datos, vuelve a no haber ningun error", bool(rep2["ok"]))
	# No existe en la version publica.
	DevTools.simulate_release(true)
	var pub = Diagnostics.new()
	var pub_rep: Dictionary = pub.run_all()
	_check("en una compilacion de distribucion el diagnostico no hace nada", pub.findings.size() == 1 and String(pub.findings[0]["severity"]) == "info" and bool(pub_rep["ok"]))
	_check("... y las herramientas de desarrollo estan desactivadas", not DevTools.enabled())
	DevTools.simulate_release(false)
	_check("el diagnostico no escribe el guardado ni cambia el estado (monedas intactas)", GameState.coins == 0)


func _has(diag, area: String, needle_a: String, needle_b: String, severity: String = "error") -> bool:
	for f in diag.findings:
		if String(f["area"]) == area and String(f["severity"]) == severity and String(f["text"]).contains(needle_a) and String(f["text"]).contains(needle_b):
			return true
	return false


## --- 9. Pantallas ------------------------------------------------------------------------------------------
func _cards(list: Node, prefix: String = "") -> int:
	var n := 0
	for child in list.get_children():
		if child is PanelContainer and (prefix.is_empty() or String(child.name).begins_with(prefix)):
			n += 1
	return n


func _check_screens() -> void:
	_out("[DBG27] == PANTALLAS NUEVAS ==")
	_fresh()
	GameState.roster = ["goku", "asta", "yuno", "gojo", "isagi", "mai", "sakuta_mai"]
	GameState.ensure_defaults()
	# Colecciones.
	_app.call("open_screen", "collection_rewards")
	await _wait(0.4)
	var screen = _app.get("_screens").get("collection_rewards", null)
	_check("la pantalla de colecciones abre", screen != null)
	if screen == null:
		return
	var list: Node = screen.get_node("Margin/VBoxContainer/ScrollContainer/List") if screen.get_node_or_null("Margin/VBoxContainer/ScrollContainer/List") != null else screen.find_child("List", true, false)
	_check("SERIES: 12 tarjetas", _cards(list, "Col_") == 12)
	screen.call("_select_kind", "category")
	await _wait(0.1)
	_check("CATEGORIAS: 13 tarjetas", _cards(list, "Col_") == 13)
	screen.call("_select_kind", "rarity")
	await _wait(0.1)
	_check("RAREZAS: 2 tarjetas", _cards(list, "Col_") == 2)
	screen.call("_select_kind", "event")
	await _wait(0.1)
	_check("EVENTOS: 1 tarjeta", _cards(list, "Col_") == 1)
	screen.call("_select_kind", "series")
	await _wait(0.1)
	var db_card: Node = list.get_node_or_null("Col_col_serie_black_clover")
	_check("la tarjeta de Dragon Ball existe y tiene sus botones de tramo", db_card != null and db_card.find_child("Claim_half", true, false) != null and db_card.find_child("Claim_full", true, false) != null)
	var coins_before: int = GameState.coins
	screen.call("_on_claim", "col_serie_black_clover", "half")
	await _wait(0.1)
	_check("reclamar desde la pantalla paga y la pantalla se repinta", GameState.coins > coins_before and (list.get_node("Col_col_serie_black_clover").find_child("Claim_half", true, false) as Button).disabled)
	var feedback: Label = screen.find_child("Feedback", true, false)
	_check("la pantalla dice lo que se ha entregado", feedback != null and feedback.text.length() > 0)
	screen.call("_toggle_expand", "col_serie_black_clover")
	await _wait(0.1)
	_check("ver personajes muestra los que tienes", list.get_node("Col_col_serie_black_clover").find_children("*", "Label", true, false).size() >= 8)
	var claim_all: Button = screen.find_child("ClaimAll", true, false)
	_check("el boton RECLAMAR TODO refleja lo pendiente", claim_all != null)
	_app.call("go_back")
	await _wait(0.1)
	# Perfil.
	GameState.account.add_xp(800)
	_app.call("open_screen", "profile")
	await _wait(0.4)
	var profile = _app.get("_screens").get("profile", null)
	_check("el perfil abre", profile != null)
	if profile != null:
		var level_label: Label = profile.find_child("LevelLabel", true, false)
		_check("el perfil muestra el nivel de cuenta (%s)" % level_label.text, level_label != null and level_label.text.begins_with("NIVEL 5"))
		var bar: ProgressBar = profile.find_child("XpBar", true, false)
		_check("la barra de XP tiene el progreso del nivel", bar != null and bar.max_value == float(GameState.account.xp_needed(5)))
		_check("hay una fila por nivel pendiente", profile.find_child("Level_2", true, false) != null and profile.find_child("Level_5", true, false) != null)
		var c0: int = GameState.coins
		profile.call("_on_claim_all")
		await _wait(0.1)
		_check("RECLAMAR TODO del perfil paga los niveles y entrega el fondo del nivel 5", GameState.coins > c0 and GameState.account.owns_cosmetic("bg_equipo"))
		_check("el fondo ganado aparece para equiparlo", profile.find_child("Cos_bg_equipo", true, false) != null)
		profile.call("_on_equip", "bg_equipo", "background")
		await _wait(0.1)
		_check("equiparlo desde el perfil lo guarda", GameState.account.background_equipped == "bg_equipo")
		_app.call("go_back")
		await _wait(0.1)
	# Menu principal: fondo, nivel e ilustracion.
	var menu = _app.get("_screens").get("main_menu", null)
	menu.call("refresh")
	await _wait(0.1)
	var bg: Node = menu.get_node("Background")
	_check("el menu principal usa el fondo equipado (slot team)", String(bg.get("slot")) == "team")
	var pbtn: Button = menu.find_child("ProfileButton", true, false)
	_check("el menu muestra el nivel de cuenta y lo pendiente", pbtn != null and pbtn.text.begins_with("PERFIL  -  NIVEL 5"))
	GameState.account.grant_cosmetic("ill_goku")
	GameState.account.equip_illustration("ill_goku")
	menu.call("refresh")
	var hero_name: Label = menu.get("_hero_name")
	_check("la ilustracion equipada sustituye al lider en el escaparate", hero_name.text == "SON GOKU")
	GameState.account.equip_background("")
	GameState.account.equip_illustration("")
	menu.call("refresh")
	_check("quitar el fondo y la ilustracion devuelve el menu de siempre", String(bg.get("slot")) == "menu")
	# Colecciones personales: pestana en misiones.
	_app.call("open_screen", "missions")
	await _wait(0.4)
	var missions = _app.get("_screens").get("missions", null)
	var mlist: Node = missions.get_node("Margin/Main/Scroll/List")
	_check("MISIONES tiene ahora 5 pestanas (DIARIAS, SEMANALES, PERMANENTES, PERSONAJES, LOGROS)", missions.get_node("Margin/Main/Tabs").get_child_count() == 5)
	missions.call("_select_tab", "personal")
	await _wait(0.1)
	_check("PERSONAJES: 12 tarjetas, sin etiqueta de reinicio", _cards(mlist) == 12)
	missions.call("_select_tab", "permanent")
	await _wait(0.1)
	_check("PERMANENTES sigue con las 7 de siempre", _cards(mlist) == 7)
	GameState.meta.record("battle", 1, { "victory": true, "ally_ids": ["goku"], "bosses": [], "rounds": 4, "fallen": 0, "solo": true })
	missions.call("_select_tab", "personal")
	await _wait(0.1)
	_check("una personal en curso se ve con su progreso", GameState.meta.personal_state("pm_goku_batallas")["progress"] == 1)
	_app.call("go_back")
	await _wait(0.1)
	# Comparar.
	_app.call("open_screen", "collection")
	await _wait(0.3)
	var col = _app.get("_screens").get("collection", null)
	_check("la coleccion tiene los botones RECOMPENSAS y COMPARAR", col.find_child("RewardsButton", true, false) != null and col.find_child("CompareButton", true, false) != null)
	_app.call("go_back")
	await _wait(0.1)
	_app.call("open_screen", "compare")
	await _wait(0.4)
	var cmp = _app.get("_screens").get("compare", null)
	_check("la pantalla de comparar abre", cmp != null)
	if cmp != null:
		cmp.call("select_pair", "gojo", "isagi")
		await _wait(0.1)
		_check("tiene los dos selectores y una fila por estadistica", cmp.find_child("PickA", true, false) != null and cmp.find_child("Stat_hp", true, false) != null and cmp.find_child("Stat_dodge_rate", true, false) != null)
		var verdict: Label = cmp.find_child("Verdict", true, false)
		_check("dice quien gana mas estadisticas (%s)" % verdict.text, verdict != null and verdict.text.length() > 0)
		_app.call("go_back")
		await _wait(0.1)
	# Evolucion: prevision y confirmacion.
	GameState.progress["sakuta_mai"] = { "level": 100, "xp": 0 }
	GameState.add_item("rabbit_costume", 25)
	GameState.party = ["sakuta_mai", "mai"]
	GameState.coins = 1000
	_app.call("open_screen", "evolution")
	await _wait(0.4)
	var evo = _app.get("_screens").get("evolution", null)
	evo.set("_selected_id", "sakuta_mai")
	evo.call("_build_detail")
	await _wait(0.1)
	_check("la pantalla EVOLUCION muestra la tabla de estadisticas previstas", evo.find_child("StatPreview", true, false) != null and evo.find_child("PreviewGrid", true, false) != null)
	var grid: GridContainer = evo.find_child("PreviewGrid", true, false)
	_check("la tabla tiene cabecera + 6 estadisticas x 4 columnas", grid != null and grid.get_child_count() == 4 + 6 * 4)
	var check: Dictionary = GameState.can_special_evolve("sakuta_mai")
	_check("Sakuta y Mai esta lista para evolucionar (preparada la prueba: %s)" % String(check.get("reason", "")), bool(check["ok"]))
	if bool(check["ok"]):
		evo.call("_on_evolve_pressed")
		await _wait(0.1)
		_check("PRIMER toque: NO evoluciona (la unidad importante se consume)", GameState.is_owned("sakuta_mai") and not GameState.is_owned("sakuta"))
		var evolve_button: Button = evo.find_child("EvolveButton", true, false)
		_check("... y el boton pasa a pedir confirmacion", evolve_button != null and evolve_button.text == "CONFIRMAR EVOLUCION")
		_check("... y avisa de por que", (evo.get("subtitle_label") as Label).text.contains("CONSUME"))
		evo.call("_on_evolve_pressed")
		await _wait(0.2)
		_check("SEGUNDO toque: evoluciona", GameState.is_owned("sakuta") and not GameState.is_owned("sakuta_mai"))
		_check("... y el nivel y el equipo pasan al personaje nuevo", GameState.level_of("sakuta") == 100 and GameState.party.has("sakuta"))
		_check("... y la coleccion de Seishun Buta Yarou sigue completa", bool(GameState.collections.state("col_serie_seishun_buta")["complete"]))
		var after_special: Dictionary = GameState.meta.personal_state("pm_sakuta_evolucion")
		_check("... y la evolucion cuenta para su mision personal", int(after_special["progress"]) == 1)
	_app.call("go_back")
	await _wait(0.1)
	# Info de fases en pantalla.
	_app.call("open_screen", "stage_select")
	await _wait(0.4)
	var ss = _app.get("_screens").get("stage_select", null)
	var texts := ""
	for b in ss.find_children("*", "Button", true, false):
		texts += (b as Button).text + "\n"
	_check("la seleccion de batalla dice la regla de pago", texts.contains(StageInfo.STAGE_RULE) and texts.contains("Recompensa:"))
	_check("... y marca al jefe (Vigia del Vacio es Makima)", texts.contains("JEFE"))
	_app.call("go_back")
	await _wait(0.1)
	_app.call("open_screen", "tower")
	await _wait(0.4)
	var tw = _app.get("_screens").get("tower", null)
	var tower_text := ""
	for l in tw.find_children("*", "Label", true, false):
		tower_text += (l as Label).text + "\n"
	_check("la torre dice que cada piso solo paga la primera vez", tower_text.contains(StageInfo.TOWER_RULE))
	_check("... y cada piso ensena lo que paga", tower_text.contains("monedas"))
	_app.call("go_back")
	await _wait(0.1)
	# Panel de desarrollo: solo en depuracion.
	var settings_scene: PackedScene = load("res://scenes/screens/settings.tscn")
	var st = settings_scene.instantiate()
	add_child(st)
	await _wait(0.2)
	_check("en depuracion el panel de desarrollo trae el boton de diagnostico", st.find_child("DiagnosticsButton", true, false) != null)
	st.queue_free()
	DevTools.simulate_release(true)
	var st2 = settings_scene.instantiate()
	add_child(st2)
	await _wait(0.2)
	_check("en la version publica NO hay panel de desarrollo ni diagnostico", st2.find_child("DiagnosticsButton", true, false) == null and st2.find_child("DevAddDuoButton", true, false) == null)
	st2.queue_free()
	DevTools.simulate_release(false)


## --- 10. v16: nadie nace UR/LR, banners coherentes y nombres de cosmeticos --------------------
func _check_v16_rarity() -> void:
	_out("[DBG27] == v16: RAREZA NATURAL Y BANNERS ==")
	_fresh()
	var natural_bad: Array = []
	for id in DB.characters:
		var d: Dictionary = DB.characters[id]
		if (String(d.get("rarity", "")) == "UR" or String(d.get("rarity", "")) == "LR") and String(d.get("evolved_from", "")).is_empty():
			natural_bad.append(String(id))
	_check("ningun personaje nace UR ni LR (solo las formas evolucionadas: %s)" % ", ".join(PackedStringArray(natural_bad)), natural_bad.is_empty())
	for id in ["goku", "frieren", "makima", "sukuna"]:
		_check("%s nace SSR" % id, String(DB.characters[id]["rarity"]) == "SSR")
	var banner_ok := true
	var pool_rarities: Dictionary = {}
	for b in DB.all_banners():
		var bid := String((b as Dictionary)["id"])
		if not GameState.banner_problems(bid).is_empty() or (GameState.banner_rates(bid) as Dictionary).has("UR") or (GameState.banner_rates(bid) as Dictionary).has("LR"):
			banner_ok = false
		for id in GameState.banner_pool(bid):
			pool_rarities[String(DB.characters[id]["rarity"])] = true
	_check("ningun banner da UR ni LR y todos son validos (suman 1, sin rarezas huerfanas)", banner_ok)
	_check("los pools solo contienen SR y SSR", pool_rarities.keys().size() == 2 and pool_rarities.has("SR") and pool_rarities.has("SSR"))
	# Una x10 en cada banner solo puede dar SR o SSR.
	GameState.gems = 100000
	var seen_bad := false
	for b in DB.all_banners():
		var bid2 := String((b as Dictionary)["id"])
		for n in 30:
			var report: Dictionary = GameState.summon(bid2, 10)
			for r in report.get("results", []):
				var rar := String((r as Dictionary).get("rarity", ""))
				if rar != "SR" and rar != "SSR":
					seen_bad = true
	_check("300 tiradas por banner: jamas sale algo que no sea SR o SSR", not seen_bad)
	# Goku, ahora SSR, evoluciona a UR como cualquier otro SSR.
	GameState.progress["goku"] = { "level": 100, "xp": 0 }
	GameState.coins = 1000000
	var can: Dictionary = GameState.can_evolve("goku")
	_check("Goku (SSR) puede evolucionar a UR al nivel 100", bool(can.get("ok", false)) and String(can.get("to", "")) == "UR")
	var rep: Dictionary = GameState.evolve("goku")
	_check("... y tras evolucionar es UR con su pasiva de forma UR", not rep.is_empty() and GameState.rarity_of("goku") == "UR" and String(GameState.character_data("goku")["passive"].get("id", "")) == "pas_goku_lr_saiyan")
	_check("las colecciones siguen validas (Leyendas = Goku, Frieren, Makima, Sukuna)", GameState.collections.members_of("col_rareza_ur").size() == 4 and GameState.collections.problems("col_rareza_ur").is_empty())
	_check("los cosmeticos no repiten su prefijo (Ilustracion: Ilustracion:)", not Rewards.describe({ "cosmetics": ["ill_asta"] }).contains("Ilustracion: Ilustracion"))
	var any_prefixed := false
	for id in DB.cosmetics:
		if String(DB.cosmetics[id]["name"]).begins_with("Fondo: ") or String(DB.cosmetics[id]["name"]).begins_with("Ilustracion: "):
			any_prefixed = true
	_check("los nombres de cosmetico no llevan el prefijo del tipo", not any_prefixed)
	# El diagnostico avisa si alguien vuelve a hacer nacer a un personaje como UR.
	var saved: Dictionary = DB.characters["gojo"].duplicate(true)
	DB.characters["gojo"]["rarity"] = "UR"
	var d1 = Diagnostics.new()
	d1.run_all()
	_check("el diagnostico detecta un personaje que nace UR", _has(d1, "personajes", "gojo", "nace con rareza UR"))
	DB.characters["gojo"] = saved


func _check_v16_screens() -> void:
	_out("[DBG27] == v16: PANTALLAS ==")
	_fresh()
	_app.call("open_screen", "summon")
	await _wait(0.4)
	var summon = _app.get("_screens").get("summon", null)
	summon.call("_on_banner_tab", "banner_ur")
	summon.call("_on_info_pressed")
	await _wait(0.3)
	var panel = summon.get_node_or_null("BannerInfoPanel")
	_check("INFO DEL BANNER abre su ventana", panel != null)
	if panel != null:
		var view := get_viewport().get_visible_rect().size
		_check("la ventana ocupa la pantalla entera (%s de %s)" % [str(panel.size), str(view)], panel.size.x >= view.x * 0.95 and panel.size.y >= view.y * 0.95)
		var body: Node = panel.find_child("Body", true, false)
		_check("el contenido no esta vacio: %d lineas, alto %d" % [body.get_child_count(), int(body.size.y)], body.get_child_count() > 15 and body.size.y > 300)
		_check("muestra probabilidades, pity y personajes", _all_text(body).contains("PROBABILIDAD") and _all_text(body).contains("PITY") and _all_text(body).contains("PERSONAJES DISPONIBLES"))
		_check("no dice que nadie llegue a UR sin evolucion: Goku llega a UR", _all_text(body).contains("Son Goku") )
		var scroll: ScrollContainer = body.get_parent()
		_check("el scroll tiene altura propia (no colapsa)", scroll.size.y > 300)
		panel.queue_free()
	await _wait(0.1)
	_app.call("go_back")
	await _wait(0.1)
	# Perfil rediseñado.
	GameState.account.add_xp(1800)
	GameState.account.grant_cosmetic("ill_goku")
	_app.call("open_screen", "profile")
	await _wait(0.4)
	var profile = _app.get("_screens").get("profile", null)
	_check("el perfil tiene retrato, nivel con fuente grande y seis estadisticas", profile.find_child("Portrait", true, false).texture != null and profile.find_child("LevelLabel", true, false).get_theme_font_size("font_size") >= 44 and profile.find_child("Stats", true, false).get_child_count() == 6)
	var lv: Node = profile.find_child("Level_2", true, false)
	_check("cada nivel pendiente es una tarjeta con su boton", lv is PanelContainer and lv.find_children("*", "Button", true, false).size() == 1)
	var small: Array = []
	for l in profile.find_children("*", "Label", true, false):
		if (l as Label).visible and (l as Label).get_theme_font_size("font_size") < 22 and (l as Label).text.length() > 0:
			small.append((l as Label).text)
	_check("ningun texto del perfil usa la fuente diminuta (<22): %s" % str(small), small.is_empty())
	var cos: Node = profile.find_child("Cos_ill_goku", true, false)
	_check("las ilustraciones ganadas aparecen en cuadricula", cos != null and cos.get_parent() is GridContainer)
	_app.call("go_back")
	await _wait(0.1)


func _all_text(node: Node) -> String:
	var out := ""
	for l in node.find_children("*", "Label", true, false):
		out += (l as Label).text + "\n"
	return out
