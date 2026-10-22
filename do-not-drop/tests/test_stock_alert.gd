extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_stock_alert.gd
##
## StockAlert (expansion D-0613, stock_alert.gd), the low-stock warning:
## - a product that pending orders need more of than the free stock holds is reported
##   with needed, have and missing; one with enough stock is not;
## - the needs of several pending orders add up, and the entry carries the earliest due;
## - packed orders, delivered orders and units sealed in a box do not count;
## - units already ordered from a supplier (incoming) shrink `missing`, and a gap they
##   close entirely is `covered`;
## - the list is ordered most urgent first;
## - fresh() names only the products that were not short before, and skips covered ones.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_basic()
	_test_sum_and_due()
	_test_ignored()
	_test_incoming()
	_test_order()
	_test_fresh()
	quit(_failures)


func _order(
	id: StringName, items: Array, state: StringName = Order.STATE_OPEN, due: int = 240
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
	var orders: Array = [
		_order(&"o1", [{"product": &"hen", "qty": 2}, {"product": &"sourdough", "qty": 3}])
	]
	var list: Array[Dictionary] = StockAlert.shortages(inv, orders)
	_expect(list.size() == 1, "only the product with a gap is reported")
	_expect(list[0]["product"] == &"hen", "the short product is the hen")
	_expect(
		list[0]["needed"] == 2 and list[0]["have"] == 1 and list[0]["missing"] == 1,
		"needed 2, have 1, missing 1"
	)
	_expect(not list[0]["covered"], "nothing incoming: not covered")
	_expect(StockAlert.shortages(inv, []).is_empty(), "no orders, no warning")


func _test_sum_and_due() -> void:
	var inv := _inv({"hen@shelf:a1": 2})
	var orders: Array = [
		_order(&"o1", [{"product": &"hen", "qty": 2}], Order.STATE_OPEN, 300),
		_order(&"o2", [{"product": &"hen", "qty": 1}], Order.STATE_LATE, 120),
	]
	var list: Array[Dictionary] = StockAlert.shortages(inv, orders)
	_expect(list.size() == 1 and list[0]["needed"] == 3, "two pending orders add up to 3")
	_expect(list[0]["missing"] == 1 and list[0]["due_min"] == 120, "missing 1, earliest due 120")


func _test_ignored() -> void:
	var inv := _inv({"hen@box:b1": 5, "hen@shelf:a1": 1})
	var packed: Dictionary = _order(&"o1", [{"product": &"hen", "qty": 4}], Order.STATE_PACKED)
	var done: Dictionary = _order(&"o2", [{"product": &"hen", "qty": 4}], Order.STATE_DELIVERED)
	var boxed_late: Dictionary = _order(&"o3", [{"product": &"hen", "qty": 4}], Order.STATE_LATE)
	boxed_late["box_id"] = &"b1"
	_expect(
		StockAlert.shortages(inv, [packed, done, boxed_late]).is_empty(),
		"packed, delivered and boxed orders are not pending"
	)
	var open: Dictionary = _order(&"o4", [{"product": &"hen", "qty": 2}])
	var list: Array[Dictionary] = StockAlert.shortages(inv, [open])
	_expect(
		list.size() == 1 and list[0]["have"] == 1, "the 5 hens sealed in a box are not free stock"
	)


func _test_incoming() -> void:
	var inv := _inv({"hen@shelf:a1": 1})
	var orders: Array = [_order(&"o1", [{"product": &"hen", "qty": 4}])]
	var part: Array[Dictionary] = StockAlert.shortages(inv, orders, {&"hen": 1})
	_expect(part[0]["missing"] == 2 and not part[0]["covered"], "1 coming: still 2 missing")
	var full: Array[Dictionary] = StockAlert.shortages(inv, orders, {&"hen": 3})
	_expect(full[0]["missing"] == 0 and full[0]["covered"], "3 coming close the gap")
	var extra: Array[Dictionary] = StockAlert.shortages(inv, orders, {&"hen": 9})
	_expect(extra[0]["missing"] == 0 and extra[0]["covered"], "more than needed is still covered")


func _test_order() -> void:
	var inv := Inventory.new()
	var orders: Array = [
		_order(&"o1", [{"product": &"sourdough", "qty": 1}], Order.STATE_OPEN, 400),
		_order(&"o2", [{"product": &"hen", "qty": 1}], Order.STATE_OPEN, 200),
		_order(&"o3", [{"product": &"antique_lamp", "qty": 1}], Order.STATE_OPEN, 200),
	]
	var list: Array[Dictionary] = StockAlert.shortages(inv, orders)
	var ids: Array = list.map(func(e: Dictionary) -> StringName: return e["product"])
	_expect(
		ids == [&"antique_lamp", &"hen", &"sourdough"],
		"earliest due first, ties by product id: %s" % [ids]
	)


func _test_fresh() -> void:
	var inv := Inventory.new()
	var before: Array[Dictionary] = StockAlert.shortages(
		inv, [_order(&"o1", [{"product": &"hen", "qty": 1}])]
	)
	var after: Array[Dictionary] = (
		StockAlert
		. shortages(
			inv,
			[
				_order(&"o1", [{"product": &"hen", "qty": 1}]),
				_order(&"o2", [{"product": &"sourdough", "qty": 1}]),
			]
		)
	)
	_expect(StockAlert.fresh(before, after) == [&"sourdough"], "only the new product is fresh")
	_expect(StockAlert.fresh([], before) == [&"hen"], "from nothing, the short one is fresh")
	var covered: Array[Dictionary] = StockAlert.shortages(
		inv, [_order(&"o1", [{"product": &"hen", "qty": 1}])], {&"hen": 1}
	)
	_expect(StockAlert.fresh([], covered).is_empty(), "a covered gap does not warn")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)
