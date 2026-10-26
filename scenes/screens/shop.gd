extends Control

const NAV := preload("res://scenes/nav.gd")
const WalletChip := preload("res://ui/wallet_chip.gd")
const VI := preload("res://ui/visual_identity.gd")
const ShopIcon := preload("res://ui/shop_icon.gd")
const Portrait := preload("res://ui/portrait.gd")
const TypeColors := preload("res://ui/type_colors.gd")

## TIENDA: gastar lo que el jugador ha ganado.
##
## IDENTIDAD PROPIA. No es una lista mas con otro titulo: es un PUESTO DE MERCADO.
##   - el dorado es el color protagonista (fondo, precios y boton de compra);
##   - los articulos se agrupan en ESTANTES por lo que entregan (monedas, gemas,
##     materiales, personajes), con su rotulo;
##   - cada articulo lleva una ETIQUETA DE PRECIO grande en la esquina, que es lo
##     primero que se mira en una tienda;
##   - comprar abre un PANEL DE COMPRA que ensena que te llevas y cuanto pagas,
##     en vez de cobrar de un toque.
##
## Todo sale de res://data/shop/*.json (nombre, descripcion, costes y recompensa):
## anadir un articulo es crear su JSON, nunca tocar esta pantalla.
##
## Quien cobra y quien entrega es GameState.buy_shop_item: aqui solo se pinta el
## informe que devuelve. No hay ninguna comprobacion de saldo escrita en la UI.

@onready var title_label: Label = $Margin/Main/Header/Title
@onready var subtitle_label: Label = $Margin/Main/Subtitle
@onready var shelves: VBoxContainer = $Margin/Main/Scroll/Shelves
@onready var back_button: Button = $Margin/Main/BackButton
@onready var confirm_layer: Control = $ConfirmLayer

## Ultimo informe de compra, para pintarlo bajo la cabecera.
var _last_purchase: Dictionary = {}
var _coins_chip: Control = null
var _gems_chip: Control = null
var _confirm_panel: PanelContainer = null
var _confirm_title: Label = null
var _confirm_body: Label = null
var _confirm_buy: Button = null
var _confirm_cancel: Button = null
var _pending_id := ""


func _ready() -> void:
	_apply_identity()
	back_button.pressed.connect(_back)
	_build_confirm_panel()


## Aspecto estatico. El dorado manda aqui: es la pantalla del dinero.
func _apply_identity() -> void:
	VI.screen_title(title_label, VI.GOLD)
	VI.style_subtitle(subtitle_label)
	back_button.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	VI.tint_button(back_button, VI.BLUE)
	# Cartera: dos placas con icono (monedas a la izquierda, gemas a la derecha).
	var wallet := HBoxContainer.new()
	wallet.name = "Wallet"
	wallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coins_chip = WalletChip.make("coin", GameState.coins, VI.GOLD)
	_gems_chip = WalletChip.make("gem", GameState.gems, VI.CYAN)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet.add_child(_coins_chip)
	wallet.add_child(gap)
	wallet.add_child(_gems_chip)
	var header: Node = title_label.get_parent()
	while header != null and header.get_parent() != subtitle_label.get_parent():
		header = header.get_parent()
	var host: Node = subtitle_label.get_parent()
	host.add_child(wallet)
	host.move_child(wallet, header.get_index() + 1)


func refresh() -> void:
	_update_wallet()
	_build()


func _update_wallet() -> void:
	_coins_chip.call("set_value", GameState.coins)
	_gems_chip.call("set_value", GameState.gems)


## --- Construccion -----------------------------------------------------------

func _build() -> void:
	_clear(shelves)
	var items := _shop_items()
	if items.is_empty():
		subtitle_label.text = "La tienda esta vacia."
		return
	subtitle_label.text = "Compra con monedas o gemas. Todo lo que entrega un articulo esta en sus datos."
	if not _last_purchase.is_empty():
		shelves.add_child(_make_receipt())
	for shelf in _shelves_of(items):
		shelves.add_child(_make_shelf_head(String(shelf["title"]), String(shelf["note"])))
		# Estante = rejilla de 2 puestos de mercado, no una lista de filas.
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shelves.add_child(grid)
		for raw_item in shelf["items"]:
			grid.add_child(_make_item_row(raw_item))


## Los articulos de la tienda, ordenados por nombre.
func _shop_items() -> Array:
	var out: Array = []
	for raw in DB.all_shop_items():
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			out.append(raw)
	out.sort_custom(func(a, b): return String(a.get("name", "")) < String(b.get("name", "")))
	return out


