extends RefCounted
## Bounded stair/curb climbing for a CharacterBody3D. Call once per physics tick
## after setting velocity. Ordinary walking, slopes, jumps and falls still use
## the body's own move_and_slide(); only a verified low obstruction gets lifted.

const MAX_HEIGHT: float = .22
const MIN_RISE: float = .005


static func move_and_slide(body: CharacterBody3D, delta: float, height: float = MAX_HEIGHT) -> bool:
	var up: Vector3 = body.up_direction.normalized()
	var motion: Vector3 = body.velocity.slide(up) * delta
	if (
		height <= 0
		or not body.is_on_floor()
		or body.velocity.dot(up) > 0
		or motion.length_squared() < .000001
	):
		body.move_and_slide()
		return false
	var start: Transform3D = body.global_transform
	var blocked := KinematicCollision3D.new()
	if not body.test_move(start, motion, blocked, body.safe_margin):
		body.move_and_slide()
		return false
	# A normal slope is already handled by Godot, without a stair correction.
	if blocked.get_normal().dot(up) >= cos(body.floor_max_angle):
		body.move_and_slide()
		return false
	if body.test_move(start, up * height, null, body.safe_margin):
		body.move_and_slide()
		return false
	var raised: Transform3D = start
	raised.origin += up * height
	if body.test_move(raised, motion, null, body.safe_margin):
		body.move_and_slide()
		return false
	raised.origin += motion
	var landing := KinematicCollision3D.new()
	if not body.test_move(raised, -up * height, landing, body.safe_margin):
		body.move_and_slide()
		return false
	var at: Vector3 = raised.origin + landing.get_travel()
	var rise: float = (at - start.origin).dot(up)
	var support := KinematicCollision3D.new()
	# A rounded capsule can perch on a tall edge while its origin rises less
	# than that edge. Bound the actual supporting surfaces as well as the body.
	if not body.test_move(start, -up * height, support, body.safe_margin):
		body.move_and_slide()
		return false
	var surface_rise: float = (landing.get_position() - support.get_position()).dot(up)
	if (
		rise <= MIN_RISE
		or rise > height + body.safe_margin
		or surface_rise > height + body.safe_margin
		or landing.get_normal().dot(up) < cos(body.floor_max_angle)
	):
		body.move_and_slide()
		return false
	# The sweeps cover the full body shape, including its head. Refresh floor
	# state at the verified landing without applying horizontal motion twice.
	var horizontal_velocity: Vector3 = body.velocity.slide(up)
	body.global_position = at
	body.velocity = -up * .2
	body.move_and_slide()
	body.velocity += horizontal_velocity
	return true
