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
## - CompanyRoot (solo = host) has a CompanyTrips child with the gate across the exit (north wall)
##   and DayCycle.trips_out reads it.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_cycle()
	_test_far_cap()
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
		_expect(is_equal_approx(trips.gate.distance(Vector3(0, 0, -half_depth - 1.0)), 1.0),
			"the gate lies across the north exit")
		_expect(level.day_cycle.trips_out.is_valid() and level.day_cycle.trips_out.call() == 0,
			"DayCycle reads trips_out from it")
	level.queue_free()
	await process_frame
	state.call(&"reset")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_company_trips"))
