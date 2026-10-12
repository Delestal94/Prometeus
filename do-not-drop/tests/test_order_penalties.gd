extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_penalties.gd
##
## Delivery penalties (expansion D-0506, order_penalties.gd), on an order of 2 units sold at 80
## plus 40 shipping (pay 200):
## - a perfect delivery pays everything and costs no reputation;
## - a wrong, missing or extra product pays 0 and costs WRONG_BOX_REPUTATION;
## - a broken unit loses its sell price and costs BROKEN_PRODUCT_REPUTATION each;
## - late takes LATE_PENALTY, a box labeled for another order takes MISLABEL_PAY_LOSS;
## - penalties stack, the reputation loss of one delivery is capped, and the pay never goes below 0;
## - the reputation change reaches CompanyState and stays inside its range.

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
	_test_clean_and_wrong()
	_test_broken()
	_test_late_and_label()
	_test_stacking()
	_test_reputation(state)
	state.reset()
	if _failures == 0:
		print("PASS: delivery penalties cost pay and reputation")
	quit(_failures)


func _order() -> Dictionary:
	return Order.make(&"o1", "C", &"centro", &"h", [{"product": &"avg", "qty": 2}], 0, _products)


func _box(units: int, label: StringName = &"o1") -> PackedBox:
	var box := PackedBox.new(&"M")
	for i in units:
		box.place(_products[&"avg"], Vector3i(i, 0, 0))
	box.label_order_id = label
	return box


func _test_clean_and_wrong() -> void:
	var order: Dictionary = _order()
	_expect(order["pay"] == 200, "the order pays 200")
	var ok: Dictionary = OrderPenalties.assess(order, _box(2), 100, [], _products)
	_expect(ok["pay"] == 200 and ok["lost"] == 0, "a perfect delivery pays 200")
	_expect(ok["kinds"].is_empty() and ok["reputation"] == 0.0, "no failure, no reputation loss")
	for units in [1, 3]:
		var wrong: Dictionary = OrderPenalties.assess(order, _box(units), 100, [], _products)
		_expect(wrong["pay"] == 0, "%d units instead of 2 pays 0" % units)
		_expect(wrong["kinds"] == [OrderPenalties.KIND_WRONG], "%d units is wrong" % units)
		_expect(wrong["reputation"] == CompanyTuning.WRONG_BOX_REPUTATION, "wrong box costs reputation")
	_expect(not OrderPenalties.matches_order(order, null), "no box matches nothing")


func _test_broken() -> void:
	var order: Dictionary = _order()
	var one: Dictionary = OrderPenalties.assess(order, _box(2), 100, [&"avg"], _products)
	_expect(one["pay"] == 120 and one["lost"] == 80, "one broken unit loses its 80 (got %d)" % one["pay"])
	_expect(one["kinds"] == [OrderPenalties.KIND_BROKEN], "broken is reported")
	_expect(one["reputation"] == CompanyTuning.BROKEN_PRODUCT_REPUTATION, "one broken: -5")
	var both: Dictionary = OrderPenalties.assess(order, _box(2), 100, [&"avg", &"avg"], _products)
	_expect(both["pay"] == 40, "both broken leave only the shipping (got %d)" % both["pay"])
	_expect(both["reputation"] == CompanyTuning.PENALTY_REPUTATION_CAP, "two broken: -10, the cap")
	var ghost: Dictionary = OrderPenalties.assess(order, _box(2), 100, [&"nope"], _products)
	_expect(ghost["pay"] == 200, "an unknown broken product loses no pay")


func _test_late_and_label() -> void:
	var order: Dictionary = _order()
	var late: Dictionary = OrderPenalties.assess(order, _box(2), int(order["due_min"]) + 1, [], _products)
	_expect(late["pay"] == 150 and late["kinds"] == [OrderPenalties.KIND_LATE], "late pays 150")
	_expect(late["pay"] == Order.payout(order, int(order["due_min"]) + 1), "late matches Order.payout")
	_expect(late["reputation"] == 0.0, "late costs no reputation")
	var on_time: Dictionary = OrderPenalties.assess(order, _box(2), int(order["due_min"]), [], _products)
	_expect(on_time["pay"] == 200, "on the due minute is not late")
	var label: Dictionary = OrderPenalties.assess(order, _box(2, &"other"), 100, [], _products)
	_expect(label["pay"] == 170 and label["kinds"] == [OrderPenalties.KIND_MISLABELED], "wrong label: -15 %")
	_expect(label["reputation"] == CompanyTuning.MISLABEL_REPUTATION, "wrong label costs reputation")
	var none: Dictionary = OrderPenalties.assess(order, _box(2, &""), 100, [], _products)
	_expect(none["pay"] == 170, "an unlabeled box counts as mislabeled")


func _test_stacking() -> void:
	var order: Dictionary = _order()
	var all: Dictionary = OrderPenalties.assess(
		order, _box(2, &"other"), int(order["due_min"]) + 1, [&"avg"], _products
	)
	# 200 - 80 broken = 120, x0.75 late = 90, x0.85 label = 76.5 -> 77 (roundi).
	_expect(all["pay"] == 77, "broken, late and mislabeled stack (got %d)" % all["pay"])
	_expect(all["kinds"].size() == 3, "three failures reported")
	_expect(all["reputation"] == -6.0, "reputation -5 -1 = -6")
	_expect(all["lost"] == 200 - 77, "lost is base minus pay")


func _test_reputation(state: Node) -> void:
	state.new_company("Penalty Co")
	var start: float = state.reputation
	OrderPenalties.apply_reputation(state, {"reputation": -3.0})
	_expect(state.reputation == start - 3.0, "reputation moves by the verdict")
	OrderPenalties.apply_reputation(state, {"reputation": -500.0})
	_expect(state.reputation == CompanyTuning.REPUTATION_MIN, "reputation stops at its minimum")
	state.add_reputation(500.0)
	_expect(state.reputation == CompanyTuning.REPUTATION_MAX, "reputation stops at its maximum")
	OrderPenalties.apply_reputation(null, {"reputation": -1.0})


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
