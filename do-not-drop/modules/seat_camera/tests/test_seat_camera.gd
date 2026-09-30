extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/seat_camera/tests/test_seat_camera.gd
##
## The seat_camera module on its own (docs/modulos.md): the camera starts
## at the game's preferred field of view, reads per-seat look limits from a
## LookLimits marker's metadata, clamps look motion to them (with the
## game's sensitivity and inversion), recenters, shakes only while current
## and by the game's scale, kicks the field of view and recovers it, and
## backs off a wall in front of the eye.

var _failures: int = 0


class GameCamera extends SeatCamera:
	var wanted_fov: float = 75.0
	var sensitivity: float = 2.0
	var inverted: bool = false
	var shake_share: float = 0.5

	func _preferred_fov() -> float:
		return wanted_fov

	func _look_sensitivity() -> float:
		return sensitivity

	func _look_y_sign() -> float:
		return -1.0 if inverted else 1.0

	func _shake_scale() -> float:
		return shake_share


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var seat := Node3D.new()
	root.add_child(seat)
	var limits := Marker3D.new()
	limits.name = SeatCamera.LOOK_LIMITS_NODE
	limits.set_meta(&"pitch_min", -20.0)
	limits.set_meta(&"pitch_max", 30.0)
	limits.set_meta(&"yaw_max", 90.0)
	seat.add_child(limits)
	var camera := GameCamera.new()
	seat.add_child(camera)
	await process_frame
	_expect(is_equal_approx(camera.fov, 75.0), "The camera starts at the game's preferred FOV (got %.1f)" % camera.fov)
	var limits_read: Array[float] = [
		camera.pitch_down_limit_degrees, camera.pitch_limit_degrees, camera.yaw_limit_degrees,
	]
	_expect(limits_read == [-20.0, 30.0, 90.0],
		"Per-seat limits come from the marker's metadata (got %s)" % [limits_read])
	camera._apply_look(Vector2(10.0, 0.0))
	_expect(is_equal_approx(camera._look_yaw, -deg_to_rad(90.0)),
		"Yaw is clamped to the seat's limit (got %.2f)" % camera._look_yaw)
	camera.reset_look()
	camera._apply_look(Vector2(0.1, 0.0))
	_expect(is_equal_approx(camera._look_yaw, -0.2),
		"The game's sensitivity scales the motion (got %.3f)" % camera._look_yaw)
	camera.reset_look()
	camera.inverted = true
	camera._apply_look(Vector2(0.0, 0.1))
	_expect(camera._look_pitch > 0.0, "Inverted look flips the vertical motion (got %.3f)" % camera._look_pitch)
	camera.reset_look()
	_expect(is_zero_approx(camera._look_yaw) and is_zero_approx(camera._look_pitch), "Recentering zeroes the look")

	# The first camera in a viewport becomes current on its own: put it aside.
	camera.deactivate()
	camera.add_shake(1.0)
	_expect(is_zero_approx(camera.shake_strength()), "A camera that isn't current doesn't shake")
	camera.activate()
	camera.add_shake(1.0)
	_expect(is_equal_approx(camera.shake_strength(), 0.5),
		"Shake is scaled by the game's setting (got %.2f)" % camera.shake_strength())
	camera.kick_fov(10.0)
	_expect(is_equal_approx(camera.fov, 80.0), "The FOV kick is scaled too (got %.1f)" % camera.fov)
	for _frame: int in range(90):
		await process_frame
	_expect(camera.fov < 76.0 and camera.shake_strength() < 0.01,
		"The FOV recovers and the shake decays (fov %.1f, shake %.2f)" % [camera.fov, camera.shake_strength()])
	camera.deactivate()
	_expect(not camera.current and is_equal_approx(camera.fov, 75.0), "Deactivating restores the preferred FOV")

	# A wall right in front of the eye: the pose backs off along the line of sight.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# A thin wall 7 cm ahead of the eye, inside WALL_CLEARANCE + near.
	box.size = Vector3(4.0, 4.0, 0.04)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 0.0, -0.09)
	root.add_child(wall)
	await physics_frame
	await physics_frame
	var cleared: Transform3D = camera._clear_of_walls(Transform3D.IDENTITY)
	_expect(cleared.origin.z > 0.0 and cleared.origin.z <= SeatCamera.MAX_PULLBACK + 0.001,
		"The eye backs off a wall ahead, at most MAX_PULLBACK (got %.3f)" % cleared.origin.z)
	wall.queue_free()
	seat.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the seat camera reads limits, looks, shakes and clears walls on the module alone")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
