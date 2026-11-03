extends RefCounted

## DIAGNOSTICO DE DESARROLLO (v15). Detecta datos y estado mal configurados ANTES de que
## lo note un jugador. SOLO LEE: no modifica nada del juego ni escribe el guardado.
##
## Esta herramienta es de desarrollo y NO existe en la version publica:
##   - todo `run*` empieza por `DevTools.enabled()` (compilacion de depuracion + interruptor),
##     igual que el resto de res://dev/: en una exportacion de release devuelve un
##     informe vacio con un unico aviso;
##   - se monta solo desde el panel DEVELOPER TOOLS (Ajustes, solo en depuracion) o con
##     `godot --headless --path . -- --diag`;
##   - la carpeta res://dev/ se excluye de la exportacion (ver dev/README.md).
##
## Cada hallazgo es { severity, area, text }:
##   error   -> el juego esta roto o es injusto (un personaje imposible, una fase injugable)
##   warning -> raro pero jugable (arte que falta: el juego dibuja una silueta)
##   info    -> contexto

const DevTools := preload("res://dev/dev_tools.gd")
const Families := preload("res://core/families.gd")
const Rewards := preload("res://core/rewards.gd")
const Collections := preload("res://core/collections.gd")

const AREAS := ["ids", "recursos", "guardado", "recompensas", "personajes", "fases"]
const VALID_RARITIES := ["N", "R", "SR", "SSR", "UR", "LR"]

var findings: Array = []


func _add(severity: String, area: String, text: String) -> void:
	findings.append({ "severity": severity, "area": area, "text": text })


## Ejecuta TODOS los grupos y devuelve el informe.
func run_all() -> Dictionary:
	findings = []
	if not DevTools.enabled():
		_add("info", "ids", "Diagnostico no disponible en esta compilacion.")
		return report()
	check_duplicate_ids()
	check_missing_resources()
	check_save()
	check_duplicate_rewards()
	check_unobtainable_characters()
	check_stages()
	return report()


func report() -> Dictionary:
	var counts := { "error": 0, "warning": 0, "info": 0 }
	for f in findings:
		counts[String(f["severity"])] = int(counts[String(f["severity"])]) + 1
	return { "findings": findings.duplicate(true), "counts": counts, "ok": int(counts["error"]) == 0 }


## Texto del informe, una linea por hallazgo (para consola y panel).
func to_text(max_lines: int = 400) -> String:
	var rep := report()
	var lines := PackedStringArray()
	lines.append("DIAGNOSTICO: %d errores, %d avisos, %d notas" % [rep["counts"]["error"], rep["counts"]["warning"], rep["counts"]["info"]])
	var shown := 0
	for severity in ["error", "warning", "info"]:
		for f in findings:
			if String(f["severity"]) != severity:
				continue
			shown += 1
			if shown > max_lines:
				continue
			lines.append("[%s] %s: %s" % [String(f["severity"]).to_upper(), String(f["area"]), String(f["text"])])
	if shown > max_lines:
		lines.append("... y %d mas" % (shown - max_lines))
	return "\n".join(lines)


func of_area(area: String, severity: String = "") -> Array:
	var out: Array = []
	for f in findings:
		if String(f["area"]) == area and (severity.is_empty() or String(f["severity"]) == severity):
			out.append(f)
	return out


## --- 1. Identificadores duplicados -------------------------------------------------

func check_duplicate_ids() -> void:
	# Los duplicados dentro de una carpeta ya los cuenta DB al cargar.
	for e in DB.load_errors:
		_add("error", "ids", String(e))
	# Un id repetido ENTRE carpetas que comparten espacio de nombres.
	_cross_dupes("objetos y cosmeticos", [["objeto", DB.items.keys()], ["cosmetico", DB.cosmetics.keys()]])
	_cross_dupes("misiones y logros", [["mision", DB.missions.keys()], ["logro", DB.achievements.keys()]])
	_cross_dupes("personajes y enemigos", [["personaje", DB.characters.keys()], ["enemigo", DB.enemies.keys()]])
	# Ids de fase repetidos entre historia, eventos y stages sueltos.
	var stage_ids: Dictionary = {}
	for id in DB.stages.keys():
		_note_id(stage_ids, String(id), "stage")
	for world_id in DB.worlds.keys():
		for level in DB.story_levels(String(world_id)):
			_note_id(stage_ids, String((level as Dictionary).get("id", "")), "historia %s" % world_id)
	for event_id in DB.events.keys():
		for st in DB.event_stages(String(event_id)):
			_note_id(stage_ids, String((st as Dictionary).get("id", "")), "evento %s" % event_id)
	for id in stage_ids:
		if (stage_ids[id] as Array).size() > 1:
			_add("error", "ids", "id de fase repetido '%s': %s" % [id, ", ".join(PackedStringArray(stage_ids[id]))])
	# Ids repetidos DENTRO de las listas de un archivo (pisos de torre, niveles de un mundo).
	for tower_id in DB.towers.keys():
		var seen: Array = []
		for fl in DB.tower_floors(String(tower_id)):
			var n := int((fl as Dictionary).get("floor", 0))
			if seen.has(n):
				_add("error", "ids", "torre %s: el piso %d esta repetido" % [tower_id, n])
			seen.append(n)
	# El id del archivo tiene que coincidir con el nombre del archivo (un archivo copiado
	# y no renombrado es el origen tipico de duplicados silenciosos).
	for pair in [["personajes", DB.characters], ["enemigos", DB.enemies], ["misiones", DB.missions], ["logros", DB.achievements],
			["colecciones", DB.collections], ["cosmeticos", DB.cosmetics], ["banners", DB.banners], ["objetos", DB.items]]:
		for id in (pair[1] as Dictionary).keys():
			var path := String(((pair[1] as Dictionary)[id] as Dictionary).get("_path", ""))
			if not path.is_empty() and path.get_file().get_basename() != String(id):
				_add("warning", "ids", "%s: el id '%s' no coincide con el archivo %s" % [pair[0], id, path.get_file()])


