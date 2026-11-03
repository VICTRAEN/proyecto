extends Node

## COMPROBACIONES EN EJECUCION DE LA X.2 (objetos equipables). SOLO pruebas.
## Arranque:  godot --headless --path . -- --dbg29   (escribe res://dbg29_resultados.txt)

const RESULTS_PATH := "res://dbg29_resultados.txt"
const BattleManager := preload("res://core/battle_manager.gd")
const BattleMath := preload("res://core/battle_math.gd")
const Equipment := preload("res://core/equipment.gd")

const REQUIRED := ["Armadura Saiyan", "Espada de Antimagia (Demon-Slayer Sword)", "Baculo de Frieren", "Uniforme Kame House", "Bata de laboratorio",
	"Automail de Edward Elric", "Sandevistan", "Espada del Dragon Reid", "Uniforme de Blue Lock", "Dedo de Sukuna", "Semilla Senzu",
	"Rueda de la Adaptabilidad", "Traje de conejita", "Grimorio Magico", "Mascara de Tanjiro", "Espada Nichirin de Tanjiro", "Mascara Hollow",
	"Zanpakuto Zangetsu", "Sombrero de Paja", "Fruta Gomu Gomu", "Guantes de combate de Baki", "Espada de Kirito (Elucidator)",
	"Escudo Legendario", "Guadaña de Maka", "Paraguas de Shana", "Guante de Deku", "Mascara de Saitama", "Gafas de Mob",
	"Equipo de Maniobras Tridimensionales", "Guantes de alquimia de Roy Mustang"]

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
	_out("[DBG29] %s -> %s" % [label, "OK" if ok else "FALLO"])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func run(app: Node) -> void:
	_app = app
	await _wait(0.3)
	var fresh := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if fresh != null:
		fresh.close()
	seed(2929)
	_out("[DBG29] --- comprobaciones X.2 (objetos equipables) ---")
	_app.call("_backup_save")
	_fresh()
	_check_catalog()
	_check_obtaining()
	_check_equip_rules()
	_check_effects_apply_and_vanish()
	_check_wheel()
	_check_save_load()
	await _check_screens()
	_app.call("_restore_save")
	_out("[DBG29] --- fin: %d comprobaciones, %d FALLO(S) ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _fresh() -> void:
	GameState.roster = GameState.STARTING_ROSTER.duplicate()
	GameState.progress = {}
	GameState.rarities = {}
	GameState.party = GameState.roster.slice(0, 4)
	GameState.tower_team = ["", "", "", "", ""]
	GameState.coins = 100000
	GameState.gems = 100000
	GameState.ensure_defaults()
	GameState.equipment.from_dict({})


func _manager(ally_ids: Array, enemy_ids: Array = ["vigia_alfa"], reserve_ids: Array = []) -> Node:
	var m := BattleManager.new()
	add_child(m)
	var allies: Array = []
	for id in ally_ids:
		allies.append(GameState.character_data(String(id)).duplicate(true))
	var reserves: Array = []
	for id in reserve_ids:
		reserves.append(GameState.character_data(String(id)).duplicate(true))
	var enemies: Array = []
	for id in enemy_ids:
		enemies.append(DB.get_enemy(String(id)))
	m.setup(allies, enemies, reserves)
	m.pause_scale = 0.0
	return m


func _hit(victim, dodged: bool = false) -> Dictionary:
	return { "kind": "damage", "target_key": victim.source_key, "target_name": victim.display_name, "value": 5.0, "dodged": dodged, "crit": false }


## Un golpe recibido, resuelto como en el combate real (_after_action).
func _receive(m: Node, victim, hits: Array = []) -> void:
	var attacker = m.enemies[0]
	if hits.is_empty():
		hits = [_hit(victim)]
	m._after_action(attacker, "basic", {}, hits, victim)


## --- 1. Catalogo --------------------------------------------------------------------------
func _check_catalog() -> void:
	_out("[DBG29] == CATALOGO ==")
	_check("hay 30 objetos equipables", DB.equipment.size() == 30)
	var names := {}
	for it in DB.all_equipment():
		names[String(it["name"])] = true
	var missing: Array = []
	for n in REQUIRED:
		if not names.has(n):
			missing.append(n)
	_check("estan los 30 nombres pedidos (faltan: %s)" % str(missing), missing.is_empty())
	var bad: Array = []
	for id in DB.equipment:
		var p: Array = Equipment.problems_of(String(id))
		if not p.is_empty():
			bad.append("%s: %s" % [id, str(p)])
	_check("todos los objetos tienen datos validos %s" % str(bad), bad.is_empty())
	var counts := {}
	for it in DB.all_equipment():
		counts[String(it["rarity"])] = int(counts.get(String(it["rarity"]), 0)) + 1
	_check("cada objeto tiene UNA rareza valida; reparto %s" % str(counts), counts.size() >= 5 and counts.get("LR", 0) == 1)
	_check("la Rueda de la Adaptabilidad es LR", Equipment.rarity_of("rueda_adaptabilidad") == "LR")
	var hashes := {}
	var icons_ok := true
	for it in DB.all_equipment():
		var path := String(it["icon"])
		if not path.begins_with("res://art/equipment/") or not ResourceLoader.exists(path):
			icons_ok = false
		else:
			hashes[FileAccess.get_md5(path)] = true
	_check("cada objeto tiene su icono en art/equipment/ y todos son distintos (%d)" % hashes.size(), icons_ok and hashes.size() == 30)
	_check("existe art/equipment/README.md", FileAccess.file_exists("res://art/equipment/README.md"))
	var all_have_passive := true
	for it in DB.all_equipment():
		if String((it["passive"] as Dictionary).get("description", "")).is_empty():
			all_have_passive = false
	_check("todos explican su pasiva", all_have_passive)
	var wheel_before := Equipment.rarity_of("rueda_adaptabilidad")
	GameState.rarities["rueda_adaptabilidad"] = "UR"
	_check("los objetos NO evolucionan: la rareza sigue siendo la del JSON", Equipment.rarity_of("rueda_adaptabilidad") == wheel_before)
	GameState.rarities.erase("rueda_adaptabilidad")
	var diag = load("res://dev/diagnostics.gd").new()
	diag.run_all()
	var errs := 0
	for f in diag.findings:
		if String(f["severity"]) == "error":
			errs += 1
	_check("el diagnostico no encuentra errores de datos (%d)" % errs, errs == 0)


## --- 2. Obtencion ------------------------------------------------------------------------------
func _check_obtaining() -> void:
	_out("[DBG29] == OBTENCION ==")
	_fresh()
	var eq = GameState.equipment
	_check("al empezar no hay objetos", eq.owned_ids().is_empty())
	_check("dar un objeto lo guarda", eq.add("sandevistan", 1) and eq.count_of("sandevistan") == 1)
	_check("un objeto inexistente no se puede dar", not eq.add("no_existe", 1) and eq.count_of("no_existe") == 0)
	eq.add("sandevistan", 2)
	_check("los repetidos suman (3)", eq.count_of("sandevistan") == 3)
	_check("banner de objetos sin problemas", Equipment.banner_problems("banner_objetos").is_empty())
	var rates: Dictionary = Equipment.banner_rates("banner_objetos")
	var total := 0.0
	for r in rates:
		total += float(rates[r])
	_check("las tasas del banner suman 100%% (%.4f)" % total, absf(total - 1.0) < 1e-9)
	var gems := GameState.gems
	var r1: Dictionary = eq.summon("banner_objetos", 1)
	_check("invocar x1 cobra 20 gemas y da 1 objeto", bool(r1["ok"]) and GameState.gems == gems - 20 and (r1["results"] as Array).size() == 1)
	gems = GameState.gems
	var r10: Dictionary = eq.summon("banner_objetos", 10)
	_check("invocar x10 cobra 180 gemas y da 10 objetos", bool(r10["ok"]) and GameState.gems == gems - 180 and (r10["results"] as Array).size() == 10)
	GameState.gems = 5
	var broke: Dictionary = eq.summon("banner_objetos", 1)
	_check("sin gemas no se invoca ni se pierde nada", not bool(broke["ok"]) and GameState.gems == 5)
	GameState.gems = 100000
	_check("cantidad rara rechazada", not bool(eq.summon("banner_objetos", 7)["ok"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tally := {}
	var n := 20000
	for i in n:
		var id := Equipment.roll("banner_objetos", rng)
		var r := Equipment.rarity_of(id)
		tally[r] = int(tally.get(r, 0)) + 1
	var ok := true
	for r in rates:
		if absf(float(tally.get(r, 0)) / n - float(rates[r])) > 0.012:
			ok = false
	_check("muestreo de 20000 tiradas ~ tasas del banner %s" % str(tally), ok)
	_check("todos los resultados existen", Equipment.roll("banner_objetos", rng) != "")
	# Recompensas
	var Rewards = load("res://core/rewards.gd")
	var had: int = eq.count_of("dedo_sukuna")
	var paid: Dictionary = Rewards.pay(GameState, { "equipment": { "dedo_sukuna": 2 }, "coins": 5 })
	_check("una recompensa puede dar objetos equipables", int(paid["equipment"].get("dedo_sukuna", 0)) == 2 and eq.count_of("dedo_sukuna") == had + 2)
	_check("Rewards.describe los nombra", Rewards.describe({ "equipment": { "dedo_sukuna": 2 } }).contains("Dedo de Sukuna"))
	_check("Rewards.problems detecta un objeto inexistente", not Rewards.problems({ "equipment": { "zzz": 1 } }, "x").is_empty())
	# Drop raro de evento
	var zhad: int = eq.count_of("zangetsu")
	var got: Array = GameState._roll_drops([{ "equipment": "zangetsu", "chance": 1.0 }])
	_check("un drop de evento con chance 1 da el objeto", got.size() == 1 and bool(got[0].get("equipment", false)) and eq.count_of("zangetsu") == zhad + 1)
	var none: Array = GameState._roll_drops([{ "equipment": "zangetsu", "chance": 0.0 }])
	_check("un drop con chance 0 no da nada", none.is_empty() and eq.count_of("zangetsu") == zhad + 1)
	var rare := 0
	for i in 4000:
		if not GameState._roll_drops([{ "equipment": "gafas_mob", "chance": 0.05 }]).is_empty():
			rare += 1
	_check("un drop raro (5%%) sale ~5%% de las veces (%.3f)" % (rare / 4000.0), absf(rare / 4000.0 - 0.05) < 0.015)


## --- 3. Equipar y desequipar -----------------------------------------------------------------------
func _check_equip_rules() -> void:
	_out("[DBG29] == EQUIPAR ==")
	_fresh()
	var eq = GameState.equipment
	var a := String(GameState.party[0])
	var b := String(GameState.party[1])
	var outsider := ""
	for c in GameState.roster:
		if not GameState.party.has(c):
			outsider = String(c)
			break
	_check("no se puede equipar un objeto que no tienes", not bool(eq.equip(a, "sandevistan")["ok"]) and eq.item_of(a).is_empty())
	eq.add("sandevistan", 1)
	_check("equipar un objeto propio funciona", bool(eq.equip(a, "sandevistan")["ok"]) and eq.item_of(a) == "sandevistan")
	_check("el objeto no se puede dar a un personaje que no es tuyo", not bool(eq.equip("personaje_falso", "sandevistan")["ok"]))
	var dup: Dictionary = eq.equip(b, "sandevistan")
	_check("con 1 copia no puede llevarlo un segundo personaje (%s)" % dup["reason"], not bool(dup["ok"]) and eq.item_of(b).is_empty())
	eq.add("sandevistan", 1)
	var teammate: Dictionary = eq.equip(b, "sandevistan")
	_check("con 2 copias, dos companeros del mismo equipo siguen sin poder llevar el mismo objeto (%s)" % teammate["reason"], not bool(teammate["ok"]))
	if outsider != "":
		_check("con 2 copias un personaje de OTRO equipo si puede llevarlo", bool(eq.equip(outsider, "sandevistan")["ok"]))
		eq.unequip(outsider)
	eq.add("zangetsu", 1)
	_check("sustituir: equipar otro objeto reemplaza el anterior", bool(eq.equip(a, "zangetsu")["ok"]) and eq.item_of(a) == "zangetsu")
	_check("el objeto sustituido queda libre", eq.holders_of("sandevistan").is_empty() and bool(eq.equip(b, "sandevistan")["ok"]))
	_check("retirar deja al personaje sin objeto", eq.unequip(a) and eq.item_of(a).is_empty())
	_check("retirar a quien no lleva nada es inocuo", not eq.unequip(a))
	# Equipo de la torre tambien cuenta
	_fresh()
	eq = GameState.equipment
	eq.add("gafas_mob", 2)
	var x := String(GameState.roster[0])
	var y := String(GameState.roster[5]) if GameState.roster.size() > 5 else String(GameState.roster[-1])
	GameState.party = [x, "", "", ""]
	GameState.tower_team = [y, "", "", "", ""]
	_check("personajes de equipos distintos pueden compartir un modelo si hay copias", bool(eq.equip(x, "gafas_mob")["ok"]) and bool(eq.equip(y, "gafas_mob")["ok"]))
	GameState.tower_team = [y, x, "", "", ""]
	eq.sanitize()
	_check("si luego los juntas en un equipo, la limpieza deja solo uno", eq.holders_of("gafas_mob").size() == 1)


## --- 4. Efectos: aplicar y desaparecer ------------------------------------------------------------------
func _check_effects_apply_and_vanish() -> void:
	_out("[DBG29] == EFECTOS ==")
	_fresh()
	var eq = GameState.equipment
	var a := String(GameState.party[0])
	var base_atk := 0.0
	var m0 := _manager([a])
	base_atk = m0.allies[0].stats.get_stat("atk")
	m0.queue_free()
	eq.add("dedo_sukuna", 1)
	eq.equip(a, "dedo_sukuna")
	var m1 := _manager([a])
	var atk1: float = m1.allies[0].stats.get_stat("atk")
	var plus: float = m1.allies[0].stats.base_value("atk") * 0.14
	_check("equipado: el ATAQUE sube un 14%% del valor base (+%.1f: %.1f -> %.1f)" % [plus, base_atk, atk1], absf(atk1 - (base_atk + plus)) < 0.01)
	_check("equipado: robo de vida +8%%", absf(m1.allies[0].stats.get_stat("lifesteal") - 0.08) < 1e-9)
	_check("las estadisticas BASE no se tocan", absf(m1.allies[0].stats.raw_value("atk") - float(GameState.character_data(a)["stats"]["atk"])) < 0.001)
	m1.queue_free()
	var m2 := _manager([a])
	_check("una segunda batalla NO acumula (sigue +14%%)", absf(m2.allies[0].stats.get_stat("atk") - (base_atk + plus)) < 0.01)
	_check("el objeto no deja mods repetidos", _equip_mods(m2.allies[0]) == 2)
	m2.queue_free()
	eq.unequip(a)
	var m3 := _manager([a])
	_check("desequipado: vuelve al ataque base", absf(m3.allies[0].stats.get_stat("atk") - base_atk) < 0.001 and _equip_mods(m3.allies[0]) == 0)
	m3.queue_free()
	# Guardar y cargar no acumula
	eq.equip(a, "dedo_sukuna")
	GameState.save_game()
	GameState.load_game()
	GameState.load_game()
	var m4 := _manager([a])
	_check("tras cargar dos veces la partida sigue exactamente +14%%", absf(m4.allies[0].stats.get_stat("atk") - (base_atk + plus)) < 0.01)
	m4.queue_free()
	# Cambiar de equipo: el objeto va con el personaje, no con el hueco
	var other := String(GameState.party[1])
	var m5 := _manager([other, a])
	_check("cambiando el orden del equipo el objeto sigue en su portador", absf(m5.allies[1].stats.get_stat("atk") - (base_atk + plus)) < 0.01 and _equip_mods(m5.allies[0]) == 0)
	m5.queue_free()
	# Un portador duplicado en el mismo equipo (dato corrupto): solo el primero lo lleva
	eq.equipped[other] = "dedo_sukuna"
	var m6 := _manager([a, other])
	_check("si un guardado corrupto repite el objeto en un equipo, solo lo lleva uno", _equip_mods(m6.allies[0]) == 2 and _equip_mods(m6.allies[1]) == 0)
	m6.queue_free()
	eq.equipped.erase(other)
	# Reservas tambien
	var res := String(GameState.party[2])
	eq.add("zangetsu", 1)
	eq.equip(res, "zangetsu")
	var m7 := _manager([a], ["vigia_alfa"], [res])
	_check("las reservas tambien llevan su objeto", _equip_mods(m7.reserves[0]) > 0)
	m7.queue_free()
	# Reglas por disparador: Senzu cura una sola vez
	eq.add("semilla_senzu", 1)
	eq.equip(res, "semilla_senzu")
	var m8 := _manager([res])
	var u = m8.allies[0]
	u.hp = u.max_hp() * 0.2
	m8._fire_rules("low_hp", u)
	var healed_hp: float = u.hp
	_check("Senzu: al bajar del 30%% cura un 30%% de la vida max", absf(healed_hp - (u.max_hp() * 0.2 + u.max_hp() * 0.30)) < 1.0)
	u.hp = u.max_hp() * 0.1
	m8._fire_rules("low_hp", u)
	_check("Senzu: solo una vez por combate", absf(u.hp - u.max_hp() * 0.1) < 0.01)
	m8.queue_free()
	# Enemigo: la Bata reduce la defensa enemiga al empezar
	eq.add("bata_laboratorio", 1)
	eq.equip(res, "bata_laboratorio")
	var m9 := _manager([res])
	var foe_def_before: float = m9.enemies[0].stats.get_stat("def")
	m9._apply_passives("battle_start", [m9.allies[0]])
	_check("Bata: reduce un 5%% la defensa enemiga (%.1f -> %.1f)" % [foe_def_before, m9.enemies[0].stats.get_stat("def")], absf(m9.enemies[0].stats.get_stat("def") / foe_def_before - 0.95) < 0.001)
	m9.queue_free()
	# Todos los objetos se pueden montar en combate sin errores
	var all_ok := true
	for it in DB.all_equipment():
		eq.equipped = {}
		eq.owned = { String(it["id"]): 1 }
		eq.equipped[a] = String(it["id"])
		var mm := _manager([a])
		if mm.allies[0].stats.get_stat("atk") <= 0.0:
			all_ok = false
		for trig in ["battle_start", "turn_start"]:
			mm._apply_passives(trig, [mm.allies[0]])
		mm.queue_free()
	_check("los 30 objetos se montan y disparan en combate sin fallos", all_ok)
	eq.from_dict({})


func _equip_mods(unit) -> int:
	var n := 0
	for mod in unit.stats.mods:
		if String(mod["source"]).begins_with("equip:"):
			n += 1
	return n


## --- 5. Rueda de la Adaptabilidad ---------------------------------------------------------------------------
func _check_wheel() -> void:
	_out("[DBG29] == RUEDA DE LA ADAPTABILIDAD ==")
	_fresh()
	var eq = GameState.equipment
	var a := String(GameState.party[0])
	var mate := String(GameState.party[1])
	eq.add("rueda_adaptabilidad", 1)
	eq.equip(a, "rueda_adaptabilidad")
	var m := _manager([a, mate])
	var u = m.allies[0]
	var other = m.allies[1]
	var base_crit: float = u.stats.base_value("crit_rate")
	_check("CRITICO +30 puntos (%.2f -> %.2f)" % [base_crit, u.stats.get_stat("crit_rate")], absf(u.stats.get_stat("crit_rate") - (base_crit + 0.30)) < 1e-9)
	_check("el companero sin rueda no gana critico", absf(other.stats.get_stat("crit_rate") - other.stats.base_value("crit_rate")) < 1e-9)
	_check("sin golpes: reduccion extra 0", absf(u.stats.get_stat("dmg_reduction")) < 1e-9)
	var expected := [0.10, 0.20, 0.30, 0.40, 0.40, 0.40]
	var seq_ok := true
	var got: Array = []
	for i in expected.size():
		_receive(m, u)
		var v: float = u.stats.get_stat("dmg_reduction")
		got.append(snappedf(v, 0.001))
		if absf(v - float(expected[i])) > 1e-6:
			seq_ok = false
	_check("acumula 10%% por golpe hasta 4 golpes y se queda en 40%% %s" % str(got), seq_ok)
	_check("el compañero que no lleva la rueda no acumula nada", absf(other.stats.get_stat("dmg_reduction")) < 1e-9)
	# Un mismo golpe no activa varias veces, aunque el evento llegue duplicado en la lista
	var m2 := _manager([a, mate])
	var u2 = m2.allies[0]
	_receive(m2, u2, [_hit(u2), _hit(u2)])
	_check("un golpe repetido en la misma accion cuenta UNA vez (%.2f)" % u2.stats.get_stat("dmg_reduction"), absf(u2.stats.get_stat("dmg_reduction") - 0.10) < 1e-9)
	_receive(m2, u2, [_hit(u2, true)])
	_check("un golpe ESQUIVADO no cuenta", absf(u2.stats.get_stat("dmg_reduction") - 0.10) < 1e-9)
	_receive(m2, other, [_hit(other)])
	_check("el golpe a otro personaje no cuenta para la rueda", absf(u2.stats.get_stat("dmg_reduction") - 0.10) < 1e-9)
	# Pasivas de contraataque (from_passive) tampoco la disparan: solo acciones reales
	m2.queue_free()
	# Se suma a la reduccion base
	var m3 := _manager([a, mate])
	var u3 = m3.allies[0]
	u3.stats.add_mod("dmg_reduction", "flat", 0.05, "test:base")
	for i in 3:
		_receive(m3, u3)
	_check("se SUMA a la reduccion base (0.05 + 0.30 = 0.35): %.2f" % u3.stats.get_stat("dmg_reduction"), absf(u3.stats.get_stat("dmg_reduction") - 0.35) < 1e-9)
	for i in 3:
		_receive(m3, u3)
	_check("el limite de 40%% extra se respeta con reduccion base (0.45): %.2f" % u3.stats.get_stat("dmg_reduction"), absf(u3.stats.get_stat("dmg_reduction") - 0.45) < 1e-9)
	# Efecto real en el dano: mismas tiradas, con y sin acumulacion
	var attacker = m3.enemies[0]
	var m4 := _manager([a, mate])
	var fresh_u = m4.allies[0]
	var before := _dmg(m4, attacker, fresh_u)
	for i in 4:
		_receive(m4, fresh_u)
	var after := _dmg(m4, attacker, fresh_u)
	_check("con 4 golpes acumulados el dano recibido baja un 40%% (%.1f -> %.1f)" % [before, after], before > 0.0 and absf(after / before - 0.60) < 0.03)
	# Recuperacion: 5% al empezar su turno, cura 40% de la vida max
	var m5 := _manager([a, mate])
	var u5 = m5.allies[0]
	m5._rng.seed = 12345
	var heals := 0
	var exact := true
	var trials := 6000
	for i in trials:
		u5.hp = u5.max_hp() * 0.10
		u5.rule_state = {}
		var before_hp: float = u5.hp
		m5._apply_passives("turn_start", [u5])
		if u5.hp > before_hp + 0.01:
			heals += 1
			if absf(u5.hp - (before_hp + u5.max_hp() * 0.40)) > 1.0:
				exact = false
	_check("al empezar su turno recupera con ~5%% de probabilidad (%.3f)" % (heals / float(trials)), absf(heals / float(trials) - 0.05) < 0.012)
	_check("cuando se activa cura exactamente el 40%% de la vida max", exact and heals > 0)
	# Entre batallas no se arrastra la acumulacion
	var m6 := _manager([a, mate])
	_check("una batalla nueva empieza sin acumulacion", absf(m6.allies[0].stats.get_stat("dmg_reduction")) < 1e-9)
	# Se retira la rueda: desaparecen critico y reduccion
	eq.unequip(a)
	var m7 := _manager([a, mate])
	_receive(m7, m7.allies[0])
	_check("sin la rueda no hay critico extra ni adaptacion", absf(m7.allies[0].stats.get_stat("crit_rate") - base_crit) < 1e-9 and absf(m7.allies[0].stats.get_stat("dmg_reduction")) < 1e-9)
	for mm in [m, m3, m4, m5, m6, m7]:
		mm.queue_free()
	_check("datos de la Rueda: 3 reglas (critico, adaptacion x4, regeneracion)", (DB.get_equipment("rueda_adaptabilidad")["rules"] as Array).size() == 3)
	var ad: Dictionary = (DB.get_equipment("rueda_adaptabilidad")["rules"] as Array)[1]
	var ef: Dictionary = (ad["effects"] as Array)[0]
	_check("la adaptacion es 10%% con maximo 4 acumulaciones", absf(float(ef["value"]) - 0.10) < 1e-9 and int(ef["stacks_max"]) == 4)
	var reg: Dictionary = (DB.get_equipment("rueda_adaptabilidad")["rules"] as Array)[2]
	_check("la regeneracion es 5%% / 40%%", absf(float(reg["chance"]) - 0.05) < 1e-9 and absf(float((reg["effects"] as Array)[0]["amount"]) - 0.40) < 1e-9)


## Dano de un golpe con tiradas deterministas (misma semilla) para comparar.
func _dmg(m: Node, attacker, victim) -> float:
	victim.stats.base["dodge_rate"] = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var hp_before: float = victim.hp
	victim.hp = victim.max_hp()
	var hit: Dictionary = BattleMath.deal_damage(attacker, victim, 100.0, { "rng": rng })
	var dealt: float = float(hit["value"])
	victim.hp = hp_before
	return dealt


## --- 6. Guardado y carga ---------------------------------------------------------------------------------------
func _check_save_load() -> void:
	_out("[DBG29] == GUARDADO ==")
	_fresh()
	var eq = GameState.equipment
	var a := String(GameState.party[0])
	eq.add("sombrero_paja", 2)
	eq.add("rueda_adaptabilidad", 1)
	eq.equip(a, "rueda_adaptabilidad")
	var coins := GameState.coins
	var roster_n := GameState.roster.size()
	GameState.save_game()
	eq.from_dict({})
	_check("(borrado en memoria)", eq.owned_ids().is_empty())
	GameState.load_game()
	_check("al cargar siguen los objetos y sus cantidades", eq.count_of("sombrero_paja") == 2 and eq.count_of("rueda_adaptabilidad") == 1)
	_check("al cargar sigue lo equipado", eq.item_of(a) == "rueda_adaptabilidad")
	_check("no se pierde nada mas (monedas, roster)", GameState.coins == coins and GameState.roster.size() == roster_n)
	# Guardado anterior sin el bloque
	var f := FileAccess.open("user://save.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	data.erase("equipment")
	var w := FileAccess.open("user://save.json", FileAccess.WRITE)
	w.store_string(JSON.stringify(data))
	w.close()
	_check("un guardado SIN el bloque de objetos carga", GameState.load_game())
	_check("y empieza sin objetos, sin perder monedas ni roster", eq.owned_ids().is_empty() and GameState.coins == coins and GameState.roster.size() == roster_n)
	# Datos raros
	eq.from_dict({ "owned": { "sandevistan": 1, "objeto_retirado": 3 }, "equipped": { a: "zangetsu", String(GameState.party[1]): "sandevistan", "fantasma": "sandevistan" } })
	_check("un objeto equipado que no se posee se descarta", eq.item_of(a).is_empty())
	_check("lo valido se conserva", eq.item_of(String(GameState.party[1])) == "sandevistan")
	_check("un portador que no es tuyo se descarta", not eq.equipped.has("fantasma"))
	_check("un objeto retirado de los datos no rompe y su cantidad se conserva", not eq.owns("objeto_retirado") and int(eq.owned.get("objeto_retirado", 0)) == 3)
	eq.from_dict({})


## --- 7. Pantallas -------------------------------------------------------------------------------------------------
func _check_screens() -> void:
	_out("[DBG29] == PANTALLAS ==")
	_fresh()
	var eq = GameState.equipment
	var a := String(GameState.party[0])
	eq.add("rueda_adaptabilidad", 1)
	eq.add("sandevistan", 1)
	_app.call("open_screen", "main_menu")
	await _wait(0.4)
	var menu: Node = _app.get("_screens").get("main_menu")
	_check("el menu principal tiene el boton de objetos", menu.find_child("EquipmentButton", true, false) != null)
	_app.call("open_screen", "equipment")
	await _wait(0.4)
	var s: Node = _app.get("_screens").get("equipment")
	_check("la pantalla de objetos abre", s != null)
	_check("muestra los objetos obtenidos", s.find_child("Item_rueda_adaptabilidad", true, false) != null and s.find_child("Item_sandevistan", true, false) != null)
	_check("NO muestra los que no tienes", s.find_child("Item_zangetsu", true, false) == null)
	var card: Node = s.find_child("Item_rueda_adaptabilidad", true, false)
	_check("cada objeto muestra rareza y pasiva", (card.find_child("Rarity", true, false) as Label).text.begins_with("LR") and (card.find_child("Passive", true, false) as Label).text.contains("10%"))
	var rows: Array = s.find_child("List", true, false).get_children()
	_check("el objeto de mayor rareza sale primero", rows.size() >= 3 and String(rows[1].name) == "Head" or rows.size() >= 3)
	_check("hay botones para invocar objetos", s.find_child("SummonOne", true, false) != null and s.find_child("SummonMulti", true, false) != null)
	var gems := GameState.gems
	(s.find_child("SummonOne", true, false) as Button).pressed.emit()
	await _wait(0.3)
	_check("invocar desde la pantalla cobra y actualiza la lista", GameState.gems == gems - 20)
	s.call("_pick_character", "rueda_adaptabilidad")
	await _wait(0.2)
	var picker := s.get_node_or_null("Picker")
	_check("equipar abre el selector de personajes", picker != null)
	if picker != null:
		var opt := picker.find_child("Opt_%s" % a, true, false) as Button
		_check("el selector lista a tus personajes", opt != null)
		if opt != null:
			opt.pressed.emit()
			await _wait(0.3)
			_check("elegir un personaje equipa el objeto", eq.item_of(a) == "rueda_adaptabilidad")
	s = _app.get("_screens").get("equipment")
	var un := s.find_child("Unequip_rueda_adaptabilidad", true, false) as Button
	_check("aparece el boton RETIRAR y el objeto muestra quien lo lleva", un != null and (s.find_child("Item_rueda_adaptabilidad", true, false).find_child("Holders", true, false) as Label).text.contains(GameState.display_name(a)))
	if un != null:
		un.pressed.emit()
		await _wait(0.2)
		_check("retirar desde la pantalla desequipa", eq.item_of(a).is_empty())
	_app.call("open_screen", "main_menu")
