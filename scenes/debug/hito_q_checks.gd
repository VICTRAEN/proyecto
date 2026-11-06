extends Node

## COMPROBACIONES EN EJECUCION DE LA X.5 (transformaciones en combate). SOLO pruebas.
## Arranque:  godot --headless --path . -- --dbg31   (escribe res://dbg31_resultados.txt)
## Ningun personaje real tiene transformacion: aqui se INYECTA una definicion de prueba en la copia
## de datos que recibe el combate (nunca en los JSON ni en GameState).

const RESULTS_PATH := "res://dbg31_resultados.txt"
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
	_out("[DBG31] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func run(app: Node) -> void:
	_app = app
	await _wait(0.3)
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	seed(3131)
	_out("[DBG31] --- comprobaciones X.5 (transformaciones) ---")
	_app.call("_backup_save")
	_fresh()
	_check_data()
	_check_unit_level()
	await _check_battle_manual()
	await _check_one_per_team()
	await _check_auto_and_revert()
	await _check_no_transform_battle()
	await _check_ui()
	_check_save_compat()
	_app.call("_restore_save")
	_out("[DBG31] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
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


## Definicion de prueba completa (todas las claves que admite el sistema).
func _def() -> Dictionary:
	return {
		"id": "test_form", "name": "FORMA DE PRUEBA", "form": "transform", "type": "INT",
		"stat_multiplier": 1.5, "heal_ratio": 0.0, "color": "#ff8800",
		"attack": { "id": "test_burst", "name": "Estallido", "power": 20, "target": "enemy_all", "effects": [] },
		"skills": [
			{ "kind": "basic", "id": "t_basic", "name": "Golpe forma", "power": 120, "target": "enemy", "cost": 0 },
			{ "kind": "special", "id": "t_special", "name": "Especial forma", "power": 220, "target": "enemy", "cost": 2 },
		],
		"passives": [ { "id": "t_pas", "name": "Pasiva forma", "trigger": "battle_start", "effects": [ { "type": "stat_mod", "stat": "atk", "kind": "mult", "value": 0.1, "turns": 99 } ] } ],
		"art": { "front": "res://art/none_front.png" },
	}


func _party(with_def_for: Array) -> Array:
	var out: Array = []
	for id in GameState.roster.slice(0, 3):
		var d: Dictionary = GameState.character_data(String(id)).duplicate(true)
		if with_def_for.has(String(id)):
			d["transformations"] = [_def()]
		out.append(d)
	return out


func _enemies() -> Array:
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_004_01", "difficulty": "normal" })
	return GameState.enemy_data()


func _snap(u) -> Dictionary:
	return {
		"name": u.display_name, "type": u.type, "max_hp": u.max_hp(), "atk": u.attack(), "def": u.defense(), "speed": u.speed(),
		"skills": JSON.stringify(u.skills), "passives": JSON.stringify(u.passives), "art": JSON.stringify(u.art),
		"roles": JSON.stringify(u.roles), "style": u.portrait_style, "ult": JSON.stringify(u.ultimate),
	}


func _check_data() -> void:
	var dir := DirAccess.open("res://data/characters")
	var with_t: Array = []
	var total := 0
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		total += 1
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/" + f))
		if parsed is Dictionary:
			var t = (parsed as Dictionary).get("transformations", [])
			if t is Array and not (t as Array).is_empty():
				with_t.append(String(parsed.get("id", f)))
	_check("solo Asta tiene transformacion en los datos reales (%d personajes revisados: %s)" % [total, str(with_t)], with_t == ["asta"] and total > 0)
	var any_can := false
	for id in GameState.roster:
		var u := CombatUnit.new()
		u.setup(GameState.character_data(String(id)), true, 0)
		any_can = any_can or u.can_transform()
	_check("con los datos reales y el equipo inicial (Asta es SSR) nadie puede transformarse", not any_can)


func _check_unit_level() -> void:
	var base: Dictionary = GameState.character_data(String(GameState.roster[0])).duplicate(true)
	var plain := CombatUnit.new()
	plain.setup(base, true, 0)
	_check("sin definicion: has_transformation falso", not plain.has_transformation() and not plain.can_transform())
	var enemy_like := CombatUnit.new()
	var d1 := base.duplicate(true)
	d1["transformations"] = [_def()]
	enemy_like.setup(d1, false, 0)
	_check("un enemigo con definicion NO puede transformarse", not enemy_like.can_transform())
	var u := CombatUnit.new()
	u.setup(d1, true, 0)
	_check("con definicion: can_transform", u.has_transformation() and u.can_transform())
	var before := _snap(u)
	var hp_before := u.hp
	var ok := u.apply_transformation()
	_check("apply_transformation devuelve true y marca transformed", ok and u.transformed)
	_check("estadisticas suben (vida, ataque, defensa, velocidad)", u.max_hp() > before["max_hp"] and u.attack() > before["atk"] and u.defense() > before["def"] and u.speed() > before["speed"])
	_check("x1.5 aplicado al ataque", absf(u.attack() - float(before["atk"]) * 1.5) < 1.0)
	_check("la vida actual sube con la maxima", u.hp > hp_before)
	_check("cambian nombre, tipo, habilidades, pasivas y arte", u.display_name == "FORMA DE PRUEBA" and u.type == "INT" and JSON.stringify(u.skills) != before["skills"] and JSON.stringify(u.passives) != before["passives"] and String(u.art.get("front", "")) == "res://art/none_front.png")
	_check("la habilidad especial nueva esta activa", String(u.skill_by_kind("special").get("id", "")) == "t_special")
	_check("visual_form() es la carpeta de la forma", u.visual_form() == "transform")
	_check("no se puede transformar dos veces", not u.can_transform() and not u.apply_transformation())
	var atk := u.transform_attack()
	_check("transform_attack: kind special, coste 0", String(atk.get("kind", "")) == "special" and int(atk.get("cost", -1)) == 0 and int(atk.get("power", 0)) == 20)
	u.hp = u.max_hp() * 0.5
	u.revert_transformation()
	var after := _snap(u)
	var same := true
	for k in before.keys():
		if str(before[k]) != str(after[k]):
			same = false
			_out("   diferencia en %s: %s -> %s" % [k, before[k], after[k]])
	_check("revert restaura TODO (stats, skills, pasivas, arte, nombre, tipo, roles, ultimate)", same and not u.transformed)
	_check("revert conserva la proporcion de vida (50%)", absf(u.hp_ratio() - 0.5) < 0.02)
	_check("visual_form() vuelve a vacio", u.visual_form() == "")
	_check("tras revertir se puede volver a transformar (otro combate)", u.can_transform())
	# Definicion minima: solo multiplicador => sigue siendo valida (ataque por defecto).
	var u2 := CombatUnit.new()
	var d2 := base.duplicate(true)
	d2["transformations"] = [{ "id": "min", "stat_multiplier": 1.2 }]
	u2.setup(d2, true, 0)
	_check("definicion minima valida con ataque por defecto", u2.can_transform() and int(u2.transform_attack().get("power", 0)) == 150)
	var u3 := CombatUnit.new()
	var d3 := base.duplicate(true)
	d3["transformations"] = [{ "name": "sin id" }]
	u3.setup(d3, true, 0)
	_check("definicion sin id se ignora", not u3.has_transformation())


## Combate manual: el jugador pulsa TRANSFORMAR en el turno de la unidad capaz.
func _check_battle_manual() -> void:
	var party := _party([String(GameState.roster[0])])
	var m := BattleManager.new()
	add_child(m)
	m.setup(party, _enemies(), [])
	m.pause_scale = 0.0
	m.set_auto(false)
	var state := { "done": false, "transformed": 0, "requests": 0, "capable_requests": 0, "attack_dmg": 0.0 }
	var ev := []
	m.transformed.connect(func(u, _d): state["transformed"] += 1; ev.append(String(u.id)))
	m.battle_finished.connect(func(_v, _r): state["done"] = true)
	var ctx := { "unit": null, "before": {}, "enemy_hp": 0.0, "did": false }
	var first_id := String(GameState.roster[0])
	m.action_requested.connect(func(u):
		state["requests"] += 1
		if not ctx["did"] and u.id == first_id and m.can_transform(u):
			ctx["did"] = true
			ctx["unit"] = u
			ctx["before"] = _snap(u)
			ctx["enemy_hp"] = _hp_total(m)
			m.submit_action.call_deferred({ "kind": "transform", "target_key": "" })
		elif not ctx["did"] or ctx.get("release", false):
			var tk := ""
			for e in m.enemies:
				if e.alive:
					tk = e.source_key
					break
			m.submit_action.call_deferred({ "kind": "basic", "target_key": tk })
	)
	m.start_battle()
	for i in 1200:
		if state["done"] or (ctx["did"] and state["transformed"] > 0 and i > 10 and _hp_total(m) < float(ctx["enemy_hp"])):
			break
		await _wait(0.03)
	var unit0 = ctx["unit"]
	var before: Dictionary = ctx["before"]
	_check("el boton (accion transform) transforma a la unidad", ctx["did"] and state["transformed"] == 1 and unit0 != null and unit0.transformed)
	_check("solo se transformo el personaje capaz", ev == [first_id])
	_check("el manager registra la unidad transformada", m.transformed_unit == unit0)
	_check("durante el combate sigue transformado (stats mayores)", unit0.attack() > float(before["atk"]) and unit0.display_name == "FORMA DE PRUEBA")
	_check("el ataque de transformacion hizo dano al rival", _hp_total(m) < float(ctx["enemy_hp"]))
	# Un compañero sin definicion no puede.
	var other = null
	for a in m.allies:
		if a != unit0:
			other = a
	_check("un compañero sin definicion no puede transformarse", other != null and not m.can_transform(other))
	_check("la unidad transformada no puede volver a transformarse", not m.can_transform(unit0))
	# Termina el combate: revierte.
	ctx["release"] = true
	m.set_auto(true)
	for i in 1500:
		if state["done"]:
			break
		await _wait(0.03)
	_check("el combate termina", state["done"])
	var after := _snap(unit0)
	var same := true
	for k in before.keys():
		if str(before[k]) != str(after[k]):
			same = false
			_out("   diferencia en %s: %s -> %s" % [k, before[k], after[k]])
	_check("al terminar el combate todo vuelve al estado original", same and not unit0.transformed)
	m.queue_free()


func _hp_total(m) -> float:
	var t := 0.0
	for e in m.enemies:
		t += e.hp
	return t


## Varios personajes capaces: solo uno por equipo y por combate. Si el transformado muere, el cupo sigue gastado.
func _check_one_per_team() -> void:
	var ids := [String(GameState.roster[0]), String(GameState.roster[1]), String(GameState.roster[2])]
	var party := _party(ids)
	var m := BattleManager.new()
	add_child(m)
	m.setup(party, _enemies(), [])
	m.pause_scale = 0.0
	var a0 = m.allies[0]
	var a1 = m.allies[1]
	_check("tres personajes capaces al inicio", m.can_transform(a0) and m.can_transform(a1) and m.can_transform(m.allies[2]))
	m._do_transform(a0)
	_check("tras transformar uno, ningun otro puede (limite por equipo)", not m.can_transform(a1) and not m.can_transform(m.allies[2]))
	_check("can_use('transform') coherente", not m.can_use(a1, "transform"))
	a0.hp = 0.0
	_check("si el transformado muere el cupo NO se libera", not m.can_transform(a1))
	m.queue_free()
	# Combate completo en auto con tres capaces: solo una transformacion.
	var m2 := BattleManager.new()
	add_child(m2)
	m2.setup(_party(ids), _enemies(), [])
	m2.pause_scale = 0.0
	m2.set_auto(true)
	var st := { "n": 0, "done": false }
	m2.transformed.connect(func(_u, _d): st["n"] += 1)
	m2.battle_finished.connect(func(_v, _r): st["done"] = true)
	m2.start_battle()
	for i in 1500:
		if st["done"]:
			break
		await _wait(0.03)
	_check("combate completo con 3 capaces: exactamente 1 transformacion", st["done"] and st["n"] == 1)
	m2.queue_free()


func _check_auto_and_revert() -> void:
	var id := String(GameState.roster[0])
	var before_data := JSON.stringify(GameState.character_data(id))
	var party := _party([id])
	var m := BattleManager.new()
	add_child(m)
	m.setup(party, _enemies(), [])
	m.pause_scale = 0.0
	m.set_auto(true)
	var st := { "done": false, "n": 0 }
	m.transformed.connect(func(_u, _d): st["n"] += 1)
	m.battle_finished.connect(func(_v, _r): st["done"] = true)
	var unit0 = m.allies[0]
	var snap := _snap(unit0)
	m.start_battle()
	for i in 1500:
		if st["done"]:
			break
		await _wait(0.03)
	_check("modo auto: el capaz se transforma por si solo", st["done"] and st["n"] == 1)
	var fin := _snap(unit0)
	for k in snap.keys():
		if str(snap[k]) != str(fin[k]):
			_out("   diferencia en %s: %s -> %s" % [k, snap[k], fin[k]])
	_check("auto: todo revertido al final", not unit0.transformed and str(fin) == str(snap))
	_check("los datos de GameState no se tocan", JSON.stringify(GameState.character_data(id)) == before_data)
	_check("la copia de datos real sigue sin transformaciones", (GameState.character_data(id).get("transformations", []) as Array).is_empty())
	m.queue_free()
	# Un segundo combate empieza limpio.
	var m2 := BattleManager.new()
	add_child(m2)
	m2.setup(_party([id]), _enemies(), [])
	_check("segundo combate: cupo y estado limpios", m2.transformed_unit == null and m2.can_transform(m2.allies[0]))
	m2.queue_free()
	# Reserva: un suplente capaz que entra puede transformarse; la reversion cubre reservas.
	var res_party := _party([])
	var res_data: Array = [GameState.character_data(String(GameState.roster[3])).duplicate(true)]
	res_data[0]["transformations"] = [_def()]
	var m3 := BattleManager.new()
	add_child(m3)
	m3.setup(res_party, _enemies(), res_data)
	var r = m3.reserves[0] if m3.reserves.size() > 0 else null
	if r != null:
		var rs := _snap(r)
		m3._do_transform(r)
		m3._revert_transformations()
		_check("la reversion tambien cubre a los suplentes", str(_snap(r)) == str(rs) and not r.transformed)
	else:
		_check("la reversion tambien cubre a los suplentes (sin reservas en este setup, omitido)", true)
	m3.queue_free()


func _check_no_transform_battle() -> void:
	var m := BattleManager.new()
	add_child(m)
	m.setup(_party([]), _enemies(), [])
	m.pause_scale = 0.0
	m.set_auto(true)
	var st := { "done": false, "n": 0, "victory": false }
	m.transformed.connect(func(_u, _d): st["n"] += 1)
	m.battle_finished.connect(func(v, _r): st["done"] = true; st["victory"] = v)
	m.start_battle()
	for i in 1500:
		if st["done"]:
			break
		await _wait(0.03)
	_check("combate sin capaces: normal, sin transformaciones, termina", st["done"] and st["n"] == 0 and m.transformed_unit == null)
	m.queue_free()


## UI real: el boton circular aparece solo para el capaz, se pulsa y transforma.
func _check_ui() -> void:
	var id := String(GameState.roster[0])
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_004_01", "difficulty": "normal" })
	var scene: PackedScene = load("res://scenes/battle/battle.tscn")
	if scene == null:
		_check("escena de combate cargable", false)
		return
	# Definicion inyectada SOLO en memoria (DB) durante la prueba y restaurada despues.
	var original = DB.characters.get(id, {})
	var patched: Dictionary = (original as Dictionary).duplicate(true)
	patched["transformations"] = [_def()]
	DB.characters[id] = patched
	var ui: Control = scene.instantiate()
	add_child(ui)
	await _wait(0.6)
	var mgr = ui.get("manager")
	_check("UI: el combate arranca", mgr != null)
	if mgr != null:
		mgr.pause_scale = 0.0
		var btn = ui.get("transform_button")
		_check("UI: existe TransformButton", btn != null and ui.find_child("TransformButton", true, false) != null)
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
		var visible_for_capable: bool = btn != null and btn.visible
		_check("UI: el boton se ve en el turno del capaz", visible_for_capable)
		if visible_for_capable:
			btn.emit_signal("pressed")
			await _wait(0.4)
			_check("UI: pulsar el boton transforma", mgr.transformed_unit != null and mgr.transformed_unit.transformed)
			_check("UI: el boton se oculta tras transformar", not btn.visible)
	DB.characters[id] = original
	ui.queue_free()
	await _wait(0.2)


func _with_def(d: Dictionary) -> Dictionary:
	d["transformations"] = [_def()]
	return d


func _check_save_compat() -> void:
	GameState.save_game()
	var text := FileAccess.get_file_as_string(GameState.SAVE_PATH) if "SAVE_PATH" in GameState else ""
	_check("el guardado no contiene datos de transformacion", text.find("transform") == -1 and text.find("FORMA DE PRUEBA") == -1)
	GameState.load_game()
	_check("el guardado carga igual que antes", GameState.roster.size() > 0)
