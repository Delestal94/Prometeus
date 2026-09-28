extends SceneTree
## Measures a complete delivery with the real S-108 autopilot and a delivery bot (S-110).
##   <godot> --headless --fixed-fps 60 --path do-not-drop --script res://tests/bench_delivery_time.gd
## Optional: -- --seeds=1081,1082,1084,1085,1087 --houses=1,2,3,4 --cruise=50
##
## Unlike bench_route_duration.gd, stops are not a fixed 25-second estimate. At every house an
## actual Player picks up an actual DeliveryPackage, walks from the parked van to the real
## doorbell at Player.WALK_SPEED, rings it through DoorbellPoint, and walks back before the
## autopilot continues. Short exit, pickup, ring and boarding pauses represent the actions that
## happen around the walking itself. The benchmark fails if any door is not resolved.

const LOOKAHEAD: float = 14.0
## Same radius level_base.gd accepts as a legitimate house stop. With the van's measured
## 6 m braking distance this parks alongside the yard instead of ~40 m before the door.
const BRAKE_DISTANCE: float = 18.0
const MAX_DELIVERY_SECONDS: float = 600.0
const EXIT_SECONDS: float = 1.0
const PICKUP_SECONDS: float = 1.3
const RING_SECONDS: float = 0.35
const BOARD_SECONDS: float = 1.0
const BOT_WALK_SPEED: float = 3.6  # Player.WALK_SPEED; constants are not runtime properties.
const DEFAULT_SEEDS: Array[int] = [1081, 1082, 1084, 1085, 1087]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	var seeds: Array[int] = []
	for value: String in _arg("seeds", "1081,1082,1084,1085,1087").split(","):
		seeds.append(int(value))
	if seeds.is_empty():
		seeds = DEFAULT_SEEDS.duplicate()
	var house_counts: Array[int] = []
	for value: String in _arg("houses", "1,2,3,4").split(","):
		house_counts.append(int(value))
	var cruise_kmh: float = float(_arg("cruise", "50"))
	print("BENCH complete delivery: seeds %s, houses %s, cruise %.0f km/h" % [seeds, house_counts, cruise_kmh])
	var summary: Dictionary = {}
	for houses: int in house_counts:
		summary[houses] = []
		for seed_value: int in seeds:
			var result: Dictionary = await _deliver(seed_value, houses, cruise_kmh)
			summary[houses].append(result)
			print("RUN seed=%d houses=%d length=%.0fm drive=%.1fs stops=%.1fs total=%.2fmin delivered=%d rescues=%d%s"
					% [
				seed_value, houses, result.length, result.drive, result.stops, result.total / 60.0,
				result.delivered, result.rescues, "" if result.finished else " UNFINISHED"])
	print("")
	print("| Casas | Largo medio (m) | Manejo medio (s) | Paradas medias (s) | Minutos promedio | Máximo | Mínimo |")
	print("|---|---:|---:|---:|---:|---:|---:|")
	for houses: int in house_counts:
		var runs: Array = summary[houses]
		var length_sum: float = 0.0
		var drive_sum: float = 0.0
		var stop_sum: float = 0.0
		var total_sum: float = 0.0
		var worst: float = 0.0
		var best: float = INF
		for result: Dictionary in runs:
			length_sum += result.length
			drive_sum += result.drive
			stop_sum += result.stops
			total_sum += result.total
			worst = maxf(worst, result.total)
			best = minf(best, result.total)
		var count: float = float(runs.size())
		print("| %d | %.0f | %.1f | %.1f | %.2f | %.2f | %.2f |" % [
			houses, length_sum / count, drive_sum / count, stop_sum / count,
			total_sum / count / 60.0, worst / 60.0, best / 60.0])
	print("%s bench_delivery_time: %d physical deliveries" % ["PASS" if _failures == 0 else "FAIL",
			house_counts.size() * seeds.size()])
	quit(_failures)


