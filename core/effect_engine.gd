extends RefCounted

const CombatUnit := preload("res://core/combat_unit.gd")
const BattleMath := preload("res://core/battle_math.gd")
const StatBlock := preload("res://core/stat_block.gd")

## Motor de efectos declarativos.
##
## Una pasiva o una habilidad no es una funcion: es una lista de efectos con
## parametros. Este archivo es el unico que sabe interpretarlos. Anadir un tipo
## de efecto nuevo (counter, escudo, regeneracion, transformacion, ...) es UN
## caso mas en el match de apply_one, no una funcion por personaje.
##
## Contexto esperado en ctx:
##   actor  -> CombatUnit que origina la accion
##   target -> CombatUnit elegido como objetivo principal (puede ser null)
##   team   -> array con el bando del actor (incluido el)
##   foes   -> array con el bando contrario
##   rng    -> RandomNumberGenerator compartido del combate
##   source -> string que identifica el origen (se usa para agrupar mods)
##   round  -> numero de ronda actual


static func apply_effects(effects: Array, ctx: Dictionary) -> Array:
	var results: Array = []
	for effect in effects:
		if not (effect is Dictionary) or not effect.has("type"):
			continue
		var condition: Dictionary = effect.get("condition", {})
		if not condition.is_empty() and not check_condition(condition, ctx):
			continue
		results.append_array(apply_one(effect, ctx))
	return results


static func apply_one(effect: Dictionary, ctx: Dictionary) -> Array:
	var results: Array = []
	var actor: CombatUnit = ctx["actor"]
	var effect_type := String(effect.get("type", ""))
	var source := String(ctx.get("source", "efecto"))
	var targets := resolve_targets(String(effect.get("target", "self")), ctx)

	match effect_type:
		"damage":
			var power := float(effect.get("power", 100))
			for target in targets:
				results.append(BattleMath.deal_damage(actor, target, power, ctx))
		"heal":
			for target in targets:
				var amount := _heal_amount(effect, actor, target)
				var healed = target.heal(amount)
				results.append({
					"kind": "heal",
					"target_key": target.source_key,
					"target_name": target.display_name,
					"value": healed,
				})
		"stat_mod":
			var stat_name := String(effect.get("stat", "atk"))
			var mod_kind := String(effect.get("kind", "mult"))
			if StatBlock.is_extra_stat(stat_name):
				mod_kind = "flat"
			var mod_value := float(effect.get("value", 0.0))
			var turns := int(effect.get("turns", 0))
			var stacks_max := int(effect.get("stacks_max", 0))
			for target in targets:
				var previous_max = target.max_hp()
				var mod_source := "%s@%s" % [source, target.source_key]
				var applied_value := mod_value
				if stacks_max > 1:
					# Acumulable: cada aplicacion suma el valor, hasta stacks_max veces.
					for existing in target.stats.mods:
						if String(existing["source"]) == mod_source and String(existing["stat"]) == stat_name:
							applied_value = float(existing["value"]) + mod_value
							break
					if absf(applied_value) > absf(mod_value) * float(stacks_max):
						applied_value = mod_value * float(stacks_max)
				target.stats.add_mod(stat_name, mod_kind, applied_value, mod_source, turns)
				if stat_name == "max_hp":
					var new_max = target.max_hp()
					if new_max > previous_max:
						target.hp = minf(new_max, target.hp + (new_max - previous_max))
				results.append({
					"kind": "stat_mod",
					"target_key": target.source_key,
					"target_name": target.display_name,
					"stat": stat_name,
					"mod_kind": mod_kind,
					"value": applied_value,
					"turns": turns,
				})
		"sp_gain":
			var amount := int(effect.get("amount", 1))
			for target in targets:
				target.gain_sp(amount)
				results.append({
					"kind": "sp_gain",
					"target_key": target.source_key,
					"target_name": target.display_name,
					"value": amount,
				})
		"status":
			var status_name := String(effect.get("status", "stun"))
			var status_turns := int(effect.get("turns", 1))
			for target in targets:
				if not target.alive:
					continue
				target.add_status(status_name, status_turns)
				results.append({
					"kind": "status",
					"target_key": target.source_key,
					"target_name": target.display_name,
					"value": status_name,
					"turns": status_turns,
				})
		"shield":
			var shield_turns := int(effect.get("turns", 0))
			for target in targets:
				if not target.alive:
					continue
				var shield_amount := _scaled_amount(effect, actor, target)
				target.add_shield(shield_amount, shield_turns, "%s@%s" % [source, target.source_key])
				results.append({
					"kind": "shield",
					"target_key": target.source_key,
					"target_name": target.display_name,
					"value": shield_amount,
					"turns": shield_turns,
				})
		"periodic":
			# Sangrado, quemadura, veneno (dano al empezar el turno del portador) o
			# regeneracion (cura). La cantidad se fija AL APLICARLO (de la vida
			# maxima del objetivo o del ataque de quien lo aplica).
			var periodic_kind := String(effect.get("kind", "bleed"))
			var periodic_turns := int(effect.get("turns", 2))
			for target in targets:
				if not target.alive:
					continue
				var per_turn := _scaled_amount(effect, actor, target)
				target.add_periodic(periodic_kind, per_turn, periodic_turns, "%s@%s" % [source, actor.source_key])
				results.append({
					"kind": "periodic",
					"target_key": target.source_key,
					"target_name": target.display_name,
					"value": per_turn,
					"status": periodic_kind,
					"turns": periodic_turns,
				})
		"cleanse":
			for target in targets:
				var removed: int = target.cleanse()
				results.append({
					"kind": "cleanse",
					"target_key": target.source_key,
					"target_name": target.display_name,
					"value": removed,
				})
		"dispel":
			for target in targets:
				if not target.alive:
					continue
				var dispelled: int = target.dispel()
				results.append({
					"kind": "dispel",
					"target_key": target.source_key,
					"target_name": target.display_name,
					"value": dispelled,
				})
		"sp_drain":
			var drain := int(effect.get("amount", 1))
			for target in targets:
				if not target.alive:
					continue
				var before: int = target.sp
				target.sp = maxi(0, target.sp - drain)
				results.append({
					"kind": "sp_drain",
					"target_key": target.source_key,
					"target_name": target.display_name,
					"value": before - target.sp,
				})
		"undying":
			var charges := int(effect.get("charges", 1))
			for target in targets:
				if not target.alive:
					continue
				target.undying += charges
				target.undying_heal = maxf(target.undying_heal, float(effect.get("heal", 0.1)))
				results.append({
					"kind": "undying",
					"target_key": target.source_key,
					"target_name": target.display_name,
					"value": charges,
				})
		_:
			push_warning("EffectEngine: tipo de efecto desconocido '%s'" % effect_type)
	return results