func _cross_dupes(label: String, groups: Array) -> void:
	var seen: Dictionary = {}
	for g in groups:
		for id in g[1]:
			if seen.has(String(id)):
				_add("error", "ids", "id repetido entre %s: '%s' (%s y %s)" % [label, id, seen[String(id)], g[0]])
			else:
				seen[String(id)] = String(g[0])


func _note_id(book: Dictionary, id: String, origin: String) -> void:
	if id.is_empty():
		return
	if not book.has(id):
		book[id] = []
	(book[id] as Array).append(origin)


## --- 2. Recursos ausentes ------------------------------------------------------------

func check_missing_resources() -> void:
	var bg := load("res://ui/background.gd")
	# Arte de personajes: faltar solo dibuja una silueta (aviso, no error).
	var missing_slots: Dictionary = { "front": [], "back": [], "icon": [] }
	for id in DB.characters.keys():
		var data: Dictionary = DB.characters[id]
		for slot in ["front", "back", "icon"]:
			var path := _art_path(String(id), data, slot)
			if not ResourceLoader.exists(path):
				(missing_slots[slot] as Array).append(String(id))
	for slot in missing_slots:
		var list: Array = missing_slots[slot]
		if not list.is_empty():
			_add("warning", "recursos", "%d personajes sin arte '%s' (se dibuja una silueta): %s" % [list.size(), slot, _short_list(list)])
	# Iconos de objetos.
	for id in DB.items.keys():
		var icon := DB.item_icon(String(id))
		if not ResourceLoader.exists(icon):
			_add("warning", "recursos", "objeto '%s': falta el icono %s" % [id, icon])
	# X.2: objetos equipables y sus banners. Equipables y evolutivos son familias distintas.
	for route in DB.special_evolution_routes():
		for cost in (route as Dictionary).get("item_cost", []):
			var cost_id := String((cost as Dictionary).get("item", ""))
			if DB.equipment.has(cost_id):
				_add("error", "recursos", "la evolucion %s -> %s pide '%s', que es un EQUIPABLE (solo valen objetos evolutivos)" % [(route as Dictionary).get("from", ""), (route as Dictionary).get("to", ""), cost_id])
			elif not DB.items.has(cost_id):
				_add("error", "recursos", "la evolucion %s -> %s pide '%s', que no existe" % [(route as Dictionary).get("from", ""), (route as Dictionary).get("to", ""), cost_id])
	for eid in DB.equipment.keys():
		if DB.items.has(String(eid)):
			_add("error", "recursos", "el id '%s' esta en data/items Y en data/equipment: un objeto es equipable o evolutivo, no ambos" % eid)
	for iid in DB.items.keys():
		if String((DB.items[iid] as Dictionary).get("type", "")) == "evolution_material" and String((DB.items[iid] as Dictionary).get("kind", "")) != "evolutive":
			_add("error", "recursos", "el objeto evolutivo '%s' no declara \"kind\": \"evolutive\"" % iid)
	for eid in DB.equipment.keys():
		for problem in GameState.Equipment.problems_of(String(eid)):
			_add("error", "recursos", "objeto equipable '%s': %s" % [eid, problem])
		var icon := String((DB.equipment[eid] as Dictionary).get("icon", ""))
		if not icon.is_empty() and not ResourceLoader.exists(icon):
			_add("warning", "recursos", "objeto equipable '%s': falta el icono %s (se dibuja un recuadro)" % [eid, icon])
	for bid in DB.equipment_banners.keys():
		for problem in GameState.Equipment.banner_problems(String(bid)):
			_add("error", "recursos", "banner de objetos '%s': %s" % [bid, problem])
	# Cosmeticos: el fondo o la ilustracion tienen que existir de verdad.
	for id in DB.cosmetics.keys():
		var c: Dictionary = DB.cosmetics[id]
		if String(c.get("type", "")) == "background":
			if not bg.has_image(String(c.get("slot", ""))):
				_add("error", "recursos", "cosmetico '%s': no hay imagen para el fondo '%s'" % [id, c.get("slot", "")])
		elif String(c.get("type", "")) == "illustration":
			var ch := String(c.get("character", ""))
			if not DB.characters.has(ch):
				_add("error", "recursos", "cosmetico '%s': el personaje '%s' no existe" % [id, ch])
			elif not ResourceLoader.exists(_art_path(ch, DB.characters[ch], "front")):
				_add("error", "recursos", "cosmetico '%s': '%s' no tiene ilustracion front.png (se veria una silueta)" % [id, ch])
		elif ["frame", "theme", "decoration"].has(String(c.get("type", ""))):
			# v16: marcos, temas y decoraciones se definen solo con colores/modo en su JSON.
			var color_key := "tint" if String(c.get("type", "")) == "theme" else "color"
			if not String(c.get(color_key, "")).is_valid_html_color():
				_add("error", "recursos", "cosmetico '%s': '%s' no es un color valido" % [id, color_key])
			if String(c.get("type", "")) == "decoration" and not ["motes", "stars", "embers"].has(String(c.get("mode", ""))):
				_add("error", "recursos", "cosmetico '%s': modo de decoracion desconocido '%s'" % [id, c.get("mode", "")])
		else:
			_add("error", "recursos", "cosmetico '%s': tipo desconocido '%s'" % [id, c.get("type", "")])
	# Fondos pedidos por mundos, stages, eventos y torres.
	var wanted: Dictionary = {}
	for id in DB.stages.keys():
		_want(wanted, String(DB.stages[id].get("background", "")), "stage %s" % id)
	for id in DB.worlds.keys():
		_want(wanted, String(DB.worlds[id].get("background", "")), "mundo %s" % id)
		for level in DB.story_levels(String(id)):
			_want(wanted, String((level as Dictionary).get("background", "")), "nivel %s" % (level as Dictionary).get("id", ""))
	for id in DB.events.keys():
		_want(wanted, String(DB.events[id].get("background", "")), "evento %s" % id)
		for st in DB.event_stages(String(id)):
			_want(wanted, String((st as Dictionary).get("background", "")), "fase %s" % (st as Dictionary).get("id", ""))
	for id in DB.towers.keys():
		_want(wanted, String(DB.towers[id].get("background", "")), "torre %s" % id)
	for slot in wanted:
		if not bg.has_image(String(slot)) and not (bg.PALETTES as Dictionary).has(String(slot)) and not (bg.EXTRA_PALETTES as Dictionary).has(String(slot)):
			# El fondo cae a la paleta por defecto (nunca queda negro), pero es contenido sin hacer.
			var users: Array = wanted[slot]
			_add("warning", "recursos", "fondo '%s' sin imagen ni paleta propia (usa la paleta por defecto); lo piden %d fases: %s" % [slot, users.size(), _short_list(users, 4)])
	# Dialogos referenciados.
	for world_id in DB.worlds.keys():
		for level in DB.story_levels(String(world_id)):
			_need_dialogue(String((level as Dictionary).get("dialogue", "")), "nivel %s" % (level as Dictionary).get("id", ""))
	for event_id in DB.events.keys():
		for st in DB.event_stages(String(event_id)):
			_need_dialogue(String((st as Dictionary).get("dialogue", "")), "fase %s" % (st as Dictionary).get("id", ""))
	# Audio: lo que falta del catalogo (lo aportado por el usuario es nota, no error).
	for ev in GameAudio.missing_events():
		_add("warning", "recursos", "audio del catalogo sin archivo: %s" % ev)
	for ev in GameAudio.missing_user_supplied():
		_add("info", "recursos", "audio opcional sin archivo (lo aportas tu): %s" % ev)


