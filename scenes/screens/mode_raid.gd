extends "res://scenes/screens/mode_base.gd"

## INCURSION DE JEFE (X.3): el jefe de la semana (rota solo por la fecha), sus tramos de dano,
## objetivos, records y registro de intentos.

func _screen_title() -> String:
	return "INCURSION DE JEFE"


static func _time_text(seconds: int) -> String:
	var d := seconds / 86400
	var h := (seconds % 86400) / 3600
	return "%d d %d h" % [d, h]


func refresh() -> void:
	if list == null:
		return
	clear_list()
	var m = GameState.modes
	var raid_id: String = m.current_raid_id()
	var raid := DB.get_raid(raid_id)
	if raid.is_empty():
		list.add_child(make_label("No hay incursiones disponibles.", VI.FONT_BODY, VI.INK_SOFT))
		return
	var rec: Dictionary = m.raid_record(raid_id)
	var enemy := DB.get_enemy(String(raid.get("enemy", "")))
	var col := make_card("RaidCard", String(raid.get("name", raid_id)).to_upper(), VI.RED)
	col.add_child(make_label(String(raid.get("description", "")), VI.FONT_SMALL, VI.INK_SOFT))
	col.add_child(make_label("Jefe: %s   Vida: %d   Fases: %d   Limite: %d rondas" % [String(enemy.get("name", "?")), m.raid_enemy_max_hp(raid_id), (enemy.get("phases", []) as Array).size() + 1, int(raid.get("rounds", 0))], VI.FONT_SMALL, VI.INK))
	col.add_child(make_label("Cambia en %s. Despues: %s." % [_time_text(int(GameState.meta.seconds_left("weekly"))), String(DB.get_raid(m.next_raid_id()).get("name", "-"))], VI.FONT_TINY, VI.INK_DIM))
	col.add_child(make_label("Mejor dano: %d   Intentos: %d   Jefes derrotados: %d   Mejor fase: %d" % [int(rec["best_damage"]), int(rec["attempts"]), int(rec["kills"]), int(rec["best_phase"])], VI.FONT_SMALL, VI.GOLD_LIGHT))
	var problem: String = GameState.team_problem()
	if not problem.is_empty():
		col.add_child(make_label(problem, VI.FONT_SMALL, VI.RED))
	col.add_child(make_button("FightButton", "COMBATIR", VI.RED, _fight.bind(raid_id), 96.0))
	var tiers := make_card("TiersCard", "TRAMOS DE DANO (esta semana)", VI.GOLD)
	for tier in raid.get("tiers", []):
		var need := int(tier.get("damage", 0))
		var done: bool = (rec["claimed_tiers"] as Array).has(need)
		tiers.add_child(make_label("%s %d de dano: %s" % ["[x]" if done else "[ ]", need, Rewards_describe(tier.get("reward", {}))], VI.FONT_TINY, VI.GREEN if done else VI.INK))
	var objs := make_card("ObjectivesCard", "OBJETIVOS (esta semana)", VI.CYAN)
	for obj in raid.get("objectives", []):
		var done2: bool = (rec["claimed_objectives"] as Array).has(String(obj.get("id", "")))
		objs.add_child(make_label("%s %s -> %s" % ["[x]" if done2 else "[ ]", String(obj.get("text", "")), Rewards_describe(obj.get("reward", {}))], VI.FONT_TINY, VI.GREEN if done2 else VI.INK))
	var log_col := make_card("LogCard", "REGISTRO DE INTENTOS", VI.VIOLET)
	var log: Array = rec["log"]
	if log.is_empty():
		log_col.add_child(make_label("Aun no has intentado esta incursion.", VI.FONT_TINY, VI.INK_DIM))
	for i in mini(8, log.size()):
		var e: Dictionary = log[i]
		log_col.add_child(make_label("%s  dano %d  fase %d  rondas %d  bajas %d%s" % [String(e.get("week", "")).trim_prefix("W"), int(e.get("damage", 0)), int(e.get("phase", 1)), int(e.get("rounds", 0)), int(e.get("fallen", 0)), "  JEFE DERROTADO" if bool(e.get("boss_defeated", false)) else ""], VI.FONT_TINY, VI.INK))
	var last := make_card("LastCard", "", VI.BLUE)
	add_last_report(last)
	if last.get_child_count() == 0:
		last.get_parent().queue_free()


func Rewards_describe(reward: Dictionary) -> String:
	return preload("res://core/rewards.gd").describe(reward)


func _fight(raid_id: String) -> void:
	if not GameState.modes.start_raid(raid_id):
		say("No se puede empezar: %s" % GameState.team_problem(), false)
		return
	say("")
	open_battle()
