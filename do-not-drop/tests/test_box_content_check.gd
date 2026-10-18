extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_box_content_check.gd
##
## Content errors of a packed box (expansion D-0712, box_content_check.gd):
## - the exact content gives empty missing and extra, and the door accepts it;
## - a missing unit and a missing product show up in `missing`, an extra unit or product in
##   `extra`, with their counts;
## - at the table (PackingStation.content_errors) the error shows before taping and sealing
##   a wrong box is still allowed; at the door the same box is rejected with the same reason;
## - no box is missing everything; door_accepts agrees with OrderPenalties.matches_order.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_diff()
	_test_two_moments()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _product(id: StringName) -> ProductDefinition:
	var p := ProductDefinition.new()
	p.id = id
	p.cells = Vector3i(1, 1, 1)
	return p


func _box_with(ids: Array) -> PackedBox:
	var box := PackedBox.new(&"M")
	for id: StringName in ids:
		var p: ProductDefinition = _product(id)
		var spot: Vector3i = box.first_fit(p)
		if spot == PackedBox.NO_SPOT or not box.place(p, spot):
			_failures += 1
			printerr("FAIL: setup could not place ", id)
	return box


func _order() -> Dictionary:
	return {
		"id": "o1",
		"items": [{"product": "mug", "qty": 2}, {"product": "book", "qty": 1}],
	}


func _test_diff() -> void:
	var order: Dictionary = _order()
	var ok: PackedBox = _box_with([&"mug", &"mug", &"book"])
	var d: Dictionary = BoxContentCheck.diff(order, ok)
	var clean: bool = (d["missing"] as Dictionary).is_empty() and (d["extra"] as Dictionary).is_empty()
	_expect(clean, "exact box has no errors")
	_expect(BoxContentCheck.is_correct(order, ok), "exact box is correct")
	var short: Dictionary = BoxContentCheck.diff(order, _box_with([&"mug", &"book"]))
	_expect(short["missing"] == {&"mug": 1}, "one mug short")
	_expect((short["extra"] as Dictionary).is_empty(), "nothing extra when short")
	var gone: Dictionary = BoxContentCheck.diff(order, _box_with([&"mug", &"mug"]))
	_expect(gone["missing"] == {&"book": 1}, "the book is missing")
	var over: Dictionary = BoxContentCheck.diff(order, _box_with([&"mug", &"mug", &"book", &"book", &"lamp"]))
	_expect(over["extra"] == {&"book": 1, &"lamp": 1}, "extra unit and extra product")
	_expect((over["missing"] as Dictionary).is_empty(), "nothing missing when over")
	var none: Dictionary = BoxContentCheck.diff(order, null)
	_expect(none["missing"] == {&"mug": 2, &"book": 1}, "no box misses everything")
	_expect(not BoxContentCheck.is_correct(order, null), "no box is not correct")


func _test_two_moments() -> void:
	var order: Dictionary = _order()
	var state: Node = root.get_node("CompanyState")
	state.reset()
	var table: PackingStation = PackingStation.make(&"t1")
	table.start_box(&"M")
	for id: StringName in [&"mug", &"book"]:
		table.stage_product(id)
		_expect(table.put_in_box(_product(id), table.box.first_fit(_product(id))), "placed " + String(id))
	# Moment 1: at the table, before taping.
	var errors: Dictionary = table.content_errors(order)
	_expect(errors["missing"] == {&"mug": 1}, "the table warns about the missing mug")
	_expect(table.seal(state), "a wrong box can still be taped")
	# Moment 2: at the door.
	var door: Dictionary = BoxContentCheck.door_accepts(order, table.dispatch())
	_expect(not door["ok"], "the door rejects it")
	_expect(door["missing"] == {&"mug": 1}, "with the same reason")
	var good: PackedBox = _box_with([&"mug", &"mug", &"book"])
	_expect(BoxContentCheck.door_accepts(order, good)["ok"], "the door accepts the right box")
	_expect(
		OrderPenalties.matches_order(order, good) == BoxContentCheck.is_correct(order, good),
		"same rule as OrderPenalties"
	)
	_expect(PackingStation.make(&"t2").content_errors(order)["missing"].size() == 2, "empty table misses all")
	state.reset()
