extends Node

## Autoload GameState: estado del jugador.
##
## Guarda dos cosas distintas y conviene no mezclarlas:
##   roster   -> QUE personajes tiene el jugador.
##   progress -> COMO esta cada uno: nivel y experiencia.
##
## El JSON del personaje (res://data/characters/<id>.json) solo guarda su
## IDENTIDAD: nombre, tipo, rareza, stats de nivel 1, pasiva, habilidades, arte.
## El nivel y la XP viven AQUI, que es estado del jugador, no del personaje. Por
## eso subir de nivel no reescribe ningun JSON y un personaje nuevo (cuando
## lleguen los 100-150) no necesita nada especial: entra en roster y progress.
##
## character_data(id) es el unico sitio que junta las dos cosas: devuelve el JSON
## con el nivel ya inyectado. Todo lo que pinte o construya un personaje debe
## pasar por ahi, para que la ficha, la coleccion y el combate ensenen el mismo
## numero.
##
## Guardado: un unico archivo JSON en user:// con numero de version. Si el archivo
## no existe (primera partida) se usan los valores por defecto y no pasa nada.

const Progression := preload("res://core/progression.gd")
## El formato de un modificador (nombre de la stat y texto del valor) lo decide
## core/stat_block.gd. Aqui se lee para que el informe de una mutacion diga
## exactamente lo mismo que el panel de informacion.
const StatBlock := preload("res://core/stat_block.gd")

const SAVE_PATH := "user://save.json"
## Version del formato del guardado.
##   1 -> roster, progress, party, monedas, gemas, stages, misiones, contadores.
##   2 -> anade rarities (rareza EVOLUCIONADA por personaje) y duplicates.
##   3 -> anade inventory (id de objeto -> cantidad), mutations (la mutacion
##        activa de cada personaje), story_progress (nivel -> dificultades
##        superadas) y event_progress (stage superado, recompensa entregada y
##        veces completado).
## Un archivo de una version ANTERIOR se MIGRA (load_game llama a _migrate), asi
## que el progreso del jugador nunca se pierde. Solo se ignora un archivo de una
## version DESCONOCIDA (mayor que esta), que no sabemos interpretar.
const SAVE_VERSION := 3

const STARTING_COINS := 1000
const STARTING_GEMS := 300
## Personajes que el jugador tiene desde el principio. El dia que exista el gacha
## esto sera solo el roster inicial y el resto llegara invocando.
const STARTING_ROSTER := [
	"gojo", "isagi", "frieren", "mai",
	"asta", "yuno", "yami",
	"goku", "vegeta", "deku",
	"lucy", "david",
	"denji", "makima", "reze",
	"maomao", "senku",
	"hinata", "kageyama", "marin",
	"itadori", "sukuna", "tanjiro", "akaza",
	"subaru", "miku", "nino", "itsuki",
]
## Posiciones del equipo. El roster entero NO es el equipo: el combate se juega
## con 4 unidades hasta que llegue la fase de equipos mayor, asi que el equipo por
## defecto son los 4 primeros y la pantalla EQUIPO los reordena.
const PARTY_SIZE := 4
## Cuantos personajes del EQUIPO tienen que compartir un link para que se active.
## Con 2 basta: el link premia juntar parejas, no llenar el equipo de lo mismo.
const LINK_MIN_HOLDERS := 2

## Personajes obtenidos. Cuando exista el gacha, se anaden aqui.
var roster: Array = []
## id -> { "level": int, "xp": int }
var progress: Dictionary = {}
## Rareza EVOLUCIONADA por personaje. La rareza BASE vive en el JSON del
## personaje (es su identidad); esto es estado del jugador y solo guarda los
## personajes que han evolucionado, asi que un id ausente significa "usa la del
## JSON". Formato: id -> "UR".
var rarities: Dictionary = {}
## Duplicados obtenidos de cada personaje. id -> copias de mas. El primer
## personaje obtenido NO cuenta como duplicado.
var duplicates: Dictionary = {}
## Nivel de DUPE de cada personaje (0..max). Es lo UNICO que se guarda del sistema de
## Dupes: las copias disponibles se CALCULAN (duplicates - nivel) y los bonus salen de
## data/dupes/rules.json, asi no hay datos redundantes que puedan desincronizarse.
var dupe_levels: Dictionary = {}
## Equipo activo: lo usa el combate, tal cual, sin copias.
var party: Array = []
var friend: String = ""

var coins := STARTING_COINS
var gems := STARTING_GEMS
var materials := 0

## Contadores que el juego conoce de base. Anadir uno nuevo es una linea aqui y
## save_game lo vuelca solo; un contador que solo aparezca en un JSON de mision
## tambien se guarda, porque save_game guarda el diccionario entero.
## "personajes_obtenidos" NO se guarda: es roster.size(), y duplicarlo seria una
## segunda fuente de verdad que se puede desincronizar.
const DEFAULT_COUNTERS := {
	"combates_jugados": 0,
	"victorias": 0,
	"derrotas": 0,
	"invocaciones": 0,
	"duplicados_obtenidos": 0,
	"evoluciones": 0,
	"monedas_gastadas": 0,
	"gemas_gastadas": 0,
	"compras_tienda": 0,
	"historia_niveles": 0,
	"eventos_completados": 0,
	"mutaciones": 0,
	"objetos_obtenidos": 0,
}
var counters := DEFAULT_COUNTERS.duplicate()
## Stages ya ganados. Un stage se desbloquea cuando el anterior esta en esta
## lista, asi que la progresion es un dato mas del guardado.
var completed_stages: Array = []
## id de mision -> { "claimed": bool }. El progreso no se guarda: se calcula
## siempre desde los contadores, que es lo que realmente ha hecho el jugador.
var missions_claimed: Dictionary = {}

## Enemigos de la fase jugable actual. En la fase de mapa esto lo sustituye el
## nodo elegido en el mapa.
var current_stage_enemies: Array = ["void_warden"]
## Stage elegido en la pantalla de seleccion. Los enemigos de la batalla salen de
## su JSON, nunca de una lista escrita a mano en el combate.
var stage_id := "stage_001"
## Mundo de HISTORIA elegido. El mapa lo lee para saber que mundo pintar; se
## guarda porque el jugador entra y sale del mapa varias veces.
var current_world_id := ""
## Energia: RESERVADO. Todavia no se gasta ni se muestra; el campo y el
## energy_cost del stage existen para que una batalla pueda costar energia mas
## adelante sin cambiar el formato del guardado.
var energy := 100
var energy_max := 100

## --- V3: estado de los sistemas nuevos (inventario, mutaciones, historia y eventos) ---

## Inventario: id de objeto -> cantidad. El catalogo de objetos (nombre,
## descripcion, icono, rareza) vive en res://data/items/<id>.json y NO se guarda
## aqui: el guardado solo lleva la cantidad, que es lo unico que cambia.
var inventory: Dictionary = {}
## Mutacion ACTIVA por personaje: id -> un informe ya resuelto
## { rank, bonus_percent, effect, stats: [{stat, bonus, bonus_percent}], sp_reduction }.
## Solo hay una por personaje porque una tirada nueva sustituye a la anterior.
## La mutacion pertenece al PERSONAJE y sobrevive a las evoluciones.
var mutations: Dictionary = {}
## Historia: nivel_id -> ["normal", "hard", "extreme"] con las dificultades YA
## superadas. Completar EXTREMO mete tambien NORMAL y DIFICIL en esta lista, asi
## que "estar en la lista" significa exactamente "esa dificultad esta pagada".
var story_progress: Dictionary = {}
## Eventos: evento_id -> { stages: { stage_id -> { completed, clears } },
## rewards_claimed: { id -> true }, times_completed: int }.
var event_progress: Dictionary = {}


func _ready() -> void:
	ensure_defaults()
	load_game()


## Rellena lo que falte sin tocar lo que ya existe. Se llama al arrancar y
## despues de cargar, asi que un archivo viejo (o ninguno) nunca deja el juego a
## medias: los personajes nuevos del roster aparecen con nivel 1.
func ensure_defaults() -> void:
	if roster.is_empty():
		roster = STARTING_ROSTER.duplicate()
	# Un guardado de una version anterior tiene solo los personajes de entonces:
	# los que el juego da por defecto y no estan en su roster se anaden, para que
	# un roster nuevo aparezca sin perder el progreso que ya tenia el jugador.
	for id in STARTING_ROSTER:
		if not roster.has(id):
			roster.append(id)
	for id in roster:
		var key := String(id)
		if not progress.has(key):
			progress[key] = { "level": Progression.LEVEL_MIN, "xp": 0 }
		# Un personaje obtenido nunca tiene duplicados negativos: el contador
		# empieza en 0 y solo sube al volver a salir.
		if not duplicates.has(key):
			duplicates[key] = 0
	if party.is_empty():
		party = roster.slice(0, PARTY_SIZE)
	# Los contadores nuevos se anaden a un guardado viejo con valor 0, sin tocar
	# los que ya existian. Los que define el codigo son la lista de referencia.
	for key in DEFAULT_COUNTERS.keys():
		if not counters.has(key):
			counters[key] = DEFAULT_COUNTERS[key]


## --- Progresion ------------------------------------------------------------

func level_of(id: String) -> int:
	var entry: Dictionary = progress.get(id, {})
	return int(entry.get("level", Progression.LEVEL_MIN))


func xp_of(id: String) -> int:
	var entry: Dictionary = progress.get(id, {})
	return int(entry.get("xp", 0))


func xp_to_next(id: String) -> int:
	return Progression.xp_to_next(level_of(id))


func is_max_level(id: String) -> bool:
	return level_of(id) >= Progression.LEVEL_MAX


## Suma experiencia y sube de nivel tantas veces como haga falta. Devuelve cuantos
## niveles se han ganado. Un personaje a nivel maximo deja de acumular XP.
func add_xp(id: String, amount: int) -> int:
	var key := String(id)
	if amount <= 0 or not progress.has(key):
		return 0
	if is_max_level(key):
		return 0
	var result: Dictionary = Progression.apply_xp(level_of(key), xp_of(key), amount)
	progress[key] = {
		"level": int(result["level"]),
		"xp": int(result["xp"]),
	}
	save_game()
	return int(result["levels_gained"])


## Fija el nivel a mano. Se usa para probar la progresion sin jugar misiones.
func set_level(id: String, new_level: int) -> void:
	var key := String(id)
	if not progress.has(key):
		return
	progress[key] = {
		"level": clampi(new_level, Progression.LEVEL_MIN, Progression.LEVEL_MAX),
		"xp": 0,
	}
	save_game()


## --- Datos de personaje ----------------------------------------------------

## Rareza BASE del personaje: sale siempre de su JSON, es su identidad.
func base_rarity_of(id: String) -> String:
	var base: Dictionary = DB.get_character(String(id))
	return String(base.get("rarity", "R"))


## Rareza EFECTIVA: la evolucionada si el jugador ya evoluciono a ese personaje,
## y la del JSON si no. Es el unico sitio donde se decide esta mezcla.
func rarity_of(id: String) -> String:
	var key := String(id)
	if rarities.has(key):
		return String(rarities[key])
	return base_rarity_of(key)


## El personaje ha evolucionado? Compara la rareza efectiva con la del JSON, asi
## que no hace falta guardar un booleano aparte que se pueda desincronizar.
func is_evolved(id: String) -> bool:
	return rarity_of(String(id)) != base_rarity_of(String(id))


## FORMA visual de un personaje: su rareza efectiva en minusculas ("ssr", "ur",
## "lr"). Es lo que decide que subcarpeta de arte se busca primero, asi que una
## unidad evolucionada ensena su propio dibujo sin que ninguna pantalla tenga que
## saber nada de evoluciones. Devuelve "" si el id no es un personaje, para que el
## arte caiga a la convencion base.
func form_of(id: String) -> String:
	var key := String(id)
	# Un ENEMIGO no es un personaje del roster y no tiene forma: se queda con su
	# arte base. Se pregunta con has_character para no llenar el log de "personaje
	# desconocido" cada vez que se pinta una unidad rival.
	if key.is_empty() or not DB.has_character(key):
		return ""
	return rarity_of(key).to_lower()


## El personaje tiene su propia imagen para esa forma? Mira la convencion
## <id>/<forma>/<ranura>.png sin cargar la imagen: la ficha puede decir si esa
## forma ya tiene arte propio. (La convencion vive en ui/portrait.gd.)
func has_form_art(id: String, slot_name: String = "icon") -> bool:
	var key := String(id)
	var form := form_of(key)
	if form.is_empty():
		return false
	return ResourceLoader.exists("res://art/characters/%s/%s/%s.png" % [key, form, slot_name])


func duplicates_of(id: String) -> int:
	return int(duplicates.get(String(id), 0))


func is_owned(id: String) -> bool:
	return roster.has(String(id))


## Pasiva ACTIVA del personaje: si ha evolucionado usa la del bloque de evolucion
## (la version mejorada), y si no la de siempre. El combate y la ficha leen
## siempre esta, nunca la clave "passive" del JSON directamente.
func passive_of(id: String) -> Dictionary:
	var data := character_data(String(id))
	return data.get("passive", {})


## TODAS las pasivas activas: la principal y, si el personaje ha evolucionado, la
## segunda pasiva que le da la evolucion. Un personaje sin evolucionar tiene una
## sola. Devuelve datos ya resueltos, sin que nadie lea claves del JSON.
func passives_of(id: String) -> Array:
	var out: Array = []
	for passive in character_data(String(id)).get("passives", []):
		if passive is Dictionary and not passive.is_empty():
			out.append(passive)
	return out


## El JSON del personaje con el nivel y la rareza EFECTIVA del jugador ya dentro.
## Devuelve una copia, asi que nadie puede modificar por accidente los datos
## cargados por DB.
func character_data(id: String) -> Dictionary:
	var base: Dictionary = DB.get_character(String(id))
	if base.is_empty():
		return {}
	var data: Dictionary = base.duplicate(true)
	data["level"] = level_of(String(id))
	data["level_max"] = Progression.LEVEL_MAX
	data["base_rarity"] = String(base.get("rarity", "R"))
	# La rareza base sale del JSON; la efectiva puede haber subido al evolucionar.
	data["rarity"] = rarity_of(String(id))
	data["evolved"] = is_evolved(String(id))
	# Multiplicador de la FORMA. Sale de la ruta de evolucion (res://data/evolution/
	# rules.json -> stat_multiplier), asi que el numero es dato y no codigo. Vale 1.0
	# mientras el personaje no ha evolucionado, con lo que su balance no cambia.
	# Lo aplica core/stat_block.gd: aqui solo se entrega resuelto.
	data["stat_multiplier"] = 1.0
	if is_evolved(String(id)):
		# La ruta que LLEGA a la rareza actual (SSR->UR = x1.25, UR->LR = x1.5):
		# el multiplicador es total sobre las estadisticas base, no se encadena.
		var into := _route_into(rarity_of(String(id)))
		if not into.is_empty():
			data["stat_multiplier"] = float(into.get("stat_multiplier", 1.0))
	data["owned"] = is_owned(String(id))
	data["duplicates"] = duplicates_of(String(id))
	data["dupe_level"] = dupe_level_of(String(id))
	data["dupe_mods"] = dupe_mods_for(String(id))
	# El bloque "evolution" es la RECETA (pasiva mejorada, links y categorias
	# nuevos), no algo que se pinte: la ficha ve el resultado ya aplicado.
	var evolution = data.get("evolution", {})
	var form_stages: Array = _form_stages(String(id), evolution)
	var passives: Array = []
	var active_passive: Dictionary = data.get("passive", {})
	data["ultimate"] = {}
	if not form_stages.is_empty():
		# La forma ACTUAL manda: cada etapa (UR, luego LR) trae su propia pasiva y
		# su segunda pasiva; links, categorias y arte se ACUMULAN.
		var top: Dictionary = form_stages[form_stages.size() - 1]
		var top_passive = top.get("passive", {})
		if top_passive is Dictionary and not (top_passive as Dictionary).is_empty():
			active_passive = top_passive
			passives.append(top_passive)
			var extra = top.get("passive_extra", {})
			if extra is Dictionary and not (extra as Dictionary).is_empty():
				passives.append(extra)
		elif not active_passive.is_empty():
			passives.append(active_passive)
		var merged_links: Array = data.get("links", [])
		var merged_cats: Array = data.get("categories", [])
		var merged_art: Dictionary = data.get("art", {}).duplicate()
		for stage in form_stages:
			merged_links = _merged_ids(merged_links, (stage as Dictionary).get("links", []))
			merged_cats = _merged_ids(merged_cats, (stage as Dictionary).get("categories", []))
			var form_art = (stage as Dictionary).get("art", {})
			if form_art is Dictionary:
				for slot_name in (form_art as Dictionary).keys():
					merged_art[String(slot_name)] = String((form_art as Dictionary)[slot_name])
			# La ULTIMATE es dato de la forma: solo existe si la etapa la declara
			# (el duo la trae en su bloque LR), asi que SSR y UR no la tienen.
			var ult = (stage as Dictionary).get("ultimate", {})
			if ult is Dictionary and not (ult as Dictionary).is_empty():
				data["ultimate"] = (ult as Dictionary).duplicate(true)
		data["links"] = merged_links
		data["categories"] = merged_cats
		data["art"] = merged_art
	elif not active_passive.is_empty():
		passives.append(active_passive)
	data["passive"] = active_passive
	data["passives"] = passives
	return data


## Etapas de forma ya ALCANZADAS por el personaje, en orden: [UR] si es UR,
## [UR, LR] si es LR. Cada etapa es un diccionario del bloque "evolution" (la
## de UR es el propio bloque; la de LR es evolution.lr). Vacia si no ha evolucionado.
func _form_stages(id: String, evolution: Variant) -> Array:
	var out: Array = []
	if not is_evolved(id) or not (evolution is Dictionary) or (evolution as Dictionary).is_empty():
		return out
	out.append(evolution)
	if rarity_of(id) == "LR":
		var lr = (evolution as Dictionary).get("lr", {})
		if lr is Dictionary and not (lr as Dictionary).is_empty():
			out.append(lr)
	return out


## Ruta de evolucion (rules.json) cuyo DESTINO es esa rareza, o {}.
func _route_into(to_rarity: String) -> Dictionary:
	for route in DB.evolution_routes():
		if String((route as Dictionary).get("to", "")) == to_rarity:
			return route
	return {}


func _merged_ids(base_ids: Variant, extra_ids: Variant) -> Array:
	var out: Array = []
	for source in [base_ids, extra_ids]:
		if not (source is Array):
			continue
		for raw_id in source:
			var key := String(raw_id)
			if not out.has(key):
				out.append(key)
	return out


func party_data() -> Array:
	var data_list: Array = []
	for id in party:
		# Una ranura vacia del equipo no es un personaje desconocido: se salta.
		if String(id).is_empty():
			continue
		var data := character_data(String(id))
		if not data.is_empty():
			data_list.append(data)
	return data_list


## --- El equipo y sus HUECOS -------------------------------------------------
## El equipo son SIEMPRE PARTY_SIZE posiciones fijas, y una posicion puede estar
## VACIA ("") o ocupada por un personaje. No es una lista que se acorta: 1/4 es un
## equipo de una unidad, y el hueco es un estado legitimo, no un error a corregir.
## Esto es lo que permite montar a Sakuta solo en la posicion 1, o dejar el equipo
## a 0/4. Todo lo que lee el equipo (combate, ficha, pantalla) pasa por aqui, para
## que "cuantas unidades llevo" se calcule en un unico sitio.

