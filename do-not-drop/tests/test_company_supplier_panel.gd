extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_supplier_panel.gd
##
## The supplier order screen (expansion D-0603.b, supplier_order_panel.gd), driven by injected data
## only:
## - one row per product the supplier sells (a product it does not sell has none); plus / minus
##   change the units, the total and the pallet count follow, and a line shows "✓" when it has units;
## - Order puts the order in the SupplierSchedule for the next day (the truck of day + 1 carries
##   those pallets), charges nothing, empties the cart and emits `ordered` with the lines;
## - an empty cart or a wallet that does not cover the total keeps Order off and the line says why;
## - a line past MAX_LINE_QTY is refused with the reason and stays as it was;
## - a client (can_act false) sees Order disabled with the reason and orders nothing;
## - the focus starts on the first row, ui_accept on plus adds a unit, ui_down walks the column to
##   Order and Close; every focus neighbour points at a live node; ui_cancel closes the screen;
## - both languages have every key the screen uses.

const KEYS: Array[String] = [
	"UI_SUPPLIER_TITLE", "UI_SUPPLIER_FROM", "UI_SUPPLIER_HINT", "UI_SUPPLIER_ROW",
	"UI_SUPPLIER_TOTAL", "UI_SUPPLIER_PALLETS", "UI_SUPPLIER_ARRIVAL", "UI_SUPPLIER_PICK",
	"UI_SUPPLIER_NO_FUNDS", "UI_SUPPLIER_LINE_MAX", "UI_SUPPLIER_REFUSED", "UI_SUPPLIER_ORDERED",
	"UI_SUPPLIER_HOST_ONLY", "UI_SUPPLIER_ORDER", "UI_SUPPLIER_CLOSE",
]

var _failures: int = 0
var _ordered: Array = []


class Wallet:
	extends RefCounted
	var money: int = 0

	func can_afford(amount: int) -> bool:
		return amount <= money


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_test_keys()
	await _test_edit_and_order()
	await _test_refusals()
	await _test_client()
	await _test_focus_and_cancel()
	if _failures == 0:
		print("PASS: the supplier screen edits the cart and orders the next-day pallets")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _ctx(money: int, can_act: bool = true) -> Dictionary:
	var lamp := ProductDefinition.new()
	lamp.id = &"lamp"
	lamp.buy_price = 50
	var vase := ProductDefinition.new()
	vase.id = &"vase"
	vase.buy_price = 20
	var other := ProductDefinition.new()
	other.id = &"other"
	other.buy_price = 5
	var seller := SupplierDefinition.new()
	seller.id = &"s"
	seller.products = [&"lamp", &"vase"]
	var cart := SupplierOrderCart.new()
	cart.supplier = seller
	cart.products = {&"lamp": lamp, &"vase": vase, &"other": other}
	var wallet := Wallet.new()
	wallet.money = money
	return {
		"cart": cart, "wallet": wallet, "schedule": SupplierSchedule.new(), "day": 3,
		"supplier_name": "Distribuidora", "can_act": can_act,
	}


func _panel(ctx: Dictionary) -> SupplierOrderPanel:
	var panel := SupplierOrderPanel.new()
	root.add_child(panel)
	_ordered.clear()
	panel.ordered.connect(func(lines: Array[Dictionary], day: int) -> void: _ordered.append([lines, day]))
	panel.open(ctx)
	await process_frame
	await process_frame
	return panel


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		root.push_input(event)
	await process_frame


func _focus_name() -> String:
	var owner: Control = root.gui_get_focus_owner()
	return String(owner.name) if owner != null else ""


func _test_keys() -> void:
	var rows: Dictionary = {}
	var file := FileAccess.open("res://translations/strings_ui.csv", FileAccess.READ)
	while not file.eof_reached():
		var cols: PackedStringArray = file.get_csv_line()
		if cols.size() >= 3:
			rows[cols[0]] = cols
	for key: String in KEYS:
		var both: bool = rows.has(key) and rows[key][1] != "" and rows[key][2] != ""
		_expect(both, "translation row with both languages: " + key)


