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
	level.set(&"overboard_rescue_seconds", 0.05)
	package.global_position = far
	for i: int in 10:
		level._check_lost_cargo()
	_expect(int(package.get(&"trap_state")) == ITrapBehavior.TrapState.RUINED, "Past the window, the box is lost")
	_expect(_ended.size() == 2 and _ended[1] == [package_id, false],
		"The window closes as not rescued (got %s)" % [_ended])
	await process_frame
	_expect(not bool(marker.call(&"has_marker", package_id)), "The flag goes away once it's lost")

	level.queue_free()
	manager.call(&"reset_run")
	await process_frame
	if _failures == 0:
		print("PASS: a box off the van gets a rescue window, a flag, and is lost only when it runs out")
	quit(_failures)


func _on_overboard(id: StringName, _at: Vector3, seconds: float) -> void:
	_started.append([id, seconds])


func _on_overboard_ended(id: StringName, rescued: bool) -> void:
	_ended.append([id, rescued])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
