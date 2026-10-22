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
## - a vehicle node with cargo that would leave refused is held at the gate (D-0316.2): put back where it last
##   stood inside, stopped, never out (trips_out() unchanged, its orders PACKED, no departure_refused), and
##   departure_held tells its id, the reason and its driver_peer_id once per held_notice_msec and driver (a new
##   driver at once; every hold with 0); it keeps its own heading (a wall, not a lock); a
##   CompanyTripsView following it tells that driver (solo: itself) with WORLD_DISPATCH_FAR_LIMIT and the cap
##   (its departure_held, and held_at_gate with the cap); one with no cargo still leaves; with hold_at_gate off it
##   crosses refused as before;
## - a client's CompanyGateBrake (D-0316.4), told by its view's held_at_gate, builds the gate anew (gate_source) and,
##   on a copy it predicts, does what the host's hold does: one crossing from inside is put back where it last stood
##   inside, its heading kept; one already past the line when told is stopped where it is (the reconciler brings it
##   back); a copy not predicted is left alone; it lets go with fewer than the cap out, with the vehicle out in the
##   view, or when brake_msec is up; it brakes for longer than the host's pause between two notices;
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
	await _test_gate_hold()
	await _test_gate_brake()
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


## A stand-in vehicle with a driver, as vehicle.gd's driver_peer_id.
class DrivenVan:
	extends Node3D
	var driver_peer_id: int = 7


## A client's copy of a vehicle, predicted by this peer or not (vehicle.gd is_predicted()).
class PredictedVan:
	extends Node3D
	var predicted: bool = true

	func is_predicted() -> bool:
		return predicted


## Puts `van` at `z` (the gate's line at -4, outward -Z) and lets the gate look twice.
func _drive_to(van: Node3D, z: float) -> void:
	van.global_position = Vector3(0, 0, z)
	await physics_frame
	await physics_frame


func _test_gate_hold() -> void:
	var trips := CompanyTrips.new()
	trips.setup(Vector3(0, 0, -4), 4.0)
	trips.far_max = 1
	root.add_child(trips)
	var view := CompanyTripsView.new()
	root.add_child(view)
	view.follow(trips)
	var held: Array = []
	trips.departure_held.connect(func(id: StringName, reason: Dictionary, driver: int) -> void:
		held.append([id, reason, driver]))
	var told: Array = []
	view.departure_held.connect(func(id: StringName, text: String) -> void: told.append([id, text]))
	var capped: Array = []
	view.held_at_gate.connect(func(id: StringName, cap: int) -> void: capped.append([id, cap]))
	var refused: Array[int] = [0]
	trips.departure_refused.connect(func(_id: StringName, _reason: Dictionary) -> void: refused[0] += 1)
	_packed(trips, [&"o1", &"o2"])
	var first := Node3D.new()
	first.name = "van_out"
	var second := DrivenVan.new()
	second.name = "van_held"
	for van: Node3D in [first, second]:
		van.add_to_group(CompanyTrips.VEHICLE_GROUP)
		root.add_child(van)
		await _drive_to(van, -2.0)
	trips.stage_cargo(&"van_out", [&"o1"], [&"box_o1"])
	trips.stage_cargo(&"van_held", [&"o2"], [&"box_o2"])
	await _drive_to(first, -7.0)
	_expect(trips.trips_out() == 1, "one vehicle out on its trip: the cap (1) is reached")
	await _drive_to(second, -3.5)
	await _drive_to(second, -4.6)
	_expect(is_equal_approx(second.global_position.z, -3.5) and not trips.is_out(&"van_held")
		and trips.trips_out() == 1 and trips.book.state_of(&"o2") == Order.STATE_PACKED and refused[0] == 0,
		"the second, with cargo, is held at the gate where it last stood inside, not out (z %.2f, out %d)"
		% [second.global_position.z, trips.trips_out()])
	var verdict: Dictionary = trips.departure_verdict(&"van_held")
	_expect(held.size() == 1 and held[0][0] == &"van_held" and held[0][1] == verdict and held[0][2] == 7,
		"departure_held tells which vehicle, why and who drives it (got %s)" % [held])
	var text: String = tr(CompanyTrips.FAR_LIMIT)
	if text.count("%") == 1:
		text = text % 1
	_expect(told == [[&"van_held", text]], "the view tells its driver (solo: this peer) why (got %s)" % [told])
	_expect(capped == [[&"van_held", 1]], "...and held_at_gate carries the cap, for its GateBrake (got %s)" % [capped])
	await _drive_to(second, -6.0)
	_expect(is_equal_approx(second.global_position.z, -3.5) and held.size() == 1,
		"pushed again within held_notice_msec it is held again, and nobody is told twice (%d)" % held.size())
	second.driver_peer_id = 9
	await _drive_to(second, -6.0)
	_expect(held.size() == 2 and held[1][0] == &"van_held" and held[1][2] == 9,
		"...but a new driver within held_notice_msec is told at once (got %s)" % [held])
	second.rotation.y = 0.6
	await _drive_to(second, -6.0)
	_expect(is_equal_approx(second.rotation.y, 0.6) and is_equal_approx(second.global_position.z, -3.5),
		"held, it keeps its own heading (a wall to steer along, not a lock): yaw %.2f" % second.rotation.y)
	trips.held_notice_msec = 0
	await _drive_to(second, -5.0)
	_expect(held.size() == 3 and told.size() == 3, "...with no pause, every hold is told (%d)" % held.size())
	# The trip back in: there is room, and the held vehicle leaves with its cargo.
	await _drive_to(first, -1.0)
	await _drive_to(second, -6.0)
	_expect(trips.trip_of(&"van_held") != null and trips.book.state_of(&"o2") == Order.STATE_OUT,
		"with room again the held vehicle leaves with its cargo")
	# No cargo staged: not held (an empty vehicle doesn't count, D-0316).
	await _drive_to(first, -7.0)
	_expect(not is_equal_approx(first.global_position.z, -3.5) and not trips.is_out(&"van_out"),
		"a vehicle with no cargo crosses freely and isn't out")
	# hold_at_gate off: a vehicle with cargo crosses refused and counts as out, as before D-0316.2.
	await _drive_to(first, -2.0)
	_packed(trips, [&"o3"])
	trips.stage_cargo(&"van_out", [&"o3"], [&"box_o3"])
	trips.hold_at_gate = false
	await _drive_to(first, -7.0)
	_expect(trips.is_out(&"van_out") and refused[0] == 1 and is_equal_approx(first.global_position.z, -7.0),
		"with hold_at_gate off it crosses refused and counts as out")
	for node: Node in [first, second, view, trips]:
		node.queue_free()
	await process_frame


