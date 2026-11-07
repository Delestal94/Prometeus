extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_bench.gd
##
## The bench of the Modo Empresa world (expansion D-2011, tests/bench_company.gd), the parts that
## need no rendering:
## - the camera path is deterministic: the same (t, seconds) gives the same pose, in any order,
##   and it starts and ends at the player's spawn by the door;
## - it stays inside the shed (12 x 8 m, CompanyRoot.SHED_SIZE) with a margin, at eye height,
##   and every pose is a valid, finite rotation;
## - it ends looking out of the door (+Z) at the zone slabs, sweeping from side to side;
## - the summary prints one `BENCH_COMPANY key=value` line per required key (objects, nodes,
##   draw_calls, physics_bodies, frame_ms_p50, frame_ms_p95, memory_static_kb...), in order,
##   even when a key is missing ("n/a"); the percentile picks as bench_drive.gd does;
## - the drive stage (D-2011.1: the player boards the fleet's van, holds the pedal and a chase camera
##   follows it): chase_pose() is deterministic and finite, puts the camera behind and above the van,
##   looking at it, whatever its heading, and ignores the van's pitch and roll; the steering for the
##   Avenida Este (drive_target(), steer_toward()) is 0 straight ahead, right for a target on the right,
##   left for the left, clamped, and finite at any heading; drive_stats() folds the stage's frames into
##   the summary's drive_* keys (and gives none when the stage was skipped, so they print n/a);
## - the budget (D-2012): frame_stats() gives FPS (average, 1 % low), frame times and the peak of the draw
##   calls, with its prefix; walk_part() splits the walk into the loop and the door look, centro_frames()
##   keeps the drive's frames in Barrio Centro; awake_count() counts only bodies awake and not frozen;
##   quality_level() reads the preset, medium by default, and refuses a misspelt one instead of reading low;
##   budget_report() marks each row ok or OVER, a floor for the FPS and a ceiling for the rest, n/a for a stage
##   that did not run, and every line of a run off the budget's preset or resolution; merge_drive() gives a skipped
##   drive only its status, none of its keys; the table of docs/rendimiento-pc.md says the same numbers as BUDGET,
##   its first row has been measured and the series keeps every budget key, as pc-build is told to;
## - _run() applies the preset and reads the shed's numbers before the drive; the bench saves in a temp folder,
##   never in the game's company slot, and CI runs it as an informational step.

const BENCH_SOURCE: String = "res://tests/bench_company.gd"
const BENCH := preload(BENCH_SOURCE)
const SAMPLES: int = 601
## The camera stays at least this far from every wall of the shed, meters.
const WALL_MARGIN: float = 1.0
const REQUIRED_KEYS: Array[String] = [
	"objects", "nodes", "draw_calls", "physics_bodies", "frame_ms_p50", "frame_ms_p95", "memory_static_kb",
	"drive", "drive_frames", "drive_frame_ms_p50", "drive_frame_ms_p95", "drive_draw_calls", "drive_objects",
	"drive_metres", "quality", "fps_avg", "fps_low_1pct", "draw_calls_peak", "physics_active", "drive_nodes",
	"drive_physics_active", "drive_object_count", "drive_memory_static_kb", "centro_frames", "centro_fps_avg",
	"inside_draw_calls_peak", "door_draw_calls_peak",
]
## Where the budget's table lives, from the project folder, and the rows that have a number.
const BUDGET_DOC: String = "../docs/rendimiento-pc.md"
const PC_BUILD_DOC: String = "../.claude/rutinas/pc-build.md"
const WORKFLOW: String = "../.github/workflows/tests.yml"
const SITUATIONS: Dictionary = {"shed": "Galpón por defecto", "centro": "Manejando por Centro"}
## The doc's heading of the series pc-build keeps, one row per run.
const SERIES: String = "Serie del presupuesto"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_path_is_deterministic()
	_check_path_stays_in_shed()
	_check_door_look()
	_check_summary()
	_check_chase_pose()
	_check_steering()
	_check_drive_stats()
	_check_merge_drive()
	_check_frame_stats()
	_check_walk_parts()
	_check_awake_count()
	_check_quality()
	_check_budget()
	_check_budget_doc()
	_check_wiring()
	if _failures == 0:
		print("PASS: company bench path is fixed and inside the shed, the chase camera follows the van,"
			+ " summary prints every key")
	quit(_failures)


