extends Node

## COMPROBACIONES EN EJECUCION DE LA v12 (combate y sinergias). SOLO para pruebas.
## Arranque:  godot --headless --path . -- --dbg24   (escribe res://dbg24_resultados.txt)

const RESULTS_PATH := "res://dbg24_resultados.txt"
const CombatUnit := preload("res://core/combat_unit.gd")
const EffectEngine := preload("res://core/effect_engine.gd")
const BattleMath := preload("res://core/battle_math.gd")
const BM := preload("res://core/battle_manager.gd")

const KNOWN_EFFECTS := ["damage", "heal", "stat_mod", "sp_gain", "status", "shield", "periodic", "cleanse", "dispel", "sp_drain", "undying"]
const KNOWN_TRIGGERS := ["static", "battle_start", "round_start", "turn_start", "on_attack", "on_special", "on_hit", "on_crit", "on_kill", "on_dodge", "on_ally_down", "low_hp"]
const KNOWN_TARGETS := ["self", "enemy", "enemy_all", "ally", "ally_all", "ally_lowest", "ally_others", "ally_random", "random_enemy", "enemy_strongest", "enemy_lowest", "trigger_target"]

var _app: Node = null
var _fails := 0
var _checks := 0
var _rng := RandomNumberGenerator.new()


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
	_out("[DBG24] %s -> %s" % [label, "OK" if ok else "FALLO"])


