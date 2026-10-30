extends Node

const CombatUnit := preload("res://core/combat_unit.gd")
const BattleMath := preload("res://core/battle_math.gd")
const EffectEngine := preload("res://core/effect_engine.gd")
const StatBlock := preload("res://core/stat_block.gd")

## Flujo del combate por turnos. No sabe nada de UI ni de personajes concretos:
## recibe datos, construye CombatUnit y orquesta rondas, turnos y acciones.
##
## Las acciones del jugador llegan por submit_action() y se resuelven esperando
## la senal interna action_chosen, asi que el flujo del turno es una corrutina
## legible en lugar de una maquina de estados dispersa.
##
## V0.3: ademas del flujo, este nodo es la unica fuente de verdad de dos cosas
## que la UI se limita a leer:
##   - el orden de ataque real (order + order_cursor, signal order_changed)
##   - las estadisticas de la batalla (_record_stats -> CombatUnit.battle)
## El registro de texto sale por log_added con una etiqueta ("damage", "crit",
## "buff"...) para que la UI pueda darle color sin interpretar el mensaje.

signal battle_started
signal round_started(round_number: int, order_names: Array)
## Orden real de la ronda y posicion del que actua ahora. cursor == -1 significa
## "nadie ha empezado todavia".
signal order_changed(units: Array, cursor: int)
signal turn_started(unit)
signal action_requested(unit)
signal action_chosen(payload: Dictionary)
signal action_resolved(payload: Dictionary)
signal log_added(text: String, kind: String)
signal battle_finished(victory: bool, rounds: int)
## Un aliado ha caido y una RESERVA ocupa su puesto (torre). La UI cambia la tarjeta.
signal reserve_entered(out_unit, in_unit, slot_index: int)
## Una ULTIMATE de forma (LR) empieza a resolverse. La UI cambia la musica y lanza su
## presentacion; la logica del golpe ya se resuelve en la misma llamada.
signal ultimate_started(unit)
## v14. Presentacion de un jefe al empezar el combate. La UI la pinta y avisa con
## close_intro() (o el jugador la salta); sin UI conectada no se espera nada.
signal boss_intro(unit, intro: Dictionary)
signal intro_closed
## Un jefe entra en una fase nueva (index = numero de fase, 1 = la primera).
signal phase_changed(unit, index: int, phase: Dictionary)

const ENEMY_THINK_TIME := 0.7
const TURN_PAUSE := 0.15

const STUN_PAUSE := 0.4
## Pausa breve tras un cambio de fase (solo si hay UI que la pinte) y limite de
## seguridad de una presentacion: nunca puede dejar el combate colgado.
const PHASE_PAUSE := 1.0
const INTRO_MAX_SECONDS := 7.0
var _intro_open := false
var _phase_pause := 0.0
## Fases activadas en esta batalla: [{ unit, index, name }]. La leen las pruebas y
## las misiones de "derrotar jefes" no dependen de ello.
var phase_log: Array = []
## Reto de SUPERVIVENCIA (eventos): si es > 0, el combate se gana al terminar esa
## ronda con algun aliado en pie. 0 = combate normal.
var survive_rounds := 0

## Multiplicador de las PAUSAS entre turnos. Sale de GameSettings (autoload
## AJUSTES): velocidad normal = 1.0, rapida = menos espera. Las pausas del combate
## se calculan SIEMPRE multiplicando por aqui, para que el ajuste se note en todo
## el combate y no en un solo sitio.
var pause_scale := 1.0


func _on_setting_changed(key: String) -> void:
	if key == "battle_speed" and GameSettings != null:
		pause_scale = GameSettings.battle_pause_scale()


## Pausa real de un tiempo base, ya con el ajuste de velocidad aplicado.
func pause_time(base_seconds: float) -> float:
	return base_seconds * pause_scale

## Verificacion en ejecucion: deja en consola el critico base y el actual de cada
## unidad al empezar la ronda, y el del personaje que va a actuar. Sirve para
## comprobar que la pasiva de Isagi sube el numero y que vuelve a bajar cuando
## caduca. False en el juego normal.
const DEBUG_BATTLE := false
## MODO AUTO (boton AUTO del combate): los aliados eligen la accion por el jugador
## (ultimate > especial > basico, objetivo automatico). Se puede activar y
## desactivar a mitad de combate; empieza apagado en cada batalla.
var auto_mode := false
## Verdadero mientras el combate espera la accion de un aliado (lo usa set_auto).
var _awaiting_ally_action := false


func set_auto(enabled: bool) -> void:
	auto_mode = enabled
	# Si justo ahora se esta esperando al jugador, la accion se decide sola.
	if enabled and _awaiting_ally_action and not _finished:
		var unit := next_actor()
		if unit != null and unit.is_ally and unit.alive:
			submit_action({ "kind": _pick_auto_kind(unit), "target_key": "" })


func _pick_auto_kind(unit: CombatUnit) -> String:
	if can_use(unit, "ultimate"):
		return "ultimate"
	if can_use(unit, "special"):
		return "special"
	return "basic"


## Los aliados actuan solos, como el enemigo. SOLO para la verificacion en
## ejecucion: con esto se pueden leer varias rondas de tiradas sin tocar
## pantalla. En el juego normal va en false.
const DEBUG_AUTOPLAY := false

var allies: Array = []
## Reservas en espera (CombatUnit ya construidos, con links/lider/mutacion
## aplicados). Entran por rotacion en el puesto de un aliado caido.
var reserves: Array = []
## Todo el que ha pisado el combate (activos + reservas que entraron): son los
## que cobran XP, aunque hayan caido despues.
var _participants: Array = []
var enemies: Array = []
var order: Array = []
## Indice de quien tiene el turno dentro de order.
var order_cursor := -1
var round_number := 0
var lines: Array = []

