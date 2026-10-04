extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_inventory.gd
##
## Company stock (expansion D-0211, inventory.gd):
## - 200 seeded random moves keep every product's total and never go negative;
## - moving more than a location holds fails and changes nothing;
## - only receive() adds and consume() removes units;
## - reserve() stops another order from taking what is promised, release()
##   frees it, and consume() cannot eat other orders' reservations;
## - to_dict()/from_dict() round-trips, also through JSON.

const PRODUCTS: Array[StringName] = [&"hen", &"sourdough", &"glass_tower"]
const LOCATIONS: Array[StringName] = [&"dock", &"shelf:a1", &"shelf:a2", &"cart:1", &"hands:1"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_random_moves()
	_test_failed_move()
	_test_receive_consume()
	_test_reservations()
	_test_serialization()
	quit(_failures)


func _test_random_moves() -> void:
	var inv := Inventory.new()
	for product: StringName in PRODUCTS:
		_expect(inv.receive(product, 24, &"dock"), "receive 24 %s" % product)
	var rng := RandomNumberGenerator.new()
	rng.seed = 211
	var done: int = 0
	for i: int in 200:
		var product: StringName = PRODUCTS[rng.randi() % PRODUCTS.size()]
		var from: StringName = LOCATIONS[rng.randi() % LOCATIONS.size()]
		var to: StringName = LOCATIONS[rng.randi() % LOCATIONS.size()]
		var qty: int = rng.randi_range(1, 8)
		if inv.move(product, qty, from, to):
			done += 1
		for p: StringName in PRODUCTS:
			_expect(inv.count(p) == 24, "total of %s stays 24 after move %d" % [p, i])
		for loc: StringName in LOCATIONS:
			_expect(inv.count(product, loc) >= 0, "no negative stock at %s" % loc)
	_expect(done > 20, "a good share of the random moves happened (%d)" % done)
	_expect(inv.total_units() == 72, "72 units in total")


func _test_failed_move() -> void:
	var inv := Inventory.new()
	inv.receive(&"hen", 5, &"dock")
	var before: Dictionary = inv.to_dict()
	_expect(not inv.move(&"hen", 6, &"dock", &"shelf:a1"), "moving more than there is fails")
	_expect(not inv.move(&"hen", 1, &"shelf:a1", &"dock"), "moving from an empty place fails")
	_expect(not inv.move(&"hen", 0, &"dock", &"shelf:a1"), "moving 0 fails")
	_expect(not inv.move(&"hen", 1, &"dock", &"dock"), "moving to the same place fails")
	_expect(inv.to_dict() == before, "failed moves change nothing")


func _test_receive_consume() -> void:
	var inv := Inventory.new()
	_expect(not inv.receive(&"hen", 0, &"dock"), "receiving 0 fails")
	inv.receive(&"hen", 4, &"dock")
	_expect(inv.consume(&"hen", 3, &"dock"), "consume 3")
	_expect(inv.count(&"hen") == 1, "1 left")
	_expect(not inv.consume(&"hen", 2, &"dock"), "consume more than there is fails")
	_expect(inv.count(&"hen", &"dock") == 1, "failed consume changes nothing")
	_expect(inv.contents_at(&"dock") == {&"hen": 1}, "contents_at lists what is there")
	inv.consume(&"hen", 1, &"dock")
	_expect(inv.total_units() == 0 and inv.contents_at(&"dock").is_empty(), "empties cleanly")


func _test_reservations() -> void:
	var inv := Inventory.new()
	inv.receive(&"hen", 5, &"shelf:a1")
	_expect(inv.reserve(&"hen", 3, &"order1"), "order1 reserves 3")
	_expect(inv.available(&"hen") == 2, "2 available")
	_expect(not inv.reserve(&"hen", 3, &"order2"), "order2 cannot take the reserved units")
	_expect(inv.reserve(&"hen", 2, &"order2"), "order2 takes the free 2")
	_expect(not inv.consume(&"hen", 1, &"shelf:a1"), "anonymous consume cannot dip into reservations")
	_expect(inv.consume(&"hen", 3, &"shelf:a1", &"order1"), "order1 consumes its own 3")
	_expect(inv.reserved_by(&"order1").is_empty(), "order1's reservation is gone")
	_expect(inv.reserved_by(&"order2") == {&"hen": 2}, "order2 keeps its 2")
	_expect(not inv.consume(&"hen", 1, &"shelf:a1", &"order3"), "order3 cannot eat order2's units")
	inv.release(&"order2")
	_expect(inv.available(&"hen") == 2, "release frees the units")
	_expect(inv.move(&"hen", 1, &"shelf:a1", &"cart:1"), "reserved units can still be moved")


func _test_serialization() -> void:
	var inv := Inventory.new()
	inv.receive(&"hen", 5, &"dock")
	inv.receive(&"sourdough", 2, &"shelf:a1")
	inv.reserve(&"hen", 2, &"order1")
	var copy := Inventory.new()
	copy.from_dict(inv.to_dict())
	_expect(copy.to_dict() == inv.to_dict(), "dict round trip")
	var json_copy := Inventory.new()
	json_copy.from_dict(JSON.parse_string(JSON.stringify(inv.to_dict())))
	_expect(json_copy.count(&"hen", &"dock") == 5, "JSON round trip keeps stock")
	_expect(json_copy.reserved_by(&"order1") == {&"hen": 2}, "JSON round trip keeps reservations")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)
