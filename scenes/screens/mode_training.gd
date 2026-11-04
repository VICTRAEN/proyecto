extends "res://scenes/screens/mode_base.gd"

## CAMPO DE ENTRENAMIENTO (X.3): sandbox. Elige aliados (tuyos), enemigos (de todo el catalogo),
## objetos de prueba y condiciones. No gasta ni da nada, no avanza misiones y no guarda.

const SAVED := "__saved__"
const NONE := "__none__"


func _screen_title() -> String:
	return "CAMPO DE ENTRENAMIENTO"


func refresh() -> void:
	if list == null:
		return
	clear_list()
	var t: Dictionary = GameState.modes.training
	var cfg: Dictionary = GameState.modes.training_config()
	var intro := make_card("TrainInfo", "", VI.CYAN)
	intro.add_child(make_label(String(cfg.get("description", "")), VI.FONT_SMALL, VI.INK_SOFT))
	# Aliados
	var allies := make_card("AlliesCard", "TU EQUIPO", VI.BLUE)
	var size_max := int(cfg.get("team_size", 4))
	for i in size_max:
		var id := String(t["allies"][i]) if i < (t["allies"] as Array).size() else ""
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(make_button("AllySlot_%d" % i, GameState.display_name(id) if not id.is_empty() else "+ Personaje %d" % (i + 1), VI.BLUE, _pick_ally.bind(i), 72.0))
		if not id.is_empty():
			var item := String((t["loadout"] as Dictionary).get(id, SAVED))
			var label := "Objeto guardado" if item == SAVED else ("Sin objeto" if item.is_empty() or item == NONE else GameState.equipment.name_of(item))
			row.add_child(make_button("AllyGear_%d" % i, label, VI.VIOLET, _pick_gear.bind(id), 72.0))
		allies.add_child(row)
	# Enemigos
	var foes := make_card("EnemiesCard", "ENEMIGOS", VI.RED)
	for i in int(cfg.get("enemy_size", 3)):
		var eid := String(t["enemies"][i]) if i < (t["enemies"] as Array).size() else ""
		foes.add_child(make_button("EnemySlot_%d" % i, _enemy_name(eid) if not eid.is_empty() else "+ Enemigo %d" % (i + 1), VI.RED, _pick_enemy.bind(i), 72.0))
	# Condiciones
	var cond := make_card("ConditionsCard", "CONDICIONES", VI.GOLD)
	var em: Dictionary = cfg.get("enemy_mult", {})
	_stepper(cond, "EnemyMult", "Poder enemigo", "x%.2f" % float(t["enemy_mult"]), "enemy_mult", float(em.get("step", 0.25)), float(em.get("min", 0.25)), float(em.get("max", 5.0)))
	var sh: Dictionary = cfg.get("start_hp", {})
	_stepper(cond, "AllyHp", "Vida inicial aliados", "%d%%" % int(round(float(t["ally_hp"]) * 100.0)), "ally_hp", float(sh.get("step", 0.1)), float(sh.get("min", 0.1)), float(sh.get("max", 1.0)))
	_stepper(cond, "EnemyHp", "Vida inicial enemigos", "%d%%" % int(round(float(t["enemy_hp"]) * 100.0)), "enemy_hp", float(sh.get("step", 0.1)), float(sh.get("min", 0.1)), float(sh.get("max", 1.0)))
	var sp: Dictionary = cfg.get("start_sp", {})
	_stepper(cond, "AllySp", "SP inicial aliados", "%d" % int(t["ally_sp"]), "ally_sp", 1.0, float(sp.get("min", 0)), float(sp.get("max", 6)))
	_stepper(cond, "EnemySp", "SP inicial enemigos", "%d" % int(t["enemy_sp"]), "enemy_sp", 1.0, float(sp.get("min", 0)), float(sp.get("max", 6)))
	cond.add_child(make_button("RoundsCycle", "Limite de rondas: %s" % ("sin limite" if int(t["rounds"]) == 0 else str(int(t["rounds"]))), VI.VIOLET, _cycle_rounds, 72.0))
	var problem: String = GameState.modes.training_problem()
	var go := make_card("StartCard", "", VI.GREEN)
	if not problem.is_empty():
		go.add_child(make_label(problem, VI.FONT_SMALL, VI.INK_DIM))
	var b := make_button("TrainStart", "EMPEZAR ENTRENAMIENTO", VI.GREEN, _start, 96.0)
	b.disabled = not problem.is_empty()
	go.add_child(b)
	_summary_card()


func _enemy_name(eid: String) -> String:
	if eid.begins_with("char:"):
		return "%s (personaje)" % String(DB.get_character(eid.substr(5)).get("name", eid))
	return String(DB.get_enemy(eid).get("name", eid))