var _rng := RandomNumberGenerator.new()
var _finished := false
## Links del equipo que han quedado ACTIVOS en esta batalla. Se resuelve una vez
## al construir la formacion y la pantalla de combate lo lee para su aviso.
var _team_link_ids: Array = []
## Tipo de la ultima accion resuelta: la ULTI hace una pausa mas larga para que se
## vea la animacion antes de seguir con el siguiente turno.
var _last_action_kind := ""
const ULTIMATE_PAUSE := 0.9
## Pausa tras una ULTIMATE de forma: lo que dura su presentacion en pantalla.
const ULTIMATE_CINEMATIC_PAUSE := 3.0


func setup(ally_data: Array, enemy_data: Array, reserve_data: Array = []) -> void:
	allies = []
	reserves = []
	_participants = []
	enemies = []
	order = []
	order_cursor = -1
	lines = []
	round_number = 0
	_finished = false
	_rng.randomize()
	# El ajuste de velocidad de combate se lee UNA vez por batalla: si el jugador
	# lo cambia en AJUSTES, la siguiente batalla ya va distinto.
	pause_scale = GameSettings.battle_pause_scale() if GameSettings != null else 1.0
	# La velocidad se puede cambiar EN el combate (boton de la pantalla): se reaplica.
	if GameSettings != null and not GameSettings.changed.is_connected(_on_setting_changed):
		GameSettings.changed.connect(_on_setting_changed)

	var index := 0
	for data in ally_data:
		var unit := CombatUnit.new()
		unit.setup(data, true, index)
		allies.append(unit)
		_participants.append(unit.id)
		index += 1
	var reserve_index := index
	for data in reserve_data:
		var reserve_unit := CombatUnit.new()
		reserve_unit.setup(data, true, reserve_index)
		reserves.append(reserve_unit)
		reserve_index += 1

	index = 0
	for data in enemy_data:
		var unit := CombatUnit.new()
		unit.setup(data, false, index)
		enemies.append(unit)
		index += 1

	# Los links se enganchan AQUI: en cuanto la formacion existe y ANTES de que
	# empiece ningun turno (battle_started se emite despues). Este es el unico
	# sitio donde entran: setup() se llama una vez por batalla y cada batalla
	# construye sus CombatUnit desde cero, asi que no hay acumulacion entre
	# batallas ni entre turnos.
	_apply_team_links()
	# La Leader Skill del personaje de la POSICION 1 y la mutacion de cada aliado
	# entran por el mismo camino que los links: una vez por batalla, solo en los
	# aliados y con un origen propio, asi que core/stat_block.gd sigue siendo el
	# unico sitio que calcula el valor final.
	_apply_leader_skill()
	_apply_mutations()
	_attach_link_rules()
	# Las reservas esperan ya "armadas": mismos links, lider y mutacion que los activos.
	for reserve_unit in reserves:
		if not _team_link_ids.is_empty():
			GameState.apply_link_mods(reserve_unit.stats, reserve_unit.id)
		if not GameState.leader_report().is_empty():
			GameState.apply_leader_mods(reserve_unit.stats, reserve_unit.id)
		GameState.apply_mutation_mods(reserve_unit.stats, reserve_unit.id)
		reserve_unit.link_rules = GameState.link_rules_for(reserve_unit.id)


func start_battle() -> void:
	if allies.is_empty() or enemies.is_empty():
		push_error("BattleManager: no hay unidades suficientes para combatir.")
		return
	_log("Comienza el combate.", "system")
	battle_started.emit()
	await _run()


func submit_action(payload: Dictionary) -> void:
	action_chosen.emit(payload)


func can_use(unit: CombatUnit, kind: String) -> bool:
	var skill := unit.skill_by_kind(kind)
	if skill.is_empty():
		return false
	# La ultimate: una sola vez POR COMBATE, y nunca con el combate ya terminado
	# (la pantalla de resultados no puede relanzarla).
	if kind == "ultimate" and (unit.ultimate_used or _finished or not unit.is_ally):
		return false
	return unit.sp >= _skill_cost(unit, skill)


func find_unit(key: String) -> CombatUnit:
	for unit in allies:
		if unit.source_key == key:
			return unit
	for unit in enemies:
		if unit.source_key == key:
			return unit
	return null


## Unidad que actua en el turno actual de la ronda, o null si la ronda esta
## terminando. Lo usa la UI para marcar "PROXIMO" en la barra de orden.
func next_actor() -> CombatUnit:
	if order_cursor < 0 or order_cursor >= order.size():
		return null
	return order[order_cursor]


func _run() -> void:
	await _play_intros()
	_apply_passives("battle_start", _everyone())
	_check_low_hp_all()
	if not _team_link_ids.is_empty():
		_log("Links activos: %s" % ", ".join(_link_names()), "buff")
	# La Leader Skill tambien se anuncia: el jugador tiene que poder ver que su
	# lider esta haciendo algo, igual que ve los links.
	var leader_line: Dictionary = GameState.leader_report()
	if not leader_line.is_empty():
		_log("Lider %s: %s" % [String(leader_line.get("name", "")), String(leader_line.get("description", ""))], "buff")
	while not _finished:
		round_number += 1
		_build_order()
		order_cursor = 0
		if DEBUG_BATTLE:
			_debug_crit_snapshot()
		round_started.emit(round_number, order_names())
		_emit_order()
		for index in order.size():
			if _finished:
				break
			var unit: CombatUnit = order[index]
			if not unit.alive:
				continue
			order_cursor = index
			_emit_order()
			await _take_turn(unit)
			_check_end()
			_emit_order()
		if _finished:
			break
		_tick_round_end()


