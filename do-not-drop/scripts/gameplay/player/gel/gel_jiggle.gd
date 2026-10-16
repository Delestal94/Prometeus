class_name GelJiggle
extends Node
## Presentation-only secondary motion for the six soft regions in the gel rig.
##
## The owning player supplies its replicated visual velocity/yaw/grounded state
## through advance_motion(). SpringBoneSimulator3D remains local and never
## changes collision, authority or gameplay state.

const CHAIN_DEFINITIONS: Array[Dictionary] = [
	{&"name": &"head", &"bone": &"jiggle_head", &"stiffness": 0.62, &"drag": 0.36, &"radius": 0.13, &"length": 0.18},
	{&"name": &"belly", &"bone": &"jiggle_belly", &"stiffness": 0.48, &"drag": 0.30, &"radius": 0.12, &"length": 0.20},
	{
		&"name": &"forearm_l", &"bone": &"jiggle_forearm.L", &"stiffness": 0.72,
		&"drag": 0.44, &"radius": 0.055, &"length": 0.13,
	},
	{
		&"name": &"forearm_r", &"bone": &"jiggle_forearm.R", &"stiffness": 0.72,
		&"drag": 0.44, &"radius": 0.055, &"length": 0.13,
	},
	{
		&"name": &"calf_l", &"bone": &"jiggle_calf.L", &"stiffness": 0.78,
		&"drag": 0.50, &"radius": 0.065, &"length": 0.14,
	},
	{
		&"name": &"calf_r", &"bone": &"jiggle_calf.R", &"stiffness": 0.78,
		&"drag": 0.50, &"radius": 0.065, &"length": 0.14,
	},
]

const MOTION_GAIN: float = 0.018
const TURN_GAIN: float = 0.055
const JUMP_IMPULSE: float = 0.075
const LANDING_GAIN: float = 0.018
const IDLE_FORCE: float = 0.0035
const MAX_FORCE: float = 0.34
const IMPULSE_DECAY: float = 2.8
const PHASE_STEP: float = 2.399963229728653

var idle_phase: float = 0.0

var _simulators: Dictionary = {}
var _amplitudes: Dictionary = {}
var _elapsed: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO
var _last_yaw: float = 0.0
var _was_grounded: bool = true
var _has_sample: bool = false
var _impulse: Vector3 = Vector3.ZERO


func _exit_tree() -> void:
	_clear_simulators(true)


func setup(model: Node, proportions: Resource, peer_id: int) -> bool:
	_clear_simulators()
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(model)
	if skeleton == null:
		return false
	for definition: Dictionary in CHAIN_DEFINITIONS:
		var bone_name: StringName = definition[&"bone"]
		if skeleton.find_bone(bone_name) < 0:
			_clear_simulators()
			return false
		var simulator := SpringBoneSimulator3D.new()
		simulator.name = "Spring_%s" % definition[&"name"]
		skeleton.add_child(simulator)
		simulator.setting_count = 1
		simulator.mutable_bone_axes = true
		simulator.set_root_bone_name(0, bone_name)
		simulator.set_end_bone_name(0, bone_name)
		simulator.set_extend_end_bone(0, true)
		simulator.set_end_bone_direction(0, SpringBoneSimulator3D.BONE_DIRECTION_PLUS_Y)
		simulator.set_end_bone_length(0, float(definition[&"length"]))
		simulator.set_rotation_axis(0, SpringBoneSimulator3D.ROTATION_AXIS_ALL)
		simulator.set_stiffness(0, float(definition[&"stiffness"]))
		simulator.set_drag(0, float(definition[&"drag"]))
		simulator.set_gravity(0, 0.0)
		simulator.set_radius(0, float(definition[&"radius"]))
		simulator.set_center_from(0, SpringBoneSimulator3D.CENTER_FROM_WORLD_ORIGIN)
		_simulators[definition[&"name"]] = simulator
	idle_phase = fposmod(float(maxi(peer_id, 1)) * PHASE_STEP, TAU)
	apply_proportions(proportions)
	reset_motion()
	return true


