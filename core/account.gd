extends RefCounted

## NIVEL DE CUENTA Y COSMETICOS (v15).
##
## Antes de la v15 NO existia ningun nivel de cuenta (solo el nivel de cada personaje).
## Este es el sistema sencillo que lo cubre:
##
##   - La experiencia de cuenta entra SOLO por MetaProgress.record(): el mismo punto
##     unico por el que pasan las misiones, asi una accion no se cuenta dos veces y no
##     hay una segunda vía de progreso. Cuanto da cada accion lo dice
##     data/account/levels.json ("xp_sources").
##   - Cada nivel tiene su recompensa en datos (mismo formato que colecciones y
##     misiones: core/rewards.gd) y se COBRA a mano. Cobrar dos veces es imposible:
##     `claimed_levels` lo impide.
##   - Los desbloqueos son cosmeticos (fondos del menu principal, ilustraciones del
##     perfil) y titulos. Ninguno bloquea una funcion que ya existiera.
##   - Un guardado de la v14 no tiene XP de cuenta: se estima UNA vez desde sus
##     contadores ("retroactive" en el JSON) para no empezar en el nivel 1 con
##     cientos de combates a la espalda.
##
## No hay monedas nuevas: las recompensas usan monedas, gemas, materiales, objetos,
## titulos y cosmeticos que ya existian.

const Rewards := preload("res://core/rewards.gd")

var gs = null                    # GameState (se inyecta; permite probar sin autoload)
var xp := 0                      # experiencia de cuenta acumulada (total)
var claimed_levels: Array = []   # niveles cuya recompensa ya se cobro
var cosmetics_owned: Array = []
var background_equipped := ""    # id de cosmetico "background" ("" = fondo normal del menu)
var illustration_equipped := ""  # id de cosmetico "illustration" ("" = ninguna)
## Falso solo cuando se carga un guardado que aun no tenia XP de cuenta (v14): hay que
## estimarla una vez. En una partida nueva no hay nada que estimar.
var bootstrapped := true


func _init(owner = null) -> void:
	gs = owner


## --- Tabla de niveles -----------------------------------------------------------

func _cfg() -> Dictionary:
	return DB.account_config()


func max_level() -> int:
	return maxi(1, int(_cfg().get("max_level", 1)))


## XP necesaria para pasar del nivel `level` al siguiente.
func xp_needed(level: int) -> int:
	var curve = _cfg().get("xp_to_next", {})
	var base := int((curve as Dictionary).get("base", 100)) if curve is Dictionary else 100
	var step := int((curve as Dictionary).get("step", 0)) if curve is Dictionary else 0
	return maxi(1, base + step * (maxi(1, level) - 1))


## XP total acumulada que hace falta para ESTAR en el nivel `level`.
func xp_for_level(level: int) -> int:
	var total := 0
	for l in range(1, mini(level, max_level())):
		total += xp_needed(l)
	return total


func level() -> int:
	var l := 1
	var left := xp
	while l < max_level() and left >= xp_needed(l):
		left -= xp_needed(l)
		l += 1
	return l


## { level, xp_in_level, xp_needed, ratio, maxed, xp_total }
func progress() -> Dictionary:
	var l := level()
	var maxed := l >= max_level()
	var into := xp - xp_for_level(l)
	var need := xp_needed(l)
	return {
		"level": l, "xp_in_level": into if not maxed else need, "xp_needed": need,
		"ratio": 1.0 if maxed else clampf(float(into) / float(need), 0.0, 1.0),
		"maxed": maxed, "xp_total": xp,
	}


## --- Experiencia: un solo camino de entrada --------------------------------------

## XP que vale una accion. kind/ctx son los de MetaProgress.record().
func xp_for_event(kind: String, amount: int, ctx: Dictionary) -> int:
	var sources = _cfg().get("xp_sources", {})
	if not (sources is Dictionary):
		return 0
	var table: Dictionary = sources
	var total := 0
	match kind:
		"battle":
			total += int(table.get("battle_played", 0))
			if bool(ctx.get("victory", false)):
				total += int(table.get("battle_won", 0))
				total += int(table.get("boss_defeated", 0)) * (ctx.get("bosses", []) as Array).size()
		"summon":
			total += int(table.get("summon", 0)) * maxi(0, amount)
		"tower_floor":
			total += int(table.get("tower_floor", 0)) * maxi(0, amount)
		"event_stage":
			total += int(table.get("event_stage", 0)) * maxi(0, amount)
		"evolve":
			total += int(table.get("evolve", 0)) * maxi(0, amount)
	return maxi(0, total)


## Suma XP (la llama MetaProgress.record). Devuelve los niveles NUEVOS alcanzados.
func add_xp(amount: int) -> Array:
	var gained: Array = []
	if amount <= 0:
		return gained
	var before := level()
	var cap := xp_for_level(max_level())
	xp = mini(xp + amount, cap)
	for l in range(before + 1, level() + 1):
		gained.append(l)
	return gained


func on_record(kind: String, amount: int, ctx: Dictionary) -> Array:
	return add_xp(xp_for_event(kind, amount, ctx))


## Estima la XP de un guardado de la v14 una sola vez. Devuelve la XP concedida.
func bootstrap_if_needed() -> int:
	if bootstrapped or gs == null:
		bootstrapped = true
		return 0
	bootstrapped = true
	var table = _cfg().get("retroactive", {})
	if not (table is Dictionary):
		return 0
	var guess := 0
	guess += int((table as Dictionary).get("combates_jugados", 0)) * gs.counter_value("combates_jugados")
	guess += int((table as Dictionary).get("victorias", 0)) * gs.counter_value("victorias")
	guess += int((table as Dictionary).get("summon_total", 0)) * int(gs.summon_total)
	var floors := 0
	for tower_id in gs.tower_progress.keys():
		floors += gs.tower_best_floor(String(tower_id))
	guess += int((table as Dictionary).get("tower_floors", 0)) * floors
	xp = mini(guess, xp_for_level(max_level()))
	return xp


