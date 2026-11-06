extends Node

## COMPROBACIONES EN EJECUCION DE LA PRIMERA UNIDAD CON TRANSFORMACION: Asta (Union Demoniaca). SOLO pruebas.
## Arranque:  godot --headless --path . -- --dbg33   (escribe res://dbg33_resultados.txt)
## Todo con los DATOS REALES de Asta (nada inyectado), combates reales con BattleManager.

const RESULTS_PATH := "res://dbg33_resultados.txt"
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
	_out("[DBG33] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func run(app: Node) -> void:
	_app = app
	await _wait(0.3)
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	seed(3333)
	_out("[DBG33] --- Asta: Union Demoniaca ---")
	_app.call("_backup_save")
	_fresh()
	_check_data()
	_check_rarity_gate()
	_check_unit()
	await _check_battle()
	await _check_ui()
	_check_save_compat()
	_app.call("_restore_save")
	_out("[DBG33] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _fresh() -> void:
	GameState.roster = ["asta", "gojo", "isagi", "frieren", "mai"]
	GameState.progress = {}
	GameState.rarities = {}
	GameState.duplicates = {}
	GameState.inventory = {}
	GameState.party = ["asta", "gojo", "isagi", "frieren"]
	GameState.tower_team = ["", "", "", "", ""]
	GameState.ensure_defaults()
	GameState.reset_battle_context()
	for id in GameState.roster:
		GameState.set_level(String(id), 60)
	GameState.save_game()


func _asta_data(rarity: String) -> Dictionary:
	GameState.rarities = {} if rarity == "SSR" else { "asta": rarity }
	return GameState.character_data("asta")


func _check_data() -> void:
	var d := DB.get_character("asta")
	var t: Array = d.get("transformations", [])
	_check("Asta declara una transformacion con id", t.size() == 1 and String(t[0].get("id", "")) == "asta_union_demoniaca")
	var def: Dictionary = t[0]
	_check("requiere forma UR", String(def.get("min_rarity", "")) == "UR")
	_check("trae ataque de activacion, 2 habilidades y 3 pasivas", not (def.get("attack", {}) as Dictionary).is_empty() and (def["skills"] as Array).size() == 2 and (def["passives"] as Array).size() == 3)
	var ids := {}
	for f in DirAccess.open("res://data/characters").get_files():
		if f.ends_with(".json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/" + f))
			var tr = (parsed as Dictionary).get("transformations", [])
			if tr is Array and not (tr as Array).is_empty():
				ids[String(parsed["id"])] = true
	_check("Asta es el UNICO personaje con transformacion", ids.keys() == ["asta"])
	_check("carpetas de arte preparadas (ur y transform)", DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://art/characters/asta/ur")) and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://art/characters/asta/transform")))
	_check("el JSON del SSR no se ha tocado (stats base)", int(d["stats"]["max_hp"]) == 1380 and int(d["stats"]["atk"]) == 232 and String(d["rarity"]) == "SSR")


func _check_rarity_gate() -> void:
	for r in ["SSR"]:
		var u := CombatUnit.new()
		u.setup(_asta_data(r), true, 0)
		_check("Asta SSR NO puede transformarse", not u.has_transformation() and not u.can_transform())
	for r in ["UR", "LR"]:
		var u2 := CombatUnit.new()
		u2.setup(_asta_data(r), true, 0)
		_check("Asta %s SI puede transformarse" % r, u2.has_transformation() and u2.can_transform())
	var u3 := CombatUnit.new()
	u3.setup(_asta_data("UR"), false, 0)
	_check("Asta como enemigo no se transforma", not u3.can_transform())
	GameState.rarities = {}


func _snap(u) -> String:
	return JSON.stringify([u.display_name, u.type, u.max_hp(), u.attack(), u.defense(), u.speed(), u.crit_rate(), u.skills, u.passives, u.art, u.roles, u.categories, u.undying, u.visual_form()])


func _check_unit() -> void:
	var u := CombatUnit.new()
	u.setup(_asta_data("UR"), true, 0)
	var before := _snap(u)
	var hp0 := u.hp
	var atk0 := u.attack()
	var def0 := u.defense()
	var spd0 := u.speed()
	var maxhp0 := u.max_hp()
	var crit0 := u.crit_rate()
	u.apply_transformation()
	_check("nombre: Asta & Liebe: Union Demoniaca", u.display_name == "Asta & Liebe: Union Demoniaca")
	_check("estadisticas suben x1.5 (vida, ataque, defensa, velocidad)", absf(u.attack() - atk0 * 1.5) < atk0 * 0.01 and u.max_hp() > maxhp0 * 1.45 and u.defense() > def0 * 1.45 and u.speed() > spd0 * 1.45)
	_check("critico +15 puntos", absf(u.crit_rate() - crit0 - 0.15) < 0.001)
	_check("la vida actual sube con la maxima mas la cura del 25%", u.hp > hp0 + (u.max_hp() - maxhp0) * 0.99)
	_check("habilidades nuevas (Tajo Demoniaco / Divisor Negro)", String(u.skill_by_kind("basic")["name"]) == "Tajo Demoniaco" and String(u.skill_by_kind("special")["name"]) == "Divisor Negro")
	var pids := []
	for p in u.passives:
		pids.append(String(p["id"]))
	_check("pasivas: las de la forma sustituyen a las de UR", pids == ["pas_asta_ud_antimagia", "pas_asta_ud_liebe", "pas_asta_ud_nunca_me_rindo"])
	_check("la forma visual es 'transform'", u.visual_form() == "transform")
	var at := u.transform_attack()
	_check("ataque de activacion: Pacto de Liebe, a todos los rivales, coste 0", String(at["name"]).begins_with("Pacto de Liebe") and String(at["target"]) == "enemy_all" and int(at["cost"]) == 0 and int(at["power"]) == 230)
	u.revert_transformation()
	_check("revert deja a Asta UR exactamente como estaba", _snap(u) == before)


func _party() -> Array:
	var out: Array = []
	for id in GameState.party:
		out.append(GameState.character_data(String(id)))
	return out


func _enemies() -> Array:
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_004_01", "difficulty": "normal" })
	return GameState.enemy_data()


## Combate manual: el jugador transforma a Asta UR. Se congela despues para inspeccionar.
func _check_battle() -> void:
	GameState.rarities = { "asta": "UR" }
	var m := BattleManager.new()
	add_child(m)
	m.setup(_party(), _enemies(), [])
	_tank(m)
	m.pause_scale = 0.0
	m.set_auto(false)
	var ctx := { "did": false, "release": false, "n": 0, "who": [], "before": "", "enemy_hp": 0.0, "capable": [] }
	var done := [false]
	m.transformed.connect(func(u, _d): ctx["n"] += 1; ctx["who"].append(u.id))
	m.battle_finished.connect(func(_v, _r): done[0] = true)
	m.action_requested.connect(func(u):
		if not ctx["did"] and u.id == "asta":
			var capable := []
			for a in m.allies:
				if m.can_transform(a):
					capable.append(a.id)
			ctx["capable"] = capable
			ctx["did"] = true
			ctx["before"] = _snap(u)
			ctx["enemy_hp"] = _hp_total(m)
			m.submit_action.call_deferred({ "kind": "transform", "target_key": "" })
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
		if done[0] or (ctx["did"] and ctx["n"] > 0 and i > 10):
			break
		await _wait(0.03)
	var asta = null
	for a in m.allies:
		if a.id == "asta":
			asta = a
	_check("solo Asta puede transformarse en un equipo de 4", ctx["capable"] == ["asta"])
	_check("Asta se transforma una vez", ctx["n"] == 1 and ctx["who"] == ["asta"] and asta != null and asta.transformed)
	_check("el ataque de activacion hizo dano a los rivales", _hp_total(m) < float(ctx["enemy_hp"]))
	var others_blocked := true
	for a in m.allies:
		if a.id != "asta" and m.can_transform(a):
			others_blocked = false
	_check("ningun otro personaje puede transformarse en este combate", others_blocked and not m.can_transform(asta))
	_check("sigue transformado (ahora mismo)", asta.transformed and asta.display_name == "Asta & Liebe: Union Demoniaca" and asta.visual_form() == "transform")
	_check("la pasiva 'Nunca me rendire' dio una carga de supervivencia", asta.undying >= 1)
	# Muere Asta: el cupo sigue gastado y nadie mas puede
	var saved_hp: float = asta.hp
	ctx["release"] = true
	m.set_auto(true)
	for i in 1500:
		if done[0]:
			break
		await _wait(0.03)
	_check("el combate termina", done[0])
	_check("al terminar Asta vuelve a su estado UR original", not asta.transformed and asta.display_name == "Asta" and asta.visual_form() == "")
	var was: Array = JSON.parse_string(String(ctx["before"]))
	var now: Array = JSON.parse_string(_snap(asta))
	var same := true
	for idx in [0, 1, 2, 7, 8, 9, 10, 11, 12, 13]:
		if JSON.stringify(was[idx]) != JSON.stringify(now[idx]):
			same = false
			_out("   diferencia en campo %d: %s -> %s" % [idx, JSON.stringify(was[idx]), JSON.stringify(now[idx])])
	_check("nombre, tipo, vida maxima, habilidades, pasivas, arte, roles, categorias y cargas = los de antes de transformar", same)
	m.queue_free()
	# Equipo SIN Asta UR: nadie se transforma
	GameState.rarities = {}
	var m2 := BattleManager.new()
	add_child(m2)
	m2.setup(_party(), _enemies(), [])
	m2.pause_scale = 0.0
	m2.set_auto(true)
	var st := { "n": 0 }
	var d2 := [false]
	m2.transformed.connect(func(_u, _d): st["n"] += 1)
	m2.battle_finished.connect(func(_v, _r): d2[0] = true)
	m2.start_battle()
	for i in 1500:
		if d2[0]:
			break
		await _wait(0.03)
	_check("con Asta SSR el combate es el de siempre (sin transformaciones)", d2[0] and st["n"] == 0)
	m2.queue_free()
	# Auto con Asta UR: se transforma solo una vez
	GameState.rarities = { "asta": "UR" }
	var m3 := BattleManager.new()
	add_child(m3)
	m3.setup(_party(), _enemies(), [])
	m3.pause_scale = 0.0
	m3.set_auto(true)
	var st3 := { "n": 0 }
	var d3 := [false]
	m3.transformed.connect(func(_u, _d): st3["n"] += 1)
	m3.battle_finished.connect(func(_v, _r): d3[0] = true)
	m3.start_battle()
	for i in 1500:
		if d3[0]:
			break
		await _wait(0.03)
	_check("modo auto: Asta UR se transforma una vez y el combate termina", d3[0] and st3["n"] == 1)
	m3.queue_free()
	# La muerte de Asta transformado: la forma dura hasta morir
	GameState.rarities = { "asta": "UR" }
	var m4 := BattleManager.new()
	add_child(m4)
	m4.setup(_party(), _enemies(), [])
	var a4 = m4.allies[0]
	m4._do_transform(a4)
	a4.undying = 0
	a4.take_damage(a4.max_hp() * 10.0) if a4.has_method("take_damage") else null
	_check("Asta transformado muere como cualquier unidad", not a4.alive and a4.transformed)
	_check("tras su muerte nadie mas puede transformarse", not m4.can_transform(m4.allies[1]))
	m4._revert_transformations()
	_check("y al terminar el combate la forma se limpia aunque haya muerto", not a4.transformed)
	m4.queue_free()
	GameState.rarities = {}


## Enemigos muy duros: la activacion (230% a todos) no debe acabar el combate antes de inspeccionarlo.
func _tank(m) -> void:
	for e in m.enemies:
		e.stats.base["max_hp"] = float(e.stats.base["max_hp"]) * 200.0
		e.hp = e.max_hp()


func _hp_total(m) -> float:
	var t := 0.0
	for e in m.enemies:
		t += e.hp
	return t


## UI real con datos reales: el boton solo aparece en el turno de Asta UR.
func _check_ui() -> void:
	GameState.rarities = { "asta": "UR" }
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_004_01", "difficulty": "normal" })
	var scene: PackedScene = load("res://scenes/battle/battle.tscn")
	var ui: Control = scene.instantiate()
	add_child(ui)
	await _wait(0.6)
	var mgr = ui.get("manager")
	_check("UI: el combate arranca", mgr != null)
	if mgr != null:
		mgr.pause_scale = 0.0
		_tank(mgr)
		var btn = ui.get("transform_button")
		var saw_on_other := false
		for i in 400:
			var actor = ui.get("current_actor")
			if ui.get("awaiting_input") and actor != null:
				if actor.id == "asta":
					break
				if btn != null and btn.visible:
					saw_on_other = true
				var tk := ""
				for e in mgr.enemies:
					if e.alive:
						tk = e.source_key
						break
				ui.call("_finish_submit", "basic", tk)
			await _wait(0.05)
		_check("UI: el boton NO aparece en los turnos de otros personajes", not saw_on_other)
		_check("UI: el boton aparece en el turno de Asta UR", btn != null and btn.visible)
		if btn != null and btn.visible:
			btn.emit_signal("pressed")
			await _wait(0.5)
			_check("UI: pulsarlo transforma a Asta", mgr.transformed_unit != null and mgr.transformed_unit.id == "asta" and mgr.transformed_unit.transformed)
			var card_ok := false
			for c in ui.get("cards").values():
				if is_instance_valid(c) and c.unit == mgr.transformed_unit:
					card_ok = c.name_label.text == "Asta & Liebe: Union Demoniaca"
			_check("UI: la tarjeta muestra el nombre de la forma", card_ok)
			_check("UI: el boton desaparece", not btn.visible)
	ui.queue_free()
	await _wait(0.2)
	GameState.rarities = {}
	# SSR: ni siquiera existe el boton visible en su turno
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_004_01", "difficulty": "normal" })
	var ui2: Control = scene.instantiate()
	add_child(ui2)
	await _wait(0.6)
	var mgr2 = ui2.get("manager")
	var btn2 = ui2.get("transform_button")
	var seen := false
	if mgr2 != null:
		mgr2.pause_scale = 0.0
		for i in 120:
			var actor2 = ui2.get("current_actor")
			if ui2.get("awaiting_input") and actor2 != null:
				if btn2 != null and btn2.visible:
					seen = true
				var tk2 := ""
				for e in mgr2.enemies:
					if e.alive:
						tk2 = e.source_key
						break
				ui2.call("_finish_submit", "basic", tk2)
			await _wait(0.05)
	_check("UI: con Asta SSR el boton no aparece nunca", not seen)
	ui2.queue_free()
	await _wait(0.2)


func _check_save_compat() -> void:
	GameState.rarities = { "asta": "UR" }
	GameState.save_game()
	var text := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	_check("el guardado no contiene la transformacion ni sus habilidades", text.find("union_demoniaca") == -1 and text.find("Divisor Negro") == -1 and text.find("transform") == -1)
	GameState.rarities = {}
	GameState.load_game()
	_check("el guardado carga igual que antes", GameState.roster.size() > 0)