func _deliver(seed_value: int, houses: int, cruise_kmh: float) -> Dictionary:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", seed_value)
	network.set(&"world_house_count", houses)
	var world := Node3D.new()
	world.name = "DeliveryBenchWorld"
	root.add_child(world)
	var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate()
	route.set(&"batch_dressing", false)
	world.add_child(route)
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	van.position = Vector3(0.0, 0.8, 4.0)
	world.add_child(van)
	van.set(&"controls_enabled", false)
	var bot := (load("res://scenes/gameplay/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	bot.name = "Player_1"
	world.add_child(bot)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var assignments: Array = []
	for index: int in range(houses):
		assignments.append([StringName("bench_%d_%d" % [seed_value, index]), "BENCH %d" % (index + 1)])
	route.call(&"assign_packages", assignments)
	var run_manager: Node = root.get_node(^"/root/RunManager")
	run_manager.set(&"is_running", true)
	for tick: int in range(30):
		await physics_frame

	var path: Array[Vector3] = []
	path.assign(route.get(&"_path_points"))
	var stops: Array[int] = []
	for anchor: Dictionary in route.get(&"_house_anchors"):
		var at: Vector3 = (anchor.cursor as Transform3D).origin
		var nearest: int = 0
		for index: int in range(path.size()):
			if path[index].distance_to(at) < path[nearest].distance_to(at):
				nearest = index
		stops.append(nearest)
	var step: float = 1.0 / Engine.physics_ticks_per_second
	var path_index: int = 0
	var next_stop: int = 0
	var drive_ticks: int = 0
	var stop_seconds: float = 0.0
	var rescues: int = 0
	var stuck: float = 0.0
	var last_index: int = -1
	while path_index < path.size() - 1 and drive_ticks * step + stop_seconds < MAX_DELIVERY_SECONDS:
		var here: Vector3 = route.to_local(van.global_position)
		while path_index < path.size() - 1 and Vector2(path[path_index].x - here.x,
				path[path_index].z - here.z).length() < LOOKAHEAD:
			path_index += 1
		stuck = 0.0 if path_index != last_index else stuck + step
		last_index = path_index
		if stuck > 2.5 and path_index >= path.size() - 3:
			path_index = path.size() - 1
			break
		if stuck > 2.5:
			stuck = 0.0
			rescues += 1
			path_index += 2
			var rescue_at: Vector3 = route.to_global(path[path_index])
			var rescue_ahead: Vector3 = route.to_global(path[path_index + 1])
			van.global_transform = Transform3D(Basis.looking_at(rescue_ahead - rescue_at, Vector3.UP),
					rescue_at + Vector3.UP * 1.2)
			van.linear_velocity = (rescue_ahead - rescue_at).normalized() * cruise_kmh / 3.6 * 0.5
			van.angular_velocity = Vector3.ZERO
		var target_kmh: float = cruise_kmh * _bend_factor(path, path_index)
		var braking: bool = next_stop < stops.size() and _distance_along(path, path_index,
				stops[next_stop]) < BRAKE_DISTANCE
		if braking:
			target_kmh = 0.0
			if van.get(&"speed_kmh") < 1.5:
				van.call(&"set_controls", 0.0, 0.0, true)
				van.linear_velocity = Vector3.ZERO
				van.angular_velocity = Vector3.ZERO
				stop_seconds += await _serve_house(world, bot, van, route.get(&"houses")[next_stop],
						assignments[next_stop][0])
				next_stop += 1
		var local: Vector3 = van.global_transform.affine_inverse() * route.to_global(path[path_index])
		var steer: float = clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
		var speed_kmh: float = float(van.get(&"speed_kmh"))
		var throttle: float = 0.0
		if target_kmh <= 0.0:
			throttle = -1.0 if speed_kmh > 1.0 else 0.0
		elif speed_kmh < target_kmh - 2.0:
			throttle = 1.0
		elif speed_kmh > target_kmh + 3.0:
			throttle = -0.7
		else:
			throttle = 0.35
		van.call(&"set_controls", throttle, steer, false)
		await physics_frame
		drive_ticks += 1
		var position: Vector3 = van.global_position
		if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)):
			_failures += 1
			push_error("seed %d houses %d: truck position is not finite" % [seed_value, houses])
			break

	var delivered: int = 0
	for house: Node in route.get(&"houses"):
		if bool(house.get(&"delivered")):
			delivered += 1
	var finished: bool = path_index >= path.size() - 1 and delivered == houses
	if not finished:
		_failures += 1
		push_error("seed %d houses %d: finished=%s delivered=%d/%d" % [seed_value, houses,
				path_index >= path.size() - 1, delivered, houses])
	var drive_seconds: float = drive_ticks * step
	var result := {
		"length": float(route.get(&"route_length")),
		"drive": drive_seconds,
		"stops": stop_seconds,
		"total": drive_seconds + stop_seconds,
		"delivered": delivered,
		"rescues": rescues,
		"finished": finished,
	}
	run_manager.set(&"is_running", false)
	world.free()
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	await process_frame
	return result


