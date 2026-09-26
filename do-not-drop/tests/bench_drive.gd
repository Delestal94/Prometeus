extends SceneTree
## Performance probe. Run WITHOUT --headless (it measures real rendering):
##   <godot> --path do-not-drop --script res://tests/bench_drive.gd
## Builds the real level, seats the driver, and lets an autopilot drive the
## generated route at full throttle while it records every frame: frame time,
## script/physics time, draw calls and objects. Prints a summary plus every
## hitch (frame > HITCH_MS) with what was going on, so a stutter can be traced
## to rendering, physics or a script instead of guessed at.
## Optional user args: -- --seconds=60 --seed=1234 --hitch=33
## --endless drives Endless instead (level_endless.tscn), following the
## streamed road's own centre line (RouteStreamer.point_at()).
## --mood=lluvia_noche (world_mood.gd) forces the weather and time of day.
## With --headless and -- --cpu-only it measures scripts + physics alone.
## --experiment=noshadow|shadow2|noplants|nodress switches one cost off to
## measure what it's worth.

var HITCH_MS: float = 33.0
var _endless: bool = false
var _endless_best: float = -INF
const LOOKAHEAD: float = 14.0

var _level: Node3D
var _route: Node3D
var _van: VehicleBody3D
var _frames: Array[Dictionary] = []
var _last_usec: int = 0
var _path: Array[Vector3] = []
var _path_index: int = 0
var _done: bool = false
var _stuck_seconds: float = 0.0
var _rescues: int = 0
var _last_progress_index: int = -1
## Wall-clock physics cost: from the first physics_frame of an iteration to
## the process_frame that follows it (Performance's physics monitor is an
## average that lags behind, useless for spotting a single slow tick).
var _physics_start_usec: int = -1
## Motion smoothness: how evenly the rendered camera advances frame to frame
## at cruising speed. Without interpolation it only moves on physics ticks,
## so at high frame rates most frames repeat a pose and the next one jumps.
var _last_camera_origin: Vector3 = Vector3.INF
var _smooth_samples: Array[float] = []
## How far the seated driver's body drifts from its seat as drawn (should
## stay ~0: both must be interpolated the same way).
var _seat_drift_peak: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	if DisplayServer.get_name() == "headless" and not "--cpu-only" in OS.get_cmdline_user_args():
		push_error("bench_drive needs a rendering display; omit --headless.")
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", int(_arg("seed", "4242")))
	var seconds: float = float(_arg("seconds", "60"))
	HITCH_MS = float(_arg("hitch", "33"))
	if _arg("experiment", "").contains("fti"):
		physics_interpolation = true
	var build_start: int = Time.get_ticks_usec()
	_endless = "--endless" in OS.get_cmdline_user_args()
	_level = load("res://scenes/gameplay/level_endless.tscn" if _endless else "res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(_level)
	current_scene = _level
	var build_ms: float = (Time.get_ticks_usec() - build_start) / 1000.0
	# Endless has no Route: the experiments below that need one skip it.
	_route = _level.get_node_or_null(^"World/Route")
	_van = _level.vehicle
	for _i: int in range(3):
		await process_frame
	var experiment: String = _arg("experiment", "")
	if experiment.contains("shadow2"):
		for light: Node in _level.find_children("*", "DirectionalLight3D", true, false):
			(light as DirectionalLight3D).directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if experiment.contains("noshadow"):
		for light: Node in _level.find_children("*", "DirectionalLight3D", true, false):
			(light as DirectionalLight3D).shadow_enabled = false
	if _route != null and (experiment.contains("noplants") or experiment.contains("nodress")):
		for group: Node in _route.find_children("*Dressing", "Node3D", true, false):
			if experiment.contains("nodress") or group.name == "ForestDressing":
				group.queue_free()
	if _route != null and experiment.contains("nohouses"):
		for house: Node in _route.get(&"houses"):
			(house as Node3D).visible = false
	if _route != null and experiment.contains("nosegvis"):
		for segment: Node in _route.get(&"_segments"):
			for mesh: Node in segment.find_children("*", "MeshInstance3D", true, false):
				(mesh as Node3D).visible = false
	if experiment.contains("notruck"):
		(_van.get_node(^"BodyVisuals") as Node3D).visible = false
	_level.call(&"start_debug_delivery")
	if experiment.contains("camoff"):
		for camera: Node in _level.find_children("*", "Camera3D", true, false):
			camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_van.get_node(^"VehicleInputComponent").set_physics_process(false)
	# The autopilot crashes into chicanes; a box lost there would end the run
	# (and the level) halfway. This measures frames, not driving, so keep going.
	var ruined: Callable = Callable(root.get_node(^"/root/RunManager"), &"_on_package_ruined")
	var bus: Node = root.get_node(^"/root/EventBus")
	if bus.is_connected(&"package_ruined", ruined):
		bus.disconnect(&"package_ruined", ruined)
	if _route != null:
		_path.assign(_route.get(&"_path_points"))
	print("BENCH mode=%s mood=%s build_ms=%.0f nodes=%d path_points=%d route_length=%.0f" % ["endless" if _endless else "delivery", str(WorldMood.active.get("label", "")), build_ms, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), _path.size(), float(_route.get(&"route_length")) if _route != null else 0.0])
	physics_frame.connect(_drive)
	var first_frame_start: int = Time.get_ticks_usec()
	var first_ms: float = 0.0
	await process_frame
	first_ms = (Time.get_ticks_usec() - first_frame_start) / 1000.0
	_last_usec = Time.get_ticks_usec()
	var elapsed: float = 0.0
	while elapsed < seconds and not _done:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var physics_wall: float = (now - _physics_start_usec) / 1000.0 if _physics_start_usec >= 0 else 0.0
		_physics_start_usec = -1
		var ms: float = (now - _last_usec) / 1000.0
		_last_usec = now
		elapsed += ms / 1000.0
		var camera: Camera3D = root.get_viewport().get_camera_3d()
		if camera != null:
			var origin: Vector3 = camera.get_global_transform_interpolated().origin
			var speed: float = _van.linear_velocity.length()
			if _last_camera_origin != Vector3.INF and speed > 15.0 and ms > 0.0:
				_smooth_samples.append(origin.distance_to(_last_camera_origin) / (ms / 1000.0) / speed)
			_last_camera_origin = origin
		var player: Node = _level.get(&"local_player")
		if player != null and _van.linear_velocity.length() > 15.0:
			var body_visual: Node3D = player.get(&"_body_visual")
			var seat: Node3D = player.get_node_or_null(player.get(&"seat_node_path")) as Node3D
			if body_visual != null and seat != null:
				var expected: Vector3 = seat.get_global_transform_interpolated().translated_local(Vector3(0.0, -0.55, 0.0)).origin
				_seat_drift_peak = maxf(_seat_drift_peak, body_visual.get_global_transform_interpolated().origin.distance_to(expected))
		_frames.append({
			"ms": ms,
			"t": elapsed,
			"process": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"physics": physics_wall,
			"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		"memory_video": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"kmh": _van.linear_velocity.length() * 3.6,
			"progress": float(_path_index) / maxf(1.0, float(_path.size())),
			"rescues": _rescues,
		})
	_report(first_ms)
	quit()