func _take_turn(unit: CombatUnit) -> void:
	turn_started.emit(unit)

	# Sangrado, quemadura, veneno y regeneracion se resuelven al empezar el turno.
	_tick_periodics(unit)
	_check_phases()
	if not unit.alive:
		return

	if unit.is_stunned():
		_log("%s esta aturdido y pierde el turno." % unit.display_name, "status")
		action_resolved.emit({ "actor_key": unit.source_key, "actor_name": unit.display_name, "skill_name": "", "hits": [] })
		unit.tick_statuses()
		await get_tree().create_timer(STUN_PAUSE * pause_scale).timeout
		return

	_apply_passives("turn_start", [unit])
	if DEBUG_BATTLE:
		print("[DBG] turno %s: crit actual=%d%%" % [
			unit.display_name,
			int(round(BattleMath.crit_chance(unit) * 100.0)),
		])
		_debug_mods(unit, "turno")

	if unit.is_ally and DEBUG_AUTOPLAY:
		await get_tree().create_timer(ENEMY_THINK_TIME * pause_scale).timeout
		_perform(unit, _pick_enemy_kind(unit))
	elif unit.is_ally and auto_mode:
		await get_tree().create_timer(ENEMY_THINK_TIME * pause_scale).timeout
		# Si el jugador apago AUTO durante la espera, la mano vuelve a el.
		if auto_mode:
			_perform(unit, _pick_auto_kind(unit))
		else:
			action_requested.emit(unit)
			_awaiting_ally_action = true
			var manual: Dictionary = await action_chosen
			_awaiting_ally_action = false
			_perform(unit, String(manual.get("kind", "basic")), String(manual.get("target_key", "")))
	elif unit.is_ally:
		action_requested.emit(unit)
		_awaiting_ally_action = true
		var payload: Dictionary = await action_chosen
		_awaiting_ally_action = false
		# El objetivo elegido por el jugador viaja con la accion. Si no lo manda
		# (o ya no es valido) el combate elige por el.
		_perform(unit, String(payload.get("kind", "basic")), String(payload.get("target_key", "")))
	else:
		await get_tree().create_timer(ENEMY_THINK_TIME * pause_scale).timeout
		_perform(unit, _pick_enemy_kind(unit))

	unit.tick_statuses()
	if _finished:
		return
	if _last_action_kind == "ultimate":
		await get_tree().create_timer(ULTIMATE_CINEMATIC_PAUSE * pause_scale).timeout
	elif _last_action_kind == "special":
		await get_tree().create_timer(ULTIMATE_PAUSE * pause_scale).timeout
	await get_tree().create_timer(TURN_PAUSE * pause_scale).timeout
	if _phase_pause > 0.0 and not _finished:
		var wait := _phase_pause
		_phase_pause = 0.0
		await get_tree().create_timer(wait * pause_scale).timeout


func _perform(actor: CombatUnit, kind: String, target_key: String = "") -> void:
	# Una ultimate no valida (ya usada, sin SP, combate terminado o sin ella) se
	# degrada a ataque basico, igual que un especial sin SP: la accion nunca se pierde.
	if kind == "ultimate" and not can_use(actor, "ultimate"):
		kind = "basic"
	_last_action_kind = kind
	var skill := actor.skill_by_kind(kind)
	if skill.is_empty():
		return
	var cost := _skill_cost(actor, skill)
	if cost > actor.sp:
		skill = actor.skill_by_kind("basic")
		cost = 0
		kind = "basic"
		_last_action_kind = kind
	if skill.is_empty():
		return
	if cost > 0:
		actor.sp = maxi(0, actor.sp - cost)
	if kind == "ultimate":
		actor.ultimate_used = true
		_log("%s: %s" % [actor.display_name, String(skill.get("name", "ULTIMATE"))], "buff")
		ultimate_started.emit(actor)

	var team: Array = allies if actor.is_ally else enemies
	var foes: Array = enemies if actor.is_ally else allies
	var primary := _pick_target(actor, skill, target_key)
	var ctx := {
		"actor": actor,
		"target": primary,
		"team": team,
		"foes": foes,
		"rng": _rng,
		"source": "skill:%s" % String(skill.get("id", kind)),
		"round": round_number,
	}
	var skill_name := String(skill.get("name", kind))
	var hits: Array = []
	var damaged: Array = []   # unidades golpeadas (para disparadores y caidas)

	var power := float(skill.get("power", 0.0))
	if power > 0.0:
		# Habilidades v12: bonus condicionales, perforacion, robo de vida y golpes
		# multiples. Sin esos campos la habilidad es la de siempre.
		var hit_ctx := ctx.duplicate()
		hit_ctx["power_mult"] = 1.0
		hit_ctx["pierce"] = float(skill.get("pierce", 0.0))
		hit_ctx["lifesteal"] = float(skill.get("lifesteal", 0.0))
		var repeats := maxi(1, int(skill.get("hits", 1)))
		for target in EffectEngine.resolve_targets(String(skill.get("target", "enemy")), ctx):
			# El bonus se evalua por objetivo: "si tiene menos del 40% de vida".
			var target_ctx := ctx.duplicate()
			target_ctx["target"] = target
			hit_ctx["power_mult"] = EffectEngine.power_multiplier(skill, target_ctx)
			for _i in repeats:
				if not target.alive:
					break
				hits.append(BattleMath.deal_damage(actor, target, power, hit_ctx))
				if not damaged.has(target):
					damaged.append(target)

	var effects: Array = skill.get("effects", [])
	if not effects.is_empty():
		hits.append_array(EffectEngine.apply_effects(effects, ctx))

	# Retroceso: el precio de una habilidad muy fuerte (fraccion de la vida maxima).
	var recoil := float(skill.get("recoil", 0.0))
	if recoil > 0.0 and actor.alive:
		var lost := actor.take_damage(roundf(actor.max_hp() * recoil))
		hits.append({ "kind": "recoil", "target_key": actor.source_key, "target_name": actor.display_name, "value": lost })

	# Atacar con el ataque basico genera SP; tambien lo genera recibir un golpe.
	if cost == 0 and kind != "ultimate":
		actor.gain_sp(1)
	for hit in hits:
		if String(hit.get("kind", "")) == "damage" and not bool(hit.get("dodged", true)):
			var victim := find_unit(String(hit.get("target_key", "")))
			if victim != null and victim.alive:
				victim.gain_sp(1)

	_log_action(actor.display_name, skill_name, hits)
	_record_stats(actor, skill, hits)
	action_resolved.emit({
		"actor_key": actor.source_key,
		"actor_name": actor.display_name,
		"skill_name": skill_name,
		"kind": String(skill.get("kind", "basic")),
		"hits": hits,
	})
	# Consecuencias: reglas con disparador (al golpear, al recibir, critico, caida...).
	_after_action(actor, kind, skill, hits, primary)


