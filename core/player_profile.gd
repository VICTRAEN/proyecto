extends RefCounted

## PERFIL DEL JUGADOR, VITRINA Y PERSONALIZACION (v16 / X.1).
##
## Reutiliza lo que ya existe: el nivel y los cosmeticos viven en core/account.gd, los
## titulos en core/meta_progress.gd y las formas de un personaje en core/families.gd.
## Aqui solo se guarda LO ELEGIDO y se validan las reglas:
##   - avatar / favorito / vitrina = una FORMA CONCRETA ya conseguida: {root, form}.
##     "form" es la rareza visual (ssr, ur, lr). Solo se puede elegir una forma que el
##     jugador tiene AHORA (o una anterior de la misma familia ya superada): un SSR que
##     aun no evoluciono nunca ofrece el icono UR/LR, y tras evolucionar si.
##   - marco, decoracion y tema = cosmeticos de data/cosmetics (tipos frame, decoration,
##     theme) que hay que tener desbloqueados (los da el nivel de cuenta).
##   - titulo = MetaProgress.equip_title (ya valida que se posea).
##
## Si un guardado trae algo que ya no es valido (un personaje retirado, una forma que no
## se posee) se descarta al cargar y al consultar; nunca rompe ni inventa nada.

const Families := preload("res://core/families.gd")
const PortraitArt := preload("res://ui/portrait.gd")

const SHOWCASE_SLOTS := 5
const FORMS := ["ssr", "ur", "lr"]
const SLOT_TYPES := ["frame", "decoration", "theme"]

var gs = null
var avatar: Dictionary = {}              # {root, form} o {}
var favorite: Dictionary = {}            # {root, form} o {}
var showcase: Array = []                 # hasta 5 {root, form}
var equipped: Dictionary = {}            # {frame, decoration, theme} -> id de cosmetico


func _init(owner = null) -> void:
	gs = owner


## --- Formas elegibles ------------------------------------------------------------

## Formas de la familia `root` que el jugador puede mostrar: [{ id, form }]. Una forma
## es elegible si es el personaje que tiene ahora (con su forma visual real) o una forma
## anterior de la misma cadena ya superada (nunca una posterior sin evolucionar).
func available_forms(root: String) -> Array:
	var out: Array = []
	if gs == null or not DB.characters.has(root):
		return out
	var owned := Families.owned_form(gs, root)
	if owned.is_empty():
		return out
	var chain: Array = Families.forms_of(root)
	var owned_index := chain.find(owned)
	for i in chain.size():
		var id := String(chain[i])
		# Solo hasta la forma poseida: las de despues de ella no se han desbloqueado.
		if i > owned_index and owned_index >= 0:
			break
		if id == owned:
			# Misma ficha que evoluciona (SSR -> UR -> LR): ofrece desde su forma base hasta la actual.
			var base_i := FORMS.find(String(DB.get_character(id).get("rarity", "R")).to_lower())
			var cur_i := FORMS.find(String(gs.form_of(id)))
			if base_i >= 0 and cur_i >= base_i:
				for f in range(base_i, cur_i + 1):
					if not _has_form(out, String(FORMS[f])):
						out.append({ "id": id, "form": String(FORMS[f]) })
				continue
		var form := _visual_form(id, id == owned)
		if form.is_empty() or _has_form(out, form):
			continue
		out.append({ "id": id, "form": form })
	return out


func _has_form(list: Array, form: String) -> bool:
	for e in list:
		if String((e as Dictionary).get("form", "")) == form:
			return true
	return false


## Forma visual de un id: la efectiva si es el poseido; la base si es una anterior.
func _visual_form(id: String, is_current: bool) -> String:
	if is_current:
		return String(gs.form_of(id))
	return String(DB.get_character(id).get("rarity", "R")).to_lower()


## Ids poseidos aptos para vitrina/avatar/favorito: una entrada por familia (raiz).
func selectable_roots() -> Array:
	var out: Array = []
	if gs == null:
		return out
	for root in Families.all_roots():
		if not available_forms(String(root)).is_empty():
			out.append(String(root))
	return out


## Es valida {root, form} AHORA? (se posee la familia y esa forma esta desbloqueada)
func is_valid_choice(choice: Dictionary) -> bool:
	if choice.is_empty():
		return false
	var root := String(choice.get("root", ""))
	var form := String(choice.get("form", ""))
	for e in available_forms(root):
		if String((e as Dictionary).get("form", "")) == form:
			return true
	return false


## Personaje real (id) que corresponde a una eleccion valida, "" si no lo es.
func character_of(choice: Dictionary) -> String:
	var root := String(choice.get("root", ""))
	var form := String(choice.get("form", ""))
	for e in available_forms(root):
		if String((e as Dictionary).get("form", "")) == form:
			return String((e as Dictionary).get("id", ""))
	return ""


## Arte que se debe pintar: el icono de esa forma si existe; si no, el que Portrait
## ya resuelva por su cadena de reserva. Nunca el de una forma no desbloqueada.
func icon_path(choice: Dictionary) -> String:
	var id := character_of(choice)
	if id.is_empty():
		return ""
	for dir in PortraitArt.art_dirs(id):
		var path := "%s%s/icon.png" % [dir, String(choice["form"])]
		if ResourceLoader.exists(path):
			return path
	return ""


