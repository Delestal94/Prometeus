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
##   flag goes away.
## N-213.4: abandoning it closes that house's order empty (outcome &"lost",
## "PERDIDO" in the results) without ending the run, even with nothing else
## aboard; the house can't be rung for it afterwards and it pays like a missed
## door, with its own line.
## N-213.3: the rescue hook (a depot supply, gameplay/vehicle/rescue_hook.gd)
## rides along only on the run that took it; from the open rear doors it
## snags a fallen box within reach into the passenger's hands, which closes
## its window as rescued, and then needs a moment before the next throw.

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
	var hook: Node3D = vehicle.get_node(^"RescueHook")
	_expect(not bool(hook.get(&"armed")), "The rescue hook stays stowed until a run takes it")
	# Bought at the depot: begin_run() hands it to the run that leaves.
	(root.get_node(^"/root/CrewProgression").get(&"supplies") as Dictionary)[&"rescue_hook"] = true

	pickup.interact(player)
	mount.interact(player)
	seat.interact(player)
	_expect(bool(hook.get(&"armed")), "The run that took the hook from the depot carries it")
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

	# --- N-213.3: the rescue hook snags it from the open rear doors ---
	vehicle.call(&"set_door_open", &"rear", true)
	player.set(&"global_position", hook.global_position)
	_expect(not bool(hook.call(&"can_interact", player)), "With the box on its shelf there's nothing to hook")
	var behind: Vector3 = hook.global_position + vehicle.global_basis.z * 5.0
	package.global_position = behind
	level._check_lost_cargo()
	_expect(_started.size() == 2, "Falling out again opens a new window (got %d)" % _started.size())
	package.global_position = hook.global_position + vehicle.global_basis.z * 12.0
	_expect(not bool(hook.call(&"can_interact", player)), "A box far down the road is out of the hook's reach")
	package.global_position = behind
	vehicle.call(&"set_door_open", &"rear", false)
	_expect(not bool(hook.call(&"can_interact", player)), "With the rear doors shut there's no hooking")
	vehicle.call(&"set_door_open", &"rear", true)
	_expect(bool(hook.call(&"can_interact", player)), "A fallen box close behind can be hooked")
	hook.call(&"interact", player)
	_expect(player.get(&"carried_package") == package, "The hook puts the box in the passenger's hands")
	level._check_lost_cargo()
	_expect(_ended.size() == 2 and _ended[1] == [package_id, true],
		"Hooking it closes the window as rescued (got %s)" % [_ended])
	_expect(float(hook.get(&"_cooldown_left")) > 0.0, "The hook needs a moment before the next throw")
	player.set(&"global_position", vehicle.global_position)
	mount.interact(player)
	_expect(bool(package.get(&"is_loaded")), "The hooked box goes back on the shelf")

	# --- it falls out again and nobody comes: lost ---
	# Pinned so the test doesn't depend on which door the depot picked.
	var house: Node = (level.get_node(^"World/Route").get(&"houses") as Array)[0]
	house.set(&"assigned_package_id", package_id)
	level.set(&"overboard_rescue_seconds", 0.05)
	package.global_position = far
	for i: int in 10:
		level._check_lost_cargo()
	_expect(int(package.get(&"trap_state")) == ITrapBehavior.TrapState.RUINED, "Past the window, the box is lost")
	_expect(_ended.size() == 3 and _ended[2] == [package_id, false],
		"The window closes as not rescued (got %s)" % [_ended])
	await process_frame
	_expect(not bool(marker.call(&"has_marker", package_id)), "The flag goes away once it's lost")

	# --- N-213.4: abandoning it closes its order empty, the run goes on ---
	_expect(bool(manager.get(&"is_running")), "Losing the only box on the road doesn't end the run")
	_expect(bool(house.get(&"delivered")) and StringName(house.get(&"outcome")) == &"lost",
		"Its house's order closes as lost (got %s)" % house.get(&"outcome"))
	var records: Array = (manager.get(&"deliveries") as Array).filter(func(entry: Dictionary) -> bool:
		return StringName(entry["package_id"]) == package_id)
	_expect(records.size() == 1 and StringName(records[0]["outcome"]) == &"lost",
		"RunManager records the order as lost (got %s)" % [records])
	_expect(not bool(manager.call(&"_mark_photo", int(house.get(&"house_index")))),
		"There's nothing to photograph at a door whose box was lost")
	var doors: Dictionary = manager.call(&"_resolve_deliveries")
	_expect(int(doors.get("houses_lost", 0)) == 1 and int(doors.get("houses_missed", 0)) == 0,
		"The lost order is counted apart from missed doors (got %s)" % [doors])
	var lines: Array = (doors["breakdown"] as Array).filter(func(line: Dictionary) -> bool:
		return String(line["label"]) == "HUD_SCORE_LOST")
	_expect(lines.size() == 1 and int(lines[0]["points"]) < 0, "The results list the lost box as a penalty")
	manager.call(&"finish_run", true)
	_expect(int((manager.get(&"results") as Dictionary).get("houses_lost", 0)) == 1,
		"The results carry the lost order for the HUD and the depot's streak board")
	_expect(not bool(hook.get(&"armed")), "The hook is stowed again when the run ends")
	_expect(not bool(level.get_node(^"World/Route").call(&"close_lost_order", package_id)),
		"An order closes only once")

	level.queue_free()
	manager.call(&"reset_run")
	await process_frame
	if _failures == 0:
		print("PASS: a box off the van gets a rescue window, a flag and the hook, and is lost only when it runs out")
	quit(_failures)


func _on_overboard(id: StringName, _at: Vector3, seconds: float) -> void:
	_started.append([id, seconds])


func _on_overboard_ended(id: StringName, rescued: bool) -> void:
	_ended.append([id, rescued])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
