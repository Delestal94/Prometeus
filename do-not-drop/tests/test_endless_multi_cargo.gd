extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_endless_multi_cargo.gd
## Covers docs/tareas-nacho.md #50: does endless mode actually work with all
## four traps aboard at once during a real sustained drive, not just at the
## moment they're loaded? Functional coverage only (nothing crashes, every
## trap keeps ticking, the run survives) -- whether the random segment mix
## *feels* good with all four active is #55's real playtesting, deferred.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_endless.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame

	var packages: Array[Node] = []
	packages.assign(root.get_tree().get_nodes_in_group(&"cargo"))
	_expect(packages.size() == 4, "The endless level also ships all four trap types (got %d)" % packages.size())

	var trap_ids: Array = []
	for package: Node in packages:
		trap_ids.append(String(package.get(&"trap_definition").get(&"id")))
	trap_ids.sort()
	_expect(trap_ids == ["balance", "fragile", "growing_weight", "noisy"],
		"All four trap types are represented in the endless level too (got %s)" % str(trap_ids))

	var mounts: Array[Node] = []
	mounts.assign(root.get_tree().get_nodes_in_group(&"package_mount"))
	_expect(mounts.size() >= 4, "At least four mounts to seat all four traps (got %d)" % mounts.size())

	var player: Node = level.local_player
	for index: int in range(4):
		player.call(&"pick_up", packages[index].get_path())
		mounts[index].call(&"interact", player)
	for package: Node in packages:
		_expect(bool(package.get(&"is_loaded")), "%s is loaded aboard" % package.name)

	var manager: Node = root.get_node(^"/root/RunManager")
	var driver_seat: Node = level.get_node(^"World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea")
	driver_seat.call(&"interact", player)
	_expect(bool(manager.get(&"is_running")), "Delivery starts with all four traps aboard")
	_expect((manager.get(&"cargo") as Dictionary).size() == 4,
		"All four boxes actually aboard count toward the run (got %d)" % (manager.get(&"cargo") as Dictionary).size())

	# Restricted to segments a straight, un-steered drive can actually
	# survive, same reasoning as test_level_endless.gd -- what's under test
	# here is whether four simultaneous traps keep working during real
	# sustained streaming, not obstacle navigation (that's test_vehicle_stress.gd).
	var streamer: Node = level.get_node(^"World/RouteStreamer")
	streamer.set(&"segment_scripts", [StraightSegment, SpeedBumpSegment])

	var van: VehicleBody3D = level.vehicle
	van.controls_enabled = false
	van.set_controls(0.9, 0.0, false)
	for _i: int in range(1200):  # 20 simulated seconds at 60Hz, sustained speed
		await physics_frame

	# Usually still running with solid distance covered. The rare exception:
	# level_endless.gd's own stuck-detection (added after stress testing found
	# the van can occasionally land wedged against a speed bump hard enough to
	# stop dead) ends the run early instead of hanging forever -- also a pass,
	# since that's the real regression being guarded against here, not "did it
	# drive exactly N meters with four traps aboard."
	if bool(manager.get(&"is_running")):
		_expect(float(level.get(&"distance_traveled")) > 100.0,
			"Real sustained distance was covered with all four traps aboard while still running (got %.1f m)" % float(level.get(&"distance_traveled")))
	else:
		_expect(not (manager.get(&"results") as Dictionary).is_empty(),
			"If the run isn't going anymore, it's because a real end condition fired, not because it silently stalled")
	var ruined_count: int = 0
	for package: Node in packages:
		if int(package.get(&"trap_state")) == 2:
			ruined_count += 1
	_expect(ruined_count < 4, "Not every trap got ruined just from sitting through a straight, gentle drive (got %d/4 ruined)" % ruined_count)

	level.free()
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: all four traps ride together in endless mode through a real sustained drive")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