func _pose_at(index: int, seconds: float) -> Transform3D:
	return BENCH.camera_pose(seconds * float(index) / float(SAMPLES - 1), seconds)


func _check_path_is_deterministic() -> void:
	var same: bool = true
	for seconds: float in [30.0, 5.0]:
		var forward: Array[Transform3D] = []
		for index: int in range(SAMPLES):
			forward.append(_pose_at(index, seconds))
		# Asked again and in reverse order: no state between calls.
		for index: int in range(SAMPLES - 1, -1, -1):
			if _pose_at(index, seconds) != forward[index]:
				same = false
	_expect(same, "The same (t, seconds) gives the same camera pose, in any order")
	var start: Transform3D = BENCH.camera_pose(0.0, 30.0)
	var spawn := Vector3(CompanyRoot.SPAWN.x, BENCH.EYE_HEIGHT, CompanyRoot.SPAWN.z)
	_expect(start.origin.is_equal_approx(spawn), "The walk starts at the player's spawn (got %s)" % start.origin)
	var loop_end: Transform3D = BENCH.camera_pose(30.0 * BENCH.WALK_FRACTION - 0.0001, 30.0)
	_expect(loop_end.origin.distance_to(spawn) < 0.5, "The loop closes at the spawn (got %s)" % loop_end.origin)
	_expect(BENCH.camera_pose(-5.0, 30.0) == start, "Before the stage it holds the first pose")
	_expect(BENCH.camera_pose(99.0, 30.0) == BENCH.camera_pose(30.0, 30.0), "After the stage it holds the last pose")
	var waypoints: PackedVector3Array = BENCH.walk_waypoints()
	_expect(waypoints.size() >= 4 and waypoints[0] == waypoints[waypoints.size() - 1], "The loop is closed")
	_expect(BENCH.path_point(0.0).is_equal_approx(BENCH.path_point(BENCH.walk_length())),
		"path_point() wraps at its length")


func _check_path_stays_in_shed() -> void:
	var half: Vector2 = CompanyRoot.SHED_SIZE * 0.5
	var worst_x: float = 0.0
	var worst_z: float = 0.0
	var valid: bool = true
	var level_eyes: bool = true
	for seconds: float in [30.0, 5.0]:
		for index: int in range(SAMPLES):
			var pose: Transform3D = _pose_at(index, seconds)
			worst_x = maxf(worst_x, absf(pose.origin.x))
			worst_z = maxf(worst_z, absf(pose.origin.z))
			var bad_basis: bool = not pose.basis.is_finite() or absf(pose.basis.determinant() - 1.0) > 0.001
			if not pose.origin.is_finite() or bad_basis:
				valid = false
			if not is_equal_approx(pose.origin.y, BENCH.EYE_HEIGHT):
				level_eyes = false
	_expect(worst_x <= half.x - WALL_MARGIN and worst_z <= half.y - WALL_MARGIN,
		"The camera stays %.0f m from the walls (|x| %.1f of %.1f, |z| %.1f of %.1f)"
		% [WALL_MARGIN, worst_x, half.x, worst_z, half.y])
	_expect(valid, "Every pose is a finite rotation (no look straight up or down, no zero direction)")
	_expect(level_eyes, "The camera stays at eye height (%.1f m)" % BENCH.EYE_HEIGHT)
	# A real walk: the loop covers the shed instead of standing at the door.
	_expect(BENCH.walk_length() > 12.0, "The loop is long enough to cross the shed (%.0f m)" % BENCH.walk_length())


func _check_door_look() -> void:
	var seconds: float = 30.0
	var first: Transform3D = BENCH.camera_pose(seconds * BENCH.WALK_FRACTION + 0.01, seconds)
	var last: Transform3D = BENCH.camera_pose(seconds, seconds)
	var facing_door: bool = true
	var sweep: float = 0.0
	for index: int in range(SAMPLES):
		var t: float = lerpf(seconds * BENCH.WALK_FRACTION + 0.01, seconds, float(index) / float(SAMPLES - 1))
		var pose: Transform3D = BENCH.camera_pose(t, seconds)
		if -pose.basis.z.z < 0.5:
			facing_door = false
	sweep = (-first.basis.z).angle_to(-last.basis.z)
	_expect(facing_door, "In the last part the camera looks out of the door (+Z) at the zone slabs")
	_expect(sweep > 0.3, "...sweeping across them (%.2f rad)" % sweep)
	_expect(-last.basis.z.y < 0.0, "...a little down, at the ground slabs, not at the sky")


