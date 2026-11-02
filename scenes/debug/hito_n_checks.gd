extends Node

## COMPROBACIONES EN EJECUCION DE LA v16 / X.1 (banners diarios, 3% destacado, perfil,
## vitrina y personalizacion). SOLO pruebas.  Arranque: godot --headless --path . -- --dbg28

const RESULTS_PATH := "res://dbg28_resultados.txt"
const Families := preload("res://core/families.gd")
const DUO := "david_lucy_duo"
## 2026-11-02 12:00 UTC (lunes). start_date del calendario = 2026-11-02.
const DAY0 := 1793620800

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
	_out("[DBG28] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func run(app: Node) -> void:
	_app = app
	await _wait(0.3)
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	seed(2828)
	_out("[DBG28] --- comprobaciones v16 / X.1 ---")
	_app.call("_backup_save")
	_fresh()
	_check_rotation()
	_check_probabilities()
	_check_summon_gating()
	_check_profile_stats()
	_check_ownership()
	_check_showcase_forms()
	_check_customization()
	_check_save_compat()
	await _check_screens()
	_app.call("_restore_save")
	_out("[DBG28] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _fresh() -> void:
	GameState.roster = GameState.STARTING_ROSTER.duplicate()
	GameState.progress = {}
	GameState.party = []
	GameState.rarities = {}
	GameState.duplicates = {}
	GameState.dupe_levels = {}
	GameState.completed_stages = []
	GameState.coins = 100000
	GameState.gems = 100000
	GameState.ensure_defaults()
	GameState.meta.from_dict({})
	GameState.meta.now_override = DAY0
	GameState.account.from_dict({ "xp": 0 })
	GameState.profile.from_dict({})


func _day(offset: int) -> void:
	GameState.meta.now_override = DAY0 + offset * 86400


## --- 1. Rotacion por fecha ---------------------------------------------------------
func _check_rotation() -> void:
	_out("[DBG28] == ROTACION ==")
	var cycle: Array = DB.rotating_banners()
	_check("hay 7 banners diarios en el ciclo", cycle.size() == 7)
	var seen := {}
	for i in 7:
		_day(i)
		seen[GameState.daily_banner_id()] = true
	_check("7 dias seguidos = 7 banners distintos", seen.size() == 7)
	_day(0)
	var d0 := GameState.daily_banner_id()
	_day(7)
	_check("el ciclo se repite a los 7 dias", GameState.daily_banner_id() == d0)
	_day(0)
	_check("el dia 0 es el primero del ciclo (orden 0)", d0 == String((cycle[0] as Dictionary)["id"]))
	_check("solo el banner de hoy esta activo", GameState.banner_active(d0) and not GameState.banner_active(String((cycle[1] as Dictionary)["id"])))
	_check("los banners permanentes siempre estan activos", GameState.banner_active("banner_david_lucy") or DB.get_banner("banner_david_lucy").is_empty())
	var avail: Array = GameState.available_banners()
	var rot_in_avail := 0
	for b in avail:
		if GameState.is_rotating_banner(String(b["id"])):
			rot_in_avail += 1
	_check("la lista del jugador trae exactamente 1 banner diario", rot_in_avail == 1 and String((avail[0] as Dictionary)["id"]) == d0)
	_check("pasada la medianoche cambia el banner", (func():
		GameState.meta.now_override = DAY0 + 86400 * 2
		return GameState.daily_banner_id() != d0).call())
	_day(0)
	var sched: Array = GameState.banner_schedule(7)
	_check("el calendario enseña 7 dias con nombre", sched.size() == 7 and String((sched[3] as Dictionary)["name"]) != "")
	_check("texto de rotacion con cuenta atras", GameState.banner_rotation_text(d0).contains("Cambia en"))
	# Un banner nuevo entra en el ciclo solo con su JSON.
	var extra := { "id": "banner_test_extra", "name": "T", "enabled": true, "rotation": { "type": "daily", "order": 99 } }
	DB.banners["banner_test_extra"] = extra
	_check("un banner nuevo con rotation.order entra al ciclo (8)", DB.rotating_banners().size() == 8)
	DB.banners.erase("banner_test_extra")
	_check("y al quitarlo vuelve a 7", DB.rotating_banners().size() == 7)
	# Persistencia: la rotacion no se guarda, solo depende de la fecha.
	GameState.save_game()
	GameState.load_game()
	_check("tras guardar y cargar sigue el mismo banner (solo depende de la fecha)", GameState.daily_banner_id() == d0)
	var sec := GameState.seconds_to_banner_change()
	_check("segundos hasta el cambio entre 1 y 86400", sec >= 1 and sec <= 86400)


## --- 2. Probabilidades ---------------------------------------------------------------
func _check_probabilities() -> void:
	_out("[DBG28] == PROBABILIDADES ==")
	var duo_rate := GameState.banner_character_rate("banner_david_lucy", DUO)
	_check("David y Lucy: 3%% por tirada (%.4f)" % duo_rate, absf(duo_rate - 0.03) < 1e-9)
	for b in DB.rotating_banners():
		var id := String(b["id"])
		var rates := GameState.banner_rates(id)
		_check("%s: sin problemas de datos" % id, GameState.banner_problems(id).is_empty())
		_check("%s: SSR 15%%" % id, absf(float(rates.get("SSR", 0.0)) - 0.15) < 1e-9)
		var total := 0.0
		for row in GameState.banner_rate_table(id):
			total += float(row["rate"])
		_check("%s: la tabla suma 100%% (%.6f)" % [id, total], absf(total - 1.0) < 1e-9)
		var feats: Array = b.get("featured", [])
		var ok := feats.size() > 0
		for f in feats:
			ok = ok and absf(GameState.banner_character_rate(id, String(f)) - 0.03) < 1e-9
		_check("%s: cada destacado 3%%" % id, ok)
	_check("banner del duo sin problemas", GameState.banner_problems("banner_david_lucy").is_empty())
	var text := FileAccess.get_file_as_string("res://data/banners/banner_david_lucy.json")
	_check("el JSON del duo no conserva ningun 7%", not text.contains("7%") and not text.contains("0.07"))
	# Muestreo: destacado ~3% en un diario.
	_day(0)
	var bid := GameState.daily_banner_id()
	var feat := String(((DB.get_banner(bid)["featured"] as Array)[0]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var hits := 0
	var n := 20000
	for i in n:
		if GameState.banner_character_rate(bid, feat) > 0.0 and rng.randf() < GameState.banner_character_rate(bid, feat):
			hits += 1
	_check("muestreo destacado ~3%% (%.3f)" % (float(hits) / n), absf(float(hits) / n - 0.03) < 0.006)


## --- 3. summon() respeta el banner del dia --------------------------------------------
func _check_summon_gating() -> void:
	_out("[DBG28] == INVOCAR ==")
	_day(0)
	var today := GameState.daily_banner_id()
	var other := String((DB.rotating_banners()[3] as Dictionary)["id"])
	var gems := GameState.gems
	var r1: Dictionary = GameState.summon(other, 1)
	_check("invocar en un diario que no toca hoy se rechaza", not bool(r1.get("ok", false)) and GameState.gems == gems)
	var r2: Dictionary = GameState.summon(today, 1)
	_check("invocar en el diario de hoy funciona y cobra", bool(r2.get("ok", false)) and GameState.gems < gems)
	var total := GameState.summon_total
	GameState.summon(today, 10)
	_check("la x10 cuenta 10 tiradas en el historial", GameState.summon_total == total + 10)
	var perm := GameState.summon("banner_david_lucy", 1)
	_check("el banner permanente sigue funcionando", bool(perm.get("ok", false)))


## --- 4. Estadisticas del perfil --------------------------------------------------------
func _check_profile_stats() -> void:
	_out("[DBG28] == ESTADISTICAS ==")
	_fresh()
	GameState.counters["victorias"] = 7
	GameState.counters["combates_jugados"] = 9
	GameState.summon_total = 23
	GameState.completed_stages = ["stage_001", "stage_002"]
	var st: Dictionary = GameState.profile.stats()
	_check("victorias = contador real", int(st["battles_won"]) == 7 and int(st["battles_played"]) == 9)
	_check("invocaciones = summon_total", int(st["summons"]) == 23)
	_check("stages completados = 2", int(st["stages_completed"]) == 2)
	_check("personajes = roster", int(st["characters"]) == GameState.roster.size())
	var sum := 0
	for r in st["by_rarity"]:
		sum += int(st["by_rarity"][r])
	_check("la suma por rareza = personajes", sum == GameState.roster.size())
	GameState.roster.append("deku")
	GameState.roster.append("deku_extra_inexistente")
	_check("al ganar un personaje sube el contador", int(GameState.profile.stats()["characters"]) == GameState.roster.size())
	GameState.roster.erase("deku_extra_inexistente")


## --- 5. Solo se elige lo desbloqueado ---------------------------------------------------
func _check_ownership() -> void:
	_out("[DBG28] == AVATAR, MARCO, TITULO, FAVORITO ==")
	_fresh()
	var p = GameState.profile
	var not_owned := "akaza"
	GameState.roster.erase(not_owned)
	_check("avatar de un personaje que no se tiene: rechazado", not p.set_avatar(not_owned, "ssr") and p.avatar.is_empty())
	_check("favorito de un personaje que no se tiene: rechazado", not p.set_favorite(not_owned, "ssr"))
	var mine := String(GameState.roster[0])
	var root := Families.root_of(mine)
	var forms: Array = p.available_forms(root)
	_check("de un personaje propio hay al menos una forma", forms.size() >= 1)
	var f0 := String((forms[0] as Dictionary)["form"])
	_check("avatar propio aceptado", p.set_avatar(root, f0) and p.is_valid_choice(p.avatar))
	_check("forma inventada rechazada", not p.set_avatar(root, "zz"))
	_check("marco no desbloqueado: rechazado", not p.equip("frame", "frame_oro"))
	GameState.account.grant_cosmetic("frame_oro")
	_check("marco desbloqueado: aceptado", p.equip("frame", "frame_oro"))
	_check("un fondo no se puede poner como marco", not p.equip("frame", "bg_mapa"))
	_check("titulo no ganado rechazado", not GameState.meta.equip_title("title_cuenta_30"))
	_check("titulo por defecto elegible", GameState.meta.equip_title(GameState.meta.DEFAULT_TITLE))
	# Si el personaje desaparece del roster, el avatar guardado deja de ser valido.
	GameState.roster.erase(mine)
	_check("avatar de algo que ya no se tiene deja de ser valido", not p.is_valid_choice(p.avatar))


## --- 6. Vitrina y formas -----------------------------------------------------------------
func _check_showcase_forms() -> void:
	_out("[DBG28] == VITRINA Y FORMAS ==")
	_fresh()
	var p = GameState.profile
	if not GameState.roster.has(DUO):
		GameState.roster.append(DUO)
		GameState.progress[DUO] = { "level": 1, "xp": 0 }
	var root := Families.root_of(DUO)
	var forms: Array = p.available_forms(root)
	var names: Array = []
	for e in forms:
		names.append(String(e["form"]))
	_check("David y Lucy SSR sin evolucionar: solo ofrece SSR (%s)" % str(names), names == ["ssr"])
	_check("el icono UR/LR esta bloqueado", not p.set_avatar(root, "ur") and not p.set_showcase_slot(0, root, "lr"))
	_check("pero el SSR si", p.set_showcase_slot(0, root, "ssr"))
	GameState.rarities[DUO] = "UR"
	names = []
	for e in p.available_forms(root):
		names.append(String(e["form"]))
	_check("tras evolucionar a UR se puede elegir UR (y sigue el SSR): %s" % str(names), names == ["ssr", "ur"])
	_check("LR sigue bloqueado hasta evolucionar de nuevo", not p.set_showcase_slot(1, root, "lr"))
	_check("la forma UR ya es seleccionable", p.set_showcase_slot(1, root, "ur"))
	var view: Array = p.showcase_view()
	_check("la misma familia no ocupa dos huecos (se mueve)", String((view[0] as Dictionary).get("root", "")) != root and String((view[1] as Dictionary)["root"]) == root)
	GameState.rarities.erase(DUO)
	_check("si la forma deja de poseerse, la vitrina la oculta", (p.showcase_view()[1] as Dictionary).is_empty())
	_check("hueco fuera de rango rechazado", not p.set_showcase_slot(5, root, "ssr") and not p.set_showcase_slot(-1, root, "ssr"))
	_check("la vitrina siempre tiene 5 huecos", p.showcase_view().size() == 5)
	# 5 personajes distintos
	var picks := 0
	for r in p.selectable_roots():
		if picks < 5 and p.set_showcase_slot(picks, String(r), String((p.available_forms(String(r))[0] as Dictionary)["form"])):
			picks += 1
	var filled := 0
	for e in p.showcase_view():
		if not (e as Dictionary).is_empty():
			filled += 1
	_check("se pueden llenar los 5 huecos (%d)" % filled, filled == mini(5, p.selectable_roots().size()))
	# Ningun icono mostrado es de una forma sin arte propio bloqueada
	var leaks := 0
	for e in p.showcase_view():
		if not (e as Dictionary).is_empty() and not p.is_valid_choice(e):
			leaks += 1
	_check("ninguna entrada de la vitrina es invalida", leaks == 0)


## --- 7. Personalizacion del menu ----------------------------------------------------------
func _check_customization() -> void:
	_out("[DBG28] == PERSONALIZACION ==")
	_fresh()
	var p = GameState.profile
	var acc = GameState.account
	_check("hay cosmeticos de marco, tema y decoracion", acc.owned_of_type("frame").is_empty() and DB.cosmetics.has("theme_violeta") and DB.cosmetics.has("deco_motas") and DB.cosmetics.has("frame_bronce"))
	_check("tema bloqueado: no se equipa", not p.equip("theme", "theme_violeta"))
	acc.grant_cosmetic("theme_violeta")
	acc.grant_cosmetic("deco_estrellas")
	_check("tema y decoracion desbloqueados se equipan", p.equip("theme", "theme_violeta") and p.equip("decoration", "deco_estrellas"))
	_check("una decoracion no cabe en la ranura de tema", not p.equip("theme", "deco_estrellas"))
	acc.grant_cosmetic("bg_mapa")
	_check("fondo equipado cambia el slot del menu", acc.equip_background("bg_mapa") and acc.menu_background_slot() == "map")
	GameState.save_game()
	p.from_dict({})
	acc.from_dict({})
	_check("(borrado en memoria)", p.equipped_id("theme").is_empty())
	GameState.load_game()
	_check("al cargar siguen el tema, la decoracion y el fondo", p.equipped_id("theme") == "theme_violeta" and p.equipped_id("decoration") == "deco_estrellas" and GameState.account.background_equipped == "bg_mapa")
	# Todo cosmetico nuevo se consigue de verdad por nivel.
	var reachable := {}
	for e in DB.account_config().get("level_rewards", []):
		for id in (e["reward"] as Dictionary).get("cosmetics", []):
			reachable[String(id)] = true
	var lost := 0
	for c in DB.all_cosmetics():
		var t := String(c["type"])
		if ["frame", "theme", "decoration"].has(t) and not reachable.has(String(c["id"])):
			lost += 1
	_check("todos los marcos/temas/decoraciones se ganan en algun nivel", lost == 0)
	# Cosmetico retirado de los datos: se ignora sin romper.
	p.from_dict({ "equipped": { "theme": "theme_inexistente" }, "avatar": { "root": "no_existe", "form": "ssr" } })
	_check("datos obsoletos se descartan", p.equipped_id("theme").is_empty() and p.avatar.is_empty())


## --- 8. Compatibilidad con guardados anteriores ------------------------------------------------
func _check_save_compat() -> void:
	_out("[DBG28] == COMPATIBILIDAD ==")
	_fresh()
	GameState.save_game()
	var f := FileAccess.open("user://save.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	data.erase("profile")
	var coins := int(data.get("coins", GameState.coins))
	var roster_n := (data["roster"] as Array).size() if data.has("roster") else GameState.roster.size()
	var w := FileAccess.open("user://save.json", FileAccess.WRITE)
	w.store_string(JSON.stringify(data))
	w.close()
	_check("un guardado v15 (sin bloque profile) carga", GameState.load_game())
	_check("no pierde monedas ni roster", GameState.coins == coins and GameState.roster.size() == roster_n)
	_check("el perfil empieza vacio con 5 huecos", GameState.profile.avatar.is_empty() and GameState.profile.showcase_view().size() == 5)
	# Niveles ya cobrados antes de que existieran los marcos: se entregan una vez.
	GameState.account.from_dict({ "xp": 5000, "claimed_levels": [3, 6], "bootstrapped": true })
	var given: int = GameState.account.regrant_claimed_cosmetics()
	_check("los niveles ya cobrados dan sus cosmeticos nuevos (%d)" % given, GameState.account.owns_cosmetic("frame_bronce") and GameState.account.owns_cosmetic("theme_violeta"))
	_check("y no se duplican al repetir", GameState.account.regrant_claimed_cosmetics() == 0)


## --- 9. Pantallas -----------------------------------------------------------------------------------
func _check_screens() -> void:
	_out("[DBG28] == PANTALLAS ==")
	_fresh()
	GameState.account.grant_cosmetic("frame_oro")
	GameState.account.grant_cosmetic("deco_motas")
	GameState.account.grant_cosmetic("theme_cian")
	_day(0)
	for sname in ["summon", "profile", "menu_customize", "main_menu"]:
		_app.call("open_screen", sname)
		await _wait(0.4)
		var cur: Node = _app.get("_screens").get(sname) if _app.get("_screens") is Dictionary else null
		_check("pantalla %s abre sin errores" % sname, cur != null)
	_app.call("open_screen", "profile")
	await _wait(0.3)
	var prof: Node = _app.get("_screens").get("profile")
	for n in ["Hero", "Stats", "Showcase", "AvatarButton", "TitleButton", "FrameButton", "FavoriteButton", "CustomizeMenuButton"]:
		_check("el perfil tiene %s" % n, prof.find_child(n, true, false) != null)
	_check("la vitrina tiene 5 huecos", prof.find_child("Showcase", true, false).get_child_count() == 5)
	prof.call("_pick_frame")
	await _wait(0.2)
	var picker := prof.get_node_or_null("Picker")
	_check("el selector de marcos se abre", picker != null)
	if picker != null:
		var b := picker.find_child("Opt_frame_oro", true, false) as Button
		_check("ofrece el marco desbloqueado y no los bloqueados", b != null and picker.find_child("Opt_frame_neon", true, false) == null)
		if b != null:
			b.pressed.emit()
			await _wait(0.3)
			_check("elegir el marco lo equipa", GameState.profile.equipped_id("frame") == "frame_oro")
	_app.call("open_screen", "summon")
	await _wait(0.4)
	var sm: Node = _app.get("_screens").get("summon")
	var tabs := sm.find_child("BannerTabs", true, false)
	_check("la invocacion muestra el diario de hoy + permanentes", tabs != null and tabs.get_child_count() == GameState.available_banners().size())
	_day(1)
	sm.call("refresh")
	await _wait(0.2)
	_check("al cambiar el dia, la pantalla cambia de banner diario", not GameState.banner_active(String(sm.get("_banner_id"))) == false)
