extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_tips.gd
##
## Tips (expansion D-0507, order_tips.gd), on an order of 2 units sold at 80 plus 40 shipping
## (pay 200, window 240 min):
## - a perfect delivery in the first half of the window tips 15 % of the base pay;
## - a perfect delivery after half the window (or exactly at it, which still counts) does not;
## - any penalty (late, wrong, broken, mislabeled) cancels the tip;
## - the tip goes to the wallet with reason tip and adds its reputation, once.

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
	_test_speed()
	_test_penalty_cancels()
	_test_wallet(state)
	state.reset()
	if _failures == 0:
		print("PASS: perfect quick deliveries tip")
	quit(_failures)


func _order() -> Dictionary:
	return Order.make(&"o1", "C", &"centro", &"h", [{"product": &"avg", "qty": 2}], 60, _products)


func _box(units: int, label: StringName = &"o1") -> PackedBox:
	var box := PackedBox.new(&"M")
	for i in units:
		box.place(_products[&"avg"], Vector3i(i, 0, 0))
	box.label_order_id = label
	return box


func _tip(order: Dictionary, box: PackedBox, now_min: int, broken: Array = []) -> Dictionary:
	var verdict: Dictionary = OrderPenalties.assess(order, box, now_min, broken, _products)
	return OrderTips.assess(order, verdict, now_min)


func _test_speed() -> void:
	var order: Dictionary = _order()
	var created: int = int(order["created_min"])
	_expect(created == 60 and int(order["due_min"]) == 300, "window runs 60 to 300")
	var fast: Dictionary = _tip(order, _box(2), created + 10)
	_expect(fast["tip"] == 30, "a quick perfect delivery tips 15 %% of 200 (got %d)" % fast["tip"])
	_expect(fast["reputation"] == CompanyTuning.TIP_REPUTATION, "the tip adds reputation")
	_expect(_tip(order, _box(2), created)["tip"] == 30, "delivering the minute it came in tips")
	_expect(_tip(order, _box(2), created + 120)["tip"] == 30, "exactly half the window still tips")
	var slow: Dictionary = _tip(order, _box(2), created + 121)
	_expect(slow["tip"] == 0 and slow["reputation"] == 0.0, "past half the window: no tip")
	_expect(_tip(order, _box(2), created - 1)["tip"] == 0, "before the order existed: no tip")


func _test_penalty_cancels() -> void:
	var order: Dictionary = _order()
	var now: int = int(order["created_min"]) + 10
	_expect(_tip(order, _box(1), now)["tip"] == 0, "a wrong box does not tip")
	_expect(_tip(order, _box(2), now, [&"avg"])["tip"] == 0, "a broken unit does not tip")
	_expect(_tip(order, _box(2, &"other"), now)["tip"] == 0, "a mislabeled box does not tip")
	_expect(_tip(order, _box(2), int(order["due_min"]) + 1)["tip"] == 0, "a late delivery does not tip")
	_expect(OrderTips.assess(order, {}, now)["tip"] == 0, "no verdict, no tip")


func _test_wallet(state: Node) -> void:
	state.new_company("Tip Co")
	var money: int = state.money
	var rep: float = state.reputation
	var result: Dictionary = {"tip": 30, "reputation": 1.0}
	_expect(OrderTips.apply(state, result) == 30, "apply returns the tip paid")
	_expect(state.money == money + 30, "the wallet got the tip")
	_expect(state.reputation == rep + 1.0, "reputation moved")
	_expect(state.ledger.back().get("reason") == String(OrderTips.REASON_TIP), "the ledger says tip")
	_expect(OrderTips.apply(state, {"tip": 0, "reputation": 1.0}) == 0, "no tip pays nothing")
	_expect(state.money == money + 30 and state.reputation == rep + 1.0, "nothing else changed")
	_expect(OrderTips.apply(null, result) == 0, "no company, no payment")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
