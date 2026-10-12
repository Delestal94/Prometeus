extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_supplier_schedule.gd
##
## Supplier delivery calendar (expansion D-0602, supplier_schedule.gd):
## - an order placed on day N arrives on day N + 1, at 08:30, and waits until 11:30;
## - a 3-day calendar keeps each truck's products apart and lists upcoming days in order;
## - two orders of one product on one day merge, and pallets_for() splits them into
##   pallets of at most 24 units with unique ids;
## - truck_state() goes pending -> at_dock -> left, and none on a day without truck;
## - invalid orders change nothing; clear_day() removes a delivery;
## - the JSON round trip returns the same calendar and a malformed save loads clean.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_timing()
	_test_three_day_calendar()
	_test_merge_and_pallets()
	_test_truck_state()
	_test_invalid_and_clear()
	_test_round_trip()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _test_timing() -> void:
	_expect(SupplierSchedule.arrival_day(3) == 4, "ordered on day 3 arrives on day 4")
	_expect(SupplierSchedule.arrival_minute() == 8 * 60 + 30, "truck pulls in at 08:30")
	_expect(SupplierSchedule.departure_minute() == 11 * 60 + 30, "truck waits 3 h and leaves at 11:30")


func _test_three_day_calendar() -> void:
	var s := SupplierSchedule.new()
	_expect(s.place(1, [{"product": &"hen", "qty": 10}]), "day 1 order is accepted")
	_expect(s.place(2, [{"product": &"vase", "qty": 5}, {"product": &"hen", "qty": 2}]), "day 2 order")
	_expect(s.place(3, [{"product": &"lamp", "qty": 1}]), "day 3 order")
	_expect(s.upcoming_days(0) == [2, 3, 4], "trucks come on days 2, 3 and 4")
	_expect(s.upcoming_days(3) == [3, 4], "upcoming_days skips days already past")
	_expect(not s.has_delivery(1), "nothing arrives on day 1")
	_expect(s.ordered_for(2) == {&"hen": 10}, "day 2 truck brings the day 1 order")
	_expect(
		s.ordered_for(3) == {&"vase": 5, &"hen": 2}, "day 3 truck brings the day 2 order, products apart"
	)
	_expect(s.ordered_for(9).is_empty(), "a day without truck has no order")


func _test_merge_and_pallets() -> void:
	var s := SupplierSchedule.new()
	s.place(1, [{"product": &"hen", "qty": 20}])
	s.place(1, [{"product": &"hen", "qty": 10}, {"product": &"cup", "qty": 3}])
	_expect(s.ordered_for(2) == {&"hen": 30, &"cup": 3}, "two orders of one day merge")
	var pallets: Array[Dictionary] = s.pallets_for(2)
	var units: Dictionary = {}
	var ids: Dictionary = {}
	for p: Dictionary in pallets:
		units[p["product"]] = int(units.get(p["product"], 0)) + int(p["qty"])
		ids[p["id"]] = true
		_expect(Pallet.validate(p).is_empty(), "pallet %s is valid" % p["id"])
	_expect(pallets.size() == 3, "30 hens make 2 pallets and 3 cups one")
	_expect(units == {&"hen": 30, &"cup": 3}, "pallets carry exactly what was ordered")
	_expect(ids.size() == pallets.size(), "pallet ids are unique")
	_expect(pallets[0]["id"] == &"d2_cup_1", "products come in id order and ids carry the day")
	_expect(s.pallets_for(5).is_empty(), "no pallets on a day without truck")


func _test_truck_state() -> void:
	var s := SupplierSchedule.new()
	s.place(1, [{"product": &"hen", "qty": 1}])
	_expect(s.truck_state(1, 9 * 60) == SupplierSchedule.STATE_NONE, "no truck on day 1")
	_expect(s.truck_state(2, 8 * 60) == SupplierSchedule.STATE_PENDING, "08:00 not in yet")
	_expect(s.truck_state(2, 8 * 60 + 30) == SupplierSchedule.STATE_AT_DOCK, "08:30 it is in")
	_expect(s.truck_state(2, 11 * 60 + 29) == SupplierSchedule.STATE_AT_DOCK, "11:29 still waiting")
	_expect(s.truck_state(2, 11 * 60 + 30) == SupplierSchedule.STATE_LEFT, "11:30 it leaves")


func _test_invalid_and_clear() -> void:
	var s := SupplierSchedule.new()
	_expect(not s.place(-1, [{"product": &"hen", "qty": 1}]), "negative day is refused")
	_expect(not s.place(1, []), "empty order is refused")
	_expect(not s.place(1, [{"product": &"hen", "qty": 0}]), "zero units are refused")
	_expect(not s.place(1, [{"product": &"", "qty": 2}]), "empty product is refused")
	_expect(
		not s.place(1, [{"product": &"hen", "qty": 2}, {"product": &"cup", "qty": -1}]),
		"one bad line refuses the whole order"
	)
	_expect(s.upcoming_days(0).is_empty(), "refused orders leave the calendar empty")
	s.place(1, [{"product": &"hen", "qty": 2}])
	s.clear_day(2)
	_expect(not s.has_delivery(2), "clear_day removes the delivery")


func _test_round_trip() -> void:
	var s := SupplierSchedule.new()
	s.place(1, [{"product": &"hen", "qty": 30}])
	s.place(4, [{"product": &"cup", "qty": 2}])
	var text: String = JSON.stringify(s.to_dict())
	var back: SupplierSchedule = SupplierSchedule.from_dict(JSON.parse_string(text))
	_expect(back.upcoming_days(0) == [2, 5], "round trip keeps the days")
	_expect(back.ordered_for(2) == {&"hen": 30}, "round trip keeps the quantities")
	var junk: SupplierSchedule = SupplierSchedule.from_dict(
		{"deliveries": {"x": {"hen": 1}, "3": "no", "4": {"hen": -2, "": 3, "cup": 2}, "0": {"a": 1}}}
	)
	_expect(junk.upcoming_days(0) == [4], "malformed entries are skipped, valid ones kept")
	_expect(junk.ordered_for(4) == {&"cup": 2}, "bad quantities and empty products are dropped")
	_expect(SupplierSchedule.from_dict({"deliveries": 5}).upcoming_days(0).is_empty(), "wrong type loads empty")
