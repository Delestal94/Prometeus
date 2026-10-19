extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dispatch_zone.gd
##
## DispatchZone, the shed's dispatch area (expansion D-0716, dispatch_zone.gd):
## - a sealed box at rest inside the area whose order is PACKED is dispatched (and only then);
##   an open box, a carried box, a box outside, or a box whose order is not packed is not;
## - a box that leaves the area before the trip is untied, and can be dispatched again;
## - load_into() stages the waiting boxes and their orders on the vehicle and empties the zone;
##   with an empty zone it stages nothing; the vehicle then leaves with them through CompanyTrips;
## - to_dict() survives a JSON round trip.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_dispatch()
	_test_leave()
	_test_load()
	_test_roundtrip()
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _book(ids: Array[StringName]) -> OrderBook:
	var book := OrderBook.new()
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	for id: StringName in ids:
		book.add(
			Order.make(
				id, "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0, products
			)
		)
		book.mark_packed(id, StringName("box_" + str(id)))
	return book


func _zone() -> DispatchZone:
	return DispatchZone.new(AABB(Vector3(0, 0, 4), Vector3(4, 2, 3)))


func _test_dispatch() -> void:
	var zone := _zone()
	var book := _book([&"o1"])
	var inside := Vector3(1, 0.2, 5)
	_expect(
		zone.update_box(&"box_o1", &"o1", inside, false, true, book) == &"",
		"open box is not dispatched"
	)
	_expect(
		zone.update_box(&"box_o1", &"o1", inside, true, false, book) == &"",
		"carried box is not dispatched"
	)
	_expect(
		zone.update_box(&"box_o1", &"o1", Vector3(9, 0, 5), true, true, book) == &"",
		"box outside is not dispatched"
	)
	_expect(
		zone.update_box(&"box_o1", &"o2", inside, true, true, book) == &"",
		"unknown order is not dispatched"
	)
	_expect(
		zone.update_box(&"box_other", &"o1", inside, true, true, book) == &"",
		"box that is not the order's is not dispatched"
	)
	_expect(not zone.is_dispatched(&"box_o1"), "nothing dispatched yet")
	_expect(
		(
			zone.update_box(&"box_o1", &"o1", inside, true, true, book)
			== DispatchZone.RESULT_DISPATCHED
		),
		"sealed box at rest inside is dispatched"
	)
	_expect(
		zone.is_dispatched(&"box_o1") and zone.order_of(&"box_o1") == &"o1",
		"box is tied to its order"
	)
	_expect(
		zone.update_box(&"box_o1", &"o1", inside, true, true, book) == &"",
		"second report changes nothing"
	)
	_expect(zone.boxes() == [&"box_o1"] and zone.orders() == [&"o1"], "box and order listed")


func _test_leave() -> void:
	var zone := _zone()
	var book := _book([&"o1"])
	zone.update_box(&"box_o1", &"o1", Vector3(1, 0, 5), true, true, book)
	_expect(
		(
			zone.update_box(&"box_o1", &"o1", Vector3(9, 0, 5), true, false, book)
			== DispatchZone.RESULT_UNDISPATCHED
		),
		"box out of the area is untied"
	)
	_expect(
		not zone.is_dispatched(&"box_o1") and zone.boxes().is_empty(), "zone empty after it left"
	)
	_expect(
		(
			zone.update_box(&"box_o1", &"o1", Vector3(2, 0, 6), true, true, book)
			== DispatchZone.RESULT_DISPATCHED
		),
		"it can be dispatched again"
	)


func _test_load() -> void:
	var trips := CompanyTrips.new()
	trips.setup(Vector3(0, 0, -4), 2.0)
	trips.minute_now = func() -> int: return 480
	var book := _book([&"o1", &"o2", &"o3"])
	trips.book = book
	var zone := _zone()
	_expect(zone.load_into(trips, &"van") == 0, "empty zone loads nothing")
	zone.update_box(&"box_o1", &"o1", Vector3(1, 0, 5), true, true, book)
	zone.update_box(&"box_o2", &"o2", Vector3(2, 0, 5), true, true, book)
	_expect(zone.load_into(trips, &"van") == 2, "two boxes loaded")
	_expect(zone.boxes().is_empty(), "zone emptied by the load")
	_expect(trips.track(&"van", Vector3(0, 0, -1)) == &"", "van inside the shed")
	trips.track(&"van", Vector3(0, 0, -8))
	var trip: Trip = trips.trip_of(&"van")
	_expect(
		trip != null and trip.order_ids == [&"o1", &"o2"], "van left with the two dispatched orders"
	)
	_expect(
		book.state_of(&"o1") == Order.STATE_OUT and book.state_of(&"o3") == Order.STATE_PACKED,
		"o1 out, o3 still packed"
	)
	trips.free()


func _test_roundtrip() -> void:
	var zone := _zone()
	var book := _book([&"o1", &"o2"])
	zone.update_box(&"box_o1", &"o1", Vector3(1, 0, 5), true, true, book)
	zone.update_box(&"box_o2", &"o2", Vector3(2, 0, 5), true, true, book)
	var copy := _zone()
	copy.from_dict(JSON.parse_string(JSON.stringify(zone.to_dict())))
	_expect(
		copy.boxes() == [&"box_o1", &"box_o2"] and copy.orders() == [&"o1", &"o2"],
		"json round trip keeps boxes and orders"
	)