## El equipo con exactamente PARTY_SIZE posiciones, sin duplicados. Rellena con
## "" lo que falte, corta lo que sobre y NO resucita personajes que el jugador no
## tiene. Es idempotente: llamarla dos veces deja lo mismo.
func normalize_party() -> void:
	var out: Array = []
	var seen: Dictionary = {}
	# Se recorre POSICION A POSICION: cada personaje se queda donde esta. NO se
	# compacta, porque la posicion es un dato con significado (la 1 lleva la
	# Leader Skill). Compactar subiria al del slot 2 al slot 1 y le daria un
	# liderazgo que el jugador no ha pedido.
	for i in PARTY_SIZE:
		var key := ""
		if i < party.size():
			key = String(party[i])
		# Un hueco, un duplicado o un id que el jugador no tiene dejan la
		# posicion VACIA: es mas seguro un hueco que un fantasma repetido.
		if key.is_empty() or seen.has(key) or not is_owned(key):
			out.append("")
			continue
		seen[key] = true
		out.append(key)
	party = out


## Cuantas UNIDADES lleva el equipo. Los huecos no cuentan.
func party_count() -> int:
	var total := 0
	for raw_id in party:
		if not String(raw_id).is_empty():
			total += 1
	return total


## Los personajes del equipo, sin huecos y en orden de posicion.
func party_ids() -> Array:
	var out: Array = []
	for raw_id in party:
		var key := String(raw_id)
		if not key.is_empty():
			out.append(key)
	return out


## Pone (o quita) un personaje en una posicion concreta.
##   - id vacio            -> deja la posicion VACIA.
##   - id que YA esta en ESA posicion -> la deja VACIA (tocar dos veces lo quita).
##   - id que ya esta en OTRA posicion -> se MUEVE: la otra queda vacia, asi que
##     el equipo nunca tiene al mismo personaje dos veces.
## Se guarda al momento: un equipo con huecos no se pierde al cerrar el juego.
func assign_party_slot(index: int, id: String) -> void:
	if index < 0 or index >= PARTY_SIZE:
		return
	if party.size() != PARTY_SIZE:
		normalize_party()
	var key := String(id)
	if key.is_empty():
		party[index] = ""
		save_game()
		return
	if String(party[index]) == key:
		party[index] = ""
		save_game()
		return
	for i in party.size():
		if String(party[i]) == key:
			party[i] = ""
	party[index] = key
	save_game()


## Por que NO se puede combatir con este equipo, en texto. Devuelve "" si el
## equipo vale. Los huecos NO son un problema por si mismos: lo que decide si
## hacen falta mas unidades es el stage, no esta funcion.
func team_problem() -> String:
	if battle_source == BATTLE_TOWER and not _tower_lead.is_empty():
		if tower_active_ids().is_empty():
			return "El equipo de torre no tiene activos: pon al menos 1 personaje en los 3 puestos de arriba."
		return ""
	if party_count() == 0:
		return "El equipo esta vacio: elige al menos un personaje."
	return ""


## Cuantas unidades admite como MINIMO el origen de la batalla en curso. Un stage
## que pide un tamano exacto manda; si no, basta con que haya alguien. Es la unica
## respuesta a "me hacen falta 4?", y sale del stage, nunca de una regla fija.
func current_min_party_size() -> int:
	var stage := current_stage()
	var wanted := int(stage.get("requires_party_size", 0))
	if wanted > 0:
		return wanted
	return 1


## Todos los personajes obtenidos, en orden de roster. La coleccion y el equipo
## pintan esta lista; anadir un personaje al roster lo hace aparecer en las dos.
## NO incluye los no obtenidos: para eso esta all_characters_data().
func roster_data() -> Array:
	var data_list: Array = []
	for id in roster:
		var data := character_data(String(id))
		if not data.is_empty():
			data_list.append(data)
	return data_list


## TODOS los personajes del juego (obtenidos y no obtenidos), con la marca
## "owned" resuelta, para que la coleccion pueda pintar los bloqueados. Los no
## obtenidos no tienen nivel de jugador: sale el minimo.
func all_characters_data() -> Array:
	var data_list: Array = []
	for id in DB.character_ids():
		var key := String(id)
		if is_owned(key):
			data_list.append(character_data(key))
			continue
		var data: Dictionary = DB.get_character(key).duplicate(true)
		if data.is_empty():
			continue
		data["level"] = Progression.LEVEL_MIN
		data["level_max"] = Progression.LEVEL_MAX
		data["base_rarity"] = String(data.get("rarity", "R"))
		data["owned"] = false
		data["duplicates"] = 0
		data["evolved"] = false
		data_list.append(data)
	return data_list


## Personajes que el jugador NO tiene todavia. La coleccion marca estas fichas
## como bloqueadas; sigue siendo datos, no una segunda lista de personajes.
func locked_character_ids() -> Array:
	var out: Array = []
	for id in DB.character_ids():
		if not is_owned(String(id)):
			out.append(String(id))
	return out


func enemy_data() -> Array:
	var data_list: Array = []
	for id in current_stage_enemies:
		var data := DB.get_enemy(String(id))
		if not data.is_empty():
			data_list.append(data)
	return data_list


## --- Stages y recompensas ---------------------------------------------------

## Identificador de la batalla en curso. Se incrementa al empezar CADA batalla y
## es lo que impide que una misma batalla entregue recompensas dos veces: la
## pantalla de resultado manda su token y solo la primera llamada con ese token
## paga. Reintentar abre una batalla nueva (token nuevo), asi que volver a ganar
## si vuelve a dar premio, que es lo correcto.
var battle_token := 0
var _rewarded_token := -1

## --- De donde sale la batalla en curso --------------------------------------
## Una batalla puede salir de cuatro sitios: una batalla suelta (STAGE), un nivel
## de HISTORIA, un stage de un EVENTO o un piso de una TORRE. El combate NO sabe
## de donde viene: lee siempre current_stage_enemies y current_stage(). Lo que
## cambia es QUIEN paga el premio, y eso lo decide grant_battle_rewards mirando
## battle_source. Asi una batalla sigue pagando una sola vez, venga de donde venga,
## y no hay una segunda caja de recompensas por modo.
const BATTLE_STAGE := "stage"
const BATTLE_STORY := "story"
const BATTLE_EVENT := "event"
const BATTLE_TOWER := "tower"

var battle_source := BATTLE_STAGE
## Plantilla de la batalla en curso. Vacia = equipo normal (party). Un stage de
## 1 VS 1 la fija con UNA sola unidad, asi que el combate no arrastra companeros.
var battle_party: Array = []
## Reservas de la batalla en curso (solo la torre las usa): entran por rotacion
## cuando un activo cae. Vacia = sin reservas.
var battle_reserve: Array = []
## Equipo de torre EN COMBATE, con huecos (slot 1 = lider). Vacio fuera de la
## torre. Links y Leader Skill leen esto (via _lead_party) durante ese combate.
var _tower_lead: Array = []
## Datos de la batalla en curso segun su origen:
##   STAGE -> { stage }
##   STORY -> { level, difficulty }
##   EVENT -> { event, stage }
##   TOWER -> { tower, floor }
var battle_source_ref: Dictionary = {}


## Empieza una batalla y devuelve su token. Lo llama App al abrir el combate.
func begin_battle() -> int:
	battle_token += 1
	return battle_token


## Informe de recompensas vacio, con TODAS las claves que lee la pantalla de
## resultado. Un solo sitio lo construye, asi que no hay dos formatos.
func _empty_report() -> Dictionary:
	return {
		"xp": 0,
		"coins": 0,
		"characters": [],
		"granted": false,
		"unlocked": [],
		"unlocked_names": [],
		"drops": [],
		"title": "",
	}


## Lo que se pinta arriba del combate: nombre y fondo. Para un stage sale de su
## JSON; para historia, evento o torre sale del nivel/piso elegido. La pantalla de
## combate solo lee esto, asi que no necesita saber de donde viene la batalla.
func current_stage() -> Dictionary:
	match battle_source:
		BATTLE_STORY:
			return _story_battle_info()
		BATTLE_EVENT:
			return _event_battle_info()
		BATTLE_TOWER:
			return _tower_battle_info()
		_:
			return DB.get_stage(stage_id)


func _story_battle_info() -> Dictionary:
	var level_id := String(battle_source_ref.get("level", ""))
	var difficulty := String(battle_source_ref.get("difficulty", ""))
	var level := DB.world_level(DB.world_of_level(level_id), level_id)
	var entry := DB.difficulty_of_level(level, difficulty)
	if entry.is_empty():
		return {}
	return {
		"id": level_id,
		"name": "%s - %s" % [String(level.get("name", level_id)), String(entry.get("name", difficulty))],
		"background": String(level.get("background", "")),
		"enemies": entry.get("enemies", []),
		"xp_reward": int(entry.get("xp_reward", 0)),
		"coin_reward": int(entry.get("coin_reward", 0)),
	}


func _event_battle_info() -> Dictionary:
	var event_id := String(battle_source_ref.get("event", ""))
	var stage_key := String(battle_source_ref.get("stage", ""))
	var stage := DB.event_stage(event_id, stage_key)
	if stage.is_empty():
		return {}
	return {
		"id": stage_key,
		"name": "%s - %s" % [String(DB.get_event(event_id).get("name", event_id)), String(stage.get("name", stage_key))],
		"background": String(stage.get("background", "")),
		"enemies": stage.get("enemies", []),
		"xp_reward": int(stage.get("xp_reward", 0)),
		"coin_reward": int(stage.get("coin_reward", 0)),
	}


func _tower_battle_info() -> Dictionary:
	var tower_id := String(battle_source_ref.get("tower", ""))
	var floor_number := int(battle_source_ref.get("floor", 0))
	var floor_data := DB.tower_floor(tower_id, floor_number)
	if floor_data.is_empty():
		return {}
	return {
		"id": "%s_%d" % [tower_id, floor_number],
		"name": "%s - %s" % [String(DB.get_tower(tower_id).get("name", tower_id)), String(floor_data.get("name", "Piso %d" % floor_number))],
		"background": String(DB.get_tower(tower_id).get("background", "")),
		"enemies": floor_data.get("enemies", []),
		"xp_reward": int(floor_data.get("xp_reward", 0)),
		"coin_reward": int(floor_data.get("coin_reward", 0)),
	}


## Elige la batalla suelta. Sus enemigos pasan a ser los del combate.
func select_stage(new_id: String) -> void:
	var stage := DB.get_stage(String(new_id))
	if stage.is_empty():
		return
	battle_source = BATTLE_STAGE
	battle_source_ref = { "stage": String(new_id) }
	stage_id = String(new_id)
	var stage_enemies: Array = stage.get("enemies", [])
	if not stage_enemies.is_empty():
		current_stage_enemies = stage_enemies.duplicate()


## Prepara una batalla desde cualquiera de los cuatro origenes. Es el UNICO sitio
## que fija los enemigos de la batalla: la pantalla que abre el combate solo llama
## a esto, asi que los enemigos no pueden venir de una lista escrita a mano.
func prepare_battle(source: String, ref: Dictionary) -> bool:
	battle_source = String(source)
	battle_source_ref = (ref as Dictionary).duplicate(true)
	var info := current_stage()
	if info.is_empty():
		return false
	var enemies: Array = info.get("enemies", [])
	if enemies.is_empty():
		return false
	current_stage_enemies = enemies.duplicate()
	if source == BATTLE_STAGE:
		stage_id = String(ref.get("stage", stage_id))
	# SIN ATAJOS: el combate lleva SIEMPRE el equipo que el jugador ve en la
	# pantalla, huecos incluidos. Un stage que pida un equipo concreto (por
	# ejemplo 1 VS 1) lo COMPRUEBA y lo rechaza si no encaja, pero nunca recorta
	# el equipo por su cuenta: si el jugador no lo ha montado, no se juega asi.
	battle_party = []
	battle_reserve = []
	_tower_lead = []
	return true


## Plantilla de la batalla. Vacia significa "el equipo normal" (GameState.party).
## Un stage que se pelea SOLO con una unidad (1 VS 1) la fija aqui: asi el combate
## lleva exactamente a esa unidad, sin companeros, aunque el jugador tenga su
## equipo de 4 configurado. Es un dato del stage, no una regla por personaje.
func battle_party_ids() -> Array:
	if battle_party.is_empty():
		# El equipo normal, SIN los huecos: una posicion vacia no es una unidad y
		# no debe llegar al combate como una entrada mas.
		return party_ids()
	return battle_party


## Datos del equipo que COMBATE. Las pantallas y el combate leen esto, nunca
## party_data() directamente, para que una batalla 1 VS 1 no arrastre al equipo.
func battle_party_data() -> Array:
	var data_list: Array = []
	for id in battle_party_ids():
		var key := String(id)
		if key.is_empty():
			continue
		var data := character_data(key)
		if not data.is_empty():
			data_list.append(data)
	return data_list


## QUITADO A PROPOSITO: aqui vivia el atajo que recortaba el equipo a una sola
## unidad cuando el stage pedia un 1 VS 1. Ese recorte hacia que el combate
## llevara un equipo DISTINTO del que el jugador veia en la pantalla EQUIPO. La
## regla del proyecto es que se juega con lo que se ve: quien decide si el equipo
## vale es la comprobacion del stage (event_party_ready), que lo RECHAZA con su
## motivo si no encaja, en vez de cambiarlo por detras.


## Nombre de la batalla en curso (lo que se lee arriba del combate).
func current_battle_title() -> String:
	return String(current_stage().get("name", ""))


## Resumen de la fuente para la pantalla de resultado: de donde era la batalla.
func battle_source_label() -> String:
	match battle_source:
		BATTLE_STORY:
			return "HISTORIA"
		BATTLE_EVENT:
			return "EVENTO"
		BATTLE_TOWER:
			return "TORRE"
		_:
			return "BATALLA"


## Recompensas de una batalla. Se llama UNA vez, desde la pantalla de resultado.
## Devuelve el informe que pinta esa pantalla: XP entregada, monedas ganadas y que
## ha pasado con el nivel de cada participante.
##
## La XP va a los personajes que han combatido (ally_ids), no a todo el roster: un
## personaje que no ha pisado la batalla no sube. Y se usa GameState.add_xp, que es
## el mismo sistema de XP de la ficha, asi que no hay una segunda curva.
func grant_battle_rewards(token: int, ally_ids: Array, victory: bool) -> Dictionary:
	# Una batalla solo paga una vez. Si el token no es el de la batalla en curso,
	# o si esa batalla ya ha cobrado, no se entrega nada.
	if token != battle_token or _rewarded_token == token:
		return _empty_report()
	_rewarded_token = token
	# Contadores globales: una batalla jugada, y ganada o perdida. Cuentan
	# tambien al abandonar (el abandono cierra la batalla sin premios). Se
	# cuentan AQUI y una sola vez para todos los origenes, asi que historia,
	# evento y torre no llevan su propia cuenta de combates jugados.
	add_counter("combates_jugados")
	add_counter("victorias" if victory else "derrotas")
	var report := _pay_battle_by_source(ally_ids, victory)
	# El guardado cubre tambien la derrota: el contador sube aunque no haya premio.
	save_game()
	return report


## Paga la batalla segun su ORIGEN. Cada origen sabe calcular su premio en un
## sitio propio, pero todos devuelven el mismo informe, asi que la pantalla de
## resultado no cambia segun de donde venga la batalla.
func _pay_battle_by_source(ally_ids: Array, victory: bool) -> Dictionary:
	if not victory:
		if battle_source == BATTLE_TOWER:
			tower_register_defeat(String(battle_source_ref.get("tower", "")))
		var empty := _empty_report()
		empty["mode"] = battle_source
		empty["title"] = current_stage().get("name", "")
		return empty
	match battle_source:
		BATTLE_STORY:
			return _pay_story_battle(ally_ids)
		BATTLE_EVENT:
			return _pay_event_battle(ally_ids)
		BATTLE_TOWER:
			return _pay_tower_battle(ally_ids)
		_:
			return _pay_stage_battle(ally_ids)


## Batalla suelta: premio de su JSON y desbloqueo de la siguiente de la cadena.
func _pay_stage_battle(ally_ids: Array) -> Dictionary:
	var stage := current_stage()
	var xp := int(stage.get("xp_reward", 0))
	var coins_earned := int(stage.get("coin_reward", 0))
	coins += coins_earned
	var report := _empty_report()
	report["xp"] = xp
	report["coins"] = coins_earned
	report["characters"] = _grant_story_xp(ally_ids, xp)
	report["granted"] = true
	report["mode"] = BATTLE_STAGE
	report["title"] = String(stage.get("name", ""))
	var unlocked_ids := mark_stage_completed(stage_id)
	report["unlocked"] = unlocked_ids
	report["unlocked_names"] = _stage_names(unlocked_ids)
	return report


## Nivel de historia: quien marca la dificultad y paga es complete_story_level,
## que ya sabe que superar EXTREMO arrastra y paga NORMAL y DIFICIL.
func _pay_story_battle(ally_ids: Array) -> Dictionary:
	var level_id := String(battle_source_ref.get("level", ""))
	var difficulty := String(battle_source_ref.get("difficulty", ""))
	var info: Dictionary = complete_story_level(level_id, difficulty, ally_ids)
	var report := _empty_report()
	report["xp"] = int(info.get("xp", 0))
	report["coins"] = int(info.get("coins", 0))
	report["characters"] = info.get("characters", [])
	report["granted"] = bool(info.get("ok", false))
	report["mode"] = BATTLE_STORY
	report["title"] = String(info.get("level_name", ""))
	report["difficulty"] = difficulty
	report["already"] = bool(info.get("already", false))
	report["completed"] = info.get("completed", [])
	var unlocked_ids: Array = info.get("unlocked", [])
	report["unlocked"] = unlocked_ids
	report["unlocked_names"] = _story_names(unlocked_ids)
	return report


## Stage de evento: paga complete_event_stage, que cobra una sola vez la primera
## victoria y luego solo repite los drops que el JSON declare.
func _pay_event_battle(ally_ids: Array) -> Dictionary:
	var event_id := String(battle_source_ref.get("event", ""))
	var stage_key := String(battle_source_ref.get("stage", ""))
	var info: Dictionary = complete_event_stage(event_id, stage_key, ally_ids)
	var report := _empty_report()
	report["xp"] = int(info.get("xp", 0))
	report["coins"] = int(info.get("coins", 0))
	report["characters"] = info.get("characters", [])
	report["granted"] = bool(info.get("ok", false))
	report["mode"] = BATTLE_EVENT
	report["title"] = String(info.get("stage_name", ""))
	report["drops"] = info.get("drops", [])
	report["event_completed"] = bool(info.get("event_completed", false))
	report["times_completed"] = int(info.get("times_completed", 0))
	report["unlocked_names"] = _item_drop_texts(info.get("drops", []))
	return report


## Piso de torre: paga complete_tower_floor, que apunta el piso alcanzado y solo
## entrega el premio la primera vez que se supera ese piso.
func _pay_tower_battle(ally_ids: Array) -> Dictionary:
	var tower_id := String(battle_source_ref.get("tower", ""))
	var floor_number := int(battle_source_ref.get("floor", 0))
	var info: Dictionary = complete_tower_floor(tower_id, floor_number, ally_ids)
	var report := _empty_report()
	report["xp"] = int(info.get("xp", 0))
	report["coins"] = int(info.get("coins", 0))
	report["characters"] = info.get("characters", [])
	report["granted"] = bool(info.get("ok", false))
	report["mode"] = BATTLE_TOWER
	report["title"] = String(info.get("floor_name", ""))
	report["drops"] = info.get("drops", [])
	report["best_floor"] = int(info.get("best_floor", 0))
	report["checkpoint"] = int(info.get("checkpoint", 0))
	report["unlocked_names"] = _item_drop_texts(info.get("drops", []))
	return report


## Nombres legibles de una lista de stages, para el aviso de "batalla nueva".
func _stage_names(ids: Array) -> Array:
	var out: Array = []
	for raw_id in ids:
		var stage := DB.get_stage(String(raw_id))
		out.append(String(stage.get("name", raw_id)))
	return out


