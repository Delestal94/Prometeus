extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/press_photo/tests/test_press_photo.gd
##
## The press_photo module on its own (docs/modulos.md): framing() stands the
## camera `distance` away on the ground and `height` up on the side it is
## asked for, turned by its yaw, aimed just over the subject, and copes with a
## facing that points straight up; capture() comes back null at once headless
## (no frame to wait for) and leaves no viewport behind; the halftone
## material carries its paper, ink and dot pitch.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var subject := Vector3(10, 1, -4)
	var straight: Dictionary = PressPhoto.framing(subject, Vector3(0, 5, 2), 6.0, 2.0, 0.0, 0.5)
	_expect((straight["at"] as Vector3).is_equal_approx(subject + Vector3(0, 2, 6)),
			"Straight on: on the facing side, distance away and height up (%s)" % straight["at"])
	_expect((straight["look"] as Vector3).is_equal_approx(subject + Vector3(0, 0.5, 0)), "Aimed just over the subject")
	var turned: Dictionary = PressPhoto.framing(subject, Vector3.BACK, 6.0, 2.0, 90.0)
	var ground: Vector3 = (turned["at"] as Vector3) - subject
	_expect(is_equal_approx(Vector2(ground.x, ground.z).length(), 6.0) and is_equal_approx(ground.y, 2.0),
			"Turned, it keeps its distance and height (%s)" % ground)
	_expect(ground.x > 5.9, "A 90 degree yaw turns the camera from +Z round to +X (%s)" % ground)
	var up: Dictionary = PressPhoto.framing(subject, Vector3.UP, 4.0, 1.0, 0.0)
	_expect((up["at"] as Vector3).is_finite() and not (up["at"] as Vector3).is_equal_approx(up["look"]),
			"A facing straight up still gives a usable pose")

	var host := Node3D.new()
	root.add_child(host)
	var started: int = Time.get_ticks_msec()
	var photo: Texture2D = await PressPhoto.capture(host, straight)
	_expect(not PressPhoto.can_capture() and photo == null, "Headless there is nothing to capture")
	_expect(Time.get_ticks_msec() - started < 1000, "And it says so without waiting for a frame")
	_expect(host.get_child_count() == 0, "No viewport is left behind")
	_expect(await PressPhoto.capture(null, straight) == null, "No host, no photo")
	host.queue_free()

	var material: ShaderMaterial = PressPhoto.halftone_material(Color(0.9, 0.85, 0.8), Color(0.1, 0.1, 0.1), 6.0)
	_expect(material.shader == PressPhoto.HALFTONE and is_equal_approx(material.get_shader_parameter("pitch"), 6.0),
			"The halftone material carries its dot pitch")
	_expect((material.get_shader_parameter("print_ink") as Vector3).is_equal_approx(Vector3(0.1, 0.1, 0.1)),
			"And its ink")
	_expect(PressPhoto.HALFTONE.code.contains("FRAGCOORD"), "The screen is laid out in canvas pixels")

	if _failures == 0:
		print("PASS: press_photo frames a subject, captures nothing headless and prints a halftone")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
