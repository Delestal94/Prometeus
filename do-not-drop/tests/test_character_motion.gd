extends SceneTree
## Observable contact/continuity checks on the exported animation, plus real
## package IK. These catch sliding feet and disconnected hands, not clip names.
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var model: Node3D = load("res://assets/models/characters/sm_char_player_rounded.glb").instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = _find(model, "Skeleton3D")
	var animation: AnimationPlayer = _find(model, "AnimationPlayer")
	for clip: String in ["Idle", "Walk", "Stroll", "Sit", "TurnInPlace"]:
		var duration: float = animation.get_animation(clip).length
		var first: Array[Transform3D] = _pose(animation, skeleton, clip, 0.0)
		var last: Array[Transform3D] = _pose(animation, skeleton, clip, duration)
		for bone: int in first.size():
			_expect(first[bone].origin.distance_to(last[bone].origin) < 0.001,
				"%s loop closes its bone positions: %s" % [clip, skeleton.get_bone_name(bone)])
			_expect(first[bone].basis.get_rotation_quaternion().angle_to(last[bone].basis.get_rotation_quaternion()) < 0.005,
				"%s loop closes its bone rotations: %s" % [clip, skeleton.get_bone_name(bone)])
	# The gaits are in place, authored at player.gd's WALK/STROLL_AUTHORED_SPEED.
	# Add the forward travel: the ball of the planted foot (what stays on the
	# floor while the heel lifts) must hold one world spot through the stance.
	# Windows: from the flat foot to just before toe-off (animation_library.py).
	for gait: Array in [["Walk", 3.6, 0.03, 0.105], ["Stroll", 1.5, 0.10, 0.36]]:
		var a: Vector3 = _ball(animation, skeleton, gait[0], gait[2])
		var b: Vector3 = _ball(animation, skeleton, gait[0], gait[3])
		var slip: float = (b + Vector3.FORWARD * float(gait[1]) * (float(gait[3]) - float(gait[2]))).distance_to(a)
		print("MEASURE %s planted-ball drift: %.4f m" % [gait[0], slip])
		_expect(slip < 0.012, "%s planted foot tracks the ground (drift %.4f m)" % [gait[0], slip])
		_expect(absf(a.y - b.y) < 0.006, "%s planted ball keeps its contact height" % gait[0])
		# player.gd keeps the phase when switching gaits: both must start on
		# the left foot's touchdown, left foot ahead.
		# (World space: the export keeps its turn and scale on the armature node.)
		var start: Array[Transform3D] = _pose(animation, skeleton, gait[0], 0.0)
		var left: Vector3 = skeleton.to_global(start[skeleton.find_bone("foot.L")].origin)
		var right: Vector3 = skeleton.to_global(start[skeleton.find_bone("foot.R")].origin)
		_expect(left.z < right.z, "%s starts on the left foot's touchdown" % gait[0])
	# FK arms come from drivers baked at export: a lost driver leaves them still.
	var hand: int = skeleton.find_bone("hand.L")
	var swing: float = skeleton.to_global(_pose(animation, skeleton, "Walk", 0.0)[hand].origin).distance_to(
		skeleton.to_global(_pose(animation, skeleton, "Walk", animation.get_animation("Walk").length * 0.5)[hand].origin))
	print("MEASURE Walk hand swing: %.3f m" % swing)
	_expect(swing > 0.12, "Walk swings the arms (%.3f m)" % swing)
	# Jump hands over to Idle without a pop when its lock releases.
	var landed: Array[Transform3D] = _pose(animation, skeleton, "Jump", animation.get_animation("Jump").length)
	var idle: Array[Transform3D] = _pose(animation, skeleton, "Idle", 0.0)
	var worst: float = 0.0
	for bone: int in idle.size():
		worst = maxf(worst, landed[bone].origin.distance_to(idle[bone].origin))
	_expect(worst < 0.002, "Jump ends on Idle's first frame (%.4f m)" % worst)
	model.free()

	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var package: Node3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	root.add_child(package)
	package.freeze = true
	package.take_by(player)
	player._pickup_elapsed = 2.0
	player._update_carried_package()
	skeleton = player._find_skeleton(player.get_node("BodyVisual"))
	var wrists: Dictionary = {}
	var capture: Callable = func() -> void:
		for side: String in ["L", "R"]:
			wrists[side] = skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("hand." + side)).origin)
	skeleton.skeleton_updated.connect(capture)
	for i: int in range(40): await process_frame
	for side: String in ["L", "R"]:
		var target := player.find_child("PackageGrip" + side, true, false) as Marker3D
		_expect(target != null and wrists.has(side), "Package hand target is evaluated")
		if target != null and wrists.has(side):
			var gap: float = target.global_position.distance_to(wrists[side])
			print("MEASURE package wrist gap ", side, ": ", gap)
			_expect(gap < 0.075, "Hand %s reaches the actual package (%.3f m)" % [side, gap])
	player.carried_package = null
	for i: int in range(40): await process_frame
	_expect(player.find_child("PackageGripL", true, false) == null, "Dropping clears carry IK targets")
	skeleton.skeleton_updated.disconnect(capture)
	package.free(); player.free()
	if _failures == 0: print("PASS: animation loop continuity, planted-foot contact and actual carried-package wrist contact")
	quit(_failures)

func _pose(animation: AnimationPlayer, skeleton: Skeleton3D, clip: String, at: float) -> Array[Transform3D]:
	animation.play(clip)
	animation.seek(at, true)
	animation.advance(0)
	skeleton.force_update_all_bone_transforms()
	var result: Array[Transform3D] = []
	for bone: int in skeleton.get_bone_count(): result.append(skeleton.get_bone_global_pose(bone))
	return result

## The ball of the left foot in world space: 0.12 m ahead of (-Z, the way the
## character faces) and 0.11 m below the ankle at rest (animation_library.BALL
## at game scale), carried by the foot bone. Worked out in world space because
## the armature node, not the bones, carries the export's turn and scale.
func _ball(animation: AnimationPlayer, skeleton: Skeleton3D, clip: String, at: float) -> Vector3:
	var foot: int = skeleton.find_bone("foot.L")
	var rest: Transform3D = skeleton.global_transform * skeleton.get_bone_global_rest(foot)
	var local: Vector3 = rest.affine_inverse() * (rest.origin + Vector3(0.0, -0.1135, -0.1225))
	return skeleton.global_transform * _pose(animation, skeleton, clip, at)[foot] * local

func _find(node: Node, kind: String) -> Node:
	if node.is_class(kind): return node
	for child: Node in node.get_children():
		var found: Node = _find(child, kind)
		if found != null: return found
	return null

func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_failures += 1
