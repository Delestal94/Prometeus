class_name GelActiveRagdoll
extends PhysicalBoneSimulator3D
## Active physical ragdoll built on the character's real Skeleton3D.
##
## PhysicalBone3D shapes are rebuilt from the current bone rests and gel
## proportions. The skinned mesh therefore remains visible and follows its
## own rig instead of being replaced by detached placeholder capsules. While
## simulated, configurable spring motors pull each body toward the animated
## pose captured at handoff; recovery raises that influence gradually so
## animation regains the rig without a one-frame snap (S-311.48 / S-311.49).

signal finished

const GetUp := preload("res://scripts/gameplay/player/gel/gel_get_up.gd")
const Jiggle := preload("res://scripts/gameplay/player/gel/gel_jiggle.gd")
const ImpactWaves := preload("res://scripts/gameplay/player/gel/gel_impact_waves.gd")
const LIFETIME: float = 2.8
const RECOVERY_DURATION: float = 0.75
const DEFAULT_MOTOR_STRENGTH: float = 0.24
const DENSITY: float = 620.0
const MIN_MASS: float = 0.25
const POSITION_SPRING: float = 38.0
const POSITION_DAMPING: float = 7.5
const ANGULAR_SPRING: float = 28.0
const ANGULAR_DAMPING: float = 5.0
const MAX_LINEAR_ACCELERATION: float = 55.0
const MAX_ANGULAR_ACCELERATION: float = 45.0
const MAX_LINEAR_SPEED: float = 24.0
const MAX_ANGULAR_SPEED: float = 30.0
const MAX_JOINT_STRETCH_RATIO: float = 1.55
const FLOOR_CONTACT_BONES: Array[StringName] = [
	&"pelvis", &"chest", &"head", &"forearm.L", &"forearm.R", &"shin.L", &"shin.R",
]

const BODY_DEFINITIONS: Array[Dictionary] = [
	{&"bone": &"pelvis", &"end": &"chest", &"radius": 0.100, &"role": &"hips",
		&"joint": PhysicalBone3D.JOINT_TYPE_NONE, &"mass_scale": 1.30},
	{&"bone": &"chest", &"end": &"neck", &"radius": 0.105, &"role": &"torso",
		&"joint": PhysicalBone3D.JOINT_TYPE_CONE, &"mass_scale": 1.45},
	{&"bone": &"head", &"end": StringName(), &"radius": 0.120, &"role": &"head",
		&"joint": PhysicalBone3D.JOINT_TYPE_CONE, &"mass_scale": 0.85},
	{&"bone": &"upper_arm.L", &"end": &"forearm.L", &"radius": 0.045, &"role": &"arm",
		&"joint": PhysicalBone3D.JOINT_TYPE_CONE, &"mass_scale": 0.75},
	{&"bone": &"forearm.L", &"end": &"hand.L", &"radius": 0.040, &"role": &"arm",
		&"joint": PhysicalBone3D.JOINT_TYPE_HINGE, &"mass_scale": 0.65},
	{&"bone": &"upper_arm.R", &"end": &"forearm.R", &"radius": 0.045, &"role": &"arm",
		&"joint": PhysicalBone3D.JOINT_TYPE_CONE, &"mass_scale": 0.75},
	{&"bone": &"forearm.R", &"end": &"hand.R", &"radius": 0.040, &"role": &"arm",
		&"joint": PhysicalBone3D.JOINT_TYPE_HINGE, &"mass_scale": 0.65},
	{&"bone": &"thigh.L", &"end": &"shin.L", &"radius": 0.065, &"role": &"leg",
		&"joint": PhysicalBone3D.JOINT_TYPE_CONE, &"mass_scale": 1.05},
	{&"bone": &"shin.L", &"end": &"foot.L", &"radius": 0.055, &"role": &"leg",
		&"joint": PhysicalBone3D.JOINT_TYPE_HINGE, &"mass_scale": 0.90},
	{&"bone": &"thigh.R", &"end": &"shin.R", &"radius": 0.065, &"role": &"leg",
		&"joint": PhysicalBone3D.JOINT_TYPE_CONE, &"mass_scale": 1.05},
	{&"bone": &"shin.R", &"end": &"foot.R", &"radius": 0.055, &"role": &"leg",
		&"joint": PhysicalBone3D.JOINT_TYPE_HINGE, &"mass_scale": 0.90},
]