func _check_summary() -> void:
	for key: String in REQUIRED_KEYS:
		_expect(key in BENCH.SUMMARY_KEYS, "The summary has the key %s" % key)
	var stats: Dictionary = {}
	for key: String in BENCH.SUMMARY_KEYS:
		stats[key] = 1.5 if "frame_ms" in key else 7
	var lines: PackedStringArray = BENCH.summary_lines(stats)
	_expect(lines.size() == BENCH.SUMMARY_KEYS.size(), "One line per key (%d lines)" % lines.size())
	for index: int in range(mini(lines.size(), BENCH.SUMMARY_KEYS.size())):
		var key: String = BENCH.SUMMARY_KEYS[index]
		_expect(lines[index].begins_with("BENCH_COMPANY %s=" % key) and not lines[index].ends_with("=n/a"),
			"Line %d is `BENCH_COMPANY %s=value` (got '%s')" % [index, key, lines[index]])
	_expect("BENCH_COMPANY frame_ms_p95=1.50" in lines and "BENCH_COMPANY drive_frame_ms_p95=1.50" in lines,
		"Times print with two decimals")
	_expect("BENCH_COMPANY nodes=7" in lines, "Counts print as integers")
	var sparse: PackedStringArray = BENCH.summary_lines({"nodes": 3})
	_expect(sparse.size() == BENCH.SUMMARY_KEYS.size() and "BENCH_COMPANY draw_calls=n/a" in sparse,
		"A key with no value still prints its line, as n/a")
	var values: Array[float] = []
	for index: int in range(1, 101):
		values.append(float(index))
	_expect(BENCH.percentile(values, 0.5) == 51.0 and BENCH.percentile(values, 0.95) == 96.0
		and BENCH.percentile(values, 1.0) == 100.0, "The percentile picks as bench_drive.gd does")
	_expect(BENCH.percentile([] as Array[float], 0.5) == 0.0, "The percentile of nothing is 0")


## A van `yaw` radians turned from facing north (-Z), at `at`.
func _van_at(at: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), at)


func _check_chase_pose() -> void:
	var worst_behind: float = 0.0
	var best_behind: float = INF
	var lowest_up: float = INF
	var looks_at_van: bool = true
	var valid: bool = true
	var same: bool = true
	for index: int in range(24):
		var yaw: float = TAU * float(index) / 24.0
		var van: Transform3D = _van_at(Vector3(40.0 + index, 0.6, -13.0), yaw)
		var pose: Transform3D = BENCH.chase_pose(van)
		same = same and pose == BENCH.chase_pose(van)
		var forward: Vector3 = -van.basis.z
		var behind: float = (van.origin - pose.origin).dot(forward)
		worst_behind = maxf(worst_behind, behind)
		best_behind = minf(best_behind, behind)
		lowest_up = minf(lowest_up, pose.origin.y - van.origin.y)
		looks_at_van = looks_at_van and (van.origin - pose.origin).normalized().dot(-pose.basis.z) > 0.9
		if not pose.origin.is_finite() or not pose.basis.is_finite() or absf(pose.basis.determinant() - 1.0) > 0.001:
			valid = false
	_expect(same, "The same van transform gives the same chase pose")
	_expect(valid, "Every chase pose is a finite rotation")
	_expect(best_behind > BENCH.CHASE_BACK - 0.01 and worst_behind < BENCH.CHASE_BACK + 0.01,
		"The chase camera is %.0f m behind the van at any heading (%.2f..%.2f)"
		% [BENCH.CHASE_BACK, best_behind, worst_behind])
	_expect(lowest_up > BENCH.CHASE_UP - 0.01, "...and %.0f m above it (%.2f)" % [BENCH.CHASE_UP, lowest_up])
	_expect(looks_at_van, "...looking at the van (it stays ahead of the camera, within about 25 degrees)")
	# A van tipped on its side or nose: the camera keeps to the ground plane, still finite.
	var flat: Transform3D = _van_at(Vector3(0.0, 0.5, 0.0), 0.7)
	var tipped := Transform3D(flat.basis * Basis(Vector3.RIGHT, 0.5) * Basis(Vector3.FORWARD, 0.4), flat.origin)
	var tipped_pose: Transform3D = BENCH.chase_pose(tipped)
	var flat_pose: Transform3D = BENCH.chase_pose(_van_at(Vector3(0.0, 0.5, 0.0), 0.7))
	_expect(tipped_pose.origin.y == flat_pose.origin.y and tipped_pose.origin.is_finite(),
		"The camera height does not follow the van's pitch and roll")
	var upright := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(5.0, 1.0, 5.0))
	var degenerate: Transform3D = BENCH.chase_pose(upright)
	_expect(degenerate.origin.is_finite() and degenerate.basis.is_finite(),
		"A van pointing straight up still gives a finite pose")
	var moved: Transform3D = BENCH.chase_pose(_van_at(Vector3(100.0, 0.5, 0.0), 0.0))
	var start: Transform3D = BENCH.chase_pose(_van_at(Vector3(0.0, 0.5, 0.0), 0.0))
	_expect(is_equal_approx(moved.origin.x - start.origin.x, 100.0), "The camera travels with the van")


