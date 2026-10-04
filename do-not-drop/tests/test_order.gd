extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order.gd
##
## Customer order structure (expansion D-0802, order.gd):
## - make() merges repeated products, sets due_min to created + 4 h and the pay
##   to sold units plus the zone's shipping fee;
## - validate() accepts a made order and names each problem of a broken one;
## - an order survives a JSON round trip equal to the original;
## - payout() takes 25 % off once the order is past due.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_make()
	_test_validate()
	_test_json_round_trip()
	_test_payout()
	quit(_failures)


func _products() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in [&"hen", &"sourdough"]:
		out[id] = load("res://data/products/%s.tres" % id)
	return out


func _sample() -> Dictionary:
	var items: Array = [
		{"product": &"hen", "qty": 1},
		{"product": &"sourdough", "qty": 1},
		{"product": &"hen", "qty": 1}
	]
	var reqs: Array[StringName] = [&"fragile"]
	return Order.make(&"o1", "Doña Rosa", &"campo", &"campo_3", items, 120, _products(), reqs)


func _test_make() -> void:
	var products := _products()
	var order := _sample()
	_expect(order["items"].size() == 2, "repeated hen merged into one entry")
	_expect(order["items"][0] == {"product": &"hen", "qty": 2}, "hen qty 2, first-seen order kept")
	_expect(order["due_min"] == 120 + Order.WINDOW_MIN, "due 4 game hours after creation")
	var expected: int = (
		60 + products[&"hen"].get_sell_price() * 2 + products[&"sourdough"].get_sell_price()
	)
	_expect(order["pay"] == expected, "pay is units sold plus campo shipping (%d)" % expected)
	_expect(order["state"] == Order.STATE_OPEN, "a new order is open")
	var one: Array = [{"product": &"hen", "qty": 1}]
	var custom := Order.make(&"o2", "X", &"centro", &"c1", one, 0, products, [], 90)
	_expect(custom["due_min"] == 90, "explicit due_min kept")


func _test_validate() -> void:
	_expect(Order.validate(_sample()).is_empty(), "a made order is valid")
	var bad := _sample()
	bad["customer"] = ""
	bad["items"] = []
	bad["due_min"] = 10
	bad["state"] = &"bogus"
	bad["pay"] = -1
	_expect(
		Order.validate(bad).size() == 5, "five problems reported (%s)" % str(Order.validate(bad))
	)
	var too_many := _sample()
	too_many["items"] = [
		{"product": &"a", "qty": 1},
		{"product": &"b", "qty": 1},
		{"product": &"c", "qty": 1},
		{"product": &"d", "qty": 1},
	]
	_expect(not Order.validate(too_many).is_empty(), "more than 3 products rejected")
	var dup := _sample()
	dup["items"] = [{"product": &"a", "qty": 1}, {"product": &"a", "qty": 1}]
	_expect(not Order.validate(dup).is_empty(), "repeated product rejected")
	var zero := _sample()
	zero["items"] = [{"product": &"a", "qty": 0}]
	_expect(not Order.validate(zero).is_empty(), "qty 0 rejected")


func _test_json_round_trip() -> void:
	var order := _sample()
	var back := Order.from_json(Order.to_json(order))
	_expect(back == order, "JSON round trip equals the original")
	_expect(Order.validate(back).is_empty(), "round-tripped order is valid")
	_expect(Order.from_json("not json").is_empty(), "garbage gives an empty order")


func _test_payout() -> void:
	var order := _sample()
	var pay: int = order["pay"]
	_expect(Order.payout(order, order["due_min"]) == pay, "on time pays in full")
	_expect(Order.payout(order, order["due_min"] + 1) == roundi(pay * 0.75), "late pays 75 %")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)