## Agrupa los articulos en ESTANTES segun lo que entregan. El estante sale del
## campo "grant.type" del JSON, asi que un articulo nuevo cae solo en su sitio.
func _shelves_of(items: Array) -> Array:
	var order := ["coins", "gems", "materials", "character", "item"]
	var titles := {
		"coins": { "title": "MONEDAS", "note": "Para subir niveles y evolucionar." },
		"gems": { "title": "GEMAS", "note": "La moneda de las invocaciones." },
		"materials": { "title": "MATERIALES", "note": "Mejoras y objetos de progreso." },
		"character": { "title": "PERSONAJES", "note": "Fichas directas: si ya lo tienes, cuenta como duplicado." },
		"item": { "title": "OBJETOS", "note": "Objetos que van a tu mochila." },
	}
	var shelves: Array = []
	for kind in order:
		var bucket: Array = []
		for raw in items:
			if _grant_kind(raw) == kind:
				bucket.append(raw)
		if bucket.is_empty():
			continue
		var meta: Dictionary = titles.get(kind, { "title": kind.to_upper(), "note": "" })
		shelves.append({ "title": meta["title"], "note": meta["note"], "items": bucket })
	# Un tipo desconocido no se pierde: se ensena en un estante al final.
	var leftovers: Array = []
	for raw in items:
		if not order.has(_grant_kind(raw)):
			leftovers.append(raw)
	if not leftovers.is_empty():
		shelves.append({ "title": "VARIOS", "note": "", "items": leftovers })
	return shelves


func _grant_kind(item: Dictionary) -> String:
	var grant = item.get("grant", {})
	if not (grant is Dictionary):
		return ""
	return String((grant as Dictionary).get("type", ""))


