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

const ENEMY_THINK_TIME := 0.7
const TURN_PAUSE := 0.15

const STUN_PAUSE := 0.4

## Multiplicador de las PAUSAS entre turnos. Sale de GameSettings (autoload
## AJUSTES): velocidad normal = 1.0, rapida = menos espera. Las pausas del combate
## se calculan SIEMPRE multiplicando por aqui, para que el ajuste se note en todo
## el combate y no en un solo sitio.
var pause_scale := 1.0


## Pausa real de un tiempo base, ya con el ajuste de velocidad aplicado.
func pause_time(base_seconds: float) -> float:
	return base_seconds * pause_scale

## Verificacion en ejecucion: deja en consola el critico base y el actual de cada
## unidad al empezar la ronda, y el del personaje que va a actuar. Sirve para
## comprobar que la pasiva de Isagi sube el numero y que vuelve a bajar cuando
## caduca. False en el juego normal.
const DEBUG_BATTLE := false
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
	# Las reservas esperan ya "armadas": mismos links, lider y mutacion que los activos.
	for reserve_unit in reserves:
		if not _team_link_ids.is_empty():
			GameState.apply_link_mods(reserve_unit.stats, reserve_unit.id)
		if not GameState.leader_report().is_empty():
			GameState.apply_leader_mods(reserve_unit.stats, reserve_unit.id)
		GameState.apply_mutation_mods(reserve_unit.stats, reserve_unit.id)


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
	_apply_passives("battle_start", _everyone())
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
	elif unit.is_ally:
		action_requested.emit(unit)
		var payload: Dictionary = await action_chosen
		# El objetivo elegido por el jugador viaja con la accion. Si no lo manda
		# (o ya no es valido) el combate elige por el.
		_perform(unit, String(payload.get("kind", "basic")), String(payload.get("target_key", "")))
	else:
		await get_tree().create_timer(ENEMY_THINK_TIME).timeout
		_perform(unit, _pick_enemy_kind(unit))

	unit.tick_statuses()
	if _finished:
		return
	if _last_action_kind == "ultimate":
		await get_tree().create_timer(ULTIMATE_CINEMATIC_PAUSE * pause_scale).timeout
	elif _last_action_kind == "special":
		await get_tree().create_timer(ULTIMATE_PAUSE * pause_scale).timeout
	await get_tree().create_timer(TURN_PAUSE).timeout


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

	var power := float(skill.get("power", 0.0))
	if power > 0.0:
		for target in EffectEngine.resolve_targets(String(skill.get("target", "enemy")), ctx):
			hits.append(BattleMath.deal_damage(actor, target, power, ctx))

	var effects: Array = skill.get("effects", [])
	if not effects.is_empty():
		hits.append_array(EffectEngine.apply_effects(effects, ctx))

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
		if not unit.alive:
			continue
		# Una unidad puede tener VARIAS pasivas: la principal y, si ha
		# evolucionado, la segunda que le da su bloque de evolucion. Se recorren
		# todas y cada una usa su propio "source", asi que dos pasivas sobre la
		# misma stat se SUMAN (origenes distintos) en lugar de sustituirse.
		for passive in unit.passives_for_trigger(trigger):
			var effects: Array = passive.get("effects", [])
			if effects.is_empty():
				continue
			var passive_name := String(passive.get("name", "Sin pasiva"))
			var team: Array = allies if unit.is_ally else enemies
			var foes: Array = enemies if unit.is_ally else allies
			var ctx := {
				"actor": unit,
				"target": null,
				"team": team,
				"foes": foes,
				"rng": _rng,
				"source": "passive:%s" % String(passive.get("id", trigger)),
				"round": round_number,
			}
			var results := EffectEngine.apply_effects(effects, ctx)
			if results.is_empty():
				continue
			_log("%s activa %s" % [unit.display_name, passive_name], "passive")
			_record_passive_stats(unit, results)
			action_resolved.emit({
				"actor_key": unit.source_key,
				"actor_name": unit.display_name,
				"skill_name": passive_name,
				"kind": "passive",
				"hits": results,
			})


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
				if float(hit.get("value", 0.0)) >= 0.0:
					actor.battle.add("buffs_applied")
				else:
					actor.battle.add("debuffs_applied")
			"status":
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
				if float(hit.get("value", 0.0)) >= 0.0:
					unit.battle.add("buffs_applied")
				else:
					unit.battle.add("debuffs_applied")
			"status":
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
			return _alive_only(foes)
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
	# El objetivo elegido por el jugador manda, siempre que siga siendo valido
	# (vivo y del bando correcto). Si no, el combate decide solo.
	if not preferred_key.is_empty():
		for unit in pool:
			if unit.source_key == preferred_key and unit.alive:
				return unit
	return _lowest_hp(pool)


func _pick_enemy_kind(unit: CombatUnit) -> String:
	var special := unit.skill_by_kind("special")
	if not special.is_empty() and unit.sp >= _skill_cost(unit, special):
		return "special"
	return "basic"


func _build_order() -> void:
	order = []
	order.append_array(_alive_only(allies))
	order.append_array(_alive_only(enemies))
	order.sort_custom(func(a, b): return a.speed() > b.speed())


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
	for unit in _everyone():
		unit.stats.tick()
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
func _log_action(actor_name: String, skill_name: String, hits: Array) -> void:
	if hits.is_empty():
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