## Nombres legibles de una lista de niveles de historia, para el mismo aviso.
func _story_names(ids: Array) -> Array:
	var out: Array = []
	for raw_id in ids:
		var key := String(raw_id)
		# Un id de MUNDO (world_002) tambien puede llegar aqui: el aviso dice
		# "mundo nuevo" en ese caso, sin que la pantalla tenga que distinguirlo.
		if DB.worlds.has(key):
			out.append("MUNDO: %s" % String(DB.get_world(key).get("name", key)))
			continue
		var level := DB.world_level(DB.world_of_level(key), key)
		out.append(String(level.get("name", key)))
	return out


## Texto corto de una lista de drops de objeto ("Uniforme de conejita x2"), para
## que la pantalla de resultado los anuncie sin leer claves del JSON.
func _item_drop_texts(drops: Variant) -> Array:
	var out: Array = []
	if not (drops is Array):
		return out
	for entry in drops:
		if not (entry is Dictionary):
			continue
		var item_id := String((entry as Dictionary).get("item", ""))
		var amount := int((entry as Dictionary).get("amount", 0))
		out.append("%s x%d" % [item_display_name(item_id), amount])
	return out


## --- Contadores globales ----------------------------------------------------

func add_counter(key: String, amount: int = 1) -> void:
	counters[key] = int(counters.get(key, 0)) + amount


## Valor de un contador global. "personajes_obtenidos" sale del roster, que es
## quien lo sabe de verdad: guardarlo aparte seria una segunda fuente de verdad.
func counter_value(key: String) -> int:
	if key == "personajes_obtenidos":
		return roster.size()
	return int(counters.get(key, 0))


## --- Stages: completado y desbloqueo ----------------------------------------

func stage_completed(id: String) -> bool:
	return completed_stages.has(String(id))


## El primer stage siempre esta abierto; el resto pide el anterior ganado. La
## cadena sale de DB.all_stages(), asi que anadir una batalla nueva la mete en la
## cadena sin tocar este codigo ni la pantalla.
func stage_unlocked(id: String) -> bool:
	var stages: Array = DB.all_stages()
	for index in stages.size():
		if String(stages[index].get("id", "")) != String(id):
			continue
		if index == 0:
			return true
		return completed_stages.has(String(stages[index - 1].get("id", "")))
	return false


func unlocked_stage_ids() -> Array:
	var out: Array = []
	for stage in DB.all_stages():
		var sid := String(stage.get("id", ""))
		if stage_unlocked(sid):
			out.append(sid)
	return out


## Marca un stage como ganado y devuelve SOLO los que se acaban de desbloquear,
## que es lo que anuncia la pantalla de resultado.
func mark_stage_completed(id: String) -> Array:
	var key := String(id)
	if key.is_empty() or completed_stages.has(key):
		return []
	var before := unlocked_stage_ids()
	completed_stages.append(key)
	var after := unlocked_stage_ids()
	var newly: Array = []
	for sid in after:
		if not before.has(sid):
			newly.append(sid)
	save_game()
	return newly


## --- Misiones ---------------------------------------------------------------

## Estado de una mision ya resuelto para pintar. El progreso sale del contador
## global que indique su JSON, asi que una mision nueva es datos y nada mas.
func mission_state(id: String) -> Dictionary:
	var data: Dictionary = DB.get_mission(String(id))
	if data.is_empty():
		return {}
	var stat := String(data.get("stat", ""))
	var target := maxi(1, int(data.get("target", 1)))
	var progress := mini(counter_value(stat), target)
	return {
		"id": String(id),
		"name": String(data.get("name", id)),
		"description": String(data.get("description", "")),
		"stat": stat,
		"category": String(data.get("category", "GENERAL")),
		"target": target,
		"progress": progress,
		"completed": progress >= target,
		"claimed": bool(missions_claimed.get(String(id), false)),
		"reward_coins": int(data.get("reward_coins", 0)),
		"reward_gems": int(data.get("reward_gems", 0)),
	}


func all_missions_state() -> Array:
	var out: Array = []
	for mission in DB.all_missions():
		out.append(mission_state(String(mission.get("id", ""))))
	return out


## Cobra una mision completada. Devuelve lo entregado, o vacio si no habia nada
## que cobrar: una mision completada solo paga UNA vez.
func claim_mission(id: String) -> Dictionary:
	var state := mission_state(String(id))
	if state.is_empty() or not bool(state["completed"]) or bool(state["claimed"]):
		return {}
	var coins_earned := int(state["reward_coins"])
	var gems_earned := int(state["reward_gems"])
	coins += coins_earned
	gems += gems_earned
	missions_claimed[String(id)] = true
	save_game()
	return {
		"coins": coins_earned,
		"gems": gems_earned,
		"name": String(state["name"]),
	}


func display_name(id: String) -> String:
	var data: Dictionary = DB.get_character(String(id))
	return String(data.get("name", id))


## Obtenidos frente a existentes: es el contador de la coleccion ("28 / 28").
## Con el gacha, owned_count subira solo cuando un personaje entre en el roster.
func owned_count() -> int:
	return roster.size()


func total_count() -> int:
	return DB.characters.size()


## --- Obtener personajes, monedas y gemas ------------------------------------

## Entrega un personaje al jugador. Si no lo tenia, entra en el roster con nivel 1
## (el progreso lo pone ensure_defaults, que es el unico sitio que lo inicializa);
## si ya lo tenia, suma un DUPLICADO en lugar de duplicar la entrada del roster.
## Devuelve el informe para que la pantalla lo anuncie.
func add_character(id: String) -> Dictionary:
	var key := String(id)
	if DB.get_character(key).is_empty():
		return { "id": key, "added": false, "duplicate": false, "known": false }
	var was_owned := is_owned(key)
	if was_owned:
		duplicates[key] = duplicates_of(key) + 1
		add_counter("duplicados_obtenidos")
		add_counter("invocaciones")
		save_game()
		return {
			"id": key,
			"name": display_name(key),
			"rarity": rarity_of(key),
			"added": false,
			"duplicate": true,
			"known": true,
			"duplicates": duplicates_of(key),
		}
	roster.append(key)
	progress[key] = { "level": Progression.LEVEL_MIN, "xp": 0 }
	duplicates[key] = 0
	add_counter("invocaciones")
	save_game()
	return {
		"id": key,
		"name": display_name(key),
		"rarity": rarity_of(key),
		"added": true,
		"duplicate": false,
		"known": true,
		"duplicates": 0,
	}


## Gasto de monedas. Devuelve false y NO gasta nada si no llega: el jugador nunca
## se queda con monedas negativas porque una pantalla no comprobase el saldo.
func spend_coins(amount: int) -> bool:
	if amount <= 0:
		return true
	if coins < amount:
		return false
	coins -= amount
	add_counter("monedas_gastadas", amount)
	return true


## Gasto de gemas, con la misma regla: o se paga entero, o no se paga.
func spend_gems(amount: int) -> bool:
	if amount <= 0:
		return true
	if gems < amount:
		return false
	gems -= amount
	add_counter("gemas_gastadas", amount)
	return true


func add_coins(amount: int) -> void:
	if amount > 0:
		coins += amount


## --- Tienda -----------------------------------------------------------------

## Compra un objeto de la tienda. TODO sale del JSON del objeto (cost_coins,
## cost_gems y grant), asi que anadir un articulo es crear su archivo y no tocar
## ni esta funcion ni la pantalla. Reglas:
##   - se comprueban los DOS costes ANTES de cobrar: o se paga entero, o no se
##     paga nada;
##   - si la entrega no se puede hacer, se DEVUELVE el dinero: no hay compras
##     que cobren y no den nada;
##   - se guarda al momento.
func buy_shop_item(item_id: String) -> Dictionary:
	var key := String(item_id)
	# Se pregunta si EXISTE antes de pedirlo: un id viejo devuelve un informe con
	# su motivo en vez de soltar un error, porque no es un fallo del juego.
	var exists := DB.has_shop_item(key)
	var item := DB.get_shop_item(key) if exists else {}
	var report := {
		"ok": false,
		"item": key,
		"name": String(item.get("name", key)),
		"reason": "",
		"cost_coins": 0,
		"cost_gems": 0,
		"granted": {},
		"coins": coins,
		"gems": gems,
	}
	if not exists:
		report["reason"] = "Ese objeto no existe en la tienda."
		return report
	var price_coins := maxi(0, int(item.get("cost_coins", 0)))
	var price_gems := maxi(0, int(item.get("cost_gems", 0)))
	report["cost_coins"] = price_coins
	report["cost_gems"] = price_gems
	if coins < price_coins or gems < price_gems:
		report["reason"] = "No te llega: cuesta %d monedas y %d gemas." % [price_coins, price_gems]
		return report
	spend_coins(price_coins)
	spend_gems(price_gems)
	var granted := _grant_shop_reward(item.get("grant", {}))
	if granted.is_empty():
		# Sin entrega no hay compra: se devuelve el dinero tal cual estaba.
		coins += price_coins
		gems += price_gems
		report["reason"] = "Ese objeto no entrega nada."
		return report
	report["ok"] = true
	report["granted"] = granted
	report["coins"] = coins
	report["gems"] = gems
	save_game()
	return report


## Entrega la recompensa de un objeto de tienda. Los tipos viven en los datos:
##   { type: "coins",     amount: N }                    -> monedas
##   { type: "gems",      amount: N }                    -> gemas
##   { type: "materials", amount: N }                    -> materiales
##   { type: "item",      item: "<id>", amount: N }      -> objeto del inventario
##   { type: "character", character_id: "<id>" }         -> personaje (o duplicado)
## Devuelve {} con un tipo desconocido, y entonces la compra se cancela.
func _grant_shop_reward(grant) -> Dictionary:
	if not (grant is Dictionary) or (grant as Dictionary).is_empty():
		return {}
	var data: Dictionary = grant
	var kind := String(data.get("type", ""))
	var amount := maxi(1, int(data.get("amount", 1)))
	match kind:
		"coins":
			add_coins(amount)
			return { "type": kind, "amount": amount, "text": "%d monedas" % amount }
		"gems":
			gems += amount
			return { "type": kind, "amount": amount, "text": "%d gemas" % amount }
		"materials":
			materials += amount
			return { "type": kind, "amount": amount, "text": "%d materiales" % amount }
		"item":
			var item_id := String(data.get("item", ""))
			if item_id.is_empty():
				return {}
			add_item(item_id, amount)
			return { "type": kind, "id": item_id, "amount": amount, "text": "%d x %s" % [amount, item_display_name(item_id)] }
		"character":
			var char_id := String(data.get("character_id", ""))
			if char_id.is_empty():
				return {}
			var info := add_character(char_id)
			var label := String(info.get("name", display_name(char_id)))
			if bool(info.get("duplicate", false)):
				label += " (duplicado)"
			return { "type": kind, "id": char_id, "amount": 1, "text": label }
	return {}


func add_gems(amount: int) -> void:
	if amount > 0:
		gems += amount


func add_materials(amount: int) -> void:
	if amount > 0:
		materials += amount


## --- Invocacion (gacha) ------------------------------------------------------
## Todo sale de DATOS: el banner dice el coste, las probabilidades y (a traves de
## ellas) de que rarezas sale el pool. Aqui no hay ningun porcentaje escrito.
##
## REGLA DE LAS PROBABILIDADES: son POR TIRADA. Una multi de 10 son DIEZ tiradas
## independientes, cada una con su propia probabilidad de cada rareza; no es una
## sola tirada para todo el grupo.

## Personajes que NO pueden salir de una invocacion. Es DATO, no una lista escrita
## en el codigo:
##   - los que declaran "gacha": false en su JSON (unidades de evento GRATUITAS,
##     como Sakuta y Mai, que se consiguen jugando su evento);
##   - las FORMAS ya evolucionadas, que declaran "evolved_from" (Sakuta es la forma
##     UR de Sakuta y Mai: se consigue evolucionando, no tirando gemas);
##   - el DESTINO de cualquier ruta de evolucion especial.
## Anadir una ruta nueva o marcar una unidad como gratuita la excluye sola, asi que
## ninguna forma de evolucion puede colarse por un banner.
func gacha_excluded_ids() -> Array:
	var out: Array = []
	for id in DB.characters.keys():
		var key := String(id)
		var data := DB.get_character(key)
		if data.is_empty():
			continue
		if data.has("gacha") and not bool(data.get("gacha", true)):
			out.append(key)
			continue
		if not String(data.get("evolved_from", "")).is_empty():
			out.append(key)
	for raw_route in DB.special_evolution_routes():
		if not (raw_route is Dictionary):
			continue
		var to_id := String((raw_route as Dictionary).get("to", ""))
		if not to_id.is_empty() and not out.has(to_id):
			out.append(to_id)
	return out


## Probabilidades del banner reducidas a las rarezas que EXISTEN de verdad entre
## los personajes QUE PUEDEN SALIR. Si el banner declara una rareza sin ningun
## candidato invocable, esa entrada no se tiene en cuenta (y no distorsiona las
## demas): asi el 15% de SSR es real y un UR sin candidatos no se sortea.
func banner_rates(banner_id: String) -> Dictionary:
	# Las probabilidades se devuelven TAL COMO estan en el JSON (sin descartar ni
	# renormalizar rarezas): lo que se configura es lo que se sortea. Si una
	# rareza no tiene personajes o la tabla no suma 1, banner_problems() lo dice y
	# summon() se niega a tirar en vez de repartir el hueco en silencio.
	var banner := DB.get_banner(String(banner_id))
	var raw = banner.get("rates", {})
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for rarity in (raw as Dictionary).keys():
		var value := maxf(0.0, float((raw as Dictionary)[rarity]))
		if value > 0.0:
			out[String(rarity)] = value
	return out


## Fallos de configuracion de un banner (lista vacia = valido): la tabla tiene que
## sumar exactamente 1 y cada rareza con probabilidad tiene que tener al menos un
## personaje en el pool (si no, esa probabilidad se perderia o se repartiria mal).
func banner_problems(banner_id: String) -> Array:
	var problems: Array = []
	var rates := banner_rates(banner_id)
	if rates.is_empty():
		problems.append("sin probabilidades")
		return problems
	var total := 0.0
	for k in rates:
		total += float(rates[k])
	if absf(total - 1.0) > 1e-9:
		problems.append("las probabilidades suman %.6f y no 1" % total)
	var pool := banner_pool(banner_id)
	var featured := banner_featured_rates(banner_id)
	var used: Dictionary = {}
	for id in featured.keys():
		if not pool.has(String(id)):
			problems.append("'%s' tiene tasa propia pero no esta en el pool del banner" % id)
			continue
		var r := String(DB.get_character(String(id)).get("rarity", ""))
		used[r] = float(used.get(r, 0.0)) + float(featured[id])
	for r in used.keys():
		if float(used[r]) > float(rates.get(r, 0.0)) + 1e-9:
			problems.append("las tasas propias de %s superan la tasa de la rareza" % r)
	for k in rates:
		var found := false
		for id in pool:
			if String(DB.get_character(String(id)).get("rarity", "")) == String(k):
				found = true
				break
		if not found:
			problems.append("la rareza %s tiene probabilidad pero ningun personaje en el pool" % k)
	return problems


## Rarezas que existen entre los personajes cargados, contadas. Es lo que permite
## avisar de un banner mal configurado en lugar de sortear rarezas que no existen.
func character_rarities() -> Dictionary:
	var out: Dictionary = {}
	var excluded := gacha_excluded_ids()
	for id in DB.characters.keys():
		var key := String(id)
		if excluded.has(key):
			continue
		if bool(DB.get_character(key).get("banner_only", false)):
			continue
		var rarity := String(DB.get_character(key).get("rarity", ""))
		if not rarity.is_empty():
			out[rarity] = int(out.get(rarity, 0)) + 1
	return out


## Personajes que pueden salir por el banner: los que tienen una rareza con
## probabilidad. El pool no se escribe en ningun script.
func banner_pool(banner_id: String) -> Array:
	var rates := banner_rates(banner_id)
	var out: Array = []
	if rates.is_empty():
		return out
	# Fuera los que no se pueden invocar: unidades gratuitas de evento y formas
	# que solo se consiguen evolucionando.
	var excluded := gacha_excluded_ids()
	# Banner por categorias: solo personajes con alguna de ellas (si el JSON la pide).
	var wanted: Array = DB.get_banner(String(banner_id)).get("pool_categories", [])
	for id in DB.characters.keys():
		var key := String(id)
		if excluded.has(key):
			continue
		var data := DB.get_character(key)
		if not rates.has(String(data.get("rarity", ""))):
			continue
		# Unidades EXCLUSIVAS de banner (banner_only): solo salen si ESTE banner las
		# lista en "exclusive_ids". No entran en ningun otro, aunque el pool sea
		# "todos los de esa rareza".
		if bool(data.get("banner_only", false)) and not _banner_lists_exclusive(String(banner_id), key):
			continue
		if not wanted.is_empty() and not _banner_lists_exclusive(String(banner_id), key):
			var cats: Array = data.get("categories", [])
			var match_found := false
			for c in wanted:
				if cats.has(c):
					match_found = true
					break
			if not match_found:
				continue
		out.append(key)
	out.sort()
	return out


func _banner_lists_exclusive(banner_id: String, char_id: String) -> bool:
	var ids = DB.get_banner(String(banner_id)).get("exclusive_ids", [])
	return ids is Array and (ids as Array).has(char_id)


## Probabilidades ABSOLUTAS por tirada de los personajes con tasa propia en el
## banner ("featured_rates": { id: probabilidad por tirada }). Cada una tiene que
## caber dentro de la tasa de SU rareza; el resto de esa rareza se reparte a partes
## iguales entre los demas candidatos. Asi la tabla total sigue siendo la del banner.
func banner_featured_rates(banner_id: String) -> Dictionary:
	var out: Dictionary = {}
	var raw = DB.get_banner(String(banner_id)).get("featured_rates", {})
	if raw is Dictionary:
		for id in (raw as Dictionary).keys():
			var value := float((raw as Dictionary)[id])
			if value > 0.0:
				out[String(id)] = value
	return out


## Tabla EFECTIVA del banner, lista para pintar y para comprobar en pruebas: una
## fila por rareza con su tasa y, dentro de ella, las filas de los personajes con
## tasa propia. [ { rarity, rate, id: "" } , { rarity, rate, id: "david_lucy_duo" } ]
func banner_rate_table(banner_id: String) -> Array:
	var rates := banner_rates(banner_id)
	var featured := banner_featured_rates(banner_id)
	var rows: Array = []
	for rarity in rates.keys():
		var rest := float(rates[rarity])
		for id in featured.keys():
			if String(DB.get_character(String(id)).get("rarity", "")) == String(rarity):
				rest -= float(featured[id])
		rows.append({ "rarity": String(rarity), "rate": rest if rest > 1e-12 else 0.0, "id": "" })
		for id in featured.keys():
			if String(DB.get_character(String(id)).get("rarity", "")) == String(rarity):
				rows.append({ "rarity": String(rarity), "rate": float(featured[id]), "id": String(id) })
	return rows


## Elige el personaje de una rareza respetando las tasas propias del banner.
func _pick_candidate(banner_id: String, rarity: String, candidates: Array) -> String:
	var featured := banner_featured_rates(banner_id)
	var rarity_rate := float(banner_rates(banner_id).get(rarity, 0.0))
	var u := randf()
	var acc := 0.0
	var others: Array = []
	for id in candidates:
		if featured.has(String(id)) and rarity_rate > 0.0:
			acc += float(featured[String(id)]) / rarity_rate
			if u < acc:
				return String(id)
		else:
			others.append(String(id))
	if others.is_empty():
		return String(candidates[randi() % candidates.size()])
	return String(others[randi() % others.size()])


## Coste de una invocacion de `count` tiradas, leido del banner. El precio de la
## multi vive en los datos, asi que cambiar de banner no toca ningun script.
func banner_cost(banner_id: String, count: int) -> int:
	var banner := DB.get_banner(String(banner_id))
	if count <= 1:
		return maxi(0, int(banner.get("cost_gems", 0)))
	var multi := int(banner.get("multi_cost_gems", 0))
	if multi > 0:
		return multi
	return maxi(0, int(banner.get("cost_gems", 0))) * maxi(1, count)


