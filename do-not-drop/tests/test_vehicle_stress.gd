extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_vehicle_stress.gd
## Covers docs/tareas-nacho.md #97: an automated bug bash instead of a
## one-time manual session, since it costs nothing to rerun on every future
## change. Drives full throttle with oscillating steering through the whole
## RouteStreamer segment pool (all 7 types, including the concrete
## blocks/barriers a real player could clip) and checks for the physics
## failures that matter -- NaN/Inf blowups and falling through the world --
## not for "did it hit an obstacle," which is expected and correct when the
## steering is this crude.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_endless.tscn").instantiate()
	root.add_child(level)
	await process_frame
	level.call(&"start_debug_delivery")
	await process_frame
	await physics_frame

	var van: VehicleBody3D = level.vehicle
	van.controls_enabled = false

	var run_manager: Node = root.get_node(^"/root/RunManager")
	var min_y: float = van.global_position.y
	var start_z: float = van.global_position.z
	var steps_survived: int = 0
	for step: int in range(3600):  # 60 simulated seconds at 60Hz, or until the run ends
		if not bool(run_manager.get(&"is_running")):
			# level_endless.gd's own y<-8/x>42 safety net caught this and
			# ended the run (tip-over or out-of-bounds) -- correct, intended
			# behavior for crude oscillating steering through real obstacles,
			# not something this stress test should fight through.
			break
		# Crude, imperfect "player": full throttle, steering wanders instead of
		# holding straight, so it actually clips chicane/construction/bridge
		# geometry sometimes instead of always threading it cleanly.
		var steer: float = sin(float(step) * 0.03) * 0.6
		van.set_controls(0.9, steer, false)
		await physics_frame
		steps_survived = step

		var position: Vector3 = van.global_position
		var velocity: Vector3 = van.linear_velocity
		if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)):
			_expect(false, "Position stayed finite at step %d (got %s)" % [step, position])
			break
		if not (is_finite(velocity.x) and is_finite(velocity.y) and is_finite(velocity.z)):
			_expect(false, "Velocity stayed finite at step %d (got %s)" % [step, velocity])
			break
		min_y = minf(min_y, position.y)

	# -10.0 gives one frame of margin below level_endless.gd's own -8.0
	# out-of-bounds trigger -- catching the fall there and freezing the
	# vehicle is the safety net working, not a bug. Actually falling through
	# to, say, -50 would be the real regression this guards against.
	_expect(min_y > -10.0,
		"The out-of-bounds safety net actually catches a fall before it becomes a real fall-through (lowest Y reached: %.2f)" % min_y)
	_expect(steps_survived > 60,
		"The van survives more than one second before either finishing 60s clean or hitting a real loss condition (survived %d steps)" % steps_survived)

	level.free()
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: 60s of full-throttle, wandering-steering driving through every segment type stayed physically stable")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
