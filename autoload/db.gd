extends Node

## Autoload DB: carga TODO el contenido del juego desde res://data/.
##
## Regla del proyecto: anadir un personaje nuevo es crear un archivo JSON en
## data/characters/ y meter su arte. Ningun script se toca.
##
## Nota de export a movil: los .json dentro de res:// necesitan incluirse en el
## preset de exportacion (filtros de archivos no-recurso). El cargador intenta
## primero FileAccess y luego ResourceLoader para cubrir ambos casos.

const CHARACTER_DIR := "res://data/characters"
const ENEMY_DIR := "res://data/enemies"
const STAGES_DIR := "res://data/stages"
const MISSIONS_DIR := "res://data/missions"
const LINKS_DIR := "res://data/links"
const CATEGORIES_DIR := "res://data/categories"
const BANNERS_DIR := "res://data/banners"
const SHOP_DIR := "res://data/shop"
const ITEMS_DIR := "res://data/items"
const WORLDS_DIR := "res://data/worlds"
const DIALOGUES_DIR := "res://data/dialogues"
const EVENTS_DIR := "res://data/events"
const TOWERS_DIR := "res://data/towers"
## Las Leader Skills son UN archivo de balance (tabla de lideres + quien lleva
## cual), igual que las mutaciones: por eso se lee aparte y no con _load_dir.
const LEADERS_FILE := "res://data/leaders/leaders.json"
## Las mutaciones NO son entidades con id por archivo: son UN archivo de balance
## (coste, rangos, probabilidades y efectos). Igual que las reglas de evolucion.
const MUTATIONS_FILE := "res://data/mutations/config.json"
## Las reglas de evolucion son UN archivo con "routes", no una carpeta de
## entidades: por eso se lee aparte con _read_json y no con _load_dir (que
## exige un campo "id" por archivo).
const EVOLUTION_FILE := "res://data/evolution/rules.json"
## Las evoluciones ESPECIALES (cambian de personaje, no solo de rareza) viven en
## su propio archivo con "routes", con el mismo formato de lectura.
const DUPE_RULES_FILE := "res://data/dupes/rules.json"
const SPECIAL_EVOLUTION_FILE := "res://data/evolutions/special.json"
## Orden de las dificultades de un nivel de historia cuando su JSON no trae el
## campo "order". Completa una dificultad de orden N desbloquea y paga las de
## orden MENOR O IGUAL, y eso lo decide el "order" de cada dificultad, no su
## nombre: anadir una dificultad nueva no toca ningun script.
const DIFFICULTY_FALLBACK_ORDER := ["normal", "hard", "extreme"]

var characters: Dictionary = {}
var enemies: Dictionary = {}
var stages: Dictionary = {}
var missions: Dictionary = {}
var links: Dictionary = {}
var categories: Dictionary = {}
var banners: Dictionary = {}
var shop_items: Dictionary = {}
## { "routes": [ { from, to, level_required, coin_cost, stat_multiplier } ] }
var evolution_rules: Dictionary = {}
## Catalogo generico de objetos: materiales, tickets y objetos evolutivos.
var items: Dictionary = {}
## Historia: cada mundo con sus niveles y las tres dificultades de cada nivel.
var worlds: Dictionary = {}
var dialogues: Dictionary = {}
var events: Dictionary = {}
## Torres: cada torre es un JSON con sus pisos, sus enemigos y sus recompensas.
var towers: Dictionary = {}
## Tabla de Leader Skills: { default_leader, leaders: [...], by_character: {...} }.
var leader_table: Dictionary = {}
## Balance COMPLETO de mutaciones: coste, rangos y probabilidades de efecto.
var mutations_config: Dictionary = {}
## { "routes": [ { from, to, level_required, coin_cost, item_cost, boss } ] }
var special_evolution_rules: Dictionary = {}
## Reglas de Dupes (res://data/dupes/rules.json): niveles, coste y bonus. Un solo sitio.
var dupe_rules: Dictionary = {}
var load_errors: Array = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	load_errors = []
	characters = _load_dir(CHARACTER_DIR)
	enemies = _load_dir(ENEMY_DIR)
	stages = _load_dir(STAGES_DIR)
	missions = _load_dir(MISSIONS_DIR)
	links = _load_dir(LINKS_DIR)
	categories = _load_dir(CATEGORIES_DIR)
	banners = _load_dir(BANNERS_DIR)
	shop_items = _load_dir(SHOP_DIR)
	items = _load_dir(ITEMS_DIR)
	worlds = _load_dir(WORLDS_DIR)
	dialogues = _load_dir(DIALOGUES_DIR)
	events = _load_dir(EVENTS_DIR)
	towers = _load_dir(TOWERS_DIR)
	mutations_config = _load_mutations()
	evolution_rules = _read_routes_file(EVOLUTION_FILE)
	special_evolution_rules = _read_routes_file(SPECIAL_EVOLUTION_FILE)
	dupe_rules = _load_dupe_rules()
	leader_table = _load_leaders()
	_check_references()
	if load_errors.is_empty():
		print("DB: %d personajes, %d enemigos, %d stages, %d misiones, %d links, %d categorias, %d banners, %d objetos de tienda, %d objetos, %d mundos, %d dialogos, %d eventos, %d rutas de evolucion especial, %d torres y %d lideres cargados." % [
			characters.size(), enemies.size(), stages.size(), missions.size(),
			links.size(), categories.size(), banners.size(), shop_items.size(),
			items.size(), worlds.size(), dialogues.size(), events.size(),
			special_evolution_routes().size(), towers.size(), all_leaders().size()])
	else:
		for error_text in load_errors:
			push_error("DB: %s" % error_text)


