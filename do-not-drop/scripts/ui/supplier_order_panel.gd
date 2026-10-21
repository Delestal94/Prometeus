extends Control
class_name SupplierOrderPanel
## The supplier order screen of the shed (expansion D-0603.b, "Modo Empresa").
##
## One row per product the supplier sells: name, unit price, a minus button, the units in the
## order and a plus button. Under the list: the total, the pallets the truck will bring, the day
## it arrives, and an "Order" button that calls SupplierOrderCart.submit(): the order goes into
## the SupplierSchedule for the next day and nothing is charged until each pallet is received
## (D-0503). The cart refuses what the supplier does not sell and any line past MAX_LINE_QTY; a
## wallet that does not cover the total keeps Order off and the line says so.
##
## Data comes in through open() / refresh() as one dictionary, no autoload is read, so the panel
## runs headless in a test:
##   cart: SupplierOrderCart (the one this panel edits), wallet: Object with can_afford(),
##   schedule: SupplierSchedule, day: int (today), supplier_name: String (optional),
##   can_act: bool (false on a client: Order shows disabled, with the reason, not hidden).
##
## Gamepad first: rows are two buttons (minus, plus) in a grid of focus neighbours, then Order and
## Close. Every state has a mark besides its colour: "+" more, "−" less, "✓" ordered.

## The host ordered `lines` ([{product, qty}]) for the truck of `arrival_day`. The world adapter
## replicates the calendar to the clients (D-0603.c).
signal ordered(lines: Array[Dictionary], arrival_day: int)
signal closed

## Units added or removed by one press of plus / minus.
const STEP: int = 1

var _ctx: Dictionary = {}
var _rows: Dictionary = {}
var _status_key: String = ""
var _status_args: Array = []

var _supplier_label: Label
var _rows_box: VBoxContainer
var _scroll: ScrollContainer
var _total_label: Label
var _pallets_label: Label
var _arrival_label: Label
var _status_label: Label
var _order_button: Button
var _close_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build()
	hide()