## Tirada de rareza de UNA invocacion. Devuelve la rareza, o vacio si el banner no
## tiene probabilidades utilizables.
func roll_rarity(rates: Dictionary) -> String:
	return rarity_for_roll(rates, randf())


## Rareza que corresponde a un numero 0..1 (la parte determinista de la tirada,
## separada para poder comprobar los umbrales exactos en las pruebas).
func rarity_for_roll(rates: Dictionary, unit_roll: float) -> String:
	var total := 0.0
	for rarity in rates.keys():
		total += maxf(0.0, float(rates[rarity]))
	if total <= 0.0:
		return ""
	var roll := unit_roll * total
	var accumulated := 0.0
	for rarity in rates.keys():
		accumulated += maxf(0.0, float(rates[rarity]))
		if roll < accumulated:
			return String(rarity)
	return String(rates.keys()[rates.size() - 1])


## Invocacion de `count` tiradas INDEPENDIENTES. Primero cobra las gemas: si no
## llega, no se tira nada. Despues, cada posicion tira su rareza y elige un
## personaje de esa rareza; el personaje entra en el roster (o cuenta como
## duplicado) por el MISMO add_character que usa el resto del juego.
## Devuelve el informe con los resultados, para que la pantalla los revele.
func summon(banner_id: String, count: int = 1, stage_reveal: bool = false) -> Dictionary:
	var key := String(banner_id)
	var tries := maxi(1, int(count))
	var report := {
		"ok": false,
		"reason": "",
		"banner": key,
		"banner_name": String(DB.get_banner(key).get("name", key)),
		"count": tries,
		"cost": 0,
		"gems": gems,
		"results": [],
		"new_count": 0,
		"duplicate_count": 0,
	}
	if DB.get_banner(key).is_empty():
		report["reason"] = "Ese banner no existe."
		return report
	if not bool(DB.get_banner(key).get("enabled", true)):
		report["reason"] = "Ese banner no esta disponible."
		return report
	# Una secuencia de revelado a medias bloquea nuevas invocaciones: primero se
	# ensenan (o se cierran) los resultados que el jugador ya ha pagado.
	if not pending_reveal.is_empty():
		report["reason"] = "Hay una invocacion sin revelar."
		return report
	var rates := banner_rates(key)
	if rates.is_empty():
		report["reason"] = "El banner no tiene probabilidades."
		return report
	var problems := banner_problems(key)
	if not problems.is_empty():
		report["reason"] = "Banner mal configurado: %s." % "; ".join(PackedStringArray(problems))
		return report
	var pool := banner_pool(key)
	if pool.is_empty():
		report["reason"] = "El banner no tiene ningun personaje disponible."
		return report
	var cost := banner_cost(key, tries)
	report["cost"] = cost
	if not spend_gems(cost):
		report["reason"] = "Faltan gemas: cuesta %d y tienes %d." % [cost, gems]
		return report
	var results: Array = []
	for i in tries:
		var rarity := roll_rarity(rates)
		var candidates: Array = []
		for id in pool:
			if String(DB.get_character(String(id)).get("rarity", "")) == rarity:
				candidates.append(String(id))
		var picked: String = _pick_candidate(key, rarity, candidates)
		var info := add_character(picked)
		results.append({
			"id": picked,
			"name": display_name(picked),
			"rarity": rarity_of(picked),
			"new": bool(info.get("added", false)),
			"duplicate": bool(info.get("duplicate", false)),
			"duplicates": int(info.get("duplicates", 0)),
		})
		if bool(info.get("added", false)):
			report["new_count"] = int(report["new_count"]) + 1
		else:
			report["duplicate_count"] = int(report["duplicate_count"]) + 1
	report["results"] = results
	report["ok"] = true
	report["gems"] = gems
	report["reason"] = "%d invocacion(es)." % tries
	if stage_reveal:
		# Los resultados quedan FIJADOS junto al cobro y la entrega, en el mismo
		# guardado: si el juego se cierra a mitad de la revelacion, al volver se
		# ensenan los mismos sin tirar ni cobrar de nuevo.
		pending_reveal = {
			"banner": key,
			"banner_name": String(report["banner_name"]),
			"count": tries,
			"cost": cost,
			"index": 0,
			"results": results.duplicate(true),
			"new_count": int(report["new_count"]),
			"duplicate_count": int(report["duplicate_count"]),
			"cinematic_done": false,
		}
	save_game()
	return report


## --- Secuencia de revelado -----------------------------------------------------
## Estado de la invocacion que se esta ensenando una a una. Vive en el guardado:
## es solo PRESENTACION (los resultados ya estan cobrados y entregados), asi que
## recuperarla nunca vuelve a tirar ni a cobrar.
var pending_reveal: Dictionary = {}


func has_pending_reveal() -> bool:
	return not pending_reveal.is_empty()


## Resultado que toca revelar ahora, o {} si la secuencia ha terminado.
func reveal_current() -> Dictionary:
	if pending_reveal.is_empty():
		return {}
	var results: Array = pending_reveal.get("results", [])
	var i := int(pending_reveal.get("index", 0))
	if i < 0 or i >= results.size():
		return {}
	return (results[i] as Dictionary).duplicate(true)


## Avanza al siguiente resultado. Devuelve true si aun queda alguno por ensenar.
func reveal_advance() -> bool:
	if pending_reveal.is_empty():
		return false
	pending_reveal["index"] = int(pending_reveal.get("index", 0)) + 1
	save_game()
	return int(pending_reveal["index"]) < (pending_reveal.get("results", []) as Array).size()


## Marca que la cinematica completa del duo ya se ha visto en esta secuencia:
## los siguientes ejemplares hacen la revelacion especial corta.
func reveal_mark_cinematic() -> void:
	if pending_reveal.is_empty():
		return
	pending_reveal["cinematic_done"] = true
	save_game()


## Cierra la secuencia y devuelve su resumen (para ensenar la pantalla final).
func reveal_finish() -> Dictionary:
	var summary := pending_reveal.duplicate(true)
	pending_reveal = {}
	save_game()
	return summary



## --- DUPES -----------------------------------------------------------------------
## Copias repetidas de un personaje -> mejora permanente de ESE personaje. Reglas y
## numeros en data/dupes/rules.json. Copias EXTRA obtenidas = duplicates[id] (la primera
## copia del personaje no cuenta: es el propio personaje); las ya gastadas salen de
## dupe_levels[id] (cada nivel cuesta copies_per_level); disponibles = extra - gastadas.
## Es independiente del nivel de combate, la rareza y la
## evolucion (no se tocan al evolucionar), y los bonus entran en combate como
## modificadores de origen "dupe": reaplicar el mismo origen SUSTITUYE, no acumula.

func dupe_max_level() -> int:
	return int(DB.dupe_rules.get("max_level", 0))


func dupe_level_of(id: String) -> int:
	return clampi(int(dupe_levels.get(String(id), 0)), 0, dupe_max_level())


## Copias que el jugador puede gastar ahora: las obtenidas menos las ya consumidas.
func dupe_copies_available(id: String) -> int:
	return maxi(0, duplicates_of(String(id)) - _dupe_copies_spent(String(id)))


## Copias ya consumidas: suma del coste de cada nivel alcanzado.
func _dupe_copies_spent(id: String) -> int:
	var spent := 0
	var costs: Array = DB.dupe_rules.get("copies_per_level", [])
	for i in dupe_level_of(id):
		spent += int(costs[i])
	return spent


## Nivel mas alto de Dupe que se paga con `budget` copias gastadas (se usa al fusionar los
## Dupes de dos identidades en una evolucion especial).
func _dupe_level_for_budget(budget: int) -> int:
	var costs: Array = DB.dupe_rules.get("copies_per_level", [])
	var level := 0
	var spent := 0
	while level < dupe_max_level() and level < costs.size() and spent + int(costs[level]) <= budget:
		spent += int(costs[level])
		level += 1
	return level


## Coste en copias del SIGUIENTE nivel, o 0 si ya esta al maximo.
func dupe_next_cost(id: String) -> int:
	var level := dupe_level_of(id)
	var costs: Array = DB.dupe_rules.get("copies_per_level", [])
	if level >= dupe_max_level() or level >= costs.size():
		return 0
	return int(costs[level])


## Bonus TOTALES de un nivel de Dupe: { stat: valor }. Nivel fuera de rango = {}.
func dupe_bonus_for_level(level: int) -> Dictionary:
	var levels: Array = DB.dupe_rules.get("levels", [])
	if level <= 0 or level >= levels.size():
		return {}
	var row = levels[level]
	return (row as Dictionary).duplicate() if row is Dictionary else {}


## Modificadores de un nivel de Dupe listos para StatBlock.add_mod. kind: "mult"
## (relativo a la base) salvo para las probabilidades (critico/esquiva), que son flat.
func dupe_mods_for_level(level: int) -> Array:
	var out: Array = []
	var bonus := dupe_bonus_for_level(level)
	for stat in bonus.keys():
		var stat_name := String(stat)
		if not StatBlock.LABELS.has(stat_name):
			continue
		out.append({
			"stat": stat_name,
			"kind": "flat" if StatBlock.is_rate_stat(stat_name) else "mult",
			"value": float(bonus[stat]),
			"source": "dupe",
		})
	return out


func dupe_mods_for(id: String) -> Array:
	return dupe_mods_for_level(dupe_level_of(id))


## Informe de la siguiente mejora, siempre con el mismo formato:
## { ok, reason, level, max_level, next_level, cost, copies, preview: [ {stat, label,
##   current, next} ] }. La vista previa sale del MISMO calculo que el combate.
func dupe_status(id: String) -> Dictionary:
	var key := String(id)
	var level := dupe_level_of(key)
	var report := {
		"ok": false, "reason": "", "id": key, "level": level, "max_level": dupe_max_level(),
		"next_level": mini(level + 1, dupe_max_level()), "cost": dupe_next_cost(key),
		"copies": dupe_copies_available(key), "preview": [],
	}
	if DB.get_character(key).is_empty() or not is_owned(key):
		report["reason"] = "Todavia no tienes a ese personaje."
		return report
	if dupe_max_level() <= 0:
		report["reason"] = "El sistema de Dupes no esta disponible."
		return report
	if level >= dupe_max_level():
		report["reason"] = "Dupe maximo alcanzado (Dupe %d)." % dupe_max_level()
		return report
	report["preview"] = dupe_stat_preview(key, level, level + 1)
	if int(report["copies"]) < int(report["cost"]):
		report["reason"] = "Faltan copias: necesitas %d y tienes %d." % [int(report["cost"]), int(report["copies"])]
		return report
	report["ok"] = true
	report["reason"] = "Listo para mejorar a Dupe %d." % (level + 1)
	return report


## Estadisticas de la unidad (a su nivel y rareza actuales) con el Dupe `from_level` y
## con el `to_level`. Mismo StatBlock que usa el combate: nada calculado aparte.
func dupe_stat_preview(id: String, from_level: int, to_level: int) -> Array:
	var rows: Array = []
	var data := character_data(String(id))
	if data.is_empty():
		return rows
	var blocks: Array = []
	for lvl in [from_level, to_level]:
		var block := StatBlock.new(data.get("stats", {}), int(data.get("level", 1)))
		block.set_rarity_multiplier(float(data.get("stat_multiplier", 1.0)))
		for mod in dupe_mods_for_level(int(lvl)):
			block.add_mod(String(mod["stat"]), String(mod["kind"]), float(mod["value"]), String(mod["source"]))
		blocks.append(block)
	for stat in ["max_hp", "atk", "def", "speed", "crit_rate", "dodge_rate"]:
		rows.append({
			"stat": stat,
			"label": StatBlock.label(stat),
			"base": (blocks[0] as StatBlock).base_value(stat),
			"current": (blocks[0] as StatBlock).get_stat(stat),
			"next": (blocks[1] as StatBlock).get_stat(stat),
		})
	return rows


## Consume copias y sube un nivel de Dupe. ATOMICA: valida todo primero y solo
## entonces cambia el estado (un nivel y un guardado), asi un error no deja nada a
## medias y una segunda llamada sin copias no hace nada. Devuelve el informe.
func dupe_upgrade(id: String) -> Dictionary:
	var key := String(id)
	var check := dupe_status(key)
	if not bool(check["ok"]):
		check["done"] = false
		return check
	dupe_levels[key] = int(check["level"]) + 1
	save_game()
	var after := dupe_status(key)
	after["done"] = true
	after["spent"] = int(check["cost"])
	after["reached"] = int(check["level"]) + 1
	return after


## Monedas que da cada copia SOBRANTE (0 = conversion desactivada en data/dupes/rules.json).
func dupe_overflow_rate() -> int:
	var overflow = DB.dupe_rules.get("overflow", {})
	if not (overflow is Dictionary):
		return 0
	return maxi(0, int((overflow as Dictionary).get("coins_per_copy", 0)))


## Copias sobrantes: SOLO existen cuando el personaje ya esta en el Dupe maximo (antes,
## toda copia disponible sirve para mejorar). Ningun otro personaje las puede usar.
func dupe_overflow_copies(id: String) -> int:
	var key := String(id)
	if not is_owned(key) or dupe_max_level() <= 0 or dupe_level_of(key) < dupe_max_level():
		return 0
	return dupe_copies_available(key)


## Convierte TODAS las copias sobrantes de ESE personaje en monedas. Atomica: valida, y
## solo entonces resta las copias, suma las monedas y guarda (un unico guardado). Nunca
## toca copias ya gastadas ni las de otros personajes. Devuelve { done, reason, copies, coins }.
func dupe_convert_overflow(id: String) -> Dictionary:
	var key := String(id)
	var copies := dupe_overflow_copies(key)
	var rate := dupe_overflow_rate()
	var report := { "done": false, "reason": "", "id": key, "copies": copies, "coins": copies * rate }
	if rate <= 0:
		report["reason"] = "La conversion de copias sobrantes no esta disponible."
		return report
	if copies <= 0:
		report["reason"] = "No hay copias sobrantes."
		return report
	duplicates[key] = duplicates_of(key) - copies
	add_coins(copies * rate)
	save_game()
	report["done"] = true
	report["reason"] = "Copias convertidas."
	return report


## Aplica el Dupe a un StatBlock (una vez por unidad, con origen "dupe").
func apply_dupe_mods(stat_block, id: String) -> void:
	if stat_block == null:
		return
	for mod in dupe_mods_for(id):
		stat_block.add_mod(String(mod["stat"]), String(mod["kind"]), float(mod["value"]), String(mod["source"]))

## --- Inventario -------------------------------------------------------------

## Cuantos ejemplares de un objeto tiene el jugador. Un objeto que no esta en el
## diccionario son cero unidades: no se guardan ceros.
func item_count(item_id: String) -> int:
	return maxi(0, int(inventory.get(String(item_id), 0)))


func has_item(item_id: String, amount: int = 1) -> bool:
	return item_count(item_id) >= maxi(0, amount)


## Suma objetos al inventario. El nombre y el icono del objeto salen de su JSON
## (res://data/items/<id>.json), no del guardado. Devuelve el informe para que la
## pantalla lo anuncie.
func add_item(item_id: String, amount: int = 1) -> Dictionary:
	var key := String(item_id)
	if amount <= 0:
		return { "id": key, "added": 0, "count": item_count(key), "known": DB.items.has(key) }
	inventory[key] = item_count(key) + amount
	add_counter("objetos_obtenidos", amount)
	save_game()
	return {
		"id": key,
		"name": item_display_name(key),
		"added": amount,
		"count": item_count(key),
		"known": DB.items.has(key),
	}


## Quita objetos del inventario. NUNCA deja la cantidad en negativo: si no hay
## suficientes, no quita nada y devuelve false. Un objeto que llega a cero sale
## del diccionario, asi que el guardado no guarda ceros.
func remove_item(item_id: String, amount: int = 1) -> bool:
	var key := String(item_id)
	if amount <= 0:
		return true
	var current := item_count(key)
	if current < amount:
		return false
	var left := current - amount
	if left <= 0:
		inventory.erase(key)
	else:
		inventory[key] = left
	save_game()
	return true


## Nombre visible de un objeto del catalogo. Tolerante: un objeto sin JSON (o con
## el JSON borrado) devuelve su id en lugar de reventar la pantalla.
func item_display_name(item_id: String) -> String:
	var key := String(item_id)
	var data: Dictionary = DB.items.get(key, {})
	return String(data.get("name", key))


## Inventario listo para pintar: catálogo + cantidad, en orden de id. Sale del
## guardado (cantidad) y del catalogo (el resto), asi que anadir un objeto es
## crear su JSON y nada mas.
func inventory_data() -> Array:
	var out: Array = []
	var ids: Array = inventory.keys()
	ids.sort()
	for raw_id in ids:
		var key := String(raw_id)
		var count := item_count(key)
		if count <= 0:
			continue
		out.append(item_data(key, count))
	return out


## Un objeto del inventario con su catalogo resuelto. Un objeto sin JSON aparece
## igual, marcado como "defined": false, en lugar de desaparecer.
func item_data(item_id: String, count: int = -1) -> Dictionary:
	var key := String(item_id)
	var data: Dictionary = DB.items.get(key, {})
	var icon := String(data.get("icon", ""))
	if icon.is_empty():
		icon = "res://art/items/%s.png" % key
	return {
		"id": key,
		"name": String(data.get("name", key)),
		"description": String(data.get("description", "")),
		"type": String(data.get("type", "")),
		"rarity": String(data.get("rarity", "")),
		"usable": bool(data.get("usable", false)),
		"icon": icon,
		"count": count if count >= 0 else item_count(key),
		"defined": not data.is_empty(),
	}


func inventory_total() -> int:
	var total := 0
	for key in inventory.keys():
		total += item_count(String(key))
	return total


## --- Mutaciones -------------------------------------------------------------

## La mutacion activa de un personaje, o {} si no tiene ninguna. Una sola por
## personaje: una tirada nueva sustituye a la anterior.
func mutation_of(id: String) -> Dictionary:
	var entry = mutations.get(String(id), {})
	return entry if entry is Dictionary else {}


func has_mutation(id: String) -> bool:
	return not mutation_of(id).is_empty()


## Origen con el que la mutacion entra en core/stat_block.gd. Es propio (lleva el
## rango), asi que reaplicarla SUSTITUYE en lugar de acumular y una mutacion
## nueva borra la vieja por origen.
func mutation_source(id: String) -> String:
	var entry := mutation_of(id)
	if entry.is_empty():
		return ""
	var prefix := String(DB.mutation_config().get("source_prefix", "mutation"))
	return "%s:%s" % [prefix, String(entry.get("rank", ""))]


## Modificadores de la mutacion, en el formato que espera StatBlock.add_mod. El
## bonus es RELATIVO A LA BASE (kind "mult"), que es lo que hace que se aplique
## sobre la estadistica base y no sobre el valor ya buffeado.
func mutation_mods_for(id: String) -> Array:
	var out: Array = []
	var entry := mutation_of(id)
	if entry.is_empty():
		return out
	var source := mutation_source(id)
	var kind := String(DB.mutation_config().get("stat_kind", "mult"))
	for raw_stat in entry.get("stats", []):
		if not (raw_stat is Dictionary):
			continue
		out.append({
			"stat": String(raw_stat.get("stat", "")),
			"kind": kind,
			"value": float(raw_stat.get("bonus", 0.0)),
			"source": source,
		})
	return out


## Aplica la mutacion a un StatBlock ya construido. El combate llama a esto una
## vez por unidad, junto a los links: core/stat_block.gd sigue siendo el unico
## sitio que calcula el valor final.
func apply_mutation_mods(stat_block, id: String) -> void:
	if stat_block == null:
		return
	for mod in mutation_mods_for(id):
		stat_block.add_mod(String(mod["stat"]), String(mod["kind"]), float(mod["value"]), String(mod["source"]))


