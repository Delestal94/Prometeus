extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_bench.gd
##
## The bench of the Modo Empresa world (expansion D-2011, tests/bench_company.gd), the parts that
## need no rendering:
## - the camera path is deterministic: the same (t, seconds) gives the same pose, in any order,
##   and it starts and ends at the player's spawn by the door;
## - it stays inside the shed (48 x 32 m, CompanyRoot.SHED_SIZE) with a margin, at eye height,
##   and every pose is a valid, finite rotation;
## - it ends looking out of the door (+Z) at the zone slabs, sweeping from side to side;
## - the summary prints one `BENCH_COMPANY key=value` line per required key (objects, nodes,
##   draw_calls, physics_bodies, frame_ms_p50, frame_ms_p95, memory_static_kb...), in order,
##   even when a key is missing ("n/a"); the percentile picks as bench_drive.gd does;
## - the drive stage is skipped, saying why, while the company world has no vehicle (D-2011.1);
## - the bench saves in a temp folder, never in the game's company slot, and CI runs it as an
##   informational step.

const BENCH := preload("res://tests/bench_company.gd")
const SAMPLES: int = 601
## The camera stays at least this far from every wall of the shed, meters.
const WALL_MARGIN: float = 3.0
const REQUIRED_KEYS: Array[String] = [
	"objects", "nodes", "draw_calls", "physics_bodies", "frame_ms_p50", "frame_ms_p95", "memory_static_kb",
	"drive",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_path_is_deterministic()
	_check_path_stays_in_shed()
	_check_door_look()
	_check_summary()
	_check_wiring()
	if _failures == 0:
		print("PASS: company bench path is fixed and inside the shed, summary prints every key")
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
	_expect(BENCH.walk_length() > 60.0, "The loop is long enough to cross the shed (%.0f m)" % BENCH.walk_length())


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
		stats[key] = 1.5 if key.begins_with("frame_ms") else 7
	var lines: PackedStringArray = BENCH.summary_lines(stats)
	_expect(lines.size() == BENCH.SUMMARY_KEYS.size(), "One line per key (%d lines)" % lines.size())
	for index: int in range(mini(lines.size(), BENCH.SUMMARY_KEYS.size())):
		var key: String = BENCH.SUMMARY_KEYS[index]
		_expect(lines[index].begins_with("BENCH_COMPANY %s=" % key) and not lines[index].ends_with("=n/a"),
			"Line %d is `BENCH_COMPANY %s=value` (got '%s')" % [index, key, lines[index]])
	_expect("BENCH_COMPANY frame_ms_p95=1.50" in lines, "Times print with two decimals")
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


## What the file promises: the drive stage skipped with its reason, a temp save folder, and the
## step in CI that never fails the job.
func _check_wiring() -> void:
	_expect(BENCH.DRIVE_NOT_AVAILABLE.begins_with("drive: not_available")
		and BENCH.DRIVE_NOT_AVAILABLE.contains("D-2011.1"),
		"The drive stage says it is not available and why")
	_expect(BENCH.SAVE_DIR != CompanySave.SAVE_DIR and BENCH.SAVE_DIR.begins_with("user://"),
		"The bench saves in a folder of its own, not the game's company slot (%s)" % BENCH.SAVE_DIR)
	var workflow_path: String = ProjectSettings.globalize_path("res://") + "../.github/workflows/tests.yml"
	var workflow: String = FileAccess.get_file_as_string(workflow_path)
	if workflow.is_empty():
		return
	var step: int = workflow.find("bench_company.gd")
	_expect(step > 0 and workflow.find("|| true", step) > step,
		"CI runs bench_company.gd as an informational step (|| true)")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
