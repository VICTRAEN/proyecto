extends VBoxContainer

## DEVELOPER TOOLS - TEMPORAL. Interfaz del panel (ver res://dev/README.md).
## Solo se crea si DevTools.enabled(); aun asi, cada boton pasa por DevTools, que
## vuelve a comprobarlo antes de modificar nada.

const DevTools := preload("res://dev/dev_tools.gd")
const VI := preload("res://ui/visual_identity.gd")
const COOLDOWN_MS := 300

var _balances: Label = null
var _status: Label = null
var _amount_edit: LineEdit = null
var _resource_pick: OptionButton = null
var _id_edit: LineEdit = null
var _next_ok_ms := 0


func _ready() -> void:
	name = "DevToolsPanel"
	if not DevTools.enabled():
		queue_free()
		return
	add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.name = "DevTitle"
	title.text = "DEVELOPER TOOLS — TEMPORAL"
	title.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	title.add_theme_color_override("font_color", VI.RED)
	add_child(title)
	var warn := Label.new()
	warn.text = "Solo compilaciones de depuracion. Quitar antes de distribuir (res://dev/README.md)."
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	VI.style_note(warn)
	add_child(warn)
	_balances = Label.new()
	_balances.name = "DevBalances"
	_balances.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_balances.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	add_child(_balances)

	_add_quick_row([["+1.000 monedas", "coins", 1000], ["+10.000 monedas", "coins", 10000]])
	_add_quick_row([["+100 gemas", "gems", 100], ["+1.000 gemas", "gems", 1000]])
	_add_quick_row([["+50 materiales", "materials", 50]])
	_add_quick_row([["+25 uniformes", "item:rabbit_costume", 25], ["+3 fichas Mai", "item:mai_token", 3]])

	var custom := HBoxContainer.new()
	custom.add_theme_constant_override("separation", 8)
	add_child(custom)
	_resource_pick = OptionButton.new()
	_resource_pick.name = "DevResourcePick"
	_resource_pick.custom_minimum_size = Vector2(0, 80)
	_resource_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in DevTools.resources():
		_resource_pick.add_item(String(entry["label"]))
		_resource_pick.set_item_metadata(_resource_pick.item_count - 1, String(entry["key"]))
	custom.add_child(_resource_pick)
	_amount_edit = LineEdit.new()
	_amount_edit.name = "DevAmountEdit"
	_amount_edit.placeholder_text = "cantidad"
	_amount_edit.custom_minimum_size = Vector2(190, 80)
	custom.add_child(_amount_edit)
	var add := Button.new()
	add.name = "DevAddButton"
	add.text = "ANADIR"
	add.custom_minimum_size = Vector2(170, 80)
	VI.tint_button(add, VI.GOLD)
	add.pressed.connect(_on_add_custom)
	custom.add_child(add)

	var chars := HBoxContainer.new()
	chars.add_theme_constant_override("separation", 8)
	add_child(chars)
	_id_edit = LineEdit.new()
	_id_edit.name = "DevCharacterEdit"
	_id_edit.placeholder_text = "id de personaje"
	_id_edit.custom_minimum_size = Vector2(0, 80)
	_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chars.add_child(_id_edit)
	var add_char := Button.new()
	add_char.name = "DevAddCharacterButton"
	add_char.text = "ANADIR PERSONAJE"
	add_char.custom_minimum_size = Vector2(300, 80)
	VI.tint_button(add_char, VI.BLUE)
	add_char.pressed.connect(_on_add_character)
	chars.add_child(add_char)
	var duo := Button.new()
	duo.name = "DevAddDuoButton"
	duo.text = "ANADIR DAVID & LUCY (SSR)"
	duo.custom_minimum_size = Vector2(0, 80)
	VI.tint_button(duo, VI.VIOLET)
	duo.pressed.connect(_on_add_duo)
	add_child(duo)
	_status = Label.new()
	_status.name = "DevStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	add_child(_status)
	_refresh_balances()


func _add_quick_row(entries: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for entry in entries:
		var button := Button.new()
		button.text = String(entry[0])
		button.name = "Dev_%s_%d" % [String(entry[1]).replace(":", "_"), int(entry[2])]
		button.custom_minimum_size = Vector2(0, 80)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", VI.FONT_SMALL)
		VI.tint_button(button, VI.GOLD)
		button.pressed.connect(_do_grant.bind(String(entry[1]), int(entry[2])))
		row.add_child(button)


## Antirrebote: un doble toque no concede dos veces.
func _debounced() -> bool:
	var now := Time.get_ticks_msec()
	if now < _next_ok_ms:
		return false
	_next_ok_ms = now + COOLDOWN_MS
	return true


func _do_grant(key: String, amount: Variant) -> void:
	if not _debounced():
		return
	_show(DevTools.grant(key, amount))


func _on_add_custom() -> void:
	if not _debounced():
		return
	var key := String(_resource_pick.get_item_metadata(_resource_pick.selected))
	_show(DevTools.grant(key, _amount_edit.text))


func _on_add_character() -> void:
	if not _debounced():
		return
	_show(DevTools.add_character(_id_edit.text))


func _on_add_duo() -> void:
	if not _debounced():
		return
	_show(DevTools.quick_add_duo())


func _show(result: Dictionary) -> void:
	var text := String(result.get("reason", ""))
	if bool(result.get("ok", false)) and result.has("balance"):
		text = "%s  ->  saldo %s: %d" % [text, String(result.get("resource", "")), int(result.get("balance", 0))]
	_status.text = text
	_status.add_theme_color_override("font_color", VI.GREEN if bool(result.get("ok", false)) else VI.RED)
	_refresh_balances()


func _refresh_balances() -> void:
	var parts := PackedStringArray()
	for entry in DevTools.resources():
		parts.append("%s: %d" % [String(entry["label"]), int(entry["balance"])])
	_balances.text = "   |   ".join(parts)