## Puntos de SP que la mutacion le quita a la Super. Solo la mutacion Z lo hace
## (los datos dicen cual y cuanto), y nunca baja del minimo declarado.
func mutation_sp_cost_reduction(id: String) -> int:
	var entry := mutation_of(id)
	if entry.is_empty():
		return 0
	return maxi(0, int(entry.get("sp_reduction", 0)))


## Coste final de una habilidad con la mutacion aplicada: el "cost" de la
## habilidad menos la reduccion, sin bajar nunca del minimo de los datos.
func mutation_sp_cost(id: String, sp_cost: int) -> int:
	var reduction := mutation_sp_cost_reduction(id)
	if reduction <= 0:
		return sp_cost
	var minimum := int(DB.mutation_special().get("sp_cost_min", 1))
	return maxi(minimum, sp_cost - reduction)


## Informe de la mutacion listo para pintar, o {} si el personaje no tiene
## ninguna. Los textos ya vienen resueltos para que la pantalla no calcule nada.
func mutation_report(id: String) -> Dictionary:
	var key := String(id)
	var entry := mutation_of(key)
	if entry.is_empty():
		return {}
	var out: Dictionary = entry.duplicate(true)
	out["id"] = key
	out["name"] = display_name(key)
	out["active"] = true
	out["source"] = mutation_source(key)
	out["sp_cost_reduction"] = mutation_sp_cost_reduction(key)
	out["sp_cost_min"] = int(DB.mutation_special().get("sp_cost_min", 1))
	return out


## Estadisticas BASE de un personaje y como quedan CON su mutacion activa.
## La columna BASE es lo que el personaje vale a su nivel actual, con su forma,
## y SIN nada mas: ni pasivas, ni links, ni lider, ni buffs de combate. Lo unico
## que se aplica encima es la MUTACION, que es lo que esta pantalla explica.
## El valor lo resuelve StatBlock, que sigue siendo el unico sitio que calcula
## una estadistica: aqui solo se pide dos veces, antes y despues.
func mutation_stat_preview(id: String) -> Array:
	var key := String(id)
	var data := character_data(key)
	if data.is_empty():
		return []
	var block: StatBlock = StatBlock.new(data.get("stats", {}), level_of(key))
	block.set_rarity_multiplier(float(data.get("stat_multiplier", 1.0)))
	var before: Dictionary = {}
	for stat_name in StatBlock.LABELS.keys():
		before[stat_name] = block.base_value(stat_name)
	apply_mutation_mods(block, key)
	var out: Array = []
	for stat_name in StatBlock.LABELS.keys():
		var base_value := float(before[stat_name])
		var final_value := block.get_stat(stat_name)
		out.append({
			"stat": stat_name,
			"label": StatBlock.label(stat_name),
			"base": base_value,
			"with_mutation": final_value,
			"changed": absf(final_value - base_value) > 0.0001,
			"is_rate": StatBlock.is_rate_stat(stat_name),
		})
	return out


## Tira una MUTACION para un personaje y la deja activa. Cobra el coste con
## spend_coins: si no llega, NO se cobra nada y no hay tirada. El rango y el
## efecto salen por probabilidad de res://data/mutations/config.json, asi que
## ningun porcentaje esta escrito en el codigo.
## Solo hay una mutacion activa por personaje: la tirada nueva sustituye a la
## anterior (add_mod con origen propio hace el resto cuando se aplique).
## Devuelve el informe para pintar: rango, efecto, estadisticas afectadas con su
## porcentaje y, si es la mutacion Z, la reduccion de SP.
func roll_mutation(id: String) -> Dictionary:
	var key := String(id)
	var cost := DB.mutation_cost()
	var report := {
		"ok": false,
		"reason": "",
		"id": key,
		"name": display_name(key),
		"cost": cost,
		"coins": coins,
		"rank": "",
		"rank_name": "",
		"bonus_percent": 0.0,
		"effect": "",
		"effect_name": "",
		"effect_percent": 0.0,
		"stats": [],
		"replaces": "",
		"sp_reduction": 0,
		"sp_cost_min": int(DB.mutation_special().get("sp_cost_min", 1)),
	}
	if DB.get_character(key).is_empty():
		report["reason"] = "Ese personaje no existe."
		return report
	if not is_owned(key):
		report["reason"] = "Todavia no tienes a ese personaje."
		return report
	var ranks := DB.mutation_ranks()
	var effects := DB.mutation_effects()
	if ranks.is_empty() or effects.is_empty():
		report["reason"] = "El balance de mutaciones no esta cargado."
		return report
	if coins < cost:
		report["reason"] = "Faltan monedas: cuesta %d y tienes %d." % [cost, coins]
		return report
	if not spend_coins(cost):
		report["reason"] = "No se han podido pagar las monedas."
		return report
	var previous := mutation_of(key)
	var rank := _roll_weighted(ranks, "chance_percent")
	var effect := _roll_weighted(effects, "chance_percent")
	if rank.is_empty() or effect.is_empty():
		report["reason"] = "La tirada no ha devuelto nada."
		return report
	var rank_id := String(rank.get("id", ""))
	var bonus_percent := float(rank.get("bonus_percent", 0.0))
	var kind := String(DB.mutation_config().get("stat_kind", "mult"))
	var stats: Array = []
	for raw_stat in effect.get("stats", []):
		var stat_name := String(raw_stat)
		stats.append({
			"stat": stat_name,
			"label": StatBlock.label(stat_name),
			"bonus": bonus_percent / 100.0,
			"bonus_percent": bonus_percent,
			"kind": kind,
			"text": StatBlock.mod_value_text(stat_name, kind, bonus_percent / 100.0),
		})
	var special := DB.mutation_special()
	var sp_reduction := 0
	if rank_id == String(special.get("rank", "")):
		sp_reduction = int(special.get("sp_cost_reduction", 0))
	var sp_minimum := int(special.get("sp_cost_min", 1))
	mutations[key] = {
		"rank": rank_id,
		"rank_name": String(rank.get("name", rank_id)),
		"bonus_percent": bonus_percent,
		"effect": String(effect.get("id", "")),
		"effect_name": String(effect.get("name", "")),
		"effect_percent": float(effect.get("chance_percent", 0.0)),
		"stats": stats,
		"sp_reduction": sp_reduction,
		"sp_cost_min": sp_minimum,
		"source": "%s:%s" % [String(DB.mutation_config().get("source_prefix", "mutation")), rank_id],
	}
	add_counter("mutaciones")
	save_game()
	report["ok"] = true
	report["reason"] = "Mutacion %s aplicada." % rank_id
	report["coins"] = coins
	report["rank"] = rank_id
	report["rank_name"] = String(rank.get("name", rank_id))
	report["bonus_percent"] = bonus_percent
	report["effect"] = String(effect.get("id", ""))
	report["effect_name"] = String(effect.get("name", ""))
	report["effect_percent"] = float(effect.get("chance_percent", 0.0))
	report["stats"] = stats
	report["sp_reduction"] = sp_reduction
	report["sp_cost_min"] = sp_minimum
	report["replaces"] = String(previous.get("rank", "")) if not previous.is_empty() else ""
	report["mutation"] = mutation_report(key)
	return report


## Recorre la mutacion de un personaje por su rango (por si su JSON cambia). Se
## usa al cargar y al evolucionar, para que el bonus y el origen sean los del
## rank que el guardado ya tenia y la mutacion no se pierda.
func _refresh_mutation(key: String) -> void:
	var entry := mutation_of(key)
	if entry.is_empty():
		return
	var rank := DB.mutation_rank(String(entry.get("rank", "")))
	if rank.is_empty():
		return
	var kind := String(DB.mutation_config().get("stat_kind", "mult"))
	var bonus_percent := float(rank.get("bonus_percent", 0.0))
	var stats: Array = []
	for raw_stat in entry.get("stats", []):
		if not (raw_stat is Dictionary):
			continue
		var stat_name := String(raw_stat.get("stat", ""))
		stats.append({
			"stat": stat_name,
			"label": StatBlock.label(stat_name),
			"bonus": bonus_percent / 100.0,
			"bonus_percent": bonus_percent,
			"kind": kind,
			"text": StatBlock.mod_value_text(stat_name, kind, bonus_percent / 100.0),
		})
	if stats.is_empty():
		return
	entry["stats"] = stats
	entry["bonus_percent"] = bonus_percent
	entry["rank_name"] = String(rank.get("name", String(entry.get("rank", ""))))


## Tirada ponderada por el campo indicado. Es el unico sitio que tira una
## probabilidad de mutacion: los numeros vienen del JSON, no del codigo.
func _roll_weighted(entries: Array, chance_key: String) -> Dictionary:
	var total := 0.0
	for entry in entries:
		if entry is Dictionary:
			total += maxf(0.0, float(entry.get(chance_key, 0.0)))
	if total <= 0.0:
		return {}
	var roll := randf() * total
	var accumulated := 0.0
	for entry in entries:
		if not (entry is Dictionary):
			continue
		accumulated += maxf(0.0, float(entry.get(chance_key, 0.0)))
		if roll < accumulated:
			return entry
	for entry in entries:
		if entry is Dictionary:
			return entry
	return {}


## --- Historia: mundos, niveles y dificultades --------------------------------

## Dificultades ya superadas de un nivel de historia, tal cual se guardan.
func story_difficulties_completed(level_id: String) -> Array:
	var entry = story_progress.get(String(level_id), [])
	return entry if entry is Array else []


func story_level_completed(level_id: String, difficulty: String) -> bool:
	return story_difficulties_completed(level_id).has(String(difficulty))


## Un nivel esta superado si lo esta en CUALQUIER dificultad (es lo que desbloquea
## el siguiente nivel del mundo).
func story_level_cleared(level_id: String) -> bool:
	return not story_difficulties_completed(level_id).is_empty()


## El primer nivel de un mundo esta abierto; los demas piden el anterior superado.
## El orden sale de la lista de niveles del mundo, no de un indice escrito aqui.
func story_level_unlocked(level_id: String) -> bool:
	var key := String(level_id)
	var world_id := DB.world_of_level(key)
	if world_id.is_empty():
		return false
	if not world_unlocked(world_id):
		return false
	var levels := DB.story_levels(world_id)
	var index := _level_index(levels, key)
	if index <= 0:
		return true
	var previous = levels[index - 1]
	if not (previous is Dictionary):
		return false
	return story_level_cleared(String((previous as Dictionary).get("id", "")))


func _level_index(levels: Array, level_id: String) -> int:
	for i in range(levels.size()):
		var level = levels[i]
		if level is Dictionary and String(level.get("id", "")) == level_id:
			return i
	return -1


## Elige el mundo de HISTORIA. Solo apunta cual es: el mapa lo lee al abrirse y
## asi volver a entrar devuelve al jugador al mundo donde estaba.
func select_world(new_id: String) -> void:
	var world := DB.get_world(String(new_id))
	if world.is_empty():
		return
	current_world_id = String(new_id)
	save_game()


## Un mundo se desbloquea con SUS DATOS: el bloque "unlock" de su JSON dice de que
## mundo depende y cuantos niveles hay que haber superado. No hay ninguna rama
## del tipo "si el mundo es el numero 1".
func world_unlocked(world_id: String) -> bool:
	var world := DB.get_world(String(world_id))
	if world.is_empty():
		return false
	var unlock = world.get("unlock", {})
	if not (unlock is Dictionary) or (unlock as Dictionary).is_empty():
		return true
	var requires_world := String((unlock as Dictionary).get("requires_world", ""))
	if requires_world.is_empty():
		return true
	if not DB.worlds.has(requires_world):
		return false
	return world_completed_levels(requires_world) >= int((unlock as Dictionary).get("requires_levels_completed", 0))


## Niveles de un mundo superados en alguna dificultad.
func world_completed_levels(world_id: String) -> int:
	var done := 0
	for level in DB.story_levels(String(world_id)):
		if level is Dictionary and story_level_cleared(String(level.get("id", ""))):
			done += 1
	return done


## Niveles de un mundo: cuantos hay y cuantos estan superados, para el mapa.
func world_status(world_id: String) -> Dictionary:
	var world := DB.get_world(String(world_id))
	var levels: Array = []
	for level in DB.story_levels(String(world_id)):
		if level is Dictionary:
			levels.append(story_level_status(String(level.get("id", ""))))
	var done := 0
	for entry in levels:
		if bool(entry.get("cleared", false)):
			done += 1
	return {
		"id": String(world.get("id", world_id)),
		"name": String(world.get("name", world_id)),
		"description": String(world.get("description", "")),
		"background": String(world.get("background", "")),
		"position": world.get("position", {}),
		"unlock": world.get("unlock", {}),
		"unlocked": world_unlocked(String(world_id)),
		"levels": levels,
		"level_count": levels.size(),
		"levels_completed": done,
	}


## Un nivel de historia con sus tres dificultades resueltas para pintar. Cada
## dificultad dice si esta superada y si ya ha pagado su recompensa.
func story_level_status(level_id: String) -> Dictionary:
	var key := String(level_id)
	var world_id := DB.world_of_level(key)
	var level := DB.world_level(world_id, key)
	var difficulties: Array = []
	var completed_count := 0
	for difficulty in DB.difficulties_of_level(level):
		var difficulty_id := String(difficulty.get("id", ""))
		var done := story_level_completed(key, difficulty_id)
		if done:
			completed_count += 1
		difficulties.append({
			"id": difficulty_id,
			"name": String(difficulty.get("name", difficulty_id.to_upper())),
			"order": int(difficulty.get("order", 0)),
			"completed": done,
			"enemies": difficulty.get("enemies", []),
			"xp_reward": int(difficulty.get("xp_reward", 0)),
			"coin_reward": int(difficulty.get("coin_reward", 0)),
			"level_required": int(difficulty.get("level_required", 0)),
		})
	return {
		"id": key,
		"world_id": world_id,
		"name": String(level.get("name", key)),
		"position": level.get("position", {}),
		"next": String(level.get("next", "")),
		"background": String(level.get("background", "")),
		"dialogue": String(level.get("dialogue", "")),
		"unlocked": story_level_unlocked(key),
		"cleared": story_level_cleared(key),
		"difficulties": difficulties,
		"difficulties_completed": completed_count,
	}


## Cierra un nivel de historia en una dificultad. REGLA DE ORO: una dificultad se
## paga UNA vez, y completar la dificultad de orden N completa y paga tambien
## todas las de orden MENOR. Por eso superar EXTREMO marca y entrega NORMAL,
## DIFICIL y EXTREMO de golpe (si alguna ya estaba hecha, no se repite).
## El orden sale del campo "order" de cada dificultad en el JSON.
## Devuelve el informe: que dificultades se han pagado ahora, XP, monedas y la
## lista de niveles que se acaban de desbloquear.
func complete_story_level(level_id: String, difficulty: String, ally_ids: Array = []) -> Dictionary:
	var key := String(level_id)
	var difficulty_id := String(difficulty)
	var world_id := DB.world_of_level(key)
	var report := {
		"ok": false,
		"reason": "",
		"level_id": key,
		"level_name": "",
		"world_id": world_id,
		"difficulty": difficulty_id,
		"already": false,
		"completed": [],
		"xp": 0,
		"coins": 0,
		"characters": [],
		"unlocked": [],
	}
	var level := DB.world_level(world_id, key)
	if level.is_empty():
		report["reason"] = "Ese nivel de historia no existe."
		return report
	report["level_name"] = String(level.get("name", key))
	var entry := DB.difficulty_of_level(level, difficulty_id)
	if entry.is_empty():
		report["reason"] = "Ese nivel no tiene la dificultad '%s'." % difficulty_id
		return report
	if story_level_completed(key, difficulty_id):
		report["ok"] = true
		report["already"] = true
		report["reason"] = "Esa dificultad ya estaba superada y pagada."
		return report
	var was_cleared := story_level_cleared(key)
	var target_order := DB.difficulty_order_of(difficulty_id, entry)
	var completed: Array = []
	var coins_earned := 0
	var xp_earned := 0
	# De menos a mas: completar la dificultad de orden N arrastra todas las de
	# orden menor, y cada una solo se paga si no estaba ya pagada.
	for difficulty_entry in DB.difficulties_of_level(level):
		if int(difficulty_entry.get("order", 0)) > target_order:
			continue
		var other_id := String(difficulty_entry.get("id", ""))
		if story_level_completed(key, other_id):
			continue
		_mark_story_difficulty(key, other_id)
		completed.append(other_id)
		coins_earned += int(difficulty_entry.get("coin_reward", 0))
		xp_earned += int(difficulty_entry.get("xp_reward", 0))
	add_coins(coins_earned)
	add_counter("historia_niveles")
	var character_report: Array = []
	if not was_cleared:
		character_report = _grant_story_xp(ally_ids, xp_earned)
	report["ok"] = true
	report["reason"] = "Nivel superado en %s." % difficulty_id
	report["completed"] = completed
	report["coins"] = coins_earned
	report["xp"] = xp_earned
	report["characters"] = character_report
	report["unlocked"] = _newly_unlocked_levels(key)
	save_game()
	return report


func _mark_story_difficulty(level_id: String, difficulty: String) -> void:
	var key := String(level_id)
	var list: Array = story_difficulties_completed(key)
	if not list.has(String(difficulty)):
		list.append(String(difficulty))
	story_progress[key] = list


## Reparte la XP de un nivel de historia entre los personajes que han combatido,
## con el MISMO add_xp de la ficha y del combate: no hay una segunda curva.
func _grant_story_xp(ally_ids: Array, xp: int) -> Array:
	var out: Array = []
	if xp <= 0:
		return out
	for raw_id in ally_ids:
		var id := String(raw_id)
		if not progress.has(id):
			continue
		var before := level_of(id)
		add_xp(id, xp)
		out.append({
			"id": id,
			"name": display_name(id),
			"level_before": before,
			"level_after": level_of(id),
			"xp": xp,
		})
	return out


## Niveles que se acaban de desbloquear al superar "level_id": sus vecinos que
## ahora cumplen las condiciones. La pantalla de resultado los anuncia.
func _newly_unlocked_levels(level_id: String) -> Array:
	var world_id := DB.world_of_level(level_id)
	var levels := DB.story_levels(world_id)
	var index := _level_index(levels, level_id)
	var out: Array = []
	if index >= 0 and index + 1 < levels.size():
		var next_level = levels[index + 1]
		if next_level is Dictionary:
			var next_id := String((next_level as Dictionary).get("id", ""))
			if story_level_unlocked(next_id):
				out.append(next_id)
	var next_world := next_world_id(world_id)
	if not next_world.is_empty() and world_unlocked(next_world):
		out.append(next_world)
	return out


## Mundo que va DESPUES de un mundo, leido de los datos: el primero que lo pide
## en su "unlock". Anadir un mundo nuevo es crear su JSON.
func next_world_id(world_id: String) -> String:
	for world in DB.all_worlds():
		var unlock = world.get("unlock", {})
		if unlock is Dictionary and String((unlock as Dictionary).get("requires_world", "")) == String(world_id):
			return String(world.get("id", ""))
	return ""


## --- Eventos: stages, recompensa de personaje y contador ---------------------

## Progreso guardado de un evento, creado vacio si es la primera vez.
func event_state(event_id: String) -> Dictionary:
	var key := String(event_id)
	var entry = event_progress.get(key, null)
	if not (entry is Dictionary):
		entry = _empty_event_state()
		event_progress[key] = entry
	return entry


func _empty_event_state() -> Dictionary:
	return { "stages": {}, "rewards_claimed": {}, "times_completed": 0 }


func event_stage_completed(event_id: String, stage_id: String) -> bool:
	var entry = event_state(event_id)["stages"].get(String(stage_id), {})
	return bool((entry as Dictionary).get("completed", false)) if entry is Dictionary else false


## Cuantas veces se ha superado un stage (el evento se puede repetir por objetos).
func event_stage_clears(event_id: String, stage_id: String) -> int:
	var entry = event_state(event_id)["stages"].get(String(stage_id), {})
	return int((entry as Dictionary).get("clears", 0)) if entry is Dictionary else 0


