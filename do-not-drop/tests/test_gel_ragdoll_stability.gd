extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_ragdoll_stability.gd
## S-311.54: 100 deterministic randomized poses, impulses and proportions
## remain finite, respect the joint-stretch cap and settle in under four seconds.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const Ragdoll := preload("res://scripts/gameplay/player/gel/gel_active_ragdoll.gd")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Shaper := preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")
const CASE_COUNT: int = 100
const SETTLE_LIMIT_SECONDS: float = 4.0
const POSE_BONES: Array[StringName] = [
	&"chest", &"head", &"upper_arm.L", &"upper_arm.R",
	&"thigh.L", &"thigh.R", &"forearm.L", &"forearm.R",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = GEL_SCENE.instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(model)
	var shaper: GelBodyShaper = Shaper.new()
	var proportions: GelBodyProportions = Proportions.new()
	var ragdoll: GelActiveRagdoll = Ragdoll.new()
	model.add_child(ragdoll)
	_expect(skeleton != null and shaper.setup(model) and ragdoll.setup(model, proportions, 1),
		"the randomized stability rig is available")
	if skeleton == null:
		quit(_failures)
		return

	var random := RandomNumberGenerator.new()
	random.seed = 31154
	var worst_stretch: float = 1.0
	for case_index: int in CASE_COUNT:
		_randomize_proportions(proportions, random)
		shaper.apply(proportions)
		_randomize_pose(skeleton, random)
		ragdoll.rebuild(proportions)
		var impulse := Vector3(
			random.randf_range(-14.0, 14.0),
			random.randf_range(-4.0, 16.0),
			random.randf_range(-14.0, 14.0)
		)
		_expect(ragdoll.start_ragdoll(impulse, Vector3.ZERO, 3115400 + case_index),
			"randomized fall %d starts" % case_index)
		await physics_frame
		await physics_frame
		var state: Dictionary = ragdoll.stability_state()
		worst_stretch = maxf(worst_stretch, float(state[&"stretch_ratio"]))
		_expect(bool(state[&"finite"]), "randomized fall %d stays finite" % case_index)
		_expect(float(state[&"stretch_ratio"]) <= GelActiveRagdoll.MAX_JOINT_STRETCH_RATIO + 0.001,
			"randomized fall %d respects the joint-stretch cap" % case_index)
		ragdoll.stop_ragdoll()
		_expect(bool(ragdoll.stability_state()[&"settled"]),
			"randomized fall %d settles" % case_index)
		_reset_pose(skeleton)

	var started_ms: int = Time.get_ticks_msec()
	_expect(ragdoll.start_ragdoll(Vector3(8.0, 6.0, -5.0), Vector3.ZERO, 31154),
		"the timed settling fall starts")
	await create_timer(GelActiveRagdoll.LIFETIME - GelActiveRagdoll.RECOVERY_DURATION).timeout
	ragdoll.begin_recovery(GelActiveRagdoll.RECOVERY_DURATION)
	await create_timer(GelActiveRagdoll.RECOVERY_DURATION).timeout
	ragdoll.stop_ragdoll()
	var elapsed_seconds: float = float(Time.get_ticks_msec() - started_ms) / 1000.0
	_expect(elapsed_seconds < SETTLE_LIMIT_SECONDS, "the ragdoll settles in under four seconds")
	var settled_state: Dictionary = ragdoll.stability_state()
	_expect(bool(settled_state[&"settled"]), "physical simulation stops after settling")
	_expect(bool(settled_state[&"finite"]), "the settled rig remains finite")
	print("MEASURE: 100 falls, worst joint stretch %.3fx, settle %.3fs"
		% [worst_stretch, elapsed_seconds])
	model.free()
	if _failures == 0:
		print("PASS: 100 randomized gel ragdolls remain finite, bounded and settle under 4 s")
	quit(_failures)


func _randomize_proportions(proportions: GelBodyProportions, random: RandomNumberGenerator) -> void:
	var values: Dictionary = {}
	for definition: Dictionary in GelBodyProportions.PARAMETER_DEFINITIONS:
		values[definition[&"name"]] = random.randf_range(
			float(definition[&"minimum"]), float(definition[&"maximum"])
		)
	proportions.apply_dictionary(values)


func _randomize_pose(skeleton: Skeleton3D, random: RandomNumberGenerator) -> void:
	for bone_name: StringName in POSE_BONES:
		var bone_index: int = skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var axis := Vector3(random.randf_range(-1.0, 1.0), random.randf_range(-1.0, 1.0),
			random.randf_range(-1.0, 1.0)).normalized()
		if axis.length_squared() < 0.1:
			axis = Vector3.RIGHT
		skeleton.set_bone_pose_rotation(bone_index, Quaternion(axis, random.randf_range(-0.65, 0.65)))
	skeleton.force_update_all_bone_transforms()


func _reset_pose(skeleton: Skeleton3D) -> void:
	for bone_name: StringName in POSE_BONES:
		var bone_index: int = skeleton.find_bone(bone_name)
		if bone_index >= 0:
			skeleton.set_bone_pose_rotation(bone_index, Quaternion.IDENTITY)
	skeleton.force_update_all_bone_transforms()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