var collision_mask: int = 1
var _model: Node3D
var _skeleton: Skeleton3D
var _animation: AnimationPlayer
var _animation_was_active: bool = true
var _ragdoll_active: bool = false
var _physical_bones: Dictionary = {}
var _animated_body_poses: Dictionary = {}
var _motor_strength: float = DEFAULT_MOTOR_STRENGTH
var _recovery_elapsed: float = 0.0
var _recovery_duration: float = 0.0
var _recovery_from_strength: float = DEFAULT_MOTOR_STRENGTH
var _recovery_start_poses: Dictionary = {}
var _recovery_world_offset: Vector3 = Vector3.ZERO
var _get_up_clip: StringName = StringName()
var _recovery_anchor_limit: float = -1.0
var _simulation_seed: int = 0
var _jiggle: Node
var _impact_waves: Node
var _floor_contacts: Dictionary = {}
var _previous_body_velocities: Dictionary = {}
var _collision_exception_rid: RID
var _joint_rest_lengths: Dictionary = {}


func _ready() -> void:
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not _ragdoll_active:
		return
	if _recovery_duration > 0.0:
		_recovery_elapsed = minf(_recovery_elapsed + delta, _recovery_duration)
	_stabilize_physical_bodies()
	_apply_pose_motors(delta)
	_limit_joint_stretch()
	_advance_soft_effects(delta)


## Finds the real rig, reparents this simulator below it and builds every
## physical bone. Returns false without changing visibility when the model is
## not a compatible humanoid.
func setup(
	model: Node,
	proportions: GelBodyProportions = null,
	mask: int = 1,
	collision_exception: CollisionObject3D = null
) -> bool:
	_model = model as Node3D
	_skeleton = PlayerAppearance.find_skeleton(model)
	_animation = PlayerAppearance.find_animation_player(model)
	collision_mask = mask
	if _skeleton == null or not _has_required_bones():
		return false
	if get_parent() == null:
		_skeleton.add_child(self)
	elif get_parent() != _skeleton:
		reparent(_skeleton, false)
	active = true
	rebuild(proportions)
	if collision_exception != null:
		_collision_exception_rid = collision_exception.get_rid()
		physical_bones_add_collision_exception(_collision_exception_rid)
	_setup_soft_effects(model, proportions, collision_exception)
	return _physical_bones.size() == BODY_DEFINITIONS.size()


## Recalculates collision dimensions and masses after a proportion change.
## Bone lengths come from the already-shaped Skeleton3D rests; morph-driven
## thickness values expand the corresponding body regions.
func rebuild(proportions: GelBodyProportions = null) -> void:
	if _skeleton == null or _ragdoll_active:
		return
	for value: Variant in _physical_bones.values():
		var physical_bone := value as PhysicalBone3D
		if physical_bone != null:
			remove_child(physical_bone)
			physical_bone.free()
	_physical_bones.clear()
	var values: Dictionary = proportions.as_dictionary() \
		if proportions != null else GelBodyProportions.default_dictionary()
	var rig_height: float = _rig_height()
	for definition: Dictionary in BODY_DEFINITIONS:
		_build_physical_bone(definition, values, rig_height)