## Comprueba que ningun link o categoria mencionada por un personaje se quede sin
## definir. Asi un personaje nuevo con un link mal escrito avisa al arrancar en
## lugar de dar un bonus invisible.
func _check_references() -> void:
	for id in characters.keys():
		var data: Dictionary = characters[id]
		_check_character_refs(String(id), data, "")
		_check_character_relations(String(id), data)
		var evolution = data.get("evolution", {})
		if evolution is Dictionary and not evolution.is_empty():
			_check_character_refs(String(id), evolution, "evolution.")
			var lr_stage = (evolution as Dictionary).get("lr", {})
			if lr_stage is Dictionary and not (lr_stage as Dictionary).is_empty():
				_check_character_refs(String(id), lr_stage, "evolution.lr.")
	_check_banner_refs()
	_check_world_refs()
	_check_event_refs()
	_check_special_evolution_refs()


## Un banner solo puede nombrar personajes que existen (destacados, exclusivos y
## tasas propias), para que un id mal escrito avise al arrancar.
func _check_banner_refs() -> void:
	for banner_id in banners.keys():
		var banner: Dictionary = banners[banner_id]
		for field in ["featured", "exclusive_ids"]:
			var ids = banner.get(field, [])
			if ids is Array:
				for raw in ids:
					if not characters.has(String(raw)):
						load_errors.append("El banner '%s' nombra a '%s' en %s y no existe." % [banner_id, raw, field])
		var rates = banner.get("featured_rates", {})
		if rates is Dictionary:
			for raw in (rates as Dictionary).keys():
				if not characters.has(String(raw)):
					load_errors.append("El banner '%s' da tasa propia a '%s' y no existe." % [banner_id, raw])


## Los enemigos de HISTORIA tienen que existir, y cada nivel tiene que traer sus
## dificultades con enemigos y recompensas. Un id mal escrito sale en el log de
## arranque en vez de romper el juego al entrar al nivel.
func _check_world_refs() -> void:
	for world_id in worlds.keys():
		var world: Dictionary = worlds[world_id]
		var unlock = world.get("unlock", {})
		if unlock is Dictionary and not unlock.is_empty():
			var requires_world := String(unlock.get("requires_world", ""))
			if not requires_world.is_empty() and not worlds.has(requires_world):
				load_errors.append("El mundo '%s' pide desbloquearse tras '%s', que no existe." % [world_id, requires_world])
		var levels = world.get("levels", [])
		if not (levels is Array) or (levels as Array).is_empty():
			load_errors.append("El mundo '%s' no tiene niveles." % world_id)
			continue
		for level in levels:
			if not (level is Dictionary):
				continue
			_check_story_level(String(world_id), level)


func _check_story_level(world_id: String, level: Dictionary) -> void:
	var level_id := String(level.get("id", ""))
	var dialogue := String(level.get("dialogue", ""))
	if not dialogue.is_empty() and not dialogues.has(dialogue):
		load_errors.append("El nivel '%s' del mundo '%s' usa el dialogo '%s', que no existe." % [level_id, world_id, dialogue])
	var difficulties = level.get("difficulties", {})
	if not (difficulties is Dictionary) or (difficulties as Dictionary).is_empty():
		load_errors.append("El nivel '%s' del mundo '%s' no tiene dificultades." % [level_id, world_id])
		return
	for difficulty_id in (difficulties as Dictionary).keys():
		var difficulty = difficulties[difficulty_id]
		if not (difficulty is Dictionary):
			continue
		for enemy_id in difficulty.get("enemies", []):
			if not enemies.has(String(enemy_id)):
				load_errors.append("El nivel '%s' (%s) del mundo '%s' usa el enemigo '%s', que no existe." % [level_id, String(difficulty_id), world_id, String(enemy_id)])


