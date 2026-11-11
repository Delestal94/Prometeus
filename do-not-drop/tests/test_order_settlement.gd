extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_settlement.gd
##
## Settling a delivery (expansion D-0815, order_settlement.gd), on an order of 2 units sold at 80
## plus 40 shipping (pay 200, window 60 to 300):
## - a perfect quick delivery pays in full, tips 15 %, and earns the clean and tip reputation;
## - a perfect slow one pays in full with only the clean reputation, no tip;
## - late, wrong box, broken unit and mislabeled box pay less and cost reputation, never tip;
## - the wallet gets the pay with reason order_paid and the order closes with that pay;
## - the pay is cashed at the door (D-0516): it lands in the ledger stamped with the delivery's day and
##   clock, DaySummary counts it that same day;
## - an order that is not out on the road (or unknown, or settled twice) changes nothing;
## - the result carries the customer's stars (D-0816): 5 for the quick perfect one, 4 for the slow
##   one, fewer for each failure, 0 when nothing was settled (test_order_rating covers the rules), and
##   the closed order keeps them in the book (D-0816.b); nothing settled, nothing rated.

var _failures: int = 0
var _products: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var def := ProductDefinition.new()
	def.id = &"avg"
	def.buy_price = 50
	def.cells = Vector3i(1, 1, 1)
	_products[&"avg"] = def
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_test_perfect(state)
	_test_cashed_at_the_door(state)
	_test_penalties(state)
	_test_not_deliverable(state)
	state.reset()
	if _failures == 0:
		print("PASS: delivered orders pay, tip and move the reputation")
	quit(_failures)


func _book_out() -> OrderBook:
	var book := OrderBook.new()
	book.add(Order.make(&"o1", "C", &"centro", &"h", [{"product": &"avg", "qty": 2}], 60, _products))
	book.mark_packed(&"o1", &"box1")
	book.mark_out(&"o1", &"trip1")
	return book


func _box(units: int, label: StringName = &"o1") -> PackedBox:
	var box := PackedBox.new(&"M")
	for i in units:
		box.place(_products[&"avg"], Vector3i(i, 0, 0))
	box.label_order_id = label
	return box


func _test_perfect(state: Node) -> void:
	state.new_company("Settle Co")
	var money: int = state.money
	var rep: float = state.reputation
	var book := _book_out()
	var result: Dictionary = OrderSettlement.settle(book, state, &"o1", _box(2), 70, [], _products)
	_expect(result["ok"] and result["paid"] == 200, "a perfect delivery pays in full")
	_expect(result["tip"] == 30, "and tips 15 %% (got %d)" % result["tip"])
	_expect(result["stars"] == 5, "and earns 5 stars")
	var gain: float = CompanyTuning.CLEAN_DELIVERY_REPUTATION + CompanyTuning.TIP_REPUTATION
	_expect(is_equal_approx(result["reputation"], gain), "reputation reported is clean plus tip")
	_expect(state.money == money + 230, "the wallet got pay and tip")
	_expect(is_equal_approx(state.reputation, rep + gain), "the company reputation moved by it")
	var reasons: Array = []
	for entry: Dictionary in state.ledger.slice(state.ledger.size() - 2):
		reasons.append(entry.get("reason"))
	_expect(reasons == ["order_paid", "tip"], "the ledger says order_paid then tip")
	_expect(book.state_of(&"o1") == Order.STATE_DELIVERED, "the order is closed")
	var closed: Dictionary = book.get_order(&"o1")
	_expect(closed["paid"] == 200 and closed["quality"] == 100 and closed["intact"], "closed with its pay")
	_expect(closed.get("stars") == 5, "and the book keeps its 5 stars")
	var again: Dictionary = OrderSettlement.settle(book, state, &"o1", _box(2), 70, [], _products)
	_expect(not again["ok"] and state.money == money + 230, "settling twice pays once")
	_expect(again["stars"] == 0, "and the second try has no stars")
	book.free()
	# Slow but perfect: full pay, clean reputation, no tip.
	book = _book_out()
	money = state.money
	rep = state.reputation
	var slow: Dictionary = OrderSettlement.settle(book, state, &"o1", _box(2), 250, [], _products)
	_expect(slow["ok"] and slow["paid"] == 200 and slow["tip"] == 0, "slow and perfect: no tip")
	_expect(slow["stars"] == 4, "slow and perfect: 4 stars")
	_expect(state.money == money + 200, "only the pay reached the wallet")
	_expect(
		is_equal_approx(state.reputation, rep + CompanyTuning.CLEAN_DELIVERY_REPUTATION),
		"only the clean delivery reputation"
	)
	book.free()


