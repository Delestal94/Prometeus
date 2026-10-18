class_name GelContactDeformation
extends Node
## Presentation-only compression when two replicated player capsules meet.
## It reads existing transforms and velocities, but never changes gameplay
## movement, collision, authority or network state.

const CONTACT_DISTANCE: float = 0.74
const RELEASE_DISTANCE: float = 0.88
const MAX_VERTICAL_SEPARATION: float = 1.35
const MIN_COMPRESSION: float = 0.055
const MAX_COMPRESSION: float = 0.16
const SPEED_GAIN: float = 0.025
const RESPONSE: float = 24.0
const IMPULSE_DECAY: float = 0.72

var _mesh: MeshInstance3D
var _amount: float = 0.0
var _impulse: float = 0.0
var _local_direction: Vector3 = Vector3.RIGHT
var _touching: Dictionary = {}


func _exit_tree() -> void:
	_set_amount(0.0)


func setup(model: Node) -> bool:
	_mesh = PlayerAppearance.find_mesh_instance(model)
	reset_deformation()
	return _mesh != null


func update_contact(player: CharacterBody3D, delta: float) -> void:
	var touching_now: Dictionary = {}
	for candidate: Node in get_tree().get_nodes_in_group(&"player"):
		if candidate == player or not candidate is CharacterBody3D:
			continue
		var other := candidate as CharacterBody3D
		var offset: Vector3 = other.global_position - player.global_position
		var horizontal := Vector3(offset.x, 0.0, offset.z)
		var distance: float = horizontal.length()
		var other_id: int = other.get_instance_id()
		var was_touching: bool = _touching.has(other_id)
		var inside_contact: bool = distance <= CONTACT_DISTANCE and absf(offset.y) <= MAX_VERTICAL_SEPARATION
		var inside_release: bool = distance <= RELEASE_DISTANCE and absf(offset.y) <= MAX_VERTICAL_SEPARATION
		if inside_contact or (was_touching and inside_release):
			touching_now[other_id] = true
		if inside_contact and not was_touching:
			var direction: Vector3 = horizontal.normalized() if distance > 0.0001 else Vector3.RIGHT
			var closing_speed: float = maxf((player.velocity - other.velocity).dot(direction), 0.0)
			trigger_contact(direction, closing_speed)
	_touching = touching_now
	advance(delta)


func trigger_contact(world_direction: Vector3, closing_speed: float) -> void:
	var direction := Vector3(world_direction.x, 0.0, world_direction.z)
	if direction.length_squared() <= 0.000001:
		direction = Vector3.RIGHT
	if _mesh != null and is_instance_valid(_mesh):
		_local_direction = (_mesh.global_basis.inverse() * direction.normalized()).normalized()
	else:
		_local_direction = direction.normalized()
	_impulse = maxf(
		_impulse,
		clampf(MIN_COMPRESSION + maxf(closing_speed, 0.0) * SPEED_GAIN, MIN_COMPRESSION, MAX_COMPRESSION)
	)
	_write_uniforms()


func advance(delta: float) -> void:
	var step: float = maxf(delta, 0.0)
	var blend: float = 1.0 - exp(-RESPONSE * step)
	_set_amount(lerpf(_amount, _impulse, blend))
	_impulse = move_toward(_impulse, 0.0, IMPULSE_DECAY * step)


func reset_deformation() -> void:
	_amount = 0.0
	_impulse = 0.0
	_local_direction = Vector3.RIGHT
	_touching.clear()
	_write_uniforms()


func deformation_amount() -> float:
	return _amount


func deformation_direction() -> Vector3:
	return _local_direction


func deformation_scales() -> Vector3:
	var contact_scale: float = maxf(1.0 - _amount, 0.82)
	var radial_scale: float = 1.0 / sqrt(contact_scale)
	return Vector3(contact_scale, radial_scale, radial_scale)


func _set_amount(value: float) -> void:
	_amount = clampf(value, 0.0, MAX_COMPRESSION)
	_write_uniforms()


func _write_uniforms() -> void:
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.set_instance_shader_parameter(&"gel_contact_direction", _local_direction)
		_mesh.set_instance_shader_parameter(&"gel_contact_compression", _amount)
