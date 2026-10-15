extends Node

## CAPTURAS EN MOVIMIENTO (solo pruebas): secuencias de fotogramas de las
## animaciones y de las ventanas modales, para revisarlas a ojo.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 540x960 -- --motion
## Guarda en user://motion/<nombre>_<n>.png.

var _app: Node = null
const EvolutionFx := preload("res://ui/evolution_fx.gd")


func run(app: Node) -> void:
	_app = app
	DirAccess.make_dir_recursive_absolute("user://motion")
	await _frames(5)
	_app.call("_backup_save")
	GameState.coins = 50000
	GameState.gems = 3200
	GameState.party = ["gojo", "isagi", "frieren", "mai"]
	GameState.normalize_party()
	GameState.tower_progress.clear()

	# Tienda: ventana de confirmacion.
	_app.call("open_screen", "shop")
	await _frames(20)
	var shop = _app.get("_screens")["shop"]
	shop.call("_ask_confirm", "shop_monedas_1000")
	await _frames(15)
	_save("shop_confirm_0")
	shop.call("_close_confirm")
	_app.call("go_back")
	await _frames(3)

	# Mutaciones: ventana del ritual y resultado.
	_app.call("open_screen", "mutations")
	await _frames(20)
	var mut = _app.get("_screens")["mutations"]
	mut.call("_open_ritual")
	await _frames(20)
	_save("ritual_0")
	mut.call("_on_confirm_mutation")
	for i in 5:
		await _wait(0.35)
		_save("ritual_res_%d" % i)
	mut.call("_close_modal")
	_app.call("go_back")
	await _frames(3)

	# Invocacion x10: fotogramas.
	_app.call("open_screen", "summon")
	await _frames(20)
	var summon = _app.get("_screens")["summon"]
	summon.call("_on_roll", 10)
	for i in 8:
		await _wait(0.45)
		_save("summon_%d" % i)
	await _wait(2.5)
	_save("summon_end")
	_app.call("go_back")
	await _frames(3)

	# Evolucion: efecto sobre la pantalla.
	_app.call("open_screen", "evolution")
	await _frames(20)
	var host: Node = _app.get("_screens")["evolution"]
	EvolutionFx.play(host, "SSR", "UR", "Satoru Gojo", "gojo", "gojo")
	for i in 8:
		await _wait(0.4)
		_save("evo_%d" % i)
	await _wait(2.0)
	_app.call("go_back")
	await _frames(3)

	# Combate: ataque normal y ulti.
	GameState.prepare_battle(GameState.BATTLE_STORY, { "level": "world_001_01", "difficulty": "normal" })
	_app.call("open_battle")
	await _wait(1.2)
	var battle = _app.get("_battle")
	var mgr = battle.get("manager")
	var actor = null
	for i in 40:
		actor = mgr.next_actor()
		if actor != null and actor.is_ally and bool(battle.get("awaiting_input")):
			break
		await _wait(0.15)
	_save("atk_before")
	mgr.submit_action({ "kind": "basic" })
	for i in 5:
		await _wait(0.12)
		_save("atk_%d" % i)
	for i in 40:
		actor = mgr.next_actor()
		if actor != null and actor.is_ally and bool(battle.get("awaiting_input")):
			break
		await _wait(0.15)
	actor.sp = 10
	_save("ult_before")
	mgr.submit_action({ "kind": "special" })
	for i in 9:
		await _wait(0.2)
		_save("ult_%d" % i)
	await _wait(1.0)
	await _app.call("_dbg12_finish_battle", false)
	await _wait(2.4)
	_save("result")
	_app.call("close_battle")
	_app.call("_restore_save")
	get_tree().quit(0)


func _save(shot_name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://motion/%s.png" % shot_name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
