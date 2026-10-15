extends RefCounted

## DEVELOPER TOOLS - TEMPORAL. Logica de las herramientas de desarrollador.
##
## TODO lo que modifica el estado esta protegido aqui, no solo escondido en la
## interfaz: cada accion empieza por `_allowed()` y, si la herramienta no esta
## habilitada, devuelve { ok: false, reason: "..." } sin tocar nada. La habilitacion
## exige DOS condiciones a la vez:
##   1) OS.is_debug_build()  -> false en una exportacion de release (distribucion)
##   2) MASTER_SWITCH        -> interruptor de este archivo (ponlo a false, o borra la
##                              carpeta res://dev/, para apagarlo del todo)
## Para DESACTIVAR o ELIMINAR: ver res://dev/README.md.
##
## Usa las APIs de estado existentes (GameState.add_coins / add_gems / add_materials /
## add_item / add_character y save_game): no hay una segunda copia del guardado ni
## monedas nuevas. No toca probabilidades del gacha ni estadisticas de personajes.

const MASTER_SWITCH := true
const MAX_GRANT := 1000000000

## Solo para PRUEBAS: simula una compilacion de distribucion (is_debug_build() == false)
## sin tener que exportar el juego.
static var _simulate_release := false


static func simulate_release(value: bool) -> void:
	_simulate_release = value


## Esta habilitada la herramienta? (compilacion de depuracion + interruptor).
static func enabled() -> bool:
	return MASTER_SWITCH and OS.is_debug_build() and not _simulate_release


static func _denied() -> Dictionary:
	return { "ok": false, "reason": "Developer Tools no disponible en esta compilacion." }


## Recursos que existen DE VERDAD en el juego, con su saldo actual. La clave es lo que
## se pasa a grant(): "coins", "gems", "materials" y "item:<id>" por cada objeto del
## catalogo (uniformes de conejita, fichas de Mai...). No existen tickets de invocacion
## ni otra moneda premium: no se inventan.
static func resources() -> Array:
	var out: Array = [
		{ "key": "coins", "label": "Monedas", "balance": GameState.coins },
		{ "key": "gems", "label": "Gemas (invocacion)", "balance": GameState.gems },
		{ "key": "materials", "label": "Materiales de evolucion", "balance": GameState.materials },
	]
	var ids: Array = DB.items.keys()
	ids.sort()
	for id in ids:
		out.append({ "key": "item:%s" % id, "label": GameState.item_display_name(String(id)), "balance": GameState.item_count(String(id)) })
	return out


static func balance_of(key: String) -> int:
	match key:
		"coins":
			return GameState.coins
		"gems":
			return GameState.gems
		"materials":
			return GameState.materials
	if key.begins_with("item:"):
		return GameState.item_count(key.substr(5))
	return -1


## Suma `amount` a un recurso. Rechaza cantidades no positivas o absurdas y recursos
## que no existen. Guarda una sola vez con el guardado normal.
static func grant(key: String, amount: Variant) -> Dictionary:
	if not enabled():
		return _denied()
	var value := _parse_amount(amount)
	if value <= 0:
		return { "ok": false, "reason": "Cantidad invalida (hace falta un entero entre 1 y %d)." % MAX_GRANT }
	if balance_of(key) < 0:
		return { "ok": false, "reason": "Recurso desconocido: %s." % key }
	if key.begins_with("item:") and not DB.items.has(key.substr(5)):
		return { "ok": false, "reason": "Objeto desconocido: %s." % key }
	match key:
		"coins":
			GameState.add_coins(value)
		"gems":
			GameState.add_gems(value)
		"materials":
			GameState.add_materials(value)
		_:
			GameState.add_item(key.substr(5), value)
	GameState.save_game()
	return { "ok": true, "reason": "+%d" % value, "resource": key, "amount": value, "balance": balance_of(key) }


## Valida una entrada de texto o numero: solo enteros positivos sin signo ni decimales.
static func _parse_amount(raw: Variant) -> int:
	if raw == null or raw is bool:
		return -1
	if raw is float:
		return int(raw) if float(raw) == floorf(float(raw)) and float(raw) > 0.0 and float(raw) <= MAX_GRANT else -1
	if raw is int:
		return int(raw) if int(raw) <= MAX_GRANT else -1
	var text := String(raw).strip_edges().replace(".", "").replace(",", "")
	if text.is_empty() or not text.is_valid_int():
		return -1
	var value := text.to_int()
	return value if value > 0 and value <= MAX_GRANT else -1


## Anade un personaje al roster por la funcion normal del juego. Si ya lo tiene NO lo
## duplica (pulsar dos veces no da dos unidades): devuelve ok=false con el motivo.
static func add_character(id: String) -> Dictionary:
	if not enabled():
		return _denied()
	var key := id.strip_edges()
	if key.is_empty() or not DB.has_character(key):
		return { "ok": false, "reason": "No existe el personaje '%s'." % key }
	if GameState.is_owned(key):
		return { "ok": false, "reason": "Ya tienes a %s." % GameState.display_name(key), "id": key }
	var info := GameState.add_character(key)
	if not bool(info.get("added", false)):
		return { "ok": false, "reason": "No se ha podido anadir.", "id": key }
	return { "ok": true, "reason": "%s anadido (%s)." % [GameState.display_name(key), GameState.rarity_of(key)], "id": key, "rarity": GameState.rarity_of(key) }


static func quick_add_duo() -> Dictionary:
	return add_character("david_lucy_duo")
