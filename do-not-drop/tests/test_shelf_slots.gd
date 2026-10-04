extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shelf_slots.gd
##
## Shelf with labeled product slots (expansion D-0608, shelf.gd):
## - make() builds the 8 slots of the shelf placeable and refuses an empty id or 0 slots;
## - set_label() labels an empty slot, refuses a product that already has a slot, and refuses
##   relabeling a slot that holds units; clear_label() only works on an empty slot;
## - deposit() moves units from hands/pallet into the slot's location in the Inventory, only
##   for the labeled product and never past CompanyTuning.SHELF_SLOT_CAPACITY;
## - withdraw() takes units back out, never more than the slot holds;
## - no unit is created or lost: the Inventory total is the same after any move;
## - to_dict()/from_dict() survive a JSON round trip.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_make_and_labels()
	_test_deposit_withdraw()
	_test_conservation()
	_test_json()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _test_make_and_labels() -> void:
	var def: PlaceableDefinition = load("res://data/placeables/shelf.tres")
	var shelf: Shelf = Shelf.make(&"s1", def.slots)
	_expect(shelf != null and shelf.slot_count() == 8, "shelf has the 8 slots of the placeable")
	_expect(Shelf.make(&"", 8) == null, "empty id is refused")
	_expect(Shelf.make(&"s1", 0) == null, "0 slots is refused")
	var inv := Inventory.new()
	_expect(shelf.set_label(inv, 0, &"hen"), "labels an empty slot")
	_expect(shelf.find_slot(&"hen") == 0 and shelf.label_of(0) == &"hen", "label is found")
	_expect(not shelf.set_label(inv, 1, &"hen"), "a product has one slot per shelf")
	_expect(not shelf.set_label(inv, 8, &"lamp"), "slot out of range is refused")
	_expect(not shelf.set_label(inv, 1, &""), "empty product is refused")
	inv.receive(&"hen", 3, &"hands:1")
	_expect(shelf.deposit(inv, 0, &"hen", 3, &"hands:1"), "deposit succeeds")
	_expect(not shelf.set_label(inv, 0, &"lamp"), "a slot with units cannot be relabeled")
	_expect(not shelf.clear_label(inv, 0), "a slot with units cannot be cleared")
	_expect(shelf.withdraw(inv, 0, 3, &"hands:1"), "empties the slot")
	_expect(shelf.clear_label(inv, 0) and shelf.label_of(0) == &"", "empty slot clears")


func _test_deposit_withdraw() -> void:
	var shelf: Shelf = Shelf.make(&"s1", 2)
	var inv := Inventory.new()
	shelf.set_label(inv, 0, &"hen")
	inv.receive(&"hen", 30, &"pallet:p1")
	inv.receive(&"lamp", 2, &"hands:1")
	_expect(
		not shelf.deposit(inv, 0, &"lamp", 2, &"hands:1"), "wrong product for the label is refused"
	)
	_expect(not shelf.deposit(inv, 1, &"hen", 1, &"pallet:p1"), "unlabeled slot is refused")
	_expect(not shelf.deposit(inv, 0, &"hen", 25, &"pallet:p1"), "past capacity is refused")
	_expect(inv.count(&"hen", &"pallet:p1") == 30, "a refused deposit changes nothing")
	_expect(not shelf.deposit(inv, 0, &"hen", 0, &"pallet:p1"), "0 units is refused")
	_expect(not shelf.deposit(inv, 0, &"hen", 5, &"pallet:none"), "source without units is refused")
	_expect(shelf.deposit(inv, 0, &"hen", 20, &"pallet:p1"), "20 units fit")
	_expect(shelf.free_space(inv, 0) == 4, "4 units of space left")
	_expect(shelf.count(inv, 0) == 20 and shelf.total_of(inv, &"hen") == 20, "count reads 20")
	_expect(inv.count(&"hen", &"shelf:s1_0") == 20, "units sit at shelf:s1_0")
	_expect(not shelf.deposit(inv, 0, &"hen", 5, &"pallet:p1"), "5 do not fit in 4")
	_expect(shelf.withdraw(inv, 0, 3, &"hands:1"), "takes 3 out")
	_expect(shelf.count(inv, 0) == 17, "17 left")
	_expect(not shelf.withdraw(inv, 0, 18, &"hands:1"), "cannot take more than it holds")
	_expect(not shelf.withdraw(inv, 1, 1, &"hands:1"), "unlabeled slot gives nothing")


func _test_conservation() -> void:
	var shelf: Shelf = Shelf.make(&"s2", 2)
	var inv := Inventory.new()
	shelf.set_label(inv, 0, &"hen")
	shelf.set_label(inv, 1, &"lamp")
	inv.receive(&"hen", 24, &"pallet:p1")
	inv.receive(&"lamp", 10, &"pallet:p2")
	var total: int = inv.total_units()
	for i: int in 50:
		shelf.deposit(inv, 0, &"hen", 1 + i % 5, &"pallet:p1")
		shelf.withdraw(inv, 0, 1 + i % 3, &"hands:1")
		shelf.deposit(inv, 1, &"lamp", 2, &"pallet:p2")
		shelf.withdraw(inv, 1, 1, &"pallet:p2")
	_expect(inv.total_units() == total, "50 moves keep the total at %d" % total)
	_expect(shelf.count(inv, 0) <= CompanyTuning.SHELF_SLOT_CAPACITY, "slot never overflows")


func _test_json() -> void:
	var shelf: Shelf = Shelf.make(&"s3", 3)
	var inv := Inventory.new()
	shelf.set_label(inv, 2, &"hen")
	var back: Shelf = Shelf.from_dict(JSON.parse_string(JSON.stringify(shelf.to_dict())))
	_expect(back != null and back.id == &"s3" and back.slot_count() == 3, "round trip keeps shape")
	_expect(back.label_of(2) == &"hen" and back.label_of(0) == &"", "round trip keeps labels")
	_expect(Shelf.from_dict({}) == null, "empty data is not a shelf")