## El evento declara sus stages en datos: enemigos, objeto que suelta, personaje
## que entrega y la unidad que exige en el equipo. Todos esos ids se validan aqui.
func _check_event_refs() -> void:
	for event_id in events.keys():
		var event: Dictionary = events[event_id]
		var reward := String(event.get("character_reward", ""))
		if not reward.is_empty() and not characters.has(reward):
			load_errors.append("El evento '%s' entrega el personaje '%s', que no existe." % [event_id, reward])
		var stages = event.get("stages", [])
		if not (stages is Array) or (stages as Array).is_empty():
			load_errors.append("El evento '%s' no tiene stages." % event_id)
			continue
		for stage in stages:
			if not (stage is Dictionary):
				continue
			_check_event_stage(String(event_id), stage)


func _check_event_stage(event_id: String, stage: Dictionary) -> void:
	var stage_id := String(stage.get("id", ""))
	var dialogue := String(stage.get("dialogue", ""))
	if not dialogue.is_empty() and not dialogues.has(dialogue):
		load_errors.append("El stage '%s' del evento '%s' usa el dialogo '%s', que no existe." % [stage_id, event_id, dialogue])
	for enemy_id in stage.get("enemies", []):
		if not enemies.has(String(enemy_id)):
			load_errors.append("El stage '%s' del evento '%s' usa el enemigo '%s', que no existe." % [stage_id, event_id, String(enemy_id)])
	for key in ["grant_character", "requires_party_character"]:
		var character_id := String(stage.get(key, ""))
		if not character_id.is_empty() and not characters.has(character_id):
			load_errors.append("El stage '%s' del evento '%s' usa el personaje '%s' en '%s', que no existe." % [stage_id, event_id, character_id, key])
	for drop in stage.get("drops", []):
		if not (drop is Dictionary):
			continue
		var item_id := String(drop.get("item", ""))
		if not item_id.is_empty() and not items.has(item_id):
			load_errors.append("El stage '%s' del evento '%s' suelta el objeto '%s', que no existe." % [stage_id, event_id, item_id])


## Las dos evoluciones especiales cambian de PERSONAJE: sus relaciones
## evolves_to / evolved_from y los objetos que piden tienen que existir.
func _check_character_relations(id: String, data: Dictionary) -> void:
	for related in data.get("evolves_to", []):
		if not characters.has(String(related)):
			load_errors.append("El personaje '%s' dice que evoluciona a '%s', que no existe." % [id, String(related)])
	var from := String(data.get("evolved_from", ""))
	if not from.is_empty() and not characters.has(from):
		load_errors.append("El personaje '%s' dice venir de '%s', que no existe." % [id, from])


func _check_special_evolution_refs() -> void:
	for route in special_evolution_routes():
		var route_id := String(route.get("id", "?"))
		for key in ["from", "to"]:
			var character_id := String(route.get(key, ""))
			if character_id.is_empty():
				load_errors.append("La ruta de evolucion especial '%s' no dice su '%s'." % [route_id, key])
			elif not characters.has(character_id):
				load_errors.append("La ruta de evolucion especial '%s' usa el personaje '%s', que no existe." % [route_id, character_id])
		var boss := String(route.get("boss", ""))
		if not boss.is_empty() and not enemies.has(boss):
			load_errors.append("La ruta de evolucion especial '%s' pelea contra el enemigo '%s', que no existe." % [route_id, boss])
		var dialogue := String(route.get("dialogue", ""))
		if not dialogue.is_empty() and not dialogues.has(dialogue):
			load_errors.append("La ruta de evolucion especial '%s' usa el dialogo '%s', que no existe." % [route_id, dialogue])
		for cost in route.get("item_cost", []):
			if not (cost is Dictionary):
				continue
			var item_id := String(cost.get("item", ""))
			if not item_id.is_empty() and not items.has(item_id):
				load_errors.append("La ruta de evolucion especial '%s' pide el objeto '%s', que no existe." % [route_id, item_id])


func _check_character_refs(id: String, data: Dictionary, prefix: String) -> void:
	for link_id in data.get("links", []):
		if not links.has(String(link_id)):
			load_errors.append("El personaje '%s' referencia %slinks '%s', que no existe." % [id, prefix, String(link_id)])
	for category_id in data.get("categories", []):
		if not categories.has(String(category_id)):
			load_errors.append("El personaje '%s' referencia %scategoria '%s', que no existe." % [id, prefix, String(category_id)])