func _art_path(id: String, data: Dictionary, slot: String) -> String:
	var art = data.get("art", {})
	if art is Dictionary and not String((art as Dictionary).get(slot, "")).is_empty():
		return String((art as Dictionary)[slot])
	return "res://art/characters/%s/%s.png" % [id, slot]


func _want(book: Dictionary, slot: String, origin: String) -> void:
	if slot.is_empty():
		return
	if not book.has(slot):
		book[slot] = []
	(book[slot] as Array).append(origin)


func _need_dialogue(id: String, origin: String) -> void:
	if not id.is_empty() and not DB.dialogues.has(id):
		_add("error", "recursos", "%s: el dialogo '%s' no existe" % [origin, id])


func _short_list(list: Array, n: int = 8) -> String:
	if list.size() <= n:
		return ", ".join(PackedStringArray(list))
	return "%s y %d mas" % [", ".join(PackedStringArray(list.slice(0, n))), list.size() - n]


## --- 3. Errores de guardado ----------------------------------------------------------

## Comprueba el guardado EN MEMORIA (lo que save_game escribiria) y el archivo real si
## existe. No escribe nada.
func check_save() -> void:
	var payload: Dictionary = GameState.build_save_payload()
	var text := JSON.stringify(payload)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_add("error", "guardado", "el guardado no se puede serializar a JSON y volver a leer")
		return
	for key in ["version", "roster", "progress", "party", "coins", "gems", "meta_progress", "account", "collections", "favorites", "inventory"]:
		if not (parsed as Dictionary).has(key):
			_add("error", "guardado", "falta la clave '%s' en el guardado" % key)
	if int((parsed as Dictionary).get("version", 0)) != GameState.SAVE_VERSION:
		_add("error", "guardado", "version del guardado %s distinta de SAVE_VERSION %d" % [(parsed as Dictionary).get("version"), GameState.SAVE_VERSION])
	# Referencias del estado a datos que existen.
	for id in GameState.roster:
		if not DB.characters.has(String(id)):
			_add("error", "guardado", "el roster tiene un personaje que no existe: '%s'" % id)
		if not GameState.progress.has(String(id)):
			_add("error", "guardado", "'%s' esta en el roster pero no tiene progreso" % id)
	var seen_roster: Array = []
	for id in GameState.roster:
		if seen_roster.has(String(id)):
			_add("error", "guardado", "personaje repetido en el roster: '%s'" % id)
		seen_roster.append(String(id))
	for id in GameState.party:
		if not String(id).is_empty() and not GameState.roster.has(String(id)):
			_add("error", "guardado", "el equipo lleva a '%s', que no esta en el roster" % id)
	for id in GameState.favorites:
		if not GameState.roster.has(String(id)):
			_add("error", "guardado", "favorito '%s' que no esta en el roster" % id)
	for item_id in GameState.inventory:
		if not DB.items.has(String(item_id)):
			_add("error", "guardado", "el inventario tiene un objeto que no existe: '%s'" % item_id)
		elif int(GameState.inventory[item_id]) <= 0:
			_add("error", "guardado", "cantidad no positiva guardada de '%s'" % item_id)
	for key in ["coins", "gems", "materials"]:
		if int(GameState.get(key)) < 0:
			_add("error", "guardado", "%s negativo (%d)" % [key, int(GameState.get(key))])
	for id in GameState.rarities:
		if not VALID_RARITIES.has(String(GameState.rarities[id])):
			_add("error", "guardado", "rareza no valida guardada para '%s'" % id)
	# Cuenta, colecciones y misiones personales.
	var acc = GameState.account
	for l in acc.claimed_levels:
		if int(l) > acc.level():
			_add("error", "guardado", "nivel de cuenta %d cobrado sin haberlo alcanzado (nivel %d)" % [int(l), acc.level()])
	for id in acc.cosmetics_owned:
		if not DB.cosmetics.has(String(id)):
			_add("error", "guardado", "cosmetico guardado que no existe: '%s'" % id)
	if not acc.background_equipped.is_empty() and not acc.owns_cosmetic(acc.background_equipped):
		_add("error", "guardado", "fondo equipado que no se posee: '%s'" % acc.background_equipped)
	for cid in GameState.collections.claimed:
		if not DB.collections.has(String(cid)):
			_add("error", "guardado", "coleccion cobrada que ya no existe: '%s'" % cid)
			continue
		var tiers: Array = []
		for t in DB.collections[cid].get("tiers", []):
			tiers.append(String((t as Dictionary).get("id", "")))
		for tier_id in GameState.collections.claimed[cid]:
			if not tiers.has(String(tier_id)):
				_add("error", "guardado", "tramo cobrado inexistente: %s/%s" % [cid, tier_id])
			elif not bool(_tier_reached(String(cid), String(tier_id))):
				_add("error", "guardado", "tramo cobrado sin haber alcanzado su requisito: %s/%s" % [cid, tier_id])
	for pid in GameState.meta.personal:
		var data: Dictionary = DB.missions.get(String(pid), {})
		if data.is_empty():
			_add("error", "guardado", "mision personal guardada que no existe: '%s'" % pid)
		elif int(GameState.meta.personal[pid].get("progress", 0)) > int(data.get("target", 1)):
			_add("error", "guardado", "mision personal %s con progreso mayor que su objetivo" % pid)
	# El archivo real, si existe: tiene que ser legible y de una version conocida.
	if FileAccess.file_exists(GameState.SAVE_PATH):
		var raw := FileAccess.get_file_as_string(GameState.SAVE_PATH)
		var disk = JSON.parse_string(raw)
		if not (disk is Dictionary):
			_add("error", "guardado", "user://save.json existe pero no se puede leer")
		elif int((disk as Dictionary).get("version", 0)) > GameState.SAVE_VERSION:
			_add("error", "guardado", "el archivo es de una version mas nueva que el juego")
		else:
			_add("info", "guardado", "user://save.json legible (version %d)" % int((disk as Dictionary).get("version", 0)))
	else:
		_add("info", "guardado", "todavia no hay user://save.json (primera partida)")


