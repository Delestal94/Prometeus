extends SceneTree
## Performance probe of the Modo Empresa world (expansion D-2011). Run WITHOUT --headless (it
## measures real rendering), like bench_drive.gd:
##   <godot> --path do-not-drop --script res://tests/bench_company.gd -- --seconds=30
## Opens the company world (scenes/gameplay/company_root.tscn, what --mode=company opens) and moves
## a camera along a FIXED path for `--seconds` (default 30): a loop around the inside of the shed
## and, at the end, a look out of the door at the zone slabs. A second stage, "drive 30 s toward
## Barrio Centro" (D-2011.1), puts the player at the wheel of the fleet's van (the same driving as
## tests/bot_company_van.gd: the cab door, SeatPoint.interact, the accelerator held down), lets it
## roll out of the gate along the street for `--seconds` and follows it with a chase camera (behind and
## above, chase_pose()). It records its own frames; if there is no van or the player cannot board it,
## it prints `drive: not_available (<why>)` and is skipped without failing.
## Prints one summary block, a line per key with the stable prefix `BENCH_COMPANY key=value`
## (objects, nodes, draw_calls, draw_calls_peak, physics_bodies, physics_active, fps_avg, fps_low_1pct,
## frame_ms_p50, frame_ms_p95, memory_static_kb... of the walk, with the world as the walk left it; the same
## with `drive_` for the drive, plus drive_metres; `centro_` for the drive's frames inside Barrio Centro;
## `inside_` and `door_` for the walk's two parts, the loop and the look out of the door),
## then `BENCH_COMPANY_BUDGET <situation> <key>=<value> <limit> ok|OVER` against the budget of
## docs/rendimiento-pc.md (D-2012, BUDGET) and a final `BENCH_COMPANY_OK`. Over budget is reported, not a
## failure. It quits by itself; a hard wall-clock timeout ends it with `BENCH_COMPANY_TIMEOUT` (exit code 3) if
## the world never comes up or a frame never returns.
## Optional user args: -- --seconds=30 (per stage) --hard=<seconds> (the hard timeout)
## --quality=low|medium|high (or 0|1|2, the graphics preset; the budget is set on medium, the default).
## With --headless and -- --cpu-only it measures scripts + physics alone (draw_calls reads 0, no budget).
## The company saves into a temp folder (user://bench_company), never the game's slot.
## The camera paths and the summary format are static functions (camera_pose(), chase_pose(), summary_lines()),
## checked without rendering by tests/test_company_bench.gd.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const SAVE_DIR: String = "user://bench_company"
const PREFIX: String = "BENCH_COMPANY"
## The summary block, in this order: one `BENCH_COMPANY key=value` line each.
const SUMMARY_KEYS: Array[String] = [
	"mode", "quality", "resolution", "render_scale", "seconds", "frames", "build_ms", "objects", "object_count",
	"nodes", "draw_calls", "draw_calls_peak", "physics_bodies", "physics_active", "fps_avg", "fps_low_1pct",
	"frame_ms_p50", "frame_ms_p95", "memory_static_kb", "drive", "drive_frames", "drive_fps_avg",
	"drive_fps_low_1pct", "drive_frame_ms_p50", "drive_frame_ms_p95", "drive_draw_calls", "drive_draw_calls_peak",
	"drive_objects", "drive_nodes", "drive_physics_bodies", "drive_physics_active", "drive_metres",
	"centro_frames", "centro_fps_avg", "centro_fps_low_1pct", "centro_frame_ms_p50", "centro_frame_ms_p95",
	"centro_draw_calls", "centro_draw_calls_peak", "centro_objects",
	"inside_frames", "inside_fps_avg", "inside_fps_low_1pct", "inside_frame_ms_p50", "inside_frame_ms_p95",
	"inside_draw_calls", "inside_draw_calls_peak", "inside_objects",
	"door_frames", "door_fps_avg", "door_fps_low_1pct", "door_frame_ms_p50", "door_frame_ms_p95",
	"door_draw_calls", "door_draw_calls_peak", "door_objects",
]
## The budget of docs/rendimiento-pc.md (D-2012), rows in the doc's order: which summary key it caps, and the
## limit, as a floor ("min", the FPS) or a ceiling ("max"). draw_calls_peak, not the average: the walk's average
## hides the look out of the door, the worst view of the shed. physics_active: rigid bodies awake, not all of them.
## test_company_bench checks these numbers against the table of the doc. "Galpón grande lleno" (fps 60) is not
## here: this bench only opens the starting shed, D-0947 measures that one.
const BUDGET: Array[Dictionary] = [
	{"situation": "shed", "key": "fps_avg", "min": 90.0},
	{"situation": "shed", "key": "draw_calls_peak", "max": 900.0},
	{"situation": "shed", "key": "physics_active", "max": 400.0},
	{"situation": "shed", "key": "nodes", "max": 6000.0},
	{"situation": "centro", "key": "centro_fps_avg", "min": 75.0},
]
## The preset the budget is set on.
const DEFAULT_QUALITY: String = "medium"
const QUALITY_NAMES: Array[String] = ["low", "medium", "high"]
## The zone whose frames are the `centro_` keys: the van is inside its bounds.
const CENTRO_ZONE: String = "res://data/zones/centro.tres"
## What the drive stage prints when it is skipped: this prefix, then the reason.
const DRIVE_NOT_AVAILABLE: String = "drive: not_available"
## The van the stage drives: the fleet's (CompanyFleet), the same one the company-day bot takes out.
const VAN_ID: StringName = &"van_classic"
## The chase camera: this far behind the van and this high over it, looking at a point ahead of it.
const CHASE_BACK: float = 9.0
const CHASE_UP: float = 4.0
const CHASE_LOOK_AHEAD: float = 6.0
## Barrio Centro lies east (+X) of the shed along the Avenida Este (mapa.md: z = the shed's, from the gate
## to x = 256 and on), while the van leaves the yard facing north (-Z). The driver steers for the point
## DRIVE_LOOKAHEAD ahead of it on that avenue.
const DRIVE_LOOKAHEAD: float = 60.0
const STEER_LEFT: StringName = &"drive_left"
const STEER_RIGHT: StringName = &"drive_right"
## The angle off the nose (radians) at which the steering is at full lock; below it, proportional.
const STEER_FULL_LOCK: float = 0.5
## Physics ticks the stage lets the world settle (the van on the ground) before the player boards.
const DRIVE_SETTLE_TICKS: int = 30
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
## Drives the fleet's van like a player (boards it, holds the pedal): shared with the company-day bot.
const VAN := preload("res://tests/bot_company_van.gd")