## Lee un archivo con una lista "routes" (rutas de evolucion genericas y rutas
## de evolucion especial). Es el mismo patron tolerante que el resto: si falta el
## archivo o la lista, se avisa en el log de arranque y el juego sigue.
func _read_routes_file(path: String) -> Dictionary:
	var data = _read_json(path)
	if not (data is Dictionary):
		load_errors.append("No se pudieron leer las rutas de evolucion en %s" % path)
		return {}
	var routes = data.get("routes", [])
	if not (routes is Array):
		load_errors.append("%s no tiene una lista 'routes'." % path)
		return { "routes": [] }
	return data


## El balance de mutaciones se lee como un archivo de configuracion: coste,
## rangos y probabilidades viven AHI y no en el codigo. Si falta, se avisa y el
## sistema de mutaciones queda desactivado en lugar de inventarse una tabla.
func _load_mutations() -> Dictionary:
	var data = _read_json(MUTATIONS_FILE)
	if not (data is Dictionary):
		load_errors.append("No se pudo leer el balance de mutaciones en %s" % MUTATIONS_FILE)
		return {}
	if not (data.get("ranks", []) is Array) or (data.get("ranks", []) as Array).is_empty():
		load_errors.append("%s no tiene una lista 'ranks' con los rangos de mutacion." % MUTATIONS_FILE)
	if not (data.get("effects", []) is Array) or (data.get("effects", []) as Array).is_empty():
		load_errors.append("%s no tiene una lista 'effects' con los efectos posibles." % MUTATIONS_FILE)
	return data


## Ids de todos los personajes cargados, en orden alfabetico. Lo usan COLECCION y
## EQUIPO, para que no exista ninguna lista de personajes escrita en un script.
func character_ids() -> Array:
	var ids: Array = characters.keys()
	ids.sort()
	return ids


## Existe ese personaje? Se pregunta antes de pedirlo cuando el id puede ser de
## otra cosa (un enemigo, una casilla vacia) y no queremos un error en el log.
func has_character(id: String) -> bool:
	return characters.has(id)


## Puede salir este personaje de una invocacion? Por defecto SI: la excepcion es
## explicita en los datos. Un personaje con "gacha": false (una unidad free to
## play, que se consigue en su evento) queda fuera de TODOS los banners, y sus
## formas evolucionadas tambien, porque heredan el bloque del personaje base.
## La excepcion se declara en el JSON, nunca en un script.
func is_gacha_character(id: String) -> bool:
	var key := String(id)
	if not characters.has(key):
		return false
	return bool((characters[key] as Dictionary).get("gacha", true))


func get_character(id: String) -> Dictionary:
	if characters.has(id):
		return characters[id]
	push_error("DB: personaje desconocido '%s'." % id)
	return {}


func get_enemy(id: String) -> Dictionary:
	if not enemies.has(id):
		push_error("DB: enemigo desconocido '%s'." % id)
		return {}
	return _resolve_enemy(enemies[id])


## Un enemigo puede declarar "based_on": el id de un PERSONAJE del roster. Entonces
## pelea con la identidad de ese personaje (nombre, tipo, rareza, arte, pasiva y
## habilidades), pero CONSERVA lo suyo: su propio id de enemigo, sus estadisticas y
## cualquier campo que declare su JSON, que se aplica ENCIMA. Asi cambiar la cara
## de un boss de evento es cambiar una linea de datos, sin duplicar un personaje ni
## escribir una rama por enemigo. Sin "based_on" se devuelve tal cual.
func _resolve_enemy(data: Dictionary) -> Dictionary:
	var base_id := String(data.get("based_on", ""))
	if base_id.is_empty() or not characters.has(base_id):
		return data
	var merged: Dictionary = (characters[base_id] as Dictionary).duplicate(true)
	for key in data.keys():
		merged[key] = data[key]
	# El arte se busca por el ID, y el id de un enemigo no tiene carpeta de arte
	# propia: si el enemigo no declara la suya, se apunta a la del personaje base
	# para que salga con su cara en vez de una silueta.
	var own_art = data.get("art", {})
	if not (own_art is Dictionary) or (own_art as Dictionary).is_empty():
		merged["art"] = _base_art_paths(base_id)
	return merged


## Rutas de arte del personaje base, solo para las ranuras que tienen PNG de
## verdad. Sirve para que un enemigo con "based_on" herede el dibujo sin cargar
## nada que no exista (ui/portrait.gd dibuja una silueta si no hay archivo).
func _base_art_paths(character_id: String) -> Dictionary:
	var out: Dictionary = {}
	for slot_name in ["front", "back", "icon"]:
		for ext in [".png", ".webp"]:
			var path := "res://art/characters/%s/%s%s" % [character_id, slot_name, ext]
			if ResourceLoader.exists(path):
				out[slot_name] = path
				break
	return out


func get_stage(id: String) -> Dictionary:
	if stages.has(id):
		return stages[id]
	push_error("DB: stage desconocido '%s'." % id)
	return {}