## Shows the screen for `ctx` (see the class doc) and takes focus.
func open(ctx: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clear_status()
	refresh(ctx)
	show()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	_focus_first.call_deferred()


func close() -> void:
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	closed.emit()


## Redraws the rows and totals from `ctx`; the cart keeps whatever was already in it.
func refresh(ctx: Dictionary) -> void:
	_ctx = ctx
	if _rows_box == null:
		return
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	var cart: SupplierOrderCart = _cart()
	if cart != null:
		for id: StringName in _product_ids(cart):
			_add_row(id, cart)
	_update_view()


## Adds `STEP` units of a product. Returns {"ok", "key", "args"}: when not ok the cart stays as it
## was and key / args say why (also shown on the screen).
func more(product: StringName) -> Dictionary:
	return _edit(product, STEP)


## Takes `STEP` units off a product (the line goes away at zero).
func less(product: StringName) -> Dictionary:
	return _edit(product, -STEP)


## Puts the order in the schedule for the next day: SupplierOrderCart.submit(). Returns how many
## pallets will come (0 when the screen may not act, the cart is empty or the wallet is short).
func confirm() -> int:
	if not can_confirm():
		return 0
	var cart: SupplierOrderCart = _cart()
	var pallets: int = cart.pallet_count()
	var lines: Array[Dictionary] = cart.to_array()
	var arrival: int = SupplierSchedule.arrival_day(_day())
	if not cart.submit(_ctx.get("wallet"), _ctx.get("schedule"), _day()):
		_status_key = "UI_SUPPLIER_REFUSED"
		_status_args = []
		_update_view()
		return 0
	_status_key = "UI_SUPPLIER_ORDERED"
	_status_args = [pallets, arrival]
	ordered.emit(lines, arrival)
	refresh(_ctx)
	_focus_first()
	return pallets


## True when Order would do something: the screen may act and the cart is orderable.
func can_confirm() -> bool:
	var cart: SupplierOrderCart = _cart()
	return _acts() and cart != null and _ctx.get("schedule") != null and cart.can_submit(_ctx.get("wallet"))


func qty_of(product: StringName) -> int:
	var cart: SupplierOrderCart = _cart()
	return cart.qty(product) if cart != null else 0


func more_button(product: StringName) -> Button:
	return (_rows.get(product, {}) as Dictionary).get("more")


func less_button(product: StringName) -> Button:
	return (_rows.get(product, {}) as Dictionary).get("less")


func order_button() -> Button:
	return _order_button


func close_button() -> Button:
	return _close_button


## The line under the list: the last refusal, "ordered N pallets", or the reason Order is off.
func status_text() -> String:
	return _status_label.text if _status_label != null else ""


func total_text() -> String:
	return _total_label.text if _total_label != null else ""


## Translated "key % args", tolerant of a key that takes fewer values than it was given.
static func reason_text(key: String, args: Array) -> String:
	var text: String = TranslationServer.translate(key)
	var needed: int = text.count("%")
	if needed == 0:
		return text
	var values: Array = args.duplicate()
	while values.size() < needed:
		values.append("")
	return text % values.slice(0, needed)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(700, 0), 22)
	column.add_theme_constant_override("separation", 8)
	UiTheme.title(column, tr("UI_SUPPLIER_TITLE"), 34)
	_supplier_label = UiTheme.label(column, "", 19, UiTheme.INK, true)
	_supplier_label.name = "Supplier"
	UiTheme.label(column, tr("UI_SUPPLIER_HINT"), 15, UiTheme.MUTED)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 250)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_rows_box)
	_total_label = UiTheme.label(column, "", 22, UiTheme.INK, true)
	_total_label.name = "Total"
	_pallets_label = UiTheme.label(column, "", 16, UiTheme.MUTED)
	_pallets_label.name = "Pallets"
	_arrival_label = UiTheme.label(column, "", 16, UiTheme.MUTED)
	_arrival_label.name = "Arrival"
	_status_label = UiTheme.label(column, "", 16, UiTheme.ORANGE)
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_order_button = UiTheme.button(buttons, tr("UI_SUPPLIER_ORDER"), true)
	_order_button.name = "Order"
	_order_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_order_button.pressed.connect(confirm)
	_close_button = UiTheme.button(buttons, tr("UI_SUPPLIER_CLOSE"))
	_close_button.name = "Close"
	_close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_button.pressed.connect(close)


