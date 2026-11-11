extends SceneTree
## S-311.79: authored reaction clips stay readable and return to Idle. Runtime
## event selection and blending belong to S-311.80, so this test only exercises
## the exported animation library.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const DURATIONS: Dictionary = {
	&"Stumble": 1.2,
	&"Slip": 1.3,
	&"Pushed": 0.9,
	&"BoxHit": 0.8,
	&"Scared": 1.0,
	&"Dizzy": 2.4,
	&"ShakeOffWater": 1.8,
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
	_expect(skeleton != null and player != null, "the real gel exposes its reaction clips")
	if skeleton != null and player != null:
		_check_manifest(player)
		_check_balance_reactions(player, skeleton)
		_check_impact_reactions(player, skeleton)
		_check_sustained_reactions(player, skeleton)
		_check_recovery(player, skeleton)
	gel.free()
	if _failures == 0:
		print("PASS: gel reactions trip, slip, recoil, startle, sway and shake cleanly")
	quit(_failures)


func _check_manifest(player: AnimationPlayer) -> void:
	for clip: StringName in DURATIONS:
		_expect(player.has_animation(clip), "the gel export contains %s" % clip)
		if player.has_animation(clip):
			_expect(absf(player.get_animation(clip).length - float(DURATIONS[clip])) < 0.02,
				"%s keeps its authored duration" % clip)


func _check_balance_reactions(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	var stumble_impact: Array[Transform3D] = _pose(player, skeleton, &"Stumble", 0.18)
	var stumble_step: Array[Transform3D] = _pose(player, skeleton, &"Stumble", 0.41)
	var slip_impact: Array[Transform3D] = _pose(player, skeleton, &"Slip", 0.2)
	var slip_step: Array[Transform3D] = _pose(player, skeleton, &"Slip", 0.48)
	var head: int = skeleton.find_bone(&"head")
	var left_foot: int = skeleton.find_bone(&"foot.L")
	var right_foot: int = skeleton.find_bone(&"foot.R")
	_expect(stumble_impact[head].origin.distance_to(idle[head].origin) > 0.12,
		"Stumble has a visible forward lurch")
	_expect(stumble_step[left_foot].origin.distance_to(idle[left_foot].origin) > 0.08,
		"Stumble catches itself with the left foot")
	_expect(slip_impact[head].origin.distance_to(idle[head].origin) > 0.10,
		"Slip throws the upper body off balance")
	_expect(slip_step[right_foot].origin.distance_to(idle[right_foot].origin) > 0.12,
		"Slip sends the right foot forward")


func _check_impact_reactions(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	var pushed: Array[Transform3D] = _pose(player, skeleton, &"Pushed", 0.14)
	var hit: Array[Transform3D] = _pose(player, skeleton, &"BoxHit", 0.12)
	var scared: Array[Transform3D] = _pose(player, skeleton, &"Scared", 0.14)
	var pelvis: int = skeleton.find_bone(&"pelvis")
	var head: int = skeleton.find_bone(&"head")
	var left: int = skeleton.find_bone(&"hand.L")
	var right: int = skeleton.find_bone(&"hand.R")
	_expect(absf(pushed[pelvis].origin.x - idle[pelvis].origin.x) > 0.08,
		"Pushed displaces the body sideways")
	_expect(hit[head].origin.distance_to(idle[head].origin) > 0.08,
		"BoxHit recoils the head and chest")
	_expect(hit[left].origin.distance_to(idle[left].origin) > 0.15
		and hit[right].origin.distance_to(idle[right].origin) > 0.15,
		"BoxHit raises both arms into a protective flinch")
	_expect(scared[pelvis].origin.y < idle[pelvis].origin.y - 0.06,
		"Scared ducks under the explosive surprise")
	_expect(scared[left].origin.y > idle[left].origin.y + 0.10
		and scared[right].origin.y > idle[right].origin.y + 0.10,
		"Scared lifts both hands")


func _check_sustained_reactions(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	var dizzy: Array[Transform3D] = _pose(player, skeleton, &"Dizzy", 0.55)
	var shake_a: Array[Transform3D] = _pose(player, skeleton, &"ShakeOffWater", 0.25)
	var shake_b: Array[Transform3D] = _pose(player, skeleton, &"ShakeOffWater", 0.35)
	var head: int = skeleton.find_bone(&"head")
	var chest: int = skeleton.find_bone(&"chest")
	_expect(dizzy[head].origin.distance_to(idle[head].origin) > 0.06
		or _basis_angle(dizzy[head], idle[head]) > 0.12,
		"Dizzy visibly sways the head")
	_expect(_basis_angle(shake_a[chest], shake_b[chest]) > 0.14,
		"ShakeOffWater reverses the torso twist between shake phases")


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