func _check_steering() -> void:
	# The yard's exit faces north (-Z) and Centro lies east (+X): the first target is to the van's right.
	var parked: Transform3D = _van_at(Vector3(0.0, 0.5, -11.0), 0.0)
	var first: Vector3 = BENCH.drive_target(parked.origin, 0.0)
	_expect(first.x > parked.origin.x + 30.0 and first.z == 0.0 and first.y == 0.0,
		"The first target is on the Avenida Este, east of the van (%s)" % first)
	_expect(BENCH.steer_toward(parked, first) > 0.9, "Facing north, the avenue to the east asks for full right (%.2f)"
		% BENCH.steer_toward(parked, first))
	_expect(BENCH.drive_target(Vector3(-50.0, 0.0, 0.0), 0.0).x > 0.0, "West of the shed it still aims east of it")
	_expect(BENCH.drive_target(Vector3(300.0, 0.0, -2.0), 0.0).x > 300.0, "...and further along it keeps aiming ahead")
	var east: Transform3D = _van_at(Vector3(100.0, 0.5, 0.0), -PI * 0.5)
	_expect(is_zero_approx(BENCH.steer_toward(east, Vector3(300.0, 0.0, 0.0))),
		"Facing the target the steering is 0 (%.3f)" % BENCH.steer_toward(east, Vector3(300.0, 0.0, 0.0)))
	var right: float = BENCH.steer_toward(east, Vector3(300.0, 0.0, 20.0))
	var left: float = BENCH.steer_toward(east, Vector3(300.0, 0.0, -20.0))
	_expect(right > 0.0 and left < 0.0 and is_equal_approx(right, -left),
		"A target on the right steers right, on the left steers left, the same amount (%.3f, %.3f)" % [right, left])
	_expect(absf(BENCH.steer_toward(east, Vector3(0.0, 0.0, 0.0))) == 1.0, "A target behind is full lock")
	var small: float = BENCH.steer_toward(east, Vector3(300.0, 0.0, 5.0))
	_expect(small > 0.0 and small < right, "A small angle steers less than a big one (%.3f < %.3f)" % [small, right])
	_expect(BENCH.steer_toward(east, east.origin) == 0.0, "On the target it does not steer")
	var pitched := Transform3D(east.basis * Basis(Vector3.RIGHT, 0.4), east.origin)
	var pitched_steer: float = BENCH.steer_toward(pitched, Vector3(300.0, 3.0, 20.0))
	_expect(absf(pitched_steer - right) < 0.2,
		"The steering is read on the ground plane (a pitched van, a target above: %.3f vs %.3f)"
		% [pitched_steer, right])
	var finite: bool = true
	for index: int in range(24):
		var steer: float = BENCH.steer_toward(_van_at(Vector3(index, 0.5, 0.0), TAU * float(index) / 24.0),
			Vector3(250.0, 0.0, 10.0))
		finite = finite and is_finite(steer) and absf(steer) <= 1.0
	_expect(finite, "At every heading the steering is a number in -1..1")


