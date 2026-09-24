extends SceneTree
## How long a delivery takes, measured by driving it (tareas de Nacho N-102).
##   <godot> --headless --fixed-fps 60 --path do-not-drop --script res://tests/bench_route_duration.gd
## --fixed-fps makes each frame one physics tick, so it runs faster than real
## time. Optional user args: -- --seeds=1-20 --houses=1,2,3,4 --cruise=50 --stop=25
##
## For every seed and house count it builds the real route (route.tscn) and a
## real truck, and an autopilot drives it end to end: pure pursuit along the
## route's own path points, holding a cruising speed (km/h) that it eases off
## in bends, and braking to a stop at each house. The stop itself -- get out,
## walk, ring, come back -- isn't simulated: each house adds --stop seconds.
## The autopilot can't weave through a chicane or roadworks; when it's pinned
## against one it's put back on the road a little further on, and that costs
## RESCUE_PENALTY seconds, about what a person loses threading it slowly.
##
## Prints one line per run and a table per house count: total minutes
## (average and worst) and the average driving speed, the number the route's
## length budget (route.gd ROUTE_CRUISE_SPEED) is based on.

const LOOKAHEAD: float = 14.0
## Distance along the path, before a house's stop, at which braking starts.
const BRAKE_DISTANCE: float = 30.0
const RESCUE_PENALTY: float = 8.0
## Gives up on a run that takes longer than this (a truck stuck for good).
const MAX_DRIVE_SECONDS: float = 900.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	var seed_range: PackedStringArray = _arg("seeds", "1-20").split("-")
	var first_seed: int = int(seed_range[0])
	var last_seed: int = int(seed_range[-1])
	var house_counts: Array[int] = []
	for value: String in _arg("houses", "1,2,3,4").split(","):
		house_counts.append(int(value))
	var cruise_kmh: float = float(_arg("cruise", "50"))
	var stop_seconds: float = float(_arg("stop", "25"))
	print("BENCH route duration: seeds %d-%d, houses %s, cruise %.0f km/h, %.0f s per stop" % [first_seed, last_seed, house_counts, cruise_kmh, stop_seconds])
	var summary: Dictionary = {}
	for houses: int in house_counts:
		summary[houses] = []
		for seed_value: int in range(first_seed, last_seed + 1):
			var result: Dictionary = await _drive_route(seed_value, houses, cruise_kmh, stop_seconds)
			summary[houses].append(result)
			print("RUN seed=%d houses=%d length=%.0fm drive=%.0fs rescues=%d total=%.2fmin avg_speed=%.1fkm/h%s" % [
				seed_value, houses, result.length, result.drive, result.rescues, result.total / 60.0,
				result.length / maxf(result.drive, 0.01) * 3.6, "" if result.finished else " UNFINISHED"])
	print("")
	print("| Casas | Largo medio (m) | Minutos promedio | Minutos máximo | Minutos mínimo | Velocidad media (km/h) |")
	print("|---|---|---|---|---|---|")
	for houses: int in house_counts:
		var runs: Array = summary[houses]
		var length_sum: float = 0.0
		var total_sum: float = 0.0
		var drive_sum: float = 0.0
		var worst: float = 0.0
		var best: float = INF
		for result: Dictionary in runs:
			length_sum += result.length
			total_sum += result.total
			drive_sum += result.drive
			worst = maxf(worst, result.total)
			best = minf(best, result.total)
		var count: float = float(runs.size())
		print("| %d | %.0f | %.2f | %.2f | %.2f | %.1f |" % [houses, length_sum / count, total_sum / count / 60.0, worst / 60.0, best / 60.0, length_sum / maxf(drive_sum, 0.01) * 3.6])
	quit(_failures)


func _drive_route(seed_value: int, houses: int, cruise_kmh: float, stop_seconds: float) -> Dictionary:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", seed_value)
	network.set(&"world_house_count", houses)
	var world := Node3D.new()
	root.add_child(world)
	var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate()
	route.set(&"batch_dressing", false)
	world.add_child(route)
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	van.position = Vector3(0.0, 0.8, 4.0)
	world.add_child(van)
	van.controls_enabled = false
	var run_manager: Node = root.get_node(^"/root/RunManager")
	run_manager.set(&"is_running", true)
	for tick: int in range(30):
		await physics_frame

	var path: Array[Vector3] = []
	path.assign(route.get(&"_path_points"))
	# Path index where each house's stop is: the path point nearest to where
	# the road was when the house was built.
	var stops: Array[int] = []
	for anchor: Dictionary in route.get(&"_house_anchors"):
		var at: Vector3 = (anchor.cursor as Transform3D).origin
		var nearest: int = 0
		for index: int in range(path.size()):
			if path[index].distance_to(at) < path[nearest].distance_to(at):
				nearest = index
		stops.append(nearest)
	var path_index: int = 0
	var next_stop: int = 0
	var ticks: int = 0
	var rescues: int = 0
	var stuck: float = 0.0
	var last_index: int = -1
	var step: float = 1.0 / Engine.physics_ticks_per_second
	while path_index < path.size() - 1 and ticks * step < MAX_DRIVE_SECONDS:
		var here: Vector3 = route.to_local(van.global_position)
		while path_index < path.size() - 1 and Vector2(path[path_index].x - here.x, path[path_index].z - here.z).length() < LOOKAHEAD:
			path_index += 1
		stuck = 0.0 if path_index != last_index else stuck + step
		last_index = path_index
		if stuck > 2.5 and path_index >= path.size() - 3:
			# Pinned right at the goal: close enough, the delivery is over.
			path_index = path.size() - 1
			break
		if stuck > 2.5:
			stuck = 0.0
			rescues += 1
			path_index += 2
			var at: Vector3 = route.to_global(path[path_index])
			var ahead: Vector3 = route.to_global(path[path_index + 1])
			van.global_transform = Transform3D(Basis.looking_at(ahead - at, Vector3.UP), at + Vector3.UP * 1.2)
			van.linear_velocity = (ahead - at).normalized() * cruise_kmh / 3.6 * 0.5
			van.angular_velocity = Vector3.ZERO
		var target_kmh: float = cruise_kmh * _bend_factor(path, path_index)
		var braking_for_stop: bool = next_stop < stops.size() and _distance_along(path, path_index, stops[next_stop]) < BRAKE_DISTANCE
		if braking_for_stop:
			target_kmh = 0.0
			if van.speed_kmh < 1.5:
				next_stop += 1  # Stopped at the door: the stop's time is added below.
		var local: Vector3 = van.global_transform.affine_inverse() * route.to_global(path[path_index])
		var steer: float = clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
		var throttle: float = 0.0
		if target_kmh <= 0.0:
			throttle = -1.0 if van.speed_kmh > 1.0 else 0.0
		elif van.speed_kmh < target_kmh - 2.0:
			throttle = 1.0
		elif van.speed_kmh > target_kmh + 3.0:
			throttle = -0.7
		else:
			throttle = 0.35
		van.set_controls(throttle, steer, false)
		await physics_frame
		ticks += 1
		var position: Vector3 = van.global_position
		if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)):
			_failures += 1
			push_error("seed %d houses %d: the truck's position blew up" % [seed_value, houses])
			break

	var drive: float = ticks * step
	var result := {
		"length": float(route.get(&"route_length")),
		"drive": drive,
		"rescues": rescues,
		"total": drive + rescues * RESCUE_PENALTY + stops.size() * stop_seconds,
		"finished": path_index >= path.size() - 1,
	}
	run_manager.set(&"is_running", false)
	world.free()
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	await process_frame
	return result


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