## --- Reglas con disparador (v12) ---------------------------------------------
## Pasivas y links comparten formato: { id, name, trigger, chance, once, cooldown,
## threshold, condition, effects }. Aqui se decide CUANDO se disparan; el motor de
## efectos (EffectEngine) decide QUE hacen.

func _after_action(actor: CombatUnit, kind: String, skill: Dictionary, hits: Array, primary) -> void:
	var landed := false
	var crit := false
	var killed: Array = []
	var hit_victims: Array = []
	var dodgers: Array = []
	for hit in hits:
		if String(hit.get("kind", "")) != "damage":
			continue
		var victim := find_unit(String(hit.get("target_key", "")))
		if victim == null:
			continue
		if bool(hit.get("dodged", false)):
			if not dodgers.has(victim):
				dodgers.append(victim)
			continue
		landed = true
		if bool(hit.get("crit", false)):
			crit = true
		if not hit_victims.has(victim):
			hit_victims.append(victim)
		if not victim.alive and not killed.has(victim):
			killed.append(victim)
	if landed and actor.alive:
		_fire_rules("on_attack", actor, { "target": hit_victims[0] })
		if crit:
			_fire_rules("on_crit", actor, { "target": hit_victims[0] })
		if kind in ["special", "ultimate"]:
			_fire_rules("on_special", actor, { "target": hit_victims[0] })
	elif kind in ["special", "ultimate"] and actor.alive and not landed:
		_fire_rules("on_special", actor, { "target": primary })
	for victim in hit_victims:
		if victim.alive:
			_fire_rules("on_hit", victim, { "target": actor })
	for victim in dodgers:
		if victim.alive:
			_fire_rules("on_dodge", victim, { "target": actor })
	for victim in killed:
		if actor.alive:
			_fire_rules("on_kill", actor, { "target": victim })
			var refund := int(skill.get("sp_refund", 0))
			if refund > 0:
				actor.gain_sp(refund)
				_log("%s recupera %d SP al derrotar a %s" % [actor.display_name, refund, victim.display_name], "sp")
	_check_low_hp_all()
	_after_deaths(actor)


## Un aliado que cae avisa a los que quedan en pie (on_ally_down).
func _after_deaths(_cause) -> void:
	for unit in _everyone():
		if unit.alive or unit.death_handled:
			continue
		unit.death_handled = true
		var team: Array = allies if unit.is_ally else enemies
		for mate in team:
			if mate.alive and mate != unit:
				_fire_rules("on_ally_down", mate, { "target": unit })


func _check_low_hp_all() -> void:
	_check_phases()
	for unit in _everyone():
		if unit.alive:
			_fire_rules("low_hp", unit)


func _fire_rules(trigger: String, unit: CombatUnit, extra: Dictionary = {}) -> void:
	if not unit.alive or _finished:
		return
	for rule in unit.rules_for_trigger(trigger):
		_try_rule(unit, rule, trigger, extra)


func _rule_key(rule: Dictionary, trigger: String) -> String:
	return String(rule.get("id", trigger))


func _try_rule(unit: CombatUnit, rule: Dictionary, trigger: String, extra: Dictionary) -> bool:
	var effects: Array = rule.get("effects", [])
	if effects.is_empty():
		return false
	var key := _rule_key(rule, trigger)
	var state: Dictionary = unit.rule_state.get(key, { "used": 0, "next_round": 0 })
	if bool(rule.get("once", false)) and int(state["used"]) > 0:
		return false
	if round_number < int(state["next_round"]):
		return false
	if trigger == "low_hp" and unit.hp_ratio() >= float(rule.get("threshold", 0.35)):
		return false
	var team: Array = allies if unit.is_ally else enemies
	var foes: Array = enemies if unit.is_ally else allies
	var ctx := {
		"actor": unit,
		"target": extra.get("target", null),
		"team": team,
		"foes": foes,
		"rng": _rng,
		"source": "%s:%s" % ["link" if String(rule.get("origin", "")) == "link" else "passive", key],
		"round": round_number,
		"from_passive": true,
	}
	var rule_condition: Dictionary = rule.get("condition", {})
	if not rule_condition.is_empty() and not EffectEngine.check_condition(rule_condition, ctx):
		return false
	var chance := float(rule.get("chance", 1.0))
	if chance < 1.0 and _rng.randf() >= chance:
		return false
	var results := EffectEngine.apply_effects(effects, ctx)
	if results.is_empty():
		return false
	state["used"] = int(state["used"]) + 1
	state["next_round"] = round_number + int(rule.get("cooldown", 0))
	unit.rule_state[key] = state
	var rule_name := String(rule.get("name", "Sin nombre"))
	var origin_text := "Link %s" % rule_name if String(rule.get("origin", "")) == "link" else rule_name
	_log("%s activa %s" % [unit.display_name, origin_text], "passive")
	_record_passive_stats(unit, results)
	action_resolved.emit({
		"actor_key": unit.source_key,
		"actor_name": unit.display_name,
		"skill_name": origin_text,
		"kind": "passive" if trigger in ["battle_start", "turn_start"] else "rule",
		"hits": results,
	})
	# Un efecto de una regla puede matar (contraataque, dano): se resuelven sus
	# consecuencias sin volver a disparar on_hit/on_attack (from_passive).
	for result in results:
		if String(result.get("kind", "")) == "damage" and not bool(result.get("dodged", false)):
			var victim := find_unit(String(result.get("target_key", "")))
			if victim != null and not victim.alive and unit.alive:
				_fire_rules("on_kill", unit, { "target": victim })
	_check_low_hp_all()
	_after_deaths(unit)
	_check_end()
	return true


