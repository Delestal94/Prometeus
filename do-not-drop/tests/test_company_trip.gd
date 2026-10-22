extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_trip.gd
##
## Trip and TripGate (expansion D-0302, trip.gd / trip_gate.gd):
## - a vehicle with 2 dispatched boxes crossing the gate outward starts a Trip
##   with those 2 orders OUT; orders that are not PACKED stay out of the trip;
## - coming back empty closes the Trip: the delivered order stays DELIVERED and
##   the other one becomes FAILED, with the time spent outside recorded;
## - TripGate only counts crossings through the opening, in the right
##   direction, and ignores the first position it sees;
## - a closed trip cannot deliver or close again;
## - D-0319: the trip lasts as many game minutes as the real time outside x 60 / 90 (the clock
##   always runs, S3), and its summary shows the leaving and coming back time as HH:MM.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_trip_cycle()
	_test_start_skips_unpacked()
	_test_gate_crossings()
	_test_closed_trip_is_final()
	_test_trip_spends_day_hours()
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _book(ids: Array[StringName], pack: bool = true) -> OrderBook:
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	var book := OrderBook.new()
	for id: StringName in ids:
		var order := Order.make(id, "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0, products)
		book.add(order)
		if pack:
			book.mark_packed(id, StringName("box_" + str(id)))
	return book


func _test_trip_cycle() -> void:
	var book := _book([&"o1", &"o2"])
	var gate := TripGate.new(Vector3.ZERO, Vector3.BACK, 12.0)
	var trips: Array[Trip] = []
	gate.departed.connect(
		func(v: StringName) -> void:
			trips.append(Trip.start(&"t1", v, [&"o1", &"o2"], [&"box_o1", &"box_o2"], book, 480))
	)
	_expect(gate.track(&"van", Vector3(0, 0, -5)) == &"", "first position only sets the side")
	_expect(gate.track(&"van", Vector3(1, 0, 4)) == &"departed", "crossing outward departs")
	_expect(trips.size() == 1 and trips[0] != null, "a trip was created")
	var trip: Trip = trips[0]
	_expect(trip.order_ids.size() == 2, "trip holds the 2 orders")
	_expect(book.state_of(&"o1") == Order.STATE_OUT, "o1 is OUT")
	_expect(book.state_of(&"o2") == Order.STATE_OUT, "o2 is OUT")
	_expect(trip.is_out() and trip.duration_min() == -1, "trip is out, no duration yet")
	_expect(trip.deliver(&"o1", book, 90, true, 500), "o1 delivered")
	_expect(not trip.deliver(&"o1", book, 90, true, 500), "o1 cannot be delivered twice")
	_expect(not trip.deliver(&"nope", book, 90, true, 500), "foreign order refused")
	var closed: Array = []
	gate.returned.connect(func(_v: StringName) -> void: closed.append(trip.close(book, 540)))
	_expect(gate.track(&"van", Vector3(0, 0, -2)) == &"returned", "crossing inward returns")
	_expect(closed.size() == 1 and closed[0] == [&"o2"], "only the undelivered order failed")
	_expect(book.state_of(&"o1") == Order.STATE_DELIVERED, "o1 stays DELIVERED")
	_expect(book.state_of(&"o2") == Order.STATE_FAILED, "o2 is FAILED")
	_expect(trip.duration_min() == 60, "60 min outside")


func _test_start_skips_unpacked() -> void:
	var book := _book([&"o1"])
	book.add(_book([&"o3"], false).get_order(&"o3"))
	var trip := Trip.start(&"t2", &"van", [&"o1", &"o3", &"ghost"], [], book, 0)
	_expect(trip != null and trip.order_ids == [&"o1"], "only the packed order leaves")
	_expect(book.state_of(&"o3") == Order.STATE_OPEN, "unpacked order untouched")
	_expect(Trip.start(&"t3", &"van", [&"o3"], [], book, 0) == null, "nothing to carry, no trip")


func _test_gate_crossings() -> void:
	var gate := TripGate.new(Vector3(10, 0, 0), Vector3.BACK, 12.0)
	gate.track(&"van", Vector3(10, 0, -3))
	_expect(gate.track(&"van", Vector3(30, 0, 3)) == &"", "crossing beside the opening is ignored")
	_expect(gate.track(&"van", Vector3(30, 0, 4)) == &"", "staying outside does nothing")
	_expect(gate.distance(Vector3(10, 0, 2.5)) == 2.5, "distance is positive outside")
	gate.forget(&"van")
	_expect(gate.track(&"van", Vector3(10, 0, 3)) == &"", "after forget the side is learned again")
	_expect(gate.track(&"van", Vector3(11, 0, -1)) == &"returned", "inward through the opening")


func _test_closed_trip_is_final() -> void:
	var book := _book([&"o1"])
	var trip := Trip.start(&"t4", &"van", [&"o1"], [], book, 10)
	_expect(trip.close(book, 20) == [&"o1"], "closing fails the undelivered order")
	_expect(trip.close(book, 30).is_empty(), "a second close does nothing")
	_expect(trip.return_min == 20, "return time is the first close")
	_expect(not trip.deliver(&"o1", book, 100, true, 25), "closed trip delivers nothing")


func _test_trip_spends_day_hours() -> void:
	var clock := GameClock.new()
	var ticks: Array[int] = [0]
	clock.ticks = func() -> int: return ticks[0]
	clock.start(float(CompanyTuning.DAY_START_MIN))
	var book := _book([&"o1"])
	var depart: int = roundi(clock.minute_now())
	var trip := Trip.start(&"t5", &"van", [&"o1"], [], book, depart)
	ticks[0] = 270000  # 270 real s = 3 game hours at 90 s per hour
	trip.close(book, roundi(clock.minute_now()))
	var expected: float = 270.0 * 60.0 / CompanyTuning.SECONDS_PER_GAME_HOUR
	_expect(absf(float(trip.duration_min()) - expected) <= 1.0, "180 game min for 270 real s, got %d" % trip.duration_min())
	var result: Dictionary = TripResult.build(trip, book)
	_expect(result["depart_clock"] == TripResult.clock_text(depart), "summary has the leaving time")
	_expect(result["return_clock"] == TripResult.clock_text(depart + trip.duration_min()), "summary has the return time")
	_expect(TripResult.clock_text(1450) == "00:10" and TripResult.clock_text(-1) == "", "clock text wraps past midnight")
	clock.free()
