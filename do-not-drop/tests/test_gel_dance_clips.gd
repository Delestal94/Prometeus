extends SceneTree
## S-311.88: eight original dance loops are present, finite, seamless and
## visually distinct; Conga's nearby phase policy is covered by the animator test.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const DURATIONS: Dictionary = {
	&"SimpleStep": 2.4,
	&"Robot": 2.4,
	&"Disco": 2.8,
	&"FloorWorm": 3.2,
	&"Headbang": 1.6,
	&"VictoryDance": 2.8,
	&"Flan": 2.4,
	&"Conga": 2.4,
}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gel: Node3D = GEL_SCENE.instantiate()
	root.add_child(gel)
	await process_frame
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(gel)
	var player: AnimationPlayer = PlayerAppearance.find_animation_player(gel)
	_expect(skeleton != null and player != null, "the real gel exposes its dance library")
	if skeleton != null and player != null:
		_check_manifest_and_loops(player, skeleton)
		_check_signatures(player, skeleton)
	gel.free()
	if _failures == 0:
		print("PASS: eight original gel dances loop cleanly and keep distinct silhouettes")
	quit(_failures)


func _check_manifest_and_loops(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	for clip: StringName in DURATIONS:
		_expect(player.has_animation(clip), "the gel export contains %s" % clip)
		if not player.has_animation(clip):
			continue
		var animation: Animation = player.get_animation(clip)
		_expect(absf(animation.length - float(DURATIONS[clip])) < 0.02,
			"%s keeps its authored duration" % clip)
		var start: Array[Transform3D] = _pose(player, skeleton, clip, 0.0)
		var middle: Array[Transform3D] = _pose(player, skeleton, clip, animation.length * 0.5)
		var finish: Array[Transform3D] = _pose(player, skeleton, clip, animation.length)
		_expect(start.all(func(value: Transform3D) -> bool: return value.is_finite())
			and middle.all(func(value: Transform3D) -> bool: return value.is_finite())
			and finish.all(func(value: Transform3D) -> bool: return value.is_finite()),
			"%s keeps finite named-bone poses" % clip)
		_expect(_worst_position(start, finish) < 0.005
			and _worst_basis_angle(start, finish) < 0.01
			and _worst_scale_delta(start, finish) < 0.01,
			"%s closes its loop without a visible seam" % clip)


func _check_signatures(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var pelvis: int = skeleton.find_bone(&"pelvis")
	var chest: int = skeleton.find_bone(&"chest")
	var head: int = skeleton.find_bone(&"head")
	var foot_l: int = skeleton.find_bone(&"foot.L")
	var foot_r: int = skeleton.find_bone(&"foot.R")
	var hand_l: int = skeleton.find_bone(&"hand.L")
	var hand_r: int = skeleton.find_bone(&"hand.R")
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)

	var step_left: Array[Transform3D] = _pose(player, skeleton, &"SimpleStep", 0.6)
	var step_right: Array[Transform3D] = _pose(player, skeleton, &"SimpleStep", 1.8)
	_expect(absf(step_left[pelvis].origin.x - step_right[pelvis].origin.x) > 0.08,
		"SimpleStep clearly transfers weight between both sides")

	var robot_a: Array[Transform3D] = _pose(player, skeleton, &"Robot", 0.3)
	var robot_b: Array[Transform3D] = _pose(player, skeleton, &"Robot", 0.9)
	_expect(_basis_angle(robot_a[chest], robot_b[chest]) > 0.18,
		"Robot reverses its locked torso angles")

	var disco_a: Array[Transform3D] = _pose(player, skeleton, &"Disco", 0.7)
	var disco_b: Array[Transform3D] = _pose(player, skeleton, &"Disco", 2.1)
	_expect(disco_a[hand_l].origin.y > disco_a[hand_r].origin.y + 0.18
		and disco_b[hand_r].origin.y > disco_b[hand_l].origin.y + 0.18,
		"Disco alternates the high diagonal pointing arm")

	var worm: Array[Transform3D] = _pose(player, skeleton, &"FloorWorm", 0.8)
	_expect(worm[pelvis].origin.y < idle[pelvis].origin.y - 0.20,
		"FloorWorm keeps the body visibly low to the floor")

	var bang_up: Array[Transform3D] = _pose(player, skeleton, &"Headbang", 0.0)
	var bang_down: Array[Transform3D] = _pose(player, skeleton, &"Headbang", 0.4)
	_expect(_basis_angle(bang_up[head], bang_down[head]) > 0.45,
		"Headbang drives a strong readable head arc")

	var victory: Array[Transform3D] = _pose(player, skeleton, &"VictoryDance", 0.35)
	_expect(victory[pelvis].origin.y > idle[pelvis].origin.y + 0.04
		and victory[hand_l].origin.y > victory[head].origin.y
		and victory[hand_r].origin.y > victory[head].origin.y,
		"VictoryDance lifts the body with both arms overhead")

	var flan_a: Array[Transform3D] = _pose(player, skeleton, &"Flan", 1.0)
	var flan_b: Array[Transform3D] = _pose(player, skeleton, &"Flan", 2.2)
	var flan_chest_angle: float = _basis_angle(flan_a[chest], flan_b[chest])
	var flan_head_angle: float = _basis_angle(flan_a[head], flan_b[head])
	_expect(flan_chest_angle > 0.25 and flan_head_angle > 0.18,
		"Flan sends the whole upper body through an opposing gel wave (%.3f/%.3f)"
		% [flan_chest_angle, flan_head_angle])

	var conga_left: Array[Transform3D] = _pose(player, skeleton, &"Conga", 0.6)
	var conga_right: Array[Transform3D] = _pose(player, skeleton, &"Conga", 1.8)
	_expect(conga_left[foot_l].origin.y > conga_left[foot_r].origin.y + 0.035
		and conga_right[foot_r].origin.y > conga_right[foot_l].origin.y + 0.035,
		"Conga alternates its marching knees on the shared loop phase")


func _pose(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip: StringName,
	at: float
) -> Array[Transform3D]:
	player.play(clip)
	player.seek(at, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var result: Array[Transform3D] = []
	for bone: int in skeleton.get_bone_count():
		result.append(skeleton.get_bone_global_pose(bone))
	return result


func _basis_angle(first: Transform3D, second: Transform3D) -> float:
	return first.basis.get_rotation_quaternion().angle_to(second.basis.get_rotation_quaternion())


func _worst_position(first: Array[Transform3D], second: Array[Transform3D]) -> float:
	var worst: float = 0.0
	for bone: int in first.size():
		worst = maxf(worst, first[bone].origin.distance_to(second[bone].origin))
	return worst


func _worst_basis_angle(first: Array[Transform3D], second: Array[Transform3D]) -> float:
	var worst: float = 0.0
	for bone: int in first.size():
		worst = maxf(worst, _basis_angle(first[bone], second[bone]))
	return worst


func _worst_scale_delta(first: Array[Transform3D], second: Array[Transform3D]) -> float:
	var worst: float = 0.0
	for bone: int in first.size():
		worst = maxf(worst, first[bone].basis.get_scale().distance_to(
			second[bone].basis.get_scale()))
	return worst


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
