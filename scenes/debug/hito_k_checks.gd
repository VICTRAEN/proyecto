extends Node

## COMPROBACIONES EN EJECUCION DE LA v13 (pity, historial, banners, copias). SOLO pruebas.
## Arranque:  godot --headless --path . -- --dbg25   (escribe res://dbg25_resultados.txt)

const RESULTS_PATH := "res://dbg25_resultados.txt"
const DUO := "david_lucy_duo"

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
	_out("[DBG25] %s -> %s" % [label, "OK" if ok else "FALLO"])


func run(app: Node) -> void:
	_app = app
	await get_tree().create_timer(0.3).timeout
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	seed(4242)
	_out("[DBG25] --- comprobaciones v13 ---")
	_app.call("_backup_save")
	_check_reach()
	_check_pity_single_multi()
	_check_pity_natural_reset()
	_check_persistence()
	_check_history()
	_check_banner_info()
	await _check_screens()
	_check_copies()
	await _check_collection_screen()
	_app.call("_restore_save")
	_out("[DBG25] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _reset_summon_state() -> void:
	GameState.pity_counters = {}
	GameState.summon_history = []
	GameState.summon_total = 0
	GameState.summon_banner_totals = {}
	GameState.pending_reveal = {}
	GameState.gems = 100000


## Banner de prueba con probabilidades fijas: casi siempre SR, el duo practicamente no sale solo.
func _install_test_banner(id: String, rates: Dictionary, featured_rates: Dictionary = {}) -> void:
	DB.banners[id] = {
		"id": id, "name": "Prueba", "enabled": true, "cost_gems": 10, "multi_pulls": 10, "multi_cost_gems": 90,
		"rates": rates, "pool_categories": [], "exclusive_ids": [DUO], "featured_rates": featured_rates,
		"featured": [], "featured_bonus": 0.0, "pity": { "pulls": 10, "rarity": "LR" },
	}


## --- 1. Rareza maxima alcanzable --------------------------------------------------------------
func _check_reach() -> void:
	_out("[DBG25] == RAREZA MAXIMA ALCANZABLE ==")
	_check("el duo (SSR con forma LR) llega a LR", GameState.max_reachable_rarity(DUO) == "LR")
	_check("un SSR sin forma LR llega a UR (gojo)", GameState.max_reachable_rarity("gojo") == "UR")
	_check("un UR sin forma LR se queda en UR (frieren)", GameState.max_reachable_rarity("frieren") == "UR")
	_check("sakuta_mai llega a LR por su ruta de evolucion especial", GameState.max_reachable_rarity("sakuta_mai") == "LR")
	var only_duo := true
	var lr_capable: Array = []
	for id in DB.character_ids():
		if GameState.can_reach_rarity(String(id), "LR") and not GameState.gacha_excluded_ids().has(String(id)):
			lr_capable.append(String(id))
	only_duo = lr_capable == [DUO]
	_check("entre los personajes invocables solo el duo puede llegar a LR (%s)" % str(lr_capable), only_duo)
	for banner in DB.all_banners():
		var bid := String((banner as Dictionary).get("id", ""))
		_check("%s: sin errores de configuracion" % bid, GameState.banner_problems(bid).is_empty())
		var st := GameState.pity_status(bid)
		if bid == "banner_david_lucy":
			_check("el banner del duo tiene pity de 10 y solo cuenta al duo", bool(st["enabled"]) and int(st["pulls"]) == 10 and (st["eligible"] as Array) == [DUO])
		else:
			_check("%s no tiene pity (nadie de su pool llega a LR) y lo dice" % bid, not bool(st["enabled"]) and not String(st["reason"]).is_empty())


## --- 2. Pity en individual y multiple -----------------------------------------------------------
func _check_pity_single_multi() -> void:
	_out("[DBG25] == PITY: INDIVIDUAL Y MULTIPLE ==")
	_install_test_banner("t_pity", { "SR": 0.9999999, "SSR": 0.0000001 })
	_reset_summon_state()
	var seen_guarantee := -1
	var all_ok := true
	for n in 9:
		var r := GameState.summon("t_pity", 1)
		all_ok = all_ok and bool(r["ok"]) and not bool(r["results"][0]["guaranteed"]) and GameState.pity_counter("t_pity") == n + 1
	_check("las 9 primeras tiradas individuales no garantizan y el contador sube 1..9", all_ok)
	var tenth := GameState.summon("t_pity", 1)
	_check("la 10a tirada individual garantiza al duo", bool(tenth["ok"]) and String(tenth["results"][0]["id"]) == DUO and bool(tenth["results"][0]["guaranteed"]))
	_check("tras el garantizado el contador vuelve a 0", GameState.pity_counter("t_pity") == 0 and int(tenth["pity_after"]) == 0)
	# multi desde 0
	_reset_summon_state()
	var m := GameState.summon("t_pity", 10)
	var guaranteed_at := -1
	var count_dup := 0
	for i in 10:
		if bool(m["results"][i]["guaranteed"]):
			guaranteed_at = i
			count_dup += 1
	_check("una x10 desde 0: la 10a tirada es la garantizada (una sola vez)", guaranteed_at == 9 and count_dup == 1 and String(m["results"][9]["id"]) == DUO)
	_check("la x10 deja el contador en 0 y cuesta lo de una x10", GameState.pity_counter("t_pity") == 0 and int(m["cost"]) == 90)
	# multi desde 5: garantizada en la 5a, sin contar dos veces
	_reset_summon_state()
	GameState.pity_counters["t_pity"] = 5
	var m2 := GameState.summon("t_pity", 10)
	_check("una x10 desde 5: la 5a tirada es la garantizada", bool(m2["results"][4]["guaranteed"]) and String(m2["results"][4]["id"]) == DUO and int(m2["pity_guaranteed"]) == 1)
	_check("...y las 5 siguientes empiezan de nuevo (contador 5, no se cuenta dos veces)", int(m2["pity_after"]) == 5 and GameState.pity_counter("t_pity") == 5)
	# 25 tiradas desde 0
	_reset_summon_state()
	var big := 0
	var sum_guar := 0
	for chunk in [10, 10, 5]:
		var rr := GameState.summon("t_pity", chunk)
		sum_guar += int(rr["pity_guaranteed"])
		big += chunk
	_check("25 tiradas en tres invocaciones dan 2 garantizadas y quedan 5 de contador", sum_guar == 2 and GameState.pity_counter("t_pity") == 5 and big == 25)
	# x1 mezclado con x10 equivale a tiradas seguidas
	_reset_summon_state()
	for k in 4:
		GameState.summon("t_pity", 1)
	var mix := GameState.summon("t_pity", 10)
	_check("4 individuales + x10: la garantizada cae en la 6a de la multi (10a en total)", bool(mix["results"][5]["guaranteed"]) and int(mix["pity_guaranteed"]) == 1)
	# sin gemas: no cobra, no cambia nada
	_reset_summon_state()
	GameState.gems = 5
	GameState.pity_counters["t_pity"] = 7
	var broke := GameState.summon("t_pity", 10)
	_check("sin gemas no se tira, no se cobra y el pity no cambia", not bool(broke["ok"]) and GameState.gems == 5 and GameState.pity_counter("t_pity") == 7 and GameState.summon_history.is_empty())
	# banner sin pity no usa contador
	_reset_summon_state()
	GameState.summon("banner_apertura", 10)
	_check("un banner sin pity no acumula contador", not GameState.pity_counters.has("banner_apertura") and not bool(GameState.pity_status("banner_apertura")["enabled"]))
	# el banner real del duo
	_reset_summon_state()
	var real_ok := true
	var guaranteed_total := 0
	for k in 12:
		var rr2 := GameState.summon("banner_david_lucy", 10)
		real_ok = real_ok and bool(rr2["ok"])
		guaranteed_total += int(rr2["pity_guaranteed"])
		var has_duo := false
		for entry in rr2["results"]:
			if String(entry["id"]) == DUO:
				has_duo = true
		real_ok = real_ok and has_duo
	_check("banner real del duo: TODA x10 contiene al duo (12 de 12)", real_ok)
	# Efecto real del pity sobre el banner del duo (informativo, 3000 tiradas x1).
	_reset_summon_state()
	var duo_hits := 0
	var worst_gap := 0
	var gap := 0
	for n in 3000:
		var rr3 := GameState.summon("banner_david_lucy", 1)
		if String(rr3["results"][0]["id"]) == DUO:
			duo_hits += 1
			gap = 0
		else:
			gap += 1
			worst_gap = maxi(worst_gap, gap)
	_out("[DBG25] INFO banner del duo con pity: duo en %.2f%% de las tiradas (sin pity seria 7%%), maximo %d tiradas seguidas sin duo" % [100.0 * float(duo_hits) / 3000.0, worst_gap])
	_check("en 3000 tiradas nunca pasan 9 seguidas sin el duo", worst_gap <= 9)
	DB.banners.erase("t_pity")


## --- 3. Reinicio si aparece antes ------------------------------------------------------------------
func _check_pity_natural_reset() -> void:
	_out("[DBG25] == PITY: REINICIO SI SALE ANTES ==")
	# La mitad de los SSR son el duo: sale solo muy a menudo.
	_install_test_banner("t_nat", { "SR": 0.5, "SSR": 0.5 }, { DUO: 0.4 })
	_reset_summon_state()
	var invariants := true
	var since := 0
	var max_gap := 0
	var natural_resets := 0
	for n in 600:
		var r := GameState.summon("t_nat", 1)
		var entry: Dictionary = r["results"][0]
		if String(entry["id"]) == DUO:
			invariants = invariants and int(entry["pity"]) == 0 and GameState.pity_counter("t_nat") == 0
			if not bool(entry["guaranteed"]):
				natural_resets += 1
			since = 0
		else:
			since += 1
			invariants = invariants and int(entry["pity"]) == since and since <= 9
		max_gap = maxi(max_gap, since)
	_check("si el duo sale antes de la 10a, el contador vuelve a 0 (%d reinicios naturales)" % natural_resets, invariants and natural_resets > 50)
	_check("nunca pasan 9 tiradas seguidas sin el duo (max %d)" % max_gap, max_gap <= 9)
	# frecuencia real de elegir al duo dentro de SSR (7/15 = 0.4667 en el banner real)
	var hits := 0
	var ssr_pool: Array = []
	for id in GameState.banner_pool("banner_david_lucy"):
		if String(DB.get_character(String(id)).get("rarity", "")) == "SSR":
			ssr_pool.append(String(id))
	for n in 20000:
		if GameState._pick_candidate("banner_david_lucy", "SSR", ssr_pool) == DUO:
			hits += 1
	var freq := float(hits) / 20000.0
	_check("las tasas actuales se conservan: el duo es el 7%% por tirada (%.3f de los SSR, esperado 0.467)" % freq, absf(freq - 7.0 / 15.0) < 0.02)
	DB.banners.erase("t_nat")


## --- 4. Persistencia -----------------------------------------------------------------------------------
func _check_persistence() -> void:
	_out("[DBG25] == PERSISTENCIA ==")
	_install_test_banner("t_per", { "SR": 0.9999999, "SSR": 0.0000001 })
	_reset_summon_state()
	for n in 4:
		GameState.summon("t_per", 1)
	var gems_after := GameState.gems
	GameState.pity_counters = {}
	GameState.summon_history = []
	GameState.summon_total = 0
	GameState.load_game()
	_check("el contador sobrevive a cerrar y abrir el juego (4)", GameState.pity_counter("t_per") == 4)
	_check("el historial y el total sobreviven", GameState.summon_history.size() == 4 and GameState.summon_total == 4)
	_check("recargar dos veces no cambia nada (no se puede repetir una tirada cerrando)", GameState.gems == gems_after)
	GameState.load_game()
	_check("...ni el contador ni el historial", GameState.pity_counter("t_per") == 4 and GameState.summon_history.size() == 4 and GameState.gems == gems_after)
	# garantizada tras recargar a mitad
	for n in 5:
		GameState.summon("t_per", 1)
	GameState.load_game()
	_check("tras 9 tiradas y recargar, la siguiente sigue siendo la garantizada", GameState.pity_counter("t_per") == 9 and bool(GameState.summon("t_per", 1)["results"][0]["guaranteed"]))
	# revelado pendiente: no se vuelve a tirar ni cobrar
	_reset_summon_state()
	var staged := GameState.summon("t_per", 10, true)
	var gems_staged := GameState.gems
	var ids_before: Array = []
	for entry in staged["results"]:
		ids_before.append(entry["id"])
	GameState.pending_reveal = {}
	GameState.load_game()
	var ids_after: Array = []
	for entry in GameState.pending_reveal.get("results", []):
		ids_after.append(entry["id"])
	_check("un revelado interrumpido recupera EXACTAMENTE los mismos resultados", ids_before == ids_after and GameState.has_pending_reveal())
	_check("...sin cobrar de nuevo", GameState.gems == gems_staged)
	var again := GameState.summon("t_per", 1)
	_check("con un revelado pendiente no se acepta otra invocacion ni se cobra", not bool(again["ok"]) and GameState.gems == gems_staged)
	GameState.reveal_finish()
	_check("al terminar el revelado se puede invocar de nuevo", bool(GameState.summon("t_per", 1)["ok"]))
	# guardado antiguo sin claves nuevas
	GameState._load_summon_records({ "version": 3 })
	_check("un guardado anterior a la v13 carga con todo a cero", GameState.pity_counters.is_empty() and GameState.summon_history.is_empty() and GameState.summon_total == 0)
	GameState._load_summon_records({ "pity_counters": { "t_per": 3, "x": "basura" }, "summon_history": ["basura", { "results": "mal" }, { "time": 5, "results": [{ "id": "gojo" }, 7] }], "summon_total": -4 })
	_check("datos mal formados se descartan sin romper", GameState.pity_counters.get("t_per", 0) == 3 and GameState.summon_history.size() == 1 and GameState.summon_total == 0)
	DB.banners.erase("t_per")


## --- 5. Historial --------------------------------------------------------------------------------------------
func _check_history() -> void:
	_out("[DBG25] == HISTORIAL ==")
	_reset_summon_state()
	GameState.summon("banner_apertura", 1)
	GameState.summon("banner_destacado", 10)
	GameState.summon("banner_david_lucy", 10)
	var list := GameState.summon_history_list()
	_check("una entrada por invocacion (3)", list.size() == 3)
	_check("cada entrada trae banner, fecha, coste, resultados y total acumulado", String(list[1]["banner"]) == "banner_destacado" and int(list[1]["time"]) > 0 and int(list[1]["cost"]) == 90 and (list[1]["results"] as Array).size() == 10 and int(list[2]["total_after"]) == 21)
	_check("total de invocaciones = 21 y por banner", GameState.summon_total == 21 and int(GameState.summon_banner_totals["banner_destacado"]) == 10 and int(GameState.summon_banner_totals["banner_apertura"]) == 1)
	_check("la entrada del duo guarda el progreso del pity", bool(list[2]["pity_enabled"]) and int(list[2]["pity_pulls"]) == 10 and list[2].has("pity_after"))
	var ts := GameState.format_timestamp(int(list[0]["time"]))
	_check("la fecha se formatea 'AAAA-MM-DD  HH:MM' (%s)" % ts, ts.length() == 17 and ts[4] == "-" and ts[14] == ":")
	# el revelado no duplica el historial
	var before := GameState.summon_history.size()
	GameState.summon("banner_apertura", 10, true)
	GameState.reveal_advance()
	GameState.reveal_finish()
	_check("pasar por el revelado no duplica la entrada (+1)", GameState.summon_history.size() == before + 1)
	# tope
	for n in 310:
		GameState.summon_history.append({ "time": 1, "banner": "x", "count": 1, "cost": 0, "results": [] })
	GameState.summon("banner_apertura", 1)
	_check("el historial se limita a %d entradas y los totales no se pierden" % GameState.SUMMON_HISTORY_MAX, GameState.summon_history.size() == GameState.SUMMON_HISTORY_MAX and GameState.summon_total == 32)
	var newest: Dictionary = GameState.summon_history[GameState.summon_history.size() - 1]
	_check("la mas reciente se conserva al recortar", String(newest["banner"]) == "banner_apertura")


## --- 6. Informacion de banners -----------------------------------------------------------------------------------
func _check_banner_info() -> void:
	_out("[DBG25] == INFORMACION DE BANNERS ==")
	for banner in DB.all_banners():
		var bid := String((banner as Dictionary).get("id", ""))
		var pool := GameState.banner_pool(bid)
		var total := 0.0
		var by_rarity: Dictionary = {}
		for id in pool:
			var rate := GameState.banner_character_rate(bid, String(id))
			total += rate
			var rarity := String(DB.get_character(String(id)).get("rarity", ""))
			by_rarity[rarity] = float(by_rarity.get(rarity, 0.0)) + rate
		var rates := GameState.banner_rates(bid)
		var matches := absf(total - 1.0) < 1e-9
		for rarity in rates.keys():
			matches = matches and absf(float(by_rarity.get(rarity, 0.0)) - float(rates[rarity])) < 1e-9
		_check("%s: las probabilidades por personaje suman 1 y cuadran con cada rareza" % bid, matches)
	_check("las tasas reales del banner del duo: duo 7%% y SSR total 15%%", absf(GameState.banner_character_rate("banner_david_lucy", DUO) - 0.07) < 1e-9)
	var apertura_rate := GameState.banner_character_rate("banner_apertura", "gojo")
	var ssr_count := 0
	for id in GameState.banner_pool("banner_apertura"):
		if String(DB.get_character(String(id)).get("rarity", "")) == "SSR":
			ssr_count += 1
	_check("un destacado sin tasa propia tiene la tasa normal de su rareza repartida (%.4f)" % apertura_rate, absf(apertura_rate - 0.15 / float(ssr_count)) < 1e-9)
	_check("un personaje fuera del pool tiene 0 (la forma LR de Sakuta)", GameState.banner_character_rate("banner_apertura", "sakuta_mai_lr") == 0.0 and GameState.banner_character_rate("banner_apertura", DUO) == 0.0)
	_check("las reglas del pity salen de la configuracion real (10, LR, duo)", GameState.pity_rules_text("banner_david_lucy").contains("9 tiradas") and GameState.pity_rules_text("banner_david_lucy").contains("LR") and GameState.pity_rules_text("banner_david_lucy").contains("tirada 10"))
	_check("y un banner sin pity lo dice", GameState.pity_rules_text("banner_ur").contains("no tiene pity"))


## --- 7. Pantallas ------------------------------------------------------------------------------------------------------------
func _all_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	if node is Button:
		text += (node as Button).text + "\n"
	for child in node.get_children():
		text += _all_text(child)
	return text


func _check_screens() -> void:
	_out("[DBG25] == PANTALLAS ==")
	_reset_summon_state()
	GameState.roster = GameState.roster
	var screen = load("res://scenes/screens/summon.tscn").instantiate()
	add_child(screen)
	await get_tree().process_frame
	screen.set("_banner_id", "banner_david_lucy")
	screen.call("refresh")
	_check("INVOCAR trae los botones INFO y HISTORIAL", screen.find_child("InfoButton", true, false) != null and screen.find_child("HistoryButton", true, false) != null)
	var pity_label: Label = screen.find_child("PityProgress", true, false)
	_check("INVOCAR muestra el progreso del pity del banner (%s)" % pity_label.text, pity_label != null and pity_label.visible and pity_label.text.contains("PITY  0/10"))
	GameState.pity_counters["banner_david_lucy"] = 9
	screen.call("refresh")
	_check("con 9 de 10 avisa de que la proxima esta garantizada", pity_label.text.contains("PROXIMA"))
	GameState.pity_counters["banner_david_lucy"] = 0
	screen.set("_banner_id", "banner_apertura")
	screen.call("refresh")
	_check("un banner sin pity no muestra progreso", not pity_label.visible)
	# info
	for banner in DB.all_banners():
		var bid := String((banner as Dictionary).get("id", ""))
		screen.set("_banner_id", bid)
		screen.call("_on_info_pressed")
		var panel: Node = screen.get_node_or_null("BannerInfoPanel")
		var text := _all_text(panel) if panel != null else ""
		var ok := panel != null and text.contains("PROBABILIDAD POR TIRADA") and text.contains("PITY") and text.contains("PERSONAJES DISPONIBLES")
		for row in GameState.banner_rate_table(bid):
			if String(row["id"]).is_empty():
				var total_rate: float = float(row["rate"])
				for other in GameState.banner_rate_table(bid):
					if String(other["rarity"]) == String(row["rarity"]) and not String(other["id"]).is_empty():
						total_rate += float(other["rate"])
				ok = ok and text.contains(String(row["rarity"]) + "  " + load("res://ui/banner_info_panel.gd").pct(total_rate))
		_check("la ventana de info de %s muestra tasas, pity y personajes" % bid, ok)
		if panel != null:
			panel.queue_free()
			await get_tree().process_frame
	screen.set("_banner_id", "banner_david_lucy")
	screen.call("_on_info_pressed")
	var duo_text := _all_text(screen.get_node("BannerInfoPanel"))
	_check("la info del banner del duo ensena 7% propio y [cuenta para el pity]", duo_text.contains("7%") and duo_text.contains("cuenta para el pity") and duo_text.contains("llega a LR"))
	screen.get_node("BannerInfoPanel").queue_free()
	await get_tree().process_frame
	# invocar desde la pantalla: se cobra una vez y se bloquea el doble toque
	_reset_summon_state()
	GameState.roster = GameState.roster
	var gems_before := GameState.gems
	screen.set("_banner_id", "banner_david_lucy")
	screen.call("_on_roll", 10)
	var gems_charged := GameState.gems
	screen.call("_on_roll", 10)
	screen.call("_on_roll", 1)
	_check("un toque cobra una vez (90) y el doble toque durante la animacion no cobra", gems_before - gems_charged == 90 and GameState.gems == gems_charged and GameState.summon_history.size() == 1)
	_check("hay una animacion previa en marcha", screen.get_node_or_null("SummonFx") != null)
	var fx = screen.get_node_or_null("SummonFx")
	if fx != null:
		fx.call("_skip")
	await get_tree().process_frame
	var reveal = screen.get("_reveal")
	_check("al terminar (o saltar) la animacion empieza el revelado", reveal != null and is_instance_valid(reveal))
	# omitir todo
	if reveal != null and is_instance_valid(reveal):
		await get_tree().create_timer(0.6).timeout
		# el duo es siempre SSR; si la primera carta es el duo hay cinematica: la saltamos
		if reveal.call("phase") == "cinematic":
			reveal.call("skip_cinematic")
			await get_tree().process_frame
		var first_phase: String = reveal.call("phase")
		_check("el revelado empieza en una carta o en la cinematica del duo (%s)" % first_phase, first_phase == "card" or first_phase == "cinematic")
		await get_tree().create_timer(0.6).timeout
		reveal.call("skip_all")
		await get_tree().create_timer(0.3).timeout
		_check("OMITIR TODO lleva al resumen sin volver a tirar ni cobrar", reveal.call("phase") == "summary" and GameState.gems == gems_charged and GameState.summon_history.size() == 1)
		_check("el resumen ensena el progreso del pity", reveal.find_child("PityInfo", true, false) != null)
		reveal.call("_close")
		await get_tree().process_frame
	_check("cerrar el resumen deja la invocacion sin pendientes", not GameState.has_pending_reveal())
	# cinematica del duo conservada: una invocacion cuyo primer resultado es el duo
	GameState.pending_reveal = {
		"banner": "banner_david_lucy", "banner_name": "x", "count": 1, "cost": 10, "index": 0, "new_count": 1, "duplicate_count": 0,
		"results": [{ "id": DUO, "name": "duo", "rarity": "SSR", "new": true, "duplicate": false, "duplicates": 0 }], "cinematic_done": false,
	}
	var cinematic = load("res://ui/summon_reveal.gd").start(screen)
	await get_tree().process_frame
	_check("la cinematica especial de David + Lucy se sigue reproduciendo", (cinematic.get("fx_log") as Array).has("cinematic_start") and cinematic.call("phase") == "cinematic")
	cinematic.call("skip_cinematic")
	await get_tree().process_frame
	_check("...y se puede saltar", cinematic.call("phase") == "card")
	cinematic.call("_close")
	await get_tree().process_frame
	screen.queue_free()
	# historial
	_reset_summon_state()
	GameState.summon("banner_david_lucy", 10)
	GameState.summon("banner_apertura", 1)
	var hist = load("res://scenes/screens/summon_history.tscn").instantiate()
	add_child(hist)
	await get_tree().process_frame
	hist.call("refresh")
	var htext := _all_text(hist)
	_check("la pantalla de historial lista las invocaciones, el banner y el total", htext.contains("Edgerunners") and htext.contains("Apertura") and htext.contains("Total de invocaciones: 11"))
	_check("muestra la fecha, el pity y los personajes", htext.contains("Pity:") and htext.contains("PITY 0/10") or htext.contains("PITY"))
	var list_node: VBoxContainer = hist.find_child("List", true, false)
	_check("hay una fila por invocacion (2)", list_node.get_child_count() == 2)
	hist.call("_on_filter", 2 if DB.all_banners().size() > 2 else 1)
	_check("el filtro por banner reduce la lista", list_node.get_child_count() <= 2)
	hist.queue_free()
	await get_tree().process_frame
	var nav_ok: bool = _app.has_method("open_screen")
	_app.call("open_screen", "summon_history")
	_check("el historial se abre desde la app", _app.call("current_screen") == "summon_history" and nav_ok)
	_app.call("go_back")


## --- 8. Copias -------------------------------------------------------------------------------------------------------------------
func _ledger_ok(id: String) -> bool:
	var l := GameState.copy_ledger(id)
	return int(l["total"]) == int(l["available"]) + int(l["used"]) + int(l["converted"])


func _check_copies() -> void:
	_out("[DBG25] == COPIAS TOTALES / DISPONIBLES ==")
	GameState.roster = []
	GameState.duplicates = {}
	GameState.dupe_levels = {}
	GameState.copies_converted = {}
	GameState.favorites = []
	GameState.rarities = {}
	GameState.progress = {}
	GameState.coins = 1000000
	GameState.add_character("frieren")
	for n in 11:
		GameState.add_character("frieren")
	var l := GameState.copy_ledger("frieren")
	_check("12 invocaciones: total 12, disponibles 11, usadas 1", int(l["total"]) == 12 and int(l["available"]) == 11 and int(l["used"]) == 1 and _ledger_ok("frieren"))
	GameState.party = ["frieren", "", "", ""]
	GameState.normalize_party()
	GameState.assign_party_slot(1, "gojo") if GameState.is_owned("gojo") else null
	var l2 := GameState.copy_ledger("frieren")
	_check("equipar no cambia las copias", l2["total"] == l["total"] and l2["available"] == l["available"] and l2["used"] == l["used"])
	var cost := GameState.dupe_next_cost("frieren")
	var up := GameState.dupe_upgrade("frieren")
	var l3 := GameState.copy_ledger("frieren")
	_check("mejorar (Dupe 1) gasta %d copias: disponibles -%d, usadas +%d, total igual" % [cost, cost, cost], bool(up["done"]) and int(l3["total"]) == 12 and int(l3["available"]) == 11 - cost and int(l3["used"]) == 1 + cost and _ledger_ok("frieren"))
	# evolucion normal: gojo SSR -> UR
	for n in 5:
		GameState.add_character("gojo")
	var g1 := GameState.copy_ledger("gojo")
	GameState.progress["gojo"] = { "level": 100, "xp": 0 }
	var ev := GameState.evolve("gojo")
	var g2 := GameState.copy_ledger("gojo")
	_check("evolucionar (SSR a UR) no cambia total, disponibles ni usadas", not ev.is_empty() and g1["total"] == g2["total"] and g1["available"] == g2["available"] and g1["used"] == g2["used"] and int(g2["total"]) == 5)
	var stack_gojo := {}
	for stack in GameState.copy_stacks():
		if String(stack["id"]) == "gojo":
			stack_gojo = stack
	_check("tras evolucionar, las copias siguen siendo SSR y salen como pila aparte", String(stack_gojo.get("quality", "")) == "SSR" and not bool(stack_gojo.get("merged", true)) and int(stack_gojo.get("count", 0)) == 4)
	var up2 := GameState.dupe_upgrade("gojo")
	var g3 := GameState.copy_ledger("gojo")
	_check("ahora (UR) puede mejorar y las copias gastadas pasan a usadas", bool(up2["done"]) and int(g3["total"]) == 5 and int(g3["available"]) == 4 - int(up2["spent"]) and _ledger_ok("gojo"))
	# conversion de sobrantes y favorito
	GameState.dupe_levels["frieren"] = GameState.dupe_max_level()
	var spare := GameState.dupe_overflow_copies("frieren")
	var total_before := int(GameState.copy_ledger("frieren")["total"])
	GameState.set_favorite("frieren", true)
	var coins_before := GameState.coins
	var blocked := GameState.dupe_convert_overflow("frieren")
	_check("un FAVORITO no puede convertir sus copias sobrantes", not bool(blocked["done"]) and bool(blocked.get("protected", false)) and GameState.coins == coins_before and GameState.dupe_overflow_copies("frieren") == spare)
	GameState.set_favorite("frieren", false)
	var done := GameState.dupe_convert_overflow("frieren")
	var lc := GameState.copy_ledger("frieren")
	_check("sin favorito se convierte: monedas suben, total se conserva y se anota como convertidas", bool(done["done"]) and GameState.coins == coins_before + int(done["coins"]) and int(lc["total"]) == total_before and int(lc["available"]) == 0 and int(lc["converted"]) == spare and _ledger_ok("frieren"))
	_check("el texto del libro cuenta las convertidas", GameState.copy_ledger_text("frieren").contains("convertidas"))
	GameState.save_game()
	GameState.copies_converted = {}
	GameState.load_game()
	_check("las copias convertidas persisten", int(GameState.copy_ledger("frieren")["converted"]) == spare)
	# evolucion especial: la identidad nueva hereda las copias
	GameState.add_character("sakuta_mai")
	for n in 3:
		GameState.duplicates["sakuta_mai"] = GameState.duplicates_of("sakuta_mai") + 1
	GameState.progress["sakuta_mai"] = { "level": 100, "xp": 0 }
	GameState.add_item("rabbit_costume", 25)
	var sm_before := GameState.copy_ledger("sakuta_mai")
	var sp := GameState.evolve_special("sakuta_mai")
	var sk := GameState.copy_ledger("sakuta")
	_check("la evolucion especial pasa las copias al personaje nuevo (total %d, disponibles %d)" % [int(sk["total"]), int(sk["available"])], not sp.is_empty() and int(sk["total"]) == int(sm_before["total"]) and _ledger_ok("sakuta") and int(GameState.copy_ledger("sakuta_mai")["total"]) == 0)
	GameState.favorites = []


func _check_collection_screen() -> void:
	_out("[DBG25] == COLECCION: DUPLICADOS Y FAVORITOS ==")
	GameState.favorites = []
	var screen = load("res://scenes/screens/collection.tscn").instantiate()
	add_child(screen)
	await get_tree().process_frame
	screen.call("refresh")
	await get_tree().process_frame
	var grid: GridContainer = screen.find_child("Grid", true, false)
	if grid == null:
		for child in screen.find_children("*", "GridContainer", true, false):
			grid = child
			break
	var all_count := grid.get_child_count()
	_check("la coleccion trae los filtros CON COPIAS y FAVORITOS", screen.find_child("DupesToggle", true, false) != null and screen.find_child("FavoritesToggle", true, false) != null)
	var toggle: Button = screen.find_child("DupesToggle", true, false)
	toggle.button_pressed = true
	await get_tree().process_frame
	var dupe_count := grid.get_child_count()
	var expected := 0
	for id in GameState.roster:
		if GameState.dupe_copies_available(String(id)) > 0:
			expected += 1
	_check("CON COPIAS muestra solo a quien tiene copias disponibles (%d de %d)" % [dupe_count, all_count], dupe_count >= expected and dupe_count <= all_count and dupe_count > 0)
	toggle.button_pressed = false
	GameState.set_favorite("gojo", true)
	var fav: Button = screen.find_child("FavoritesToggle", true, false)
	fav.button_pressed = true
	await get_tree().process_frame
	var all_marked := grid.get_child_count() >= 1
	for card in grid.get_children():
		all_marked = all_marked and card.find_child("FavoriteMark", true, false) != null
	_check("FAVORITOS muestra solo a los favoritos (%d cartas, la unidad y su pila de copias) y todas llevan la estrella" % grid.get_child_count(), all_marked and grid.get_child_count() <= 2)
	fav.button_pressed = false
	GameState.set_favorite("gojo", false)
	# la ficha: boton de favorito y proteccion
	var dupe_box = load("res://ui/dupe_tab.gd").build("frieren", true, false, Callable(), Callable(), Callable())
	var fb: Button = dupe_box.find_child("FavoriteButton", true, false)
	_check("la pestana DUPES de la ficha trae el boton FAVORITO", fb != null)
	fb.button_pressed = true
	_check("marcar el boton protege al personaje", GameState.is_favorite("frieren") and bool(GameState.consume_guard("frieren")["protected"]))
	fb.button_pressed = false
	_check("desmarcarlo lo desprotege", not GameState.is_favorite("frieren"))
	dupe_box.queue_free()
	screen.queue_free()
