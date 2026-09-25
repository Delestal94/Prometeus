extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_seat_look_limits.gd
##
## The camera doesn't go through the cab (N-504, first_person_camera.gd):
## - every seat's camera reads its own limits from the LookLimits marker on
##   its eye point (vehicle.tscn): the driver can't look up through the cab
##   roof or turn round through the bulkhead, the cargo seats get their own;
## - a wild mouse swing stops at those limits, both ways;
## - if the view still ends up nose-to-wall (under WALL_CLEARANCE), the eye
##   backs off along its line of sight -- and stays put with nothing ahead.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	van.freeze = true
	root.add_child(van)
	await process_frame
	var cameras: Array[Node] = van.find_children("FirstPersonCamera", "Camera3D", true, false)
	_expect(cameras.size() >= 11, "Every seat has its camera (%d)" % cameras.size())
	for camera: Node in cameras:
		var limits: Node = camera.get_parent().get_node_or_null(^"LookLimits")
		_expect(limits != null, "%s has its look limits" % camera.get_parent().name)
		if limits == null:
			continue
		_expect(is_equal_approx(float(camera.get(&"pitch_limit_degrees")), float(limits.get_meta(&"pitch_max")))
			and is_equal_approx(float(camera.get(&"pitch_down_limit_degrees")), float(limits.get_meta(&"pitch_min")))
			and is_equal_approx(float(camera.get(&"yaw_limit_degrees")), float(limits.get_meta(&"yaw_max"))),
			"%s's camera takes its seat's limits" % camera.get_parent().name)
	var driver: Node = van.get_node(^"CabinInterior/DriverEyePoint/FirstPersonCamera")
	_expect(float(driver.get(&"pitch_limit_degrees")) <= 40.0, "The driver can't look up through the roof (%.0f°)" % float(driver.get(&"pitch_limit_degrees")))
	_expect(float(driver.get(&"yaw_limit_degrees")) <= 120.0, "...nor turn round through the bulkhead (%.0f°)" % float(driver.get(&"yaw_limit_degrees")))

	# A wild swing each way stops at the limits.
	driver.call(&"_apply_look", Vector2(-100000.0, -100000.0))
	_expect(is_equal_approx(float(driver.get(&"_look_pitch")), deg_to_rad(float(driver.get(&"pitch_limit_degrees")))), "Looking up stops at the seat's limit")
	_expect(is_equal_approx(absf(float(driver.get(&"_look_yaw"))), deg_to_rad(float(driver.get(&"yaw_limit_degrees")))), "Turning stops at the seat's limit")
	driver.call(&"_apply_look", Vector2(200000.0, 200000.0))
	_expect(is_equal_approx(float(driver.get(&"_look_pitch")), deg_to_rad(float(driver.get(&"pitch_down_limit_degrees")))), "Looking down stops at the seat's limit")
	driver.call(&"reset_look")

	# Nose to a wall: the eye backs off. A cargo seat, looking straight ahead.
	var seat_camera := van.get_node(^"CargoBay/LeftSeat1EyePoint/FirstPersonCamera") as Camera3D
	var base: Transform3D = seat_camera.transform
	_expect(base.is_equal_approx(seat_camera.call(&"_clear_of_walls", base)), "With nothing right ahead, the eye stays in its seat")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 0.05)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	var forward: Vector3 = -seat_camera.global_basis.z
	wall.global_transform = Transform3D(seat_camera.global_basis, seat_camera.global_position + forward * 0.07)
	for frame: int in range(2):
		await physics_frame
	var backed: Transform3D = seat_camera.call(&"_clear_of_walls", base)
	var parent_node := seat_camera.get_parent() as Node3D
	var moved: Vector3 = parent_node.global_basis * (backed.origin - base.origin)
	_expect(moved.length() > 0.02 and moved.normalized().dot(-forward) > 0.9,
		"A wall 7 cm ahead: the eye backs off along its line of sight (%.3f m)" % moved.length())
	wall.queue_free()
	van.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: every seat has its look limits, a swing stops at them, and a wall in the face pushes the eye back")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