func run(app: Node) -> void:
	_app = app
	await get_tree().create_timer(0.3).timeout
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	_rng.seed = 7
	_out("[DBG24] --- comprobaciones v12 ---")
	_app.call("_backup_save")
	_check_data()
	_check_effects()
	await _check_triggers()
	_check_links()
	await _check_saved_teams()
	await _check_battles()
	_app.call("_restore_save")
	_out("[DBG24] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _unit(id: String, ally := true, slot := 0) -> CombatUnit:
	var unit := CombatUnit.new()
	unit.setup(GameState.character_data(id), ally, slot)
	return unit


func _ctx(actor: CombatUnit, target, team: Array, foes: Array, round_n := 1) -> Dictionary:
	return { "actor": actor, "target": target, "team": team, "foes": foes, "rng": _rng, "source": "test", "round": round_n }


func _rule_list(data: Dictionary) -> Array:
	var rules: Array = []
	var p = data.get("passive", {})
	if p is Dictionary and not (p as Dictionary).is_empty():
		rules.append(p)
	var ev = data.get("evolution", {})
	if ev is Dictionary:
		for key in ["passive", "passive_extra"]:
			if (ev as Dictionary).has(key):
				rules.append(ev[key])
	return rules


func _effects_valid(effects: Array) -> bool:
	for e in effects:
		if not KNOWN_EFFECTS.has(String(e.get("type", ""))):
			return false
		if not KNOWN_TARGETS.has(String(e.get("target", "self"))):
			return false
	return true


## --- 1. Datos ---------------------------------------------------------------------
func _check_data() -> void:
	_out("[DBG24] == DATOS: PASIVAS, HABILIDADES Y LINKS ==")
	var all_valid := true
	var desc_ok := true
	var signatures := {}
	var spec_signatures := {}
	var count := 0
	for id in DB.character_ids():
		var data: Dictionary = DB.get_character(String(id))
		for rule in _rule_list(data):
			count += 1
			if not KNOWN_TRIGGERS.has(String(rule.get("trigger", ""))) or not _effects_valid(rule.get("effects", [])):
				all_valid = false
				_out("[DBG24]   regla invalida en %s: %s" % [id, str(rule.get("id", ""))])
			if String(rule.get("description", "")).length() < 10:
				desc_ok = false
			var sig := "%s|%s" % [rule["trigger"], JSON.stringify(rule["effects"])]
			signatures[sig] = true
		for skill in data.get("skills", []):
			if String(skill.get("kind", "")) == "special":
				if not _effects_valid(skill.get("effects", [])):
					all_valid = false
				var ssig := "%s|%s|%s|%s|%s|%s" % [JSON.stringify(skill.get("effects", [])), skill.get("hits", 1), skill.get("pierce", 0), skill.get("lifesteal", 0), JSON.stringify(skill.get("bonus", [])), skill.get("power", 0)]
				spec_signatures[ssig] = true
				if String(skill.get("description", "")).length() < 10:
					desc_ok = false
	_check("todas las pasivas (%d) usan solo efectos, disparadores y objetivos que el motor conoce" % count, all_valid)
	_check("todas las pasivas y especiales tienen descripcion", desc_ok)
	_check("hay %d pasivas distintas entre %d (antes 21 patrones)" % [signatures.size(), count], signatures.size() >= 55)
	_check("hay %d especiales distintos entre 65 (antes 12 firmas)" % spec_signatures.size(), spec_signatures.size() >= 55)
	var triggers := {}
	for id in DB.character_ids():
		for rule in _rule_list(DB.get_character(String(id))):
			triggers[String(rule["trigger"])] = true
	_check("se usan %d disparadores distintos (antes 2)" % triggers.size(), triggers.size() >= 9)
	var link_ok := true
	var tiers_total := 0
	for link in DB.all_links():
		var tiers: Array = link.get("tiers", [])
		if tiers.size() < 3:
			link_ok = false
		for tier in tiers:
			tiers_total += 1
			for rule in tier["rules"]:
				if not KNOWN_TRIGGERS.has(String(rule.get("trigger", ""))) or not _effects_valid(rule.get("effects", [])) or String(rule.get("text", "")).is_empty():
					link_ok = false
	_check("los 13 links tienen 3 niveles con reglas validas y texto (%d niveles)" % tiers_total, link_ok and DB.all_links().size() == 13)
	var ids_ok := DB.character_ids().size() == 65 and DB.has_character("david_lucy_duo") and DB.has_character("sakuta_mai_lr")
	_check("el roster sigue en 65 personajes con los mismos identificadores", ids_ok)
	var four := 0
	for id in DB.character_ids():
		var sp := {}
		for skill in DB.get_character(String(id)).get("skills", []):
			if String(skill.get("kind", "")) == "special":
				sp = skill
		if int(sp.get("cost", 0)) == 3 and float(sp.get("power", 0)) >= 0.0:
			four += 1
	_check("los costes de las especiales no han cambiado (SP 3)", four == 65)


## --- 2. Efectos del motor -------------------------------------------------------------
func _check_effects() -> void:
	_out("[DBG24] == EFECTOS DEL MOTOR ==")
	var a := _unit("gojo")
	var b := _unit("akaza", false)
	var team := [a]
	var foes := [b]
	# escudo
	var hp0 := a.hp
	a.add_shield(100.0, 2, "t")
	var dealt := a.take_damage(60.0)
	_check("un escudo absorbe el dano antes que la vida (vida intacta: %s)" % [a.hp == hp0], a.hp == hp0 and dealt == 0.0 and is_equal_approx(a.shield_total(), 40.0))
	a.take_damage(100.0)
	_check("al romperse, el resto pasa a la vida", is_equal_approx(a.hp, hp0 - 60.0) and a.shield_total() == 0.0)
	a.hp = hp0
	a.add_shield(50.0, 1, "t")
	a.tick_round()
	_check("un escudo con duracion caduca al acabar la ronda", a.shield_total() == 0.0)
	# periodicos
	b.add_periodic("bleed", 30.0, 2, "t")
	b.add_periodic("poison", 20.0, 3, "u")
	_check("sangrado y veneno de origenes distintos conviven", b.periodics.size() == 2)
	b.add_periodic("bleed", 45.0, 2, "t")
	_check("reaplicar el mismo sangrado lo REFRESCA (no se acumula)", b.periodics.size() == 2)
	# cleanse / dispel
	b.stats.add_mod("atk", "mult", -0.2, "x", 2)
	b.stats.add_mod("def", "mult", 0.3, "y", 2)
	b.stats.add_mod("atk", "mult", 0.1, "perm", 0)
	b.add_status("stun", 1)
	var cleansed := b.cleanse()
	_check("purgar quita debuffs temporales, estados y sangrados (%d)" % cleansed, b.periodics.is_empty() and not b.is_stunned() and b.stats.get_stat("atk") > b.stats.base_value("atk"))
	_check("purgar NO quita buffs ni bonos permanentes", is_equal_approx(b.stats.get_stat("def"), b.stats.base_value("def") * 1.3))
	b.add_shield(30.0, 2, "s")
	b.dispel()
	_check("disipar quita buffs temporales y escudos pero respeta lo permanente", b.shield_total() == 0.0 and is_equal_approx(b.stats.get_stat("def"), b.stats.base_value("def")) and b.stats.get_stat("atk") > b.stats.base_value("atk"))
	# sp_drain
	b.sp = 3
	EffectEngine.apply_effects([{ "type": "sp_drain", "target": "enemy", "amount": 2 }], _ctx(a, b, team, foes))
	_check("robar SP baja los puntos del rival (3 -> %d)" % b.sp, b.sp == 1)
	# undying
	var c := _unit("subaru")
	c.undying = 1
	c.undying_heal = 0.3
	c.take_damage(c.max_hp() * 5.0)
	_check("ultimo aliento: sobrevive a un golpe mortal con el 30%% de vida", c.alive and is_equal_approx(c.hp_ratio(), 0.3) and c.undying == 0)
	c.take_damage(c.max_hp() * 5.0)
	_check("la carga se gasta: el segundo golpe mortal si mata", not c.alive)
	# apilado
	var d := _unit("akaza")
	var stack_effect := { "type": "stat_mod", "target": "self", "stat": "atk", "kind": "mult", "value": 0.06, "turns": 3, "stacks_max": 3 }
	for i in 6:
		EffectEngine.apply_effects([stack_effect], _ctx(d, null, [d], [b]))
	_check("un bono acumulable sube hasta su tope (x3 = +18%%) y no mas", is_equal_approx(d.stats.get_stat("atk") / d.stats.base_value("atk"), 1.18))
	# dano: vulnerabilidad, perforacion, reduccion
	var att := _unit("gojo")
	var vic := _unit("akaza", false)
	vic.stats.add_mod("def", "flat", 400.0, "tdef")
	var ctx := _ctx(att, vic, [att], [vic])
	var results_base := []
	var results_vuln := []
	var results_pierce := []
	var results_red := []
	_rng.seed = 11
	att.stats.add_mod("crit_rate", "flat", -1.0, "nocrit")
	vic.stats.add_mod("dodge_rate", "flat", -1.0, "nododge")
	for i in 40:
		vic.hp = vic.max_hp()
		results_base.append(BattleMath.deal_damage(att, vic, 200.0, ctx)["value"])
	vic.stats.add_mod("dmg_taken", "flat", 0.5, "v")
	for i in 40:
		vic.hp = vic.max_hp()
		results_vuln.append(BattleMath.deal_damage(att, vic, 200.0, ctx)["value"])
	vic.stats.remove_source("v")
	var pierce_ctx := ctx.duplicate()
	pierce_ctx["pierce"] = 0.5
	for i in 40:
		vic.hp = vic.max_hp()
		results_pierce.append(BattleMath.deal_damage(att, vic, 200.0, pierce_ctx)["value"])
	vic.stats.add_mod("dmg_reduction", "flat", 0.3, "r")
	for i in 40:
		vic.hp = vic.max_hp()
		results_red.append(BattleMath.deal_damage(att, vic, 200.0, ctx)["value"])
	var avg := func(arr: Array) -> float:
		var total := 0.0
		for v in arr:
			total += float(v)
		return total / float(arr.size())
	_check("marca de vulnerabilidad: +50%% de dano recibido (x%.2f)" % (avg.call(results_vuln) / avg.call(results_base)), absf(avg.call(results_vuln) / avg.call(results_base) - 1.5) < 0.06)
	_check("perforacion: ignora parte de la defensa (mas dano)", avg.call(results_pierce) > avg.call(results_base) * 1.05)
	_check("reduccion de dano: -30%% (x%.2f)" % (avg.call(results_red) / avg.call(results_base)), absf(avg.call(results_red) / avg.call(results_base) - 0.7) < 0.06)
	# robo de vida
	att.hp = att.max_hp() * 0.5
	var steal_ctx := ctx.duplicate()
	steal_ctx["lifesteal"] = 0.5
	vic.stats.remove_source("r")
	vic.hp = vic.max_hp()
	var res: Dictionary = BattleMath.deal_damage(att, vic, 200.0, steal_ctx)
	_check("robo de vida: cura la mitad del dano hecho (%.0f de %.0f)" % [float(res["lifesteal"]), float(res["value"])], absf(float(res["lifesteal"]) - float(res["value"]) * 0.5) < 1.0)
	# condiciones
	var low := _unit("akaza", false)
	low.hp = low.max_hp() * 0.3
	var cond_ctx := _ctx(att, low, [att], [low])
	_check("condicion: objetivo con menos del 40% de vida", EffectEngine.check_condition({ "type": "target_hp_below", "value": 0.4 }, cond_ctx))
	_check("condicion: objetivo con efecto negativo (no)", not EffectEngine.check_condition({ "type": "target_debuffed" }, cond_ctx))
	low.stats.add_mod("atk", "mult", -0.1, "z", 2)
	_check("condicion: objetivo con efecto negativo (si)", EffectEngine.check_condition({ "type": "target_debuffed" }, cond_ctx))
	var skill := { "bonus": [{ "condition": { "type": "target_hp_below", "value": 0.4 }, "power_mult": 1.5 }, { "condition": { "type": "target_debuffed" }, "power_mult": 1.2 }] }
	_check("los bonus de una habilidad se multiplican (x1.8)", is_equal_approx(EffectEngine.power_multiplier(skill, cond_ctx), 1.8))


## --- 3. Disparadores en un combate real -------------------------------------------------
func _manager(ally_ids: Array, enemy_ids: Array) -> Node:
	var mgr: Node = BM.new()
	add_child(mgr)
	var ally_data: Array = []
	for id in ally_ids:
		ally_data.append(GameState.character_data(id))
	var enemy_data: Array = []
	for id in enemy_ids:
		enemy_data.append(DB.get_enemy(id))
	GameState.party = ally_ids.duplicate()
	mgr.setup(ally_data, enemy_data)
	mgr.pause_scale = 0.0
	return mgr


func _rule(trigger: String, effects: Array, extra := {}) -> Dictionary:
	var rule := { "id": "t_%s_%d" % [trigger, randi()], "name": "Prueba", "trigger": trigger, "effects": effects, "condition": {} }
	rule.merge(extra, true)
	return rule


func _check_triggers() -> void:
	_out("[DBG24] == DISPARADORES ==")
	var mgr := _manager(["gojo", "isagi", "miku", "mai"], ["vigia_alfa", "vigia_beta"])
	var gojo: CombatUnit = mgr.allies[0]
	var isagi: CombatUnit = mgr.allies[1]
	var foe: CombatUnit = mgr.enemies[0]
	mgr.round_number = 1
	# on_hit con contraataque
	gojo.passives = [_rule("on_hit", [{ "type": "damage", "target": "trigger_target", "power": 100 }])]
	var foe_hp := foe.hp
	mgr.call("_fire_rules", "on_hit", gojo, { "target": foe })
	_check("on_hit: el golpeado contraataca a quien le ha pegado", foe.hp < foe_hp)
	# chance 0
	gojo.passives = [_rule("on_hit", [{ "type": "damage", "target": "trigger_target", "power": 100 }], { "chance": 0.0 })]
	foe_hp = foe.hp
	for i in 20:
		mgr.call("_fire_rules", "on_hit", gojo, { "target": foe })
	_check("probabilidad 0%: no se dispara nunca", foe.hp == foe_hp)
	# once
	gojo.passives = [_rule("on_hit", [{ "type": "sp_gain", "target": "self", "amount": 1 }], { "once": true })]
	gojo.sp = 0
	for i in 5:
		mgr.call("_fire_rules", "on_hit", gojo, { "target": foe })
	_check("una vez por combate: solo dispara una vez (SP %d)" % gojo.sp, gojo.sp == 1)
	# cooldown
	gojo.passives = [_rule("on_hit", [{ "type": "sp_gain", "target": "self", "amount": 1 }], { "cooldown": 3 })]
	gojo.sp = 0
	mgr.round_number = 1
	mgr.call("_fire_rules", "on_hit", gojo, { "target": foe })
	mgr.call("_fire_rules", "on_hit", gojo, { "target": foe })
	var after_same_round := gojo.sp
	mgr.round_number = 4
	mgr.call("_fire_rules", "on_hit", gojo, { "target": foe })
	_check("enfriamiento 3: una vez en la ronda 1 (%d) y otra en la 4 (%d)" % [after_same_round, gojo.sp], after_same_round == 1 and gojo.sp == 2)
	# low_hp
	gojo.passives = [_rule("low_hp", [{ "type": "shield", "target": "self", "amount": 0.2, "of": "max_hp", "turns": 2 }], { "threshold": 0.4, "once": true })]
	mgr.call("_check_low_hp_all")
	var before := gojo.shield_total()
	gojo.hp = gojo.max_hp() * 0.3
	mgr.call("_check_low_hp_all")
	var once_shield := gojo.shield_total()
	gojo.shield_total()
	gojo.shields = []
	mgr.call("_check_low_hp_all")
	_check("low_hp: salta al bajar del umbral, no antes, y solo una vez", before == 0.0 and once_shield > 0.0 and gojo.shield_total() == 0.0)
	gojo.hp = gojo.max_hp()
	# on_ally_down
	isagi.passives = [_rule("on_ally_down", [{ "type": "stat_mod", "target": "self", "stat": "atk", "kind": "mult", "value": 0.3, "turns": 3 }])]
	var atk_before := isagi.attack()
	var miku: CombatUnit = mgr.allies[2]
	miku.take_damage(miku.max_hp() * 10.0)
	mgr.call("_after_deaths", null)
	_check("on_ally_down: los que quedan reaccionan cuando cae un aliado", isagi.attack() > atk_before * 1.25)
	var atk_mid := isagi.attack()
	mgr.call("_after_deaths", null)
	_check("la caida solo se resuelve UNA vez", is_equal_approx(isagi.attack(), atk_mid))
	# round_start y condicion de regla
	gojo.passives = [_rule("round_start", [{ "type": "stat_mod", "target": "self", "stat": "dmg_reduction", "kind": "flat", "value": 0.2, "turns": 1 }], { "condition": { "type": "round_at_least", "value": 3 } })]
	mgr.round_number = 2
	mgr.call("_apply_passives", "round_start", [gojo])
	var r2 := gojo.stats.get_stat("dmg_reduction")
	mgr.round_number = 3
	mgr.call("_apply_passives", "round_start", [gojo])
	_check("condicion de regla: desde la ronda 3 (R2=%.2f, R3=%.2f)" % [r2, gojo.stats.get_stat("dmg_reduction")], r2 == 0.0 and is_equal_approx(gojo.stats.get_stat("dmg_reduction"), 0.2))
	# efecto temporal caduca
	gojo.stats.tick()
	_check("el efecto temporal de la regla caduca al acabar la ronda", gojo.stats.get_stat("dmg_reduction") == 0.0)
	# periodicos en el turno
	foe.hp = foe.max_hp()
	foe.add_periodic("bleed", 50.0, 2, "t")
	mgr.call("_tick_periodics", foe)
	_check("el sangrado resta vida al empezar el turno (-50) y dura 2 turnos", is_equal_approx(foe.hp, foe.max_hp() - 50.0) and foe.periodics.size() == 1)
	mgr.call("_tick_periodics", foe)
	_check("...y desaparece al terminar", foe.periodics.is_empty())
	# provocar
	var f2: CombatUnit = mgr.enemies[1]
	f2.add_status("taunt", 2)
	var skill := gojo.skill_by_kind("basic")
	var all_on_taunter := true
	for i in 20:
		var tgt = mgr.call("_pick_target", gojo, skill, foe.source_key)
		if tgt != f2:
			all_on_taunter = false
	_check("provocar: los ataques a un objetivo solo pueden ir al que provoca", all_on_taunter)
	var cands: Array = mgr.candidates(gojo, "basic")
	_check("provocar: el jugador solo puede elegir al que provoca", cands.size() == 1 and cands[0] == f2)
	mgr.queue_free()


## --- 4. Links por niveles ------------------------------------------------------------------
func _check_links() -> void:
	_out("[DBG24] == LINKS POR NIVELES ==")
	# heroes: gojo, deku, tanjiro, reinhard son 'heroes'
	var heroes: Array = []
	for id in DB.character_ids():
		if (DB.get_character(String(id)).get("links", []) as Array).has("heroes") and DB.get_character(String(id)).get("rarity", "") != "LR":
			heroes.append(String(id))
	GameState.party = [heroes[0], "mai", "senku", "miku"]
	_check("un solo portador: el link NO se activa", not GameState.active_link_ids().has("heroes"))
	GameState.party = [heroes[0], heroes[1], "mai", "senku"]
	_check("2 portadores: nivel 1", GameState.link_tier_reached("heroes", GameState.link_holder_count("heroes")) == 1 and GameState.active_link_ids().has("heroes"))
	GameState.party = [heroes[0], heroes[1], heroes[2], "senku"]
	_check("3 portadores: nivel 2", GameState.link_tier_reached("heroes", GameState.link_holder_count("heroes")) == 2)
	GameState.party = [heroes[0], heroes[1], heroes[2], heroes[3]]
	_check("4 portadores: nivel 3", GameState.link_tier_reached("heroes", GameState.link_holder_count("heroes")) == 3)
	# reglas por personaje
	GameState.party = [heroes[0], heroes[1], heroes[2], "senku"]
	var rules_holder := GameState.link_rules_for(heroes[0])
	var rules_outsider := GameState.link_rules_for("senku")
	_check("un portador recibe las reglas del link (%d) y quien no lo lleva, ninguna de 'heroes'" % rules_holder.size(), rules_holder.size() >= 1)
	var outsider_has_heroes := false
	for rule in rules_outsider:
		if String(rule["id"]).begins_with("link_heroes_"):
			outsider_has_heroes = true
	_check("quien no es portador no recibe reglas de heroes", not outsider_has_heroes)
	# 'first': solo el primer portador
	var first_count := 0
	for id in [heroes[0], heroes[1], heroes[2]]:
		for rule in GameState.link_rules_for(id):
			if String(rule["id"]) == "link_heroes_escudo":
				first_count += 1
	_check("reglas 'first': solo UN portador la lleva (%d)" % first_count, first_count == 1)
	# estaticos
	var vets: Array = []
	for id in DB.character_ids():
		if (DB.get_character(String(id)).get("links", []) as Array).has("veteranos"):
			vets.append(String(id))
	GameState.party = [vets[0], vets[1], "mai", "senku"]
	var static_mods := GameState.link_mods_for(vets[0])
	var has_dr := false
	for mod in static_mods:
		if String(mod["stat"]) == "dmg_reduction":
			has_dr = true
	_check("link estatico: veteranos aporta reduccion de dano desde el nivel 1", has_dr)
	# informe de sinergias
	var report := GameState.team_synergy_report()
	var row := {}
	for entry in report:
		if String(entry["id"]) == "veteranos":
			row = entry
	_check("el informe de sinergias lista niveles, textos y A QUIEN benefician", not row.is_empty() and row["tiers"].size() >= 3 and (row["tiers"][0]["rules"][0]["who_names"] as Array).size() >= 2)
	# compat: link antiguo con 'effects'
	_check("el roster mantiene los links de cada personaje", (DB.get_character("gojo").get("links", []) as Array).has("heroes"))


## --- 5. Combates automaticos completos -------------------------------------------------------
func _check_battles() -> void:
	_out("[DBG24] == COMBATES COMPLETOS CON LAS MECANICAS NUEVAS ==")
	var ids: Array = DB.character_ids()
	var finished := 0
	var errors_free := true
	var seeds := RandomNumberGenerator.new()
	seeds.seed = 99
	for game in 12:
		var pool := ids.duplicate()
		var team: Array = []
		for k in 4:
			var pick := seeds.randi_range(0, pool.size() - 1)
			team.append(pool[pick])
			pool.remove_at(pick)
		for id in team:
			GameState.progress[id] = { "level": 10, "xp": 0 }
		var mgr := _manager(team, ["torre_guardian", "torre_verdugo", "torre_avatar"])
		mgr.set_auto(true)
		var holder := { "done": false }
		mgr.battle_finished.connect(func(_v, _r): holder["done"] = true)
		mgr.start_battle()
		var guard := 0
		while not holder["done"] and guard < 3000 and mgr.round_number < 60:
			await get_tree().process_frame
			guard += 1
		if holder["done"]:
			finished += 1
		mgr.queue_free()
	_check("12 combates automaticos de equipos aleatorios terminan solos (%d/12)" % finished, finished == 12 and errors_free)


## --- 6. Equipos guardados, favoritos, proteccion y autoconfiguracion ----------------------------
func _check_saved_teams() -> void:
	_out("[DBG24] == EQUIPOS GUARDADOS, FAVORITOS Y AUTOCONFIGURACION ==")
	var ids: Array = DB.character_ids()
	GameState.saved_teams = []
	GameState.favorites = []
	GameState.roster = []
	var mine: Array = []
	for k in 8:
		var key := String(ids[k])
		GameState.add_character(key)
		mine.append(key)
	GameState.party = [mine[0], mine[1], mine[2], mine[3]]
	GameState.normalize_party()
	# crear / listar
	var created := GameState.saved_team_create("Alfa")
	_check("crear un equipo guardado con el equipo actual", bool(created["ok"]) and GameState.saved_team_count() == 1)
	var team_a := int(created["id"])
	var stored: Array = GameState.saved_team_get(team_a)["members"]
	_check("conserva la posicion de cada personaje (la 1 es el lider)", stored[0] == mine[0] and stored[3] == mine[3] and stored.size() == GameState.SAVED_TEAM_SLOTS)
	_check("un equipo vacio no se guarda", not bool(GameState.saved_team_create("Nada", ["", "", "", "", ""])["ok"]))
	# renombrar / duplicar
	_check("renombrar", bool(GameState.saved_team_rename(team_a, "Beta")["ok"]) and GameState.saved_team_get(team_a)["name"] == "Beta")
	_check("un nombre vacio no renombra", not bool(GameState.saved_team_rename(team_a, "   ")["ok"]) and GameState.saved_team_get(team_a)["name"] == "Beta")
	var copy := GameState.saved_team_duplicate(team_a)
	_check("duplicar crea otro equipo con los mismos miembros", bool(copy["ok"]) and GameState.saved_team_count() == 2 and GameState.saved_team_get(int(copy["id"]))["members"] == stored)
	# editar: cambiar el equipo activo y actualizar el guardado
	GameState.party = [mine[4], mine[5], mine[6], mine[7]]
	_check("actualizar un equipo guardado con el equipo activo", bool(GameState.saved_team_update(team_a)["ok"]) and GameState.saved_team_get(team_a)["members"][0] == mine[4])
	_check("el duplicado NO cambia al editar el original", GameState.saved_team_get(int(copy["id"]))["members"][0] == mine[0])
	# aplicar
	GameState.party = [mine[0], "", "", ""]
	var applied := GameState.saved_team_apply(team_a)
	_check("elegir un equipo lo pone como equipo activo", bool(applied["ok"]) and GameState.party[0] == mine[4] and GameState.party_count() == 4)
	# limite 20
	var made := 2
	var last_ok := true
	while made < GameState.SAVED_TEAM_MAX:
		last_ok = last_ok and bool(GameState.saved_team_create("T%d" % made, [mine[0]])["ok"])
		made += 1
	_check("se pueden guardar hasta 20 equipos", last_ok and GameState.saved_team_count() == 20)
	var over := GameState.saved_team_create("de mas", [mine[0]])
	_check("el equipo 21 se rechaza con un mensaje", not bool(over["ok"]) and not String(over["reason"]).is_empty() and GameState.saved_team_count() == 20)
	# personaje no disponible: no se modifica en silencio
	var ghost_team := GameState.saved_team_create("Fantasma", ["no_existe_xyz", mine[0], "", "", ""])
	_check("(hay hueco para el equipo fantasma tras borrar uno)", not bool(ghost_team["ok"]))
	GameState.saved_team_delete(int(copy["id"]))
	_check("borrar baja el contador", GameState.saved_team_count() == 19 and GameState.saved_team_get(int(copy["id"])).is_empty())
	ghost_team = GameState.saved_team_create("Fantasma", ["no_existe_xyz", mine[0], "", "", ""])
	_check("un equipo con un id desconocido se guarda tal cual", bool(ghost_team["ok"]))
	var before: Array = GameState.party.duplicate()
	var refused := GameState.saved_team_apply(int(ghost_team["id"]))
	_check("si falta alguien NO se aplica y se informa de quien", not bool(refused["ok"]) and String(refused["reason"]).contains("no_existe_xyz") and GameState.party == before)
	var stat := GameState.saved_team_status(int(ghost_team["id"]))
	_check("el estado lista disponibles y ausentes", (stat["missing"] as Array).size() == 1 and (stat["available"] as Array).size() == 1 and not bool(stat["complete"]))
	var partial := GameState.saved_team_apply(int(ghost_team["id"]), "party", true)
	_check("USAR IGUAL aplica solo a los disponibles y deja huecos", bool(partial["ok"]) and GameState.party[0] == "" and GameState.party[1] == mine[0])
	_check("el equipo guardado conserva al ausente", GameState.saved_team_get(int(ghost_team["id"]))["members"][0] == "no_existe_xyz")
	# personaje que se pierde de la coleccion
	var lost := String(mine[1])
	var tid := int(GameState.saved_team_create("Perdido", [mine[0], lost], "party")["id"]) if GameState.saved_team_count() < 20 else -1
	if tid < 0:
		GameState.saved_team_delete(int(ghost_team["id"]))
		tid = int(GameState.saved_team_create("Perdido", [mine[0], lost])["id"])
	GameState.roster.erase(lost)
	var gone := GameState.saved_team_status(tid)
	_check("un personaje que ya no tienes aparece como ausente, sin tocar el equipo guardado", (gone["missing"] as Array).size() == 1 and GameState.saved_team_get(tid)["members"].has(lost))
	GameState.roster.append(lost)
	# torre (5 puestos)
	GameState.tower_team = [mine[0], mine[1], mine[2], mine[3], mine[4]]
	var tower_id := int(GameState.saved_team_create("Torre", [], "tower")["id"]) if GameState.saved_team_count() < 20 else -1
	if tower_id < 0:
		GameState.saved_team_delete(tid)
		tower_id = int(GameState.saved_team_create("Torre", [], "tower")["id"])
	GameState.tower_team = ["", "", "", "", ""]
	_check("un equipo de torre guarda 5 puestos y se aplica a la torre", bool(GameState.saved_team_apply(tower_id, "tower")["ok"]) and GameState.tower_team[4] == mine[4])
	# requisitos del contenido
	_check("un equipo vacio no vale para el contenido", not GameState.content_problem_for([]).is_empty())
	_check("un equipo normal vale para un combate normal", GameState.content_problem_for([mine[0]]).is_empty() or GameState.current_min_party_size() > 1)
	# favoritos y proteccion
	GameState.set_favorite(mine[0], true)
	_check("marcar favorito", GameState.is_favorite(mine[0]) and GameState.favorite_ids().has(mine[0]))
	var guard := GameState.consume_guard(mine[0])
	_check("consume_guard bloquea a un favorito y avisa", bool(guard["protected"]) and not String(guard["message"]).is_empty())
	GameState.set_favorite("no_lo_tengo", true)
	_check("no se marca como favorito lo que no se tiene", not GameState.is_favorite("no_lo_tengo"))
	GameState.set_favorite(mine[0], false)
	var warn := GameState.consume_guard(mine[0])
	_check("un personaje en equipos guardados avisa de cuales (sin bloquear)", not bool(warn["protected"]) and (warn["teams"] as Array).size() >= 1 and not String(warn["message"]).is_empty())
	# evolucion especial consume: protegida por favorito y arrastra equipos guardados
	GameState.add_character("sakuta_mai")
	GameState.progress["sakuta_mai"] = { "level": 100, "xp": 0 }
	GameState.add_item("rabbit_costume", 25)
	var team_s := GameState.saved_team_create("Con Sakuta", ["sakuta_mai", mine[0]]) if GameState.saved_team_count() < 20 else { "ok": false, "id": -1 }
	if not bool(team_s["ok"]):
		GameState.saved_team_delete(tower_id)
		team_s = GameState.saved_team_create("Con Sakuta", ["sakuta_mai", mine[0]])
	GameState.set_favorite("sakuta_mai", true)
	var blocked := GameState.can_special_evolve("sakuta_mai")
	_check("un favorito no se puede consumir en una evolucion especial", not bool(blocked["ok"]) and bool(blocked["protected"]))
	_check("evolve_special no hace nada con un favorito", GameState.evolve_special("sakuta_mai").is_empty() and GameState.is_owned("sakuta_mai"))
	GameState.set_favorite("sakuta_mai", false)
	var ready := GameState.can_special_evolve("sakuta_mai")
	_check("sin favorito, la evolucion avisa de los equipos guardados", bool(ready["ok"]) and String(ready["reason"]).contains("Con Sakuta"))
	var evolved := GameState.evolve_special("sakuta_mai")
	_check("la evolucion se hace", not evolved.is_empty() and GameState.is_owned("sakuta") and not GameState.is_owned("sakuta_mai"))
	_check("el equipo guardado sigue al personaje nuevo", (GameState.saved_team_get(int(team_s["id"]))["members"] as Array).has("sakuta") and not (GameState.saved_team_get(int(team_s["id"]))["members"] as Array).has("sakuta_mai"))
	# guardar y cargar
	GameState.set_favorite(mine[2], true)
	var count_before := GameState.saved_team_count()
	var names_before: Array = []
	for team in GameState.saved_team_list():
		names_before.append(team["name"])
	var next_before := GameState._next_team_id
	GameState.save_game()
	GameState.saved_teams = []
	GameState.favorites = []
	GameState.load_game()
	var names_after: Array = []
	for team in GameState.saved_team_list():
		names_after.append(team["name"])
	_check("guardar y cargar conserva equipos, nombres y favoritos", GameState.saved_team_count() == count_before and names_after == names_before and GameState.is_favorite(mine[2]))
	_check("el contador de ids no se repite tras cargar", GameState._next_team_id >= next_before)
	# guardado antiguo sin las claves nuevas
	GameState._load_saved_teams({ "version": 3 })
	_check("un guardado antiguo sin equipos carga con listas vacias", GameState.saved_team_count() == 0 and GameState.favorites.is_empty())
	GameState._load_saved_teams({ "saved_teams": [{ "id": 5, "name": "x", "members": ["a", "a", 7] }, "basura", { "name": "sin id" }], "next_team_id": 1 })
	_check("equipos mal formados se descartan sin romper y sin ids repetidos", GameState.saved_team_count() == 1 and GameState.saved_team_list()[0]["members"][1] == "" and GameState._next_team_id >= 6)
	# autoconfiguracion
	GameState.roster = mine.duplicate()
	for id in mine:
		GameState.progress[id] = { "level": 10, "xp": 0 }
	GameState.battle_source = "story"
	var proposal := GameState.autoconfigure_team("party")
	var members: Array = proposal.get("members", [])
	var unique := {}
	for id in members:
		unique[id] = true
	_check("autoconfigurar propone 4 personajes distintos de tu coleccion", bool(proposal["ok"]) and members.size() == 4 and unique.size() == 4)
	var owned_only := true
	for id in members:
		owned_only = owned_only and mine.has(id)
	_check("la propuesta solo usa personajes que tienes y trae motivos", owned_only and not (proposal["parts"] as Array).is_empty())
	var party_before: Array = GameState.party.duplicate()
	GameState.autoconfigure_team("party")
	_check("proponer NO cambia el equipo; aplicar si", GameState.party == party_before)
	GameState.apply_autoconfigured(members, "party")
	_check("aplicar la propuesta pone el equipo y se puede modificar despues", GameState.party_count() == 4)
	var tower_prop := GameState.autoconfigure_team("tower")
	_check("la propuesta de torre trae 5 personajes", (tower_prop["members"] as Array).size() == 5)
	_check("sin personajes no hay propuesta pero tampoco error", _empty_proposal())
	# panel
	var panel = load("res://ui/saved_teams_panel.gd").new()
	panel.setup("party")
	add_child(panel)
	_check("la ventana de equipos guardados se construye", panel.get_node_or_null("List") != null or panel.find_child("List", true, false) != null)
	panel.queue_free()
	# pantalla EQUIPO con los botones nuevos
	var screen = load("res://scenes/screens/team.tscn").instantiate()
	add_child(screen)
	screen.call("refresh")
	_check("la pantalla EQUIPO trae EQUIPOS, AUTO y FAVORITO", screen.find_child("TeamsButton", true, false) != null and screen.find_child("AutoButton", true, false) != null and screen.find_child("FavButton", true, false) != null)
	var party_pre: Array = GameState.party.duplicate()
	screen.call("_on_auto_pressed")
	_check("AUTO ensena la propuesta sin cambiar el equipo", GameState.party == party_pre and not (screen.get("_auto_proposal") as Dictionary).is_empty())
	screen.call("_on_auto_pressed")
	_check("el segundo toque de AUTO la aplica", (screen.get("_auto_proposal") as Dictionary).is_empty() and GameState.party_count() == 4)
	screen.call("_open_saved_teams")
	_check("EQUIPOS abre la ventana", screen.get_node_or_null("SavedTeamsPanel") != null)
	screen.queue_free()
	# torre: botones y autoconfiguracion de 5
	var tower_screen = load("res://scenes/screens/tower.tscn").instantiate() if ResourceLoader.exists("res://scenes/screens/tower.tscn") else null
	if tower_screen != null:
		add_child(tower_screen)
		tower_screen.call("refresh")
		_check("la pantalla de torre trae EQUIPOS y AUTO", tower_screen.find_child("TeamsButton", true, false) != null and tower_screen.find_child("AutoButton", true, false) != null)
		GameState.tower_team = ["", "", "", "", ""]
		tower_screen.call("_on_auto_pressed")
		_check("AUTO en la torre llena los 5 puestos", GameState.tower_team_count() == 5)
		tower_screen.queue_free()
	for scene_path in ["res://scenes/screens/world_map.tscn", "res://scenes/screens/events.tscn"]:
		var pre_screen = load(scene_path).instantiate()
		add_child(pre_screen)
		if pre_screen.has_method("refresh"):
			pre_screen.call("refresh")
		await get_tree().process_frame
		_check("%s abre con su boton EQUIPO previo al combate" % scene_path.get_file(), pre_screen.find_child("TeamButton", true, false) != null)
		pre_screen.queue_free()
	# ventana previa al combate: AUTO propone y aplica; ofrece crear/ajustar
	var pre = load("res://ui/saved_teams_panel.gd").open_on(self, "party", true)
	_check("la ventana previa al combate ofrece crear o ajustar el equipo", pre.find_child("OpenTeamScreen", true, false) != null and pre.find_child("Auto", true, false) != null)
	var pre_party: Array = GameState.party.duplicate()
	pre.call("_on_auto")
	_check("AUTO en la ventana no toca el equipo hasta confirmar", GameState.party == pre_party)
	pre.queue_free()


func _empty_proposal() -> bool:
	var keep: Array = GameState.roster.duplicate()
	GameState.roster = []
	var result := GameState.autoconfigure_team("party")
	GameState.roster = keep
	return not bool(result["ok"]) and not String(result["reason"]).is_empty()
