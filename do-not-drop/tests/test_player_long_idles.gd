extends SceneTree
## S-311.90: a motionless owner cycles through three authored long idles,
## input/movement cancels them, BlowBubble owns a translucent presentation,
## and the existing anim_clip property remains the only network contract.

const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const DURATIONS: Dictionary = {
	&"InspectHand": 3.4,
	&"BlowBubble": 3.2,
	&"IdleBounce": 2.6,
}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_exported_clips()
	await _check_timer_and_cancellation()
	if _failures == 0:
		print("PASS: three replicated long idles wait, cycle, bubble and cancel on activity")
	quit(_failures)


func _check_exported_clips() -> void:
	var gel: Node3D = GEL_SCENE.instantiate()
	root.add_child(gel)
	await process_frame
	var animation_player: AnimationPlayer = PlayerAppearance.find_animation_player(gel)
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(gel)
	_expect(animation_player != null and skeleton != null, "the real gel exposes its long-idle clips")
	if animation_player != null and skeleton != null:
		for clip: StringName in DURATIONS:
			_expect(animation_player.has_animation(clip), "the gel export contains %s" % clip)
			if animation_player.has_animation(clip):
				_expect(absf(animation_player.get_animation(clip).length - float(DURATIONS[clip])) < 0.02,
					"%s keeps its authored duration" % clip)
		_check_authored_poses(animation_player, skeleton)
	gel.free()


func _check_authored_poses(animation_player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var idle: Array[Transform3D] = _pose(animation_player, skeleton, &"Idle", 0.0)
	var left_hand: int = skeleton.find_bone(&"hand.L")
	var right_hand: int = skeleton.find_bone(&"hand.R")
	var head: int = skeleton.find_bone(&"head")
	var pelvis: int = skeleton.find_bone(&"pelvis")
	var inspect: Array[Transform3D] = _pose(animation_player, skeleton, &"InspectHand", 1.35)
	_expect(inspect[left_hand].origin.distance_to(idle[left_hand].origin) > 0.22
			and inspect[left_hand].origin.distance_to(inspect[head].origin) < 0.65,
		"InspectHand raises the translucent hand into the character's gaze")
	var blowing: Array[Transform3D] = _pose(animation_player, skeleton, &"BlowBubble", 1.3)
	_expect(blowing[left_hand].origin.distance_to(blowing[head].origin) < 0.7
			and blowing[right_hand].origin.distance_to(blowing[head].origin) < 0.7,
		"BlowBubble cups both hands close to the mouth")
	var bounce: Array[Transform3D] = _pose(animation_player, skeleton, &"IdleBounce", 0.66)
	_expect(bounce[pelvis].origin.y > idle[pelvis].origin.y + 0.1,
		"IdleBounce clearly leaves the floor")
	for clip: StringName in DURATIONS:
		var end: Array[Transform3D] = _pose(
			animation_player, skeleton, clip, float(DURATIONS[clip])
		)
		var worst: float = 0.0
		for bone: int in idle.size():
			worst = maxf(worst, end[bone].origin.distance_to(idle[bone].origin))
		_expect(worst < 0.01, "%s returns exactly to Idle" % clip)


func _check_timer_and_cancellation() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	await process_frame
	var animator: PlayerAnimator = player.animator
	_expect(not animator.update_long_idle(PlayerAnimator.LONG_IDLE_DELAY_SECONDS - 0.1, true),
		"the ordinary idle remains quiet before the long-idle delay")
	_expect(animator.update_long_idle(0.11, true) and player.anim_state == &"InspectHand",
		"the first long idle examines the translucent hand after the delay")
	animator.animate()
	_expect(player.anim_clip == &"InspectHand"
			and StringName(animator.anim_player.current_animation) == &"InspectHand",
		"the owner publishes and plays the exact inspect-hand clip")
	animator.note_activity()
	animator.animate()
	_expect(player.anim_state == Player.ANIM_IDLE and player.anim_clip == Player.ANIM_IDLE,
		"input cancels an automatic idle immediately")

	_expect(animator.update_long_idle(PlayerAnimator.LONG_IDLE_DELAY_SECONDS, true)
			and player.anim_state == &"BlowBubble",
		"the next quiet interval selects the bubble idle")
	animator.animate()
	animator.anim_player.seek(1.35, true)
	animator.animate()
	var bubble := player.get_node_or_null(^"LongIdleBubble") as MeshInstance3D
	_expect(bubble != null and bubble.visible and bubble.scale.x > 0.9,
		"BlowBubble grows a translucent bubble in front of the character")
	_expect(PlayerAnimator.idle_bubble_amount(0.4) == 0.0
			and PlayerAnimator.idle_bubble_amount(1.35) > 0.9
			and PlayerAnimator.idle_bubble_amount(2.8) == 0.0,
		"the bubble appears only during the authored blowing beat")
	animator.note_activity()
	animator.animate()
	_expect(bubble != null and not bubble.visible, "leaving BlowBubble hides its presentation")

	_expect(animator.update_long_idle(PlayerAnimator.LONG_IDLE_DELAY_SECONDS, true)
			and player.anim_state == &"IdleBounce",
		"the third quiet interval advances to the in-place bounce")
	animator.update_movement(1.0, 2.0)
	animator.animate()
	_expect(player.anim_state == Player.ANIM_IDLE and player.anim_clip == Player.ANIM_IDLE,
		"movement cancels the long idle instead of sliding its pose")
	var sync := player.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var clip_path := NodePath(".:anim_clip")
	_expect(sync.replication_config.has_property(clip_path)
			and sync.replication_config.property_get_spawn(clip_path)
			and sync.replication_config.property_get_replication_mode(clip_path)
			== SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
		"long idles reuse replicated anim_clip for peers and late joiners")
	player.free()


func _pose(
	animation_player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip: StringName,
	at: float
) -> Array[Transform3D]:
	animation_player.play(clip)
	animation_player.seek(at, true)
	animation_player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var result: Array[Transform3D] = []
	for bone: int in skeleton.get_bone_count():
		result.append(skeleton.get_bone_global_pose(bone))
	return result


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