## Starts physics without replacing or hiding the mesh. `impulse` behaves as
## a velocity kick at the pelvis, while carried_velocity seeds every body.
func start_ragdoll(
	impulse: Vector3,
	carried_velocity: Vector3 = Vector3.ZERO,
	simulation_seed: int = 0
) -> bool:
	if _ragdoll_active or _physical_bones.is_empty() \
			or not impulse.is_finite() or not carried_velocity.is_finite():
		return false
	_ragdoll_active = true
	if _animation != null:
		_animation_was_active = _animation.active
		_animation.active = false
	physical_bones_start_simulation()
	_capture_animated_body_poses()
	_capture_joint_rest_lengths()
	_recovery_elapsed = 0.0
	_recovery_duration = 0.0
	_floor_contacts.clear()
	_previous_body_velocities.clear()
	_simulation_seed = simulation_seed
	set_physics_process(true)
	var random := RandomNumberGenerator.new()
	random.seed = simulation_seed
	for value: Variant in _physical_bones.values():
		var physical_bone := value as PhysicalBone3D
		var jitter := Vector3(
			random.randf_range(-0.04, 0.04),
			random.randf_range(-0.02, 0.04),
			random.randf_range(-0.04, 0.04)
		)
		physical_bone.linear_velocity = carried_velocity.limit_length(MAX_LINEAR_SPEED) + jitter
		physical_bone.angular_velocity = Vector3(
			random.randf_range(-0.16, 0.16),
			random.randf_range(-0.16, 0.16),
			random.randf_range(-0.16, 0.16)
		)
	var pelvis := _physical_bones.get(&"pelvis") as PhysicalBone3D
	if pelvis != null:
		pelvis.apply_central_impulse(impulse.limit_length(MAX_LINEAR_SPEED) * pelvis.mass)
	return true


## Stops physics and hands the rig back to its AnimationPlayer.
func stop_ragdoll() -> void:
	if not _ragdoll_active:
		return
	for value: Variant in _physical_bones.values():
		var physical_bone := value as PhysicalBone3D
		if physical_bone != null:
			physical_bone.linear_velocity = Vector3.ZERO
			physical_bone.angular_velocity = Vector3.ZERO
	physical_bones_stop_simulation()
	_commit_recovery_anchor()
	_ragdoll_active = false
	set_physics_process(false)
	_recovery_elapsed = 0.0
	_recovery_duration = 0.0
	_recovery_start_poses.clear()
	_recovery_world_offset = Vector3.ZERO
	if _animation != null:
		_animation.active = _animation_was_active


## Gameplay convenience matching the old 2.8-second knockdown contract.
func fall(
	impulse: Vector3,
	carried_velocity: Vector3 = Vector3.ZERO,
	simulation_seed: int = 0
) -> void:
	if not start_ragdoll(impulse, carried_velocity, simulation_seed):
		return
	await get_tree().create_timer(LIFETIME - RECOVERY_DURATION).timeout
	begin_recovery(RECOVERY_DURATION)
	await get_tree().create_timer(RECOVERY_DURATION).timeout
	stop_ragdoll()
	finished.emit()
	queue_free()


func physical_bone(bone_name: StringName) -> PhysicalBone3D:
	return _physical_bones.get(bone_name) as PhysicalBone3D


## Sets how much the animated pose resists impacts: zero is fully loose,
## while one uses the full active-ragdoll springs.
func set_motor_strength(strength: float) -> void:
	_motor_strength = clampf(strength, 0.0, 1.0)
	if _recovery_duration <= 0.0:
		_recovery_from_strength = _motor_strength


func motor_strength() -> float:
	return _effective_motor_strength()


## Applies an additional hit without restarting the fall, so repeated cargo
## impacts can shove or trip an already-simulating character.
func push(bone_name: StringName, impulse: Vector3) -> bool:
	if not _ragdoll_active or not impulse.is_finite():
		return false
	var body := physical_bone(bone_name)
	if body == null:
		return false
	body.linear_velocity += impulse
	return true


## Raises motor authority smoothly. The physics bodies remain dynamic for the
## whole blend and approach the animation target before simulation stops.
func begin_recovery(duration: float = RECOVERY_DURATION) -> void:
	if not _ragdoll_active:
		return
	_recovery_start_poses.clear()
	for bone_name: StringName in _physical_bones:
		var body := physical_bone(bone_name)
		if body != null:
			_recovery_start_poses[bone_name] = body.global_transform
	var chest := physical_bone(&"chest")
	_get_up_clip = GetUp.select_clip(chest.global_basis) if chest != null else GetUp.FACE_UP
	var pelvis := physical_bone(&"pelvis")
	if pelvis != null:
		var standing_pelvis: Transform3D = _base_target_global_transform(&"pelvis")
		_recovery_world_offset = pelvis.global_position - standing_pelvis.origin
		_recovery_world_offset.y = 0.0
		if _recovery_anchor_limit >= 0.0:
			_recovery_world_offset = _recovery_world_offset.limit_length(_recovery_anchor_limit)
	_recovery_from_strength = _effective_motor_strength()
	_recovery_duration = maxf(duration, 0.001)
	_recovery_elapsed = 0.0


