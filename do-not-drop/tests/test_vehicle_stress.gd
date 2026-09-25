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
##
## N-803 adds the delivery route (level_base.tscn: depot, curved road, houses):
## 3 simulated minutes of aggressive driving -- flat out, braking late and hard,
## swerving, only looking ahead enough to steer round a block in its lane --
## over several seeds with 4 houses. Besides NaN and falling out of
## the world it checks that the truck never ends up stuck with no safety net
## firing: every time it stops making progress for STUCK_SECONDS while the
## driver is still trying (forward and in reverse), level_base.gd must already
## have ended the run (tipped, off the route, stuck with the pedal down); a
## truck wedged upright where nothing ends the run is a soft lock the players
## can't get out of. (It found one: high-centred on the roadworks' cones and
## wall, see construction_zone_segment.gd and level_base.gd STUCK_SECONDS.)
## Physics runs 4x faster than real time (FAST_FORWARD more ticks per second,
## each still 1/60 s of simulation), so the whole test fits in the CI timeout.

const FAST_FORWARD: int = 4
const DELIVERY_SECONDS: float = 180.0
const DELIVERY_SEEDS: Array[int] = [11, 4242, 90210, 31337]
const STUCK_SECONDS: float = 12.0
const LOOKAHEAD: float = 12.0

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	# More ticks per real second, same simulated step (1/60 s): see FAST_FORWARD.
	Engine.physics_ticks_per_second = 60 * FAST_FORWARD
	Engine.time_scale = float(FAST_FORWARD)
	Engine.max_physics_steps_per_frame = 8 * FAST_FORWARD
	await _stress_endless()
	await _stress_delivery_route()
	if _failures == 0:
		print("PASS: 60s of Endless and 3 min of aggressive delivery driving stayed physically stable, and nothing got stuck unnoticed")
	quit(_failures)


func _stress_endless() -> void:
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
	root.get_node(^"/root/RunManager").call(&"reset_run")


