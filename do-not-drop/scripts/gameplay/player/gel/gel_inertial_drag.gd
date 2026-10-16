class_name GelInertialDrag
extends Node
## Presentation-only inertia for the head and arms. The shader weights vertices
## by distance from their neck/shoulder anchors; this controller only uploads a
## small local-space lag from body acceleration and yaw velocity.

const ACCELERATION_GAIN: float = 0.0015
const TURN_GAIN: float = 0.012
const MAX_LINEAR_DRAG: float = 0.055
const MAX_TURN_DRAG: float = 0.075
const RESPONSE: float = 13.0

var _mesh: MeshInstance3D
var _linear_drag: Vector3 = Vector3.ZERO
var _turn_drag: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO
var _last_yaw: float = 0.0
var _has_sample: bool = false


func _exit_tree() -> void:
	_set_uniform(Vector3.ZERO, 0.0)


func setup(model: Node) -> bool:
	_mesh = PlayerAppearance.find_mesh_instance(model)
	reset_motion()
	return _mesh != null


func advance_motion(linear_velocity: Vector3, yaw_radians: float, delta: float) -> void:
	var step: float = maxf(delta, 0.0001)
	if not _has_sample:
		_last_velocity = linear_velocity
		_last_yaw = yaw_radians
		_has_sample = true
		_set_uniform(Vector3.ZERO, 0.0)
		return

	var world_acceleration: Vector3 = (linear_velocity - _last_velocity) / step
	var local_acceleration: Vector3 = world_acceleration
	if _mesh != null and is_instance_valid(_mesh):
		local_acceleration = _mesh.global_basis.inverse() * world_acceleration
	var target_linear: Vector3 = (-local_acceleration * ACCELERATION_GAIN).limit_length(MAX_LINEAR_DRAG)
	var yaw_velocity: float = wrapf(yaw_radians - _last_yaw, -PI, PI) / step
	var target_turn: float = clampf(-yaw_velocity * TURN_GAIN, -MAX_TURN_DRAG, MAX_TURN_DRAG)
	var blend: float = 1.0 - exp(-RESPONSE * step)
	_linear_drag = _linear_drag.lerp(target_linear, blend)
	_turn_drag = lerpf(_turn_drag, target_turn, blend)
	_set_uniform(_linear_drag, _turn_drag)
	_last_velocity = linear_velocity
	_last_yaw = yaw_radians


func reset_motion() -> void:
	_linear_drag = Vector3.ZERO
	_turn_drag = 0.0
	_last_velocity = Vector3.ZERO
	_last_yaw = 0.0
	_has_sample = false
	_set_uniform(Vector3.ZERO, 0.0)


func drag_uniform() -> Vector4:
	return Vector4(_linear_drag.x, _linear_drag.y, _linear_drag.z, _turn_drag)


func _set_uniform(linear: Vector3, turn: float) -> void:
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.set_instance_shader_parameter(&"gel_inertia", Vector4(linear.x, linear.y, linear.z, turn))