## Sangrado/quemadura/veneno/regeneracion al empezar el turno del portador.
func _tick_periodics(unit: CombatUnit) -> void:
	if unit.periodics.is_empty():
		return
	var hits: Array = []
	var kept: Array = []
	for entry in unit.periodics:
		var amount := float(entry["per_turn"])
		if String(entry["kind"]) == "regen":
			var healed := unit.heal(amount)
			hits.append({ "kind": "heal", "target_key": unit.source_key, "target_name": unit.display_name, "value": healed })
		else:
			var dealt := unit.take_damage(roundf(amount))
			hits.append({ "kind": "dot", "target_key": unit.source_key, "target_name": unit.display_name, "value": dealt, "status": String(entry["kind"]) })
		entry["turns"] = int(entry["turns"]) - 1
		if int(entry["turns"]) > 0:
			kept.append(entry)
	unit.periodics = kept
	for hit in hits:
		_log_action("", "", [hit])
	action_resolved.emit({
		"actor_key": unit.source_key,
		"actor_name": unit.display_name,
		"skill_name": "",
		"kind": "periodic",
		"hits": hits,
	})
	_check_low_hp_all()
	_after_deaths(null)
	_check_end()


func _attach_link_rules() -> void:
	for unit in allies:
		unit.link_rules = GameState.link_rules_for(unit.id)


## Los links ACTIVOS del equipo del jugador entran en las estadisticas de cada
## ALIADO antes de que empiece el primer turno. Los enemigos NO pasan por aqui:
## los links son sinergias de la formacion del jugador, no del rival.
##
## GameState.apply_link_mods aplica cada efecto con StatBlock.add_mod y un origen
## propio ("link:<id>"), asi que core/stat_block.gd sigue siendo el unico sitio
## que calcula el valor final y volver a aplicar el mismo link SUSTITUYE el mod
## anterior en vez de sumarlo (StatBlock.add_mod quita el origen antes de anadir).
## Los aliados con links activos se anuncian por la senal battle_started para que
## la pantalla pueda avisar sin conocer las reglas.
func _apply_team_links() -> void:
	_team_link_ids = GameState.active_link_ids()
	if _team_link_ids.is_empty():
		return
	for unit in allies:
		if unit.is_ally:
			GameState.apply_link_mods(unit.stats, unit.id)


func active_team_link_ids() -> Array:
	return _team_link_ids.duplicate()


## Nombres legibles de los links activos, para el aviso del combate. Los datos
## salen de DB: aqui no se escribe ni un nombre de link.
func active_team_link_names() -> Array:
	return _link_names()


func _link_names() -> Array:
	var names: Array = []
	for link_id in _team_link_ids:
		var link := DB.get_link(String(link_id))
		names.append(String(link.get("name", link_id)))
	return names


## Leader Skill del equipo. Solo cuenta la del personaje de la POSICION 1:
## GameState decide quien es y a que aliados afecta (por tipo o por categoria) y
## aqui solo se aplica. Entra ANTES del primer turno, como los links.
func _apply_leader_skill() -> void:
	var leader: Dictionary = GameState.leader_report()
	if leader.is_empty():
		return
	for unit in allies:
		if unit.is_ally:
			GameState.apply_leader_mods(unit.stats, unit.id)


## Mutacion de cada aliado. La mutacion es del PERSONAJE y sobrevive a las
## evoluciones; el combate solo la aplica. Los enemigos no estan en el roster, asi
## que no tienen mutacion y aqui solo se recorren los aliados.
func _apply_mutations() -> void:
	for unit in allies:
		if unit.is_ally:
			GameState.apply_mutation_mods(unit.stats, unit.id)


## Coste REAL de una habilidad: el "cost" del JSON menos lo que le quite la
## mutacion (solo la Z lo hace, y nunca por debajo del minimo de los datos).
## GameState.mutation_sp_cost es el unico sitio que lo calcula, asi que el boton,
## el turno del enemigo y el gasto real usan el mismo numero.
func _skill_cost(unit: CombatUnit, skill: Dictionary) -> int:
	if skill.is_empty():
		return 0
	return GameState.mutation_sp_cost(unit.id, int(skill.get("cost", 0)))


## Aplica la pasiva de cada unidad cuyo trigger coincida. Los efectos son datos,
## asi que anadir pasivas nuevas no toca este archivo.
func _apply_passives(trigger: String, units: Array) -> void:
	for unit in units:
		if not unit.alive or _finished:
			continue
		# Pasivas del personaje (una, o dos si ha evolucionado) y reglas de sus
		# links. Cada una usa su propio "source": dos reglas sobre la misma stat se
		# SUMAN (origenes distintos) en lugar de sustituirse.
		for rule in unit.rules_for_trigger(trigger):
			_try_rule(unit, rule, trigger, {})


## --- Estadisticas de la batalla -------------------------------------------
## Unico sitio donde suben los contadores. Cada rama comprueba que la accion ha
## ocurrido de verdad (un golpe esquivado no cuenta como dano hecho ni recibido).

func _record_stats(actor: CombatUnit, skill: Dictionary, hits: Array) -> void:
	if actor.battle == null:
		return
	if String(skill.get("kind", "basic")) in ["special", "ultimate"]:
		actor.battle.add("specials")
	else:
		actor.battle.add("basic_attacks")

	for hit in hits:
		var victim := find_unit(String(hit.get("target_key", "")))
		if victim == null:
			continue
		match String(hit.get("kind", "")):
			"damage":
				if bool(hit.get("dodged", false)):
					victim.battle.add("dodges")
				else:
					var dealt := int(round(float(hit.get("value", 0.0))))
					actor.battle.add("damage_dealt", dealt)
					actor.battle.add("hits_dealt")
					if bool(hit.get("crit", false)):
						actor.battle.add("crits")
					victim.battle.add("damage_received", dealt)
					victim.battle.add("hits_received")
			"heal":
				var healed := int(round(float(hit.get("value", 0.0))))
				if healed > 0:
					actor.battle.add("healing_done", healed)
					victim.battle.add("healing_received", healed)
			"stat_mod":
				if StatBlock.mod_is_beneficial(String(hit.get("stat", "")), float(hit.get("value", 0.0))):
					actor.battle.add("buffs_applied")
				else:
					actor.battle.add("debuffs_applied")
			"status", "dispel", "sp_drain":
				actor.battle.add("debuffs_applied")
			"shield":
				actor.battle.add("buffs_applied")
			"periodic":
				if String(hit.get("status", "")) == "regen":
					actor.battle.add("buffs_applied")
				else:
					actor.battle.add("debuffs_applied")