func recovery_progress() -> float:
	if _recovery_duration <= 0.0:
		return 0.0
	return clampf(_recovery_elapsed / _recovery_duration, 0.0, 1.0)


func get_up_clip() -> StringName:
	return _get_up_clip


func recovery_world_offset() -> Vector3:
	return _recovery_world_offset


func set_recovery_anchor_limit(maximum_distance: float) -> void:
	_recovery_anchor_limit = maxf(maximum_distance, 0.0)


func simulation_seed() -> int:
	return _simulation_seed


func jiggle_controller() -> Node:
	return _jiggle


func impact_wave_controller() -> Node:
	return _impact_waves


## Shared entry point for detected contacts and deterministic gameplay/tests.
func report_floor_contact(world_position: Vector3, strength: float) -> void:
	if not _ragdoll_active or not world_position.is_finite():
		return
	var amount: float = clampf(strength, 0.0, 1.0)
	if amount <= 0.0:
		return
	if _impact_waves != null:
		_impact_waves.add_impact(world_position, amount)
	if _jiggle != null:
		_jiggle.add_impulse(Vector3.DOWN * lerpf(0.08, 0.28, amount))


## Maximum distance between a physical body and its captured animated pose.
func pose_error() -> float:
	var result: float = 0.0
	for bone_name: StringName in _physical_bones:
		var body := physical_bone(bone_name)
		var target: Transform3D = _target_global_transform(bone_name)
		if body != null:
			result = maxf(result, body.global_position.distance_to(target.origin))
	return result


## Snapshot used by the stability gate without exposing solver internals.
func stability_state() -> Dictionary:
	return {
		&"finite": _bodies_are_finite(),
		&"settled": not _ragdoll_active and not is_simulating_physics(),
		&"stretch_ratio": _maximum_joint_stretch_ratio(),
	}


func _bodies_are_finite() -> bool:
	for value: Variant in _physical_bones.values():
		var body := value as PhysicalBone3D
		if body == null or not body.global_transform.is_finite() \
				or not body.linear_velocity.is_finite() or not body.angular_velocity.is_finite():
			return false
	return true


## Largest centre-to-centre separation relative to the distance captured at
## simulation handoff. The cap leaves room for capsules rotating around their
## joint anchors while catching a solver explosion before a limb visibly tears.
func _maximum_joint_stretch_ratio() -> float:
	var maximum: float = 1.0
	for child_name: StringName in _joint_rest_lengths:
		var joint: Dictionary = _joint_rest_lengths[child_name]
		var child := physical_bone(child_name)
		var parent := physical_bone(joint[&"parent"])
		if child == null or parent == null:
			continue
		var rest_length: float = float(joint[&"length"])
		maximum = maxf(maximum, child.global_position.distance_to(parent.global_position) / rest_length)
	return maximum


func _capture_animated_body_poses() -> void:
	_animated_body_poses.clear()
	var to_skeleton: Transform3D = _skeleton.global_transform.affine_inverse()
	for bone_name: StringName in _physical_bones:
		var body := physical_bone(bone_name)
		if body != null:
			_animated_body_poses[bone_name] = to_skeleton * body.global_transform


func _capture_joint_rest_lengths() -> void:
	_joint_rest_lengths.clear()
	for child_name: StringName in _physical_bones:
		var parent_name: StringName = _physical_parent_name(child_name)
		if parent_name.is_empty():
			continue
		var child := physical_bone(child_name)
		var parent := physical_bone(parent_name)
		if child == null or parent == null:
			continue
		_joint_rest_lengths[child_name] = {
			&"parent": parent_name,
			&"length": maxf(child.global_position.distance_to(parent.global_position), 0.001),
		}