func get_mission(id: String) -> Dictionary:
	if missions.has(id):
		return missions[id]
	push_error("DB: mision desconocida '%s'." % id)
	return {}


func get_link(id: String) -> Dictionary:
	if links.has(id):
		return links[id]
	push_error("DB: link desconocido '%s'." % id)
	return {}


func get_category(id: String) -> Dictionary:
	if categories.has(id):
		return categories[id]
	push_error("DB: categoria desconocida '%s'." % id)
	return {}


func get_banner(id: String) -> Dictionary:
	if banners.has(id):
		return banners[id]
	push_error("DB: banner desconocido '%s'." % id)
	return {}


## Existe ese articulo? Permite comprobarlo SIN ensuciar el log: una pantalla o
## una compra que recibe un id viejo (un articulo retirado, por ejemplo) no debe
## soltar un error, porque no es un fallo del juego sino un dato que ya no esta.
func has_shop_item(id: String) -> bool:
	return shop_items.has(id)


func get_shop_item(id: String) -> Dictionary:
	if shop_items.has(id):
		return shop_items[id]
	push_error("DB: objeto de tienda desconocido '%s'." % id)
	return {}


## Regla de evolucion entre dos rarezas, o {} si esa ruta no esta definida. La
## cadena entera (R->SR, SR->SSR, SSR->UR, UR->LR) son entradas de "routes" en
## res://data/evolution/rules.json: anadir una transicion no toca ningun script.
func evolution_rule(from_rarity: String, to_rarity: String) -> Dictionary:
	for route in evolution_routes():
		if String(route.get("from", "")) != from_rarity:
			continue
		if String(route.get("to", "")) != to_rarity:
			continue
		return route
	return {}


## Todas las rutas de evolucion declaradas, en el orden del archivo.
func evolution_routes() -> Array:
	var routes = evolution_rules.get("routes", [])
	return routes if routes is Array else []


## Todas las rutas que parten de una rareza, para saber si una unidad puede
## evolucionar a algo sin escribir ninguna tabla en el codigo.
func evolution_routes_from(from_rarity: String) -> Array:
	var out: Array = []
	for route in evolution_routes():
		if String(route.get("from", "")) == from_rarity:
			out.append(route)
	return out


## Vinculos de un personaje (base + los que anade su bloque de evolucion), en
## formato de datos resuelto para pintar. Una pantalla no lee "links" a mano.
func character_links(id: String) -> Array:
	var data := get_character(String(id))
	return _resolve_ids(data.get("links", []), links)


## Categorias de un personaje (base + las que anade su bloque de evolucion).
func character_categories(id: String) -> Array:
	var data := get_character(String(id))
	return _resolve_ids(data.get("categories", []), categories)


func _resolve_ids(ids: Variant, catalog: Dictionary) -> Array:
	var out: Array = []
	if not (ids is Array):
		return out
	for raw_id in ids:
		var key := String(raw_id)
		var entry: Dictionary = catalog.get(key, {})
		out.append({
			"id": key,
			"name": String(entry.get("name", key)),
			"description": String(entry.get("description", "")),
			"defined": not entry.is_empty(),
		})
	return out


## Misiones ordenadas por id, en el mismo orden que la pantalla las pinta.
func all_missions() -> Array:
	var ids: Array = missions.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		out.append(missions[id])
	return out


## Stages ordenados por id. La pantalla de seleccion los pinta en este orden, asi
## que anadir una batalla nueva es crear su JSON y nada mas.
func all_stages() -> Array:
	var ids: Array = stages.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		out.append(stages[id])
	return out


## Catalogos ordenados por id, para que cualquier pantalla que los liste se
## construya sola al anadir un JSON nuevo.
func all_links() -> Array:
	return _all_sorted(links)


func all_categories() -> Array:
	return _all_sorted(categories)


## Carga y VALIDA las reglas de Dupes. Si el archivo falta o es incoherente se deja
## constancia en load_errors y el sistema queda desactivado (max_level 0) en vez de
## aplicar numeros a medias.
func _load_dupe_rules() -> Dictionary:
	var off := { "max_level": 0, "copies_per_level": [], "levels": [{}] }
	if not FileAccess.file_exists(DUPE_RULES_FILE):
		return off
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DUPE_RULES_FILE))
	if not (parsed is Dictionary):
		load_errors.append("%s no es un JSON valido." % DUPE_RULES_FILE)
		return off
	var rules: Dictionary = parsed
	var max_level := int(rules.get("max_level", 0))
	var levels = rules.get("levels", [])
	var costs = rules.get("copies_per_level", [])
	if not (levels is Array) or (levels as Array).size() != max_level + 1 or not (costs is Array) or (costs as Array).size() != max_level:
		load_errors.append("Dupes: 'levels' debe tener max_level+1 filas y 'copies_per_level' max_level.")
		return off
	for cost in costs:
		if int(cost) < 1:
			load_errors.append("Dupes: cada mejora cuesta al menos 1 copia.")
			return off
	var overflow = rules.get("overflow", {})
	if not (overflow is Dictionary) or int((overflow as Dictionary).get("coins_per_copy", 0)) < 0:
		load_errors.append("Dupes: 'overflow.coins_per_copy' debe ser un numero >= 0 (0 = sin conversion).")
		rules["overflow"] = {}
	return rules


