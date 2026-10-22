extends SceneTree
## S-311.78: the exported gel body owns the full gameplay clip set. This
## checks authored contacts and transitions without coupling them to the
## PlayerAnimator state machine that belongs to S-311.80.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const DURATIONS: Dictionary = {
	&"PickUpPackage": 1.6,
	&"PickUpHigh": 1.6,
	&"CarryWalk": 1.0 / 3.0,
	&"ThrowPackage": 1.0,
	&"DropPackage": 0.9,
	&"Sit": 4.0,
	&"Drive": 2.0,
	&"EnterTruck": 1.2,
	&"ExitTruck": 1.2,
	&"RingDoorbell": 1.1,
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
	_expect(skeleton != null and player != null, "the real gel exposes its gameplay animation library")
	if skeleton != null and player != null:
		_check_manifest(player)
		_check_carry(player, skeleton)
		_check_package_actions(player, skeleton)
		_check_vehicle_actions(player, skeleton)
		_check_doorbell(player, skeleton)
	gel.free()
	if _failures == 0:
		print("PASS: gel gameplay clips carry, handle packages, use the truck and ring the bell")
	quit(_failures)


func _check_manifest(player: AnimationPlayer) -> void:
	for clip: StringName in DURATIONS:
		_expect(player.has_animation(clip), "the gel export contains %s" % clip)
		if player.has_animation(clip):
			_expect(absf(player.get_animation(clip).length - float(DURATIONS[clip])) < 0.02,
				"%s keeps its authored duration" % clip)


func _check_carry(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var start: Array[Transform3D] = _pose(player, skeleton, &"CarryWalk", 0.0)
	var middle: Array[Transform3D] = _pose(player, skeleton, &"CarryWalk", 0.16)
	var end: Array[Transform3D] = _pose(player, skeleton, &"CarryWalk", float(DURATIONS[&"CarryWalk"]))
	var foot: int = skeleton.find_bone(&"foot.L")
	var hand_left: int = skeleton.find_bone(&"hand.L")
	var hand_right: int = skeleton.find_bone(&"hand.R")
	_expect(start[foot].origin.distance_to(middle[foot].origin) > 0.08,
		"CarryWalk has a real step instead of sliding")
	_expect(start[hand_left].origin.distance_to(middle[hand_left].origin) < 0.12
		and start[hand_right].origin.distance_to(middle[hand_right].origin) < 0.12,
		"CarryWalk keeps both hands steady on the package")
	_expect(_worst_position(start, end) < 0.002, "CarryWalk closes without a pose pop")


func _check_package_actions(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var chest: int = skeleton.find_bone(&"chest")
	var left: int = skeleton.find_bone(&"hand.L")
	var right: int = skeleton.find_bone(&"hand.R")
	var carry: Array[Transform3D] = _pose(player, skeleton, &"CarryWalk", 0.0)
	var thrown: Array[Transform3D] = _pose(player, skeleton, &"ThrowPackage", 0.52)
	var lowered: Array[Transform3D] = _pose(player, skeleton, &"DropPackage", 0.58)
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	var throw_end: Array[Transform3D] = _pose(player, skeleton, &"ThrowPackage", 1.0)
	var drop_end: Array[Transform3D] = _pose(player, skeleton, &"DropPackage", 0.9)
	var carry_reach: float = (carry[left].origin.distance_to(carry[chest].origin)
		+ carry[right].origin.distance_to(carry[chest].origin)) * 0.5
	var throw_reach: float = (thrown[left].origin.distance_to(thrown[chest].origin)
		+ thrown[right].origin.distance_to(thrown[chest].origin)) * 0.5
	_expect(throw_reach > carry_reach + 0.08,
		"ThrowPackage extends both arms through release (%.3f -> %.3f m)" % [carry_reach, throw_reach])
	_expect(lowered[left].origin.y < carry[left].origin.y - 0.12
		and lowered[right].origin.y < carry[right].origin.y - 0.12,
		"DropPackage lowers both hands before release")
	_expect(_worst_position(throw_end, idle) < 0.01, "ThrowPackage recovers into Idle")
	_expect(_worst_position(drop_end, idle) < 0.01, "DropPackage recovers into Idle")


func _check_vehicle_actions(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	var drive: Array[Transform3D] = _pose(player, skeleton, &"Drive", 0.0)
	var drive_end: Array[Transform3D] = _pose(player, skeleton, &"Drive", 2.0)
	var pelvis: int = skeleton.find_bone(&"pelvis")
	var left_foot: int = skeleton.find_bone(&"foot.L")
	var right_foot: int = skeleton.find_bone(&"foot.R")
	_expect(drive[pelvis].origin.y < idle[pelvis].origin.y - 0.3,
		"Drive sits the pelvis on the cab seat")
	_expect(drive[left_foot].origin.distance_to(drive[right_foot].origin) > 0.18,
		"Drive separates the feet for the pedal targets")
	_expect(_worst_position(drive, drive_end) < 0.002, "Drive closes without a pose pop")
	var enter_start: Array[Transform3D] = _pose(player, skeleton, &"EnterTruck", 0.0)
	var enter_end: Array[Transform3D] = _pose(player, skeleton, &"EnterTruck", 1.2)
	var exit_start: Array[Transform3D] = _pose(player, skeleton, &"ExitTruck", 0.0)
	var exit_end: Array[Transform3D] = _pose(player, skeleton, &"ExitTruck", 1.2)
	_expect(_worst_position(enter_start, idle) < 0.01, "EnterTruck starts from Idle")
	_expect(_worst_position(enter_end, drive) < 0.01, "EnterTruck settles into Drive")
	_expect(_worst_position(exit_start, drive) < 0.01, "ExitTruck starts from Drive")
	_expect(_worst_position(exit_end, idle) < 0.01, "ExitTruck finishes in Idle")


func _check_doorbell(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	var press: Array[Transform3D] = _pose(player, skeleton, &"RingDoorbell", 0.58)
	var end: Array[Transform3D] = _pose(player, skeleton, &"RingDoorbell", 1.1)
	var right: int = skeleton.find_bone(&"hand.R")
	var left: int = skeleton.find_bone(&"hand.L")
	_expect(press[right].origin.distance_to(idle[right].origin) > 0.3,
		"RingDoorbell reaches the pressing hand to the button")
	var free_hand_motion: float = press[left].origin.distance_to(idle[left].origin)
	_expect(free_hand_motion < 0.10,
		"RingDoorbell leaves the free hand relaxed (moved %.3f m)" % free_hand_motion)
	_expect(_worst_position(end, idle) < 0.01, "RingDoorbell returns to Idle")


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


func _worst_position(first: Array[Transform3D], second: Array[Transform3D]) -> float:
	var worst: float = 0.0
	for bone: int in first.size():
		worst = maxf(worst, first[bone].origin.distance_to(second[bone].origin))
	return worst


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