## Una pasiva tambien reparte buffs, debuffs y curaciones: se cuentan igual.
func _record_passive_stats(unit: CombatUnit, results: Array) -> void:
	if unit.battle == null:
		return
	for hit in results:
		var target := find_unit(String(hit.get("target_key", "")))
		match String(hit.get("kind", "")):
			"damage":
				var dealt := int(round(float(hit.get("value", 0.0))))
				unit.battle.add("damage_dealt", dealt)
				unit.battle.add("hits_dealt")
				if target != null and not bool(hit.get("dodged", false)):
					target.battle.add("damage_received", dealt)
					target.battle.add("hits_received")
			"heal":
				var healed := int(round(float(hit.get("value", 0.0))))
				if healed > 0:
					unit.battle.add("healing_done", healed)
					if target != null:
						target.battle.add("healing_received", healed)
			"stat_mod":
				if StatBlock.mod_is_beneficial(String(hit.get("stat", "")), float(hit.get("value", 0.0))):
					unit.battle.add("buffs_applied")
				else:
					unit.battle.add("debuffs_applied")
			"status", "dispel", "sp_drain":
				unit.battle.add("debuffs_applied")
			"shield":
				unit.battle.add("buffs_applied")
			"periodic":
				if String(hit.get("status", "")) == "regen":
					unit.battle.add("buffs_applied")
				else:
					unit.battle.add("debuffs_applied")


## Lado al que apunta una habilidad. Cadena vacia = afecta a varios y no hay nada
## que elegir. Es lo que consulta la UI para decidir si abre el modo "elige
## objetivo", asi que la regla vive aqui y no en la pantalla.
func target_side(unit: CombatUnit, kind: String) -> String:
	var skill := unit.skill_by_kind(kind)
	if skill.is_empty():
		return ""
	var spec := String(skill.get("target", "enemy"))
	if spec == "self":
		return "self"
	if spec.ends_with("_all") or spec == "ally_lowest":
		return ""
	if spec.begins_with("ally"):
		return "ally"
	return "enemy"


## Unidades que el jugador puede senalar con esa habilidad.
func candidates(unit: CombatUnit, kind: String) -> Array:
	var team: Array = allies if unit.is_ally else enemies
	var foes: Array = enemies if unit.is_ally else allies
	match target_side(unit, kind):
		"ally":
			return _alive_only(team)
		"enemy":
			return _apply_taunt(_alive_only(foes), unit)
		"self":
			return [unit]
	return []


## Solo se pregunta cuando hay algo que decidir: con un unico candidato el combate
## elige por el jugador y el turno no se alarga con un toque de mas.
func needs_target(unit: CombatUnit, kind: String) -> bool:
	return candidates(unit, kind).size() > 1


func _pick_target(actor: CombatUnit, skill: Dictionary, preferred_key: String = "") -> CombatUnit:
	var team: Array = allies if actor.is_ally else enemies
	var foes: Array = enemies if actor.is_ally else allies
	var pool: Array = team if String(skill.get("target", "enemy")).begins_with("ally") else foes
	pool = _apply_taunt(pool, actor)
	# El objetivo elegido por el jugador manda, siempre que siga siendo valido
	# (vivo y del bando correcto). Si no, el combate decide solo.
	if not preferred_key.is_empty():
		for unit in pool:
			if unit.source_key == preferred_key and unit.alive:
				return unit
	return _lowest_hp(pool)


## PROVOCAR: si algun rival vivo provoca, los ataques a UN objetivo solo pueden
## apuntar a los que provocan. Los ataques a todos no se ven afectados.
func _apply_taunt(pool: Array, actor: CombatUnit) -> Array:
	if pool.is_empty() or pool[0].is_ally == actor.is_ally:
		return pool
	var taunters: Array = []
	for unit in pool:
		if unit.alive and unit.has_status("taunt"):
			taunters.append(unit)
	return taunters if not taunters.is_empty() else pool


func _pick_enemy_kind(unit: CombatUnit) -> String:
	# Patron de la fase actual (v14): cicla por las acciones que declara; si la
	# que toca es el especial y no hay SP, ataca normal. Sin patron, como siempre.
	if not unit.pattern.is_empty():
		var wanted := String(unit.pattern[unit.pattern_step % unit.pattern.size()])
		unit.pattern_step += 1
		var chosen := unit.skill_by_kind(wanted)
		if not chosen.is_empty() and unit.sp >= _skill_cost(unit, chosen):
			return wanted
		return "basic"
	var special := unit.skill_by_kind("special")
	if not special.is_empty() and unit.sp >= _skill_cost(unit, special):
		return "special"
	return "basic"


func _build_order() -> void:
	order = []
	order.append_array(_alive_only(allies))
	order.append_array(_alive_only(enemies))
	order.sort_custom(func(a, b): return a.speed() > b.speed())
	if randomize_ally_order:
		_shuffle_allies_in_order()


## ORDEN ALEATORIO DEL EQUIPO (v11). La velocidad sigue repartiendo los TURNOS entre
## bandos (en que posiciones de la ronda actuan aliados y en cuales enemigos), pero
## QUIEN de tus personajes ocupa cada una de esas posiciones se sortea en cada ronda,
## para que no ataquen siempre en el mismo orden. Cada aliado vivo actua exactamente
## una vez por ronda y los enemigos no se tocan.
var randomize_ally_order := true


