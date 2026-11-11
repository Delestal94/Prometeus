extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_waiting.gd
##
## OrderWaiting (expansion D-0811, order_waiting.gd), orders the shed cannot cover today:
## - an order whose products are all in free stock is ready; one that lacks units waits
##   and names what it lacks;
## - two orders for the same last units: the earlier due is ready, the other waits;
## - units sealed in a box do not count; packed and closed orders appear in neither list;
## - can_cover / missing_for judge one order alone;
## - unblocked_by lists the waiting orders a delivery on its way would free.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_basic()
	_test_shared_stock()
	_test_ignored()
	_test_single()
	_test_unblocked()
	quit(_failures)


func _order(
	id: StringName, items: Array, due: int = 240, state: StringName = Order.STATE_OPEN
) -> Dictionary:
	return {"id": id, "state": state, "items": items, "due_min": due}


func _inv(stock: Dictionary) -> Inventory:
	var inv := Inventory.new()
	for key: String in stock:
		var parts: PackedStringArray = key.split("@")
		inv.receive(StringName(parts[0]), int(stock[key]), StringName(parts[1]))
	return inv


func _test_basic() -> void:
	var inv := _inv({"hen@shelf:a1": 1, "sourdough@shelf:a2": 3})
	var ok := _order(&"ok", [{"product": &"sourdough", "qty": 3}])
	var short := _order(
		&"short", [{"product": &"hen", "qty": 3}, {"product": &"sourdough", "qty": 0}]
	)
	var result: Dictionary = OrderWaiting.classify(inv, [ok, short])
	_expect(result["ready"] == [&"ok"], "covered order is ready")
	_expect(result["waiting"].has(&"short"), "short order waits")
	_expect(result["waiting"][&"short"] == {&"hen": 2}, "it lacks 2 hens")
	var none: Dictionary = OrderWaiting.classify(inv, [])
	_expect(none["ready"].is_empty() and none["waiting"].is_empty(), "no orders, empty result")


func _test_shared_stock() -> void:
	var inv := _inv({"hen@shelf:a1": 1})
	var late := _order(&"b", [{"product": &"hen", "qty": 1}], 300)
	var early := _order(&"a", [{"product": &"hen", "qty": 1}], 200)
	var result: Dictionary = OrderWaiting.classify(inv, [late, early])
	_expect(result["ready"] == [&"a"], "the earlier due gets the last hen")
	_expect(
		result["waiting"].has(&"b") and result["waiting"][&"b"] == {&"hen": 1}, "the other waits"
	)
	var tie: Dictionary = OrderWaiting.classify(
		inv,
		[
			_order(&"z", [{"product": &"hen", "qty": 1}]),
			_order(&"y", [{"product": &"hen", "qty": 1}])
		]
	)
	_expect(tie["ready"] == [&"y"], "same due: lower id first")
	var split: Dictionary = OrderWaiting.classify(
		_inv({"hen@shelf:a1": 2}),
		[
			_order(&"p", [{"product": &"hen", "qty": 2}], 100),
			_order(&"q", [{"product": &"hen", "qty": 1}], 200)
		]
	)
	_expect(split["ready"] == [&"p"] and split["waiting"].has(&"q"), "units are not counted twice")
	var dup: Dictionary = OrderWaiting.classify(
		_inv({"hen@shelf:a1": 2}),
		[_order(&"d", [{"product": &"hen", "qty": 1}, {"product": &"hen", "qty": 2}])]
	)
	_expect(dup["waiting"].get(&"d", {}) == {&"hen": 1}, "repeated lines add up")


func _test_ignored() -> void:
	var inv := _inv({"hen@box:b1": 5})
	var sealed := _order(&"s", [{"product": &"hen", "qty": 1}])
	_expect(OrderWaiting.classify(inv, [sealed])["waiting"].has(&"s"), "sealed units do not count")
	var packed := _order(&"p", [{"product": &"hen", "qty": 1}], 240, Order.STATE_PACKED)
	packed["box_id"] = &"b1"
	var done := _order(&"d", [{"product": &"hen", "qty": 1}], 240, Order.STATE_DELIVERED)
	var result: Dictionary = OrderWaiting.classify(inv, [packed, done])
	_expect(
		result["ready"].is_empty() and result["waiting"].is_empty(), "packed and closed ignored"
	)
	var late := _order(&"l", [{"product": &"hen", "qty": 1}], 240, Order.STATE_LATE)
	_expect(
		OrderWaiting.classify(_inv({"hen@shelf:a1": 1}), [late])["ready"] == [&"l"], "late counts"
	)


func _test_single() -> void:
	var inv := _inv({"hen@shelf:a1": 1})
	var o := _order(&"o", [{"product": &"hen", "qty": 2}])
	_expect(not OrderWaiting.can_cover(inv, o), "2 hens are not covered by 1")
	_expect(OrderWaiting.missing_for(inv, o) == {&"hen": 1}, "missing 1")
	_expect(OrderWaiting.can_cover(inv, _order(&"x", [{"product": &"hen", "qty": 1}])), "1 hen is")


func _test_unblocked() -> void:
	var inv := _inv({"hen@shelf:a1": 1})
	var a := _order(&"a", [{"product": &"hen", "qty": 1}], 100)
	var b := _order(&"b", [{"product": &"hen", "qty": 1}], 200)
	var c := _order(&"c", [{"product": &"hen", "qty": 1}], 300)
	_expect(OrderWaiting.unblocked_by(inv, [a, b, c], {&"hen": 1}) == [&"b"], "one hen frees one")
	_expect(OrderWaiting.unblocked_by(inv, [a, b, c], {}).is_empty(), "nothing incoming")
	_expect(inv.count(&"hen") == 1, "the real inventory is untouched")


func _expect(cond: bool, message: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
