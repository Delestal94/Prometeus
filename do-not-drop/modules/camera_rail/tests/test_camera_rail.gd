extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/camera_rail/tests/test_camera_rail.gd
##
## The camera_rail module on its own (docs/modulos.md): a rail holds its first
## pose before it starts and its last after it ends, passes through every
## point at its second, eases the move once over the whole rail (soft start
## and stop, a snap with "out", a jump with "cut"), interpolates aim, up and
## field of view (keeping the last one said), and reads points written as
## arrays (JSON) as well as vectors.

var _failures: int = 0


func _initialize() -> void:
	var rail: Array = [
		{"at": Vector3(0, 0, 0), "look": Vector3(0, 0, -1), "t": 0.0, "fov": 40.0},
		{"at": Vector3(2, 0, 0), "look": Vector3(2, 0, -1), "t": 1.0},
		{"at": Vector3(4, 2, 0), "look": Vector3(4, 0, -1), "t": 3.0, "fov": 20.0, "up": Vector3.RIGHT},
	]
	var before: Dictionary = CameraRail.pose_at(rail, -1.0)
	_expect(before["at"] == Vector3.ZERO and is_equal_approx(before["fov"], 40.0), "Holds the first pose before it starts")
	var after: Dictionary = CameraRail.pose_at(rail, 9.0)
	_expect((after["at"] as Vector3).is_equal_approx(Vector3(4, 2, 0)) and is_equal_approx(after["fov"], 20.0),
			"Holds the last pose after it ends")
	_expect((after["up"] as Vector3).is_equal_approx(Vector3.RIGHT), "Ends with the last point's up")
	var linear: Dictionary = CameraRail.pose_at(rail, 1.0, "linear")
	_expect((linear["at"] as Vector3).is_equal_approx(Vector3(2, 0, 0)), "Linear passes through a point at its second")
	_expect(is_equal_approx(linear["fov"], 40.0), "A point without fov keeps the one before (%s)" % linear["fov"])
	var mid: Dictionary = CameraRail.pose_at(rail, 2.0, "linear")
	_expect(float(mid["fov"]) < 40.0 and float(mid["fov"]) > 20.0, "The fov eases between points")

	var straight: Array = [{"at": [0, 0, 0], "look": [0, 0, -5], "t": 0}, {"at": [10, 0, 0], "look": [10, 0, -5], "t": 2}]
	var early: float = (CameraRail.pose_at(straight, 0.2)["at"] as Vector3).x
	var half: float = (CameraRail.pose_at(straight, 1.0)["at"] as Vector3).x
	_expect(early < 1.0 and is_equal_approx(half, 5.0), "Smooth starts slow and is half way at half time (%.2f, %.2f)" % [early, half])
	var snap: float = (CameraRail.pose_at(straight, 0.4, "out")["at"] as Vector3).x
	_expect(snap > 7.0, "Out covers most of the way early (%.2f)" % snap)
	var cut: float = (CameraRail.pose_at(straight, 1.9, "cut")["at"] as Vector3).x
	_expect(is_equal_approx(cut, 0.0) and is_equal_approx((CameraRail.pose_at(straight, 2.0, "cut")["at"] as Vector3).x, 10.0),
			"Cut holds, then jumps at the next point's second")
	var plain: Dictionary = CameraRail.pose_at(straight, 1.0)
	_expect(plain["up"] == Vector3.UP and is_equal_approx(plain["fov"], CameraRail.DEFAULT_FOV), "Defaults: up and fov")
	_expect(is_equal_approx(CameraRail.length(rail), 3.0) and CameraRail.length([]) == 0.0, "Length is the last point's second")
	_expect(CameraRail.pose_at([], 1.0).has("at"), "An empty rail still gives a pose")
	for name: String in CameraRail.EASES:
		_expect(is_equal_approx(CameraRail.eased_fraction(0.0, name), 0.0) and is_equal_approx(CameraRail.eased_fraction(1.0, name), 1.0),
				"Ease %s goes from 0 to 1" % name)
	if _failures == 0:
		print("PASS: camera rails hold, pass their points, ease once and blend aim, up and fov")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