func _physical_parent_name(bone_name: StringName) -> StringName:
	var bone_index: int = _skeleton.find_bone(bone_name)
	var parent_index: int = _skeleton.get_bone_parent(bone_index) if bone_index >= 0 else -1
	while parent_index >= 0:
		var parent_name: StringName = _skeleton.get_bone_name(parent_index)
		if _physical_bones.has(parent_name):
			return parent_name
		parent_index = _skeleton.get_bone_parent(parent_index)
	return StringName()


func _stabilize_physical_bodies() -> void:
	for bone_name: StringName in _physical_bones:
		var body := physical_bone(bone_name)
		if body == null:
			continue
		if not body.global_transform.is_finite() or not body.linear_velocity.is_finite() \
				or not body.angular_velocity.is_finite():
			body.global_transform = _target_global_transform(bone_name)
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			continue
		body.linear_velocity = body.linear_velocity.limit_length(MAX_LINEAR_SPEED)
		body.angular_velocity = body.angular_velocity.limit_length(MAX_ANGULAR_SPEED)


func _limit_joint_stretch() -> void:
	for child_name: StringName in _joint_rest_lengths:
		var joint: Dictionary = _joint_rest_lengths[child_name]
		var child := physical_bone(child_name)
		var parent := physical_bone(joint[&"parent"])
		if child == null or parent == null:
			continue
		var offset: Vector3 = child.global_position - parent.global_position
		var maximum: float = float(joint[&"length"]) * MAX_JOINT_STRETCH_RATIO
		if offset.length_squared() <= maximum * maximum:
			continue
		var direction: Vector3 = offset.normalized()
		child.global_position = parent.global_position + direction * maximum
		var outward_speed: float = child.linear_velocity.dot(direction)
		if outward_speed > 0.0:
			child.linear_velocity -= direction * outward_speed


func _setup_soft_effects(model: Node, proportions: Resource, collision_exception: CollisionObject3D) -> void:
	var jiggle: Node = Jiggle.new()
	add_child(jiggle)
	var peer_id: int = collision_exception.get_multiplayer_authority() \
		if collision_exception != null else 1
	if not jiggle.setup(model, proportions, peer_id):
		jiggle.queue_free()
		return
	_jiggle = jiggle
	_impact_waves = ImpactWaves.new()
	add_child(_impact_waves)
	if not _impact_waves.setup(model):
		_impact_waves.queue_free()
		_impact_waves = null


func _advance_soft_effects(delta: float) -> void:
	var pelvis := physical_bone(&"pelvis")
	if _jiggle != null and pelvis != null:
		_jiggle.advance_motion(pelvis.linear_velocity, pelvis.global_rotation.y, false, delta)
	if _impact_waves != null:
		_impact_waves.advance(delta)
	_detect_floor_contacts()


func _detect_floor_contacts() -> void:
	if _impact_waves == null or get_world_3d() == null:
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for bone_name: StringName in FLOOR_CONTACT_BONES:
		var body := physical_bone(bone_name)
		if body == null:
			continue
		var shape := body.get_node_or_null(^"Shape") as CollisionShape3D
		var capsule := shape.shape as CapsuleShape3D if shape != null else null
		var reach: float = capsule.radius + 0.08 if capsule != null else 0.16
		var exclude: Array[RID] = [body.get_rid()]
		if _collision_exception_rid.is_valid():
			exclude.append(_collision_exception_rid)
		var query := PhysicsRayQueryParameters3D.create(
			body.global_position, body.global_position + Vector3.DOWN * reach,
			collision_mask, exclude
		)
		query.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(query)
		var touching: bool = not hit.is_empty()
		var was_touching: bool = bool(_floor_contacts.get(bone_name, false))
		var previous_velocity: Vector3 = _previous_body_velocities.get(
			bone_name, body.linear_velocity
		)
		if touching and not was_touching:
			var impact_speed: float = maxf(-previous_velocity.y, 0.0)
			if impact_speed >= 0.35:
				var contact: Vector3 = hit.get(&"position", body.global_position)
				report_floor_contact(contact, clampf(impact_speed / 8.0, 0.18, 1.0))
		_floor_contacts[bone_name] = touching
		_previous_body_velocities[bone_name] = body.linear_velocity