static func check_condition(condition: Dictionary, ctx: Dictionary) -> bool:
	var actor: CombatUnit = ctx["actor"]
	var team: Array = ctx.get("team", [])
	var foes: Array = ctx.get("foes", [])
	var target = ctx.get("target", null)
	var condition_type := String(condition.get("type", ""))
	var value = condition.get("value", 0)
	match condition_type:
		"hp_below":
			return _whose_hp_ratio(condition, actor, team, target) < float(value if value != null else 0.5)
		"hp_above":
			return _whose_hp_ratio(condition, actor, team, target) > float(value if value != null else 0.5)
		"round_at_least":
			return int(ctx.get("round", 0)) >= int(float(value))
		"round_at_most":
			return int(ctx.get("round", 0)) <= int(float(value))
		"team_has_category":
			var wanted := String(value)
			for member in team:
				for category in member.categories:
					if String(category) == wanted:
						return true
			return false
		"team_category_count_at_least":
			# value = numero; category = cual. Cuenta aliados VIVOS del bando.
			var count := 0
			for member in team:
				if member.alive and member.categories.has(String(condition.get("category", ""))):
					count += 1
			return count >= int(float(value))
		"team_has_role":
			for member in team:
				if member.alive and member.roles.has(String(value)):
					return true
			return false
		"allies_alive_at_most":
			return _alive_only(team).size() <= int(float(value))
		"allies_alive_at_least":
			return _alive_only(team).size() >= int(float(value))
		"allies_fallen_at_least":
			var fallen := 0
			for member in team:
				if not member.alive:
					fallen += 1
			return fallen >= int(float(value))
		"enemies_alive_at_least":
			return _alive_only(foes).size() >= int(float(value))
		"enemies_alive_at_most":
			return _alive_only(foes).size() <= int(float(value))
		"sp_at_least":
			return actor.sp >= int(float(value))
		"self_shielded":
			return actor.shield_total() > 0.0
		"self_debuffed":
			return actor.has_debuff()
		"target_debuffed":
			return target != null and target.has_debuff()
		"target_shielded":
			return target != null and target.shield_total() > 0.0
		"target_has_status":
			return target != null and target.has_status(String(value))
		"target_type_is":
			return target != null and String(target.type) == String(value)
		"target_hp_below":
			return target != null and target.hp_ratio() < float(value)
		"target_hp_above":
			return target != null and target.hp_ratio() > float(value)
		"self_type_is":
			return String(actor.type) == String(value)
	return true