## Drives the delivery route of each seed in turn until DELIVERY_SECONDS of
## simulated driving add up. Whenever the level ends the run (tipped, off the
## route, the goal) the truck is put back on the road further on and a new run
## starts, so the three minutes are all spent driving.
func _stress_delivery_route() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var manager: Node = root.get_node(^"/root/RunManager")
	var step: float = 1.0 / 60.0
	var driven: float = 0.0
	var endings: Dictionary = {}
	var seed_index: int = 0
	while driven < DELIVERY_SECONDS and seed_index < DELIVERY_SEEDS.size() * 3:
		var seed_value: int = DELIVERY_SEEDS[seed_index % DELIVERY_SEEDS.size()]
		seed_index += 1
		network.set(&"world_seed", seed_value)
		network.set(&"world_house_count", 4)
		var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
		root.add_child(level)
		current_scene = level
		await process_frame
		await physics_frame
		level.call(&"start_debug_delivery")
		await physics_frame
		_expect(bool(manager.get(&"is_running")), "seed %d: the delivery run starts" % seed_value)
		var van: VehicleBody3D = level.get(&"vehicle")
		var route: Node3D = level.get_node(^"World/Route")
		var path: Array[Vector3] = []
		path.assign(route.get(&"_path_points"))
		var path_index: int = 0
		var ticks: int = 0
		var stalled: float = 0.0
		var reversing: float = 0.0
		var pull_out: float = 0.0
		var escape_side: float = 1.0
		var recoveries: int = 0
		var best_progress: float = -INF
		var since_progress: float = 0.0
		# Up to a minute per seed, so every seed gets driven.
		while ticks < 60 * 60 and driven < DELIVERY_SECONDS:
			if not bool(manager.get(&"is_running")):
				var reason: String = str((manager.get(&"results") as Dictionary).get("reason", "goal"))
				endings[reason] = int(endings.get(reason, 0)) + 1
				if path_index >= path.size() - 2:
					break  # Past the goal: on to the next seed.
				path_index = mini(path_index + 3, path.size() - 2)
				await _respawn(van, route, path, path_index)
				level.set(&"tipped_seconds", 0.0)
				level.set(&"stuck_seconds", 0.0)
				manager.call(&"reset_run")
				manager.call(&"start_run")
				best_progress = -INF
				since_progress = 0.0
				stalled = 0.0
				reversing = 0.0
				pull_out = 0.0
				recoveries = 0
			var here: Vector3 = route.to_local(van.global_position)
			while path_index < path.size() - 1 and Vector2(path[path_index].x - here.x, path[path_index].z - here.z).length() < LOOKAHEAD:
				path_index += 1
			var target: Vector3 = van.global_transform.affine_inverse() * route.to_global(path[path_index])
			var t: float = float(ticks) * step
			# Aggressive: aims a little off the line, flat out, and every ~9 s
			# stamps on the brakes with the handbrake for a second.
			var steer: float = clampf(atan2(target.x, -target.z) * 2.6 + sin(t * 1.7) * 0.35, -1.0, 1.0)
			# Eyes on the road: steer round a block ahead, like a driver would,
			# instead of hitting it and relying on the reverse-out below.
			steer = clampf(steer + _avoid(van, steer), -1.0, 1.0)
			var throttle: float = 1.0
			var handbrake: bool = fmod(t, 9.0) > 8.0
			if handbrake:
				throttle = -1.0
			var speed: float = absf(float(van.get(&"speed_kmh")))
			stalled = stalled + step if speed < 2.0 and not handbrake else 0.0
			if stalled > 1.5 and reversing <= 0.0 and pull_out <= 0.0:
				# Pinned: back out at full lock, one side and then the other,
				# then pull away the other way -- what a person does, instead
				# of charging the same cone again.
				reversing = 2.5
				escape_side = 1.0 if recoveries % 2 == 0 else -1.0
				recoveries += 1
			if reversing > 0.0:
				reversing -= step
				throttle = -1.0
				steer = escape_side
				if reversing <= 0.0:
					pull_out = 1.2
			elif pull_out > 0.0:
				pull_out -= step
				throttle = 1.0
				steer = -escape_side
			van.call(&"set_controls", throttle, steer, handbrake and reversing <= 0.0)
			await physics_frame
			ticks += 1
			driven += step
			var position: Vector3 = van.global_position
			if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)
					and is_finite(van.linear_velocity.length())):
				_expect(false, "seed %d: the truck's position and velocity stay finite (got %s at %.1f s)" % [seed_value, position, t])
				break
			_expect(position.y > -10.0,
				"seed %d: the truck never falls out of the world (y %.1f at %.1f s)" % [seed_value, position.y, t])
			if position.y <= -10.0:
				break
			if not bool(manager.get(&"is_running")):
				continue
			var progress: float = float(route.call(&"road_distance", position))
			if progress > best_progress + 3.0:
				best_progress = progress
				since_progress = 0.0
				recoveries = 0
			else:
				since_progress += step
			if since_progress > STUCK_SECONDS:
				_expect(false, "seed %d: stuck %.0f s with no progress and the run still going -- nothing caught it (at %s, %.0f m along, %.1f s)" % [
					seed_value, STUCK_SECONDS, position, progress, t])
				break
			_expect(float(route.call(&"distance_from_path", position)) < 50.0,
				"seed %d: the off-route safety net ends the run before the truck is 50 m from the road (at %.1f s)" % [seed_value, t])
		level.queue_free()
		await process_frame
		manager.call(&"reset_run")
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	print("delivery stress: %.0f s driven over %d route(s), runs ended by: %s" % [driven, seed_index, endings])
	_expect(driven >= DELIVERY_SECONDS, "3 minutes of delivery driving were simulated (got %.0f s)" % driven)


## Three rays from the bumper (left, ahead, right), ignoring anything
## ground-like. With something in the way, pushes the steering toward the side
## with more free road.
func _avoid(van: VehicleBody3D, steer: float) -> float:
	var space := van.get_world_3d().direct_space_state
	var reach: float = 14.0
	var free: Array[float] = []
	for angle: float in [-0.35, 0.0, 0.35]:
		var from: Vector3 = van.global_transform * Vector3(0.0, -0.1, -2.9)
		var direction: Vector3 = van.global_basis * Vector3(sin(angle), 0.0, -cos(angle))
		direction.y = 0.0
		var query := PhysicsRayQueryParameters3D.create(from, from + direction.normalized() * reach)
		query.exclude = [van.get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() or (hit.normal as Vector3).y > 0.6:
			free.append(reach)
		else:
			free.append(from.distance_to(hit.position))
	if free[1] >= reach and minf(free[0], free[2]) >= reach * 0.5:
		return 0.0
	var bias: float = (free[2] - free[0]) / reach
	if absf(bias) < 0.15:
		bias = 0.5 if steer >= 0.0 else -0.5
	return clampf(bias * 2.0, -1.0, 1.0)


## Puts the truck back on the road at path point `index`, facing along it.
## The level froze it when the run ended (_on_run_ended, deferred).
func _respawn(van: VehicleBody3D, route: Node3D, path: Array[Vector3], index: int) -> void:
	await physics_frame
	var at: Vector3 = route.to_global(path[index])
	var ahead: Vector3 = route.to_global(path[index + 1])
	van.freeze = false
	van.global_transform = Transform3D(Basis.looking_at(ahead - at, Vector3.UP), at + Vector3.UP * 1.2)
	van.linear_velocity = Vector3.ZERO
	van.angular_velocity = Vector3.ZERO
	await physics_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