func _tier_reached(collection_id: String, tier_id: String) -> bool:
	for t in GameState.collections.state(collection_id).get("tiers", []):
		if String(t["id"]) == tier_id:
			return bool(t["reached"])
	return false


## --- 4. Recompensas duplicadas ---------------------------------------------------------

func check_duplicate_rewards() -> void:
	# Cada recompensa de cada fuente, normalizada a { origen -> bloque }.
	var blocks: Array = []
	for cid in DB.collections.keys():
		for t in DB.collections[cid].get("tiers", []):
			blocks.append({ "origin": "coleccion %s/%s" % [cid, (t as Dictionary).get("id", "")], "reward": (t as Dictionary).get("reward", {}) })
	for entry in DB.account_config().get("level_rewards", []):
		blocks.append({ "origin": "cuenta nivel %d" % int((entry as Dictionary).get("level", 0)), "reward": (entry as Dictionary).get("reward", {}) })
	for m in DB.personal_missions():
		blocks.append({ "origin": "mision personal %s" % (m as Dictionary).get("id", ""), "reward": (m as Dictionary).get("reward", {}) })
	# 1) formato de cada bloque.
	for b in blocks:
		for p in Rewards.problems(b["reward"], String(b["origin"])):
			_add("error", "recompensas", String(p))
	# 2) cosmeticos entregados por mas de una fuente.
	var cosmetic_sources: Dictionary = {}
	for b in blocks:
		for c in (b["reward"] as Dictionary).get("cosmetics", []):
			if not cosmetic_sources.has(String(c)):
				cosmetic_sources[String(c)] = []
			(cosmetic_sources[String(c)] as Array).append(String(b["origin"]))
	for c in cosmetic_sources:
		if (cosmetic_sources[c] as Array).size() > 1:
			_add("error", "recompensas", "el cosmetico '%s' lo dan varias fuentes: %s" % [c, ", ".join(PackedStringArray(cosmetic_sources[c]))])
	for id in DB.cosmetics.keys():
		if not cosmetic_sources.has(String(id)):
			_add("warning", "recompensas", "el cosmetico '%s' no lo da ninguna fuente (inalcanzable)" % id)
	# 3) titulos: el mismo id dado por varias fuentes, o dos ids con el mismo nombre.
	var title_origins: Dictionary = {}
	var name_ids: Dictionary = {}
	for t in GameState.meta.title_sources():
		var tid := String(t["id"])
		if not title_origins.has(tid):
			title_origins[tid] = []
		(title_origins[tid] as Array).append(String(t["source"]))
		var nm := String(t["name"]).to_lower()
		if not name_ids.has(nm):
			name_ids[nm] = []
		if not (name_ids[nm] as Array).has(tid):
			(name_ids[nm] as Array).append(tid)
	for id in DB.achievements:
		var td = DB.achievements[id].get("title", {})
		if td is Dictionary and not String((td as Dictionary).get("id", "")).is_empty():
			var tid2 := String((td as Dictionary)["id"])
			if not title_origins.has(tid2):
				title_origins[tid2] = []
			(title_origins[tid2] as Array).append("logro %s" % id)
			var nm2 := String((td as Dictionary).get("name", "")).to_lower()
			if not name_ids.has(nm2):
				name_ids[nm2] = []
			if not (name_ids[nm2] as Array).has(tid2):
				(name_ids[nm2] as Array).append(tid2)
	for tid in title_origins:
		if (title_origins[tid] as Array).size() > 1:
			_add("error", "recompensas", "el titulo '%s' lo dan varias fuentes: %s" % [tid, ", ".join(PackedStringArray(title_origins[tid]))])
	for nm in name_ids:
		if (name_ids[nm] as Array).size() > 1:
			_add("warning", "recompensas", "varios titulos con el mismo nombre '%s': %s" % [nm, ", ".join(PackedStringArray(name_ids[nm]))])
	# 4) niveles de cuenta repetidos o fuera de rango; huecos.
	var levels_seen: Array = []
	for entry in DB.account_config().get("level_rewards", []):
		var l := int((entry as Dictionary).get("level", 0))
		if levels_seen.has(l):
			_add("error", "recompensas", "el nivel de cuenta %d tiene dos recompensas" % l)
		levels_seen.append(l)
		if l < 2 or l > int(DB.account_config().get("max_level", 1)):
			_add("error", "recompensas", "recompensa en el nivel %d, fuera de 2-%d" % [l, int(DB.account_config().get("max_level", 1))])
	# 5) una coleccion con dos tramos identicos paga dos veces lo mismo.
	for cid in DB.collections.keys():
		var tiers: Array = DB.collections[cid].get("tiers", [])
		for i in tiers.size():
			for j in range(i + 1, tiers.size()):
				if JSON.stringify((tiers[i] as Dictionary).get("reward", {})) == JSON.stringify((tiers[j] as Dictionary).get("reward", {})):
					_add("warning", "recompensas", "coleccion %s: los tramos '%s' y '%s' pagan lo mismo" % [cid, (tiers[i] as Dictionary).get("id", ""), (tiers[j] as Dictionary).get("id", "")])
	# 6) colecciones: configuracion y que sean COMPLETABLES de verdad.
	for cid in GameState.collections.ids():
		for p in GameState.collections.problems(String(cid)):
			_add("error", "recompensas", String(p))
	# 7) misiones personales: personaje y objetivo coherentes.
	var objective_types := ["battle_played", "battle_won", "boss_defeated", "evolve"]
	for m in DB.personal_missions():
		var mid := String((m as Dictionary).get("id", ""))
		var root := String((m as Dictionary).get("character", ""))
		if not DB.characters.has(root):
			_add("error", "recompensas", "mision personal %s: el personaje '%s' no existe" % [mid, root])
			continue
		var obj: Dictionary = (m as Dictionary).get("objective", {})
		if not objective_types.has(String(obj.get("type", ""))):
			_add("error", "recompensas", "mision personal %s: objetivo desconocido '%s'" % [mid, obj.get("type", "")])
		for key in ["with_all", "with_any"]:
			for other in obj.get(key, []):
				if not DB.characters.has(String(other)):
					_add("error", "recompensas", "mision personal %s: '%s' no existe" % [mid, other])
		if int((m as Dictionary).get("target", 0)) < 1:
			_add("error", "recompensas", "mision personal %s: objetivo (target) menor que 1" % mid)
		if String(obj.get("type", "")) == "evolve" and DB.special_evolution_routes_from(root).is_empty() and (DB.characters[root].get("evolution", {}) as Dictionary).is_empty():
			_add("error", "recompensas", "mision personal %s: pide evolucionar a '%s', que no tiene evolucion" % [mid, root])
		if not Families.reachable(root):
			_add("error", "recompensas", "mision personal %s: '%s' no se puede conseguir" % [mid, root])


