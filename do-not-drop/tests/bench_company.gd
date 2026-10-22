extends SceneTree
## Performance probe of the Modo Empresa world (expansion D-2011). Run WITHOUT --headless (it
## measures real rendering), like bench_drive.gd:
##   <godot> --path do-not-drop --script res://tests/bench_company.gd -- --seconds=30
## Opens the company world (scenes/gameplay/company_root.tscn, what --mode=company opens) and moves
## a camera along a FIXED path for `--seconds` (default 30): a loop around the inside of the shed
## and, at the end, a look out of the door at the zone slabs. A second stage, "drive 30 s toward
## Barrio Centro", has no vehicle or road to run on yet: it prints `drive: not_available` and is
## skipped without failing (D-2011.1 fills in _stage_drive()).
## Prints one summary block, a line per key with the stable prefix `BENCH_COMPANY key=value`
## (objects, nodes, draw_calls, physics_bodies, frame_ms_p50, frame_ms_p95, memory_static_kb...),
## and a final `BENCH_COMPANY_OK`. It quits by itself; a hard wall-clock timeout ends it with
## `BENCH_COMPANY_TIMEOUT` (exit code 3) if the world never comes up or a frame never returns.
## Optional user args: -- --seconds=30 (per stage) --hard=<seconds> (the hard timeout).
## With --headless and -- --cpu-only it measures scripts + physics alone (draw_calls reads 0).
## The company saves into a temp folder (user://bench_company), never the game's slot.
## The camera path and the summary format are static functions (camera_pose(), summary_lines()),
## checked without rendering by tests/test_company_bench.gd.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const SAVE_DIR: String = "user://bench_company"
const PREFIX: String = "BENCH_COMPANY"
## The summary block, in this order: one `BENCH_COMPANY key=value` line each.
const SUMMARY_KEYS: Array[String] = [
	"mode", "seconds", "frames", "build_ms", "objects", "object_count", "nodes", "draw_calls",
	"physics_bodies", "frame_ms_p50", "frame_ms_p95", "memory_static_kb", "drive",
]
const DRIVE_NOT_AVAILABLE: String = "drive: not_available (no vehicle in the company world yet, D-2011.1)"
## Eye height of the camera over the shed floor, meters.
const EYE_HEIGHT: float = 1.7
## The loop the camera walks, as half extents (x, z) around the shed's centre: down the middle aisle
## of the furnished shed (12 x 8 m, D-0911), clear of the shelves, tables and pallets. It starts and
## ends at the player's spawn (0, 2.6), on the dock floor.
const WALK_HALF: Vector2 = Vector2(2.6, 1.3)
## The share of the stage spent walking the loop; the rest is the look out of the door.
const WALK_FRACTION: float = 0.8
## How far ahead along the loop the camera looks, meters.
const LOOK_AHEAD: float = 4.0
## Where the door look sweeps: from the left to the right of this line over the zone slabs
## (campo and puerto lie beyond the door, +Z).
const DOOR_LOOK_X: float = 400.0
const DOOR_LOOK_Z: float = 500.0
const DEFAULT_SECONDS: float = 30.0
const WARMUP_FRAMES: int = 3

var _camera: Camera3D
var _hard_seconds: float = 0.0
var _finished: bool = false


func _initialize() -> void:
	_run.call_deferred()


# --- The camera path (static: tests/test_company_bench.gd calls it without rendering) ---


## The corners of the walked loop at eye height, in order, closed (the last is the first).
static func walk_waypoints() -> PackedVector3Array:
	var spawn := Vector3(CompanyRoot.SPAWN.x, EYE_HEIGHT, CompanyRoot.SPAWN.z)
	return PackedVector3Array([
		spawn,
		Vector3(WALK_HALF.x, EYE_HEIGHT, WALK_HALF.y),
		Vector3(WALK_HALF.x, EYE_HEIGHT, -WALK_HALF.y),
		Vector3(-WALK_HALF.x, EYE_HEIGHT, -WALK_HALF.y),
		Vector3(-WALK_HALF.x, EYE_HEIGHT, WALK_HALF.y),
		spawn,
	])


static func walk_length() -> float:
	var points: PackedVector3Array = walk_waypoints()
	var total: float = 0.0
	for index: int in range(points.size() - 1):
		total += points[index].distance_to(points[index + 1])
	return total


## The point `distance` meters along the loop (it wraps around).
static func path_point(distance: float) -> Vector3:
	var points: PackedVector3Array = walk_waypoints()
	var left: float = fposmod(distance, walk_length())
	for index: int in range(points.size() - 1):
		var leg: float = points[index].distance_to(points[index + 1])
		if left <= leg:
			return points[index].lerp(points[index + 1], left / leg if leg > 0.0 else 0.0)
		left -= leg
	return points[points.size() - 1]


## The camera's pose `t` seconds into a stage of `seconds`: the same for the same (t, seconds), with
## no state. The first WALK_FRACTION walks the loop looking where it is going; the rest stands by
## the door and sweeps the view across the zone slabs outside.
static func camera_pose(t: float, seconds: float) -> Transform3D:
	var progress: float = clampf(t / maxf(seconds, 0.001), 0.0, 1.0)
	var origin: Vector3
	var target: Vector3
	if progress < WALK_FRACTION:
		var along: float = progress / WALK_FRACTION * walk_length()
		origin = path_point(along)
		target = path_point(along + LOOK_AHEAD)
	else:
		var sweep: float = (progress - WALK_FRACTION) / (1.0 - WALK_FRACTION)
		origin = path_point(walk_length())
		target = Vector3(lerpf(-DOOR_LOOK_X, DOOR_LOOK_X, sweep), 0.0, DOOR_LOOK_Z)
	return Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin)