## Banners ACTIVOS (los que no declaran "enabled": false), ordenados por id.
func all_banners() -> Array:
	var out: Array = []
	for banner in _all_sorted(banners):
		if bool((banner as Dictionary).get("enabled", true)):
			out.append(banner)
	return out


func all_shop_items() -> Array:
	return _all_sorted(shop_items)


func _all_sorted(catalog: Dictionary) -> Array:
	var ids: Array = catalog.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		out.append(catalog[id])
	return out


## --- Objetos ----------------------------------------------------------------

func get_item(id: String) -> Dictionary:
	if items.has(id):
		return items[id]
	push_error("DB: objeto desconocido '%s'." % id)
	return {}


func all_items() -> Array:
	return _all_sorted(items)


## Ruta del icono de un objeto. La convencion es res://art/items/<id>.png, asi
## que un objeto nuevo solo necesita su JSON y, si el PNG todavia no existe, la
## pantalla dibuja un marcador en lugar de romperse.
func item_icon(id: String) -> String:
	var data := get_item(String(id))
	var icon := String(data.get("icon", ""))
	if not icon.is_empty():
		return icon
	return "res://art/items/%s.png" % String(id)


## --- Historia (mundos y niveles) --------------------------------------------

func get_world(id: String) -> Dictionary:
	if worlds.has(id):
		return worlds[id]
	push_error("DB: mundo desconocido '%s'." % id)
	return {}


func all_worlds() -> Array:
	return _all_sorted(worlds)


## Un nivel de historia por su mundo y su id. Devuelve {} si no existe: la
## pantalla de mapa pregunta por los niveles que el mundo declara, no por una
## lista escrita en el codigo.
func world_level(world_id: String, level_id: String) -> Dictionary:
	var world := get_world(String(world_id))
	for level in world.get("levels", []):
		if level is Dictionary and String(level.get("id", "")) == String(level_id):
			return level
	return {}


func story_levels(world_id: String) -> Array:
	var world := get_world(String(world_id))
	var levels = world.get("levels", [])
	return levels if levels is Array else []


## Todos los ids de nivel de historia del juego, en el orden de sus mundos.
func story_level_ids() -> Array:
	var out: Array = []
	for world in all_worlds():
		for level in world.get("levels", []):
			if level is Dictionary:
				out.append(String(level.get("id", "")))
	return out


## Nivel de historia al que pertenece un id, buscando en todos los mundos.
func world_of_level(level_id: String) -> String:
	for world in all_worlds():
		for level in world.get("levels", []):
			if level is Dictionary and String(level.get("id", "")) == String(level_id):
				return String(world.get("id", ""))
	return ""


## Las dificultades de un nivel, ORDENADAS por su campo "order" y listas para
## pintar: [{ id, order, name, enemies, xp_reward, coin_reward }]. El orden es un
## DATO del JSON: completar la dificultad de orden N desbloquea y paga las de
## orden menor o igual, sin ninguna rama de codigo por dificultad.
func story_level_difficulties(world_id: String, level_id: String) -> Array:
	var level := world_level(world_id, level_id)
	return difficulties_of_level(level)


func difficulties_of_level(level: Dictionary) -> Array:
	var out: Array = []
	var table = level.get("difficulties", {})
	if not (table is Dictionary):
		return out
	var index := 0
	for raw_id in (table as Dictionary).keys():
		var entry = table[raw_id]
		if not (entry is Dictionary):
			index += 1
			continue
		var difficulty_id := String(raw_id)
		out.append({
			"id": difficulty_id,
			"order": difficulty_order_of(difficulty_id, (entry as Dictionary), index),
			"name": String((entry as Dictionary).get("name", difficulty_id.to_upper())),
			"enemies": (entry as Dictionary).get("enemies", []),
			"xp_reward": int((entry as Dictionary).get("xp_reward", 0)),
			"coin_reward": int((entry as Dictionary).get("coin_reward", 0)),
		})
		index += 1
	out.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	return out


