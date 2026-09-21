extends SceneTree
## Run WITHOUT --headless: the dummy display cannot capture the mouse.
## Exercise the real input handlers, seat-relative look and non-accumulating shake.
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This input test needs a display. Run without --headless.")
		quit(2)
		return
	var anchor := Node3D.new()
	root.add_child(anchor)
	anchor.rotation.y = 0.7
	var scene: PackedScene = load("res://scenes/presentation/first_person_camera.tscn")
	var camera: Camera3D = scene.instantiate()
	camera.position = Vector3(0.2, 1.5, -0.3)
	anchor.add_child(camera)
	camera.set_process(false)
	camera.activate()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await process_frame
	_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Test display captures the mouse")
	var rest: Transform3D = camera.transform
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(100.0, -50.0)
	camera._unhandled_input(mouse)
	camera._process(0.0)
	var looking: Transform3D = camera.transform
	_expect(not looking.basis.is_equal_approx(rest.basis), "Mouse turns the active seat camera")
	_expect(looking.origin.is_equal_approx(rest.origin), "Looking keeps the eye anchored in its seat")
	_expect(camera.global_basis.is_equal_approx(anchor.global_basis * looking.basis), "Look inherits the vehicle's orientation")
	camera._process(0.1)
	_expect(camera.transform.is_equal_approx(looking), "Look persists without further mouse input")
	camera._on_vehicle_impact(5.0, Vector3.ZERO)
	camera._process(0.01)
	camera._process(1.0)
	_expect(camera.transform.is_equal_approx(looking), "Shake returns to player's chosen look direction")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera._unhandled_input(mouse)
	camera._process(0.0)
	_expect(camera.transform.is_equal_approx(looking), "Menus block mouse look")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	paused = true
	camera._unhandled_input(mouse)
	camera._process(0.1)
	_expect(camera.transform.is_equal_approx(looking), "Pause blocks look")
	paused = false
	camera.deactivate()
	camera._unhandled_input(mouse)
	_expect(camera.transform.is_equal_approx(rest), "Inactive cameras ignore look input")
	camera.activate()
	mouse.relative = Vector2(100000.0, -100000.0)
	camera._unhandled_input(mouse)
	_expect(is_equal_approx(camera._look_yaw, -deg_to_rad(camera.yaw_limit_degrees)), "Horizontal head turn clamps at its limit")
	_expect(is_equal_approx(camera._look_pitch, deg_to_rad(camera.pitch_limit_degrees)), "Vertical head turn clamps before flipping")
	var center := InputEventAction.new()
	center.action = &"look_center"
	center.pressed = true
	camera._unhandled_input(center)
	_expect(camera.transform.is_equal_approx(rest), "Center view restores forward seat orientation")
	Input.action_press(&"look_right", 0.6)
	for frame in range(30):
		camera._process(1.0 / 30.0)
	var at_30_fps: Basis = camera.basis
	camera.reset_look()
	for frame in range(120):
		camera._process(1.0 / 120.0)
	_expect(camera.basis.is_equal_approx(at_30_fps), "Stick turn speed is independent of render frame rate")
	Input.action_release(&"look_right")
	var player_scene: PackedScene = load("res://scenes/gameplay/player/player.tscn")
	var player: Node3D = player_scene.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	Input.action_press(&"look_right")
	player._physics_process(0.1)
	_expect(player.rotation.y < 0.0, "Right stick turns the on-foot player right")
	Input.action_release(&"look_right")
	player.rotation = Vector3.ZERO
	Input.action_press(&"walk_forward")
	player._physics_process(0.1)
	_expect(player.velocity.z < 0.0, "On-foot forward action walks toward camera forward")
	Input.action_release(&"walk_forward")
	player.board_seat(camera, false, null)
	var player_rotation: Vector3 = player.rotation
	Input.action_press(&"look_right")
	player._physics_process(0.1)
	_expect(player.rotation.is_equal_approx(player_rotation), "Seated player does not also consume foot look")
	Input.action_release(&"look_right")
	player.free()
	anchor.free()
	if failures == 0:
		print("PASS: mouse/stick look, seat orientation, limits, center, shake, pause, foot movement and frame-rate independence")
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
