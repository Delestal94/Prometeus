extends SceneTree
## RunManager/RouteEventManager: every drawable route event succeeds or expires,
## failure clamps team money, and no challenge survives the end of a run.
## A failed "impatient client" shortens the deadline of the next house that still
## has one (and only while the run lasts); the old time bonus no longer exists.

const DeadlineCut = preload("res://scripts/core/deadline_cut.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus: Node = root.get_node(^"/root/EventBus")
	var routes: Node = root.get_node(^"/root/RouteEventManager")
	var run: Node = root.get_node(^"/root/RunManager")
	var crew: Node = root.get_node(^"/root/CrewProgression")
	var network: Node = root.get_node(^"/root/NetworkManager")
	var original_peers: Array = (network.get("peer_ids") as Array).duplicate()
	var first: DeliveryPackage = load("res://scenes/gameplay/package/package.tscn").instantiate()
	var second: DeliveryPackage = load("res://scenes/gameplay/package/package.tscn").instantiate()
	first.name = "RouteTestFirst"
	first.package_id = &"route_test_first"
	first.freeze = true
	second.name = "RouteTestSecond"
	second.package_id = &"route_test_second"
	second.trap_definition = load("res://data/traps/noisy.tres")
	second.freeze = true
	root.add_child(first)
	root.add_child(second)
	await process_frame
	first.is_loaded = true
	second.is_loaded = true
	# Real mounts with a seat looking at each: the parasite event only counts a
	# box some seat can tend (seat_tending.gd), not by the mount's name.
	var seat_script: GDScript = load("res://scripts/gameplay/interaction/seat_point.gd")
	for mount_name: String in ["LeftSeat1PackageMount", "RightSeat1PackageMount"]:
		var mount := Node3D.new()
		mount.name = mount_name
		root.add_child(mount)
		var area := Area3D.new()
		area.name = "InteractionArea"
		mount.add_child(area)
		var seat := Node3D.new()
		seat.name = mount_name.replace("PackageMount", "EyePoint")
		root.add_child(seat)
		var seat_area: Area3D = Area3D.new()
		seat_area.set_script(seat_script)
		seat_area.name = "InteractionArea"
		seat_area.set(&"role", &"passenger")
		seat_area.set(&"required_mount_path", NodePath("/root/%s/InteractionArea" % mount_name))
		seat.add_child(seat_area)
	first.current_mount_path = NodePath("/root/LeftSeat1PackageMount/InteractionArea")
	second.current_mount_path = NodePath("/root/RightSeat1PackageMount/InteractionArea")
	bus.houses_assigned.emit([[first.package_id, "First"]])
	for event_id: StringName in routes.ROUTE_POOL:
		run.reset_run()
		crew.reset_campaign()
		run.is_running = true
		first.is_open = false
		second.is_open = false
		if event_id == &"parasite_box":
			_set_peers(network, [1, 2])
		else:
			_set_peers(network, [1])
		_expect(routes.begin_event(event_id) == event_id, "%s starts (got %s)" % [event_id, routes.active_event_id])
		match event_id:
			&"inspection":
				routes._physics_process(45.0)
			&"impatient_client":
				bus.house_delivery_recorded.emit(0, &"delivered_ok", first.package_id)
			&"mixed_labels":
				bus.vehicle_impact.emit(7.0, Vector3.ZERO)
				first.set_open(true, 2)
				second.set_open(true, 3)
				_expect(int(crew.merit.get(3, 0)) == 15, "Second opener earns mixed-label merit (got %s)" % crew.merit)
			&"mimetic_package":
				var chosen: DeliveryPackage = second if routes.active_event.get("package") == second.package_id else first
				routes.on_package_impact(chosen, 99.0)
				routes._physics_process(20.0)
			&"parasite_box":
				var first_before: float = first.integrity
				var second_before: float = second.integrity
				first.apply_impact(8.0)
				var first_loss: float = first_before - first.integrity
				_expect(is_equal_approx(second_before - second.integrity, first_loss * 0.5), "Parasite copies exactly half the real damage")
				first.set_tender(1)
				second.set_tender(1)
				first._accept_tender_input(1, {"steady": true})
				second._accept_tender_input(1, {"steady": true})
				routes._physics_process(2.1)
				_expect(routes.active_event_id == &"parasite_box", "One player cannot separate both parasite boxes")
				second.set_tender(2)
				second._accept_tender_input(2, {"steady": true})
				routes._physics_process(2.0)
				_expect(int(crew.merit.get(1, 0)) == 25 and int(crew.merit.get(2, 0)) == 25, "Both parasite helpers earn merit once (got %s)" % crew.merit)
		_expect(routes.active_event_id.is_empty(), "%s resolves successfully (got %s)" % [event_id, routes.active_event_id])
		_expect(bool(routes.resolved_events.get(event_id, false)), "%s records success (got %s)" % [event_id, routes.resolved_events])
		first.set_tender(0)
		second.set_tender(0)
		first.is_open = false
		second.is_open = false
		run.reset_run()
		crew.reset_campaign()
		run.is_running = true
		if event_id == &"parasite_box":
			_set_peers(network, [1, 2])
		_expect(routes.begin_event(event_id) == event_id, "%s restarts for expiry (got %s)" % [event_id, routes.active_event_id])
		if event_id == &"inspection":
			first.is_open = true
		crew.team_money = 5
		if event_id == &"impatient_client":
			run.deadlines = run.plan_deadlines([200.0, 400.0])
		routes._physics_process(float(routes.active_event.get("duration", 90.0)) + 1.0)
		_expect(routes.active_event_id.is_empty(), "%s expires (got %s)" % [event_id, routes.active_event_id])
		_expect(routes.resolved_events.get(event_id) == false, "%s records failure (got %s)" % [event_id, routes.resolved_events])
		_expect(crew.team_money == 0, "%s fine clamps money at zero (got %s)" % [event_id, crew.team_money])
		if event_id == &"impatient_client":
			var planned: Array = run.plan_deadlines([200.0, 400.0])
			_expect(int(run.deadlines[0]["seconds"]) == int(planned[0]["seconds"]),
					"Impatient failure leaves the client's own deadline alone (got %s)" % [run.deadlines])
			_expect(int(run.deadlines[1]["seconds"]) == roundi(float(planned[1]["seconds"]) * 0.85),
					"Impatient failure cuts 15%% off the next house's deadline (got %s)" % [run.deadlines])
	_check_shortened_deadlines(run)
	run.reset_run()
	crew.reset_campaign()
	_set_peers(network, [1])
	run.is_running = true
	for _attempt: int in range(30):
		var random_id: StringName = routes.begin_random()
		_expect(random_id != &"parasite_box", "Solo draw excludes parasite (got %s)" % random_id)
		routes.reset_route()
	_expect(routes.begin_event(&"inspection") == &"inspection", "Run-end test starts inspection (got %s)" % routes.active_event_id)
	var money_before_end: int = crew.team_money
	bus.run_ended.emit(0, {})
	_expect(routes.active_event_id.is_empty(), "Run end clears active event (got %s)" % routes.active_event_id)
	_expect(crew.team_money == money_before_end, "Run end charges no fine (got %s)" % crew.team_money)
	routes.reset_route()
	run.reset_run()
	crew.reset_campaign()
	_set_peers(network, original_peers)
	first.queue_free()
	second.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: route events resolve, expire, and clean up correctly")
	quit(_failures)


## RunManager.shorten_next_deadline(): which house it picks, the floor, and when it does nothing.
func _check_shortened_deadlines(run: Node) -> void:
	run.reset_run()
	run.is_running = true
	var planned: Array = run.plan_deadlines([200.0, 400.0, 600.0])
	run.deadlines = planned.duplicate(true)
	_expect(run.shorten_next_deadline(0) == 1, "The house after the impatient one is shortened")
	_expect(int(run.deadlines[1]["seconds"]) < int(planned[1]["seconds"]), "Its deadline is earlier")
	_expect(int(run.deadlines[0]["seconds"]) == int(planned[0]["seconds"])
			and int(run.deadlines[2]["seconds"]) == int(planned[2]["seconds"]), "No other deadline moves")
	# A house already handed over has nothing left to shorten: the next open one is used.
	run.deadlines = planned.duplicate(true)
	run.register_delivery(1, &"delivered_ok", &"skipped_box")
	_expect(run.shorten_next_deadline(0) == 2, "A delivered house is skipped")
	# Late in the run the cut never leaves less than DeadlineCut.MIN_LEFT seconds.
	run.deadlines = planned.duplicate(true)
	run.elapsed_seconds = float(planned[2]["seconds"]) - 12.0
	run.register_delivery(1, &"delivered_ok", &"skipped_box")
	_expect(run.shorten_next_deadline(1) == 2
			and float(run.deadlines[2]["seconds"]) >= run.elapsed_seconds + DeadlineCut.MIN_LEFT - 1.0,
			"The cut keeps the minimum time left (got %s)" % [run.deadlines])
	# No house after the last one: the first open deadline overall takes the cut (house 1 is delivered here).
	run.elapsed_seconds = 0.0
	run.deadlines = planned.duplicate(true)
	_expect(run.shorten_next_deadline(2) == 0 and int(run.deadlines[0]["seconds"]) < int(planned[0]["seconds"]),
			"With no later house the first open deadline is shortened (got %s)" % [run.deadlines])
	# Expired deadlines are not open: with none left nothing changes.
	run.deadlines = planned.duplicate(true)
	run.elapsed_seconds = float(planned[2]["seconds"]) + 1.0
	_expect(run.shorten_next_deadline(0) == -1 and int(run.deadlines[2]["seconds"]) == int(planned[2]["seconds"]),
			"No open deadline at all: nothing happens")
	run.elapsed_seconds = 0.0
	run.is_running = false
	run.deadlines = planned.duplicate(true)
	_expect(run.shorten_next_deadline(0) == -1 and int(run.deadlines[1]["seconds"]) == int(planned[1]["seconds"]),
			"A finished run's deadlines stay put")
	run.reset_run()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1


func _set_peers(network: Node, values: Array) -> void:
	var peers: Array[int] = []
	for value: Variant in values:
		peers.append(int(value))
	network.set(&"peer_ids", peers)
