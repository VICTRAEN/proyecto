extends Node

## SIMULADOR DE EQUILIBRIO. SOLO para pruebas (no forma parte del juego).
## Arranque:  godot --headless --path . -- --sim --n=200 --lvl=60 --out=nombre
## Juega N combates automaticos (equipos aleatorios de 4 contra grupos de enemigos
## de los datos) y escribe res://sim_<out>.txt con victorias, rondas y rendimiento
## de cada personaje. Sirve para comparar dos versiones de los datos con la misma
## semilla de equipos.

const ENEMY_SETS := {
	"vigias": ["vigia_alfa", "vigia_beta"],
	"warden": ["void_warden"],
	"torre": ["torre_guardian", "torre_verdugo", "torre_avatar"],
	"sdp": ["sdp_akaza", "sdp_mahito", "sdp_todo"],
}
const SKIP := ["sakuta_mai_lr"]

var _n := 120
var _lvl := 60
var _out := "x"
var _app: Node = null


func run(app: Node) -> void:
	_app = app
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			_n = int(arg.substr(4))
		elif arg.begins_with("--lvl="):
			_lvl = int(arg.substr(6))
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
	_app.call("_backup_save")
	var ids: Array = []
	for raw_id in DB.character_ids():
		var id := String(raw_id)
		if id != "" and not SKIP.has(id):
			ids.append(id)
	ids.sort()
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 12345
	var per_char := {}
	var set_stats := {}
	for id in ids:
		per_char[id] = { "games": 0, "wins": 0 }
	for set_name in ENEMY_SETS.keys():
		set_stats[set_name] = { "games": 0, "wins": 0, "rounds": 0 }
	for game in _n:
		var pool := ids.duplicate()
		var team: Array = []
		for k in 4:
			var pick := seed_rng.randi_range(0, pool.size() - 1)
			team.append(pool[pick])
			pool.remove_at(pick)
		for set_name in ENEMY_SETS.keys():
			var result: Dictionary = await _fight(team, ENEMY_SETS[set_name], game)
			var st: Dictionary = set_stats[set_name]
			st["games"] += 1
			st["rounds"] += int(result["rounds"])
			if bool(result["victory"]):
				st["wins"] += 1
			for id in team:
				per_char[id]["games"] += 1
				if bool(result["victory"]):
					per_char[id]["wins"] += 1
	var lines: Array = []
	lines.append("SIM n=%d lvl=%d" % [_n, _lvl])
	var tot_g := 0
	var tot_w := 0
	for set_name in set_stats.keys():
		var st: Dictionary = set_stats[set_name]
		tot_g += int(st["games"])
		tot_w += int(st["wins"])
		lines.append("set %s: win %.1f%%  rondas medias %.1f" % [set_name, 100.0 * float(st["wins"]) / maxf(1.0, float(st["games"])), float(st["rounds"]) / maxf(1.0, float(st["games"]))])
	lines.append("TOTAL win %.1f%%" % (100.0 * float(tot_w) / maxf(1.0, float(tot_g))))
	var rows: Array = []
	for id in per_char.keys():
		var pc: Dictionary = per_char[id]
		rows.append([id, 100.0 * float(pc["wins"]) / maxf(1.0, float(pc["games"])), int(pc["games"])])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	for row in rows:
		lines.append("char %s: %.1f%% (%d)" % [row[0], row[1], row[2]])
	var file := FileAccess.open("res://sim_%s.txt" % _out, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()
	for line in lines.slice(0, 6):
		print(line)
	_app.call("_restore_save")
	get_tree().quit(0)


func _fight(team: Array, enemy_ids: Array, game: int) -> Dictionary:
	GameState.party = team.duplicate()
	var ally_data: Array = []
	for id in team:
		GameState.progress[id] = { "level": _lvl, "xp": 0 }
		ally_data.append(GameState.character_data(id))
	var enemy_data: Array = []
	for eid in enemy_ids:
		enemy_data.append(DB.get_enemy(eid))
	var BM := load("res://core/battle_manager.gd")
	var mgr: Node = BM.new()
	add_child(mgr)
	mgr.setup(ally_data, enemy_data)
	mgr.pause_scale = 0.0
	mgr.set_auto(true)
	var holder := { "done": false, "victory": false, "rounds": 0 }
	mgr.battle_finished.connect(func(victory: bool, rounds: int):
		holder["done"] = true
		holder["victory"] = victory
		holder["rounds"] = rounds)
	mgr.start_battle()
	var guard := 0
	while not holder["done"] and guard < 4000:
		await get_tree().process_frame
		guard += 1
		if mgr.round_number > 40:
			break
	mgr.queue_free()
	return holder