## Pure-pursuit autopilot along the route's own path points.
func _drive() -> void:
	if _physics_start_usec < 0:
		_physics_start_usec = Time.get_ticks_usec()
	if _endless:
		_drive_endless()
		return
	if _path.is_empty():
		return
	var here: Vector3 = _route.to_local(_van.global_position)
	while _path_index < _path.size() - 1 and Vector2(_path[_path_index].x - here.x, _path[_path_index].z - here.z).length() < LOOKAHEAD:
		_path_index += 1
	if _path_index >= _path.size() - 1:
		_done = true
	# The autopilot only follows the centreline and can't weave through a
	# chicane or roadworks: when it's pinned against one, put it back on the
	# road a little further on, so one run still covers the whole route.
	_stuck_seconds += 1.0 / Engine.physics_ticks_per_second
	if _path_index != _last_progress_index:
		_last_progress_index = _path_index
		_stuck_seconds = 0.0
	if _stuck_seconds > 2.0 and _path_index < _path.size() - 3:
		_stuck_seconds = 0.0
		_rescues += 1
		_path_index += 2
		var at: Vector3 = _route.to_global(_path[_path_index])
		var ahead: Vector3 = _route.to_global(_path[_path_index + 1])
		_van.global_transform = Transform3D(Basis.looking_at(ahead - at, Vector3.UP), at + Vector3.UP * 1.2)
		_van.linear_velocity = (ahead - at).normalized() * 12.0
		_van.angular_velocity = Vector3.ZERO
		_van.reset_physics_interpolation()
	var target: Vector3 = _route.to_global(_path[_path_index])
	var local: Vector3 = _van.global_transform.affine_inverse() * target
	# Front is -Z; positive steer input turns right (+X).
	var steer: float = clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
	_van.call(&"set_controls", 1.0, steer, false)


