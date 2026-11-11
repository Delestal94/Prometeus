extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_supplier_departure.gd
##
## The supplier truck driving off (expansion D-0618, supplier_departure.gd):
## - before the departure minute the truck stays and nothing is taken;
## - at the departure minute it leaves with the pallets that were not unloaded (the D-0618 test);
## - an unloaded delivery leaves nothing behind and the note comes out exact;
## - the leftover shows up as missing in the DeliveryNote lines and the day is cleared;
## - a day without truck never "leaves"; junk in the pallet list is skipped.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_waits_until_departure()
	_test_takes_what_is_left()
	_test_all_unloaded()
	_test_no_truck_and_junk()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _schedule() -> SupplierSchedule:
	var s := SupplierSchedule.new()
	s.place(1, [{"product": &"hen", "qty": 30}, {"product": &"vase", "qty": 5}])
	return s


func _test_waits_until_departure() -> void:
	var s: SupplierSchedule = _schedule()
	var pallets: Array[Dictionary] = s.pallets_for(2)
	var before: int = SupplierSchedule.departure_minute() - 1
	var r: Dictionary = SupplierDeparture.resolve(s, 2, before, pallets, [])
	_expect(not r["left"], "the truck is still waiting a minute before it leaves")
	_expect((r["taken"] as Dictionary).is_empty(), "nothing is taken while it waits")
	_expect(s.has_delivery(2), "the delivery stays in the calendar")


func _test_takes_what_is_left() -> void:
	var s: SupplierSchedule = _schedule()
	var pallets: Array[Dictionary] = s.pallets_for(2)
	var unloaded: Array = [pallets[0]["id"], pallets[2]["id"]]
	var r: Dictionary = SupplierDeparture.resolve(
		s, 2, SupplierSchedule.departure_minute(), pallets, unloaded
	)
	_expect(r["left"], "the truck leaves at the departure minute")
	_expect(r["taken"].get(&"hen", 0) == 6, "it takes the 6 hens still on the bed")
	_expect(not (r["taken"] as Dictionary).has(&"vase"), "the unloaded vases stay")
	var lines: Array = r["note_lines"]
	_expect(lines.size() == 2 and lines[0]["missing"] == 6, "the note lines show 6 hens missing")
	_expect(not s.has_delivery(2), "the delivery is cleared once the truck left")


func _test_all_unloaded() -> void:
	var s: SupplierSchedule = _schedule()
	var pallets: Array[Dictionary] = s.pallets_for(2)
	var ids: Array = []
	for p: Dictionary in pallets:
		ids.append(p["id"])
	var r: Dictionary = SupplierDeparture.resolve(
		s, 2, SupplierSchedule.departure_minute() + 30, pallets, ids
	)
	_expect(r["left"] and (r["taken"] as Dictionary).is_empty(), "an empty bed leaves nothing")
	_expect(DeliveryNote.is_exact(r["note_lines"]), "the note is exact")


func _test_no_truck_and_junk() -> void:
	var s := SupplierSchedule.new()
	_expect(
		not SupplierDeparture.has_left(s, 5, 24 * 60), "a day without a truck never has it leave"
	)
	var taken: Dictionary = SupplierDeparture.taken_units(
		[42, {"id": "x", "product": &"", "qty": 3}, {"id": "y", "product": &"cup", "qty": 2}], []
	)
	_expect(taken == {&"cup": 2}, "junk pallets are skipped")