## El primer stage de un evento esta abierto; los demas piden el anterior
## superado. El orden sale de la lista de stages del evento.
func event_stage_unlocked(event_id: String, stage_id: String) -> bool:
	var stages := DB.event_stages(String(event_id))
	var index := -1
	for i in range(stages.size()):
		var stage = stages[i]
		if stage is Dictionary and String((stage as Dictionary).get("id", "")) == String(stage_id):
			index = i
			break
	if index <= 0:
		return index == 0
	var previous = stages[index - 1]
	if not (previous is Dictionary):
		return false
	var previous_id := String((previous as Dictionary).get("id", ""))
	return event_stage_completed(String(event_id), previous_id)


func event_cleared_count(event_id: String) -> int:
	var done := 0
	for stage in DB.event_stages(String(event_id)):
		if stage is Dictionary and event_stage_completed(String(event_id), String((stage as Dictionary).get("id", ""))):
			done += 1
	return done


func event_completed(event_id: String) -> bool:
	var total := DB.event_stages(String(event_id)).size()
	return total > 0 and event_cleared_count(String(event_id)) >= total


func event_times_completed(event_id: String) -> int:
	return int(event_state(event_id).get("times_completed", 0))


func event_reward_claimed(event_id: String, reward_id: String) -> bool:
	var claimed = event_state(event_id)["rewards_claimed"]
	return bool((claimed as Dictionary).get(String(reward_id), false)) if claimed is Dictionary else false


## El personaje que entrega el evento ya esta en el roster? Se consulta por la
## recompensa declarada en el JSON del evento, no por un id escrito en el codigo.
func event_character_claimed(event_id: String) -> bool:
	var reward := String(DB.get_event(String(event_id)).get("character_reward", ""))
	if reward.is_empty():
		return false
	return event_reward_claimed(String(event_id), reward)


## Puede el equipo entrar a un stage del evento? TODO sale del JSON del stage, sin
## ninguna rama por personaje:
##   requires_party_character -> esa unidad tiene que estar en el equipo.
##   requires_party_rarity    -> y ademas en ESA forma (la rareza efectiva del
##                               jugador, que es lo que distingue SSR de UR).
##   requires_party_solo      -> el equipo entero es esa unidad y nadie mas.
##   requires_party_size      -> el equipo tiene exactamente N unidades.
## Un stage sin ninguno de estos campos no pone ninguna condicion.
func event_party_ready(event_id: String, stage_id: String, ally_ids: Array) -> Dictionary:
	var stage := DB.event_stage(String(event_id), String(stage_id))
	var required := String(stage.get("requires_party_character", ""))
	var wanted_rarity := String(stage.get("requires_party_rarity", ""))
	var solo := bool(stage.get("requires_party_solo", false))
	var wanted_size := 1 if solo else int(stage.get("requires_party_size", 0))
	# El equipo sin huecos vacios: una casilla libre no es un personaje.
	var party: Array = []
	for raw_id in ally_ids:
		var key := String(raw_id)
		if not key.is_empty():
			party.append(key)
	var report := {
		"ok": true,
		"required": required,
		"required_rarity": wanted_rarity,
		"party_size": party.size(),
		"required_size": wanted_size,
		"reason": "",
	}
	# 1) Tamano exacto del equipo (es lo que convierte el combate en un 1 VS 1).
	if wanted_size > 0 and party.size() != wanted_size:
		report["ok"] = false
		if solo:
			report["reason"] = "Este combate es 1 contra 1: lleva SOLO a %s, sin companeros (ahora llevas %d)." % [
				display_name(required) if not required.is_empty() else "la unidad requerida", party.size()]
		else:
			report["reason"] = "Este combate pide un equipo de %d unidades (ahora llevas %d)." % [wanted_size, party.size()]
		return report
	# 2) La unidad requerida tiene que estar.
	if not required.is_empty() and not party.has(required):
		report["ok"] = false
		report["reason"] = "Ese combate lo tiene que pelear %s: anadelo al equipo." % display_name(required)
		return report
	# 3) Y en la forma concreta: la rareza EFECTIVA tiene que ser la que pide el
	#    stage. Asi un SSR sin evolucionar no vale donde se pide el UR.
	if not required.is_empty() and not wanted_rarity.is_empty():
		var current := rarity_of(required)
		if current != wanted_rarity:
			report["ok"] = false
			report["reason"] = "Este combate pide a %s en su forma %s (ahora esta en %s)." % [
				display_name(required), wanted_rarity, current if not current.is_empty() else "?"]
			return report
	return report


## Nombre legible de la condicion de equipo de un stage, para que la pantalla la
## ensene sin conocer las claves del JSON. Devuelve "" si el stage no pide nada.
func event_party_requirement_text(event_id: String, stage_id: String) -> String:
	var stage := DB.event_stage(String(event_id), String(stage_id))
	var required := String(stage.get("requires_party_character", ""))
	var wanted_rarity := String(stage.get("requires_party_rarity", ""))
	var solo := bool(stage.get("requires_party_solo", false))
	var wanted_size := 1 if solo else int(stage.get("requires_party_size", 0))
	var parts := PackedStringArray()
	if solo:
		parts.append("Equipo: SOLO %s (1 unidad)" % display_name(required))
	elif wanted_size > 0:
		parts.append("Equipo de %d unidades" % wanted_size)
	if not required.is_empty():
		var name_text := display_name(required)
		if not wanted_rarity.is_empty():
			name_text += " en forma %s" % wanted_rarity
		parts.append("Requiere: %s" % name_text)
	return "   ".join(parts)


## Supera un stage del evento. Marca el stage, suma un paseo, tira los objetos
## que suelta (min/max del JSON) al inventario y, cuando el evento entero queda
## superado, sube su contador de veces completado. La recompensa de personaje NO
## se entrega aqui: la entrega claim_event_character, que solo paga una vez.
func complete_event_stage(event_id: String, stage_id: String, ally_ids: Array = []) -> Dictionary:
	var event_key := String(event_id)
	var stage_key := String(stage_id)
	var stage := DB.event_stage(event_key, stage_key)
	var report := {
		"ok": false,
		"reason": "",
		"event_id": event_key,
		"event_name": String(DB.get_event(event_key).get("name", event_key)),
		"stage_id": stage_key,
		"stage_name": "",
		"xp": 0,
		"coins": 0,
		"drops": [],
		"characters": [],
		"times_completed": 0,
		"event_completed": false,
		"unlocked": [],
	}
	if stage.is_empty():
		report["reason"] = "Ese stage del evento no existe."
		return report
	report["stage_name"] = String(stage.get("name", stage_key))
	var gate := event_party_ready(event_key, stage_key, ally_ids)
	if not bool(gate["ok"]):
		report["reason"] = String(gate["reason"])
		return report
	var already := event_stage_completed(event_key, stage_key)
	var xp := int(stage.get("xp_reward", 0))
	var coins_earned := int(stage.get("coin_reward", 0))
	var drops := _roll_drops(stage.get("drops", []))
	if not already:
		add_counter("combates_jugados")
		add_counter("victorias")
	add_coins(coins_earned)
	var character_report: Array = []
	if not already:
		character_report = _grant_story_xp(ally_ids, xp)
	_mark_event_stage(event_key, stage_key)
	report["ok"] = true
	report["reason"] = "Stage superado." if already else "Stage superado por primera vez."
	report["xp"] = xp if not already else 0
	report["coins"] = coins_earned
	report["drops"] = drops
	report["characters"] = character_report
	var total := DB.event_stages(event_key).size()
	if event_completed(event_key):
		var state := event_state(event_key)
		state["times_completed"] = int(state.get("times_completed", 0)) + 1
		var counter := String(DB.get_event(event_key).get("counter", "eventos_completados"))
		if not counter.is_empty():
			add_counter(counter)
		report["event_completed"] = true
		report["counter"] = counter
		report["counter_value"] = counter_value(counter)
	report["times_completed"] = event_times_completed(event_key)
	var stages := DB.event_stages(event_key)
	for i in range(stages.size()):
		var entry = stages[i]
		if not (entry is Dictionary):
			continue
		if String((entry as Dictionary).get("id", "")) == stage_key and i + 1 < stages.size():
			var next_entry = stages[i + 1]
			if next_entry is Dictionary:
				var next_id := String((next_entry as Dictionary).get("id", ""))
				if event_stage_unlocked(event_key, next_id):
					report["unlocked"].append(next_id)
	save_game()
	return report


func _mark_event_stage(event_id: String, stage_id: String) -> void:
	var state := event_state(event_id)
	var stages: Dictionary = state["stages"]
	var entry = stages.get(stage_id, {})
	if not (entry is Dictionary):
		entry = {}
	(entry as Dictionary)["completed"] = true
	(entry as Dictionary)["clears"] = int((entry as Dictionary).get("clears", 0)) + 1
	stages[stage_id] = entry
	state["stages"] = stages


## Tira los objetos que suelta un stage. Cada drop dice "item", "min" y "max": el
## rango vive en el JSON del evento, no en el codigo.
func _roll_drops(drops: Variant) -> Array:
	var out: Array = []
	if not (drops is Array):
		return out
	for drop in drops:
		if not (drop is Dictionary):
			continue
		var item_id := String((drop as Dictionary).get("item", ""))
		if item_id.is_empty():
			continue
		var low := int((drop as Dictionary).get("min", 1))
		var high := int((drop as Dictionary).get("max", low))
		if high < low:
			high = low
		var amount := randi_range(low, high) if high > low else low
		if amount <= 0:
			continue
		var info := add_item(item_id, amount)
		out.append({
			"item": item_id,
			"name": item_display_name(item_id),
			"amount": amount,
			"count": int(info.get("count", item_count(item_id))),
		})
	return out


## Stage del evento que ENTREGA un personaje: el que declara "grant_character"
## con ese id en su JSON. Devuelve "" si ningun stage lo entrega, que significa
## que la recompensa no esta atada a ningun combate.
func event_reward_stage(event_id: String, reward_id: String) -> String:
	for stage in DB.event_stages(String(event_id)):
		if not (stage is Dictionary):
			continue
		if String((stage as Dictionary).get("grant_character", "")) == String(reward_id):
			return String((stage as Dictionary).get("id", ""))
	return ""


## Se puede reclamar YA el personaje de un evento? La recompensa esta atada al
## stage que la declara: hasta que ESE stage no este superado de verdad (progreso
## persistente, no que el personaje exista en los datos) no se entrega nada.
## Devuelve { ok, reason, reward, stage_id, stage_name }.
func event_reward_ready(event_id: String) -> Dictionary:
	var event_key := String(event_id)
	var reward := String(DB.get_event(event_key).get("character_reward", ""))
	var out := { "ok": false, "reason": "", "reward": reward, "stage_id": "", "stage_name": "" }
	if reward.is_empty():
		out["reason"] = "Este evento no entrega ningun personaje."
		return out
	if event_reward_claimed(event_key, reward):
		out["ok"] = true
		out["reason"] = "Ese personaje ya se entrego."
		return out
	var stage_id := event_reward_stage(event_key, reward)
	out["stage_id"] = stage_id
	if stage_id.is_empty():
		# La recompensa no depende de ningun stage: se puede reclamar.
		out["ok"] = true
		return out
	var stage := DB.event_stage(event_key, stage_id)
	out["stage_name"] = String(stage.get("name", stage_id))
	if not event_stage_completed(event_key, stage_id):
		out["reason"] = "Supera antes '%s' para poder reclamar a %s." % [out["stage_name"], display_name(reward)]
		return out
	out["ok"] = true
	return out


## Entrega la unidad que da un evento. Solo paga UNA vez y SOLO si el stage que
## la entrega esta superado: sin eso no hay recompensa. A partir de ahi el evento
## se puede repetir por objetos, pero no vuelve a soltar el personaje.
func claim_event_character(event_id: String) -> Dictionary:
	var event_key := String(event_id)
	var reward := String(DB.get_event(event_key).get("character_reward", ""))
	if reward.is_empty():
		return { "ok": false, "reason": "Este evento no entrega ningun personaje.", "id": "" }
	# El progreso REAL manda: si el stage que la entrega no esta superado, no se
	# reclama nada. Antes bastaba con pulsar el boton, que era el bug.
	var ready := event_reward_ready(event_key)
	if not bool(ready.get("ok", false)):
		return {
			"ok": false,
			"blocked": true,
			"id": reward,
			"name": display_name(reward),
			"reason": String(ready.get("reason", "")),
		}
	if event_reward_claimed(event_key, reward):
		return {
			"ok": true,
			"already": true,
			"id": reward,
			"name": display_name(reward),
			"reason": "Ese personaje ya se entrego.",
		}
	var info := add_character(reward)
	var claimed: Dictionary = event_state(event_key)["rewards_claimed"]
	claimed[reward] = true
	event_state(event_key)["rewards_claimed"] = claimed
	save_game()
	return {
		"ok": true,
		"already": false,
		"id": reward,
		"name": display_name(reward),
		"duplicate": bool(info.get("duplicate", false)),
		"reason": "Personaje entregado." if not bool(info.get("duplicate", false)) else "Ya lo tenias: se ha sumado un duplicado.",
	}


## Estado de un evento listo para pintar: sus stages, que esta superado, la
## recompensa de personaje y el contador de veces completado.
func event_status(event_id: String) -> Dictionary:
	var event_key := String(event_id)
	var event := DB.get_event(event_key)
	var counter := String(event.get("counter", "eventos_completados"))
	# Estado de la recompensa de personaje (si depende de un stage, si ya se
	# puede reclamar y por que no). Lo calcula GameState, no la pantalla.
	var reward_state: Dictionary = event_reward_ready(event_key)
	var stages: Array = []
	for stage in DB.event_stages(event_key):
		if not (stage is Dictionary):
			continue
		var stage_id := String((stage as Dictionary).get("id", ""))
		stages.append({
			"id": stage_id,
			"name": String((stage as Dictionary).get("name", stage_id)),
			"position": (stage as Dictionary).get("position", {}),
			"background": String((stage as Dictionary).get("background", "")),
			"dialogue": String((stage as Dictionary).get("dialogue", "")),
			"difficulty": String((stage as Dictionary).get("difficulty", "NORMAL")),
			"enemies": (stage as Dictionary).get("enemies", []),
			"xp_reward": int((stage as Dictionary).get("xp_reward", 0)),
			"coin_reward": int((stage as Dictionary).get("coin_reward", 0)),
			"drops": (stage as Dictionary).get("drops", []),
			"requires_party_character": String((stage as Dictionary).get("requires_party_character", "")),
			"completed": event_stage_completed(event_key, stage_id),
			"clears": event_stage_clears(event_key, stage_id),
			"unlocked": event_stage_unlocked(event_key, stage_id),
		})
	return {
		"id": event_key,
		"name": String(event.get("name", event_key)),
		"description": String(event.get("description", "")),
		"background": String(event.get("background", "")),
		"stages": stages,
		"stage_count": stages.size(),
		"stages_completed": event_cleared_count(event_key),
		"completed": event_completed(event_key),
		"times_completed": event_times_completed(event_key),
		"counter": counter,
		"counter_value": counter_value(counter),
		"character_reward": String(event.get("character_reward", "")),
		"character_claimed": event_character_claimed(event_key),
		# Si la recompensa esta atada a un stage, estos tres campos dicen de cual
		# se trata y si ya se puede reclamar: la pantalla no calcula ninguna regla.
		"character_stage": String(reward_state.get("stage_id", "")),
		"character_stage_name": String(reward_state.get("stage_name", "")),
		"character_ready": bool(reward_state.get("ok", false)),
		"character_reason": String(reward_state.get("reason", "")),
	}


## --- Links del equipo -------------------------------------------------------

## Un link esta ACTIVO cuando al menos DOS personajes del EQUIPO lo comparten: un
## link con un solo portador no da bonus. Se mira el equipo (party) y no el
## roster, porque el bonus es de la formacion que combate.
func active_link_ids() -> Array:
	var counts := _link_counts()
	var out: Array = []
	for link_id in counts.keys():
		if int(counts[link_id]) >= LINK_MIN_HOLDERS:
			out.append(String(link_id))
	out.sort()
	return out


func is_link_active(link_id: String) -> bool:
	return active_link_ids().has(String(link_id))


## Cuantos personajes del equipo llevan un link (base + los que aporta la
## evolucion de cada uno). Es el dato que decide si el link se activa.
func link_holder_count(link_id: String) -> int:
	return int(_link_counts().get(String(link_id), 0))


func _link_counts() -> Dictionary:
	var counts: Dictionary = {}
	for id in _lead_party():
		var key := String(id)
		if key.is_empty():
			continue
		for link_id in character_data(key).get("links", []):
			var link_key := String(link_id)
			counts[link_key] = int(counts.get(link_key, 0)) + 1
	return counts


## Estado de los links de un personaje, ya resuelto para pintar: la ficha solo
## lee "active" y "holders". No se escribe aqui ninguna logica de pintado.
## Devuelve [{ id, name, description, active, holders, effects }].
func link_status(id: String) -> Array:
	var counts := _link_counts()
	var out: Array = []
	for raw_id in character_data(String(id)).get("links", []):
		var link_id := String(raw_id)
		var link := DB.get_link(link_id)
		var holders := int(counts.get(link_id, 0))
		out.append({
			"id": link_id,
			"name": String(link.get("name", link_id)),
			"description": String(link.get("description", "")),
			"effects": link.get("effects", []),
			"holders": holders,
			"active": holders >= LINK_MIN_HOLDERS,
			"defined": not link.is_empty(),
		})
	return out


## Estado de todos los links que lleva el equipo, activos o no. Es lo que pinta
## la pantalla de equipo para ensenar que sinergias estan encendidas.
func team_links_status() -> Array:
	var counts := _link_counts()
	var out: Array = []
	for link in DB.all_links():
		var link_id := String(link.get("id", ""))
		var holders := int(counts.get(link_id, 0))
		if holders <= 0:
			continue
		out.append({
			"id": link_id,
			"name": String(link.get("name", link_id)),
			"description": String(link.get("description", "")),
			"effects": link.get("effects", []),
			"holders": holders,
			"active": holders >= LINK_MIN_HOLDERS,
			"defined": true,
		})
	out.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	return out


## Modificadores que los links ACTIVOS aportan a un personaje del equipo. Cada uno
## se aplica con StatBlock.add_mod y un origen propio ("link:<id>"), asi que
## core/stat_block.gd sigue siendo el unico sitio que calcula el valor final y
## reaplicar el mismo link lo sustituye en vez de acumularlo.
func link_mods_for(id: String) -> Array:
	var out: Array = []
	for link_id in active_link_ids():
		if not _character_has_link(String(id), link_id):
			continue
		var link := DB.get_link(link_id)
		for effect in link.get("effects", []):
			if not (effect is Dictionary):
				continue
			if String(effect.get("type", "")) != "stat_mod":
				continue
			out.append({
				"stat": String(effect.get("stat", "")),
				"kind": String(effect.get("kind", "mult")),
				"value": float(effect.get("value", 0.0)),
				"source": "link:%s" % link_id,
			})
	return out


## Aplica los links activos a un StatBlock ya construido (core/stat_block.gd).
## El combate llama a esto una vez por aliado al empezar la batalla.
func apply_link_mods(stat_block, id: String) -> void:
	if stat_block == null:
		return
	for mod in link_mods_for(id):
		stat_block.add_mod(String(mod["stat"]), String(mod["kind"]), float(mod["value"]), String(mod["source"]))


func _character_has_link(id: String, link_id: String) -> bool:
	for raw_id in character_data(id).get("links", []):
		if String(raw_id) == String(link_id):
			return true
	return false


## --- Leader Skills -----------------------------------------------------------
## Solo funciona la Leader Skill del personaje que ocupa la POSICION 1 del equipo.
## A quien afecta lo dice su "condition" (todo el equipo, un tipo o una categoria)
## y el efecto entra en las estadisticas de esos aliados al empezar la batalla,
## igual que un link. Todo sale de res://data/leaders/leaders.json: aqui no hay
## ninguna rama por personaje.

