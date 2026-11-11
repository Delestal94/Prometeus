extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_parts.gd
##
## One order in several boxes (expansion D-0729, order_parts.gd), with a product of 8 cells (2x2x2) and
## an XL box of 64 cells that takes 48 before an order is split:
## - an order of up to 6 units is one part, and that part is the order itself;
## - 7 units are two parts and 14 are three, with ids "<order>#n" that name their order;
## - the units add up: the parts hold exactly what the order asked for, and the split is the same
##   every time (no peer disagrees);
## - more than ORDER_BOXES_MAX boxes' worth still comes back in ORDER_BOXES_MAX parts;
## - match() pairs boxes with parts in any order: all boxes right -> ok; a box short, a wrong box or a
##   box left over -> not ok, saying which part or box.

var _failures: int = 0
var _products: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var def := ProductDefinition.new()
	def.id = &"crate"
	def.buy_price = 10
	def.cells = Vector3i(2, 2, 2)
	_products[&"crate"] = def
	var small := ProductDefinition.new()
	small.id = &"pen"
	small.buy_price = 1
	small.cells = Vector3i(1, 1, 1)
	_products[&"pen"] = small
	_test_split()
	_test_cap()
	_test_match()
	if _failures == 0:
		print("PASS: big orders split into boxes that are matched at the door")
	quit(_failures)


func _order(items: Array) -> Dictionary:
	return Order.make(&"o1", "C", &"centro", &"h", items, 60, _products)


func _units(parts: Array[Dictionary]) -> Dictionary:
	var total: Dictionary = {}
	for part: Dictionary in parts:
		for item: Dictionary in part["items"]:
			total[item["product"]] = int(total.get(item["product"], 0)) + int(item["qty"])
	return total


func _test_split() -> void:
	var one: Dictionary = _order([{"product": &"crate", "qty": 6}])
	_expect(not OrderParts.is_multi(one, _products), "6 units fit one box")
	var parts: Array[Dictionary] = OrderParts.split(one, _products)
	_expect(parts.size() == 1 and parts[0]["id"] == &"o1", "one part, the order itself")

	var two: Dictionary = _order([{"product": &"crate", "qty": 7}])
	_expect(OrderParts.is_multi(two, _products), "7 units need more than one box")
	parts = OrderParts.split(two, _products)
	_expect(parts.size() == 2, "7 units are two parts")
	_expect(parts[0]["id"] == &"o1#1" and parts[1]["id"] == &"o1#2", "part ids are numbered")
	_expect(OrderParts.order_id_of(parts[1]["id"]) == &"o1", "a part names its order")
	_expect(OrderParts.order_id_of(&"o1") == &"o1", "a plain id is its own order")
	_expect(_units(parts) == {&"crate": 7}, "the parts hold what the order asked for")
	_expect(OrderParts.split(two, _products) == parts, "the split is deterministic")

	var three: Dictionary = _order([{"product": &"crate", "qty": 12}, {"product": &"pen", "qty": 5}])
	parts = OrderParts.split(three, _products)
	_expect(parts.size() == 3, "101 cells are three parts")
	_expect(_units(parts) == {&"crate": 12, &"pen": 5}, "mixed products add up")


func _test_cap() -> void:
	var huge: Dictionary = _order([{"product": &"crate", "qty": 30}])
	var parts: Array[Dictionary] = OrderParts.split(huge, _products)
	_expect(parts.size() == CompanyTuning.ORDER_BOXES_MAX, "never more than the cap")
	_expect(_units(parts) == {&"crate": 30}, "nothing is lost at the cap")


func _box_with(items: Dictionary) -> PackedBox:
	var box := PackedBox.new(&"XL")
	for id: StringName in items:
		for _n: int in int(items[id]):
			var spot: Vector3i = box.first_fit(_products[id])
			_expect(box.place(_products[id], spot), "placed %s" % id)
	return box


func _test_match() -> void:
	var order: Dictionary = _order([{"product": &"crate", "qty": 7}])
	var parts: Array[Dictionary] = OrderParts.split(order, _products)
	var first: PackedBox = _box_with({&"crate": int(parts[0]["items"][0]["qty"])})
	var second: PackedBox = _box_with({&"crate": int(parts[1]["items"][0]["qty"])})
	_expect(OrderParts.door_accepts(order, _products, [first, second]), "both boxes right")
	_expect(OrderParts.door_accepts(order, _products, [second, first]), "the order of boxes does not matter")
	var short: Dictionary = OrderParts.match(order, _products, [first])
	_expect(not short["ok"] and short["missing"] == [1], "one box short names the missing part")
	var wrong: Dictionary = OrderParts.match(order, _products, [first, _box_with({&"pen": 1})])
	_expect(not wrong["ok"] and wrong["missing"] == [1] and wrong["extra"] == [1], "a wrong box is extra")
	var spare: Dictionary = OrderParts.match(order, _products, [first, second, _box_with({&"pen": 1})])
	_expect(not spare["ok"] and spare["extra"] == [2], "a box left over fails")
	_expect(not OrderParts.door_accepts(order, _products, []), "no boxes fail")


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAIL: " + msg)