func _test_penalties(state: Node) -> void:
	state.new_company("Penalty Co")
	var cases: Array[Dictionary] = [
		{"name": "late", "box": _box(2), "now": 301, "broken": [], "kind": &"late"},
		{"name": "wrong box", "box": _box(1), "now": 70, "broken": [], "kind": &"wrong"},
		{"name": "broken unit", "box": _box(2), "now": 70, "broken": [&"avg"], "kind": &"broken"},
		{"name": "mislabeled", "box": _box(2, &"other"), "now": 70, "broken": [], "kind": &"mislabeled"},
	]
	for c: Dictionary in cases:
		var book := _book_out()
		var money: int = state.money
		var rep: float = state.reputation
		var result: Dictionary = OrderSettlement.settle(
			book, state, &"o1", c["box"], c["now"], c["broken"], _products
		)
		var name: String = c["name"]
		_expect(result["ok"] and c["kind"] in result["kinds"], "%s: delivered with its failure" % name)
		_expect(result["paid"] < 200 and result["lost"] == 200 - result["paid"], "%s: pays less" % name)
		_expect(result["tip"] == 0, "%s: no tip" % name)
		_expect(result["stars"] >= 1 and result["stars"] <= 3, "%s: 1 to 3 stars" % name)
		_expect(state.money == money + result["paid"], "%s: the wallet got only what it paid" % name)
		if c["kind"] == &"late":
			_expect(result["reputation"] == 0.0, "late costs money but no reputation")
		else:
			_expect(result["reputation"] < 0.0 and state.reputation < rep, "%s: costs reputation" % name)
		_expect(book.get_order(&"o1")["paid"] == result["paid"], "%s: the book keeps that pay" % name)
		_expect(book.get_order(&"o1").get("stars") == result["stars"], "%s: and those stars" % name)
		book.free()


func _test_not_deliverable(state: Node) -> void:
	state.new_company("Idle Co")
	var money: int = state.money
	var rep: float = state.reputation
	var book := OrderBook.new()
	book.add(Order.make(&"o1", "C", &"centro", &"h", [{"product": &"avg", "qty": 2}], 60, _products))
	var open: Dictionary = OrderSettlement.settle(book, state, &"o1", _box(2), 70, [], _products)
	_expect(not open["ok"] and book.state_of(&"o1") == Order.STATE_OPEN, "an open order is not settled")
	_expect(open["stars"] == 0, "and has no stars")
	_expect(not book.get_order(&"o1").has("stars"), "nor any in the book")
	var ghost: Dictionary = OrderSettlement.settle(book, state, &"nope", _box(2), 70, [], _products)
	_expect(not ghost["ok"], "an unknown order is not settled")
	_expect(not OrderSettlement.settle(null, state, &"o1", _box(2), 70, [], _products)["ok"], "no book")
	_expect(not OrderSettlement.settle(book, null, &"o1", _box(2), 70, [], _products)["ok"], "no company")
	_expect(state.money == money and state.reputation == rep, "nothing was paid or moved")
	book.free()


func _test_cashed_at_the_door(state: Node) -> void:
	state.new_company("Door Co")
	state.clock_minutes = 600
	var book := _book_out()
	var result: Dictionary = OrderSettlement.settle(book, state, &"o1", _box(2), 70, [], _products)
	var paid_entry: Dictionary = {}
	for entry: Dictionary in state.ledger:
		if entry.get("reason") == "order_paid":
			paid_entry = entry
	_expect(
		not paid_entry.is_empty() and paid_entry["day"] == state.day and paid_entry["minute"] == 600,
		"the pay is in the ledger at the day and clock of the delivery"
	)
	var summary: Dictionary = DaySummary.build(state, state.day)
	_expect(
		summary["income_by_reason"].get("order_paid", 0) == result["paid"],
		"the day summary counts the pay of a delivery made that day"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