func _check_drive_stats() -> void:
	_expect(BENCH.drive_stats([] as Array[Dictionary], 0.0).is_empty(),
		"A skipped drive stage adds no keys (they print n/a)")
	var frames: Array[Dictionary] = []
	for index: int in range(100):
		frames.append({"ms": float(index + 1), "draws": 10.0, "objects": 20.0})
	var stats: Dictionary = BENCH.drive_stats(frames, 321.5)
	_expect(stats.get("drive_frames") == 100 and stats.get("drive_frame_ms_p50") == 51.0
		and stats.get("drive_frame_ms_p95") == 96.0, "The drive's frames give its count and percentiles (%s)" % stats)
	_expect(stats.get("drive_draw_calls") == 10 and stats.get("drive_objects") == 20
		and is_equal_approx(float(stats.get("drive_metres", 0.0)), 321.5), "...the averages and the metres driven")
	var lines: PackedStringArray = BENCH.summary_lines(stats)
	_expect("BENCH_COMPANY drive_metres=321.50" in lines and "BENCH_COMPANY drive_frames=100" in lines
		and "BENCH_COMPANY drive_frame_ms_p50=51.00" in lines, "...and they print as BENCH_COMPANY drive_* lines")
	_expect(BENCH.SUMMARY_KEYS.find("drive") < BENCH.SUMMARY_KEYS.find("drive_frames"),
		"The drive's status comes before its numbers")


func _check_merge_drive() -> void:
	var tree: Dictionary = {"drive_nodes": 9, "drive_physics_bodies": 9, "drive_physics_active": 9}
	var skipped: Dictionary = {"status": "not_available: no van", "frames": [] as Array[Dictionary], "metres": 0.0}
	var stats: Dictionary = {"nodes": 5, "physics_active": 2}
	BENCH.merge_drive(stats, skipped, tree)
	_expect(stats.keys().size() == 3 and stats.get("drive") == skipped.status,
		"A skipped drive adds its status and no number of its own (%s)" % stats)
	var lines: PackedStringArray = BENCH.summary_lines(stats)
	_expect("BENCH_COMPANY drive_nodes=n/a" in lines and "BENCH_COMPANY drive_physics_active=n/a" in lines,
		"...so the tree's drive_ keys print n/a, not the shed's numbers")
	var frames: Array[Dictionary] = [{"ms": 1.0, "draws": 2.0, "objects": 3.0, "in_centro": true}]
	var driven: Dictionary = {}
	BENCH.merge_drive(driven, {"status": "ok", "frames": frames, "metres": 12.0}, tree)
	_expect(driven.get("drive") == "ok" and driven.get("drive_nodes") == 9 and driven.get("drive_frames") == 1
		and driven.get("centro_frames") == 1 and driven.get("drive_metres") == 12.0,
		"A drive that ran adds its frames, the tree and Centro (%s)" % driven)


func _check_frame_stats() -> void:
	_expect(BENCH.frame_stats([] as Array[Dictionary], "x_").is_empty(), "No frames, no keys (they print n/a)")
	var frames: Array[Dictionary] = []
	for index: int in range(100):
		frames.append({"ms": float(index + 1), "draws": 10.0 + index, "objects": 20.0})
	var stats: Dictionary = BENCH.frame_stats(frames, "x_")
	_expect(stats.get("x_frames") == 100, "The frames are counted, under the prefix (%s)" % stats)
	_expect(is_equal_approx(float(stats.get("x_fps_avg", 0.0)), 100.0 * 1000.0 / 5050.0),
		"The average FPS is frames over the total time, not the mean of each frame's FPS")
	_expect(is_equal_approx(float(stats.get("x_fps_low_1pct", 0.0)), 1000.0 / 100.0),
		"The 1 %% low is 1000 / p99 ms, as docs/rendimiento-pc.md defines it")
	_expect(stats.get("x_draw_calls_peak") == 109 and stats.get("x_draw_calls") == 60,
		"The peak of the draw calls is apart from their average")
	var plain: Dictionary = BENCH.frame_stats(frames, "")
	_expect(plain.has("fps_avg") and plain.has("frames"), "With no prefix the keys are the walk's own")


