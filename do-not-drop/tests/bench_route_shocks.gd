extends SceneTree
## Which stretch of road hits the cargo how hard (tareas de Nacho N-105).
##   <godot> --headless --fixed-fps 60 --path do-not-drop --script res://tests/bench_route_shocks.gd
## Optional user args: -- --seeds=1-10 --houses=2 --cruise=50
##
## Drives real routes like bench_route_duration.gd (same autopilot, no stops)
## at a cruising speed and records, at the cargo bay's first package mount,
## what a box riding there feels: the jolt per physics tick (change of
## velocity at that point, gravity taken out -- the same measure package.gd
## feeds a Fragile box) and how far the truck leans. Per segment type it
## prints the typical and the worst jolt of a pass, how often a pass crosses
## Fragile's light (3.0 m/s) and heavy (7.0 m/s) thresholds, and the lean.
## Run it at cruise and at a careful speed (--cruise=30): every obstacle has
## to be passable without damage by someone taking it slowly.

const LOOKAHEAD: float = 14.0
const LIGHT: float = 3.0
const HEAVY: float = 7.0
const MAX_DRIVE_SECONDS: float = 600.0


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	var seed_range: PackedStringArray = _arg("seeds", "1-10").split("-")
	var houses: int = int(_arg("houses", "2"))
	var cruise_kmh: float = float(_arg("cruise", "50"))
	# type -> Array of passes: {"peak": float, "tilt": float}
	var passes: Dictionary = {}
	for seed_value: int in range(int(seed_range[0]), int(seed_range[-1]) + 1):
		var found: Dictionary = await _drive(seed_value, houses, cruise_kmh)
		for type: String in found:
			if not passes.has(type):
				passes[type] = []
			passes[type].append_array(found[type])
	print("")
	print("Crucero %.0f km/h, semillas %s, %d casas" % [cruise_kmh, "-".join(seed_range), houses])
	print("| Tramo | Pasadas | Golpe típico (m/s) | Golpe máximo (m/s) | Pasadas >= 3,0 | Pasadas >= 7,0 | Inclinación máx. (°) |")
	print("|---|---|---|---|---|---|---|")
	var types: Array = passes.keys()
	types.sort()
	for type: String in types:
		var list: Array = passes[type]
		var peaks: Array[float] = []
		var tilt: float = 0.0
		var light: int = 0
		var heavy: int = 0
		for entry: Dictionary in list:
			peaks.append(entry.peak)
			tilt = maxf(tilt, entry.tilt)
			light += int(entry.peak >= LIGHT)
			heavy += int(entry.peak >= HEAVY)
		peaks.sort()
		print("| %s | %d | %.1f | %.1f | %d%% | %d%% | %.0f |" % [type, list.size(), peaks[peaks.size() / 2], peaks[-1],
			roundi(100.0 * light / list.size()), roundi(100.0 * heavy / list.size()), tilt])
	quit(0)


## Drives one route end to end; returns {type: [{"peak", "tilt"}, ...]},
## one entry per segment the truck went through.
func _drive(seed_value: int, houses: int, cruise_kmh: float) -> Dictionary:
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
	van.set(&"controls_enabled", false)
	var run_manager: Node = root.get_node(^"/root/RunManager")
	run_manager.set(&"is_running", true)
	for tick: int in range(30):
		await physics_frame

	# Which segment each path point belongs to (route.gd lays them out in
	# order, get_dressing_slots(10.0) per segment).
	var path: Array[Vector3] = []
	path.assign(route.get(&"_path_points"))
	var owner_of: Array[int] = []
	var segments: Array = route.get(&"_segments")
	for index: int in range(segments.size()):
		for slot: Transform3D in (segments[index] as RouteSegment).get_dressing_slots(10.0):
			owner_of.append(index)
	var mount: Node3D = van.get_node(^"CargoBay/LeftSeat1PackageMount")
	var step: float = 1.0 / Engine.physics_ticks_per_second
	var gravity: Vector3 = Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var previous: Vector3 = van.call(&"point_velocity", mount.global_position)
	var by_segment: Dictionary = {}  # segment index -> {"peak", "tilt"}
	var path_index: int = 0
	var ticks: int = 0
	var stuck: float = 0.0
	var last_index: int = -1
	while path_index < path.size() - 1 and ticks * step < MAX_DRIVE_SECONDS:
		var here: Vector3 = route.to_local(van.global_position)
		while path_index < path.size() - 1 and Vector2(path[path_index].x - here.x, path[path_index].z - here.z).length() < LOOKAHEAD:
			path_index += 1
		stuck = 0.0 if path_index != last_index else stuck + step
		last_index = path_index
		if stuck > 2.5:
			# Pinned against a chicane: skip ahead (and don't count the jolt of
			# being put back on the road).
			if path_index >= path.size() - 3:
				break
			stuck = 0.0
			path_index += 2
			var at: Vector3 = route.to_global(path[path_index])
			var ahead: Vector3 = route.to_global(path[path_index + 1])
			van.global_transform = Transform3D(Basis.looking_at(ahead - at, Vector3.UP), at + Vector3.UP * 1.2)
			van.linear_velocity = (ahead - at).normalized() * cruise_kmh / 3.6 * 0.5
			van.angular_velocity = Vector3.ZERO
			for settle: int in range(20):
				await physics_frame
			previous = van.call(&"point_velocity", mount.global_position)
		var local: Vector3 = van.global_transform.affine_inverse() * route.to_global(path[path_index])
		var steer: float = clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
		var speed: float = van.get(&"speed_kmh")
		var throttle: float = 1.0 if speed < cruise_kmh - 2.0 else (-0.7 if speed > cruise_kmh + 3.0 else 0.35)
		van.call(&"set_controls", throttle, steer, false)
		await physics_frame
		ticks += 1
		var now: Vector3 = van.call(&"point_velocity", mount.global_position)
		var jolt: float = (now - previous - gravity * step).length()
		previous = now
		# The segment under the truck: the path point nearest to it, not the
		# lookahead one.
		var nearest: int = maxi(0, path_index - 1)
		var segment: int = owner_of[mini(nearest, owner_of.size() - 1)]
		var entry: Dictionary = by_segment.get(segment, {"peak": 0.0, "tilt": 0.0})
		entry.peak = maxf(entry.peak, jolt)
		entry.tilt = maxf(entry.tilt, rad_to_deg(van.global_basis.y.angle_to(Vector3.UP)))
		by_segment[segment] = entry
	var result: Dictionary = {}
	for segment: int in by_segment:
		var type: String = (segments[segment] as RouteSegment).get_script().get_global_name()
		if not result.has(type):
			result[type] = []
		result[type].append(by_segment[segment])
	run_manager.set(&"is_running", false)
	world.free()
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	await process_frame
	return result
