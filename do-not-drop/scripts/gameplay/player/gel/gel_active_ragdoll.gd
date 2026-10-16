class_name GelActiveRagdoll
extends PhysicalBoneSimulator3D
## Physical ragdoll built on the character's real Skeleton3D (S-311.48).
##
## PhysicalBone3D shapes are rebuilt from the current bone rests and gel
## proportions. The skinned mesh therefore remains visible and follows its
## own rig instead of being replaced by detached placeholder capsules.

signal finished

const LIFETIME: float = 2.8
const DENSITY: float = 620.0
const MIN_MASS: float = 0.25

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
var _skeleton: Skeleton3D
var _animation: AnimationPlayer
var _animation_was_active: bool = true
var _ragdoll_active: bool = false
var _physical_bones: Dictionary = {}


## Finds the real rig, reparents this simulator below it and builds every
## physical bone. Returns false without changing visibility when the model is
## not a compatible humanoid.
func setup(
	model: Node,
	proportions: GelBodyProportions = null,
	mask: int = 1,
	collision_exception: CollisionObject3D = null
) -> bool:
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
		physical_bones_add_collision_exception(collision_exception.get_rid())
	return _physical_bones.size() == BODY_DEFINITIONS.size()


## Recalculates collision dimensions and masses after a proportion change.
## Bone lengths come from the already-shaped Skeleton3D rests; morph-driven
## thickness values expand the corresponding body regions.
func rebuild(proportions: GelBodyProportions = null) -> void:
	if _skeleton == null or _ragdoll_active:
		return
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_physical_bones.clear()
	var values: Dictionary = proportions.as_dictionary() \
		if proportions != null else GelBodyProportions.default_dictionary()
	var rig_height: float = _rig_height()
	for definition: Dictionary in BODY_DEFINITIONS:
		_build_physical_bone(definition, values, rig_height)


## Starts physics without replacing or hiding the mesh. `impulse` behaves as
## a velocity kick at the pelvis, while carried_velocity seeds every body.
func start_ragdoll(impulse: Vector3, carried_velocity: Vector3 = Vector3.ZERO) -> bool:
	if _ragdoll_active or _physical_bones.is_empty():
		return false
	_ragdoll_active = true
	if _animation != null:
		_animation_was_active = _animation.active
		_animation.active = false
	physical_bones_start_simulation()
	for value: Variant in _physical_bones.values():
		var physical_bone := value as PhysicalBone3D
		physical_bone.linear_velocity = carried_velocity
	var pelvis := _physical_bones.get(&"pelvis") as PhysicalBone3D
	if pelvis != null:
		pelvis.apply_central_impulse(impulse * pelvis.mass)
	return true


## Stops physics and hands the rig back to its AnimationPlayer.
func stop_ragdoll() -> void:
	if not _ragdoll_active:
		return
	physical_bones_stop_simulation()
	_ragdoll_active = false
	if _animation != null:
		_animation.active = _animation_was_active


## Gameplay convenience matching the old 2.8-second knockdown contract.
func fall(impulse: Vector3, carried_velocity: Vector3 = Vector3.ZERO) -> void:
	if not start_ragdoll(impulse, carried_velocity):
		return
	await get_tree().create_timer(LIFETIME).timeout
	stop_ragdoll()
	finished.emit()
	queue_free()


func physical_bone(bone_name: StringName) -> PhysicalBone3D:
	return _physical_bones.get(bone_name) as PhysicalBone3D


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
