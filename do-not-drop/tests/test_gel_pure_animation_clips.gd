extends SceneTree
## S-311.87: six pure-gel clips visibly squash, stretch, bounce, separate,
## shiver and inflate through the shared named-bone rig, then recover to Idle.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const DURATIONS: Dictionary = {
	&"Pancake": 2.4,
	&"GumStretch": 2.8,
	&"BallBounce": 2.4,
	&"SplitAndJoin": 3.2,
	&"ColdShiver": 2.0,
	&"Inflate": 2.8,
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
	_expect(skeleton != null and player != null, "the real gel exposes its pure-gel clips")
	if skeleton != null and player != null:
		_check_manifest(player, skeleton)
		_check_silhouettes(player, skeleton)
		_check_recovery(player, skeleton)
	gel.free()
	if _failures == 0:
		print("PASS: six pure-gel clips squash, stretch, bounce, split, shiver and inflate")
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


func _check_silhouettes(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	var pelvis: int = skeleton.find_bone(&"pelvis")
	var chest: int = skeleton.find_bone(&"chest")
	var head: int = skeleton.find_bone(&"head")
	var idle_height: float = idle[head].origin.y - idle[pelvis].origin.y

	var flat: Array[Transform3D] = _pose(player, skeleton, &"Pancake", 0.9)
	var flat_height: float = flat[head].origin.y - flat[pelvis].origin.y
	_expect(flat_height < idle_height - 0.12,
		"Pancake compresses the body vertically (%.3f versus %.3f)"
		% [flat_height, idle_height])

	var stretched: Array[Transform3D] = _pose(player, skeleton, &"GumStretch", 1.1)
	var stretched_height: float = stretched[head].origin.y - stretched[pelvis].origin.y
	_expect(stretched_height > idle_height + 0.14,
		"GumStretch pulls the body taller (%.3f versus %.3f)"
		% [stretched_height, idle_height])

	var airborne: Array[Transform3D] = _pose(player, skeleton, &"BallBounce", 0.47)
	_expect(airborne[pelvis].origin.y > idle[pelvis].origin.y + 0.16,
		"BallBounce lifts the whole body clear of its rest pose")

	var divided: Array[Transform3D] = _pose(player, skeleton, &"SplitAndJoin", 1.1)
	var idle_span: float = idle[head].origin.distance_to(idle[pelvis].origin)
	var divided_span: float = divided[head].origin.distance_to(divided[pelvis].origin)
	_expect(divided_span > idle_span + 0.14,
		"SplitAndJoin separates the upper and lower halves (%.3f versus %.3f)"
		% [divided_span, idle_span])

	var shiver_a: Array[Transform3D] = _pose(player, skeleton, &"ColdShiver", 0.42)
	var shiver_b: Array[Transform3D] = _pose(player, skeleton, &"ColdShiver", 0.48)
	_expect(_basis_angle(shiver_a[chest], shiver_b[chest]) > 0.12,
		"ColdShiver reverses the torso vibration quickly")

	var inflated: Array[Transform3D] = _pose(player, skeleton, &"Inflate", 1.2)
	var idle_volume: float = absf(idle[chest].basis.determinant())
	var inflated_volume: float = absf(inflated[chest].basis.determinant())
	_expect(inflated_volume > idle_volume * 1.18,
		"Inflate increases the torso volume (%.3f versus %.3f)"
		% [inflated_volume, idle_volume])


func _check_recovery(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	for clip: StringName in DURATIONS:
		var end: Array[Transform3D] = _pose(player, skeleton, clip, float(DURATIONS[clip]))
		_expect(_worst_position(end, idle) < 0.01
			and _worst_basis_angle(end, idle) < 0.02
			and _worst_scale_delta(end, idle) < 0.02,
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