## Rotulo de estante: placa dorada angulada con el nombre, y su nota debajo.
func _make_shelf_head(title_text: String, note_text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var bar := PanelContainer.new()
	var style := VI.chip(VI.GOLD, 0.95)
	style.edge_width = 3.0
	style.cut = 12.0
	style.cut_corners = 15
	style.studs = true
	style.stud_color = VI.GOLD_LIGHT
	style.gloss = 0.25
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	bar.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = title_text
	VI.style_title(label, VI.FONT_SECTION)
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(label)
	box.add_child(bar)

	if not note_text.is_empty():
		var note := Label.new()
		note.text = note_text
		note.add_theme_font_size_override("font_size", VI.FONT_TINY)
		note.add_theme_color_override("font_color", VI.INK_SOFT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(note)
	return box


## Una fila de articulo: nombre y descripcion a la izquierda, ETIQUETA DE PRECIO
## grande en el medio y el boton de compra a la derecha. Todo el bloque es un
## boton, para que se pueda pulsar en cualquier sitio de la fila.
func _make_item_row(item: Dictionary) -> Control:
	var price_coins := maxi(0, int(item.get("cost_coins", 0)))
	var price_gems := maxi(0, int(item.get("cost_gems", 0)))
	var affordable := GameState.coins >= price_coins and GameState.gems >= price_gems
	var accent: Color = VI.GOLD if affordable else VI.INK_DIM

	# PUESTO DE MERCADO: ilustracion arriba, nombre, lo que entrega, precio y compra.
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Puesto de mercado: marco dorado biselado si se puede comprar; cromo apagado si no.
	var style := VI.panel(0.80, true, VI.RADIUS_PANEL)
	if affordable:
		style.metal_light = VI.METAL_GOLD_LIGHT
		style.metal_dark = VI.METAL_GOLD_DARK
		style.edge_width = 4.0
		style.studs = true
		style.stud_color = VI.GOLD_LIGHT
		style.glow = Color(VI.GOLD.r, VI.GOLD.g, VI.GOLD.b, 0.30)
		style.glow_size = 10.0
	tile.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	tile.add_child(box)

	var grant: Dictionary = item.get("grant", {}) if item.get("grant", {}) is Dictionary else {}
	var kind := String(grant.get("type", ""))
	var art_holder := Control.new()
	art_holder.custom_minimum_size = Vector2(0, 120)
	art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(art_holder)
	if kind == "character":
		var cid := String(grant.get("character_id", ""))
		var cdata: Dictionary = DB.get_character(cid)
		var art := Portrait.new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_holder.add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.setup(cid, TypeColors.color_for(String(cdata.get("type", "STR"))),
			String(cdata.get("portrait_style", "short")), Portrait.art_path_from(cdata, "front"), "front", "")
	else:
		var icon := Control.new()
		icon.set_script(ShopIcon)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_holder.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.call("setup", kind, int(grant.get("amount", 1)), VI.GOLD if kind != "gems" else Color(0.55, 0.9, 1.0))

	var name_label := Label.new()
	name_label.text = String(item.get("name", String(item.get("id", ""))))
	name_label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	name_label.add_theme_color_override("font_color", VI.INK if affordable else VI.INK_DIM)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	var granted := _grant_text(item)
	if not granted.is_empty():
		var grant_label := Label.new()
		grant_label.text = "x " + granted
		grant_label.add_theme_font_size_override("font_size", VI.FONT_TINY)
		grant_label.add_theme_color_override("font_color", VI.GREEN if affordable else VI.INK_DIM)
		grant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grant_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(grant_label)

	box.add_child(_make_price_tag(price_coins, price_gems, affordable))

	var buy := Button.new()
	buy.text = "COMPRAR"
	buy.custom_minimum_size = Vector2(0.0, 64.0)
	buy.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	VI.tint_button(buy, VI.GOLD if affordable else VI.INK_DIM)
	buy.disabled = not affordable
	buy.pressed.connect(_ask_confirm.bind(String(item.get("id", ""))))
	box.add_child(buy)
	return tile


func _make_price_tag(price_coins: int, price_gems: int, affordable: bool) -> Control:
	var holder := VBoxContainer.new()
	holder.custom_minimum_size = Vector2(0.0, 0.0)
	holder.add_theme_constant_override("separation", 2)

	if price_coins > 0:
		holder.add_child(_price_line("%d" % price_coins, "MONEDAS", VI.GOLD, affordable))
	if price_gems > 0:
		holder.add_child(_price_line("%d" % price_gems, "GEMAS", Color(0.55, 0.9, 1.0, 1.0), affordable))
	if price_coins <= 0 and price_gems <= 0:
		holder.add_child(_price_line("GRATIS", "", VI.GREEN, true))
	return holder


func _price_line(amount: String, unit: String, color: Color, affordable: bool) -> Control:
	# Precio con el icono de su moneda: se reconoce de un vistazo sin leer la unidad.
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	var icon_name := "gem" if unit == "GEMAS" else ("coin" if unit == "MONEDAS" else "")
	if not icon_name.is_empty() and VI.has_icon(icon_name):
		var icon := VI.icon_rect(icon_name, 40.0)
		icon.modulate = Color.WHITE if affordable else Color(0.55, 0.55, 0.62, 0.8)
		box.add_child(icon)
	var value := Label.new()
	value.text = amount
	value.add_theme_font_size_override("font_size", VI.FONT_SECTION)
	value.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.35) if affordable else VI.INK_DIM)
	value.add_theme_color_override("font_outline_color", Color(0.04, 0.0, 0.10, 0.85))
	value.add_theme_constant_override("outline_size", 4)
	box.add_child(value)
	if unit.is_empty() or VI.has_icon(icon_name):
		return box
	var unit_label := Label.new()
	unit_label.text = unit
	unit_label.add_theme_font_size_override("font_size", VI.FONT_TINY)
	unit_label.add_theme_color_override("font_color", VI.INK_DIM)
	box.add_child(unit_label)
	return box


## Texto de lo que entrega un articulo, para que se sepa que se compra.
func _grant_text(item: Dictionary) -> String:
	var grant = item.get("grant", {})
	if not (grant is Dictionary) or (grant as Dictionary).is_empty():
		return ""
	var data: Dictionary = grant
	var kind := String(data.get("type", ""))
	var amount := int(data.get("amount", 1))
	match kind:
		"coins":
			return "%d monedas" % amount
		"gems":
			return "%d gemas" % amount
		"materials":
			return "%d materiales" % amount
		"character":
			return GameState.display_name(String(data.get("character_id", "")))
		"item":
			return "%d x %s" % [amount, GameState.item_display_name(String(data.get("item", "")))]
	return ""


