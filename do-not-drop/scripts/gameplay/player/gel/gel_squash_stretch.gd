class_name GelSquashStretch
extends Node
## Presentation-only, constant-volume deformation driven by body acceleration.
## The shader stretches vertically and compensates both radial axes, so the
## product of the three scale factors stays at one. Collision is untouched.

const MAX_STRETCH: float = 0.16
const MAX_SQUASH: float = -0.18
const ACCELERATION_GAIN: float = 0.0022
const TAKEOFF_GAIN: float = 0.026
const LANDING_GAIN: float = 0.030
const MIN_TAKEOFF: float = 0.055
const MIN_LANDING: float = 0.075
const RESPONSE: float = 16.0
const IMPULSE_DECAY: float = 7.0

var _mesh: MeshInstance3D
var _amount: float = 0.0
var _impulse: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO
var _was_grounded: bool = true
var _has_sample: bool = false


func _exit_tree() -> void:
	_set_amount(0.0)


func setup(model: Node) -> bool:
	_mesh = PlayerAppearance.find_mesh_instance(model)
	reset_motion()
	return _mesh != null


func advance_motion(linear_velocity: Vector3, grounded: bool, delta: float) -> void:
	var step: float = maxf(delta, 0.0001)
	if not _has_sample:
		_last_velocity = linear_velocity
		_was_grounded = grounded
		_has_sample = true
		_set_amount(0.0)
		return

	var vertical_acceleration: float = (linear_velocity.y - _last_velocity.y) / step
	var acceleration_amount: float = clampf(
		vertical_acceleration * ACCELERATION_GAIN, MAX_SQUASH * 0.5, MAX_STRETCH * 0.65
	)
	# Takeoff stretches along the jump. Contact reverses the positive stopping
	# acceleration into compression: the body spreads while its feet stop.
	if _was_grounded and not grounded and linear_velocity.y > 0.0:
		trigger_takeoff(linear_velocity.y)
	elif not _was_grounded and grounded:
		trigger_landing(absf(minf(_last_velocity.y, 0.0)))
	else:
		_impulse = clampf(_impulse + acceleration_amount, MAX_SQUASH, MAX_STRETCH)

	_impulse = move_toward(_impulse, 0.0, IMPULSE_DECAY * step * 0.1)
	var blend: float = 1.0 - exp(-RESPONSE * step)
	_set_amount(lerpf(_amount, _impulse, blend))
	_last_velocity = linear_velocity
	_was_grounded = grounded


func trigger_takeoff(speed: float) -> void:
	_impulse = maxf(_impulse, clampf(absf(speed) * TAKEOFF_GAIN, MIN_TAKEOFF, MAX_STRETCH))


func trigger_landing(speed: float) -> void:
	_impulse = minf(_impulse, -clampf(absf(speed) * LANDING_GAIN, MIN_LANDING, -MAX_SQUASH))


func reset_motion() -> void:
	_amount = 0.0
	_impulse = 0.0
	_last_velocity = Vector3.ZERO
	_was_grounded = true
	_has_sample = false
	_set_amount(0.0)


func deformation_amount() -> float:
	return _amount


func deformation_scales() -> Vector3:
	var vertical_scale: float = maxf(1.0 + _amount, 0.8)
	var radial_scale: float = 1.0 / sqrt(vertical_scale)
	return Vector3(radial_scale, vertical_scale, radial_scale)


func _set_amount(value: float) -> void:
	_amount = clampf(value, MAX_SQUASH, MAX_STRETCH)
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.set_instance_shader_parameter(&"gel_squash_stretch", _amount)