## --- 5. Personajes imposibles de obtener ----------------------------------------------

func check_unobtainable_characters() -> void:
	for id in DB.characters.keys():
		var key := String(id)
		if not Families.reachable(key):
			_add("error", "personajes", "'%s' es IMPOSIBLE de conseguir (ni invocacion, ni tienda, ni evento, ni evolucion alcanzable)" % key)
	# Nadie nace UR ni LR: esas rarezas se consiguen SOLO evolucionando (v16).
	for id in DB.characters.keys():
		var data: Dictionary = DB.get_character(String(id))
		var born := String(data.get("rarity", ""))
		if (born == "UR" or born == "LR") and String(data.get("evolved_from", "")).is_empty() and not _is_special_target(String(id)):
			_add("error", "personajes", "'%s' nace con rareza %s: ningun personaje puede nacer UR/LR (solo SSR como maximo; UR y LR se consiguen evolucionando)" % [id, born])
	# SSR sin bloque "evolution": se quedan en SSR para siempre (no pueden despertar como UR).
	var dead_ends: Array = []
	for id in DB.characters.keys():
		var d2: Dictionary = DB.get_character(String(id))
		if String(d2.get("rarity", "")) == "SSR" and (d2.get("evolution", {}) as Dictionary).is_empty() and String(d2.get("evolved_from", "")).is_empty():
			dead_ends.append(String(id))
	if not dead_ends.is_empty():
		dead_ends.sort()
		_add("warning", "personajes", "%d personajes SSR no tienen bloque 'evolution' y no pueden llegar a UR: %s" % [dead_ends.size(), ", ".join(PackedStringArray(dead_ends))])
	# Rarezas que ningun banner activo puede dar aunque el personaje este en el pool.
	for banner in DB.all_banners():
		var bid := String((banner as Dictionary).get("id", ""))
		for p in GameState.banner_problems(bid):
			_add("error", "personajes", "banner %s: %s" % [bid, p])
	# Cada formas evolucionada declarada tiene que tener su ruta (y viceversa).
	for id in DB.characters.keys():
		var data: Dictionary = DB.characters[id]
		for child in data.get("evolves_to", []):
			if not DB.characters.has(String(child)):
				_add("error", "personajes", "'%s' evoluciona a '%s', que no existe" % [id, child])
		var parent := String(data.get("evolved_from", ""))
		if not parent.is_empty():
			if not DB.characters.has(parent):
				_add("error", "personajes", "'%s' viene de '%s', que no existe" % [id, parent])
			elif not (DB.characters[parent].get("evolves_to", []) as Array).has(String(id)):
				_add("warning", "personajes", "'%s' dice venir de '%s' pero '%s' no lo lista en evolves_to" % [id, parent, parent])
	# Personajes que ninguna coleccion de serie ni categoria cubre (nota informativa).
	var covered: Dictionary = {}
	for cid in GameState.collections.ids():
		for root in GameState.collections.members_of(String(cid)):
			covered[String(root)] = true
	var uncovered: Array = []
	for root in Families.all_roots():
		if not covered.has(String(root)):
			uncovered.append(String(root))
	if not uncovered.is_empty():
		_add("info", "personajes", "%d familias no estan en ninguna coleccion: %s" % [uncovered.size(), _short_list(uncovered)])