var _camera: Camera3D
## The rigid bodies of the stage running (listed when it starts) and the most of them awake at a sample.
var _bodies: Array[RigidBody3D] = []
var _awake_peak: int = 0
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


## The chase camera for a van at `van_transform`: CHASE_BACK behind it and CHASE_UP above it
## (flattened to the ground plane, so the view does not pitch with the van's bounce), looking at a
## point CHASE_LOOK_AHEAD in front of the van. Pure: the same transform gives the same pose.
static func chase_pose(van_transform: Transform3D) -> Transform3D:
	var forward: Vector3 = -van_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var origin: Vector3 = van_transform.origin - forward * CHASE_BACK + Vector3.UP * CHASE_UP
	var target: Vector3 = van_transform.origin + forward * CHASE_LOOK_AHEAD
	return Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin)


## Where the driver aims, from where the van is: the avenue's centre line (z = `avenue_z`)
## DRIVE_LOOKAHEAD metres east of the van (or of the shed, if the van is still west of it).
static func drive_target(van_position: Vector3, avenue_z: float) -> Vector3:
	return Vector3(maxf(van_position.x, 0.0) + DRIVE_LOOKAHEAD, 0.0, avenue_z)


## The steering (-1 full left .. 1 full right, as Input.get_axis(drive_left, drive_right)) that points
## a van at `van_transform` to `target`: proportional to the angle off its nose, on the ground plane.
static func steer_toward(van_transform: Transform3D, target: Vector3) -> float:
	var forward: Vector3 = -van_transform.basis.z
	forward.y = 0.0
	var wanted: Vector3 = target - van_transform.origin
	wanted.y = 0.0
	if forward.length_squared() < 0.0001 or wanted.length_squared() < 0.0001:
		return 0.0
	# Counter-clockwise seen from above is to the left, so the steering is the angle with its sign flipped.
	return clampf(-forward.signed_angle_to(wanted, Vector3.UP) / STEER_FULL_LOCK, -1.0, 1.0)


