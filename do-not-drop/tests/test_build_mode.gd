extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_build_mode.gd
##
## State of the warehouse build mode (expansion D-0901, build_mode.gd):
## - enter() starts it on a floor, shows the grid and emits `entered`; exit() undoes it and
##   emits `exited`;
## - enter() is refused (state unchanged, last_refusal set) when already active, on an empty
##   floor, or when the caller says the crew member is busy;
## - exit() when not active does nothing;
## - grid_lines() holds one segment per grid line (border included) and is empty when the
##   grid is hidden or the mode is off;
## - pan() keeps the focus over the floor; zoom_by() stays within the tuning limits;
## - camera_pose() is raised, pitched as tuned, and higher when zoomed out.

var _failures: int = 0
var _entered: int = 0
var _exited: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mode := BuildMode.new()
	mode.entered.connect(func() -> void: _entered += 1)
	mode.exited.connect(func() -> void: _exited += 1)

	_expect(not mode.active, "starts inactive")
	_expect(mode.grid_lines().is_empty(), "no grid lines while inactive")
	_expect(not mode.exit(), "exit() when inactive does nothing")

	_expect(not mode.enter(Vector2i(12, 8), false), "busy crew member cannot enter")
	_expect(mode.last_refusal == &"busy" and not mode.active, "busy refusal leaves it off")
	_expect(not mode.enter(Vector2i(0, 8)), "empty floor is refused")
	_expect(mode.last_refusal == &"empty_floor", "empty floor reason")

	_expect(mode.enter(Vector2i(12, 8)), "enter on a valid floor")
	_expect(mode.active and mode.grid_visible and _entered == 1, "active, grid on, signal once")
	_expect(mode.focus == Vector2(6.0, 4.0), "focus starts at the floor center")
	_expect(not mode.enter(Vector2i(12, 8)), "entering twice is refused")
	_expect(mode.last_refusal == &"already_active" and _entered == 1, "second enter changes nothing")

	# 12 x 8 cells: 13 vertical + 9 horizontal lines, 2 points each.
	_expect(mode.grid_lines().size() == (13 + 9) * 2, "grid has a line per cell border (got %d)" % mode.grid_lines().size())
	mode.set_grid_visible(false)
	_expect(mode.grid_lines().is_empty(), "hidden grid draws nothing")
	mode.set_grid_visible(true)

	mode.pan(Vector2(100.0, -100.0))
	_expect(mode.focus == Vector2(12.0, 0.0), "pan stops at the floor edge (got %s)" % mode.focus)
	mode.zoom_by(10.0)
	_expect(is_equal_approx(mode.zoom, CompanyTuning.BUILD_ZOOM_MAX), "zoom out is clamped")
	var far: Dictionary = mode.camera_pose()
	mode.zoom_by(-10.0)
	_expect(is_equal_approx(mode.zoom, CompanyTuning.BUILD_ZOOM_MIN), "zoom in is clamped")
	var near: Dictionary = mode.camera_pose()
	_expect((far["position"] as Vector3).y > (near["position"] as Vector3).y, "zoomed out is higher")
	_expect((near["position"] as Vector3).y > 1.0, "the camera is raised")
	_expect(is_equal_approx(near["pitch_deg"], CompanyTuning.BUILD_CAMERA_PITCH_DEG), "pitch as tuned")

	_expect(mode.exit() and not mode.active and not mode.grid_visible and _exited == 1, "exit turns it off")
	mode.pan(Vector2(1.0, 1.0))
	_expect(mode.focus == Vector2(12.0, 0.0), "pan is ignored when inactive")
	_expect(mode.enter(Vector2i(4, 4)) and mode.zoom == 1.0, "re-entering resets the zoom")

	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