## Endless: follow the streamed road's centre line, and past a chicane it
## can't weave, hop the truck 20 m on.
func _drive_endless() -> void:
	var streamer: RouteStreamer = _level.get_node(^"World/RouteStreamer")
	var along: float = streamer.distance_along(_van.global_position)
	_stuck_seconds += 1.0 / Engine.physics_ticks_per_second
	if along > _endless_best + 1.0:
		_endless_best = along
		_stuck_seconds = 0.0
	if _stuck_seconds > 2.0:
		_stuck_seconds = 0.0
		_rescues += 1
		var at: Vector3 = streamer.point_at(along + 20.0)
		var ahead: Vector3 = streamer.point_at(along + 25.0)
		_van.global_transform = Transform3D(Basis.looking_at(ahead - at, Vector3.UP), at + Vector3.UP * 1.2)
		_van.linear_velocity = (ahead - at).normalized() * 12.0
		_van.angular_velocity = Vector3.ZERO
		_van.reset_physics_interpolation()
	var local: Vector3 = _van.global_transform.affine_inverse() * streamer.point_at(along + LOOKAHEAD)
	var steer: float = clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
	_van.call(&"set_controls", 1.0, steer, false)


func _report(first_ms: float) -> void:
	if _frames.is_empty():
		print("BENCH no frames")
		return
	var times: Array[float] = []
	var total: float = 0.0
	var draws: float = 0.0
	var objects: float = 0.0
	var prims: float = 0.0
	var process_ms: float = 0.0
	var physics_ms: float = 0.0
	var physics_peak: float = 0.0
	var memory_static_peak: float = 0.0
	var memory_video_peak: float = 0.0
	var physics_ticks: int = 0
	for f: Dictionary in _frames:
		times.append(f.ms)
		total += f.ms
		draws += f.draws
		objects += f.objects
		prims += f.prims
		memory_static_peak = maxf(memory_static_peak, f.memory_static)
		memory_video_peak = maxf(memory_video_peak, f.memory_video)
		process_ms += f.process
		if f.physics > 0.0:
			physics_ms += f.physics
			physics_ticks += 1
			physics_peak = maxf(physics_peak, f.physics)
	var n: float = float(_frames.size())
	times.sort()
	var p: Callable = func(q: float) -> float: return times[clampi(int(q * n), 0, times.size() - 1)]
	print("BENCH first_frame_ms=%.0f frames=%d avg_ms=%.2f fps=%.0f p50=%.2f p95=%.2f p99=%.2f max=%.1f" % [first_ms, _frames.size(), total / n, 1000.0 * n / total, p.call(0.5), p.call(0.95), p.call(0.99), times[-1]])
	print("BENCH avg draws=%.0f objects=%.0f prims=%.0f progress=%.2f" % [draws / n, objects / n, prims / n, _frames[-1].progress])
	print("BENCH physics per tick: avg=%.2fms peak=%.2fms (%d ticks)" % [physics_ms / maxf(1.0, physics_ticks), physics_peak, physics_ticks])
	print("BENCH memory_static_peak_mib=%.1f memory_video_peak_mib=%.1f" % [
		memory_static_peak / 1048576.0,
		memory_video_peak / 1048576.0,
	])
	if _smooth_samples.size() > 10:
		var mean: float = 0.0
		for v: float in _smooth_samples:
			mean += v
		mean /= _smooth_samples.size()
		var variance: float = 0.0
		var frozen: int = 0
		for v: float in _smooth_samples:
			variance += (v - mean) * (v - mean)
			if v < 0.2:
				frozen += 1
		print("BENCH motion judder=%.2f (0 = perfectly even; std/mean of camera speed vs truck speed) frozen_frames=%.0f%%" % [sqrt(variance / _smooth_samples.size()) / maxf(mean, 0.001), 100.0 * frozen / _smooth_samples.size()])
	print("BENCH seated body drift from its seat, peak=%.3fm" % _seat_drift_peak)
	var hitches: int = 0
	for f: Dictionary in _frames:
		if f.ms > HITCH_MS:
			hitches += 1
			if hitches <= 40:
				print("HITCH rescue=%d t=%.2fs ms=%.1f process_monitor=%.1f physics=%.1f draws=%d objects=%d kmh=%.0f progress=%.2f" % [f.rescues, f.t, f.ms, f.process, f.physics, f.draws, f.objects, f.kmh, f.progress])
	print("BENCH hitches(>%.0fms)=%d rescues=%d" % [HITCH_MS, hitches, _rescues])