## --- 6. Fases mal configuradas -----------------------------------------------------------

func check_stages() -> void:
	for id in DB.stages.keys():
		_check_encounter("stage %s" % id, DB.stages[id].get("enemies", []), int(DB.stages[id].get("xp_reward", 0)), int(DB.stages[id].get("coin_reward", 0)))
	# Historia: dificultades, enlaces y desbloqueos.
	for world_id in DB.worlds.keys():
		var world: Dictionary = DB.worlds[world_id]
		var levels: Array = DB.story_levels(String(world_id))
		if levels.is_empty():
			_add("error", "fases", "mundo %s no tiene niveles" % world_id)
		var level_ids: Array = []
		for level in levels:
			level_ids.append(String((level as Dictionary).get("id", "")))
		var req := String((world.get("unlock", {}) as Dictionary).get("requires_world", ""))
		if not req.is_empty():
			if not DB.worlds.has(req):
				_add("error", "fases", "mundo %s: requiere el mundo '%s', que no existe" % [world_id, req])
			elif req == world_id:
				_add("error", "fases", "mundo %s se requiere a si mismo" % world_id)
			else:
				var need := int((world.get("unlock", {}) as Dictionary).get("requires_levels_completed", 0))
				if need > DB.story_levels(req).size():
					_add("error", "fases", "mundo %s pide %d niveles de %s y solo tiene %d (nunca se desbloquea)" % [world_id, need, req, DB.story_levels(req).size()])
		for level in levels:
			var lid := String((level as Dictionary).get("id", ""))
			var next := String((level as Dictionary).get("next", ""))
			if not next.is_empty() and not level_ids.has(next):
				_add("error", "fases", "nivel %s: 'next' apunta a '%s', que no esta en el mundo" % [lid, next])
			_check_position(lid, (level as Dictionary).get("position", {}))
			var diffs: Array = DB.difficulties_of_level(level)
			if diffs.is_empty():
				_add("error", "fases", "nivel %s no tiene dificultades" % lid)
			var orders: Array = []
			for d in diffs:
				var order := int((d as Dictionary).get("order", 0))
				if orders.has(order):
					_add("error", "fases", "nivel %s: dos dificultades con el mismo orden %d" % [lid, order])
				orders.append(order)
				_check_encounter("nivel %s/%s" % [lid, (d as Dictionary).get("id", "")], (d as Dictionary).get("enemies", []), int((d as Dictionary).get("xp_reward", 0)), int((d as Dictionary).get("coin_reward", 0)))
		# Niveles inalcanzables: solo el primero no tiene predecesor.
		var pointed: Array = []
		for level in levels:
			if not String((level as Dictionary).get("next", "")).is_empty():
				pointed.append(String((level as Dictionary).get("next", "")))
		var roots: Array = []
		for lid in level_ids:
			if not pointed.has(lid):
				roots.append(lid)
		if levels.size() > 0 and roots.size() != 1:
			_add("error", "fases", "mundo %s: %d niveles sin predecesor (%s); deberia haber exactamente 1" % [world_id, roots.size(), ", ".join(PackedStringArray(roots))])
		# Ciclos.
		var guard := 0
		var cur := String(roots[0]) if not roots.is_empty() else ""
		var visited: Array = []
		while not cur.is_empty() and guard < 100:
			guard += 1
			if visited.has(cur):
				_add("error", "fases", "mundo %s: ciclo en los niveles (%s)" % [world_id, cur])
				break
			visited.append(cur)
			cur = String(DB.world_level(String(world_id), cur).get("next", ""))
		if roots.size() == 1 and visited.size() != level_ids.size():
			_add("error", "fases", "mundo %s: %d de %d niveles no se alcanzan desde el primero" % [world_id, level_ids.size() - visited.size(), level_ids.size()])
	# Eventos.
	for event_id in DB.events.keys():
		var stages: Array = DB.event_stages(String(event_id))
		if stages.is_empty():
			_add("error", "fases", "evento %s no tiene fases" % event_id)
		var ids: Array = []
		for st in stages:
			ids.append(String((st as Dictionary).get("id", "")))
		for st in stages:
			var sid := String((st as Dictionary).get("id", ""))
			_check_encounter("evento %s/%s" % [event_id, sid], (st as Dictionary).get("enemies", []), int((st as Dictionary).get("xp_reward", 0)), int((st as Dictionary).get("coin_reward", 0)))
			var next := String((st as Dictionary).get("next", ""))
			if not next.is_empty() and not ids.has(next):
				_add("error", "fases", "evento %s: la fase %s apunta a '%s', que no existe" % [event_id, sid, next])
			var req_char := String((st as Dictionary).get("requires_party_character", ""))
			if not req_char.is_empty():
				if not DB.characters.has(req_char):
					_add("error", "fases", "evento %s/%s: exige a '%s', que no existe" % [event_id, sid, req_char])
				else:
					var want := String((st as Dictionary).get("requires_party_rarity", ""))
					if not want.is_empty() and not _form_reachable(req_char, want):
						_add("error", "fases", "evento %s/%s: exige a %s en forma %s, imposible de alcanzar" % [event_id, sid, req_char, want])
					if not Families.reachable(req_char):
						_add("error", "fases", "evento %s/%s: exige a '%s', que no se puede conseguir" % [event_id, sid, req_char])
			if int((st as Dictionary).get("requires_party_size", 0)) > GameState.PARTY_SIZE:
				_add("error", "fases", "evento %s/%s: pide un equipo de %d y el maximo es %d" % [event_id, sid, int((st as Dictionary).get("requires_party_size", 0)), GameState.PARTY_SIZE])
			if bool((st as Dictionary).get("requires_party_solo", false)) and int((st as Dictionary).get("requires_party_size", 1)) > 1:
				_add("error", "fases", "evento %s/%s: es en solitario pero pide un equipo de mas de 1" % [event_id, sid])
			var grant := String((st as Dictionary).get("grant_character", ""))
			if not grant.is_empty() and not DB.characters.has(grant):
				_add("error", "fases", "evento %s/%s: concede a '%s', que no existe" % [event_id, sid, grant])
			for drop in (st as Dictionary).get("drops", []):
				if drop is Dictionary and (drop as Dictionary).has("equipment"):
					# X.2: drop raro de objeto equipable.
					var drop_chance := float((drop as Dictionary).get("chance", 0.05))
					if not DB.equipment.has(String((drop as Dictionary)["equipment"])):
						_add("error", "fases", "evento %s/%s: suelta el objeto equipable '%s', que no existe" % [event_id, sid, (drop as Dictionary)["equipment"]])
					elif drop_chance <= 0.0 or drop_chance > 1.0:
						_add("error", "fases", "evento %s/%s: probabilidad de drop fuera de rango" % [event_id, sid])
				elif drop is Dictionary and not DB.items.has(String((drop as Dictionary).get("item", ""))):
					_add("error", "fases", "evento %s/%s: suelta '%s', que no existe" % [event_id, sid, (drop as Dictionary).get("item", "")])
			_check_position("%s/%s" % [event_id, sid], (st as Dictionary).get("position", {}))
		var reward_char := String(DB.events[event_id].get("character_reward", ""))
		if not reward_char.is_empty() and not DB.characters.has(reward_char):
			_add("error", "fases", "evento %s: premia con '%s', que no existe" % [event_id, reward_char])
	# Torres: pisos 1..n sin huecos, jefe en cada multiplo del checkpoint.
	for tower_id in DB.towers.keys():
		var floors: Array = DB.tower_floors(String(tower_id))
		var step := DB.tower_checkpoint_step(String(tower_id))
		var numbers: Array = []
		for fl in floors:
			numbers.append(int((fl as Dictionary).get("floor", 0)))
		numbers.sort()
		for i in numbers.size():
			if int(numbers[i]) != i + 1:
				_add("error", "fases", "torre %s: los pisos no son 1..%d seguidos (falla en %d)" % [tower_id, numbers.size(), int(numbers[i])])
				break
		for fl in floors:
			var n := int((fl as Dictionary).get("floor", 0))
			_check_encounter("torre %s piso %d" % [tower_id, n], (fl as Dictionary).get("enemies", []), int((fl as Dictionary).get("xp_reward", 0)), int((fl as Dictionary).get("coin_reward", 0)))
			var is_boss := bool((fl as Dictionary).get("boss", false))
			if step > 0 and n % step == 0 and not is_boss:
				_add("warning", "fases", "torre %s piso %d: es un checkpoint pero no esta marcado como jefe" % [tower_id, n])
			var item := String((fl as Dictionary).get("first_clear_item", ""))
			if not item.is_empty() and not DB.items.has(item):
				_add("error", "fases", "torre %s piso %d: da '%s', que no existe" % [tower_id, n, item])
	# Jefes con fases: cada fase tiene que declarar algo que hacer.
	for id in DB.enemies.keys():
		var phases = DB.enemies[id].get("phases", [])
		if phases is Array:
			for i in (phases as Array).size():
				var ph = (phases as Array)[i]
				if not (ph is Dictionary) or (ph as Dictionary).is_empty():
					_add("error", "fases", "enemigo %s: la fase %d esta vacia" % [id, i + 1])


