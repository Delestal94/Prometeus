class_name GelHairSprings
extends Node
## Presentation-only spring-bone rig for locks, pigtails and braids (S-311.63).
## Each tagged mesh is rebound to a native Skeleton3D bone at its authored position.

const STIFFNESS: float = 0.68
const DRAG: float = 0.42
const RADIUS: float = 0.045
const END_LENGTH: float = 0.07
const MOTION_GAIN: float = 0.014
const TURN_GAIN: float = 0.045
const MAX_FORCE: float = 0.28

var _skeleton: Skeleton3D
var _simulators: Dictionary = {}
var _last_velocity: Vector3 = Vector3.ZERO
var _last_yaw: float = 0.0
var _has_sample: bool = false


func setup(hair: Node3D) -> bool:
	_clear_rig()
	var chains: Dictionary = _collect_chains(hair)
	if chains.is_empty():
		return false
	_skeleton = Skeleton3D.new()
	_skeleton.name = "GelHairSkeleton"
	hair.add_child(_skeleton)
	for chain_name: StringName in chains:
		_build_chain(chain_name, chains[chain_name] as Array)
	_skeleton.force_update_all_bone_transforms()
	reset_motion()
	return not _simulators.is_empty()


func advance_motion(linear_velocity: Vector3, yaw_radians: float, delta: float) -> void:
	var step: float = maxf(delta, 0.0001)
	if not _has_sample:
		_last_velocity = linear_velocity
		_last_yaw = yaw_radians
		_has_sample = true
		_apply_force(Vector3.ZERO)
		return
	var acceleration: Vector3 = ((linear_velocity - _last_velocity) / step).limit_length(15.0)
	var yaw_rate: float = clampf(wrapf(yaw_radians - _last_yaw, -PI, PI) / step, -7.0, 7.0)
	var right: Vector3 = Basis(Vector3.UP, yaw_radians) * Vector3.RIGHT
	_apply_force((-acceleration * MOTION_GAIN - right * yaw_rate * TURN_GAIN).limit_length(MAX_FORCE))
	_last_velocity = linear_velocity
	_last_yaw = yaw_radians


func reset_motion() -> void:
	_last_velocity = Vector3.ZERO
	_last_yaw = 0.0
	_has_sample = false
	for simulator: SpringBoneSimulator3D in _simulators.values():
		simulator.external_force = Vector3.ZERO
		simulator.reset()


func simulator_count() -> int:
	return _simulators.size()


func simulator_for(chain_name: StringName) -> SpringBoneSimulator3D:
	return _simulators.get(chain_name) as SpringBoneSimulator3D


func skeleton() -> Skeleton3D:
	return _skeleton


func _build_chain(chain_name: StringName, pieces: Array) -> void:
	pieces.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return int(a.get_meta(&"gel_spring_index")) < int(b.get_meta(&"gel_spring_index")))
	var parent: int = -1
	var previous_position: Vector3 = Vector3.ZERO
	var first_bone: StringName
	var last_bone: StringName
	for index: int in pieces.size():
		var piece := pieces[index] as MeshInstance3D
		var authored: Transform3D = piece.transform
		var bone_name := StringName("hair_%s_%d" % [chain_name, index])
		var bone: int = _skeleton.get_bone_count()
		_skeleton.add_bone(bone_name)
		_skeleton.set_bone_parent(bone, parent)
		var origin: Vector3 = authored.origin if parent < 0 else authored.origin - previous_position
		_skeleton.set_bone_rest(bone, Transform3D(Basis.IDENTITY, origin))
		var attachment := BoneAttachment3D.new()
		attachment.name = "Attach_%s" % bone_name
		attachment.bone_name = bone_name
		_skeleton.add_child(attachment)
		piece.reparent(attachment, false)
		piece.transform = Transform3D(authored.basis, Vector3.ZERO)
		first_bone = bone_name if index == 0 else first_bone
		last_bone = bone_name
		parent = bone
		previous_position = authored.origin
	var simulator := SpringBoneSimulator3D.new()
	simulator.name = "Spring_%s" % chain_name
	_skeleton.add_child(simulator)
	simulator.setting_count = 1
	simulator.mutable_bone_axes = true
	simulator.set_root_bone_name(0, first_bone)
	simulator.set_end_bone_name(0, last_bone)
	simulator.set_extend_end_bone(0, true)
	simulator.set_end_bone_direction(0, SpringBoneSimulator3D.BONE_DIRECTION_MINUS_Y)
	simulator.set_end_bone_length(0, END_LENGTH)
	simulator.set_rotation_axis(0, SpringBoneSimulator3D.ROTATION_AXIS_ALL)
	simulator.set_stiffness(0, STIFFNESS)
	simulator.set_drag(0, DRAG)
	simulator.set_gravity(0, 0.0)
	simulator.set_radius(0, RADIUS)
	simulator.set_center_from(0, SpringBoneSimulator3D.CENTER_FROM_WORLD_ORIGIN)
	_simulators[chain_name] = simulator


func _collect_chains(hair: Node) -> Dictionary:
	var chains: Dictionary = {}
	for child: Node in hair.get_children():
		if child is MeshInstance3D and child.has_meta(&"gel_spring_chain"):
			var chain_name: StringName = child.get_meta(&"gel_spring_chain")
			if not chains.has(chain_name):
				chains[chain_name] = []
			(chains[chain_name] as Array).append(child)
	return chains


func _apply_force(force: Vector3) -> void:
	for simulator: SpringBoneSimulator3D in _simulators.values():
		simulator.external_force = force


func _clear_rig() -> void:
	_simulators.clear()
	if is_instance_valid(_skeleton):
		_skeleton.free()
	_skeleton = null
