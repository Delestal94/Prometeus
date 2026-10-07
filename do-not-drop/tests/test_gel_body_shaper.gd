extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_body_shaper.gd
##
## S-311.20 applies every morph and the six bone-driven proportions to the real
## LOD0 import. Rest edits remain reversible, animation tracks keep playing and
## 120 idle frames perform no additional shaping work.

const MODEL_PATH := "res://assets/models/characters/gel/gel_body_lod0.glb"
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Shaper := preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load(MODEL_PATH) as PackedScene
	_expect(scene != null, "the gel LOD0 scene is importable")
	if scene == null:
		quit(_failures)
		return
	var model: Node3D = scene.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	var skeleton: Skeleton3D = _find(model, "Skeleton3D") as Skeleton3D
	var body: MeshInstance3D = _find(model, "MeshInstance3D") as MeshInstance3D
	var animation: AnimationPlayer = _find(model, "AnimationPlayer") as AnimationPlayer
	_expect(skeleton != null and body != null and animation != null, "the real model exposes rig, body and clips")
	if skeleton == null or body == null or animation == null:
		model.free()
		quit(_failures)
		return

	var shaper: RefCounted = Shaper.new()
	_expect(shaper.setup(model), "the shaper discovers the imported rig and blend-shape body")
	var base_rests: Array[Transform3D] = _rests(skeleton)
	var proportions: Resource = Proportions.new()
	_set_extreme_values(proportions)

	animation.play(&"Walk")
	animation.seek(0.12, true)
	animation.advance(0.0)
	var pose_before: Array[Transform3D] = _poses(skeleton)
	_expect(shaper.apply(proportions), "changed proportions are applied once")
	_check_morphs(body, proportions)
	_check_lengths(skeleton, base_rests, proportions)
	_check_animation_pose(skeleton, animation, pose_before)

	_expect(not shaper.apply(proportions), "identical values do not recalculate the model")
	var applications_before: int = shaper.application_count
	var idle_started: int = Time.get_ticks_usec()
	for _frame: int in 120:
		await process_frame
	var idle_usec: int = Time.get_ticks_usec() - idle_started
	_expect(shaper.application_count == applications_before, "120 idle frames perform zero shaping operations")

	proportions.reset_to_delgada()
	_expect(shaper.apply(proportions), "returning to Delgada applies one changed state")
	_check_restored(skeleton, body, base_rests)
	model.free()
	if _failures == 0:
		print("PASS: gel shaping is reversible, clip-safe and idle for 120 frames (%d usec wall)" % idle_usec)
	quit(_failures)


func _set_extreme_values(proportions: Resource) -> void:
	proportions.set(&"total_height", 1.20)
	proportions.set(&"leg_length", 1.25)
	proportions.set(&"arm_length", 0.75)
	proportions.set(&"torso_length", 1.15)
	proportions.set(&"neck_length", 1.25)
	proportions.set(&"head_size", 0.80)
	var sign_value: float = -1.0
	for definition: Dictionary in Proportions.parameter_definitions():
		if definition[&"driver"] == &"morph":
			proportions.set(definition[&"name"], sign_value)
			sign_value *= -1.0


func _check_morphs(body: MeshInstance3D, proportions: Resource) -> void:
	for definition: Dictionary in Proportions.parameter_definitions():
		if definition[&"driver"] != &"morph":
			continue
		var morph_name: StringName = definition[&"name"]
		var index: int = body.find_blend_shape_by_name(morph_name)
		_expect(index >= 0, "%s exists on the real body" % morph_name)
		if index >= 0:
			_expect(
				is_equal_approx(body.get_blend_shape_value(index), float(proportions.get(morph_name))),
				"%s receives its requested weight" % morph_name
			)


