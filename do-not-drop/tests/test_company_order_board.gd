extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_order_board.gd
##
## The order board of the shed (expansion D-0804, order_board.gd + order_board_panel.gd):
## - OrderBoard.rows() lists late orders first, then the others by the time left; the closed
##   ones (delivered, failed, cancelled) go last and only the newest MAX_CLOSED are kept;
## - a row carries the customer, address, items with names, requirement keys, minutes left,
##   pay, and a state key and mark per state (every state has a mark besides its colour);
## - a delivered order is never late, whatever its due time; a malformed entry is skipped;
## - OrderBoardPanel draws the rows alone: "no orders" when empty, a card per order with its
##   mark and state, the late time in red, the closed ones without a clock, "and N more" past
##   MAX_SHOWN, and the same board in English;
## - both languages have every key the board uses.

const KEYS: Array[String] = [
	"UI_ORDER_BOARD_TITLE", "UI_ORDER_BOARD_EMPTY", "UI_ORDER_BOARD_MORE", "UI_ORDER_BOARD_ITEM",
	"UI_ORDER_BOARD_OPEN", "UI_ORDER_BOARD_PACKED", "UI_ORDER_BOARD_OUT", "UI_ORDER_BOARD_LATE",
	"UI_ORDER_BOARD_DELIVERED", "UI_ORDER_BOARD_FAILED", "UI_ORDER_BOARD_CANCELLED",
]

var _failures: int = 0
var _products: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_test_keys()
	_products = {&"mug": _product(&"mug"), &"book": _product(&"book")}
	_test_rows()
	await _test_panel()
	if _failures == 0:
		print("PASS: the order board lists every order with its state and time")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _product(id: StringName) -> ProductDefinition:
	var p := ProductDefinition.new()
	p.id = id
	p.cells = Vector3i(1, 1, 1)
	p.buy_price = 20
	return p


## An order with state `state`, created at minute 0 and due at `due`.
func _order(id: StringName, state: StringName, due: int, requirements: Array[StringName] = []) -> Dictionary:
	var order: Dictionary = Order.make(
		id, "Clara", &"centro", &"centro_house_7",
		[{"product": &"mug", "qty": 2}, {"product": &"book", "qty": 1}],
		0, _products, requirements, due,
	)
	order["state"] = state
	return order


func _ids(rows: Array[Dictionary]) -> Array:
	return rows.map(func(r: Dictionary) -> String: return String(r["order"]))


func _test_keys() -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")


func _test_rows() -> void:
	_expect(OrderBoard.rows([], 0).is_empty(), "no orders, no rows")
	var orders: Array = [
		_order(&"a", Order.STATE_OPEN, 200),
		_order(&"b", Order.STATE_PACKED, 100),
		_order(&"c", Order.STATE_LATE, 90),
		_order(&"d", Order.STATE_OUT, 150, [&"fragile"]),
		_order(&"e", Order.STATE_LATE, 50),
		{"id": "broken", "state": "nonsense"},
		"not a dictionary",
	]
	var rows: Array[Dictionary] = OrderBoard.rows(orders, 120, _products)
	_expect(_ids(rows) == ["e", "c", "b", "d", "a"], "late first, then least time left: %s" % [_ids(rows)])
	_expect(rows[0]["minutes_left"] == -70 and rows[0]["late"], "late row counts negative minutes")
	_expect(rows[2]["minutes_left"] == -20 and rows[2]["late"], "a packed order past due reads late")
	_expect(rows[3]["minutes_left"] == 30 and not rows[3]["late"], "a row in time is not late")
	var out_row: Dictionary = rows[3]
	_expect(out_row["customer"] == "Clara" and out_row["pay"] > 0, "customer and pay are carried")
	var want: Dictionary = {"street_key": "WORLD_STREET_CENTRO", "number": 7}
	_expect(out_row["address"] == want, "address: %s" % [out_row["address"]])
	_expect(out_row["items"].size() == 2 and out_row["items"][0]["qty"] == 2, "items are carried")
	_expect(out_row["requirements"] == ["WORLD_REQ_FRAGILE"], "requirement keys: %s" % [out_row["requirements"]])
	for state: StringName in Order.STATES:
		var info: Array = OrderBoard.STATE_INFO[state]
		var named: bool = TranslationServer.translate(info[0]) != info[0]
		_expect(String(info[1]) != "" and named, "%s has key and mark" % state)
	var marks: Dictionary = {}
	for info: Array in OrderBoard.STATE_INFO.values():
		marks[info[1]] = true
	_expect(marks.size() == Order.STATES.size(), "every state has its own mark")
	var closed: Array = [
		_order(&"x1", Order.STATE_DELIVERED, 10),
		_order(&"x2", Order.STATE_FAILED, 10),
		_order(&"x3", Order.STATE_CANCELLED, 10),
		_order(&"x4", Order.STATE_DELIVERED, 10),
		_order(&"live", Order.STATE_OPEN, 300),
	]
	rows = OrderBoard.rows(closed, 120)
	_expect(_ids(rows) == ["live", "x4", "x3", "x2"], "closed go last, newest first, capped: %s" % [_ids(rows)])
	_expect(not rows[1]["late"] and rows[1]["closed"], "a delivered order past due is not late")
	_expect(not rows[0]["closed"], "an open order is not closed")