func apply_proportions(proportions: Resource) -> void:
	if proportions == null:
		return
	var head_scale: float = _range_scale(float(proportions.get(&"head_size")), 0.75, 1.25, 0.82, 1.20)
	var belly_scale: float = _range_scale(float(proportions.get(&"belly")), -1.0, 1.0, 0.62, 1.58)
	var arm_scale: float = _range_scale(float(proportions.get(&"arm_thickness")), -1.0, 1.0, 0.82, 1.22)
	var leg_scale: float = _range_scale(float(proportions.get(&"leg_thickness")), -1.0, 1.0, 0.82, 1.20)
	_amplitudes = {
		&"head": head_scale,
		&"belly": belly_scale,
		&"forearm_l": arm_scale,
		&"forearm_r": arm_scale,
		&"calf_l": leg_scale,
		&"calf_r": leg_scale,
	}
	for definition: Dictionary in CHAIN_DEFINITIONS:
		var chain_name: StringName = definition[&"name"]
		var simulator: SpringBoneSimulator3D = _simulators.get(chain_name) as SpringBoneSimulator3D
		if simulator == null:
			continue
		var amplitude: float = float(_amplitudes[chain_name])
		simulator.set_stiffness(0, clampf(float(definition[&"stiffness"]) / sqrt(amplitude), 0.28, 0.92))


func advance_motion(linear_velocity: Vector3, yaw_radians: float, grounded: bool, delta: float) -> void:
	var step: float = maxf(delta, 0.0001)
	_elapsed += step
	var idle := Vector3(
		sin(_elapsed * 1.7 + idle_phase),
		0.35 * sin(_elapsed * 2.3 + idle_phase * 0.71),
		cos(_elapsed * 1.3 + idle_phase * 1.17)
	) * IDLE_FORCE
	if not _has_sample:
		_last_velocity = linear_velocity
		_last_yaw = yaw_radians
		_was_grounded = grounded
		_has_sample = true
		_apply_force(idle)
		return

	var acceleration: Vector3 = (linear_velocity - _last_velocity) / step
	acceleration = acceleration.limit_length(15.0)
	var yaw_rate: float = clampf(wrapf(yaw_radians - _last_yaw, -PI, PI) / step, -7.0, 7.0)
	var right: Vector3 = Basis(Vector3.UP, yaw_radians) * Vector3.RIGHT
	var force: Vector3 = -acceleration * MOTION_GAIN - right * yaw_rate * TURN_GAIN
	if _was_grounded and not grounded and linear_velocity.y > 0.0:
		_impulse += Vector3.DOWN * JUMP_IMPULSE
	elif not _was_grounded and grounded:
		_impulse += Vector3.DOWN * clampf(absf(_last_velocity.y) * LANDING_GAIN, 0.045, 0.16)
	force = (force + _impulse + idle).limit_length(MAX_FORCE)
	_apply_force(force)
	_impulse = _impulse.move_toward(Vector3.ZERO, IMPULSE_DECAY * step)
	_last_velocity = linear_velocity
	_last_yaw = yaw_radians
	_was_grounded = grounded


func reset_motion() -> void:
	_elapsed = 0.0
	_last_velocity = Vector3.ZERO
	_last_yaw = 0.0
	_was_grounded = true
	_has_sample = false
	_impulse = Vector3.ZERO
	for simulator: SpringBoneSimulator3D in _simulators.values():
		simulator.external_force = Vector3.ZERO
		simulator.reset()


## Adds a short secondary-motion kick from a physical contact. Active ragdoll
## uses this for floor hits while the usual acceleration sampling continues.
func add_impulse(impulse: Vector3) -> void:
	if not impulse.is_finite():
		return
	_impulse = (_impulse + impulse).limit_length(MAX_FORCE)


func simulator_count() -> int:
	return _simulators.size()


func simulator_for(chain_name: StringName) -> SpringBoneSimulator3D:
	return _simulators.get(chain_name) as SpringBoneSimulator3D


func amplitude_for(chain_name: StringName) -> float:
	return float(_amplitudes.get(chain_name, 0.0))


func _apply_force(force: Vector3) -> void:
	for chain_name: StringName in _simulators:
		var simulator: SpringBoneSimulator3D = _simulators[chain_name]
		simulator.external_force = force * float(_amplitudes.get(chain_name, 1.0))


func _clear_simulators(deferred: bool = false) -> void:
	for value: Variant in _simulators.values():
		if is_instance_valid(value):
			var simulator := value as SpringBoneSimulator3D
			if deferred:
				simulator.queue_free()
			else:
				simulator.free()
	_simulators.clear()
	_amplitudes.clear()


static func _range_scale(value: float, minimum: float, maximum: float, low: float, high: float) -> float:
	return lerpf(low, high, inverse_lerp(minimum, maximum, clampf(value, minimum, maximum)))