func difficulty_order_of(difficulty_id: String, entry: Dictionary, fallback_index: int = 0) -> int:
	if entry.has("order"):
		return int(entry.get("order", 0))
	var fallback := DIFFICULTY_FALLBACK_ORDER.find(String(difficulty_id))
	if fallback >= 0:
		return fallback
	return fallback_index


## Dificultad concreta de un nivel, con su id dentro del diccionario, o {}.
func story_difficulty(world_id: String, level_id: String, difficulty_id: String) -> Dictionary:
	var level := world_level(world_id, level_id)
	return difficulty_of_level(level, difficulty_id)


func difficulty_of_level(level: Dictionary, difficulty_id: String) -> Dictionary:
	var table = level.get("difficulties", {})
	if not (table is Dictionary) or not (table as Dictionary).has(String(difficulty_id)):
		return {}
	var entry = table[difficulty_id]
	if not (entry is Dictionary):
		return {}
	var out: Dictionary = (entry as Dictionary).duplicate(true)
	out["id"] = String(difficulty_id)
	out["level_id"] = String(level.get("id", ""))
	return out


## --- Dialogos ---------------------------------------------------------------

func get_dialogue(id: String) -> Dictionary:
	if dialogues.has(id):
		return dialogues[id]
	push_error("DB: dialogo desconocido '%s'." % id)
	return {}


func all_dialogues() -> Array:
	return _all_sorted(dialogues)


## Lineas de un dialogo listas para pintar, con el SKIP ya resuelto en datos.
func dialogue_lines(id: String) -> Array:
	var data := get_dialogue(String(id))
	var lines = data.get("lines", [])
	return lines if lines is Array else []


## --- Eventos ----------------------------------------------------------------

func get_event(id: String) -> Dictionary:
	if events.has(id):
		return events[id]
	push_error("DB: evento desconocido '%s'." % id)
	return {}


func all_events() -> Array:
	return _all_sorted(events)


func event_stages(event_id: String) -> Array:
	var event := get_event(String(event_id))
	var stages = event.get("stages", [])
	return stages if stages is Array else []


func event_stage(event_id: String, stage_id: String) -> Dictionary:
	for stage in event_stages(event_id):
		if stage is Dictionary and String(stage.get("id", "")) == String(stage_id):
			return stage
	return {}


## Id del evento al que pertenece un stage (los contadores y el progreso se
## guardan por evento, no por stage suelto).
func event_of_stage(stage_id: String) -> String:
	for event in all_events():
		for stage in event.get("stages", []):
			if stage is Dictionary and String(stage.get("id", "")) == String(stage_id):
				return String(event.get("id", ""))
	return ""


## --- Mutaciones -------------------------------------------------------------

## Balance completo de mutaciones (coste, rangos, efectos y la regla especial de
## la mutacion Z). Sale entero de res://data/mutations/config.json.
func mutation_config() -> Dictionary:
	return mutations_config


func mutation_cost() -> int:
	return int(mutations_config.get("cost", 0))


func mutation_ranks() -> Array:
	var ranks = mutations_config.get("ranks", [])
	return ranks if ranks is Array else []


func mutation_rank(rank_id: String) -> Dictionary:
	for rank in mutation_ranks():
		if rank is Dictionary and String(rank.get("id", "")) == String(rank_id):
			return rank
	return {}


func mutation_effects() -> Array:
	var effects = mutations_config.get("effects", [])
	return effects if effects is Array else []


func mutation_special() -> Dictionary:
	var special = mutations_config.get("special", {})
	return special if special is Dictionary else {}


## --- Evoluciones especiales -------------------------------------------------

func special_evolution_routes() -> Array:
	var routes = special_evolution_rules.get("routes", [])
	return routes if routes is Array else []


## Las rutas de evolucion ESPECIAL que parten de un personaje. A diferencia de
## evolution_routes_from (que va por RAREZA), estas van por PERSONAJE: son las
## que convierten sakuta_mai en sakuta y sakuta en sakuta_mai_lr.
func special_evolution_routes_from(character_id: String) -> Array:
	var out: Array = []
	for route in special_evolution_routes():
		if String(route.get("from", "")) == String(character_id):
			out.append(route)
	return out


func special_evolution_route(from_id: String, to_id: String) -> Dictionary:
	for route in special_evolution_routes_from(from_id):
		if String(route.get("to", "")) == String(to_id):
			return route
	return {}


## --- Torres ------------------------------------------------------------------

func get_tower(id: String) -> Dictionary:
	if towers.has(id):
		return towers[id]
	return {}


func all_towers() -> Array:
	return _all_sorted(towers)