func _check_encounter(label: String, enemies: Variant, xp: int, coins: int) -> void:
	if not (enemies is Array) or (enemies as Array).is_empty():
		_add("error", "fases", "%s: no tiene enemigos" % label)
		return
	for e in enemies:
		if not DB.enemies.has(String(e)):
			_add("error", "fases", "%s: el enemigo '%s' no existe" % [label, e])
	if xp < 0 or coins < 0:
		_add("error", "fases", "%s: recompensa negativa (XP %d, monedas %d)" % [label, xp, coins])
	if xp == 0 and coins == 0:
		_add("warning", "fases", "%s: no paga ni XP ni monedas" % label)


func _check_position(label: String, pos: Variant) -> void:
	if not (pos is Dictionary):
		_add("warning", "fases", "%s: sin posicion en el mapa" % label)
		return
	var x := float((pos as Dictionary).get("x", -1.0))
	var y := float((pos as Dictionary).get("y", -1.0))
	if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
		_add("error", "fases", "%s: posicion fuera del mapa (%.2f, %.2f)" % [label, x, y])


## Se puede llegar a que `id` tenga la rareza `rarity` (por nacimiento o evolucion)?
func _form_reachable(id: String, rarity: String) -> bool:
	return GameState.can_reach_rarity(id, rarity)


func _is_special_target(id: String) -> bool:
	for raw in DB.special_evolution_routes():
		if raw is Dictionary and String((raw as Dictionary).get("to", "")) == id:
			return true
	return false
