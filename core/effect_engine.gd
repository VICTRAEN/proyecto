extends RefCounted

const CombatUnit := preload("res://core/combat_unit.gd")
const BattleMath := preload("res://core/battle_math.gd")

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
			var mod_value := float(effect.get("value", 0.0))
			var turns := int(effect.get("turns", 0))
			for target in targets:
				var previous_max = target.max_hp()
				target.stats.add_mod(stat_name, mod_kind, mod_value, "%s@%s" % [source, target.source_key], turns)
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
					"value": mod_value,
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
		_:
			push_warning("EffectEngine: tipo de efecto desconocido '%s'" % effect_type)
	return results


static func check_condition(condition: Dictionary, ctx: Dictionary) -> bool:
	var actor: CombatUnit = ctx["actor"]
	var team: Array = ctx.get("team", [])
	var condition_type := String(condition.get("type", ""))
	match condition_type:
		"hp_below":
			return _whose_hp_ratio(condition, actor, team) < float(condition.get("value", 0.5))
		"hp_above":
			return _whose_hp_ratio(condition, actor, team) > float(condition.get("value", 0.5))
		"round_at_least":
			return int(ctx.get("round", 0)) >= int(float(condition.get("value", 1)))
		"team_has_category":
			var wanted := String(condition.get("value", ""))
			for member in team:
				for category in member.categories:
					if String(category) == wanted:
						return true
			return false
	return true


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
		_:
			chosen.append(actor)
	return chosen


static func _whose_hp_ratio(condition: Dictionary, actor: CombatUnit, team: Array) -> float:
	if String(condition.get("who", "self")) == "team_lowest":
		var lowest = _lowest_hp(team)
		if lowest == null:
			return 1.0
		return lowest.hp_ratio()
	return actor.hp_ratio()


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