# --- The summary (static too) ---


## Sorted values' q-th percentile (q in 0..1), as bench_drive.gd picks it.
static func percentile(sorted_values: Array[float], q: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	return sorted_values[clampi(int(q * sorted_values.size()), 0, sorted_values.size() - 1)]


## One `BENCH_COMPANY key=value` line per SUMMARY_KEYS entry, in order ("n/a" for a missing one).
static func summary_lines(stats: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for key: String in SUMMARY_KEYS:
		var value: Variant = stats.get(key, "n/a")
		var text: String = "%.2f" % value if value is float else str(value)
		lines.append("%s %s=%s" % [PREFIX, key, text])
	return lines


# --- The run ---


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	var cpu_only: bool = "--cpu-only" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" and not cpu_only:
		push_error("bench_company needs a rendering display; omit --headless (or pass -- --cpu-only).")
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var seconds: float = maxf(float(_arg("seconds", str(DEFAULT_SECONDS))), 0.5)
	_hard_seconds = float(_arg("hard", str(seconds * 2.0 + 45.0)))
	create_timer(_hard_seconds, true, false, true).timeout.connect(_on_hard_timeout)

	var build_start: int = Time.get_ticks_usec()
	_clean_save_dir()
	var level: Node3D = await _open_world()
	var build_ms: float = (Time.get_ticks_usec() - build_start) / 1000.0
	for _i: int in range(WARMUP_FRAMES):
		await process_frame

	var walk: Array[Dictionary] = await _stage_walk(seconds)
	var drive: Dictionary = await _stage_drive(seconds)
	if _finished:
		return

	var stats: Dictionary = _collect(walk, level, seconds, build_ms)
	stats["drive"] = drive.status
	_close_world(level)
	if walk.is_empty():
		print("%s_FAIL no frames" % PREFIX)
		quit(1)
		return
	for line: String in summary_lines(stats):
		print(line)
	print("%s_OK" % PREFIX)
	_finished = true
	quit()


## The company world with its save folder pointed at a temp dir, before it enters the tree (the
## host loads its slot from there on entry and marks the day interrupted there on leaving).
func _open_world() -> Node3D:
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = SAVE_DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	_camera = Camera3D.new()
	_camera.name = "BenchCamera"
	_camera.far = 4000.0
	var player_camera: Camera3D = level.player.get_node_or_null(^"Head/Camera3D") as Camera3D
	if player_camera != null:
		# Same layers as the player's view (its own body is hidden from it).
		_camera.cull_mask = player_camera.cull_mask
	level.add_child(_camera)
	_camera.global_transform = camera_pose(0.0, 1.0)
	_camera.make_current()
	return level


## Leaving the world: its exit saves the day into the temp folder, which is then removed, and the
## company and the mouse go back to how a test leaves them.
func _close_world(level: Node3D) -> void:
	root.remove_child(level)
	level.free()
	_clean_save_dir()
	var state: Node = root.get_node_or_null(^"/root/CompanyState")
	if state != null:
		state.call(&"reset")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _clean_save_dir() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_DIR))


## Walks the shed for `seconds` of wall time; one sample per frame.
func _stage_walk(seconds: float) -> Array[Dictionary]:
	return await _run_stage(seconds, camera_pose)


## "Drives 30 s toward Barrio Centro": there is no vehicle or road in the company world yet, so it
## is skipped (D-2011.1). To fill in: build the pose Callable (t, seconds) -> Transform3D that
## follows the truck, and `return {"status": "ok", "frames": await _run_stage(seconds, pose)}`.
func _stage_drive(_seconds: float) -> Dictionary:
	print(DRIVE_NOT_AVAILABLE)
	return {"status": "not_available", "frames": [] as Array[Dictionary]}


## The common stage loop: every frame the camera takes `pose.call(t, seconds)` and the frame time,
## draw calls and rendered objects are recorded. `t` is wall time since the stage began.
func _run_stage(seconds: float, pose: Callable) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var start: int = Time.get_ticks_usec()
	var last: int = start
	var elapsed: float = 0.0
	while elapsed < seconds and not _finished:
		var next_pose: Transform3D = pose.call(elapsed, seconds)
		_camera.global_transform = next_pose
		await process_frame
		var now: int = Time.get_ticks_usec()
		frames.append({
			"ms": (now - last) / 1000.0,
			"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		})
		last = now
		elapsed = (now - start) / 1000000.0
	return frames


## The numbers of the summary: averages over the walk's frames for what the renderer reports, the
## state of the tree at the end for the rest.
func _collect(frames: Array[Dictionary], level: Node, seconds: float, build_ms: float) -> Dictionary:
	var times: Array[float] = []
	var draws: float = 0.0
	var objects: float = 0.0
	for frame: Dictionary in frames:
		times.append(frame.ms)
		draws += frame.draws
		objects += frame.objects
	times.sort()
	var count: float = maxf(1.0, float(frames.size()))
	return {
		"mode": "cpu_only" if DisplayServer.get_name() == "headless" else "rendered",
		"seconds": seconds,
		"frames": frames.size(),
		"build_ms": build_ms,
		"objects": roundi(objects / count),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"draw_calls": roundi(draws / count),
		"physics_bodies": level.find_children("*", "PhysicsBody3D", true, false).size(),
		"frame_ms_p50": percentile(times, 0.5),
		"frame_ms_p95": percentile(times, 0.95),
		"memory_static_kb": roundi(Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0),
	}


func _on_hard_timeout() -> void:
	if _finished:
		return
	_finished = true
	print("%s_TIMEOUT after %.0f s" % [PREFIX, _hard_seconds])
	quit(3)
