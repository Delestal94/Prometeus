extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_jiggle.gd
## S-311.44: six weighted secondary bones, native spring modifiers, motion
## impulses, deterministic per-player idle phase and proportion scaling.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Jiggle := preload("res://scripts/gameplay/player/gel/gel_jiggle.gd")
const CHAIN_NAMES: Array[StringName] = [
	&"head", &"belly", &"forearm_l", &"forearm_r", &"calf_l", &"calf_r",
]
const BONE_NAMES: Array[StringName] = [
	&"jiggle_head", &"jiggle_belly", &"jiggle_forearm.L", &"jiggle_forearm.R",
	&"jiggle_calf.L", &"jiggle_calf.R",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(model)
	var proportions: GelBodyProportions = Proportions.new()
	var jiggle: Node = Jiggle.new()
	root.add_child(jiggle)
	_expect(jiggle.setup(model, proportions, 7), "the real gel rig accepts its spring controller")
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(model)
	_expect(skeleton != null and skeleton.get_bone_count() == 26,
		"the real gel rig exports twenty game plus six jiggle bones")
	_expect(jiggle.simulator_count() == 6, "one SpringBoneSimulator3D drives each soft region")
	for index: int in CHAIN_NAMES.size():
		var simulator: SpringBoneSimulator3D = jiggle.simulator_for(CHAIN_NAMES[index])
		_expect(simulator != null, "%s has a spring simulator" % CHAIN_NAMES[index])
		if simulator == null:
			continue
		_expect(simulator.setting_count == 1, "%s has one unbranched chain" % CHAIN_NAMES[index])
		_expect(StringName(simulator.get_root_bone_name(0)) == BONE_NAMES[index]
			and StringName(simulator.get_end_bone_name(0)) == BONE_NAMES[index],
			"%s targets %s" % [CHAIN_NAMES[index], BONE_NAMES[index]])
		_expect(simulator.is_end_bone_extended(0), "%s has a simulated tail" % CHAIN_NAMES[index])

	_check_motion_responses(jiggle)
	await _check_native_solver_moves_bone(jiggle, skeleton)
	_check_proportion_scaling(jiggle, proportions)
	_check_distinct_idle_phase(jiggle)

	model.free()
	jiggle.free()
	if _failures == 0:
		print("PASS: gel spring bones react to motion, landing, proportions and per-player idle phase")
	quit(_failures)


func _check_motion_responses(jiggle: Node) -> void:
	jiggle.reset_motion()
	jiggle.advance_motion(Vector3.ZERO, 0.0, true, 0.1)
	var idle_force: Vector3 = jiggle.simulator_for(&"belly").external_force
	_expect(idle_force.length() > 0.0 and idle_force.length() < 0.02,
		"resting gel has only a very soft tremor")

	jiggle.advance_motion(Vector3(4.0, 0.0, 0.0), 0.0, true, 0.1)
	var acceleration_force: Vector3 = jiggle.simulator_for(&"belly").external_force
	_expect(acceleration_force.length() > idle_force.length() * 5.0,
		"starting movement creates a visible inertial response")
	jiggle.advance_motion(Vector3.ZERO, 0.0, true, 0.1)
	var braking_force: Vector3 = jiggle.simulator_for(&"belly").external_force
	_expect(acceleration_force.dot(braking_force) < 0.0,
		"braking reverses the spring force")

	jiggle.reset_motion()
	jiggle.advance_motion(Vector3.ZERO, 0.0, true, 0.1)
	jiggle.advance_motion(Vector3.ZERO, 0.5, true, 0.1)
	_expect(jiggle.simulator_for(&"head").external_force.length() > 0.10,
		"turning excites the head spring")

	jiggle.reset_motion()
	jiggle.advance_motion(Vector3.ZERO, 0.0, true, 0.1)
	jiggle.advance_motion(Vector3(0.0, 5.0, 0.0), 0.0, false, 0.1)
	_expect(jiggle.simulator_for(&"belly").external_force.y < -0.10,
		"jump takeoff makes the gel lag downward")
	jiggle.reset_motion()
	jiggle.advance_motion(Vector3(0.0, -5.0, 0.0), 0.0, false, 0.1)
	jiggle.advance_motion(Vector3.ZERO, 0.0, true, 0.1)
	_expect(jiggle.simulator_for(&"belly").external_force.y < -0.10,
		"landing creates a downward settling impulse")


func _check_native_solver_moves_bone(jiggle: Node, skeleton: Skeleton3D) -> void:
	var head: int = skeleton.find_bone(&"jiggle_head")
	var rest_rotation: Quaternion = skeleton.get_bone_pose_rotation(head)
	var observed_angle: Array[float] = [0.0]
	var simulator: SpringBoneSimulator3D = jiggle.simulator_for(&"head")
	_expect(simulator.get_joint_count(0) == 1, "the extended head chain resolves to one simulated joint")
	simulator.modification_processed.connect(func() -> void:
		observed_angle[0] = maxf(observed_angle[0], rest_rotation.angle_to(
			skeleton.get_bone_pose_rotation(head))))
	jiggle.reset_motion()
	jiggle.advance_motion(Vector3.ZERO, 0.0, true, 0.05)
	jiggle.advance_motion(Vector3(5.0, 0.0, 0.0), 0.0, true, 0.05)
	for _frame: int in 12:
		await process_frame
	_expect(observed_angle[0] > 0.0001,
		"SpringBoneSimulator3D applies the force to the exported head bone")


func _check_proportion_scaling(jiggle: Node, proportions: GelBodyProportions) -> void:
	proportions.belly = -1.0
	jiggle.apply_proportions(proportions)
	var thin_amplitude: float = jiggle.amplitude_for(&"belly")
	var thin_stiffness: float = jiggle.simulator_for(&"belly").get_stiffness(0)
	proportions.belly = 1.0
	jiggle.apply_proportions(proportions)
	var full_amplitude: float = jiggle.amplitude_for(&"belly")
	var full_stiffness: float = jiggle.simulator_for(&"belly").get_stiffness(0)
	_expect(full_amplitude > thin_amplitude * 2.0,
		"a fuller belly receives substantially more spring amplitude")
	_expect(full_stiffness < thin_stiffness,
		"a fuller belly is softer as well as more mobile")


func _check_distinct_idle_phase(first: Node) -> void:
	var other_model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(other_model)
	var second: Node = Jiggle.new()
	root.add_child(second)
	_expect(second.setup(other_model, Proportions.new(), 8), "a second player gets the same spring rig")
	first.reset_motion()
	second.reset_motion()
	first.advance_motion(Vector3.ZERO, 0.0, true, 0.1)
	second.advance_motion(Vector3.ZERO, 0.0, true, 0.1)
	var first_force: Vector3 = first.simulator_for(&"head").external_force
	var second_force: Vector3 = second.simulator_for(&"head").external_force
	_expect(not first_force.is_equal_approx(second_force),
		"different player ids produce distinct resting phases")
	other_model.free()
	second.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