## LA POSICION DEL LIDER: la 1 (indice 0). Es la UNICA fuente de verdad de la
## Leader Skill, y no es una busqueda: si la posicion 0 esta vacia, NO hay lider
## aunque las posiciones 2, 3 o 4 esten ocupadas. No existe ningun caso especial
## que "promocione" a otro personaje.
const LEADER_SLOT := 0


## Id del personaje que ocupa la POSICION 1, o "" si esa posicion esta vacia.
func party_leader_id() -> String:
	var lead := _lead_party()
	if lead.size() <= LEADER_SLOT:
		return ""
	return String(lead[LEADER_SLOT])


## Leader Skill del equipo, ya resuelta para pintar. Devuelve {} si no hay equipo
## o si el lider no tiene ninguna definida. Los textos vienen listos para leerse.
func leader_report() -> Dictionary:
	var leader_id := party_leader_id()
	if leader_id.is_empty():
		return {}
	var leader := DB.leader_for(leader_id)
	if leader.is_empty():
		return {}
	var condition = leader.get("condition", {})
	return {
		"character_id": leader_id,
		"character_name": display_name(leader_id),
		"id": String(leader.get("id", "")),
		"name": String(leader.get("name", "")),
		"description": String(leader.get("description", "")),
		"condition": condition if condition is Dictionary else {},
		"effects": leader.get("effects", []),
		"affects": leader_affected_names(),
	}


## Nombres de los personajes del equipo a los que afecta la Leader Skill. Es lo
## que permite ensenar POR QUE un companero recibe el bonus.
func leader_affected_names() -> Array:
	var out: Array = []
	for id in _lead_party():
		var key := String(id)
		if key.is_empty():
			continue
		if leader_affects(key):
			out.append(display_name(key))
	return out


## Afecta la Leader Skill del equipo a este personaje? La condicion es DATO:
##   { field: "all" }            -> todo el equipo
##   { field: "type", value:"INT" }        -> solo ese tipo
##   { field: "category", value:"heroes" } -> solo esa categoria
## Una condicion desconocida no afecta a nadie, que es lo mas seguro.
func leader_affects(id: String) -> bool:
	# Sin nadie en la POSICION 1 no hay Leader Skill, y punto: se corta ANTES de
	# preguntar por el lider. Sin esta guarda, un id vacio acababa resolviendose
	# al lider por defecto y el equipo seguia recibiendo bonus sin lider.
	var leader_id := party_leader_id()
	if leader_id.is_empty():
		return false
	var leader := DB.leader_for(leader_id)
	if leader.is_empty():
		return false
	var condition = leader.get("condition", {})
	if not (condition is Dictionary) or (condition as Dictionary).is_empty():
		return true
	var field := String((condition as Dictionary).get("field", "all"))
	var value := String((condition as Dictionary).get("value", ""))
	var data := character_data(id)
	match field:
		"all":
			return true
		"type":
			return String(data.get("type", "")) == value
		"category":
			for raw_id in data.get("categories", []):
				if String(raw_id) == value:
					return true
			return false
	return false


## Modificadores que la Leader Skill del equipo aporta a un personaje. Cada uno
## lleva el origen "leader:<id>", asi que StatBlock sustituye el mod anterior en
## lugar de acumularlo y el valor final sigue calculandose en un unico sitio.
func leader_mods_for(id: String) -> Array:
	var out: Array = []
	if not leader_affects(id):
		return out
	var leader := DB.leader_for(party_leader_id())
	if leader.is_empty():
		return out
	var leader_id := String(leader.get("id", ""))
	for effect in leader.get("effects", []):
		if not (effect is Dictionary):
			continue
		if String(effect.get("type", "")) != "stat_mod":
			continue
		out.append({
			"stat": String(effect.get("stat", "")),
			"kind": String(effect.get("kind", "mult")),
			"value": float(effect.get("value", 0.0)),
			"source": "leader:%s" % leader_id,
		})
	return out


func apply_leader_mods(stat_block, id: String) -> void:
	if stat_block == null:
		return
	for mod in leader_mods_for(id):
		stat_block.add_mod(String(mod["stat"]), String(mod["kind"]), float(mod["value"]), String(mod["source"]))


## --- Torres ------------------------------------------------------------------
## Una torre es un JSON con sus pisos. El progreso guarda el piso MAS ALTO
## superado y que pisos ya han pagado su premio, asi que volver a subir no paga
## dos veces y perder no borra lo conseguido: se reanuda desde el ultimo
## multiplo de "checkpoint_step" ya superado.

## torre_id -> { best_floor, checkpoint, rewarded: [pisos ya pagados], runs }
var tower_progress: Dictionary = {}


func tower_state(tower_id: String) -> Dictionary:
	var key := String(tower_id)
	var entry = tower_progress.get(key, null)
	if entry is Dictionary:
		return entry
	var fresh := _empty_tower_state()
	tower_progress[key] = fresh
	return tower_progress[key]


func _empty_tower_state() -> Dictionary:
	return { "best_floor": 0, "checkpoint": 0, "rewarded": [], "runs": 0, "run_floor": 0 }


func tower_best_floor(tower_id: String) -> int:
	return int(tower_state(tower_id).get("best_floor", 0))


func tower_checkpoint(tower_id: String) -> int:
	return int(tower_state(tower_id).get("checkpoint", 0))


func tower_floor_rewarded(tower_id: String, floor_number: int) -> bool:
	var rewarded = tower_state(tower_id).get("rewarded", [])
	return rewarded is Array and (rewarded as Array).has(int(floor_number))


func tower_completed(tower_id: String) -> bool:
	return tower_best_floor(tower_id) >= DB.tower_floor_count(tower_id)


## Piso desde el que se reanuda la torre: se conserva lo superado hasta el ultimo
## multiplo del paso de control y se vuelve a empezar justo despues.
func tower_start_floor(tower_id: String) -> int:
	var key := String(tower_id)
	var total := DB.tower_floor_count(key)
	var best := tower_best_floor(key)
	if total <= 0:
		return 1
	if best >= total:
		return total
	var step := maxi(1, int(DB.get_tower(key).get("checkpoint_step", 5)))
	var checkpoint := (best / step) * step
	var next_floor := checkpoint + 1 if best >= checkpoint else best + 1
	return clampi(next_floor, 1, total)


## Piso en el que esta AHORA la subida actual. Al ganar un piso se pasa al
## siguiente; al perder se vuelve al ultimo checkpoint (multiplo del paso) + 1.
func tower_run_floor(tower_id: String) -> int:
	var key := String(tower_id)
	var total := DB.tower_floor_count(key)
	var run := int(tower_state(key).get("run_floor", 0))
	if run <= 0:
		run = tower_start_floor(key)
	return clampi(run, 1, maxi(1, total))


## Derrota en la torre: la subida vuelve al ultimo checkpoint superado + 1. Lo
## conseguido (premios cobrados, mejor piso) NO se pierde.
func tower_register_defeat(tower_id: String) -> Dictionary:
	var key := String(tower_id)
	var state := tower_state(key)
	state["run_floor"] = tower_start_floor(key)
	state["runs"] = int(state.get("runs", 0)) + 1
	save_game()
	return { "run_floor": int(state["run_floor"]), "checkpoint": tower_checkpoint(key) }


## Estado de la torre listo para pintar: cada piso con su nombre, si es jefe, si
## esta superado y si ya ha pagado su premio.
func tower_status(tower_id: String) -> Dictionary:
	var key := String(tower_id)
	var tower := DB.get_tower(key)
	var best := tower_best_floor(key)
	var start := tower_start_floor(key)
	var run := tower_run_floor(key)
	var floors: Array = []
	for raw_floor in DB.tower_floors(key):
		if not (raw_floor is Dictionary):
			continue
		var number := int((raw_floor as Dictionary).get("floor", 0))
		floors.append({
			"floor": number,
			"name": String((raw_floor as Dictionary).get("name", "Piso %d" % number)),
			"boss": bool((raw_floor as Dictionary).get("boss", false)),
			"enemies": (raw_floor as Dictionary).get("enemies", []),
			"xp_reward": int((raw_floor as Dictionary).get("xp_reward", 0)),
			"coin_reward": int((raw_floor as Dictionary).get("coin_reward", 0)),
			"cleared": number <= best,
			"rewarded": tower_floor_rewarded(key, number),
			"current": number == run,
		})
	return {
		"id": key,
		"name": String(tower.get("name", key)),
		"description": String(tower.get("description", "")),
		"background": String(tower.get("background", "")),
		"checkpoint_step": maxi(1, int(tower.get("checkpoint_step", 5))),
		"floor_count": DB.tower_floor_count(key),
		"floors": floors,
		"best_floor": best,
		"checkpoint": tower_checkpoint(key),
		"start_floor": start,
		"run_floor": run,
		"completed": tower_completed(key),
	}


## Supera un piso de torre. El piso mas alto que se ha pisado se apunta SIEMPRE
## (es el avance de la torre); el premio de un piso se paga UNA vez, asi que
## volver a subir no vuelve a dar XP ni monedas. El objeto de "first_clear_item"
## del JSON tambien se cobra la primera vez.
func complete_tower_floor(tower_id: String, floor_number: int, ally_ids: Array = []) -> Dictionary:
	var key := String(tower_id)
	var number := int(floor_number)
	var floor_data := DB.tower_floor(key, number)
	var report := {
		"ok": false,
		"reason": "",
		"tower": key,
		"floor": number,
		"floor_name": "",
		"xp": 0,
		"coins": 0,
		"characters": [],
		"drops": [],
		"first_clear": false,
		"best_floor": tower_best_floor(key),
		"checkpoint": tower_checkpoint(key),
	}
	if floor_data.is_empty():
		report["reason"] = "Ese piso no existe."
		return report
	report["floor_name"] = String(floor_data.get("name", "Piso %d" % number))
	var state := tower_state(key)
	if number > int(state.get("best_floor", 0)):
		state["best_floor"] = number
	var step := maxi(1, int(DB.get_tower(key).get("checkpoint_step", 5)))
	state["checkpoint"] = (int(state["best_floor"]) / step) * step
	var total_floors := DB.tower_floor_count(key)
	if number >= tower_run_floor(key):
		state["run_floor"] = mini(number + 1, maxi(1, total_floors))
	var first_clear := not tower_floor_rewarded(key, number)
	report["ok"] = true
	report["first_clear"] = first_clear
	report["reason"] = "Piso superado." if not first_clear else "Piso superado por primera vez."
	report["best_floor"] = int(state["best_floor"])
	report["checkpoint"] = int(state["checkpoint"])
	if first_clear:
		var rewarded: Array = state.get("rewarded", [])
		rewarded.append(number)
		state["rewarded"] = rewarded
		var xp := int(floor_data.get("xp_reward", 0))
		var coins_earned := int(floor_data.get("coin_reward", 0))
		add_coins(coins_earned)
		report["xp"] = xp
		report["coins"] = coins_earned
		report["characters"] = _grant_story_xp(ally_ids, xp)
		var item_id := String(floor_data.get("first_clear_item", ""))
		if not item_id.is_empty():
			var amount := int(floor_data.get("first_clear_amount", 1))
			report["drops"] = _roll_drops([{ "item": item_id, "min": amount, "max": amount }])
		add_counter("pisos_torre")
	save_game()
	return report


## --- Equipo de TORRE: 5 personajes (3 ACTIVOS + 2 RESERVAS) ------------------
## Es un equipo APARTE del de 4: la torre no toca GameState.party. Las posiciones
## 0..2 combaten; la 3 y la 4 esperan y entran cuando un activo cae. Una posicion
## puede estar vacia, igual que en el equipo normal. Vale cualquier personaje
## que el jugador tenga; ninguna regla por personaje.
const TOWER_ACTIVE := 3
const TOWER_RESERVE := 2
const TOWER_TEAM_SIZE := 5

var tower_team: Array = ["", "", "", "", ""]


func normalize_tower_team() -> void:
	var out: Array = []
	var seen: Dictionary = {}
	for i in TOWER_TEAM_SIZE:
		var key := ""
		if i < tower_team.size():
			key = String(tower_team[i])
		if key.is_empty() or seen.has(key) or not is_owned(key):
			out.append("")
			continue
		seen[key] = true
		out.append(key)
	tower_team = out


## Pone, quita o mueve un personaje en una posicion del equipo de torre. Mismas
## reglas que assign_party_slot: tocar al que ya esta lo quita, y si estaba en
## otra posicion se mueve (nunca aparece dos veces).
func assign_tower_slot(index: int, id: String) -> void:
	if index < 0 or index >= TOWER_TEAM_SIZE:
		return
	if tower_team.size() != TOWER_TEAM_SIZE:
		normalize_tower_team()
	var key := String(id)
	if key.is_empty() or String(tower_team[index]) == key:
		tower_team[index] = ""
		save_game()
		return
	for i in tower_team.size():
		if String(tower_team[i]) == key:
			tower_team[i] = ""
	tower_team[index] = key
	save_game()


func tower_team_count() -> int:
	var total := 0
	for raw_id in tower_team:
		if not String(raw_id).is_empty():
			total += 1
	return total


func tower_active_ids() -> Array:
	var out: Array = []
	for i in mini(TOWER_ACTIVE, tower_team.size()):
		var key := String(tower_team[i])
		if not key.is_empty():
			out.append(key)
	return out


func tower_reserve_ids() -> Array:
	var out: Array = []
	for i in range(TOWER_ACTIVE, mini(TOWER_TEAM_SIZE, tower_team.size())):
		var key := String(tower_team[i])
		if not key.is_empty():
			out.append(key)
	return out


## Por que no se puede empezar un piso con este equipo ("" si vale).
func tower_team_problem(tower_id: String, floor_number: int) -> String:
	if DB.tower_floor(String(tower_id), floor_number).is_empty():
		return "Ese piso no existe."
	if tower_active_ids().is_empty():
		return "Pon al menos 1 personaje en los puestos ACTIVOS."
	if floor_number > tower_run_floor(String(tower_id)):
		return "Ese piso todavia esta bloqueado."
	return ""


## Prepara un piso de torre: enemigos del piso, activos al combate y reservas en
## espera. Devuelve false (y no toca nada del combate) si el equipo no vale.
func prepare_tower_battle(tower_id: String, floor_number: int) -> bool:
	if not tower_team_problem(tower_id, floor_number).is_empty():
		return false
	if not prepare_battle(BATTLE_TOWER, { "tower": String(tower_id), "floor": floor_number }):
		return false
	battle_party = tower_active_ids()
	battle_reserve = tower_reserve_ids()
	_tower_lead = []
	for i in TOWER_ACTIVE:
		_tower_lead.append(String(tower_team[i]) if i < tower_team.size() else "")
	return true


func battle_reserve_data() -> Array:
	var data_list: Array = []
	for id in battle_reserve:
		var data := character_data(String(id))
		if not data.is_empty():
			data_list.append(data)
	return data_list


## Sale del contexto de torre: links y Leader Skill vuelven a leer el equipo normal.
func reset_battle_context() -> void:
	_tower_lead = []
	battle_reserve = []
	if battle_source == BATTLE_TOWER:
		battle_party = []
		battle_source = BATTLE_STAGE


func _lead_party() -> Array:
	return _tower_lead if not _tower_lead.is_empty() else party



## --- Evolucion --------------------------------------------------------------

## Se puede evolucionar a este personaje? Devuelve SIEMPRE el mismo formato, para
## que una pantalla pueda pintar el motivo sin conocer las reglas:
## { ok, reason, route, from, to, level, level_required, coin_cost, coins }.
## El motivo esta en texto de jugador: "esa rareza no tiene ruta", "nivel
## insuficiente", "faltan monedas"...
func can_evolve(id: String) -> Dictionary:
	var key := String(id)
	var report := {
		"ok": false,
		"reason": "",
		"route": {},
		"from": rarity_of(key),
		"to": "",
		"level": level_of(key),
		"level_required": 0,
		"coin_cost": 0,
		"coins": coins,
	}
	if DB.get_character(key).is_empty():
		report["reason"] = "Ese personaje no existe."
		return report
	if not is_owned(key):
		report["reason"] = "Todavia no tienes a ese personaje."
		return report
	var evolution = DB.get_character(key).get("evolution", {})
	if not (evolution is Dictionary) or evolution.is_empty():
		report["reason"] = "Ese personaje no tiene forma evolucionada."
		return report
	var routes := DB.evolution_routes_from(rarity_of(key))
	if routes.is_empty():
		if is_evolved(key):
			report["reason"] = "Ya ha evolucionado a %s." % rarity_of(key)
		else:
			report["reason"] = "Su rareza (%s) no tiene ruta de evolucion." % rarity_of(key)
		return report
	var route: Dictionary = routes[0]
	var to_rarity := String(route.get("to", ""))
	if to_rarity.is_empty():
		report["reason"] = "La ruta de evolucion no dice a que rareza lleva."
		return report
	# La forma LR es OPCIONAL por personaje: solo la tiene quien declara
	# evolution.lr en su JSON. Sin ese bloque, un UR no puede dar el ultimo paso.
	if to_rarity == "LR":
		var lr_block = (evolution as Dictionary).get("lr", {})
		if not (lr_block is Dictionary) or (lr_block as Dictionary).is_empty():
			report["reason"] = "Ese personaje no tiene forma LR."
			return report
	var level_required := int(route.get("level_required", Progression.LEVEL_MAX))
	var coin_cost := int(route.get("coin_cost", 0))
	report["route"] = route
	report["to"] = to_rarity
	report["level_required"] = level_required
	report["coin_cost"] = coin_cost
	if level_of(key) < level_required:
		report["reason"] = "Nivel insuficiente: hace falta nivel %d." % level_required
		return report
	if coins < coin_cost:
		report["reason"] = "Faltan monedas: cuesta %d y tienes %d." % [coin_cost, coins]
		return report
	report["ok"] = true
	report["reason"] = "Listo para evolucionar a %s." % to_rarity
	return report


## Evoluciona a un personaje. SOLO actua si can_evolve(id).ok, asi que la pantalla
## no puede saltarse el nivel ni las monedas. Conserva la identidad del personaje
## (mismo id, misma entrada en el roster, mismo arte, misma propiedad): lo unico
## que cambia es la rareza efectiva, que vuelve a nivel 1 con 0 XP.
## Devuelve el informe para que la pantalla lo anuncie, o {} si no se ha hecho.
func evolve(id: String) -> Dictionary:
	var key := String(id)
	var check := can_evolve(key)
	if not bool(check["ok"]):
		return {}
	var cost := int(check["coin_cost"])
	if not spend_coins(cost):
		return {}
	var from_rarity := String(check["from"])
	var to_rarity := String(check["to"])
	rarities[key] = to_rarity
	# La evolucion conserva al personaje pero reinicia su progresion: vuelve a
	# nivel 1 con 0 XP, que es lo que hace que la mejora cueste algo.
	progress[key] = { "level": Progression.LEVEL_MIN, "xp": 0 }
	# La MUTACION es del PERSONAJE, no de su forma: sobrevive a la evolucion. Su
	# bonus y su origen se releen del balance por si su rango ha cambiado.
	_refresh_mutation(key)
	add_counter("evoluciones")
	save_game()
	# El informe se lee DESPUES de aplicar el cambio, para que la pasiva, los
	# links y las categorias que anuncia sean los que de verdad valen ya.
	var data := character_data(key)
	var new_links: Array = []
	var evolution = DB.get_character(key).get("evolution", {})
	if evolution is Dictionary:
		new_links = evolution.get("links", [])
	return {
		"id": key,
		"name": display_name(key),
		"from_rarity": from_rarity,
		"to_rarity": to_rarity,
		"rarity": to_rarity,
		"cost": cost,
		"coins": coins,
		"level": level_of(key),
		"passive": data.get("passive", {}),
		"passives": data.get("passives", []),
		"links": new_links,
		"categories": evolution.get("categories", []) if evolution is Dictionary else [],
		"stat_multiplier": float(check["route"].get("stat_multiplier", 1.0)),
		"route": check["route"],
		"mutation": mutation_report(key),
	}