func _check_walk_parts() -> void:
	var frames: Array[Dictionary] = []
	for index: int in range(300):
		frames.append({"t": index * 0.1, "ms": 1.0, "draws": 0.0, "objects": 0.0})
	var inside: Array[Dictionary] = BENCH.walk_part(frames, 30.0, false)
	var door: Array[Dictionary] = BENCH.walk_part(frames, 30.0, true)
	_expect(inside.size() + door.size() == frames.size(), "Every frame of the walk is in one part")
	_expect(inside.size() == 240 and door.size() == 60,
		"They split at WALK_FRACTION (%d, %d)" % [inside.size(), door.size()])
	_expect(float(door[0].t) >= 30.0 * BENCH.WALK_FRACTION, "The door part is the end of the stage")
	var drive: Array[Dictionary] = [{"in_centro": false}, {"in_centro": true}, {}, {"in_centro": true}]
	_expect(BENCH.centro_frames(drive).size() == 2, "centro_frames() keeps only the frames inside Centro")


func _check_awake_count() -> void:
	var awake := RigidBody3D.new()
	var sleeping := RigidBody3D.new()
	sleeping.sleeping = true
	var frozen := RigidBody3D.new()
	frozen.freeze = true
	var bodies: Array[RigidBody3D] = [awake, sleeping, frozen]
	_expect(BENCH.awake_count(bodies) == 1,
		"Only a body awake and not frozen counts as active (%d)" % BENCH.awake_count(bodies))
	for body: RigidBody3D in bodies:
		body.free()
	_expect(BENCH.awake_count(bodies) == 0, "A body freed since the list was made is not counted, nor does it crash")


func _check_quality() -> void:
	_expect(BENCH.DEFAULT_QUALITY == "medium", "The budget is set on the medium preset, the bench's default")
	_expect(BENCH.quality_level("medium") == WorldQuality.Level.MEDIUM
		and BENCH.quality_level("LOW") == WorldQuality.Level.LOW
		and BENCH.quality_level("high") == WorldQuality.Level.HIGH, "The presets are read by name")
	_expect(BENCH.quality_level("2") == WorldQuality.Level.HIGH and BENCH.quality_level("9") == WorldQuality.Level.HIGH,
		"...or by number, clamped")
	for misspelt: String in ["medum", "", "1.5"]:
		_expect(BENCH.quality_level(misspelt) == -1, "'%s' is no preset, not the low one" % misspelt)


## Stats that meet every row of the budget, right at its limits.
func _stats_on_limits() -> Dictionary:
	var stats: Dictionary = {}
	for row: Dictionary in BENCH.BUDGET:
		stats[row.key] = row.min if row.has("min") else int(row.max)
	return stats


func _check_budget() -> void:
	var report: Dictionary = BENCH.budget_report(_stats_on_limits())
	_expect(report.over == 0 and report.lines.size() == BENCH.BUDGET.size(),
		"Right on the limits nothing is over (%s)" % report)
	for line: String in report.lines:
		_expect(line.begins_with("BENCH_COMPANY_BUDGET ") and line.ends_with(" ok"),
			"A row inside prints ok (%s)" % line)
	for row: Dictionary in BENCH.BUDGET:
		_expect(row.key in BENCH.SUMMARY_KEYS, "The budget caps a key the summary prints (%s)" % row.key)
		var stats: Dictionary = _stats_on_limits()
		stats[row.key] = row.min - 1.0 if row.has("min") else int(row.max) + 1
		var worse: Dictionary = BENCH.budget_report(stats)
		_expect(worse.over == 1, "Past the limit of %s the report says one over (%s)" % [row.key, worse])
		_expect(" %s=" % row.key in " ".join(worse.lines) and " OVER" in " ".join(worse.lines), "...and which one")
	var skipped: Dictionary = _stats_on_limits()
	skipped.erase("centro_fps_avg")
	var without: Dictionary = BENCH.budget_report(skipped)
	_expect(without.over == 0 and "BENCH_COMPANY_BUDGET centro centro_fps_avg=n/a >=75 n/a" in without.lines,
		"A drive that never reached Centro is n/a, not over (%s)" % without)
	_check_budget_setup()