func _test_edit_and_order() -> void:
	var ctx: Dictionary = _ctx(1000)
	var panel: SupplierOrderPanel = await _panel(ctx)
	_expect(panel.more_button(&"lamp") != null and panel.more_button(&"vase") != null, "a row per product sold")
	_expect(panel.more_button(&"other") == null, "no row for a product the supplier does not sell")
	_expect(panel.order_button().disabled, "Order starts off with an empty cart")
	_expect(panel.less_button(&"lamp").disabled, "minus is off at zero")
	for i: int in 3:
		_expect(panel.more(&"lamp")["ok"], "plus adds a lamp")
	panel.more(&"vase")
	_expect(panel.qty_of(&"lamp") == 3 and panel.qty_of(&"vase") == 1, "units follow the presses")
	_expect(panel.total_text().contains("170"), "total is 3 x 50 + 20")
	_expect(not panel.order_button().disabled, "Order is on with funds")
	panel.less(&"vase")
	_expect(panel.qty_of(&"vase") == 0, "minus takes the vase line off")
	var wallet: Wallet = ctx["wallet"]
	var pallets: int = panel.confirm()
	_expect(pallets == 1, "one pallet for 3 lamps (got %d)" % pallets)
	_expect(wallet.money == 1000, "nothing is charged on ordering")
	_expect((ctx["cart"] as SupplierOrderCart).is_empty(), "the cart is empty after ordering")
	var schedule: SupplierSchedule = ctx["schedule"]
	_expect(schedule.has_delivery(SupplierSchedule.arrival_day(3)), "the truck of day + 1 is booked")
	_expect(int(schedule.ordered_for(SupplierSchedule.arrival_day(3)).get("lamp", 0)) == 3, "it carries the 3 lamps")
	_expect(_ordered.size() == 1 and int(_ordered[0][1]) == SupplierSchedule.arrival_day(3), "ordered emitted once")
	_expect(panel.status_text().contains("1"), "the line says how many pallets came")
	panel.queue_free()


func _test_refusals() -> void:
	var ctx: Dictionary = _ctx(60)
	var panel: SupplierOrderPanel = await _panel(ctx)
	_expect(panel.status_text() != "", "empty cart says to pick something")
	panel.more(&"lamp")
	panel.more(&"lamp")
	_expect(panel.order_button().disabled, "100 does not fit in 60: Order is off")
	_expect(panel.status_text().contains("100"), "the line gives the total that does not fit")
	var booked: SupplierSchedule = ctx["schedule"]
	_expect(panel.confirm() == 0 and booked.upcoming_days(0).is_empty(), "no order without funds")
	var cart: SupplierOrderCart = ctx["cart"]
	cart.set_qty(&"lamp", SupplierOrderCart.MAX_LINE_QTY)
	var verdict: Dictionary = panel.more(&"lamp")
	var capped: bool = not verdict["ok"] and String(verdict["key"]) == "UI_SUPPLIER_LINE_MAX"
	_expect(capped, "past the line cap is refused with the reason")
	_expect(cart.qty(&"lamp") == SupplierOrderCart.MAX_LINE_QTY, "the refused press leaves the line alone")
	panel.queue_free()


func _test_client() -> void:
	var ctx: Dictionary = _ctx(1000, false)
	var panel: SupplierOrderPanel = await _panel(ctx)
	panel.more(&"lamp")
	_expect(panel.order_button().disabled, "a client cannot press Order")
	_expect(panel.status_text() == TranslationServer.translate("UI_SUPPLIER_HOST_ONLY"), "and is told why")
	_expect(panel.confirm() == 0 and _ordered.is_empty(), "a client orders nothing")
	panel.queue_free()


func _test_focus_and_cancel() -> void:
	var ctx: Dictionary = _ctx(1000)
	var panel: SupplierOrderPanel = await _panel(ctx)
	_expect(_focus_name() == "More", "focus starts on the first row's plus")
	await _press(&"ui_accept")
	_expect(panel.qty_of(&"lamp") == 1, "ui_accept on plus adds a unit")
	await _press(&"ui_down")
	_expect(_focus_name() == "More", "ui_down moves to the next row")
	await _press(&"ui_down")
	_expect(_focus_name() == "Order", "then to Order (on, the cart has a line)")
	await _press(&"ui_down")
	_expect(_focus_name() == "Order", "Order is the bottom of the column")
	await _press(&"ui_right")
	_expect(_focus_name() == "Close", "right goes to Close")
	var all: Array[Control] = [
		panel.more_button(&"lamp"), panel.less_button(&"lamp"), panel.order_button(), panel.close_button()
	]
	for node: Control in all:
		var paths: Array[NodePath] = [
			node.focus_neighbor_top, node.focus_neighbor_bottom, node.focus_neighbor_left, node.focus_neighbor_right
		]
		for path: NodePath in paths:
			_expect(node.get_node_or_null(path) != null, "focus neighbour of %s points at a live node" % node.name)
	await _press(&"ui_cancel")
	_expect(not panel.visible, "ui_cancel closes the screen")
	panel.queue_free()
