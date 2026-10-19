extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_box_scale.gd
##
## Control scale (expansion D-0713, box_scale.gd):
## - expected weight sums the order items by quantity, real weight sums what the box holds;
## - the exact box weighs ok with delta 0; a missing unit gives a negative delta and not ok;
##   an extra unit a positive one;
## - a different product of the same weight passes (the scale cannot tell: documented limit);
## - a small difference inside the tolerance is ok; unknown products add nothing; no box
##   weighs 0.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_weigh()
	_test_edges()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _catalog() -> Dictionary:
	var out: Dictionary = {}
	for row: Array in [[&"mug", 0.4], [&"book", 1.2], [&"cup", 0.4], [&"pen", 0.42]]:
		var p := ProductDefinition.new()
		p.id = row[0]
		p.cells = Vector3i(1, 1, 1)
		p.weight_kg = row[1]
		out[p.id] = p
	return out


func _box_with(ids: Array, products: Dictionary) -> PackedBox:
	var box := PackedBox.new(&"M")
	for id: StringName in ids:
		var p: ProductDefinition = products[id]
		box.place(p, box.first_fit(p))
	return box


func _test_weigh() -> void:
	var products: Dictionary = _catalog()
	var order := {"items": [{"product": &"mug", "qty": 2}, {"product": &"book", "qty": 1}]}
	_expect(is_equal_approx(BoxScale.expected_kg(order, products), 2.0), "expected = 2 mugs + book")
	var exact: Dictionary = BoxScale.weigh(order, _box_with([&"mug", &"mug", &"book"], products), products)
	_expect(exact["ok"] and is_zero_approx(exact["delta"]), "exact box passes with delta 0")
	var short: Dictionary = BoxScale.weigh(order, _box_with([&"mug", &"book"], products), products)
	_expect(not short["ok"] and is_equal_approx(short["delta"], -0.4), "missing mug: -0.4 kg")
	var over: Dictionary = BoxScale.weigh(order, _box_with([&"mug", &"mug", &"book", &"book"], products), products)
	_expect(not over["ok"] and is_equal_approx(over["delta"], 1.2), "extra book: +1.2 kg")
	var swapped: Dictionary = BoxScale.weigh(order, _box_with([&"mug", &"cup", &"book"], products), products)
	_expect(swapped["ok"], "a same-weight swap is invisible to the scale")


func _test_edges() -> void:
	var products: Dictionary = _catalog()
	var order := {"items": [{"product": &"mug", "qty": 1}]}
	var close: Dictionary = BoxScale.weigh(order, _box_with([&"pen"], products), products)
	_expect(close["ok"], "0.02 kg off is inside the tolerance")
	_expect(is_zero_approx(BoxScale.real_kg(null, products)), "no box weighs 0")
	var unknown := {"items": [{"product": &"ghost", "qty": 3}]}
	_expect(is_zero_approx(BoxScale.expected_kg(unknown, products)), "unknown product adds nothing")
	var empty: Dictionary = BoxScale.weigh(order, null, products)
	_expect(not empty["ok"] and is_equal_approx(empty["delta"], -0.4), "no box is short the whole order")