## The budget holds on the medium preset at 1920x1080: any other run says so on every line.
func _check_budget_setup() -> void:
	var stats: Dictionary = _stats_on_limits()
	stats["quality"] = BENCH.DEFAULT_QUALITY
	stats["resolution"] = BENCH.BUDGET_RESOLUTION
	_expect(BENCH.budget_off_setup(stats) == "" and BENCH.budget_report(stats).mark == "",
		"The budget's own setup has no mark")
	stats["quality"] = "low"
	var off: String = BENCH.budget_off_setup(stats)
	_expect(off == "quality=low", "Another preset is off (%s)" % off)
	stats["resolution"] = "1280x720"
	var report: Dictionary = BENCH.budget_report(stats)
	_expect("quality=low" in report.mark and "resolution=1280x720" in report.mark, "...and another size (%s)" % report)
	for line: String in report.lines:
		_expect(line.ends_with(report.mark) and not line.ends_with(" ok") and not line.ends_with(" OVER"),
			"A run off the setup has no bare ok or OVER (%s)" % line)


## A file of the repo around the project, checked to be there: an empty one would switch its checks off.
func _repo_file(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://") + path)
	_expect(not text.is_empty(), "%s is where this test reads it" % path)
	return text


## The numbers of the table are the bench's, its first row has what was measured, and the series that the
## "(perf)" rule compares against has a column for every row of the budget, and pc-build is told to fill them.
func _check_budget_doc() -> void:
	var doc: String = _repo_file(BUDGET_DOC)
	var limits: Dictionary = {}
	for row: Dictionary in BENCH.BUDGET:
		limits["%s %s" % [row.situation, row.key]] = roundi(row.get("min", row.get("max")))
	var first_row: String = "| %s | ≥ %d | ≤ %d | ≤ %d | ≤ %d |" % [SITUATIONS.shed, limits["shed fps_avg"],
		limits["shed draw_calls_peak"], limits["shed physics_active"], limits["shed nodes"]]
	_expect(first_row in doc, "The table's first row has the bench's numbers (%s)" % first_row)
	_expect(("| %s | ≥ %d | — | — | — |" % [SITUATIONS.centro, limits["centro centro_fps_avg"]]) in doc,
		"The table's Centro row has the bench's number")
	_expect("| Galpón grande lleno | ≥ 60 | — | — | — |" in doc,
		"The big shed's row, which D-0947 measures, is there")
	_expect(("| %s (medido) |" % SITUATIONS.shed) in doc, "The first row has a measured number")
	var routine: String = _repo_file(PC_BUILD_DOC)
	var series: int = doc.find(SERIES)
	var header: String = doc.substr(series, doc.find("|---", series) - series) if series >= 0 else ""
	_expect(SERIES in routine, "pc-build fills the budget's series (%s)" % SERIES)
	for row: Dictionary in BENCH.BUDGET:
		_expect(("`%s`" % row.key) in header, "The series has a column for %s" % row.key)
		_expect(("`%s`" % row.key) in routine, "pc-build records %s whether it fits or not" % row.key)


## What the file promises: a skipped drive stage says so with its reason, the medium preset, the shed read before
## the drive (it streams cells in, and the budget's row would count them), a temp save folder, and the step in CI
## that never fails the job.
func _check_wiring() -> void:
	_expect(BENCH.DRIVE_NOT_AVAILABLE.begins_with("drive: not_available") and BENCH.VAN_ID != &"",
		"A skipped drive stage says it is not available (and the reason follows it)")
	_expect(BENCH.SAVE_DIR != CompanySave.SAVE_DIR and BENCH.SAVE_DIR.begins_with("user://"),
		"The bench saves in a folder of its own, not the game's company slot (%s)" % BENCH.SAVE_DIR)
	var source: String = FileAccess.get_file_as_string(BENCH_SOURCE)
	var start: int = source.find("func _run() -> void:")
	var body: String = source.substr(start, source.find("\nfunc ", start + 1) - start) if start >= 0 else ""
	_expect("WorldQuality.apply(self, quality)" in body, "_run() applies the preset it reports")
	_expect(body.contains("_collect(") and body.find("_collect(") < body.find("_stage_drive("),
		"_run() reads the shed's numbers before the drive")
	var workflow: String = _repo_file(WORKFLOW)
	var step: int = workflow.find("bench_company.gd")
	_expect(step > 0 and workflow.find("|| true", step) > step,
		"CI runs bench_company.gd as an informational step (|| true)")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