## Recibo de la ultima compra, en una franja verde.
func _make_receipt() -> Control:
	var ok := bool(_last_purchase.get("ok", false))
	var bar := PanelContainer.new()
	var style := VI.panel(0.95, true, VI.RADIUS_CHIP)
	var accent: Color = VI.GREEN if ok else VI.RED
	style.set_border_width_all(3)
	style.border_color = accent
	bar.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	if ok:
		var granted: Dictionary = _last_purchase.get("granted", {})
		label.text = "COMPRADO: %s  -  has recibido %s" % [
			String(_last_purchase.get("name", "")), String(granted.get("text", ""))]
	else:
		label.text = String(_last_purchase.get("reason", "No se pudo comprar."))
	label.add_theme_font_size_override("font_size", VI.FONT_SMALL)
	label.add_theme_color_override("font_color", accent)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(label)
	return bar


## --- Panel de compra --------------------------------------------------------

## El panel se construye UNA vez y se rellena en cada compra: asi no se crean
## nodos nuevos cada vez que el jugador toca un articulo.
func _build_confirm_panel() -> void:
	confirm_layer.visible = false
	confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP

	# Telon oscuro: el resto de la tienda queda apagado y no recibe toques.
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.04, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm_layer.add_child(center)

	_confirm_panel = PanelContainer.new()
	var style := VI.panel(0.99, true, VI.RADIUS_PANEL)
	style.set_border_width_all(4)
	style.border_color = VI.GOLD
	_confirm_panel.add_theme_stylebox_override("panel", style)
	_confirm_panel.custom_minimum_size = Vector2(840, 0)
	center.add_child(_confirm_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_confirm_panel.add_child(box)

	_confirm_title = Label.new()
	_confirm_title.add_theme_font_size_override("font_size", VI.FONT_BIG)
	_confirm_title.add_theme_color_override("font_color", VI.GOLD)
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_confirm_title)

	_confirm_body = Label.new()
	_confirm_body.add_theme_font_size_override("font_size", VI.FONT_BODY)
	_confirm_body.add_theme_color_override("font_color", VI.INK_SOFT)
	_confirm_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_confirm_body)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	box.add_child(buttons)

	_confirm_cancel = Button.new()
	_confirm_cancel.text = "CANCELAR"
	_confirm_cancel.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	_confirm_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VI.tint_button(_confirm_cancel, VI.INK_DIM)
	_confirm_cancel.pressed.connect(_close_confirm)
	buttons.add_child(_confirm_cancel)

	_confirm_buy = Button.new()
	_confirm_buy.text = "COMPRAR"
	_confirm_buy.custom_minimum_size = Vector2(0.0, VI.TOUCH)
	_confirm_buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VI.tint_button(_confirm_buy, VI.GOLD)
	_confirm_buy.pressed.connect(_do_buy)
	buttons.add_child(_confirm_buy)


## Abre el panel con lo que se va a comprar. La compra NO se hace aqui: se
## pregunta antes, que es lo que evita un gasto de un toque sin querer.
func _ask_confirm(item_id: String) -> void:
	var item := DB.get_shop_item(item_id)
	if item.is_empty():
		return
	_pending_id = item_id
	_confirm_title.text = String(item.get("name", item_id))
	var coins := maxi(0, int(item.get("cost_coins", 0)))
	var gems := maxi(0, int(item.get("cost_gems", 0)))
	var parts := PackedStringArray()
	if coins > 0:
		parts.append("%d monedas" % coins)
	if gems > 0:
		parts.append("%d gemas" % gems)
	var price := "Gratis" if parts.is_empty() else "Precio: %s" % ", ".join(parts)
	var grant := _grant_text(item)
	var body := price
	if not grant.is_empty():
		body += "\nRecibes: %s" % grant
	body += "\nTienes: %d monedas y %d gemas" % [GameState.coins, GameState.gems]
	_confirm_body.text = body
	confirm_layer.visible = true
	GameAudio.play("open")


func _close_confirm() -> void:
	confirm_layer.visible = false
	_pending_id = ""
	GameAudio.play("close")


## La compra de verdad: GameState cobra, entrega y guarda, y aqui solo se pinta
## el informe. Si el informe dice que no, no se ha cobrado nada.
func _do_buy() -> void:
	if _pending_id.is_empty():
		return
	var report := GameState.buy_shop_item(_pending_id)
	_last_purchase = report
	confirm_layer.visible = false
	_pending_id = ""
	if bool(report.get("ok", false)):
		GameAudio.play("buy")
	else:
		GameAudio.play("back")
	refresh()


func _back() -> void:
	var app := NAV.app_of(self)
	if app != null and app.has_method("go_back"):
		app.call("go_back")


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
