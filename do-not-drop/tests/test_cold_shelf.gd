extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_cold_shelf.gd
##
## The fridge is the only shelf that keeps cold products (expansion D-0617, shelf.gd, default_shed.gd):
## - Shelf.make() takes the cold flag of the placeable (fridge.tres is cold, shelf.tres is not);
## - a fridge labels cold products (milk, cake) and refuses ambient ones; an ordinary shelf does the
##   opposite; leaving the temperature out skips the check;
## - the flag survives a JSON round trip, and an old save without it reads as an ordinary shelf;
## - the default shed keeps its cold products in a fridge and its ambient ones on shelves, and
##   DefaultShed.problems() flags a cold product on an ordinary shelf.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fridge_def: PlaceableDefinition = load("res://data/placeables/fridge.tres")
	var shelf_def: PlaceableDefinition = load("res://data/placeables/shelf.tres")
	var milk: ProductDefinition = load("res://data/products/milk_canister.tres")
	var vase: ProductDefinition = load("res://data/products/porcelain_vase.tres")
	var inv := Inventory.new()

	var fridge: Shelf = Shelf.make(&"cold_1", fridge_def.slots, fridge_def.cold)
	var shelf: Shelf = Shelf.make(&"shelf_1", shelf_def.slots, shelf_def.cold)
	_expect(fridge.cold and not shelf.cold, "the fridge placeable makes a cold shelf, the shelf does not")
	_expect(not Shelf.make(&"x", 2).cold, "a shelf is ordinary unless told otherwise")

	_expect(fridge.set_label(inv, 0, milk.id, milk.temperature), "the fridge labels milk")
	_expect(not fridge.set_label(inv, 1, vase.id, vase.temperature), "the fridge refuses a vase")
	_expect(fridge.label_of(1) == &"", "...and leaves the slot unlabeled")
	_expect(shelf.set_label(inv, 0, vase.id, vase.temperature), "an ordinary shelf labels a vase")
	_expect(not shelf.set_label(inv, 1, milk.id, milk.temperature), "...and refuses milk")
	_expect(shelf.set_label(inv, 1, milk.id), "no temperature given skips the check")

	var again: Shelf = Shelf.from_dict(JSON.parse_string(JSON.stringify(fridge.to_dict())))
	_expect(again != null and again.cold and again.label_of(0) == milk.id, "the cold flag survives JSON")
	var old: Shelf = Shelf.from_dict({"id": "shelf_9", "labels": ["", ""]})
	_expect(old != null and not old.cold, "a shelf saved before the flag is ordinary")

	var data: DefaultShed = DefaultShed.load_default()
	_expect(data != null, "the default shed loads")
	if data != null:
		_expect(data.problems().is_empty(), "the default shed is sound (%s)" % ", ".join(data.problems()))
		var broken: DefaultShed = data.duplicate(true) as DefaultShed
		broken.shelf_stock.append({"shelf": "shelf_1", "slot": 7, "product": "milk_canister", "qty": 0})
		_expect(not broken.problems().is_empty(), "milk labeled on an ordinary shelf is a problem")

	if _failures == 0:
		print("PASS: only the fridge keeps cold products")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)
