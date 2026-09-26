extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_stuck_detection.gd
##
## level_base.gd's stuck rule (N-803): a truck that can't move while the
## driver keeps the pedal down -- high-centred on an obstacle, wheels spinning
## in the air -- ends the delivery after STUCK_SECONDS, like tipping over or
## leaving the road does, instead of leaving the crew in a soft lock. And the
## rule doesn't fire on its own: parked at a house with nobody on the pedal,
## the run goes on.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var manager: Node = root.get_node(^"/root/RunManager")
	network.set(&"world_seed", 4242)
	network.set(&"world_house_count", 1)

	# Parked, nobody on the pedal: nothing ends.
	var level: Node = await _start_level()
	var van: VehicleBody3D = level.get(&"vehicle")
	for tick: int in range(60 * 9):
		van.call(&"set_controls", 0.0, 0.0, true)
		await physics_frame
	_expect(bool(manager.get(&"is_running")), "Parked with nobody on the pedal, the run goes on (stuck %.1f s)" % float(level.get(&"stuck_seconds")))

	# Even with drive force requested, the watchdog ignores the places where
	# stopping is part of the delivery loop, plus a van with nobody driving.
	van.set(&"controls_enabled", false)
	van.set(&"engine_force", -100.0)
	van.set(&"driver_peer_id", int(network.call(&"local_id")))
	_expect(not bool(level.call(&"_should_count_as_stuck")), "Trying to leave the depot does not count as stuck")
	var house := (level.get(&"route").get(&"houses") as Array)[0] as Node3D
	van.global_position = house.global_position
	_expect(not bool(level.call(&"_should_count_as_stuck")), "Stopping beside a delivery house does not count as stuck")
	var depot := level.get(&"depot") as Node3D
	var depot_constants: Dictionary = (depot.get_script() as Script).get_script_constant_map()
	var truck_bay: Vector3 = depot_constants["TRUCK_BAY"] as Vector3
	var truck_clear_z: float = float(depot_constants["TRUCK_CLEAR_Z"])
	van.global_position = depot.to_global(Vector3(0.0, truck_bay.y, truck_clear_z - 15.0))
	van.set(&"driver_peer_id", 0)
	_expect(not bool(level.call(&"_should_count_as_stuck")), "A stopped van with no driver does not count as stuck")
	await _free_level(level)

	# Pedal down against a wall it can't move: ends as stuck.
	level = await _start_level(true)
	van = level.get(&"vehicle")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 4.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	wall.collision_layer = 1
	level.add_child(wall)
	wall.global_position = van.global_transform * Vector3(0.0, 1.5, -3.6)
	var ended_after: float = -1.0
	for tick: int in range(60 * 10):
		van.call(&"set_controls", 1.0, 0.0, false)
		await physics_frame
		if not bool(manager.get(&"is_running")):
			ended_after = float(tick) / 60.0
			break
	var reason: String = str((manager.get(&"results") as Dictionary).get("reason", ""))
	_expect(ended_after > 0.0, "Pedal down and not moving, the run ends (still running after 10 s, speed %.2f)" % van.linear_velocity.length())
	_expect(reason.contains("atascada"), "...as stuck (reason '%s')" % reason)
	_expect(ended_after >= 6.0 or ended_after < 0.0, "...and not before STUCK_SECONDS (%.1f s)" % ended_after)
	await _free_level(level)

	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	if _failures == 0:
		print("PASS: a wedged truck with the pedal down ends the run; a parked one doesn't")
	quit(_failures)


func _start_level(start_outside_depot: bool = false) -> Node:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	if start_outside_depot:
		var depot := level.get(&"depot") as Node3D
		var depot_constants: Dictionary = (depot.get_script() as Script).get_script_constant_map()
		var truck_bay: Vector3 = depot_constants["TRUCK_BAY"] as Vector3
		var truck_clear_z: float = float(depot_constants["TRUCK_CLEAR_Z"])
		var van := level.get(&"vehicle") as VehicleBody3D
		van.global_position = depot.to_global(Vector3(0.0, truck_bay.y, truck_clear_z - 15.0))
		van.reset_physics_interpolation()
	level.call(&"start_debug_delivery")
	await physics_frame
	_expect(bool(root.get_node(^"/root/RunManager").get(&"is_running")), "The run starts")
	return level


func _free_level(level: Node) -> void:
	level.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