## D-0316.4: a client's CompanyGateBrake does to the copy it predicts what the host's hold does, once told.
func _test_gate_brake() -> void:
	var view := CompanyTripsView.new()
	root.add_child(view)
	var brake := CompanyGateBrake.new()
	var built: Array[int] = [0]
	brake.gate_source = func() -> TripGate:
		built[0] += 1
		return TripGate.new(Vector3(0, 0, -4), Vector3.FORWARD, 4.0)
	root.add_child(brake)
	brake.attach(view)
	var van := PredictedVan.new()
	van.name = "van"
	van.add_to_group(CompanyTrips.VEHICLE_GROUP)
	root.add_child(van)
	# Another vehicle out (refused, no trip): one out, the cap of 1 reached.
	_expect(view.apply_trip(CompanyTripsView.REFUSED, {"vehicle": "van_other", "minute": 0}) and view.trips_out() == 1,
		"the view has one vehicle out")
	await _drive_to(van, -3.5)
	await _drive_to(van, -4.6)
	_expect(is_equal_approx(van.global_position.z, -4.6) and not brake.is_braking(&"van") and built[0] == 1,
		"untold, a predicted copy crosses the gate (built once, the first tick it was predicted)")
	view.held_at_gate.emit(&"van", 1)
	_expect(brake.is_braking(&"van") and built[0] == 2, "told by its view, the brake is on, on the gate built anew")
	await _drive_to(van, -4.8)
	_expect(is_equal_approx(van.global_position.z, -4.8),
		"a copy already past the line when told is stopped where it is, not put back (the reconciler brings it)")
	await _drive_to(van, -3.5)
	van.rotation.y = 0.6
	await _drive_to(van, -4.6)
	_expect(is_equal_approx(van.global_position.z, -3.5) and is_equal_approx(van.rotation.y, 0.6),
		"one crossing from inside is put back where it last stood inside, its heading its own (z %.2f, yaw %.2f)"
		% [van.global_position.z, van.rotation.y])
	van.predicted = false
	await _drive_to(van, -4.6)
	_expect(is_equal_approx(van.global_position.z, -4.6),
		"a copy not predicted here (drawn from the host's) is left alone")
	van.predicted = true
	await _drive_to(van, -3.5)
	# Fewer than the cap out: the host lets it go, and so does the brake.
	var none: Array[StringName] = []
	view.apply_trip(CompanyTripsView.CLOSED, {"trip": "", "vehicle": "van_other", "failed": none, "minute": 0})
	await _drive_to(van, -4.6)
	_expect(not brake.is_braking(&"van") and is_equal_approx(van.global_position.z, -4.6),
		"with fewer than the cap out the brake lets go and the copy crosses")
	await _drive_to(van, -3.5)
	view.held_at_gate.emit(&"van", 0)
	view.apply_trip(CompanyTripsView.REFUSED, {"vehicle": "van", "minute": 0})
	await _drive_to(van, -4.6)
	_expect(not brake.is_braking(&"van") and is_equal_approx(van.global_position.z, -4.6),
		"...and when the view has the vehicle out (the host let it leave)")
	view.apply_trip(CompanyTripsView.CLOSED, {"trip": "", "vehicle": "van", "failed": none, "minute": 0})
	await _drive_to(van, -3.5)
	var default_msec: int = brake.brake_msec
	brake.brake_msec = 0
	brake.hold(&"van", 0)
	await _drive_to(van, -4.6)
	_expect(not brake.is_braking(&"van") and is_equal_approx(van.global_position.z, -4.6),
		"...and when its time is up with no new notice (brake_msec)")
	var trips := CompanyTrips.new()
	_expect(default_msec == roundi(CompanyTuning.GATE_BRAKE_REAL_SECONDS * 1000.0)
		and default_msec > trips.held_notice_msec
		and trips.held_notice_msec == roundi(CompanyTuning.GATE_HELD_NOTICE_REAL_SECONDS * 1000.0),
		"a notice brakes for longer (%d ms) than the host's pause between two notices (%d ms)"
		% [default_msec, trips.held_notice_msec])
	trips.free()
	for node: Node in [van, brake, view]:
		node.queue_free()
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