func _stepper(col: VBoxContainer, node: String, label: String, value: String, key: String, step: float, lo: float, hi: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := make_label("%s: %s" % [label, value], VI.FONT_SMALL, VI.INK)
	l.name = node + "Label"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var minus := make_button(node + "Minus", "-", VI.BLUE, _step.bind(key, -step, lo, hi), 64.0)
	var plus := make_button(node + "Plus", "+", VI.BLUE, _step.bind(key, step, lo, hi), 64.0)
	minus.custom_minimum_size.x = 96
	plus.custom_minimum_size.x = 96
	minus.size_flags_horizontal = Control.SIZE_SHRINK_END
	plus.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(minus)
	row.add_child(plus)
	col.add_child(row)


func _step(key: String, delta: float, lo: float, hi: float) -> void:
	var t: Dictionary = GameState.modes.training
	var v := clampf(float(t[key]) + delta, lo, hi)
	t[key] = int(round(v)) if key in ["ally_sp", "enemy_sp"] else snappedf(v, 0.01)
	refresh()


func _cycle_rounds() -> void:
	var opts: Array = GameState.modes.training_config().get("rounds", [0])
	var t: Dictionary = GameState.modes.training
	var i := opts.find(int(t["rounds"]))
	t["rounds"] = int(opts[(i + 1) % opts.size()])
	refresh()


func _pick_ally(slot: int) -> void:
	var t: Dictionary = GameState.modes.training
	var options: Array = [{ "key": NONE, "label": "(Quitar de este hueco)" }]
	for id in GameState.roster:
		if (t["allies"] as Array).has(String(id)) and (t["allies"] as Array).find(String(id)) != slot:
			continue
		options.append({ "key": String(id), "label": GameState.display_name(String(id)), "selected": (t["allies"] as Array).find(String(id)) == slot })
	PW.open_picker(self, "Elige personaje", options, func(key: String):
		var allies: Array = t["allies"]
		while allies.size() <= slot:
			allies.append("")
		allies[slot] = "" if key == NONE else key
		t["allies"] = allies.filter(func(x): return String(x) != "")
		refresh())


func _pick_gear(char_id: String) -> void:
	var t: Dictionary = GameState.modes.training
	var options: Array = [{ "key": SAVED, "label": "Usar el objeto que lleva guardado" }, { "key": NONE, "label": "Sin objeto" }]
	for item in DB.all_equipment():
		options.append({ "key": String(item["id"]), "label": "%s (%s)" % [String(item.get("name", item["id"])), String(item.get("rarity", ""))] })
	PW.open_picker(self, "Objeto de prueba (no se toca tu inventario)", options, func(key: String):
		if key == SAVED:
			(t["loadout"] as Dictionary).erase(char_id)
		else:
			t["loadout"][char_id] = "" if key == NONE else key
		refresh())


func _pick_enemy(slot: int) -> void:
	var t: Dictionary = GameState.modes.training
	var options: Array = [{ "key": NONE, "label": "(Quitar de este hueco)" }]
	var ids: Array = DB.enemies.keys()
	ids.sort()
	for id in ids:
		options.append({ "key": String(id), "label": _enemy_name(String(id)) })
	var cids: Array = DB.characters.keys()
	cids.sort()
	for id in cids:
		options.append({ "key": "char:%s" % String(id), "label": _enemy_name("char:%s" % String(id)) })
	PW.open_picker(self, "Elige enemigo", options, func(key: String):
		var foes: Array = t["enemies"]
		while foes.size() <= slot:
			foes.append("")
		foes[slot] = "" if key == NONE else key
		t["enemies"] = foes.filter(func(x): return String(x) != "")
		refresh())


func _start() -> void:
	if not GameState.modes.start_training():
		say("No se puede empezar el entrenamiento.", false)
		return
	say("")
	open_battle()


func _summary_card() -> void:
	var s: Dictionary = GameState.modes.battle_summary
	if s.is_empty() or not (s.has("allies")):
		return
	var col := make_card("SummaryCard", "ULTIMO ENTRENAMIENTO", VI.CYAN)
	col.add_child(make_label("Rondas: %d   Dano total: %d   Criticos: %d   Enemigos abatidos: %d/%d" % [int(s.get("rounds", 0)), int(s.get("damage", 0)), int(s.get("crits", 0)), int(s.get("enemies_down", 0)), int(s.get("enemy_total", 0))], VI.FONT_TINY, VI.GOLD_LIGHT))
	for a in s["allies"]:
		col.add_child(make_label("%s: dano %d, curacion %d, recibido %d, criticos %d, vida %s" % [String(a["name"]), int(a["damage"]), int(a["healing"]), int(a["received"]), int(a["crits"]), hp_text(float(a["hp_ratio"]), bool(a["alive"]))], VI.FONT_TINY, VI.INK))
	col.add_child(make_label("Entrenamiento: nada de esto se ha guardado ni ha dado recompensas.", VI.FONT_TINY, VI.INK_DIM))
