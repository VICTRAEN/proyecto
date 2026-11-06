extends Node

## COMPROBACIONES EN EJECUCION DE LA X.6 (dominio). SOLO pruebas.
## Arranque:  godot --headless --path . -- --dbg32   (escribe res://dbg32_resultados.txt)
## Ningun personaje real tiene dominio: aqui se INYECTA una definicion de prueba en la copia
## de datos que recibe el combate (nunca en los JSON ni en GameState).

const RESULTS_PATH := "res://dbg32_resultados.txt"
const BattleManager := preload("res://core/battle_manager.gd")
const CombatUnit := preload("res://core/combat_unit.gd")

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
	_out("[DBG32] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func run(app: Node) -> void:
	_app = app
	await _wait(0.3)
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	seed(3232)
	_out("[DBG32] --- comprobaciones X.6 (dominio) ---")
	_app.call("_backup_save")
	_fresh()
	_check_data()
	_check_unit_and_matching()
	await _check_battle_manual()
	await _check_rules()
	await _check_auto_no_domain()
	await _check_ui()
	_check_save_compat()
	_app.call("_restore_save")
	_out("[DBG32] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _fresh() -> void:
	GameState.roster = GameState.STARTING_ROSTER.duplicate()
	GameState.progress = {}
	GameState.rarities = {}
	GameState.duplicates = {}
	GameState.inventory = {}
	GameState.party = GameState.roster.slice(0, 4)
	GameState.tower_team = ["", "", "", "", ""]
	GameState.ensure_defaults()
	GameState.reset_battle_context()
	for id in GameState.roster:
		GameState.set_level(String(id), 60)
	GameState.save_game()


## Dominio de prueba: refuerza a la categoria de la unidad 1 (aliados) y debilita a todos los rivales.
func _def(boost_cat: String) -> Dictionary:
	return {
		"id": "test_domain", "name": "DOMINIO DE PRUEBA", "color": "#aa0033", "cost": 0, "duration_rounds": 0,
		"background": "res://art/backgrounds/battle.webp",
		"effects": [
			{ "side": "allies", "categories": [boost_cat], "stat_multiplier": 1.5, "stats": ["atk", "def"] },
			{ "side": "foes", "all": true, "stat_multiplier": 0.5, "stats": ["atk"] },
		],
	}


func _enemies() -> Array:
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_004_01", "difficulty": "normal" })
	return GameState.enemy_data()


func _cat_of(id: String) -> String:
	var cats: Array = GameState.character_data(id).get("categories", [])
	return String(cats[0]) if not cats.is_empty() else "x"


func _party(domain_for: Array, cat: String) -> Array:
	var out: Array = []
	for id in GameState.roster.slice(0, 3):
		var d: Dictionary = GameState.character_data(String(id)).duplicate(true)
		if domain_for.has(String(id)):
			d["domain"] = _def(cat)
		out.append(d)
	return out


func _check_data() -> void:
	var dir := DirAccess.open("res://data/characters")
	var with_d := 0
	var total := 0
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		total += 1
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/" + f))
		if parsed is Dictionary:
			var d = (parsed as Dictionary).get("domain", {})
			if d is Dictionary and not (d as Dictionary).is_empty():
				with_d += 1
	_check("ningun personaje real tiene dominio (%d revisados)" % total, with_d == 0 and total > 0)


func _check_unit_and_matching() -> void:
	var id0 := String(GameState.roster[0])
	var cat := _cat_of(id0)
	var base: Dictionary = GameState.character_data(id0).duplicate(true)
	var plain := CombatUnit.new()
	plain.setup(base, true, 0)
	_check("sin dominio: no puede abrirlo", not plain.has_domain() and not plain.can_open_domain())
	var d1 := base.duplicate(true)
	d1["domain"] = _def(cat)
	var foe := CombatUnit.new()
	foe.setup(d1, false, 0)
	_check("un enemigo con dominio no lo recibe", not foe.has_domain())
	var u := CombatUnit.new()
	u.setup(d1, true, 0)
	_check("con dominio: can_open_domain", u.has_domain() and u.can_open_domain())
	var d2 := base.duplicate(true)
	d2["domain"] = { "name": "sin id" }
	var u2 := CombatUnit.new()
	u2.setup(d2, true, 0)
	_check("dominio sin id se ignora", not u2.has_domain())
	var d3 := base.duplicate(true)
	var dd := _def(cat)
	dd["cost"] = 3
	d3["domain"] = dd
	var u3 := CombatUnit.new()
	u3.setup(d3, true, 0)
	u3.sp = 1
	_check("el coste de SP se respeta", not u3.can_open_domain())
	u3.sp = 3
	_check("con SP suficiente puede", u3.can_open_domain())
	_check("sin ataque: domain_attack vacio", u.domain_attack().is_empty())
	var d4 := base.duplicate(true)
	var d4d := _def(cat)
	d4d["attack"] = { "power": 80 }
	d4["domain"] = d4d
	var u4 := CombatUnit.new()
	u4.setup(d4, true, 0)
	var at := u4.domain_attack()
	_check("ataque del dominio normalizado (special, coste 0, enemy_all)", String(at.get("kind", "")) == "special" and int(at.get("cost", -1)) == 0 and String(at.get("target", "")) == "enemy_all")


func _snap(u) -> String:
	return "%s|%s|%s|%s" % [u.attack(), u.defense(), u.speed(), u.max_hp()]


## Combate manual: el jugador abre el dominio. Se congela despues para inspeccionar el estado.
func _check_battle_manual() -> void:
	var first := String(GameState.roster[0])
	var cat := _cat_of(first)
	var m := BattleManager.new()
	add_child(m)
	m.setup(_party([first], cat), _enemies(), [])
	m.pause_scale = 0.0
	m.set_auto(false)
	var ctx := { "did": false, "release": false, "before": {}, "enemy_before": [], "started": 0, "ended": [] }
	var done := [false]
	m.domain_started.connect(func(_u, _d): ctx["started"] += 1)
	m.domain_ended.connect(func(_u, _d, r): ctx["ended"].append(r))
	m.battle_finished.connect(func(_v, _r): done[0] = true)
	m.action_requested.connect(func(u):
		if not ctx["did"] and u.id == first and m.can_domain(u):
			ctx["did"] = true
			var b := {}
			for a in m.allies:
				b[a.id] = _snap(a)
			ctx["before"] = b
			var eb := []
			for e in m.enemies:
				eb.append(e.attack())
			ctx["enemy_before"] = eb
			m.submit_action.call_deferred({ "kind": "domain", "target_key": "" })
		elif not ctx["did"] or ctx["release"]:
			var tk := ""
			for e in m.enemies:
				if e.alive:
					tk = e.source_key
					break
			m.submit_action.call_deferred({ "kind": "basic", "target_key": tk })
	)
	m.start_battle()
	for i in 600:
		if done[0] or (ctx["did"] and ctx["started"] > 0 and i > 10):
			break
		await _wait(0.03)
	_check("el dominio se abre una vez", ctx["did"] and ctx["started"] == 1 and not m.active_domain.is_empty() and m.domain_caster != null)
	# Bonus a la categoria
	var boosted_ok := true
	var other_ok := true
	for a in m.allies:
		var inside: bool = (a.categories as Array).has(cat)
		var before_parts: PackedStringArray = String(ctx["before"][a.id]).split("|")
		if inside and absf((a.attack() - float(before_parts[0])) - a.base_stat("atk") * 0.5) > 1.0:
			boosted_ok = false
		if not inside and absf(a.attack() - float(before_parts[0])) > 0.01:
			other_ok = false
	_check("los aliados de la categoria suben (+50% del ataque base)", boosted_ok)
	_check("los aliados de otras categorias no cambian", other_ok)
	var foes_ok := true
	for i in m.enemies.size():
		if not (m.enemies[i].attack() < float(ctx["enemy_before"][i]) * 0.55):
			foes_ok = false
	_check("los rivales bajan (x0.5 atk)", foes_ok)
	_check("no se puede abrir un segundo dominio", not m.can_domain(m.allies[0]))
	var caster = m.domain_caster
	# Libera y deja que el combate siga hasta el final
	ctx["release"] = true
	m.set_auto(true)
	for i in 1500:
		if done[0]:
			break
		await _wait(0.03)
	_check("el combate termina", done[0])
	_check("el dominio se cierra al terminar (battle_end o caster_down)", m.active_domain.is_empty() and ctx["ended"].size() == 1)
	var clean := true
	for a in m.allies + m.enemies:
		for md in a.stats.mods:
			if String(md["source"]).begins_with("domain:"):
				clean = false
	_check("no queda ningun modificador del dominio", clean)
	m.queue_free()


func _check_rules() -> void:
	var first := String(GameState.roster[0])
	var cat := _cat_of(first)
	# Cae el que lo abrio -> el dominio termina y se limpian los bonus
	var m := BattleManager.new()
	add_child(m)
	m.setup(_party([first], cat), _enemies(), [])
	m.pause_scale = 0.0
	var caster = m.allies[0]
	var ally1 = m.allies[1]
	var base_enemy_atk: float = m.enemies[0].attack()
	var ends := []
	m.domain_ended.connect(func(_u, _d, r): ends.append(r))
	m._do_domain(caster)
	_check("tras abrirlo el rival esta debilitado", m.enemies[0].attack() < base_enemy_atk * 0.55)
	_check("limite por equipo (can_domain falso)", not m.can_domain(caster))
	caster.hp = 0.0
	caster.alive = false
	m._domain_check()
	_check("al caer el lanzador el dominio termina (caster_down)", ends == ["caster_down"] and m.active_domain.is_empty())
	_check("el rival recupera su ataque", absf(m.enemies[0].attack() - base_enemy_atk) < 0.01)
	_check("el cupo del equipo NO se libera", not m.can_domain(ally1))
	m.queue_free()
	# Duracion limitada
	var m2 := BattleManager.new()
	add_child(m2)
	var party := _party([first], cat)
	(party[0]["domain"] as Dictionary)["duration_rounds"] = 2
	m2.setup(party, _enemies(), [])
	var ends2 := []
	m2.domain_ended.connect(func(_u, _d, r): ends2.append(r))
	m2._do_domain(m2.allies[0])
	m2._domain_round_end()
	_check("duracion 2: sigue tras 1 ronda", not m2.active_domain.is_empty())
	m2._domain_round_end()
	_check("duracion 2: termina tras 2 rondas (expired)", ends2 == ["expired"] and m2.active_domain.is_empty())
	m2.queue_free()
	# Filtros: ids, types, side, sin filtro
	var m3 := BattleManager.new()
	add_child(m3)
	m3.setup(_party([], cat), _enemies(), [])
	var a0 = m3.allies[0]
	var e0 = m3.enemies[0]
	_check("filtro ids", m3.domain_matches(a0, { "ids": [a0.id] }) and not m3.domain_matches(m3.allies[1], { "ids": [a0.id] }))
	_check("filtro types", m3.domain_matches(a0, { "types": [a0.type] }) and not m3.domain_matches(a0, { "types": ["__no__"] }))
	_check("side foes/allies", not m3.domain_matches(a0, { "side": "foes", "all": true }) and m3.domain_matches(e0, { "side": "foes", "all": true }) and not m3.domain_matches(e0, { "side": "allies", "all": true }))
	_check("sin filtro afecta a todos", m3.domain_matches(a0, {}) and m3.domain_matches(e0, {}))
	_check("categoria inexistente no afecta", not m3.domain_matches(a0, { "categories": ["__no__"] }))
	# mods sueltos
	var dd := _def(cat)
	dd["effects"] = [{ "side": "allies", "all": true, "mods": [{ "stat": "speed", "kind": "mult", "value": 0.5 }] }]
	var party3 := _party([first], cat)
	party3[0]["domain"] = dd
	var m4 := BattleManager.new()
	add_child(m4)
	m4.setup(party3, _enemies(), [])
	var sp0: float = m4.allies[1].speed()
	m4._do_domain(m4.allies[0])
	_check("mods sueltos (velocidad +50% del base)", absf((m4.allies[1].speed() - sp0) - m4.allies[1].base_stat("speed") * 0.5) < 1.0)
	m4._domain_end("expired")
	_check("al terminar vuelve la velocidad", absf(m4.allies[1].speed() - sp0) < 0.01)
	m4.queue_free()
	# Reserva: el suplente que entra recibe el bonus
	var res_data: Array = [GameState.character_data(String(GameState.roster[3])).duplicate(true)]
	var m5 := BattleManager.new()
	add_child(m5)
	var cat_res := _cat_of(String(GameState.roster[3]))
	var party5 := _party([first], cat_res)
	m5.setup(party5, _enemies(), res_data)
	if m5.reserves.size() > 0:
		var r = m5.reserves[0]
		var r_atk: float = r.attack()
		m5._do_domain(m5.allies[0])
		m5.allies[1].alive = false
		m5.allies[1].hp = 0.0
		m5._rotate_reserves()
		_check("la reserva que entra recibe el dominio", m5.allies[1] == r and absf((r.attack() - r_atk) - r.base_stat("atk") * 0.5) < 1.0)
	else:
		_check("la reserva que entra recibe el dominio (sin reservas, omitido)", true)
	m5.queue_free()
	# Transformacion y dominio conviven
	var party6 := _party([first], cat)
	party6[0]["transformations"] = [{ "id": "t", "stat_multiplier": 1.2 }]
	var m6 := BattleManager.new()
	add_child(m6)
	m6.setup(party6, _enemies(), [])
	var u = m6.allies[0]
	var atk0: float = u.attack()
	m6._do_domain(u)
	m6._do_transform(u)
	_check("dominio + transformacion conviven (se acumulan: +70% del base)", absf((u.attack() - atk0) - u.base_stat("atk") * 0.7) < 1.0)
	m6._revert_transformations()
	m6._domain_end("expired")
	_check("al revertir ambos vuelve al ataque original", absf(u.attack() - atk0) < 0.01)
	m6.queue_free()


func _check_auto_no_domain() -> void:
	var first := String(GameState.roster[0])
	var cat := _cat_of(first)
	var m := BattleManager.new()
	add_child(m)
	m.setup(_party([first], cat), _enemies(), [])
	m.pause_scale = 0.0
	m.set_auto(true)
	var st := { "n": 0 }
	var done := [false]
	m.domain_started.connect(func(_u, _d): st["n"] += 1)
	m.battle_finished.connect(func(_v, _r): done[0] = true)
	m.start_battle()
	for i in 1500:
		if done[0]:
			break
		await _wait(0.03)
	_check("modo auto: abre el dominio y el combate termina", done[0] and st["n"] == 1)
	m.queue_free()
	var m2 := BattleManager.new()
	add_child(m2)
	m2.setup(_party([], cat), _enemies(), [])
	m2.pause_scale = 0.0
	m2.set_auto(true)
	var st2 := { "n": 0 }
	var done2 := [false]
	m2.domain_started.connect(func(_u, _d): st2["n"] += 1)
	m2.battle_finished.connect(func(_v, _r): done2[0] = true)
	m2.start_battle()
	for i in 1500:
		if done2[0]:
			break
		await _wait(0.03)
	_check("combate sin dominios: normal", done2[0] and st2["n"] == 0)
	m2.queue_free()
	# Fondo: ruta directa y fondo provisional de dominio
	var bgs: GDScript = load("res://ui/background.gd")
	_check("load_texture acepta una ruta completa", bgs.load_texture("res://art/backgrounds/battle.webp") != null)
	_check("ruta inexistente -> null (fondo provisional)", bgs.load_texture("res://art/backgrounds/__no__.png") == null)


func _check_ui() -> void:
	var id := String(GameState.roster[0])
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_004_01", "difficulty": "normal" })
	var scene: PackedScene = load("res://scenes/battle/battle.tscn")
	var original = DB.characters.get(id, {})
	var patched: Dictionary = (original as Dictionary).duplicate(true)
	patched["domain"] = _def(_cat_of(id))
	DB.characters[id] = patched
	var ui: Control = scene.instantiate()
	add_child(ui)
	await _wait(0.6)
	var mgr = ui.get("manager")
	_check("UI: el combate arranca", mgr != null)
	if mgr != null:
		mgr.pause_scale = 0.0
		var btn = ui.get("domain_button")
		_check("UI: existe DomainButton", btn != null and ui.find_child("DomainButton", true, false) != null)
		for i in 300:
			var actor = ui.get("current_actor")
			if ui.get("awaiting_input") and actor != null:
				if actor.id == id:
					break
				var tk := ""
				for e in mgr.enemies:
					if e.alive:
						tk = e.source_key
						break
				ui.call("_finish_submit", "basic", tk)
			await _wait(0.05)
		_check("UI: el boton se ve en el turno del capaz", btn != null and btn.visible)
		var bg = ui.get_node_or_null("Background")
		var slot_before := String(bg.get("slot")) if bg != null else ""
		if btn != null and btn.visible:
			btn.emit_signal("pressed")
			await _wait(0.4)
			_check("UI: pulsar abre el dominio", not mgr.active_domain.is_empty())
			_check("UI: el fondo cambia al del dominio", bg != null and String(bg.get("slot")) == "res://art/backgrounds/battle.webp" and String(bg.get("slot")) != slot_before)
			_check("UI: el boton se oculta", not btn.visible)
			mgr._domain_end("expired")
			await _wait(0.2)
			_check("UI: al terminar el dominio vuelve el fondo", bg != null and String(bg.get("slot")) == slot_before)
	DB.characters[id] = original
	ui.queue_free()
	await _wait(0.2)


func _check_save_compat() -> void:
	GameState.save_game()
	var text := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	_check("el guardado no contiene datos de dominio", text.find("DOMINIO DE PRUEBA") == -1 and text.find("test_domain") == -1)
	GameState.load_game()
	_check("el guardado carga igual que antes", GameState.roster.size() > 0)