## --- Recompensas por nivel -------------------------------------------------------

func level_reward(target_level: int) -> Dictionary:
	for entry in _cfg().get("level_rewards", []):
		if entry is Dictionary and int((entry as Dictionary).get("level", 0)) == target_level:
			var reward = (entry as Dictionary).get("reward", {})
			return (reward as Dictionary) if reward is Dictionary else {}
	return {}


## Niveles ya alcanzados con recompensa pendiente de cobrar.
func pending_levels() -> Array:
	var out: Array = []
	for l in range(2, level() + 1):
		if not claimed_levels.has(l) and not level_reward(l).is_empty():
			out.append(l)
	return out


## Proximos `count` niveles con su recompensa (para ensenar que viene despues).
func upcoming(count: int) -> Array:
	var out: Array = []
	var l := level() + 1
	while l <= max_level() and out.size() < count:
		var reward := level_reward(l)
		if not reward.is_empty():
			out.append({ "level": l, "reward": reward, "text": Rewards.describe(reward) })
		l += 1
	return out


func claim_level(target_level: int) -> Dictionary:
	if gs == null or target_level < 2 or target_level > level() or claimed_levels.has(target_level):
		return {}
	var reward := level_reward(target_level)
	if reward.is_empty():
		return {}
	claimed_levels.append(target_level)
	var report := Rewards.pay(gs, reward)
	gs.save_game()
	return { "level": target_level, "report": report, "text": Rewards.describe(reward) }


func claim_all_levels() -> Array:
	var out: Array = []
	for l in pending_levels():
		var done := claim_level(int(l))
		if not done.is_empty():
			out.append(done)
	return out


## Un guardado anterior ya cobro niveles cuyo premio ahora incluye cosmeticos nuevos
## (v16): se entregan una vez, sin tocar monedas ni nada mas. Idempotente.
func regrant_claimed_cosmetics() -> int:
	var given := 0
	for l in claimed_levels:
		for id in level_reward(int(l)).get("cosmetics", []):
			if grant_cosmetic(String(id)):
				given += 1
	return given


## --- Cosmeticos -----------------------------------------------------------------

func owns_cosmetic(id: String) -> bool:
	return cosmetics_owned.has(String(id))


## Da un cosmetico. Falso si no existe o ya lo tenia (no se duplica).
func grant_cosmetic(id: String) -> bool:
	var key := String(id)
	if not DB.cosmetics.has(key) or cosmetics_owned.has(key):
		return false
	cosmetics_owned.append(key)
	return true


func owned_of_type(type_name: String) -> Array:
	var out: Array = []
	for id in cosmetics_owned:
		if String((DB.cosmetics.get(String(id), {}) as Dictionary).get("type", "")) == type_name:
			out.append(String(id))
	return out


func equip_background(id: String) -> bool:
	if id.is_empty():
		background_equipped = ""
		return true
	if not owns_cosmetic(id) or String(DB.get_cosmetic(id).get("type", "")) != "background":
		return false
	background_equipped = id
	return true


func equip_illustration(id: String) -> bool:
	if id.is_empty():
		illustration_equipped = ""
		return true
	if not owns_cosmetic(id) or String(DB.get_cosmetic(id).get("type", "")) != "illustration":
		return false
	illustration_equipped = id
	return true


## Slot de fondo que debe usar el menu principal (el equipado o el de siempre).
func menu_background_slot() -> String:
	if not background_equipped.is_empty() and owns_cosmetic(background_equipped):
		var slot := String(DB.get_cosmetic(background_equipped).get("slot", ""))
		if not slot.is_empty():
			return slot
	return "menu"


## Personaje de la ilustracion equipada ("" si no hay).
func illustration_character() -> String:
	if not illustration_equipped.is_empty() and owns_cosmetic(illustration_equipped):
		return String(DB.get_cosmetic(illustration_equipped).get("character", ""))
	return ""


## --- Guardado --------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"xp": xp, "claimed_levels": claimed_levels.duplicate(),
		"cosmetics_owned": cosmetics_owned.duplicate(),
		"background_equipped": background_equipped,
		"illustration_equipped": illustration_equipped,
		"bootstrapped": bootstrapped,
	}


func from_dict(raw: Variant) -> void:
	xp = 0
	claimed_levels = []
	cosmetics_owned = []
	background_equipped = ""
	illustration_equipped = ""
	# Sin bloque (guardado de la v14): hay que estimar la XP la primera vez.
	bootstrapped = false
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return
	var data: Dictionary = raw
	xp = clampi(int(data.get("xp", 0)), 0, xp_for_level(max_level()))
	for l in data.get("claimed_levels", []):
		if not claimed_levels.has(int(l)):
			claimed_levels.append(int(l))
	for id in data.get("cosmetics_owned", []):
		# Un cosmetico retirado de los datos se ignora, no rompe la carga.
		if DB.cosmetics.has(String(id)) and not cosmetics_owned.has(String(id)):
			cosmetics_owned.append(String(id))
	background_equipped = String(data.get("background_equipped", ""))
	illustration_equipped = String(data.get("illustration_equipped", ""))
	if not owns_cosmetic(background_equipped):
		background_equipped = ""
	if not owns_cosmetic(illustration_equipped):
		illustration_equipped = ""
	bootstrapped = bool(data.get("bootstrapped", true))
