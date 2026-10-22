extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_trips.gd
##
## CompanyTrips, the shed gate hooked to the world (expansion D-0302.1, company_trips.gd):
## - a vehicle with cargo staged that crosses the gate outward starts a Trip with its orders OUT;
##   the cargo is spent (a second crossing starts nothing) and a vehicle with no cargo staged
##   starts none;
## - while the trip is out trips_out() counts it; coming back in closes it, the undelivered order
##   fails, and trip_started / trip_closed are emitted;
## - nodes in group company_vehicle are tracked by themselves every physics tick;
## - at most CompanyTuning.VEHICLES_FAR_MAX (2) vehicles are out at once (D-0316):
##   departure_verdict() refuses a third vehicle with WORLD_DISPATCH_FAR_LIMIT and the cap, never one
##   already out; a third that crosses anyway starts no trip (departure_refused, same reason, its
##   orders stay PACKED) but counts as out (trips_out() 3, is_out(), a fourth is refused, it isn't)
##   until it crosses back in; it keeps its cargo, which leaves with it once a trip came back;
## - forget() (D-0302.2.b): a vehicle that leaves the world no longer counts as out: its trip closes as if
##   it came back (what wasn't delivered fails, trip_closed), one out refused is back (refused_returned),
##   its staged cargo is dropped and the gate starts over with it (its next position only sets the side);
## - set_yard() (D-0302.2.b.2): inside is the rectangle behind the gate's line (back, half width), along the
##   given outward direction (a rotated shed too): leaving it by the far edge, a side or the back departs, coming
##   in by any of them returns, whatever the opening's width; without a yard the line and its opening rule as before;
## - only the vehicles of CompanyTrips' own multiplayer are tracked (another session's copy isn't);
## - CompanyRoot (solo = host) has a CompanyTrips child with the gate across the far edge of the playon outside
##   the north exit (CompanyFleet.gate_of(), D-0302.2.b.2), the shed's wall and exit on the inside of it, and
##   DayCycle.trips_out reads it.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_cycle()
	_test_far_cap()
	_test_forget()
	_test_yard()
	await _test_group_tracking()
	await _test_root()
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _packed(trips: CompanyTrips, ids: Array[StringName]) -> void:
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	for id: StringName in ids:
		trips.book.add(Order.make(id, "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0, products))
		trips.book.mark_packed(id, StringName("box_" + str(id)))


func _test_cycle() -> void:
	var trips := CompanyTrips.new()
	trips.setup(Vector3(0, 0, -4), 2.0)
	trips.minute_now = func() -> int: return 480
	_packed(trips, [&"o1", &"o2"])
	var started: Array[Trip] = []
	var closed: Array = []
	trips.trip_started.connect(func(t: Trip) -> void: started.append(t))
	trips.trip_closed.connect(func(t: Trip, f: Array[StringName]) -> void: closed.append([t, f]))
	trips.stage_cargo(&"van", [&"o1", &"o2"], [&"box_o1", &"box_o2"])
	trips.track(&"van", Vector3(0, 0, -2))
	_expect(trips.track(&"van", Vector3(0, 0, -6)) == &"departed", "crossing the exit departs")
	_expect(started.size() == 1 and trips.trips_out() == 1, "a trip started and is out")
	_expect(trips.book.state_of(&"o1") == Order.STATE_OUT, "its orders are OUT")
	_expect(trips.trip_of(&"van") == started[0] and started[0].depart_min == 480, "the van's trip, at 08:00")
	_expect(started[0].deliver(&"o1", trips.book, 90, true, 500), "o1 delivered while out")
	trips.track(&"van", Vector3(0, 0, -3))
	_expect(closed.size() == 1 and trips.trips_out() == 0, "coming back closes the trip")
	_expect(closed[0][1] == [&"o2"], "the undelivered order failed")
	_expect(trips.book.state_of(&"o2") == Order.STATE_FAILED, "o2 is FAILED")
	_expect(trips.closed_trips().size() == 1, "the closed trip is kept")
	trips.track(&"van", Vector3(0, 0, -6))
	_expect(started.size() == 1 and trips.trips_out() == 0, "the cargo was spent: a second crossing starts nothing")
	trips.track(&"empty", Vector3(0, 0, -2))
	trips.track(&"empty", Vector3(0, 0, -6))
	_expect(trips.trips_out() == 0 and started.size() == 1, "no cargo staged, no trip")
	trips.free()


func _test_yard() -> void:
	# A shed turned to face +X: outward is +X, the line at x = 10, the yard 20 m back and 5 m to each side.
	var trips := CompanyTrips.new()
	trips.setup(Vector3(10, 0, 0), 2.0, Vector3.RIGHT)
	trips.set_yard(20.0, 5.0)
	_packed(trips, [&"o1", &"o2"])
	trips.stage_cargo(&"van", [&"o1"], [&"box_o1"])
	trips.track(&"van", Vector3(4, 0, 0))
	_expect(trips.track(&"van", Vector3(4, 0, 8)) == &"departed",
		"round the side (8 m off the axis, far past the opening) the van departs")
	_expect(trips.trips_out() == 1, "...and a trip is out")
	_expect(trips.track(&"van", Vector3(4, 0, 2)) == &"returned" and trips.trips_out() == 0,
		"back in by the side it returns")
	trips.stage_cargo(&"van", [&"o2"], [&"box_o2"])
	_expect(trips.track(&"van", Vector3(11, 0, 0)) == &"departed", "through the opening it departs")
	_expect(trips.track(&"van", Vector3(11, 0, 7)) == &"", "...and stays out at the side")
	_expect(trips.track(&"van", Vector3(4, 0, 3)) == &"returned" and trips.trips_out() == 0,
		"back in by the side it returns")
	_expect(trips.track(&"van", Vector3(-11, 0, 0)) == &"departed", "out of the back of the compound it departs")
	_expect(trips.gate.side_of(Vector3(9.9, 0, 4.9)) == TripGate.INSIDE and trips.gate.side_of(Vector3(10.1, 0, 0))
		== TripGate.OUTSIDE and trips.gate.side_of(Vector3(9.9, 0, 5.1)) == TripGate.OUTSIDE, "the rectangle's edges")
	trips.free()
	# No yard: the line and its opening, as ever.
	var plain := CompanyTrips.new()
	plain.setup(Vector3(0, 0, -4), 2.0)
	plain.stage_cargo(&"van", [], [])
	plain.track(&"van", Vector3(8, 0, -2))
	_expect(plain.track(&"van", Vector3(8, 0, -6)) == &"",
		"without a yard a crossing off the opening counts for nothing")
	plain.free()


func _test_far_cap() -> void:
	var trips := CompanyTrips.new()
	trips.setup(Vector3(0, 0, -4), 2.0)
	_packed(trips, [&"o1", &"o2", &"o3"])
	var refused: Array = []
	trips.departure_refused.connect(func(id: StringName, reason: Dictionary) -> void: refused.append([id, reason]))
	_expect(trips.far_max == CompanyTuning.VEHICLES_FAR_MAX and trips.far_max == 2,
		"the cap is CompanyTuning.VEHICLES_FAR_MAX, 2 (got %d)" % trips.far_max)
	var vans: Array[StringName] = [&"van_1", &"van_2", &"van_3"]
	for index: int in vans.size():
		var order := StringName("o%d" % (index + 1))
		trips.stage_cargo(vans[index], [order], [StringName("box_" + str(order))])
		trips.track(vans[index], Vector3(0, 0, -2))
	_expect(trips.departure_verdict(&"van_3")["ok"], "with nobody out, a vehicle may leave")
	trips.track(&"van_1", Vector3(0, 0, -6))
	trips.track(&"van_2", Vector3(0, 0, -6))
	_expect(trips.trips_out() == 2, "two trips out (got %d)" % trips.trips_out())
	var verdict: Dictionary = trips.departure_verdict(&"van_3")
	_expect(not verdict["ok"] and verdict["key"] == CompanyTrips.FAR_LIMIT and verdict["args"] == [2],
		"a third vehicle may not leave, with the reason and the cap (got %s)" % [verdict])
	_expect(trips.departure_verdict(&"van_1")["ok"], "a vehicle already out is never refused")
	trips.track(&"van_3", Vector3(0, 0, -6))
	_expect(trips.trip_of(&"van_3") == null, "the third crossing starts no trip")
	_expect(trips.trips_out() == 3 and trips.is_out(&"van_3"),
		"...but the refused vehicle counts as out, so the day waits for it (got %d)" % trips.trips_out())
	_expect(refused.size() == 1 and refused[0][0] == &"van_3" and refused[0][1] == verdict,
		"departure_refused tells which vehicle and why (got %s)" % [refused])
	_expect(trips.book.state_of(&"o3") == Order.STATE_PACKED, "its order stays PACKED")
	_expect(trips.departure_verdict(&"van_3")["ok"], "a refused vehicle already out is not refused again")
	_expect(not trips.departure_verdict(&"van_4")["ok"], "a fourth is refused")
	trips.track(&"van_1", Vector3(0, 0, -2))
	_expect(trips.trips_out() == 2 and not trips.departure_verdict(&"van_4")["ok"],
		"one trip back with the refused one still out: still full (got %d)" % trips.trips_out())
	trips.track(&"van_3", Vector3(0, 0, -2))
	_expect(trips.trips_out() == 1 and not trips.is_out(&"van_3"), "the refused one back: it is in again")
	_expect(trips.departure_verdict(&"van_3")["ok"], "a slot is free")
	trips.track(&"van_3", Vector3(0, 0, -6))
	var third: Trip = trips.trip_of(&"van_3")
	_expect(third != null and third.order_ids == [&"o3"], "the kept cargo leaves with it now")
	_expect(trips.trips_out() == 2, "two out again (got %d)" % trips.trips_out())
	trips.free()


func _test_forget() -> void:
	var trips := CompanyTrips.new()
	trips.setup(Vector3(0, 0, -4), 2.0)
	trips.far_max = 1
	_packed(trips, [&"o1", &"o2", &"o3"])
	var closed: Array = []
	var back: Array[StringName] = []
	trips.trip_closed.connect(func(t: Trip, f: Array[StringName]) -> void: closed.append([t.vehicle_id, f]))
	trips.refused_returned.connect(func(id: StringName) -> void: back.append(id))
	trips.stage_cargo(&"van_out", [&"o1"], [&"box_o1"])
	trips.stage_cargo(&"van_refused", [&"o2"], [&"box_o2"])
	for van: StringName in [&"van_out", &"van_refused"]:
		trips.track(van, Vector3(0, 0, -2))
		trips.track(van, Vector3(0, 0, -6))
	_expect(trips.trip_of(&"van_out") != null and trips.is_out(&"van_refused") and trips.trips_out() == 2,
		"one vehicle out on a trip, one out refused (got %d out)" % trips.trips_out())
	trips.forget(&"van_out")
	_expect(trips.trips_out() == 1 and trips.trip_of(&"van_out") == null
		and closed == [[&"van_out", [&"o1"] as Array[StringName]]]
		and trips.book.state_of(&"o1") == Order.STATE_FAILED,
		"forgetting a vehicle on a trip closes it, its undelivered order failed (got %s)" % [closed])
	trips.forget(&"van_refused")
	_expect(trips.trips_out() == 0 and back == [&"van_refused"] and closed.size() == 1,
		"forgetting one out refused brings it back, no trip closes (back %s)" % [back])
	trips.track(&"van_refused", Vector3(0, 0, -2))
	trips.track(&"van_refused", Vector3(0, 0, -6))
	_expect(trips.trips_out() == 0 and trips.book.state_of(&"o2") == Order.STATE_PACKED,
		"...its staged cargo was dropped: crossing again starts nothing")
	trips.stage_cargo(&"van_new", [&"o3"], [&"box_o3"])
	trips.track(&"van_new", Vector3(0, 0, -6))
	trips.forget(&"van_new")
	trips.track(&"van_new", Vector3(0, 0, -2))
	_expect(trips.trips_out() == 0 and closed.size() == 1,
		"a forgotten vehicle's next position only sets its side (got %d out)" % trips.trips_out())
	trips.free()


func _test_group_tracking() -> void:
	var trips := CompanyTrips.new()
	trips.setup(Vector3(0, 0, -4), 4.0)
	root.add_child(trips)
	_packed(trips, [&"o1"])
	var van := Node3D.new()
	van.name = "van"
	van.add_to_group(CompanyTrips.VEHICLE_GROUP)
	root.add_child(van)
	van.global_position = Vector3(0, 0, -2)
	trips.stage_cargo(&"van", [&"o1"], [&"box_o1"])
	await physics_frame
	await physics_frame
	van.global_position = Vector3(0, 0, -7)
	await physics_frame
	await physics_frame
	_expect(trips.trips_out() == 1, "a node in the vehicle group is tracked by the physics tick")
	van.global_position = Vector3(0, 0, -1)
	await physics_frame
	await physics_frame
	_expect(trips.trips_out() == 0, "...and its return closes the trip")
	# Another session in this tree (its own SceneMultiplayer): its copy of a vehicle is not this gate's.
	var side := Node.new()
	side.name = "OtherSession"
	root.add_child(side)
	set_multiplayer(SceneMultiplayer.new(), side.get_path())
	_packed(trips, [&"o2"])
	trips.stage_cargo(&"van", [&"o2"], [&"box_o2"])
	var started: Array[int] = [0]
	trips.trip_started.connect(func(_trip: Trip) -> void: started[0] += 1)
	var copy := Node3D.new()
	copy.name = "van"
	copy.add_to_group(CompanyTrips.VEHICLE_GROUP)
	side.add_child(copy)
	copy.global_position = Vector3(0, 0, -7)
	await physics_frame
	await physics_frame
	_expect(started[0] == 0 and trips.trips_out() == 0,
		"another session's copy, out there under the same name, is not tracked (%d trips started)" % started[0])
	set_multiplayer(null, side.get_path())
	side.free()
	van.queue_free()
	trips.queue_free()
	await process_frame


func _test_root() -> void:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level: CompanyRoot = (load("res://scenes/gameplay/company_root.tscn") as PackedScene).instantiate()
	level.save_dir = "user://test_company_trips"
	root.add_child(level)
	await process_frame
	await physics_frame
	var trips: CompanyTrips = level.get(&"trips")
	_expect(trips != null and trips.get_parent() == level, "the host root has CompanyTrips")
	if trips != null:
		var half_depth: float = CompanyRoot.SHED_SIZE.y * 0.5
		var edge: float = half_depth + CompanyShed.WALL_THICKNESS + CompanyFleet.PLAYON_DEPTH_M
		_expect(is_equal_approx(trips.gate.distance(Vector3(0, 0, -edge - 1.0)), 1.0)
			and is_equal_approx(trips.gate.distance(Vector3(0, 0, -half_depth - 1.0)), 1.0 - edge + half_depth),
			"the gate lies across the far edge of the playon outside the north exit")
		_expect(level.day_cycle.trips_out.is_valid() and level.day_cycle.trips_out.call() == 0,
			"DayCycle reads trips_out from it")
	level.queue_free()
	await process_frame
	state.call(&"reset")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_company_trips"))