func _apply_pose_motors(delta: float) -> void:
	var strength: float = _effective_motor_strength()
	if strength <= 0.0:
		return
	var recovery_gain: float = lerpf(1.0, 4.5, recovery_progress())
	for bone_name: StringName in _physical_bones:
		var body := physical_bone(bone_name)
		if body == null:
			continue
		var target: Transform3D = _target_global_transform(bone_name)
		_apply_position_motor(body, target.origin, strength, recovery_gain, delta)
		_apply_rotation_motor(body, target.basis, strength, recovery_gain, delta)


func _apply_position_motor(
	body: PhysicalBone3D,
	target: Vector3,
	strength: float,
	recovery_gain: float,
	delta: float
) -> void:
	var acceleration: Vector3 = (target - body.global_position) \
		* POSITION_SPRING * strength * recovery_gain
	acceleration -= body.linear_velocity * POSITION_DAMPING * sqrt(strength) * recovery_gain
	body.linear_velocity += acceleration.limit_length(MAX_LINEAR_ACCELERATION) * delta


func _apply_rotation_motor(
	body: PhysicalBone3D,
	target: Basis,
	strength: float,
	recovery_gain: float,
	delta: float
) -> void:
	var current_rotation: Quaternion = body.global_basis.orthonormalized().get_rotation_quaternion()
	var target_rotation: Quaternion = target.orthonormalized().get_rotation_quaternion()
	var rotation_delta: Quaternion = current_rotation.inverse() * target_rotation
	if rotation_delta.w < 0.0:
		rotation_delta = -rotation_delta
	var angle: float = rotation_delta.get_angle()
	if angle <= 0.0001:
		return
	var world_axis: Vector3 = current_rotation * rotation_delta.get_axis()
	var acceleration: Vector3 = world_axis * angle * ANGULAR_SPRING * strength * recovery_gain
	acceleration -= body.angular_velocity * ANGULAR_DAMPING * sqrt(strength) * recovery_gain
	body.angular_velocity += acceleration.limit_length(MAX_ANGULAR_ACCELERATION) * delta


func _effective_motor_strength() -> float:
	var progress: float = recovery_progress()
	if progress <= 0.0:
		return _motor_strength
	var eased: float = smoothstep(0.0, 1.0, progress)
	return lerpf(_recovery_from_strength, 1.0, eased)


func _target_global_transform(bone_name: StringName) -> Transform3D:
	var target: Transform3D = _base_target_global_transform(bone_name)
	target.origin += _recovery_world_offset
	if _recovery_duration > 0.0 and _recovery_start_poses.has(bone_name):
		var physical_pose: Transform3D = _recovery_start_poses[bone_name]
		return GetUp.blend_pose(
			_get_up_clip, bone_name, physical_pose, target, recovery_progress()
		)
	return target


func _base_target_global_transform(bone_name: StringName) -> Transform3D:
	var local_target: Transform3D = _animated_body_poses.get(bone_name, Transform3D.IDENTITY)
	return _skeleton.global_transform * local_target


func _commit_recovery_anchor() -> void:
	if _model == null or _recovery_duration <= 0.0:
		return
	_model.global_position += _recovery_world_offset


func _has_required_bones() -> bool:
	for definition: Dictionary in BODY_DEFINITIONS:
		if _skeleton.find_bone(definition[&"bone"]) < 0:
			return false
		var end_name: StringName = definition[&"end"]
		if not end_name.is_empty() and _skeleton.find_bone(end_name) < 0:
			return false
	return true


func _rig_height() -> float:
	var head: int = _skeleton.find_bone(&"head")
	var pelvis: int = _skeleton.find_bone(&"pelvis")
	var highest: float = _skeleton.get_bone_global_rest(head).origin.y
	var lowest: float = 0.0
	for foot_name: StringName in [&"foot.L", &"foot.R"]:
		var foot: int = _skeleton.find_bone(foot_name)
		if foot >= 0:
			lowest = minf(lowest, _skeleton.get_bone_global_rest(foot).origin.y)
	if pelvis >= 0:
		highest = maxf(highest, _skeleton.get_bone_global_rest(pelvis).origin.y)
	var height_axis := Vector3.UP * (highest - lowest)
	return maxf((_skeleton.global_basis * height_axis).length(), 0.5)


