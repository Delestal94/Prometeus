extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_delivery_note.gd
##
## Goods-received check of a supplier delivery (expansion D-0614, delivery_note.gd):
## - received_units() adds up only the pallets that were unloaded, not the ones left on the bed;
## - compare() gives a line per product with ordered, received, missing and extra;
## - a truck that left a pallet behind registers the shortfall on its day (the D-0614 test);
## - an exact delivery registers nothing, and checking a day again replaces its record;
## - a surplus is recorded as extra, not as missing;
## - totals per product across days; invalid days record nothing;
## - the JSON round trip returns the same record and a malformed save loads clean.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_received_units()
	_test_shortfall_is_recorded()
	_test_exact_and_recheck()
	_test_extra()
	_test_totals_and_invalid_day()
	_test_round_trip()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _plan(order: Dictionary, day: int) -> Array[Dictionary]:
	var s := SupplierSchedule.new()
	s.place(day - 1, [{"product": &"hen", "qty": order.get("hen", 0)}] if order.has("hen") else [])
	for key: Variant in order:
		if key != "hen":
			s.place(day - 1, [{"product": StringName(key), "qty": order[key]}])
	return s.pallets_for(day)


func _test_received_units() -> void:
	var pallets: Array[Dictionary] = _plan({"hen": 30, "vase": 5}, 2)
	_expect(pallets.size() == 3, "30 hens make 2 pallets and 5 vases 1")
	var ids: Array = [pallets[0]["id"], pallets[2]["id"]]
	var got: Dictionary = DeliveryNote.received_units(pallets, ids)
	_expect(got.get(&"hen", 0) == 24, "only the unloaded hen pallet counts (24 of 30)")
	_expect(got.get(&"vase", 0) == 5, "the vase pallet counts")
	_expect(
		DeliveryNote.received_units(pallets, []).is_empty(), "nothing unloaded, nothing received"
	)
	_expect(
		DeliveryNote.received_units([42, {"id": "x", "product": &"", "qty": 3}], ["x"]).is_empty(),
		"junk is skipped"
	)


func _test_shortfall_is_recorded() -> void:
	var note := DeliveryNote.new()
	var pallets: Array[Dictionary] = _plan({"hen": 30, "vase": 5}, 2)
	var got: Dictionary = DeliveryNote.received_units(pallets, [pallets[0]["id"], pallets[2]["id"]])
	var lines: Array[Dictionary] = note.check(2, {&"hen": 30, &"vase": 5}, got)
	_expect(lines.size() == 2 and lines[0]["product"] == &"hen", "lines come in product order")
	_expect(lines[0]["missing"] == 6 and lines[0]["extra"] == 0, "6 hens are missing")
	_expect(lines[1]["missing"] == 0, "the vases arrived complete")
	_expect(not DeliveryNote.is_exact(lines), "the delivery is not exact")
	_expect(DeliveryNote.total_missing(lines) == 6, "total missing is 6")
	_expect(note.days_with_shortfall() == [2], "day 2 is recorded as short")
	var kept: Array[Dictionary] = note.discrepancies(2)
	_expect(kept.size() == 1 and kept[0]["product"] == &"hen", "only the hen line is kept")
	_expect(note.discrepancies(3).is_empty(), "an unchecked day has no record")


func _test_exact_and_recheck() -> void:
	var note := DeliveryNote.new()
	var lines: Array[Dictionary] = note.check(1, {&"cup": 4}, {&"cup": 4})
	_expect(DeliveryNote.is_exact(lines), "4 ordered and 4 received is exact")
	_expect(note.days_with_shortfall().is_empty(), "an exact delivery registers nothing")
	note.check(1, {&"cup": 4}, {&"cup": 1})
	_expect(note.missing_totals() == {&"cup": 3}, "3 cups missing")
	note.check(1, {&"cup": 4}, {&"cup": 4})
	_expect(note.days_with_shortfall().is_empty(), "checking the day again replaces its record")


func _test_extra() -> void:
	var note := DeliveryNote.new()
	var lines: Array[Dictionary] = note.check(1, {&"cup": 2}, {&"cup": 5, &"lamp": 1})
	_expect(lines[0]["product"] == &"cup" and lines[0]["extra"] == 3, "3 extra cups")
	_expect(
		lines[1]["product"] == &"lamp" and lines[1]["ordered"] == 0,
		"an unordered product shows as extra"
	)
	_expect(DeliveryNote.total_missing(lines) == 0, "a surplus is not a shortfall")
	_expect(note.days_with_shortfall().is_empty(), "surplus alone is not a shortfall day")
	_expect(note.discrepancies(1).size() == 2, "but the surplus is on record")


func _test_totals_and_invalid_day() -> void:
	var note := DeliveryNote.new()
	note.check(2, {&"hen": 10}, {&"hen": 4})
	note.check(5, {&"hen": 3, &"cup": 2}, {})
	_expect(note.missing_totals() == {&"hen": 9, &"cup": 2}, "totals add across days")
	_expect(note.days_with_shortfall() == [2, 5], "short days ascending")
	note.check(0, {&"hen": 1}, {})
	note.check(-3, {&"hen": 1}, {})
	_expect(note.days_with_shortfall() == [2, 5], "days below 1 record nothing")
	var odd: Array[Dictionary] = DeliveryNote.compare({&"a": 0, &"b": -2}, {&"c": 0})
	_expect(odd.is_empty(), "non-positive counts make no line")


func _test_round_trip() -> void:
	var note := DeliveryNote.new()
	note.check(2, {&"hen": 10}, {&"hen": 4})
	note.check(3, {&"cup": 2}, {&"cup": 3})
	var again := DeliveryNote.from_dict(JSON.parse_string(JSON.stringify(note.to_dict())))
	_expect(again.missing_totals() == {&"hen": 6}, "missing survives JSON")
	_expect(
		again.discrepancies(3).size() == 1 and again.discrepancies(3)[0]["extra"] == 1,
		"extra survives JSON"
	)
	var bad := DeliveryNote.from_dict(
		{"records": {"x": [], "4": "no", "5": [7, {"product": ""}, {"product": "p", "ordered": 2}]}}
	)
	_expect(
		bad.days_with_shortfall() == [5] and bad.missing_totals() == {&"p": 2},
		"a malformed save loads clean"
	)
	_expect(
		DeliveryNote.from_dict({"records": 3}).days_with_shortfall().is_empty(),
		"records of the wrong type load empty"
	)