## --- Evoluciones especiales --------------------------------------------------

## Se puede hacer la EVOLUCION ESPECIAL de un personaje? Son las rutas que
## cambian de PERSONAJE (sakuta_mai -> sakuta, sakuta -> sakuta_mai_lr) y viven
## en res://data/evolutions/special.json: coste, objetos y jefe salen de ahi, no
## de una rama de codigo por personaje.
## Devuelve siempre el mismo formato para que una pantalla pinte el motivo:
## { ok, reason, route, from, to, to_rarity, level, level_required, coin_cost,
##   coins, item_cost, items_ok, missing_items, boss, dialogue, kind }.
func can_special_evolve(id: String) -> Dictionary:
	var key := String(id)
	var report := {
		"ok": false,
		"reason": "",
		"kind": "special",
		"route": {},
		"from": key,
		"to": "",
		"to_rarity": "",
		"level": level_of(key),
		"level_required": 0,
		"coin_cost": 0,
		"coins": coins,
		"item_cost": [],
		"items_ok": true,
		"missing_items": [],
		"boss": "",
		"dialogue": "",
		# Requisito de EVENTO (opcional): que evento hay que completar y cuantas
		# veces. Va en el informe aunque la ruta no lo pida, para que la pantalla
		# siempre pueda leer las mismas claves.
		"event_id": "",
		"event_clears": 0,
		"event_clears_required": 0,
		"event_ok": true,
		"mutation": mutation_report(key),
	}
	if DB.get_character(key).is_empty():
		report["reason"] = "Ese personaje no existe."
		return report
	if not is_owned(key):
		report["reason"] = "Todavia no tienes a ese personaje."
		return report
	var routes := DB.special_evolution_routes_from(key)
	if routes.is_empty():
		report["reason"] = "Ese personaje no tiene una evolucion especial."
		return report
	var route: Dictionary = routes[0]
	var to_id := String(route.get("to", ""))
	report["route"] = route
	report["to"] = to_id
	report["to_rarity"] = String(route.get("to_rarity", ""))
	report["boss"] = String(route.get("boss", ""))
	report["dialogue"] = String(route.get("dialogue", ""))
	var level_required := int(route.get("level_required", 0))
	var coin_cost := int(route.get("coin_cost", 0))
	report["level_required"] = level_required
	report["coin_cost"] = coin_cost
	var item_cost = route.get("item_cost", [])
	report["item_cost"] = item_cost if item_cost is Array else []
	if to_id.is_empty() or DB.get_character(to_id).is_empty():
		report["reason"] = "La ruta de evolucion especial no lleva a ningun personaje valido."
		return report
	if level_of(key) < level_required:
		report["reason"] = "Nivel insuficiente: hace falta nivel %d." % level_required
		return report
	if coins < coin_cost:
		report["reason"] = "Faltan monedas: cuesta %d y tienes %d." % [coin_cost, coins]
		return report
	var missing: Array = []
	for cost in report["item_cost"]:
		if not (cost is Dictionary):
			continue
		var item_id := String((cost as Dictionary).get("item", ""))
		var amount := int((cost as Dictionary).get("amount", 1))
		if not has_item(item_id, amount):
			missing.append({
				"item": item_id,
				"name": item_display_name(item_id),
				"need": amount,
				"have": item_count(item_id),
			})
	if not missing.is_empty():
		report["items_ok"] = false
		report["missing_items"] = missing
		var names := ""
		for entry in missing:
			if not names.is_empty():
				names += ", "
			names += "%s x%d" % [String(entry["name"]), int(entry["need"])]
		report["reason"] = "Faltan objetos: %s." % names
		return report
	# 3) El evento que la ruta pida, completado las veces que diga su JSON. Es
	#    tambien un dato: aqui no hay ningun evento escrito.
	var event_id := String(route.get("requires_event", ""))
	var clears_needed := int(route.get("requires_event_clears", 0))
	if not event_id.is_empty() and clears_needed > 0:
		var clears := event_times_completed(event_id)
		report["event_id"] = event_id
		report["event_clears"] = clears
		report["event_clears_required"] = clears_needed
		if clears < clears_needed:
			report["event_ok"] = false
			report["reason"] = "%s: completado %d veces de %d." % [
				String(DB.get_event(event_id).get("name", event_id)), clears, clears_needed]
			return report
	report["ok"] = true
	report["reason"] = "Listo para la evolucion especial a %s." % display_name(to_id)
	return report


## Aplica la EVOLUCION ESPECIAL. Solo actua si can_special_evolve(id).ok, asi que
## la pantalla no puede saltarse el nivel, las monedas ni los objetos.
## Conserva el EQUIPO (la casilla que ocupaba pasa al personaje nuevo), el NIVEL,
## las monedas que sobren y la MUTACION, que se muda al personaje nuevo en lugar
## de perderse. Devuelve el informe, o {} si no se ha hecho.
func evolve_special(id: String) -> Dictionary:
	var key := String(id)
	var check := can_special_evolve(key)
	if not bool(check["ok"]):
		return {}
	var route: Dictionary = check["route"]
	var to_id := String(check["to"])
	var cost := int(check["coin_cost"])
	if not spend_coins(cost):
		return {}
	var consumed: Array = []
	for entry in check["item_cost"]:
		if not (entry is Dictionary):
			continue
		var item_id := String((entry as Dictionary).get("item", ""))
		var amount := int((entry as Dictionary).get("amount", 1))
		if not remove_item(item_id, amount):
			continue
		consumed.append({ "item": item_id, "name": item_display_name(item_id), "amount": amount })
	var mutation_before := mutation_report(key)
	var level_before := level_of(key)
	var xp_before := xp_of(key)
	# El personaje nuevo hereda el progreso: una forma superior no devuelve al
	# jugador al nivel 1, porque ya ha pagado el nivel y los objetos.
	var inherited: Dictionary = progress.get(key, { "level": level_before, "xp": xp_before }).duplicate(true)
	var slot := party.find(key)
	if bool(route.get("transfer_party", true)) and slot >= 0:
		party[slot] = to_id
	if not roster.has(to_id):
		roster.append(to_id)
	progress[to_id] = inherited
	if not duplicates.has(to_id):
		duplicates[to_id] = 0
	# Los DUPES son del personaje y no se pierden: si la ruta consume la forma
	# anterior, sus copias y su nivel de Dupe pasan a la nueva (sin duplicar bonus:
	# el nivel es un numero, no un modificador guardado).
	if bool(route.get("consume_from", true)):
		# Se juntan las copias EXTRA y las ya gastadas de las dos identidades; el nivel
		# resultante es el mas alto que ese gasto total paga. Con coste uniforme equivale
		# a sumar niveles (con tope); con costes distintos nunca se pierde ninguna copia.
		var spent_budget := _dupe_copies_spent(to_id) + _dupe_copies_spent(key)
		duplicates[to_id] = duplicates_of(to_id) + duplicates_of(key)
		var merged_level := _dupe_level_for_budget(spent_budget)
		if merged_level > 0:
			dupe_levels[to_id] = merged_level
		else:
			dupe_levels.erase(to_id)
		dupe_levels.erase(key)
	# La mutacion pertenece al PERSONAJE y no se pierde: se muda al nuevo.
	if not mutation_before.is_empty():
		mutations[to_id] = mutations.get(key, {})
	# "consume_from" es un dato de la ruta: si la ruta consume la forma anterior,
	# el personaje viejo sale del roster (su identidad ahora es la nueva).
	if bool(route.get("consume_from", true)):
		roster.erase(key)
		progress.erase(key)
		duplicates.erase(key)
		mutations.erase(key)
		rarities.erase(key)
	add_counter("evoluciones")
	save_game()
	_refresh_mutation(to_id)
	var data := character_data(to_id)
	return {
		"id": to_id,
		"from": key,
		"from_name": display_name(key),
		"name": display_name(to_id),
		"to_rarity": String(check["to_rarity"]),
		"rarity": rarity_of(to_id),
		"level": level_of(to_id),
		"level_before": level_before,
		"cost": cost,
		"coins": coins,
		"consumed_items": consumed,
		"party_slot": party.find(to_id),
		"route": route,
		"boss": String(route.get("boss", "")),
		"dialogue": String(route.get("dialogue", "")),
		"passives": data.get("passives", []),
		"links": data.get("links", []),
		"categories": data.get("categories", []),
		"mutation": mutation_report(to_id),
		"mutation_before": mutation_before,
	}


## --- Guardado --------------------------------------------------------------

func save_game() -> void:
	var payload := {
		"version": SAVE_VERSION,
		"roster": roster,
		"progress": progress,
		"party": party,
		"friend": friend,
		"coins": coins,
		"gems": gems,
		"materials": materials,
		"current_stage_enemies": current_stage_enemies,
		"stage_id": stage_id,
		"world_id": current_world_id,
		"energy": energy,
		"energy_max": energy_max,
		"counters": counters,
		"completed_stages": completed_stages,
		"missions_claimed": missions_claimed,
		"rarities": rarities,
		"duplicates": duplicates,
		"dupe_levels": dupe_levels,
		"inventory": inventory,
		"mutations": mutations,
		"story_progress": story_progress,
		"event_progress": event_progress,
		"tower_progress": tower_progress,
		"tower_team": tower_team,
		"pending_reveal": pending_reveal,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameState: no se pudo escribir %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


## Devuelve true si se ha cargado un archivo valido. Si no existe, se queda con
## los valores por defecto. Un archivo de una version ANTERIOR se MIGRA en vez de
## ignorarse (perder el progreso del jugador por una actualizacion no es
## aceptable); solo se ignora un archivo de una version DESCONOCIDA, es decir
## mayor que la actual, porque no sabemos interpretarlo.
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("GameState: %s no es un guardado valido; se ignora." % SAVE_PATH)
		return false
	var data: Dictionary = parsed
	var version := int(data.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("GameState: guardado de una version mas nueva (%d > %d); se ignora para no estropearlo." % [version, SAVE_VERSION])
		return false
	data = _migrate_save(data, version)

	# Listas vacias en el archivo no deben borrar los valores por defecto.
	var loaded_roster: Array = data.get("roster", [])
	if not loaded_roster.is_empty():
		roster = loaded_roster
	var loaded_progress = data.get("progress", {})
	if loaded_progress is Dictionary:
		for key in loaded_progress.keys():
			progress[String(key)] = loaded_progress[key]
	var loaded_party: Array = data.get("party", [])
	if not loaded_party.is_empty():
		party = loaded_party
	friend = String(data.get("friend", friend))
	coins = int(data.get("coins", coins))
	gems = int(data.get("gems", gems))
	materials = int(data.get("materials", materials))
	stage_id = String(data.get("stage_id", stage_id))
	current_world_id = String(data.get("world_id", current_world_id))
	energy = int(data.get("energy", energy))
	energy_max = int(data.get("energy_max", energy_max))
	var loaded_enemies: Array = data.get("current_stage_enemies", [])
	if not loaded_enemies.is_empty():
		current_stage_enemies = loaded_enemies
	# Contadores, stages ganados y misiones reclamadas. Se fusionan sobre los
	# valores por defecto para que un guardado viejo no borre lo que ya hay.
	var loaded_counters = data.get("counters", {})
	if loaded_counters is Dictionary:
		for key in loaded_counters.keys():
			counters[String(key)] = int(loaded_counters[key])
	completed_stages = data.get("completed_stages", completed_stages)
	var loaded_missions = data.get("missions_claimed", {})
	if loaded_missions is Dictionary:
		missions_claimed = loaded_missions.duplicate(true)
	# V2: rareza evolucionada y duplicados por personaje. Un guardado v1 no las
	# trae y se queda con lo que ya hubiera (vacio), que significa "nadie ha
	# evolucionado todavia" y "cero duplicados".
	var loaded_rarities = data.get("rarities", {})
	if loaded_rarities is Dictionary:
		for key in loaded_rarities.keys():
			rarities[String(key)] = String(loaded_rarities[key])
	var loaded_duplicates = data.get("duplicates", {})
	if loaded_duplicates is Dictionary:
		for key in loaded_duplicates.keys():
			duplicates[String(key)] = int(loaded_duplicates[key])
	# Dupes: solo se guarda el NIVEL por personaje. Un guardado anterior no lo trae y
	# arranca en 0 (sus duplicados pasan a ser copias disponibles, sin perder nada).
	# Se sanea: nivel dentro de rango y nunca mayor que las copias que lo pagan.
	dupe_levels = {}
	var loaded_dupes = data.get("dupe_levels", {})
	if loaded_dupes is Dictionary:
		for key in loaded_dupes.keys():
			var lvl := clampi(int(loaded_dupes[key]), 0, dupe_max_level())
			if lvl > 0 and DB.has_character(String(key)):
				dupe_levels[String(key)] = lvl
	for key in dupe_levels.keys():
		var owed := _dupe_copies_spent(String(key))
		if duplicates_of(String(key)) < owed:
			duplicates[String(key)] = owed
	# V3: inventario, mutaciones, progreso de historia y progreso de eventos. Un
	# guardado v1 o v2 no trae estos campos y se quedan vacios ("no tiene ningun
	# objeto", "ningun personaje tiene mutacion", "no ha jugado la historia ni los
	# eventos") sin tocar nada de lo que el archivo ya traia.
	var loaded_inventory = data.get("inventory", {})
	if loaded_inventory is Dictionary:
		for key in loaded_inventory.keys():
			var count := int(loaded_inventory[key])
			if count > 0:
				inventory[String(key)] = count
	var loaded_mutations = data.get("mutations", {})
	if loaded_mutations is Dictionary:
		for key in loaded_mutations.keys():
			var entry = loaded_mutations[key]
			if entry is Dictionary and not (entry as Dictionary).is_empty():
				mutations[String(key)] = (entry as Dictionary).duplicate(true)
				_refresh_mutation(String(key))
	var loaded_story = data.get("story_progress", {})
	if loaded_story is Dictionary:
		for key in loaded_story.keys():
			var entry = loaded_story[key]
			if entry is Array:
				story_progress[String(key)] = entry.duplicate()
	var loaded_events = data.get("event_progress", {})
	if loaded_events is Dictionary:
		for key in loaded_events.keys():
			var entry = loaded_events[key]
			if entry is Dictionary:
				event_progress[String(key)] = _normalize_event_state(entry)
	# V3: progreso de TORRES (piso mas alto superado, control y pisos ya pagados).
	var loaded_tower_team = data.get("tower_team", [])
	if loaded_tower_team is Array:
		tower_team = loaded_tower_team
	normalize_tower_team()
	# Un guardado sin torres arranca la torre desde el piso 1.
	var loaded_towers = data.get("tower_progress", {})
	if loaded_towers is Dictionary:
		for key in loaded_towers.keys():
			var entry = loaded_towers[key]
			if entry is Dictionary:
				tower_progress[String(key)] = _normalize_tower_state(entry)

	var loaded_pending = data.get("pending_reveal", {})
	pending_reveal = _clean_pending_reveal(loaded_pending)

	# Por si el archivo es de antes de anadir un personaje al roster.
	ensure_defaults()
	return true


## Una secuencia de revelado guardada solo se acepta si es coherente: resultados
## con ids que existen y un indice dentro de rango. Si no, se descarta (los
## personajes YA estan en el roster; solo se pierde la escenificacion).
func _clean_pending_reveal(raw: Variant) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return {}
	var results = (raw as Dictionary).get("results", [])
	if not (results is Array) or (results as Array).is_empty():
		return {}
	var clean: Array = []
	for entry in results:
		if entry is Dictionary and DB.has_character(String((entry as Dictionary).get("id", ""))):
			clean.append((entry as Dictionary).duplicate(true))
	if clean.is_empty():
		return {}
	var index := int((raw as Dictionary).get("index", 0))
	if index < 0 or index >= clean.size():
		return {}
	var out: Dictionary = (raw as Dictionary).duplicate(true)
	out["results"] = clean
	out["index"] = index
	return out


## Un estado de evento guardado siempre tiene la misma forma: si un guardado trae
## un campo de menos, se rellena vacio en lugar de dejar una clave sin crear.
func _normalize_event_state(entry: Dictionary) -> Dictionary:
	var out := _empty_event_state()
	var stages = entry.get("stages", {})
	if stages is Dictionary:
		out["stages"] = (stages as Dictionary).duplicate(true)
	var claimed = entry.get("rewards_claimed", {})
	if claimed is Dictionary:
		out["rewards_claimed"] = (claimed as Dictionary).duplicate(true)
	out["times_completed"] = int(entry.get("times_completed", 0))
	return out


## Un progreso de torre guardado siempre tiene la misma forma, aunque venga de un
## guardado con campos de menos: mejor un cero explicito que una clave sin crear.
func _normalize_tower_state(entry: Dictionary) -> Dictionary:
	var out := _empty_tower_state()
	out["best_floor"] = int(entry.get("best_floor", 0))
	out["checkpoint"] = int(entry.get("checkpoint", 0))
	out["runs"] = int(entry.get("runs", 0))
	out["run_floor"] = int(entry.get("run_floor", 0))
	var rewarded = entry.get("rewarded", [])
	if rewarded is Array:
		var clean: Array = []
		for raw in rewarded:
			clean.append(int(raw))
		out["rewarded"] = clean
	return out


## Lleva un guardado de una version anterior al formato actual SIN perder nada.
## Regla: todo lo que estaba se conserva, y lo que falta se anade con su valor
## por defecto. Un v1 no trae rarities ni duplicates (los campos que estrena la
## v2), asi que quedan vacios: nadie ha evolucionado y ningun personaje tiene
## duplicados. No se toca ningun campo que el archivo ya tuviera.
func _migrate_save(data: Dictionary, version: int) -> Dictionary:
	if version >= SAVE_VERSION:
		return data
	if version < 1:
		push_warning("GameState: guardado sin numero de version; se lee como v1.")
	if not (data.get("rarities") is Dictionary):
		data["rarities"] = {}
	if not (data.get("duplicates") is Dictionary):
		data["duplicates"] = {}
	# V3: inventario, mutaciones, progreso de historia por dificultad y progreso
	# de eventos. Los campos que estrena la v3 llegan vacios en un guardado viejo:
	# no tenia objetos, ni mutaciones, ni habia jugado la historia ni los eventos.
	if not (data.get("inventory") is Dictionary):
		data["inventory"] = {}
	if not (data.get("mutations") is Dictionary):
		data["mutations"] = {}
	if not (data.get("world_id") is String):
		data["world_id"] = ""
	if not (data.get("story_progress") is Dictionary):
		data["story_progress"] = {}
	if not (data.get("event_progress") is Dictionary):
		data["event_progress"] = {}
	# V3: progreso de torres. Un guardado anterior a las torres llega vacio: la
	# torre empieza en el piso 1.
	if not (data.get("tower_progress") is Dictionary):
		data["tower_progress"] = {}
	var towers = data.get("tower_progress", {})
	if towers is Dictionary:
		for key in (towers as Dictionary).keys():
			var tower_entry = (towers as Dictionary)[key]
			data["tower_progress"][key] = _normalize_tower_state(tower_entry) if tower_entry is Dictionary else _empty_tower_state()
	# La v2 no tenia nada de esto, pero si un guardado intermedio lo trajera a
	# medias, cada entrada se normaliza en lugar de darse por buena.
	var events = data.get("event_progress", {})
	if events is Dictionary:
		for key in (events as Dictionary).keys():
			var entry = (events as Dictionary)[key]
			data["event_progress"][key] = _normalize_event_state(entry) if entry is Dictionary else _empty_event_state()
	data["version"] = SAVE_VERSION
	push_warning("GameState: guardado v%d migrado a v%d sin perder datos." % [maxi(version, 1), SAVE_VERSION])
	return data


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