## --- Avatar, favorito, vitrina ---------------------------------------------------

func set_avatar(root: String, form: String) -> bool:
	var choice := { "root": root, "form": form }
	if not is_valid_choice(choice):
		return false
	avatar = choice
	return true


func set_favorite(root: String, form: String) -> bool:
	var choice := { "root": root, "form": form }
	if not is_valid_choice(choice):
		return false
	favorite = choice
	return true


func clear_favorite() -> void:
	favorite = {}


## Pone una forma en un hueco 0..4. Una familia no puede aparecer dos veces en la vitrina
## (se mueve de hueco). Devuelve falso si la forma no esta desbloqueada o el hueco es malo.
func set_showcase_slot(slot: int, root: String, form: String) -> bool:
	if slot < 0 or slot >= SHOWCASE_SLOTS:
		return false
	var choice := { "root": root, "form": form }
	if not is_valid_choice(choice):
		return false
	_pad_showcase()
	for i in SHOWCASE_SLOTS:
		if i != slot and String((showcase[i] as Dictionary).get("root", "")) == root:
			showcase[i] = {}
	showcase[slot] = choice
	return true


func clear_showcase_slot(slot: int) -> void:
	if slot < 0 or slot >= SHOWCASE_SLOTS:
		return
	_pad_showcase()
	showcase[slot] = {}


func _pad_showcase() -> void:
	while showcase.size() < SHOWCASE_SLOTS:
		showcase.append({})
	if showcase.size() > SHOWCASE_SLOTS:
		showcase.resize(SHOWCASE_SLOTS)


## Vitrina limpia y siempre de 5 huecos: lo que ya no es valido sale vacio.
func showcase_view() -> Array:
	_pad_showcase()
	var out: Array = []
	for entry in showcase:
		out.append(entry if is_valid_choice(entry as Dictionary) else {})
	return out


## --- Cosmeticos de personalizacion -------------------------------------------------

func equip(type_name: String, id: String) -> bool:
	if not SLOT_TYPES.has(type_name):
		return false
	if id.is_empty():
		equipped.erase(type_name)
		return true
	if not gs.account.owns_cosmetic(id) or String(DB.get_cosmetic(id).get("type", "")) != type_name:
		return false
	equipped[type_name] = id
	return true


func equipped_id(type_name: String) -> String:
	var id := String(equipped.get(type_name, ""))
	if id.is_empty() or not gs.account.owns_cosmetic(id):
		return ""
	return id


## Dato de estilo del cosmetico equipado ({} si no hay): lo lee la UI, no hay colores en codigo.
func equipped_data(type_name: String) -> Dictionary:
	var id := equipped_id(type_name)
	return DB.get_cosmetic(id) if not id.is_empty() else {}


## --- Estadisticas (todo sale de datos reales, nada se guarda duplicado) ---------------

func stats() -> Dictionary:
	var by_rarity := {}
	for id in gs.roster:
		var r := String(gs.rarity_of(String(id)))
		by_rarity[r] = int(by_rarity.get(r, 0)) + 1
	return {
		"level": gs.account.level(),
		"characters": int(gs.counter_value("personajes_obtenidos")),
		"families": Families.owned_roots(gs),
		"families_total": Families.all_roots().size(),
		"by_rarity": by_rarity,
		"summons": int(gs.summon_total),
		"battles_won": int(gs.counter_value("victorias")),
		"battles_played": int(gs.counter_value("combates_jugados")),
		"stages_completed": gs.completed_stages.size(),
		"stages_total": DB.all_stages().size(),
		"evolutions": int(gs.counter_value("evoluciones")),
	}


## --- Guardado ---------------------------------------------------------------------

func to_dict() -> Dictionary:
	return { "avatar": avatar.duplicate(), "favorite": favorite.duplicate(),
		"showcase": showcase.duplicate(true), "equipped": equipped.duplicate() }


func from_dict(raw: Variant) -> void:
	avatar = {}
	favorite = {}
	showcase = []
	equipped = {}
	if not (raw is Dictionary):
		_pad_showcase()
		return
	var data: Dictionary = raw
	avatar = _clean(data.get("avatar", {}))
	favorite = _clean(data.get("favorite", {}))
	for entry in data.get("showcase", []):
		showcase.append(_clean(entry))
	_pad_showcase()
	var eq = data.get("equipped", {})
	if eq is Dictionary:
		for type_name in SLOT_TYPES:
			var id := String((eq as Dictionary).get(type_name, ""))
			if not id.is_empty() and DB.cosmetics.has(id) and String(DB.get_cosmetic(id).get("type", "")) == type_name:
				equipped[type_name] = id


func _clean(entry: Variant) -> Dictionary:
	if entry is Dictionary and DB.characters.has(String((entry as Dictionary).get("root", ""))):
		return { "root": String(entry["root"]), "form": String((entry as Dictionary).get("form", "")) }
	return {}