## Multiplicador de poder de una habilidad segun sus bonus condicionales:
## "bonus": [{ "condition": {...}, "power_mult": 1.5 }]. Se multiplican entre si.
static func power_multiplier(skill: Dictionary, ctx: Dictionary) -> float:
	var mult := 1.0
	for bonus in skill.get("bonus", []):
		if not (bonus is Dictionary):
			continue
		var condition: Dictionary = bonus.get("condition", {})
		if condition.is_empty() or check_condition(condition, ctx):
			mult *= float(bonus.get("power_mult", 1.0))
	return mult


static func resolve_targets(spec: String, ctx: Dictionary) -> Array:
	var actor: CombatUnit = ctx["actor"]
	var team: Array = ctx.get("team", [])
	var foes: Array = ctx.get("foes", [])
	var primary = ctx.get("target", null)
	var chosen: Array = []

	match spec:
		"self":
			chosen.append(actor)
		"enemy":
			if primary != null and primary.alive:
				chosen.append(primary)
			else:
				var fallback = _first_alive(foes)
				if fallback != null:
					chosen.append(fallback)
		"enemy_all":
			chosen = _alive_only(foes)
		"ally":
			if primary != null and primary.alive and primary.is_ally == actor.is_ally:
				chosen.append(primary)
			else:
				var lowest = _lowest_hp(team)
				if lowest != null:
					chosen.append(lowest)
		"ally_all":
			chosen = _alive_only(team)
		"ally_lowest":
			var weakest = _lowest_hp(team)
			if weakest != null:
				chosen.append(weakest)
		"ally_others":
			for member in team:
				if member.alive and member != actor:
					chosen.append(member)
		"ally_random":
			var pool := _alive_only(team)
			if not pool.is_empty():
				chosen.append(pool[(ctx["rng"] as RandomNumberGenerator).randi_range(0, pool.size() - 1)])
		"random_enemy":
			var living := _alive_only(foes)
			if not living.is_empty():
				chosen.append(living[(ctx["rng"] as RandomNumberGenerator).randi_range(0, living.size() - 1)])
		"enemy_strongest":
			var strongest: CombatUnit = null
			for foe in foes:
				if foe.alive and (strongest == null or foe.attack() > strongest.attack()):
					strongest = foe
			if strongest != null:
				chosen.append(strongest)
		"enemy_lowest":
			var weakest_foe = _lowest_hp(foes)
			if weakest_foe != null:
				chosen.append(weakest_foe)
		"trigger_target":
			# El otro protagonista del evento: quien me ha golpeado, a quien he
			# golpeado o el aliado que ha caido. Sin el, no hay objetivo.
			if primary != null:
				chosen.append(primary)
		_:
			chosen.append(actor)
	return chosen


static func _whose_hp_ratio(condition: Dictionary, actor: CombatUnit, team: Array, target = null) -> float:
	if String(condition.get("who", "self")) == "target" and target != null:
		return target.hp_ratio()
	if String(condition.get("who", "self")) == "team_lowest":
		var lowest = _lowest_hp(team)
		if lowest == null:
			return 1.0
		return lowest.hp_ratio()
	return actor.hp_ratio()


## Cantidad de un escudo o efecto periodico: fraccion de la vida maxima del
## objetivo ("of": "max_hp"), del ataque de quien lo aplica ("atk") o fija.
static func _scaled_amount(effect: Dictionary, actor: CombatUnit, target: CombatUnit) -> float:
	var amount := float(effect.get("amount", 0.0))
	match String(effect.get("of", "max_hp")):
		"max_hp":
			return target.max_hp() * amount
		"caster_max_hp":
			return actor.max_hp() * amount
		"atk":
			return actor.attack() * amount
	return amount


static func _heal_amount(effect: Dictionary, actor: CombatUnit, target: CombatUnit) -> float:
	var amount := float(effect.get("amount", 0.0))
	match String(effect.get("of", "flat")):
		"max_hp":
			return target.max_hp() * amount
		"atk":
			return actor.attack() * amount
	return amount


static func _alive_only(units: Array) -> Array:
	var result: Array = []
	for unit in units:
		if unit.alive:
			result.append(unit)
	return result


static func _first_alive(units: Array) -> CombatUnit:
	for unit in units:
		if unit.alive:
			return unit
	return null


static func _lowest_hp(units: Array) -> CombatUnit:
	var best: CombatUnit = null
	for unit in units:
		if not unit.alive:
			continue
		if best == null or unit.hp_ratio() < best.hp_ratio():
			best = unit
	return best
