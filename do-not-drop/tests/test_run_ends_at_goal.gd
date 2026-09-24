extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_run_ends_at_goal.gd
## A delivery ends at the goal, not at the last house: with every house
## done the run goes on (the last leg to the goal is part of the 2-5 minute
## budget, and there's all the time the delivery photo needs), and it ends,
## delivered, once the truck stops inside the goal zone.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 4242)
	network.set(&"world_house_count", 1)
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var manager: Node = root.get_node(^"/root/RunManager")
	level.call(&"start_debug_delivery")
	await physics_frame
	_expect(bool(manager.get(&"is_running")), "The run starts")

	# Every house done, the truck driving away from the last one.
	for index: int in range(int(manager.get(&"expected_houses"))):
		manager.call(&"register_delivery", index, &"delivered_ok", &"")
	var van: VehicleBody3D = level.get(&"vehicle")
	for tick: int in range(90):
		van.call(&"set_controls", 0.8, 0.0, false)
		await physics_frame
	_expect(bool(manager.get(&"is_running")), "With every house done, the run goes on to the goal")

	# Parked in the goal zone.
	var route: Node3D = level.get_node(^"World/Route")
	var goal: Transform3D = route.global_transform * (route.get(&"goal_transform") as Transform3D)
	# The boxes aboard come along, where they sit in the bay: left behind,
	# they'd count as lost and end the run for another reason.
	var aboard: Dictionary = {}
	for package: RigidBody3D in level.get(&"packages"):
		if is_instance_valid(package) and bool(package.get(&"is_loaded")):
			aboard[package] = van.global_transform.affine_inverse() * package.global_transform
	van.global_transform = Transform3D(goal.basis, goal.origin + goal.basis * Vector3(0.0, 1.0, 3.0))
	van.linear_velocity = Vector3.ZERO
	van.angular_velocity = Vector3.ZERO
	for package: RigidBody3D in aboard:
		package.global_transform = van.global_transform * (aboard[package] as Transform3D)
		package.linear_velocity = Vector3.ZERO
		package.angular_velocity = Vector3.ZERO
	var ended: bool = false
	for tick: int in range(60 * 4):
		van.call(&"set_controls", -1.0, 0.0, true)
		await physics_frame
		if not bool(manager.get(&"is_running")):
			ended = true
			break
	_expect(ended, "Stopped in the goal zone, the run ends")
	_expect(bool((manager.get(&"results") as Dictionary).get("delivered", false)), "...as delivered")

	level.queue_free()
	await process_frame
	manager.call(&"reset_run")
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	if _failures == 0:
		print("PASS: the run doesn't end at the last house, it ends stopped at the goal")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
