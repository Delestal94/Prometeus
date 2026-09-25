extends SceneTree
## RunManager/RouteEventManager: every drawable route event succeeds or expires,
## failure clamps team money, and no challenge survives the end of a run.

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
				first.player_input = {"steady": true}
				second.player_input = {"steady": true}
				routes._physics_process(2.1)
				_expect(routes.active_event_id == &"parasite_box", "One player cannot separate both parasite boxes")
				second.set_tender(2)
				second.player_input = {"steady": true}
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
		routes._physics_process(float(routes.active_event.get("duration", 90.0)) + 1.0)
		_expect(routes.active_event_id.is_empty(), "%s expires (got %s)" % [event_id, routes.active_event_id])
		_expect(routes.resolved_events.get(event_id) == false, "%s records failure (got %s)" % [event_id, routes.resolved_events])
		_expect(crew.team_money == 0, "%s fine clamps money at zero (got %s)" % [event_id, crew.team_money])
		if event_id == &"impatient_client":
			_expect(run.lost_time_bonus, "Impatient failure removes time bonus (got %s)" % run.lost_time_bonus)
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


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1


func _set_peers(network: Node, values: Array) -> void:
	var peers: Array[int] = []
	for value: Variant in values:
		peers.append(int(value))
	network.set(&"peer_ids", peers)