func _check_lengths(
	skeleton: Skeleton3D,
	base_rests: Array[Transform3D],
	proportions: Resource
) -> void:
	var pelvis: int = skeleton.find_bone(&"pelvis")
	var total_height: float = float(proportions.get(&"total_height"))
	_expect(
		is_equal_approx(skeleton.get_bone_rest(pelvis).origin.y, base_rests[pelvis].origin.y * total_height),
		"total height scales the root rest origin from the floor"
	)
	_check_axis_scale(skeleton, base_rests, &"pelvis", total_height * float(proportions.get(&"torso_length")))
	_check_axis_scale(skeleton, base_rests, &"chest", float(proportions.get(&"torso_length")))
	for side: String in ["L", "R"]:
		_check_axis_scale(
			skeleton, base_rests, StringName("thigh." + side), float(proportions.get(&"leg_length"))
		)
		_check_axis_scale(skeleton, base_rests, StringName("shin." + side), float(proportions.get(&"leg_length")))
		_check_axis_scale(
			skeleton,
			base_rests,
			StringName("upper_arm." + side),
			float(proportions.get(&"arm_length"))
		)
	_check_axis_scale(skeleton, base_rests, &"neck", float(proportions.get(&"neck_length")))
	var head: int = skeleton.find_bone(&"head")
	var head_ratio: Vector3 = skeleton.get_bone_rest(head).basis.get_scale() / base_rests[head].basis.get_scale()
	_expect(head_ratio.is_equal_approx(Vector3.ONE * float(proportions.get(&"head_size"))), "head size is uniform")


func _check_axis_scale(
	skeleton: Skeleton3D,
	base_rests: Array[Transform3D],
	bone_name: StringName,
	expected: float
) -> void:
	var index: int = skeleton.find_bone(bone_name)
	var actual_scale: Vector3 = skeleton.get_bone_rest(index).basis.get_scale()
	var base_scale: Vector3 = base_rests[index].basis.get_scale()
	_expect(
		is_equal_approx(actual_scale.y / base_scale.y, expected),
		"%s changes length only on its local axis" % bone_name
	)
	_expect(is_equal_approx(actual_scale.x / base_scale.x, 1.0), "%s keeps local width" % bone_name)
	_expect(is_equal_approx(actual_scale.z / base_scale.z, 1.0), "%s keeps local depth" % bone_name)


func _check_animation_pose(
	skeleton: Skeleton3D,
	animation: AnimationPlayer,
	before: Array[Transform3D]
) -> void:
	var after: Array[Transform3D] = _poses(skeleton)
	_expect(after.size() == before.size(), "rest shaping preserves every animated bone")
	for bone_index: int in mini(after.size(), before.size()):
		_expect(after[bone_index].is_finite(), "animated bone %d stays finite" % bone_index)
		_expect(
			after[bone_index].basis.is_equal_approx(before[bone_index].basis),
			"bone %d keeps its clip pose" % bone_index
		)
	_expect(animation.is_playing() and animation.current_animation == &"Walk", "rest shaping does not stop the clip")
	animation.advance(0.05)
	var advanced: Array[Transform3D] = _poses(skeleton)
	var changed: bool = false
	for bone_index: int in advanced.size():
		_expect(advanced[bone_index].is_finite(), "advanced bone %d stays finite" % bone_index)
		changed = changed or not advanced[bone_index].is_equal_approx(after[bone_index])
	_expect(changed, "the active clip keeps advancing after rest shaping")


func _check_restored(
	skeleton: Skeleton3D,
	body: MeshInstance3D,
	base_rests: Array[Transform3D]
) -> void:
	var restored: Array[Transform3D] = _rests(skeleton)
	for bone_index: int in mini(restored.size(), base_rests.size()):
		_expect(
			restored[bone_index].is_equal_approx(base_rests[bone_index]),
			"bone %d restores Delgada rest" % bone_index
		)
	for morph_index: int in body.mesh.get_blend_shape_count():
		_expect(is_zero_approx(body.get_blend_shape_value(morph_index)), "morph %d restores Delgada zero" % morph_index)


func _rests(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone_index: int in skeleton.get_bone_count():
		result.append(skeleton.get_bone_rest(bone_index))
	return result


func _poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone_index: int in skeleton.get_bone_count():
		result.append(skeleton.get_bone_pose(bone_index))
	return result


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child: Node in node.get_children():
		var result: Node = _find(child, type_name)
		if result != null:
			return result
	return null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
