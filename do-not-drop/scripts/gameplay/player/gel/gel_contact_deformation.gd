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
const HARD_IMPACT_SPEED: float = 7.0
const FULL_IMPACT_SPEED: float = 18.0
const MIN_EXTREME_AMOUNT: float = 0.48
const MAX_EXTREME_AMOUNT: float = 1.0
const MAX_EXTREME_REBOUND: float = 0.42
const EXTREME_SPRING: float = 92.0
const EXTREME_DAMPING: float = 5.5
const EXTREME_MAX_SPEED: float = 12.0
const EXTREME_PACK_CENTER: float = 0.75
const EXTREME_PACK_HALF_RANGE: float = 0.5
const EXTREME_AXIS_MIN: float = 0.36
const EXTREME_AXIS_MAX: float = 1.65
const WORLD_IMPACT_COOLDOWN: float = 0.18

var _mesh: MeshInstance3D
var _amount: float = 0.0
var _impulse: float = 0.0
var _extreme_amount: float = 0.0
var _extreme_velocity: float = 0.0
var _extreme_active: bool = false
var _local_direction: Vector3 = Vector3.RIGHT
var _touching: Dictionary = {}
var _last_velocity: Vector3 = Vector3.ZERO
var _has_velocity_sample: bool = false
var _world_impact_cooldown: float = 0.0


func _exit_tree() -> void:
	reset_deformation()


func setup(model: Node) -> bool:
	_mesh = PlayerAppearance.find_mesh_instance(model)
	reset_deformation()
	return _mesh != null


func update_contact(player: CharacterBody3D, delta: float) -> void:
	_update_world_impact(player, delta)
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
	if closing_speed >= HARD_IMPACT_SPEED:
		trigger_extreme_impact(world_direction, closing_speed)
		return
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


func trigger_extreme_impact(world_direction: Vector3, closing_speed: float) -> void:
	var direction := Vector3(world_direction.x, 0.0, world_direction.z)
	if direction.length_squared() <= 0.000001:
		direction = Vector3.RIGHT
	if _mesh != null and is_instance_valid(_mesh):
		_local_direction = (_mesh.global_basis.inverse() * direction.normalized()).normalized()
	else:
		_local_direction = direction.normalized()
	var strength: float = remap(
		clampf(closing_speed, HARD_IMPACT_SPEED, FULL_IMPACT_SPEED),
		HARD_IMPACT_SPEED, FULL_IMPACT_SPEED, MIN_EXTREME_AMOUNT, MAX_EXTREME_AMOUNT
	)
	_extreme_amount = maxf(_extreme_amount, strength)
	_extreme_velocity = minf(_extreme_velocity, 0.0)
	_extreme_active = true
	_write_uniforms()


func advance(delta: float) -> void:
	var step: float = maxf(delta, 0.0)
	var blend: float = 1.0 - exp(-RESPONSE * step)
	_set_amount(lerpf(_amount, _impulse, blend))
	_impulse = move_toward(_impulse, 0.0, IMPULSE_DECAY * step)
	_advance_extreme(step)
	_write_uniforms()


func reset_deformation() -> void:
	_amount = 0.0
	_impulse = 0.0
	_extreme_amount = 0.0
	_extreme_velocity = 0.0
	_extreme_active = false
	_local_direction = Vector3.RIGHT
	_touching.clear()
	_last_velocity = Vector3.ZERO
	_has_velocity_sample = false
	_world_impact_cooldown = 0.0
	_write_uniforms()


func deformation_amount() -> float:
	return _amount


func deformation_direction() -> Vector3:
	return _local_direction


func deformation_scales() -> Vector3:
	if _extreme_active:
		var extreme_scale: float = clampf(
			1.0 - _extreme_amount * 0.64, EXTREME_AXIS_MIN, EXTREME_AXIS_MAX
		)
		var extreme_radial: float = 1.0 / sqrt(extreme_scale)
		return Vector3(extreme_scale, extreme_radial, extreme_radial)
	var contact_scale: float = maxf(1.0 - _amount, 0.82)
	var radial_scale: float = 1.0 / sqrt(contact_scale)
	return Vector3(contact_scale, radial_scale, radial_scale)


func extreme_amount() -> float:
	return _extreme_amount


func extreme_active() -> bool:
	return _extreme_active


func _set_amount(value: float) -> void:
	_amount = clampf(value, 0.0, MAX_COMPRESSION)


func _advance_extreme(delta: float) -> void:
	if not _extreme_active:
		return
	var remaining: float = minf(delta, 0.25)
	while remaining > 0.000001:
		var step: float = minf(remaining, 1.0 / 120.0)
		var acceleration: float = -EXTREME_SPRING * _extreme_amount \
			- EXTREME_DAMPING * _extreme_velocity
		_extreme_velocity = clampf(
			_extreme_velocity + acceleration * step, -EXTREME_MAX_SPEED, EXTREME_MAX_SPEED
		)
		_extreme_amount = clampf(
			_extreme_amount + _extreme_velocity * step,
			-MAX_EXTREME_REBOUND, MAX_EXTREME_AMOUNT
		)
		remaining -= step
	if absf(_extreme_amount) < 0.002 and absf(_extreme_velocity) < 0.025:
		_extreme_amount = 0.0
		_extreme_velocity = 0.0
		_extreme_active = false


func _update_world_impact(player: CharacterBody3D, delta: float) -> void:
	_world_impact_cooldown = maxf(_world_impact_cooldown - maxf(delta, 0.0), 0.0)
	if not _has_velocity_sample:
		_last_velocity = player.velocity
		_has_velocity_sample = true
		return
	if _world_impact_cooldown <= 0.0:
		for index: int in player.get_slide_collision_count():
			var collision: KinematicCollision3D = player.get_slide_collision(index)
			var normal: Vector3 = collision.get_normal()
			if absf(normal.y) > 0.75:
				continue
			var impact_speed: float = maxf(-_last_velocity.dot(normal), 0.0)
			if impact_speed >= HARD_IMPACT_SPEED:
				trigger_extreme_impact(-normal, impact_speed)
				_world_impact_cooldown = WORLD_IMPACT_COOLDOWN
				break
	_last_velocity = player.velocity


func _write_uniforms() -> void:
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.set_instance_shader_parameter(&"gel_contact_direction", _local_direction)
		var packed_amount: float = _amount
		if _extreme_active:
			packed_amount = EXTREME_PACK_CENTER \
				+ _extreme_amount * EXTREME_PACK_HALF_RANGE
		_mesh.set_instance_shader_parameter(&"gel_contact_compression", packed_amount)