func _shuffle_allies_in_order() -> void:
	var slots: Array = []
	var team: Array = []
	for i in order.size():
		if order[i].is_ally:
			slots.append(i)
			team.append(order[i])
	if team.size() < 2:
		return
	# Fisher-Yates con el generador del combate.
	for i in range(team.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = team[i]
		team[i] = team[j]
		team[j] = tmp
	for k in slots.size():
		order[slots[k]] = team[k]


## Solo para la verificacion en ejecucion (DEBUG_BATTLE): que modificadores
## estan vivos de verdad en una unidad.
func _debug_mods(unit: CombatUnit, tag: String) -> void:
	var mods := unit.stats.active_mods()
	if mods.is_empty():
		print("[DBG-MOD] %s %s: sin modificadores" % [tag, unit.display_name])
		return
	for mod in mods:
		print("[DBG-MOD] %s %s: %s %s %s turns=%d src=%s" % [
			tag,
			unit.display_name,
			String(mod["stat"]),
			String(mod["kind"]),
			str(mod["value"]),
			int(mod["turns"]),
			String(mod["source"]),
		])


## Solo para la verificacion en ejecucion (DEBUG_BATTLE).
func _debug_crit_snapshot() -> void:
	for unit in _everyone():
		print("[DBG] ronda %d %s: %s crit base=%d%% actual=%d%%" % [
			round_number,
			"aliado" if unit.is_ally else "rival",
			unit.display_name,
			int(round(unit.base_stat("crit_rate") * 100.0)),
			int(round(BattleMath.crit_chance(unit) * 100.0)),
		])


## Avisa a la UI del orden real y de quien actua. Se llama al empezar la ronda,
## al empezar cada turno y al terminar cada accion (por si alguien ha caido).
func _emit_order() -> void:
	order_changed.emit(order, order_cursor)


func _tick_round_end() -> void:
	if survive_rounds > 0 and round_number >= survive_rounds and not _alive_only(allies).is_empty() and not _finished:
		_log("Has resistido %d rondas." % survive_rounds, "result")
		_finish(true)
		return
	for unit in _everyone():
		unit.stats.tick()
		unit.tick_round()
	if DEBUG_BATTLE:
		print("[DBG] --- fin de ronda %d ---" % round_number)
		for unit in _everyone():
			_debug_mods(unit, "fin-ronda")


func _check_end() -> bool:
	if _finished:
		return true
	_rotate_reserves()
	if _alive_only(enemies).is_empty():
		_finish(true)
		return true
	if _alive_only(allies).is_empty():
		_finish(false)
		return true
	return false


## Si un aliado ha caido y quedan reservas, la primera ocupa su puesto. Entra al
## empezar la siguiente ronda (el orden de la actual ya esta fijado).
func _rotate_reserves() -> void:
	if reserves.is_empty() or _alive_only(enemies).is_empty():
		return
	for i in allies.size():
		if reserves.is_empty():
			return
		var fallen: CombatUnit = allies[i]
		if fallen.alive:
			continue
		var incoming: CombatUnit = reserves.pop_front()
		allies[i] = incoming
		_participants.append(incoming.id)
		_log("%s cae. %s entra desde la reserva." % [fallen.display_name, incoming.display_name], "system")
		reserve_entered.emit(fallen, incoming, i)


## Ids de todo el que ha combatido (para repartir XP).
func participant_ids() -> Array:
	return _participants.duplicate()


func _finish(victory: bool) -> void:
	if _finished:
		return
	_finished = true
	if victory:
		_log("Victoria en la ronda %d." % round_number, "result")
	else:
		_log("Derrota en la ronda %d." % round_number, "result")
	battle_finished.emit(victory, round_number)


func order_names() -> Array:
	var names: Array = []
	for unit in order:
		names.append(unit.display_name)
	return names


func _everyone() -> Array:
	var all_units: Array = []
	all_units.append_array(allies)
	all_units.append_array(enemies)
	return all_units


func _alive_only(units: Array) -> Array:
	var result: Array = []
	for unit in units:
		if unit.alive:
			result.append(unit)
	return result


func _lowest_hp(units: Array) -> CombatUnit:
	var best: CombatUnit = null
	for unit in units:
		if not unit.alive:
			continue
		if best == null or unit.hp_ratio() < best.hp_ratio():
			best = unit
	return best


func _log(text: String, kind: String = "system") -> void:
	lines.append(text)
	log_added.emit(text, kind)


## El registro es de videojuego, no una salida de consola: lineas cortas y una
## etiqueta por linea para que la UI las coloree.
static func _periodic_label(kind: String) -> String:
	match kind:
		"bleed":
			return "SANGRADO"
		"burn":
			return "QUEMADURA"
		"poison":
			return "VENENO"
		"regen":
			return "REGENERACION"
	return kind.to_upper()


func _log_action(actor_name: String, skill_name: String, hits: Array) -> void:
	if hits.is_empty():
		if not skill_name.is_empty():
			_log("%s usa %s" % [actor_name, skill_name], "system")
		return
	for hit in hits:
		var kind := String(hit.get("kind", ""))
		var target_name := String(hit.get("target_name", "el objetivo"))
		match kind:
			"damage":
				if bool(hit.get("dodged", false)):
					_log("%s esquiva a %s" % [target_name, actor_name], "dodge")
				else:
					var amount := int(round(float(hit.get("value", 0.0))))
					var tag := "damage"
					var extra := ""
					# Un golpe critico se distingue del normal en el texto y en el
					# color: mismo dato que usa el motor para aplicar el x1.6.
					if bool(hit.get("crit", false)):
						tag = "crit"
						extra = "  CRITICO!"
					# Ventaja y desventaja de tipo, en una linea corta: el
					# jugador ve QUE ha pasado, nunca el multiplicador.
					var type_mult := float(hit.get("type_mult", 1.0))
					if type_mult > 1.0:
						extra += "  VENTAJA DE TIPO"
					elif type_mult < 1.0:
						extra += "  DESVENTAJA DE TIPO"
					if float(hit.get("absorbed", 0.0)) > 0.0:
						extra += "  (escudo -%d)" % int(round(float(hit.get("absorbed", 0.0))))
					if bool(hit.get("survived", false)):
						extra += "  ULTIMO ALIENTO!"
					if float(hit.get("lifesteal", 0.0)) > 0.0:
						extra += "  (roba %d)" % int(round(float(hit.get("lifesteal", 0.0))))
					_log("%s > %s  %d DMG%s" % [actor_name, target_name, amount, extra], tag)
			"heal":
				var healed := int(round(float(hit.get("value", 0.0))))
				if healed > 0:
					_log("%s > %s  +%d HP" % [actor_name, target_name, healed], "heal")
				else:
					# Curacion sobre alguien ya al maximo: se dice, para que el
					# registro no deje un hueco raro sin explicacion.
					_log("%s > %s  ya al maximo" % [actor_name, target_name], "system")
			"stat_mod":
				var value := float(hit.get("value", 0.0))
				var stat_name := String(hit.get("stat", ""))
				var turns := int(hit.get("turns", 0))
				var duration := ""
				if turns > 0:
					duration = "  (%d turnos)" % turns
				# El formato del numero lo decide StatBlock, el mismo sitio que lo
				# pinta en el panel: critico y esquiva en puntos, el resto en %.
				_log("%s: %s %s%s" % [
					target_name,
					StatBlock.label(stat_name),
					StatBlock.mod_value_text(stat_name, String(hit.get("mod_kind", "mult")), value),
					duration,
				], "buff" if value >= 0.0 else "debuff")
			"status":
				_log("%s: %s" % [target_name, String(hit.get("value", "")).to_upper()], "status")
			"sp_gain":
				_log("%s +%d SP" % [target_name, int(hit.get("value", 0))], "sp")
			"shield":
				_log("%s: ESCUDO %d" % [target_name, int(round(float(hit.get("value", 0.0))))], "buff")
			"periodic":
				_log("%s: %s (%d por turno, %d turnos)" % [target_name, _periodic_label(String(hit.get("status", ""))), int(round(float(hit.get("value", 0.0)))), int(hit.get("turns", 0))], "heal" if String(hit.get("status", "")) == "regen" else "debuff")
			"dot":
				_log("%s sufre %s  -%d HP" % [target_name, _periodic_label(String(hit.get("status", ""))).to_lower(), int(round(float(hit.get("value", 0.0))))], "damage")
			"cleanse":
				_log("%s: purificado (%d efectos)" % [target_name, int(hit.get("value", 0))], "buff")
			"dispel":
				_log("%s: pierde %d efectos positivos" % [target_name, int(hit.get("value", 0))], "debuff")
			"sp_drain":
				_log("%s pierde %d SP" % [target_name, int(hit.get("value", 0))], "debuff")
			"undying":
				_log("%s: ULTIMO ALIENTO listo" % target_name, "buff")
			"recoil":
				_log("%s sufre el retroceso  -%d HP" % [target_name, int(round(float(hit.get("value", 0.0))))], "damage")


## --- Jefes: presentacion y fases (v14) -----------------------------------------

## Presentaciones de jefe al empezar. Solo espera si hay una UI escuchando y el
## jugador no tiene activado reducir movimiento; tiene limite de tiempo.
func _play_intros() -> void:
	if GameSettings != null and GameSettings.reduce_motion():
		return
	for boss in enemies:
		if boss.intro.is_empty() or boss_intro.get_connections().is_empty():
			continue
		_intro_open = true
		boss_intro.emit(boss, boss.intro)
		var timer := get_tree().create_timer(INTRO_MAX_SECONDS)
		timer.timeout.connect(close_intro)
		if _intro_open:
			await intro_closed


## La UI (o el jugador, saltandola) cierra la presentacion en curso.
func close_intro() -> void:
	if not _intro_open:
		return
	_intro_open = false
	intro_closed.emit()


## Activa las fases de jefe cuyas condiciones ya se cumplen. Una por una y en orden:
## si un golpe cruza dos umbrales, entran las dos fases seguidas.
func _check_phases() -> void:
	if _finished:
		return
	for boss in enemies:
		if not boss.alive:
			continue
		var guard := 0
		while boss.phase_index < boss.phases.size() and guard < 8:
			guard += 1
			var phase: Dictionary = boss.phases[boss.phase_index]
			var ctx := {
				"actor": boss, "target": null, "team": enemies, "foes": allies,
				"rng": _rng, "round": round_number,
				"source": "phase:%s" % String(phase.get("id", boss.phase_index)),
			}
			var when: Dictionary = phase.get("when", {})
			if when.is_empty() or not EffectEngine.check_condition(when, ctx):
				break
			_enter_phase(boss, phase, ctx)


func _enter_phase(boss: CombatUnit, phase: Dictionary, ctx: Dictionary) -> void:
	boss.phase_index += 1
	var results: Array = []
	var effects: Array = phase.get("effects", [])
	if not effects.is_empty():
		results = EffectEngine.apply_effects(effects, ctx)
	var heal_ratio := float(phase.get("heal_ratio", 0.0))
	if heal_ratio > 0.0:
		boss.heal(roundf(boss.max_hp() * heal_ratio))
	var sp_bonus := int(phase.get("sp", 0))
	if sp_bonus > 0:
		boss.gain_sp(sp_bonus)
	var unlocked = phase.get("unlock_skills", [])
	if unlocked is Array:
		for skill in unlocked:
			if skill is Dictionary:
				boss.unlock_skill(skill)
	if phase.has("pattern"):
		var new_pattern = phase["pattern"]
		boss.pattern = (new_pattern as Array).duplicate() if new_pattern is Array else []
		boss.pattern_step = 0
	var phase_name := String(phase.get("name", "Fase %d" % boss.phase_index))
	phase_log.append({ "unit": boss.source_key, "index": boss.phase_index, "name": phase_name, "round": round_number })
	_log("%s entra en una nueva fase: %s" % [boss.display_name, phase_name], "buff")
	if not results.is_empty():
		_record_passive_stats(boss, results)
		action_resolved.emit({
			"actor_key": boss.source_key, "actor_name": boss.display_name,
			"skill_name": phase_name, "kind": "phase", "hits": results,
		})
	phase_changed.emit(boss, boss.phase_index, phase)
	if not phase_changed.get_connections().is_empty():
		_phase_pause = maxf(_phase_pause, PHASE_PAUSE)