func _test_panel() -> void:
	var panel: Control = (load("res://scripts/ui/order_board_panel.gd") as GDScript).new()
	root.add_child(panel)
	await process_frame
	_expect(_find(panel, "Empty") != null, "an empty board says there are no orders")
	var orders: Array = [
		_order(&"a", Order.STATE_OPEN, 200),
		_order(&"c", Order.STATE_LATE, 90, [&"urgent"]),
		_order(&"z", Order.STATE_DELIVERED, 10),
	]
	panel.refresh(OrderBoard.rows(orders, 120, _products))
	await process_frame
	_expect(_find(panel, "Empty") == null, "real rows replace the empty text")
	_expect(_text(panel, "State_c") == "!  Atrasado", "late mark and state: %s" % _text(panel, "State_c"))
	_expect(_text(panel, "State_a") == "○  Por armar", "open mark and state: %s" % _text(panel, "State_a"))
	_expect(_text(panel, "State_z") == "✓  Entregado", "delivered mark: %s" % _text(panel, "State_z"))
	_expect(_text(panel, "Who_a") == "Para Clara · Calle Central 7", "who line: %s" % _text(panel, "Who_a"))
	_expect(_text(panel, "What_c") == "mug ×2, book ×1, [Urgente]", "what line: %s" % _text(panel, "What_c"))
	_expect(_text(panel, "Time_c") == "Atrasado 30 min", "late time: %s" % _text(panel, "Time_c"))
	_expect((_find(panel, "Time_c") as Label).get_theme_color(&"font_color") == UiTheme.RED, "late time is red")
	_expect(_text(panel, "Time_a") == "Quedan 80 min", "time left: %s" % _text(panel, "Time_a"))
	_expect(_find(panel, "Time_z") == null, "a closed order has no clock")
	_expect(_text(panel, "Pay_a").begins_with("Paga $"), "pay line: %s" % _text(panel, "Pay_a"))
	TranslationServer.set_locale("en")
	panel.refresh(OrderBoard.rows(orders, 120, _products))
	await process_frame
	_expect(_text(panel, "State_a") == "○  To pack", "English state: %s" % _text(panel, "State_a"))
	TranslationServer.set_locale("es")
	var many: Array = []
	for i: int in OrderBoardPanel.MAX_SHOWN + 3:
		many.append(_order(StringName("m%02d" % i), Order.STATE_OPEN, 200 + i))
	panel.refresh(OrderBoard.rows(many, 0))
	await process_frame
	_expect(_text(panel, "More") == "Y 3 más", "overflow line: %s" % _text(panel, "More"))
	_expect(_find(panel, "State_m%02d" % OrderBoardPanel.MAX_SHOWN) == null, "cards stop at MAX_SHOWN")
	panel.queue_free()


func _find(parent: Node, node_name: String) -> Node:
	var found: Array[Node] = parent.find_children(node_name, "", true, false)
	return found[0] if not found.is_empty() else null


func _text(parent: Node, node_name: String) -> String:
	var node: Node = _find(parent, node_name)
	return (node as Label).text if node != null else "<missing %s>" % node_name