func _serve_house(world: Node3D, bot: CharacterBody3D, van: VehicleBody3D, house: Node,
		package_id: StringName) -> float:
	var elapsed: float = 0.0
	var exit_position: Vector3 = van.global_position + van.global_basis.x * 1.4
	bot.global_position = exit_position
	bot.visible = true
	elapsed += await _wait_seconds(EXIT_SECONDS)
	var package := (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate() as RigidBody3D
	package.set(&"package_id", package_id)
	package.set(&"freeze", true)
	world.add_child(package)
	package.global_position = bot.global_position + Vector3.UP * 0.8
	await process_frame
	package.get_node(^"InteractionArea").call(&"interact", bot)
	elapsed += await _wait_seconds(PICKUP_SECONDS)
	var doorbell: Node3D = house.get(&"doorbell") as Node3D
	var door_position: Vector3 = doorbell.global_position
	door_position.y = house.global_position.y + 0.35
	elapsed += await _walk_to(bot, door_position)
	doorbell.call(&"interact", bot)
	elapsed += await _wait_seconds(RING_SECONDS)
	if not bool(house.get(&"delivered")):
		_failures += 1
		push_error("bot rang house %d without completing its assigned delivery" % int(house.get(&"house_index")))
	elapsed += await _walk_to(bot, exit_position)
	elapsed += await _wait_seconds(BOARD_SECONDS)
	bot.visible = false
	return elapsed


func _walk_to(bot: CharacterBody3D, target: Vector3) -> float:
	var elapsed: float = 0.0
	var step: float = 1.0 / Engine.physics_ticks_per_second
	var speed: float = BOT_WALK_SPEED
	while bot.global_position.distance_to(target) > speed * step:
		bot.global_position = bot.global_position.move_toward(target, speed * step)
		var carried: Node3D = bot.get(&"carried_package") as Node3D
		if is_instance_valid(carried):
			carried.global_position = bot.global_position + Vector3.UP * 1.05
		await physics_frame
		elapsed += step
	bot.global_position = target
	return elapsed


func _wait_seconds(seconds: float) -> float:
	var step: float = 1.0 / Engine.physics_ticks_per_second
	var ticks: int = ceili(seconds / step)
	for tick: int in range(ticks):
		await physics_frame
	return ticks * step


## 1 on a straight, down to 0.55 in a sharp bend over the next ~40 m.
func _bend_factor(path: Array[Vector3], index: int) -> float:
	var ahead: int = mini(index + 4, path.size() - 1)
	if ahead - index < 2:
		return 1.0
	var a: Vector3 = path[index + 1] - path[index]
	var b: Vector3 = path[ahead] - path[ahead - 1]
	var angle: float = rad_to_deg(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))
	return clampf(1.0 - absf(angle) / 90.0 * 0.45, 0.55, 1.0)


func _distance_along(path: Array[Vector3], from: int, to: int) -> float:
	if to <= from:
		return 0.0
	var total: float = 0.0
	for index: int in range(from, mini(to, path.size() - 1)):
		total += path[index].distance_to(path[index + 1])
	return total
