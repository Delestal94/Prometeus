extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_pallet.gd
##
## Supplier pallet (expansion D-0604, pallet.gd):
## - make() builds a sealed pallet and refuses 0 or more than 24 units;
## - plan() splits an order into full pallets plus a remainder;
## - receive() puts the units in the Inventory at pallet:<id> once, and never twice;
## - validate() names each problem; the JSON round trip returns an equal pallet.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_make()
	_test_plan()
	_test_receive()
	_test_validate_and_json()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _test_make() -> void:
	var p: Dictionary = Pallet.make(&"p1", &"hen", 24)
	_expect(
		p.get("state") == Pallet.STATE_SEALED and p.get("qty") == 24, "24 units is a sealed pallet"
	)
	_expect(Pallet.make(&"p1", &"hen", 25).is_empty(), "25 units is refused")
	_expect(Pallet.make(&"p1", &"hen", 0).is_empty(), "0 units is refused")
	_expect(Pallet.make(&"", &"hen", 3).is_empty(), "empty id is refused")


func _test_plan() -> void:
	var pallets: Array[Dictionary] = Pallet.plan(&"d1", &"sourdough", 50)
	_expect(pallets.size() == 3, "50 units need 3 pallets")
	_expect(
		pallets[0]["qty"] == 24 and pallets[1]["qty"] == 24 and pallets[2]["qty"] == 2,
		"24 + 24 + 2"
	)
	_expect(pallets[2]["id"] == &"d1_3", "ids are numbered")
	_expect(Pallet.plan(&"d1", &"hen", 0).is_empty(), "nothing to plan for 0")


func _test_receive() -> void:
	var inv := Inventory.new()
	var p: Dictionary = Pallet.make(&"p1", &"hen", 10)
	_expect(Pallet.receive(inv, p), "receive succeeds")
	_expect(inv.count(&"hen", &"pallet:p1") == 10, "units sit at pallet:p1")
	_expect(Pallet.units_left(inv, p) == 10, "units_left reads the inventory")
	_expect(not Pallet.receive(inv, p), "a second receive is refused")
	_expect(inv.total_units() == 10, "no duplicated units")
	inv.move(&"hen", 4, Pallet.location(&"p1"), &"shelf:a1")
	_expect(Pallet.units_left(inv, p) == 6, "moving 4 leaves 6")


func _test_validate_and_json() -> void:
	_expect(Pallet.validate(Pallet.make(&"p1", &"hen", 5)).is_empty(), "a made pallet is valid")
	var bad: Dictionary = {"id": &"", "product": &"", "qty": 99, "state": &"x"}
	_expect(Pallet.validate(bad).size() == 4, "4 problems are named")
	var p: Dictionary = Pallet.make(&"p2", &"puppy", 7)
	p["state"] = Pallet.STATE_OPEN
	_expect(Pallet.from_json(Pallet.to_json(p)) == p, "JSON round trip is equal")
	_expect(Pallet.from_json("not json").is_empty(), "bad JSON gives {}")
