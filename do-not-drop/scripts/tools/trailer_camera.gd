extends "res://scripts/presentation/results_orbit.gd"
class_name TrailerCamera
## The trailer's camera (tareas de Nacho N-902), debug builds only. Built on
## the results orbit (results_orbit.gd): with no rail to follow it circles the
## truck like the results shot; with one, it glides along it.
##
## A rail is 2-6 points, each a camera pose and the second it's reached:
##   {"space": "truck"|"anchor"|"world", "at": [x, y, z], "look": [x, y, z], "t": seconds}
## "truck" rides along with the truck (chase shots), "anchor" is fixed to a
## place in the world the shot picked (a crossing, a house, the depot door),
## "world" is plain world space. Between points the position follows a
## Catmull-Rom curve and the aim point eases the same way, so the camera
## never snaps; it looks at `look` (same space), and holds the last pose.
##
## In a level (debug builds, LevelCommon adds it): F7 takes over the view as a
## free camera (WASD + Q/E, mouse to look, Shift faster), F5 records the view
## as the next rail point (relative to the truck), F6 plays the rail from the
## start, F8 prints it as JSON for data/trailer_shots.json.

const FLY_SPEED: float = 6.0
const LOOK_SENSITIVITY: float = 0.0025

var rail: Array = []
var rail_time: float = -1.0
var anchor: Transform3D = Transform3D.IDENTITY
var free_flying: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _previous_camera: Camera3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	far = 800.0
	fov = 55.0


func play(points: Array, anchor_transform: Transform3D = Transform3D.IDENTITY) -> void:
	rail = points
	anchor = anchor_transform
	rail_time = 0.0
	make_current()


func _process(delta: float) -> void:
	if free_flying:
		_fly(delta)
		return
	if rail.is_empty() or rail_time < 0.0:
		super(delta)
		return
	rail_time += delta
	var pose: Array = pose_at(rail_time)
	global_position = pose[0]
	if not (pose[1] as Vector3).is_equal_approx(global_position):
		look_at(pose[1], Vector3.UP)


## [camera position, aim point] at `time` along the rail, in world space.
func pose_at(time: float) -> Array:
	var count: int = rail.size()
	if count == 1:
		return [_point(rail[0], "at"), _point(rail[0], "look")]
	var index: int = 0
	while index < count - 2 and time > float(rail[index + 1].t):
		index += 1
	var start: float = float(rail[index].t)
	var end: float = float(rail[index + 1].t)
	var u: float = clampf((time - start) / maxf(end - start, 0.001), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u) if count == 2 else u
	var before: int = maxi(index - 1, 0)
	var after: int = mini(index + 2, count - 1)
	var at: Vector3 = _catmull(_point(rail[before], "at"), _point(rail[index], "at"), _point(rail[index + 1], "at"), _point(rail[after], "at"), u)
	var look: Vector3 = _catmull(_point(rail[before], "look"), _point(rail[index], "look"), _point(rail[index + 1], "look"), _point(rail[after], "look"), u)
	return [at, look]


func rail_length() -> float:
	return float(rail[-1].t) if not rail.is_empty() else 0.0


func _point(point: Dictionary, key: String) -> Vector3:
	var value: Array = point[key]
	var local := Vector3(value[0], value[1], value[2])
	match String(point.get("space", "truck")):
		"truck":
			return target.get_global_transform_interpolated() * local if is_instance_valid(target) else local
		"anchor":
			return anchor * local
	return local


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# --- Free camera (F7) and recording (F5/F6/F8) --------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F7:
				_toggle_free()
			KEY_F5:
				record_point()
			KEY_F6:
				play(rail)
			KEY_F8:
				print("TRAILER RAIL ", JSON.stringify(rail))
	elif free_flying and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= (event as InputEventMouseMotion).relative.x * LOOK_SENSITIVITY
		_pitch = clampf(_pitch - (event as InputEventMouseMotion).relative.y * LOOK_SENSITIVITY, -1.5, 1.5)


func _toggle_free() -> void:
	free_flying = not free_flying
	if free_flying:
		_previous_camera = get_viewport().get_camera_3d()
		if _previous_camera != null and _previous_camera != self:
			global_transform = _previous_camera.global_transform
		var euler: Vector3 = global_basis.get_euler()
		_yaw = euler.y
		_pitch = euler.x
		make_current()
	elif is_instance_valid(_previous_camera):
		_previous_camera.make_current()


func _fly(delta: float) -> void:
	basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move.z -= 1.0
	if Input.is_key_pressed(KEY_S): move.z += 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if Input.is_key_pressed(KEY_E): move.y += 1.0
	if Input.is_key_pressed(KEY_Q): move.y -= 1.0
	var speed: float = FLY_SPEED * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	global_position += basis * move.normalized() * speed * delta


## The current view as the next rail point, relative to the truck, two
## seconds after the last one.
func record_point() -> Dictionary:
	var to_truck: Transform3D = target.global_transform.affine_inverse() if is_instance_valid(target) else Transform3D.IDENTITY
	var at: Vector3 = to_truck * global_position
	var look: Vector3 = to_truck * (global_position - global_basis.z * 10.0)
	var point := {"space": "truck", "at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)],
		"look": [snappedf(look.x, 0.01), snappedf(look.y, 0.01), snappedf(look.z, 0.01)],
		"t": (float(rail[-1].t) + 2.0) if not rail.is_empty() else 0.0}
	rail.append(point)
	return point
