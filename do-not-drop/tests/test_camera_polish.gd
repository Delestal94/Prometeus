extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_camera_polish.gd
## Covers items #63 (head bob), #64 (context FOV), #66 (per-seat shake
## intensity) and #67 (shake on package_ruined too) of
## docs/especificaciones-visuales.md.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_test_head_bob_and_fov()
	_test_shake_on_ruin()
	_test_per_seat_shake()
	if _failures == 0:
		print("PASS: head bob, context FOV, per-seat shake and ruin shake all check out")
	quit(_failures)


func _test_head_bob_and_fov() -> void:
	var player: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	root.add_child(player)
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var camera: Camera3D = player.get_node(^"Head/Camera3D")

	_expect(is_equal_approx(camera.fov, 78.0), "Starts at the walking FOV")

	Input.action_press(&"walk_forward")
	var bobbed: bool = false
	for _i: int in range(30):
		player.call(&"_physics_process", 1.0 / 60.0)
		if not is_equal_approx(camera.position.y, 0.0):
			bobbed = true
	Input.action_release(&"walk_forward")
	_expect(bobbed, "Walking actually bobs the camera instead of a perfectly flat glide")

	for _i: int in range(60):
		player.call(&"_physics_process", 1.0 / 60.0)
	_expect(absf(camera.position.y) < 0.01, "Standing still settles the bob back to (near) zero")

	player.set(&"carried_package", Node3D.new())  # any Node with .free()-able lifetime works, only the null-check matters
	for _i: int in range(60):
		player.call(&"_physics_process", 1.0 / 60.0)
	_expect(camera.fov < 78.0, "Carrying a package narrows the FOV instead of sharing walking's frame")
	(player.get(&"carried_package") as Node).free()
	player.free()


func _test_shake_on_ruin() -> void:
	var bus: Node = root.get_node(^"/root/EventBus")
	var camera: Camera3D = load("res://scenes/presentation/first_person_camera.tscn").instantiate()
	root.add_child(camera)
	await process_frame
	camera.call(&"activate")

	_expect(is_equal_approx(float(camera.get(&"_shake_strength")), 0.0), "No shake at rest")
	bus.emit_signal(&"package_ruined", &"fragile_01", "test")
	_expect(float(camera.get(&"_shake_strength")) > 0.0,
		"A ruined package shakes the camera too, not only a vehicle collision")
	_expect(is_equal_approx(camera.fov, float(camera.get(&"BASE_FOV"))),
		"But doesn't trigger the impact FOV kick -- that's reserved for real collisions")
	camera.free()


func _test_per_seat_shake() -> void:
	var vehicle: Node = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	root.add_child(vehicle)
	await process_frame
	var driver_camera: Camera3D = vehicle.get_node(^"CabinInterior/DriverEyePoint/FirstPersonCamera")
	var back_camera: Camera3D = vehicle.get_node(^"CargoBay/LeftSeat2EyePoint/FirstPersonCamera")
	_expect(float(back_camera.get(&"shake_position_scale")) > float(driver_camera.get(&"shake_position_scale")),
		"The back seat shakes more than the driver's, not the same fixed amount everywhere")
	vehicle.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