func _add_row(product: StringName, cart: SupplierOrderCart) -> void:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % product
	row.add_theme_constant_override("separation", 8)
	_rows_box.add_child(row)
	var name_label: Label = UiTheme.label(
		row, tr("UI_SUPPLIER_ROW") % [_product_name(product), SupplierPurchase.cost(product, 1, cart.products)], 17
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.name = "Name"
	var less_btn: Button = UiTheme.button(row, "−", false, Vector2(56, 48))
	less_btn.name = "Less"
	less_btn.pressed.connect(less.bind(product))
	var qty_label: Label = UiTheme.label(row, "", 20, UiTheme.INK, true)
	qty_label.name = "Qty"
	qty_label.custom_minimum_size = Vector2(64, 0)
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var more_btn: Button = UiTheme.button(row, "+", false, Vector2(56, 48))
	more_btn.name = "More"
	more_btn.pressed.connect(more.bind(product))
	_rows[product] = {"less": less_btn, "more": more_btn, "qty": qty_label}


func _edit(product: StringName, delta: int) -> Dictionary:
	var cart: SupplierOrderCart = _cart()
	if cart == null or not _rows.has(product):
		return {"ok": false, "key": "UI_SUPPLIER_REFUSED", "args": []}
	var done: bool = cart.add(product, delta) if delta > 0 else cart.remove(product, -delta)
	var verdict: Dictionary = {"ok": done, "key": "", "args": []}
	if done:
		_clear_status()
	elif delta > 0:
		verdict = {"ok": false, "key": "UI_SUPPLIER_LINE_MAX", "args": [SupplierOrderCart.MAX_LINE_QTY]}
		_status_key = String(verdict["key"])
		_status_args = verdict["args"]
	_update_view()
	return verdict


## Units, totals, the Order button and the focus grid from the current cart.
func _update_view() -> void:
	var cart: SupplierOrderCart = _cart()
	var supplier: String = String(_ctx.get("supplier_name", ""))
	_supplier_label.text = tr("UI_SUPPLIER_FROM") % supplier if supplier != "" else ""
	for product: StringName in _rows:
		var n: int = cart.qty(product) if cart != null else 0
		var parts: Dictionary = _rows[product]
		(parts["qty"] as Label).text = ("✓ %d" % n) if n > 0 else "0"
		(parts["less"] as Button).disabled = n <= 0
	var total: int = cart.total() if cart != null else 0
	var pallets: int = cart.pallet_count() if cart != null else 0
	_total_label.text = tr("UI_SUPPLIER_TOTAL") % total
	_pallets_label.text = tr("UI_SUPPLIER_PALLETS") % pallets
	_arrival_label.text = tr("UI_SUPPLIER_ARRIVAL") % SupplierSchedule.arrival_day(_day())
	_order_button.disabled = not can_confirm()
	_status_label.text = _status_line(cart)
	_link_focus()


func _status_line(cart: SupplierOrderCart) -> String:
	if _status_key != "":
		return reason_text(_status_key, _status_args)
	if not _acts():
		return tr("UI_SUPPLIER_HOST_ONLY")
	if cart == null or cart.is_empty():
		return tr("UI_SUPPLIER_PICK")
	if not cart.can_submit(_ctx.get("wallet")):
		return tr("UI_SUPPLIER_NO_FUNDS") % cart.total()
	return ""


## Focus grid: minus and plus side by side on each row, rows top to bottom, then Order (when on)
## and Close.
func _link_focus() -> void:
	var rows: Array[Dictionary] = []
	for product: StringName in _product_ids(_cart()):
		if _rows.has(product):
			rows.append(_rows[product])
	var tail: Array[Control] = []
	if not _order_button.disabled:
		tail.append(_order_button)
	tail.append(_close_button)
	for i: int in rows.size():
		for key: String in ["less", "more"]:
			var node: Button = rows[i][key]
			var above: Control = rows[i - 1][key] if i > 0 else node
			var below: Control = rows[i + 1][key] if i + 1 < rows.size() else tail[0]
			node.focus_neighbor_top = node.get_path_to(above)
			node.focus_neighbor_bottom = node.get_path_to(below)
			node.focus_neighbor_left = node.get_path_to(rows[i]["less"])
			node.focus_neighbor_right = node.get_path_to(rows[i]["more"])
	for i: int in tail.size():
		var node: Control = tail[i]
		var up: Control = (rows.back()["more"] as Control) if i == 0 and not rows.is_empty() else tail[maxi(i - 1, 0)]
		node.focus_neighbor_top = node.get_path_to(up)
		node.focus_neighbor_bottom = node.get_path_to(node)
		node.focus_neighbor_left = node.get_path_to(tail[maxi(i - 1, 0)])
		node.focus_neighbor_right = node.get_path_to(tail[mini(i + 1, tail.size() - 1)])


func _focus_first() -> void:
	var cart: SupplierOrderCart = _cart()
	var ids: Array[StringName] = _product_ids(cart)
	if not ids.is_empty() and _rows.has(ids[0]):
		(_rows[ids[0]]["more"] as Button).grab_focus()
	else:
		_close_button.grab_focus()


## The products the supplier sells that are in the catalog, in id order.
func _product_ids(cart: SupplierOrderCart) -> Array[StringName]:
	var out: Array[StringName] = []
	if cart == null:
		return out
	for id: StringName in cart.products:
		if cart.supplier == null or cart.supplier.sells(id):
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


func _product_name(product: StringName) -> String:
	var cart: SupplierOrderCart = _cart()
	return OrderSheet.product_name(product, cart.products if cart != null else {})


func _cart() -> SupplierOrderCart:
	return _ctx.get("cart") as SupplierOrderCart


func _day() -> int:
	return int(_ctx.get("day", 0))


func _acts() -> bool:
	return bool(_ctx.get("can_act", true))


func _clear_status() -> void:
	_status_key = ""
	_status_args = []


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