func _build_physical_bone(definition: Dictionary, values: Dictionary, rig_height: float) -> void:
	var bone_name: StringName = definition[&"bone"]
	var bone_index: int = _skeleton.find_bone(bone_name)
	var end_name: StringName = definition[&"end"]
	var role: StringName = definition[&"role"]
	var radius: float = rig_height * float(definition[&"radius"]) * _thickness_factor(role, values)
	var body_offset := Transform3D.IDENTITY
	var capsule_height: float = radius * 2.0
	if not end_name.is_empty():
		var bone_rest: Transform3D = _skeleton.get_bone_global_rest(bone_index)
		var end_rest: Transform3D = _skeleton.get_bone_global_rest(_skeleton.find_bone(end_name))
		var local_end: Vector3 = bone_rest.affine_inverse() * end_rest.origin
		var segment_length: float = (
			_skeleton.global_basis * (end_rest.origin - bone_rest.origin)
		).length()
		if segment_length > 0.001:
			body_offset.basis = Basis(Quaternion(Vector3.UP, local_end.normalized()))
			body_offset.origin = local_end * 0.5
			capsule_height = maxf(segment_length * 0.92, radius * 2.0)

	var physical_bone := PhysicalBone3D.new()
	physical_bone.name = "PhysicalBone_%s" % String(bone_name).replace(".", "_")
	physical_bone.set(&"bone_name", bone_name)
	physical_bone.body_offset = body_offset
	physical_bone.collision_layer = 0
	physical_bone.collision_mask = collision_mask
	physical_bone.friction = 0.85
	physical_bone.bounce = 0.05
	physical_bone.linear_damp = 0.15
	physical_bone.angular_damp = 0.35
	physical_bone.joint_type = int(definition[&"joint"]) as PhysicalBone3D.JointType
	_configure_joint(physical_bone, role)

	var collision := CollisionShape3D.new()
	collision.name = "Shape"
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = capsule_height
	collision.shape = capsule
	physical_bone.add_child(collision)
	physical_bone.mass = maxf(
		MIN_MASS,
		_capsule_volume(radius, capsule_height) * DENSITY * float(definition[&"mass_scale"])
	)
	add_child(physical_bone)
	_physical_bones[bone_name] = physical_bone


func _configure_joint(physical_bone: PhysicalBone3D, role: StringName) -> void:
	match physical_bone.joint_type:
		PhysicalBone3D.JOINT_TYPE_CONE:
			var swing_degrees: float = 58.0 if role in [&"arm", &"leg"] else 32.0
			var twist_degrees: float = 38.0 if role == &"arm" else 24.0
			physical_bone.set(&"joint_constraints/swing_span", deg_to_rad(swing_degrees))
			physical_bone.set(&"joint_constraints/twist_span", deg_to_rad(twist_degrees))
		PhysicalBone3D.JOINT_TYPE_HINGE:
			physical_bone.set(&"joint_constraints/angular_limit_enabled", true)
			physical_bone.set(&"joint_constraints/angular_limit_lower", deg_to_rad(-8.0))
			physical_bone.set(&"joint_constraints/angular_limit_upper", deg_to_rad(132.0))


func _thickness_factor(role: StringName, values: Dictionary) -> float:
	var factor: float = 1.0 + float(values[&"general_thickness"]) * 0.16
	match role:
		&"hips":
			factor *= 1.0 + float(values[&"hips"]) * 0.13
		&"torso":
			factor *= 1.0 + (float(values[&"belly"]) + float(values[&"chest"])) * 0.07
		&"head":
			factor *= float(values[&"head_size"]) * (1.0 + float(values[&"head_shape"]) * 0.06)
		&"arm":
			factor *= 1.0 + float(values[&"arm_thickness"]) * 0.18
		&"leg":
			factor *= 1.0 + float(values[&"leg_thickness"]) * 0.18
	return maxf(factor, 0.55)


func _capsule_volume(radius: float, height: float) -> float:
	var cylinder_height: float = maxf(height - radius * 2.0, 0.0)
	return PI * radius * radius * cylinder_height + 4.0 * PI * radius * radius * radius / 3.0
