extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_active_ragdoll.gd

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const Ragdoll := preload("res://scripts/gameplay/player/gel/gel_active_ragdoll.gd")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Shaper := preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = GEL_SCENE.instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(model)
	var shaper: GelBodyShaper = Shaper.new()
	var proportions: GelBodyProportions = Proportions.new()
	_expect(skeleton != null and shaper.setup(model), "the real gel rig is available")
	if skeleton == null:
		model.free()
		quit(_failures)
		return

	var ragdoll: GelActiveRagdoll = Ragdoll.new()
	model.add_child(ragdoll)
	_expect(ragdoll.setup(model, proportions, 1 | 64), "the physical ragdoll builds on the real rig")
	await process_frame
	_expect(ragdoll.get_parent() == skeleton, "PhysicalBoneSimulator3D is a child of Skeleton3D")
	_expect(ragdoll.get_child_count() == 11, "the rig uses eleven articulated physical bones")
	_check_joint(ragdoll, &"upper_arm.L", PhysicalBone3D.JOINT_TYPE_CONE)
	_check_joint(ragdoll, &"upper_arm.R", PhysicalBone3D.JOINT_TYPE_CONE)
	_check_joint(ragdoll, &"thigh.L", PhysicalBone3D.JOINT_TYPE_CONE)
	_check_joint(ragdoll, &"thigh.R", PhysicalBone3D.JOINT_TYPE_CONE)
	_check_joint(ragdoll, &"forearm.L", PhysicalBone3D.JOINT_TYPE_HINGE)
	_check_joint(ragdoll, &"forearm.R", PhysicalBone3D.JOINT_TYPE_HINGE)
	_check_joint(ragdoll, &"shin.L", PhysicalBone3D.JOINT_TYPE_HINGE)
	_check_joint(ragdoll, &"shin.R", PhysicalBone3D.JOINT_TYPE_HINGE)

	var neutral_arm: PhysicalBone3D = ragdoll.physical_bone(&"upper_arm.L")
	var neutral_shape := neutral_arm.get_node(^"Shape") as CollisionShape3D
	var neutral_radius: float = (neutral_shape.shape as CapsuleShape3D).radius
	var neutral_mass: float = neutral_arm.mass
	proportions.total_height = 1.20
	proportions.arm_length = 1.25
	proportions.general_thickness = 1.0
	proportions.arm_thickness = 1.0
	shaper.apply(proportions)
	ragdoll.rebuild(proportions)
	await process_frame
	var thick_arm: PhysicalBone3D = ragdoll.physical_bone(&"upper_arm.L")
	var thick_shape := thick_arm.get_node(^"Shape") as CollisionShape3D
	_expect((thick_shape.shape as CapsuleShape3D).radius > neutral_radius,
		"arm collision radius follows thickness proportions")
	_expect(thick_arm.mass > neutral_mass, "arm mass follows recalculated volume")

	_expect(ragdoll.start_ragdoll(Vector3(1.5, 2.0, -0.5)), "ragdoll simulation starts once")
	await physics_frame
	await physics_frame
	_expect(model.visible, "the real skinned model remains visible during ragdoll")
	_expect(ragdoll.is_simulating_physics(), "PhysicalBoneSimulator3D drives the rig")
	var moving: bool = false
	for child: Node in ragdoll.get_children():
		var physical_bone := child as PhysicalBone3D
		_expect(physical_bone != null and physical_bone.get_bone_id() >= 0,
			"every physical body is bound to a real skeleton bone")
		_expect(physical_bone != null and physical_bone.global_transform.is_finite(),
			"physical bone transforms stay finite")
		if physical_bone != null and physical_bone.linear_velocity.length() > 0.01:
			moving = true
	_expect(moving, "the impact moves the articulated physical rig")
	ragdoll.stop_ragdoll()
	_expect(not ragdoll.is_simulating_physics(), "simulation returns control to animation")

	model.free()
	await _check_player_integration()
	if _failures == 0:
		print("PASS: real-rig ragdoll joints, proportions, masses and simulation")
	quit(_failures)


func _check_joint(ragdoll: GelActiveRagdoll, bone_name: StringName, expected_type: int) -> void:
	var physical_bone: PhysicalBone3D = ragdoll.physical_bone(bone_name)
	_expect(physical_bone != null and physical_bone.joint_type == expected_type,
		"%s uses the requested joint type" % bone_name)
	if physical_bone == null:
		return
	if expected_type == PhysicalBone3D.JOINT_TYPE_CONE:
		_expect(float(physical_bone.get(&"joint_constraints/swing_span")) > 0.0,
			"%s has a finite cone limit" % bone_name)
	elif expected_type == PhysicalBone3D.JOINT_TYPE_HINGE:
		_expect(bool(physical_bone.get(&"joint_constraints/angular_limit_enabled")),
			"%s has its hinge limits enabled" % bone_name)


func _check_player_integration() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	await process_frame
	player.call(&"_activate_ragdoll", Vector3(1.0, 2.0, 0.0))
	await physics_frame
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(player.get_node(^"BodyVisual"))
	var live_ragdoll: GelActiveRagdoll
	if skeleton != null:
		for child: Node in skeleton.get_children():
			if child is GelActiveRagdoll:
				live_ragdoll = child
				break
	_expect(live_ragdoll != null and live_ragdoll.is_simulating_physics(),
		"package knockdown uses the real-rig simulator instead of detached capsules")
	_expect(player.visible, "the player stays visible while its skeleton ragdolls")
	await create_timer(GelActiveRagdoll.LIFETIME + 0.1).timeout
	await process_frame
	_expect(not bool(player.get(&"_ragdolled")), "the gameplay knockdown completes cleanly")
	player.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
