extends SceneTree
## Records five real deliveries for the trap balance simulator (S-108).
##   <godot> --headless --fixed-fps 60 --path do-not-drop --script res://tests/sim_record_drive.gd
## Optional: -- --seeds=1081,1082,1083,1084,1085 --houses=1 --cruise=50

const LOOKAHEAD: float = 14.0
const MAX_DRIVE_SECONDS: float = 600.0
const DEFAULT_SEEDS: Array[int] = [1081, 1082, 1084, 1085, 1087]


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
	var houses: int = int(_arg("houses", "1"))
	var cruise_kmh: float = float(_arg("cruise", "50"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/sim_data"))
	for seed_value: int in seeds:
		var recording: Dictionary = await _drive(seed_value, houses, cruise_kmh)
		var path := "res://tests/sim_data/drive_%d.json" % seed_value
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("Could not write %s" % path)
			quit(1)
			return
		file.store_string(JSON.stringify(recording))
		file.close()
		print("RECORDED seed=%d frames=%d seconds=%.1f rescues=%d -> %s" % [
			seed_value, recording.frames.size(), recording.frames.size() * recording.dt,
			recording.rescues, path])
	print("PASS sim_record_drive: %d real drives recorded" % seeds.size())
	quit(0)


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

	var path: Array[Vector3] = []
	path.assign(route.get(&"_path_points"))
	var mount: Node3D = van.get_node(^"CargoBay/LeftSeat1PackageMount")
	var step: float = 1.0 / Engine.physics_ticks_per_second
	var gravity: Vector3 = Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var previous: Vector3 = van.call(&"point_velocity", mount.global_position)
	var frames: Array[Dictionary] = []
	var path_index: int = 0
	var ticks: int = 0
	var rescues: int = 0
	var stuck: float = 0.0
	var last_index: int = -1
	while path_index < path.size() - 1 and ticks * step < MAX_DRIVE_SECONDS:
		var here: Vector3 = route.to_local(van.global_position)
		while path_index < path.size() - 1 and Vector2(path[path_index].x - here.x, path[path_index].z - here.z).length() < LOOKAHEAD:
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
			var at: Vector3 = route.to_global(path[path_index])
			var ahead: Vector3 = route.to_global(path[path_index + 1])
			van.global_transform = Transform3D(Basis.looking_at(ahead - at, Vector3.UP), at + Vector3.UP * 1.2)
			van.linear_velocity = (ahead - at).normalized() * cruise_kmh / 3.6 * 0.5
			van.angular_velocity = Vector3.ZERO
			for settle: int in range(20):
				await physics_frame
			previous = van.call(&"point_velocity", mount.global_position)
		var target_kmh: float = cruise_kmh * _bend_factor(path, path_index)
		var local: Vector3 = van.global_transform.affine_inverse() * route.to_global(path[path_index])
		var steer: float = clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
		var throttle: float = 1.0 if van.speed_kmh < target_kmh - 2.0 else (-0.7 if van.speed_kmh > target_kmh + 3.0 else 0.35)
		van.call(&"set_controls", throttle, steer, false)
		await physics_frame
		ticks += 1
		var now: Vector3 = van.call(&"point_velocity", mount.global_position)
		var velocity_delta: Vector3 = now - previous - gravity * step
		var acceleration: Vector3 = velocity_delta / step
		previous = now
		frames.append({
			"acceleration": [acceleration.x, acceleration.y, acceleration.z],
			"tilt": rad_to_deg(van.global_basis.y.angle_to(Vector3.UP)),
			"impact": velocity_delta.length(),
		})

	var result := {
		"seed": seed_value,
		"houses": houses,
		"cruise_kmh": cruise_kmh,
		"dt": step,
		"route_length": float(route.get(&"route_length")),
		"rescues": rescues,
		"frames": frames,
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
