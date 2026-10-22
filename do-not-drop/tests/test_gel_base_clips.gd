extends SceneTree
## S-311.77: the real gel export keeps the six base clips authored by
## animation_library.py, with closed loops and readable locomotion phases.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const DURATIONS: Dictionary = {
	&"Idle": 6.0,
	&"Walk": 1.0 / 3.0,
	&"Stroll": 0.6,
	&"Run": 1.0 / 3.0,
	&"Jump": 1.6,
	&"TurnInPlace": 0.8,
}
const LOOPING: Array[StringName] = [&"Idle", &"Walk", &"Stroll", &"Run", &"TurnInPlace"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gel: Node3D = GEL_SCENE.instantiate()
	root.add_child(gel)
	await process_frame
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(gel)
	var player: AnimationPlayer = PlayerAppearance.find_animation_player(gel)
	_expect(skeleton != null and player != null, "the real gel exposes its skeleton and animation player")
	if skeleton != null and player != null:
		_check_manifest(player)
		_check_loop_closure(player, skeleton)
		_check_gaits(player, skeleton)
		_check_jump(player, skeleton)
		_check_turn(player, skeleton)
	gel.free()
	if _failures == 0:
		print("PASS: gel base clips close, plant, jump and turn with readable phases")
	quit(_failures)


func _check_manifest(player: AnimationPlayer) -> void:
	for clip: StringName in DURATIONS:
		_expect(player.has_animation(clip), "the gel export contains %s" % clip)
		if player.has_animation(clip):
			var duration: float = player.get_animation(clip).length
			_expect(absf(duration - float(DURATIONS[clip])) < 0.02,
				"%s keeps its authored duration (got %.3f s)" % [clip, duration])


func _check_loop_closure(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	for clip: StringName in LOOPING:
		var first: Array[Transform3D] = _pose(player, skeleton, clip, 0.0)
		var last: Array[Transform3D] = _pose(player, skeleton, clip, player.get_animation(clip).length)
		var worst_position: float = 0.0
		var worst_rotation: float = 0.0
		for bone: int in first.size():
			worst_position = maxf(worst_position, first[bone].origin.distance_to(last[bone].origin))
			worst_rotation = maxf(worst_rotation,
				first[bone].basis.get_rotation_quaternion().angle_to(
					last[bone].basis.get_rotation_quaternion()))
		_expect(worst_position < 0.001 and worst_rotation < 0.005,
			"%s closes without a position or rotation pop" % clip)


func _check_gaits(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var lifts: Dictionary = {}
	var touchdown_sides: Array[float] = []
	for clip: StringName in [&"Stroll", &"Walk", &"Run"]:
		var duration: float = player.get_animation(clip).length
		var rest: Array[Transform3D] = _pose(player, skeleton, clip, 0.0)
		var left: int = skeleton.find_bone(&"foot.L")
		var right: int = skeleton.find_bone(&"foot.R")
		touchdown_sides.append(rest[left].origin.z - rest[right].origin.z)
		var maximum_lift: float = 0.0
		for sample: int in range(25):
			var pose: Array[Transform3D] = _pose(player, skeleton, clip, duration * sample / 24.0)
			maximum_lift = maxf(maximum_lift, pose[left].origin.y - rest[left].origin.y)
			maximum_lift = maxf(maximum_lift, pose[right].origin.y - rest[right].origin.y)
		lifts[clip] = maximum_lift
	_expect(absf(touchdown_sides[0]) > 0.05
		and signf(touchdown_sides[0]) == signf(touchdown_sides[1])
		and signf(touchdown_sides[1]) == signf(touchdown_sides[2]),
		"all gaits start on the same footfall phase")
	_expect(float(lifts[&"Stroll"]) > 0.025,
		"Stroll clears the floor (got %.3f m)" % float(lifts[&"Stroll"]))
	_expect(float(lifts[&"Walk"]) > float(lifts[&"Stroll"]) + 0.03,
		"Walk has a higher quick step than Stroll")
	_expect(float(lifts[&"Run"]) > float(lifts[&"Walk"]) + 0.05,
		"Run has the strongest flight phase")


func _check_jump(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var left: int = skeleton.find_bone(&"foot.L")
	var right: int = skeleton.find_bone(&"foot.R")
	var pelvis: int = skeleton.find_bone(&"pelvis")
	var start: Array[Transform3D] = _pose(player, skeleton, &"Jump", 0.0)
	var idle: Array[Transform3D] = _pose(player, skeleton, &"Idle", 0.0)
	var air: Array[Transform3D] = _pose(player, skeleton, &"Jump", 0.36)
	var landing: Array[Transform3D] = _pose(player, skeleton, &"Jump", 1.0)
	var end: Array[Transform3D] = _pose(player, skeleton, &"Jump", float(DURATIONS[&"Jump"]))
	_expect(air[left].origin.y - start[left].origin.y > 0.12
		and air[right].origin.y - start[right].origin.y > 0.10,
		"Jump has a clear airborne tuck")
	_expect(landing[pelvis].origin.y < start[pelvis].origin.y - 0.10,
		"Jump has a readable landing squash")
	var worst_return: float = 0.0
	for bone: int in idle.size():
		worst_return = maxf(worst_return, end[bone].origin.distance_to(idle[bone].origin))
	_expect(worst_return < 0.002,
		"Jump settles into Idle without a position pop (got %.4f m)" % worst_return)


func _check_turn(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var duration: float = player.get_animation(&"TurnInPlace").length
	var rest: Array[Transform3D] = _pose(player, skeleton, &"TurnInPlace", 0.0)
	var left: int = skeleton.find_bone(&"foot.L")
	var right: int = skeleton.find_bone(&"foot.R")
	var maximum := {left: 0.0, right: 0.0}
	var both_airborne: int = 0
	for sample: int in range(41):
		var pose: Array[Transform3D] = _pose(player, skeleton, &"TurnInPlace", duration * sample / 40.0)
		var left_lift: float = pose[left].origin.y - rest[left].origin.y
		var right_lift: float = pose[right].origin.y - rest[right].origin.y
		maximum[left] = maxf(float(maximum[left]), left_lift)
		maximum[right] = maxf(float(maximum[right]), right_lift)
		both_airborne += int(left_lift > 0.02 and right_lift > 0.02)
	_expect(float(maximum[left]) > 0.04 and float(maximum[right]) > 0.04,
		"TurnInPlace lifts and replants both feet")
	_expect(both_airborne == 0, "TurnInPlace always keeps one foot planted")


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


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
