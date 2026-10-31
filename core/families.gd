extends RefCounted

## FAMILIAS EVOLUTIVAS Y FUENTES DE OBTENCION (v15).
##
## Algunas evoluciones CAMBIAN de personaje y consumen al anterior (Sakuta y Mai ->
## Sakuta -> Sakuta y Mai LR). Para una coleccion eso es un problema: el jugador nunca
## puede tener a la vez los tres ids. Una FAMILIA agrupa todas las formas de un mismo
## personaje bajo su RAIZ (la forma que no viene de ninguna otra): se posee la familia
## si se posee cualquiera de sus formas. Asi una coleccion que pide "Sakuta y Mai" se
## puede completar tambien despues de evolucionarlo.
##
## Las funciones son estaticas y leen solo datos (DB) y, cuando hace falta, el estado
## del jugador que se les pasa.


## Raiz de la familia de `id`: sigue "evolved_from" (y las rutas especiales) hacia atras.
static func root_of(id: String) -> String:
	var current := String(id)
	var guard := 0
	while guard < 16:
		guard += 1
		var parent := _parent_of(current)
		if parent.is_empty() or parent == current:
			break
		current = parent
	return current


static func _parent_of(id: String) -> String:
	var data: Dictionary = DB.characters.get(id, {})
	var parent := String(data.get("evolved_from", ""))
	if not parent.is_empty() and DB.characters.has(parent):
		return parent
	for raw in DB.special_evolution_routes():
		if raw is Dictionary and String((raw as Dictionary).get("to", "")) == id:
			var from_id := String((raw as Dictionary).get("from", ""))
			if DB.characters.has(from_id):
				return from_id
	return ""


## Todas las formas de la familia cuya raiz es `root` (la raiz incluida), sin repetir.
static func forms_of(root: String) -> Array:
	var out: Array = []
	if not DB.characters.has(root):
		return out
	var queue: Array = [root]
	while not queue.is_empty():
		var current := String(queue.pop_front())
		if out.has(current):
			continue
		out.append(current)
		var data: Dictionary = DB.characters.get(current, {})
		for child in data.get("evolves_to", []):
			if DB.characters.has(String(child)) and not out.has(String(child)):
				queue.append(String(child))
		for raw in DB.special_evolution_routes():
			if raw is Dictionary and String((raw as Dictionary).get("from", "")) == current:
				var to_id := String((raw as Dictionary).get("to", ""))
				if DB.characters.has(to_id) and not out.has(to_id):
					queue.append(to_id)
	return out


## Raices de todas las familias, ordenadas (una por personaje "distinto" del juego).
static func all_roots() -> Array:
	var out: Array = []
	for id in DB.characters.keys():
		var root := root_of(String(id))
		if not out.has(root):
			out.append(root)
	out.sort()
	return out


## El jugador posee la familia si tiene cualquiera de sus formas en el roster.
static func owns(gs, root: String) -> bool:
	for form in forms_of(root):
		if gs.is_owned(String(form)):
			return true
	return false


## Cuantas familias del juego posee el jugador (para "Completista").
static func owned_roots(gs) -> int:
	var n := 0
	for root in all_roots():
		if owns(gs, String(root)):
			n += 1
	return n


## Id de la forma que el jugador tiene ahora de esa familia ("" si no tiene ninguna).
## Si tiene varias, la mas avanzada (la ultima de la cadena).
static func owned_form(gs, root: String) -> String:
	var best := ""
	for form in forms_of(root):
		if gs.is_owned(String(form)):
			best = String(form)
	return best


## --- Fuentes de obtencion ---------------------------------------------------------
## De donde puede salir un personaje: [{ kind, id, name }] con kind en "banner",
## "shop", "event", "evolution" o "starter". Una lista VACIA significa que el
## personaje es IMPOSIBLE de conseguir (lo detecta el diagnostico).

static func sources_of(id: String) -> Array:
	var out: Array = []
	var key := String(id)
	if not DB.characters.has(key):
		return out
	if GameState.STARTING_ROSTER.has(key):
		out.append({ "kind": "starter", "id": "", "name": "Personaje inicial" })
	for banner in DB.all_banners():
		var banner_id := String((banner as Dictionary).get("id", ""))
		if GameState.banner_pool(banner_id).has(key):
			out.append({ "kind": "banner", "id": banner_id, "name": String((banner as Dictionary).get("name", banner_id)) })
	for entry in DB.all_shop_items():
		var grant = (entry as Dictionary).get("grant", {})
		if grant is Dictionary and String((grant as Dictionary).get("type", "")) == "character" and String((grant as Dictionary).get("character_id", "")) == key:
			out.append({ "kind": "shop", "id": String((entry as Dictionary).get("id", "")), "name": String((entry as Dictionary).get("name", "Tienda")) })
	for event in DB.all_events():
		var event_id := String((event as Dictionary).get("id", ""))
		var granted := String((event as Dictionary).get("character_reward", "")) == key
		for stage in (event as Dictionary).get("stages", []):
			if stage is Dictionary and String((stage as Dictionary).get("grant_character", "")) == key:
				granted = true
		if granted:
			out.append({ "kind": "event", "id": event_id, "name": String((event as Dictionary).get("name", event_id)) })
	for raw in DB.special_evolution_routes():
		if raw is Dictionary and String((raw as Dictionary).get("to", "")) == key:
			var from_id := String((raw as Dictionary).get("from", ""))
			# La forma solo es alcanzable si la anterior lo es (se evalua sin recursion
			# infinita: la cadena termina en una raiz con fuente propia).
			out.append({ "kind": "evolution", "id": from_id, "name": "Evolucion de %s" % String((DB.characters.get(from_id, {}) as Dictionary).get("name", from_id)) })
	return out


## Texto corto de las fuentes para pintarlo en una lista ("Invocacion: Apertura").
static func sources_text(id: String) -> String:
	var parts := PackedStringArray()
	for src in sources_of(id):
		match String(src["kind"]):
			"banner":
				parts.append("Invocacion: %s" % String(src["name"]))
			"shop":
				parts.append("Tienda")
			"event":
				parts.append("Evento: %s" % String(src["name"]))
			"evolution":
				parts.append(String(src["name"]))
			"starter":
				parts.append("Inicial")
	return ", ".join(parts) if not parts.is_empty() else "No se puede conseguir"


## Es alcanzable de verdad? Una fuente de tipo "evolution" solo cuenta si el personaje
## del que se evoluciona es alcanzable a su vez (cadena sin ciclos).
static func reachable(id: String, visited: Array = []) -> bool:
	var key := String(id)
	if visited.has(key):
		return false
	visited.append(key)
	for src in sources_of(key):
		if String(src["kind"]) != "evolution":
			return true
		if reachable(String(src["id"]), visited.duplicate()):
			return true
	return false