## Solo las torres que estan ABIERTAS hoy (campo "enabled" del JSON; ausente
## significa que si). Una torre nueva en datos aparece sola en la lista.
func playable_towers() -> Array:
	var out: Array = []
	for tower in all_towers():
		if bool(tower.get("enabled", true)):
			out.append(tower)
	return out


func tower_floors(tower_id: String) -> Array:
	var tower := get_tower(String(tower_id))
	var floors = tower.get("floors", [])
	return floors if floors is Array else []


## Piso de una torre por su NUMERO de piso (1..N), que es como lo pide el juego.
func tower_floor(tower_id: String, floor_number: int) -> Dictionary:
	for floor in tower_floors(tower_id):
		if floor is Dictionary and int(floor.get("floor", 0)) == floor_number:
			return floor
	return {}


func tower_floor_count(tower_id: String) -> int:
	return tower_floors(tower_id).size()


## Cada cuantos pisos hay un punto de control y un jefe. Vive en el JSON de la
## torre, no en el codigo.
func tower_checkpoint_step(tower_id: String) -> int:
	var tower := get_tower(String(tower_id))
	return maxi(1, int(tower.get("checkpoint_step", 5)))


func tower_floor_is_boss(tower_id: String, floor_number: int) -> bool:
	var floor := tower_floor(tower_id, floor_number)
	if floor.is_empty():
		return false
	return bool(floor.get("boss", false))


## --- Leader Skills -----------------------------------------------------------

## Balance completo: { default_leader, leaders: [...], by_character: {...} }.
func leader_balance() -> Dictionary:
	return leader_table


func all_leaders() -> Array:
	var leaders = leader_table.get("leaders", [])
	return leaders if leaders is Array else []


func get_leader(id: String) -> Dictionary:
	for leader in all_leaders():
		if leader is Dictionary and String(leader.get("id", "")) == String(id):
			return leader
	return {}


func default_leader_id() -> String:
	return String(leader_table.get("default_leader", ""))


## Leader Skill de un personaje: si su JSON declara un bloque "leader", ese manda;
## si no, se busca su id en el mapa "by_character" de la tabla; y si tampoco
## aparece, se devuelve la de por defecto. Nunca hay una rama por personaje.
func leader_id_for(character_id: String) -> String:
	var key := String(character_id)
	# Un id vacio NO es un personaje sin Leader Skill declarada: es que no hay
	# nadie. Devolver "" evita resolverlo al lider por defecto (que repartia
	# bonus con la posicion 1 vacia) y evita el aviso de personaje desconocido.
	if key.is_empty():
		return ""
	var data := get_character(key)
	var own = data.get("leader", "")
	if own is String and not String(own).is_empty():
		return String(own)
	var map = leader_table.get("by_character", {})
	if map is Dictionary and (map as Dictionary).has(key):
		return String((map as Dictionary)[key])
	return default_leader_id()


func leader_for(character_id: String) -> Dictionary:
	return get_leader(leader_id_for(character_id))


## Lee la tabla de Leader Skills. Es UN archivo de balance, no una carpeta de
## entidades: por eso se lee aqui y no con _load_dir.
func _load_leaders() -> Dictionary:
	var data = _read_json(LEADERS_FILE)
	if data is Dictionary:
		return data
	load_errors.append("No se pudo leer la tabla de Leader Skills: %s" % LEADERS_FILE)
	return {}


func _load_dir(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var names := _list_files(dir_path)
	for file_name in names:
		var full_path := "%s/%s" % [dir_path, file_name]
		var data = _read_json(full_path)
		if not (data is Dictionary):
			load_errors.append("No se pudo leer %s" % full_path)
			continue
		var id := String(data.get("id", ""))
		if id.is_empty():
			load_errors.append("%s no tiene campo 'id'" % full_path)
			continue
		if result.has(id):
			load_errors.append("id duplicado '%s' en %s" % [id, full_path])
			continue
		data["_path"] = full_path
		result[id] = data
	return result


func _list_files(dir_path: String) -> Array:
	var names: Array = []
	if not DirAccess.dir_exists_absolute(dir_path):
		load_errors.append("Falta el directorio %s" % dir_path)
		return names
	var dir := DirAccess.open(dir_path)
	if dir == null:
		load_errors.append("No se puede abrir %s" % dir_path)
		return names
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			# En export los .json pueden aparecer como .json.remap: se normaliza.
			var clean := entry.replace(".remap", "")
			if clean.ends_with(".json"):
				names.append(clean)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


func _read_json(path: String) -> Variant:
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text)
		if parsed != null:
			return parsed
		load_errors.append("JSON invalido en %s" % path)
		return null
	if ResourceLoader.exists(path):
		var resource = ResourceLoader.load(path)
		if resource is JSON:
			return resource.data
	load_errors.append("Archivo no encontrado: %s" % path)
	return null
