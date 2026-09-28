extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_cargo_overboard.gd
##
## N-213.1/.2: a box that leaves the van isn't written off on the spot any
## more (level_common.gd _check_lost_cargo()):
## - it lies on the road with a rescue window, and every peer gets the relayed
##   EventBus.cargo_overboard that puts the "¡RESCATAR!" flag over it
##   (presentation/overboard_marker.gd);
## - picking it up closes the window as rescued, and it goes back on a shelf;
## - left there past the window, it's lost ("Se cayó del camión.") and the
##   flag goes away;
## - N-213.4: abandoning it closes its house's order as "lost" ("Perdido")
##   without ending the run, and the goal doesn't re-resolve it as missed.

var _failures: int = 0
var _started: Array = []
var _ended: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	var bus: Node = root.get_node(^"/root/EventBus")
	var manager: Node = root.get_node(^"/root/RunManager")
	bus.connect(&"cargo_overboard", _on_overboard)
	bus.connect(&"cargo_overboard_ended", _on_overboard_ended)
	var player: Node = level.local_player
	var vehicle: Node3D = level.get_node(^"World/Vehicle")
	var marker: Node = level.get_node(^"OverboardMarker")
	var package: Node3D = level.packages[0]
	var package_id: StringName = StringName(package.get(&"package_id"))
	var pickup: Node = package.get_node(^"InteractionArea")
	var mount: Node = vehicle.get_node(^"CargoBay/LeftShelfPackageMount/InteractionArea")
	var seat: Node = vehicle.get_node(^"CabinInterior/DriverEyePoint/InteractionArea")
	vehicle.call(&"set_door_open", &"cab_left", true)

	pickup.interact(player)
	mount.interact(player)
	seat.interact(player)
	_expect(bool(manager.get(&"is_running")), "The run starts with the box aboard")
	player.call(&"leave_seat")

	# --- it falls out: a window, not a loss ---
	var far: Vector3 = vehicle.global_position + Vector3(0.0, 0.0, 20.0)
	package.global_position = far
	level._check_lost_cargo()
	_expect(_started.size() == 1 and _started[0][0] == package_id,
		"Falling out opens a rescue window (got %s)" % [_started])
	_expect(_started.size() == 1 and float(_started[0][1]) > 15.0,
		"The window outlasts the 8-15 s rescue inside the van (got %s)" % [_started])
	_expect(int(package.get(&"trap_state")) != ITrapBehavior.TrapState.RUINED, "A box on the road isn't ruined yet")
	await process_frame
	_expect(bool(marker.call(&"has_marker", package_id)), "The fallen box gets a flag over it")
	level._check_lost_cargo()
	_expect(_started.size() == 1, "The window opens once, not every tick (got %d)" % _started.size())

	# --- somebody walks back and picks it up: rescued ---
	player.set(&"global_position", far + Vector3(1.0, 0.0, 0.0))
	pickup.interact(player)
	_expect(player.get(&"carried_package") == package, "The box on the road can be picked up")
	level._check_lost_cargo()
	_expect(_ended.size() == 1 and _ended[0] == [package_id, true],
		"Picking it up closes the window as rescued (got %s)" % [_ended])
	await process_frame
	_expect(not bool(marker.call(&"has_marker", package_id)), "The flag goes away once it's rescued")
	player.set(&"global_position", vehicle.global_position)
	mount.interact(player)
	_expect(bool(package.get(&"is_loaded")), "It goes back on the shelf")
	level._check_lost_cargo()
	_expect(_started.size() == 1, "Back aboard, no new window opens (got %d)" % _started.size())

	# --- it falls out again and nobody comes: lost ---
	# Which box house 0 waits for depends on the session seed; point its
	# order at this one so abandoning it has an order to close (N-213.4).
	var order: Array = (manager.get(&"house_assignments") as Array).duplicate(true)
	if order.is_empty():
		order.append([])
	order[0] = [package_id, "Test"]
	manager.set(&"house_assignments", order)
	level.set(&"overboard_rescue_seconds", 0.05)
	package.global_position = far
	for i: int in 10:
		level._check_lost_cargo()
	_expect(int(package.get(&"trap_state")) == ITrapBehavior.TrapState.RUINED, "Past the window, the box is lost")
	_expect(_ended.size() == 2 and _ended[1] == [package_id, false],
		"The window closes as not rescued (got %s)" % [_ended])
	await process_frame
	_expect(not bool(marker.call(&"has_marker", package_id)), "The flag goes away once it's lost")

	# --- abandoned: its order closes as "lost", the run goes on (N-213.4) ---
	var house: int = -1
	var assignments: Array = manager.get(&"house_assignments")
	for index: int in assignments.size():
		if not (assignments[index] as Array).is_empty() and StringName(assignments[index][0]) == package_id:
			house = index
	_expect(house >= 0, "The box has a house assigned (got %s)" % [assignments])
	var record: Dictionary = {}
	for entry: Dictionary in manager.get(&"deliveries"):
		if int(entry["house"]) == house:
			record = entry
	_expect(StringName(record.get("outcome", &"")) == &"lost",
		"Abandoning the box closes its order as lost (got %s)" % [record])
	_expect(bool(manager.get(&"is_running")), "Losing the only box doesn't end the run")
	_expect(bool(manager.call(&"is_empty_order", &"lost")), "A lost order counts as nothing handed over")
	var door: Node = null
	for node: Node in level.find_children("*", "", true, false):
		if node.get(&"house_index") == house and node.has_method(&"force_resolve_if_missed"):
			door = node
	if door != null:
		door.call(&"force_resolve_if_missed")
		_expect(StringName(door.get(&"outcome")) == &"lost", "Reaching the goal doesn't turn it into missed")
	var doors: Dictionary = manager.call(&"_resolve_deliveries")
	var lines: Array = []
	for line: Dictionary in doors["breakdown"]:
		lines.append(String(line["label"]))
	_expect(lines.has("Pedidos perdidos en la ruta (1)"), "The results break down the lost order (got %s)" % [lines])

	level.queue_free()
	manager.call(&"reset_run")
	await process_frame
	if _failures == 0:
		print("PASS: a box off the van gets a rescue window and a flag; abandoned, its order closes as lost")
	quit(_failures)


func _on_overboard(id: StringName, _at: Vector3, seconds: float) -> void:
	_started.append([id, seconds])


func _on_overboard_ended(id: StringName, rescued: bool) -> void:
	_ended.append([id, rescued])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