# --- The summary (static too) ---


## Sorted values' q-th percentile (q in 0..1), as bench_drive.gd picks it.
static func percentile(sorted_values: Array[float], q: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	return sorted_values[clampi(int(q * sorted_values.size()), 0, sorted_values.size() - 1)]


## The preset named by `text` (a name of QUALITY_NAMES or its number), as a WorldQuality.Level.
static func quality_level(text: String) -> int:
	var by_name: int = QUALITY_NAMES.find(text.to_lower())
	return by_name if by_name >= 0 else clampi(int(text), 0, QUALITY_NAMES.size() - 1)


## One `BENCH_COMPANY key=value` line per SUMMARY_KEYS entry, in order ("n/a" for a missing one).
static func summary_lines(stats: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for key: String in SUMMARY_KEYS:
		var value: Variant = stats.get(key, "n/a")
		var text: String = "%.2f" % value if value is float else str(value)
		lines.append("%s %s=%s" % [PREFIX, key, text])
	return lines


## One `BENCH_COMPANY_BUDGET` line per BUDGET row, and how many are over: {"lines": [...], "over": n}. A key
## with no number (a stage that was skipped, or that never reached Centro) prints n/a and is not over.
static func budget_report(stats: Dictionary) -> Dictionary:
	var lines := PackedStringArray()
	var over: int = 0
	for row: Dictionary in BUDGET:
		var value: Variant = stats.get(row.key)
		var is_floor: bool = row.has("min")
		var limit: float = row.min if is_floor else row.max
		var verdict: String = "n/a"
		var shown: String = "n/a"
		if value is int or value is float:
			var inside: bool = float(value) >= limit if is_floor else float(value) <= limit
			verdict = "ok" if inside else "OVER"
			over += 0 if inside else 1
			shown = "%.2f" % value if value is float else str(value)
		lines.append("%s_BUDGET %s %s=%s %s%d %s" % [
			PREFIX, row.situation, row.key, shown, ">=" if is_floor else "<=", roundi(limit), verdict])
	return {"lines": lines, "over": over}


## The numbers of a stage's frames, each key after `prefix`: frame times, FPS (average and 1 % low, which is
## 1000 / p99 ms as in docs/rendimiento-pc.md) and what the renderer reported (averages, and the peak of the draw
## calls). Empty frames, no keys: the summary prints them n/a.
static func frame_stats(frames: Array[Dictionary], prefix: String) -> Dictionary:
	if frames.is_empty():
		return {}
	var times: Array[float] = []
	var total_ms: float = 0.0
	var draws: float = 0.0
	var peak_draws: float = 0.0
	var objects: float = 0.0
	for frame: Dictionary in frames:
		times.append(frame.ms)
		total_ms += frame.ms
		draws += frame.draws
		peak_draws = maxf(peak_draws, frame.draws)
		objects += frame.objects
	times.sort()
	var count: float = float(frames.size())
	var p99: float = percentile(times, 0.99)
	return {
		prefix + "frames": frames.size(),
		prefix + "fps_avg": count * 1000.0 / total_ms if total_ms > 0.0 else 0.0,
		prefix + "fps_low_1pct": 1000.0 / p99 if p99 > 0.0 else 0.0,
		prefix + "frame_ms_p50": percentile(times, 0.5),
		prefix + "frame_ms_p95": percentile(times, 0.95),
		prefix + "draw_calls": roundi(draws / count),
		prefix + "draw_calls_peak": roundi(peak_draws),
		prefix + "objects": roundi(objects / count),
	}


## The drive stage's keys of the summary (empty frames: the stage was skipped, they print n/a).
static func drive_stats(frames: Array[Dictionary], metres: float) -> Dictionary:
	if frames.is_empty():
		return {}
	var stats: Dictionary = frame_stats(frames, "drive_")
	stats["drive_metres"] = metres
	return stats


## The walk's frames of one part: the loop inside, or from WALK_FRACTION on, the look out of the door.
static func walk_part(frames: Array[Dictionary], seconds: float, door: bool) -> Array[Dictionary]:
	var part: Array[Dictionary] = []
	for frame: Dictionary in frames:
		if (float(frame.get("t", 0.0)) / maxf(seconds, 0.001) >= WALK_FRACTION) == door:
			part.append(frame)
	return part


## The frames of the drive with the van inside Barrio Centro.
static func centro_frames(frames: Array[Dictionary]) -> Array[Dictionary]:
	var inside: Array[Dictionary] = []
	for frame: Dictionary in frames:
		if frame.get("in_centro", false):
			inside.append(frame)
	return inside


## How many of `bodies` are simulated right now: awake and not frozen. The PHYSICS_3D_* monitors read 0 under
## Jolt (see bench_drive.gd), so the bodies are asked one by one.
static func awake_count(bodies: Array[RigidBody3D]) -> int:
	var awake: int = 0
	for body: RigidBody3D in bodies:
		if is_instance_valid(body) and not body.sleeping and not body.freeze:
			awake += 1
	return awake


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
	var quality: int = quality_level(_arg("quality", DEFAULT_QUALITY))
	WorldQuality.apply(self, quality)
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
	# Now: the drive streams cells in and the numbers of the shed must not count them.
	var stats: Dictionary = _collect(walk, level, seconds, build_ms)
	var drive: Dictionary = await _stage_drive(seconds)
	if _finished:
		return

	stats.merge(drive_stats(drive.frames, float(drive.metres)))
	stats.merge(_tree_stats(level, "drive_"))
	stats.merge(frame_stats(centro_frames(drive.frames), "centro_"))
	stats["drive"] = drive.status
	stats["quality"] = QUALITY_NAMES[quality]
	_close_world(level)
	if walk.is_empty():
		print("%s_FAIL no frames" % PREFIX)
		quit(1)
		return
	for line: String in summary_lines(stats):
		print(line)
	if stats.mode == "rendered":
		var budget: Dictionary = budget_report(stats)
		for line: String in budget.lines:
			print(line)
		print("%s_BUDGET_OVER %d" % [PREFIX, budget.over])
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


## "Drives `seconds` toward Barrio Centro": the player boards the fleet's van and holds the
## accelerator while the chase camera follows it. It steers for the Avenida Este (drive_target(): the
## yard opens north and Centro is east) and `metres` says how far the van got. Returns
## {"status": "ok", "frames": [...], "metres": how far the van went} or {"status": "not_available:
## <why>"}. The pedal is let go and the van braked at the end, and the player gets out.
func _stage_drive(seconds: float) -> Dictionary:
	var level := current_scene as CompanyRoot
	var why: String = await _board_van(level)
	if why != "":
		print("%s (%s)" % [DRIVE_NOT_AVAILABLE, why])
		return {"status": "not_available: %s" % why, "frames": [] as Array[Dictionary], "metres": 0.0}
	var van: VehicleBody3D = VAN.van_of(level, VAN_ID)
	var start: Vector3 = van.global_position
	var avenue_z: float = level.shed.global_position.z
	var centro: Rect2 = (load(CENTRO_ZONE) as ZoneDefinition).bounds
	Input.action_press(VAN.ACCELERATE)
	var frames: Array[Dictionary] = await _run_stage(
		seconds,
		func(_t: float, _s: float) -> Transform3D: return chase_pose(van.global_transform),
		func() -> Dictionary:
			_steer(steer_toward(van.global_transform, drive_target(van.global_position, avenue_z)))
			return {"in_centro": centro.has_point(Vector2(van.global_position.x, van.global_position.z))})
	Input.action_release(VAN.ACCELERATE)
	_steer(0.0)
	var metres: float = van.global_position.distance_to(start)
	await VAN.stop(self, van)
	(level.player as Player).leave_seat()
	await process_frame
	return {"status": "ok", "frames": frames, "metres": metres}


## Holds the steering actions at `amount` (-1 left .. 1 right).
func _steer(amount: float) -> void:
	if amount < 0.0:
		Input.action_release(STEER_RIGHT)
		Input.action_press(STEER_LEFT, -amount)
	else:
		Input.action_release(STEER_LEFT)
		Input.action_press(STEER_RIGHT, amount)


## Lets the van settle and puts the player at its wheel (opens the cab door, takes the seat as the
## host does). "" when he is at the wheel, else why not.
func _board_van(level: CompanyRoot) -> String:
	if level == null:
		return "no company world"
	for _tick: int in range(DRIVE_SETTLE_TICKS):
		await physics_frame
	var van: VehicleBody3D = VAN.van_of(level, VAN_ID)
	if van == null:
		return "no %s in the fleet" % VAN_ID
	var seat := van.get_node_or_null(VAN.SEAT_PATH) as SeatPoint
	if seat == null or level.player == null:
		return "no driver seat"
	van.call(&"set_door_open", VAN.DRIVER_DOOR, true)
	seat.interact(level.player)
	await physics_frame
	if int(van.get(&"driver_peer_id")) != level.player.get_multiplayer_authority():
		return "the player could not take the wheel"
	return ""


## The common stage loop: every frame the camera takes `pose.call(t, seconds)` and the frame time,
## draw calls and rendered objects are recorded. `t` is wall time since the stage began. `each_frame`
## (optional) is called first, with no arguments, and what it returns (a Dictionary) goes into the frame's
## record (the drive stage steers there and says whether the van is in Centro). Once a second it counts the
## rigid bodies awake, off the list made at the start: finding them every time would hitch the frame it measures.
func _run_stage(seconds: float, pose: Callable, each_frame: Callable = Callable()) -> Array[Dictionary]:
	_bodies.assign(current_scene.find_children("*", "RigidBody3D", true, false))
	_awake_peak = awake_count(_bodies)
	var frames: Array[Dictionary] = []
	var start: int = Time.get_ticks_usec()
	var last: int = start
	var elapsed: float = 0.0
	var next_sample: float = 1.0
	while elapsed < seconds and not _finished:
		var extra: Dictionary = each_frame.call() if each_frame.is_valid() else {}
		var next_pose: Transform3D = pose.call(elapsed, seconds)
		_camera.global_transform = next_pose
		await process_frame
		var now: int = Time.get_ticks_usec()
		var frame: Dictionary = {
			"t": elapsed,
			"ms": (now - last) / 1000.0,
			"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		}
		frame.merge(extra)
		frames.append(frame)
		last = now
		elapsed = (now - start) / 1000000.0
		if elapsed >= next_sample:
			next_sample += 1.0
			_awake_peak = maxi(_awake_peak, awake_count(_bodies))
	return frames


## What is in the world right now, each key after `prefix`: the rendered numbers come from the frames, these
## from the tree. physics_active is the peak of the stage that just ended.
func _tree_stats(level: Node, prefix: String) -> Dictionary:
	return {
		prefix + "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		prefix + "physics_bodies": level.find_children("*", "PhysicsBody3D", true, false).size(),
		prefix + "physics_active": _awake_peak,
	}


## The walk's numbers, called as it ends, before the drive changes what is in the world.
func _collect(frames: Array[Dictionary], level: Node, seconds: float, build_ms: float) -> Dictionary:
	var stats: Dictionary = {
		"mode": "cpu_only" if DisplayServer.get_name() == "headless" else "rendered",
		"resolution": "%dx%d" % [root.size.x, root.size.y],
		"render_scale": root.scaling_3d_scale,
		"seconds": seconds,
		"build_ms": build_ms,
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"memory_static_kb": roundi(Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0),
	}
	stats.merge(frame_stats(frames, ""))
	stats.merge(frame_stats(walk_part(frames, seconds, false), "inside_"))
	stats.merge(frame_stats(walk_part(frames, seconds, true), "door_"))
	stats.merge(_tree_stats(level, ""))
	return stats


func _on_hard_timeout() -> void:
	if _finished:
		return
	_finished = true
	print("%s_TIMEOUT after %.0f s" % [PREFIX, _hard_seconds])
	quit(3)
