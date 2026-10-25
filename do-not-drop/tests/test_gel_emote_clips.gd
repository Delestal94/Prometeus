extends SceneTree
## S-311.86: the eight authored emotes are present, visually distinct through
## their named-bone poses, finite, and return to the shared Idle pose.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const DURATIONS: Dictionary = {
	&"Wave": 2.2,
	&"Clap": 2.4,
	&"Facepalm": 2.2,
	&"Shrug": 2.0,
	&"Point": 2.0,
	&"ThumbsUp": 2.0,
	&"MeltAndReturn": 3.0,
	&"ShakeLikeDog": 1.8,
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
	_expect(skeleton != null and player != null, "the real gel exposes its emote library")
	if skeleton != null and player != null:
		_check_manifest(player, skeleton)
		_check_upper_body_emotes(player, skeleton)
		_check_whole_body_emotes(player, skeleton)
		_check_recovery(player, skeleton)
	gel.free()
	if _failures == 0:
		print("PASS: eight gel emotes wave, clap, react, point, melt and shake distinctly")
	quit(_failures)


func _check_manifest(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	for clip: StringName in DURATIONS:
		_expect(player.has_animation(clip), "the gel export contains %s" % clip)
		if not player.has_animation(clip):
			continue
		var animation: Animation = player.get_animation(clip)
		_expect(absf(animation.length - float(DURATIONS[clip])) < 0.02,
			"%s keeps its authored duration" % clip)
		for at: float in [0.0, animation.length * 0.5, animation.length]:
			var pose: Array[Transform3D] = _pose(player, skeleton, clip, at)
			_expect(pose.all(func(value: Transform3D) -> bool: return value.is_finite()),
				"%s has finite named-bone poses at %.2f s" % [clip, at])


func _check_upper_body_emotes(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	var left_hand: int = skeleton.find_bone(&"hand.L")
	var right_hand: int = skeleton.find_bone(&"hand.R")
	var right_thumb: int = skeleton.find_bone(&"thumb.R")
	var head: int = skeleton.find_bone(&"head")

	var waving: Array[Transform3D] = _pose(player, skeleton, &"Wave", 0.72)
	_expect(waving[right_hand].origin.distance_to(idle[right_hand].origin) > 0.22,
		"Wave clearly raises the greeting hand")

	var clap_open: Array[Transform3D] = _pose(player, skeleton, &"Clap", 0.86)
	var clap_contact: Array[Transform3D] = _pose(player, skeleton, &"Clap", 0.58)
	_expect(clap_contact[left_hand].origin.distance_to(clap_contact[right_hand].origin)
		< clap_open[left_hand].origin.distance_to(clap_open[right_hand].origin) - 0.08,
		"Clap visibly closes both hands together")

	var palm: Array[Transform3D] = _pose(player, skeleton, &"Facepalm", 0.9)
	_expect(palm[right_hand].origin.distance_to(palm[head].origin) < 0.62
		and palm[right_hand].origin.distance_to(palm[head].origin)
		< idle[right_hand].origin.distance_to(idle[head].origin) - 0.12,
		"Facepalm places one hand at the head")

	var shrug_pose: Array[Transform3D] = _pose(player, skeleton, &"Shrug", 0.8)
	_expect(shrug_pose[left_hand].origin.distance_to(idle[left_hand].origin) > 0.16
		and shrug_pose[right_hand].origin.distance_to(idle[right_hand].origin) > 0.16,
		"Shrug opens both arms")

	var pointing: Array[Transform3D] = _pose(player, skeleton, &"Point", 0.8)
	_expect(pointing[right_hand].origin.distance_to(idle[right_hand].origin) > 0.25,
		"Point extends the right arm decisively")

	var approval: Array[Transform3D] = _pose(player, skeleton, &"ThumbsUp", 0.8)
	_expect(approval[right_hand].origin.distance_to(idle[right_hand].origin) > 0.2,
		"ThumbsUp presents the right hand beside the face")
	_expect(_basis_angle(approval[right_thumb], idle[right_thumb]) > 0.25,
		"ThumbsUp articulates the thumb instead of only lifting a fist")


func _check_whole_body_emotes(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	var pelvis: int = skeleton.find_bone(&"pelvis")
	var head: int = skeleton.find_bone(&"head")
	var chest: int = skeleton.find_bone(&"chest")
	var melted: Array[Transform3D] = _pose(player, skeleton, &"MeltAndReturn", 1.15)
	_expect(melted[pelvis].origin.y < idle[pelvis].origin.y - 0.32
		and melted[head].origin.y < idle[head].origin.y - 0.28,
		"MeltAndReturn collapses the whole body toward the floor")

	var shake_a: Array[Transform3D] = _pose(player, skeleton, &"ShakeLikeDog", 0.42)
	var shake_b: Array[Transform3D] = _pose(player, skeleton, &"ShakeLikeDog", 0.50)
	_expect(_basis_angle(shake_a[chest], shake_b[chest]) > 0.2,
		"ShakeLikeDog reverses its torso twist quickly")


func _check_recovery(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	for clip: StringName in DURATIONS:
		var end: Array[Transform3D] = _pose(player, skeleton, clip, float(DURATIONS[clip]))
		_expect(_worst_position(end, idle) < 0.01 and _worst_basis_angle(end, idle) < 0.02,
			"%s returns exactly to Idle" % clip)


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


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
