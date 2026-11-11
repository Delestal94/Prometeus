extends SceneTree
## S-311.91: delivery results select VictoryDance, failed results select the
## authored Defeat loop, and the local owner publishes that exact clip through
## the existing replicated animation properties.

const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_authored_clips()
	await _check_results_integration()
	if _failures == 0:
		print("PASS: delivery victory and result defeat are authored, stable and replicated")
	quit(_failures)


func _check_authored_clips() -> void:
	var gel: Node3D = GEL_SCENE.instantiate()
	root.add_child(gel)
	await process_frame
	var animation_player: AnimationPlayer = PlayerAppearance.find_animation_player(gel)
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(gel)
	_expect(animation_player != null and skeleton != null,
		"the real gel exposes the result reaction clips")
	if animation_player != null and skeleton != null:
		_expect(animation_player.has_animation(PlayerAnimator.ANIM_VICTORY)
				and animation_player.has_animation(PlayerAnimator.ANIM_DEFEAT),
			"the gel export contains VictoryDance and Defeat")
		_expect(absf(animation_player.get_animation(PlayerAnimator.ANIM_VICTORY).length - 2.8) < 0.02
				and absf(animation_player.get_animation(PlayerAnimator.ANIM_DEFEAT).length - 3.0) < 0.02,
			"result clips keep their authored durations")
		var idle: Array[Transform3D] = _pose(animation_player, skeleton, &"Idle", 0.0)
		var victory: Array[Transform3D] = _pose(animation_player, skeleton,
			PlayerAnimator.ANIM_VICTORY, 0.35)
		var defeat: Array[Transform3D] = _pose(animation_player, skeleton,
			PlayerAnimator.ANIM_DEFEAT, 1.5)
		var head: int = skeleton.find_bone(&"head")
		var chest: int = skeleton.find_bone(&"chest")
		var left_hand: int = skeleton.find_bone(&"hand.L")
		var right_hand: int = skeleton.find_bone(&"hand.R")
		_expect(victory[left_hand].origin.y > idle[left_hand].origin.y + 0.15
				and victory[right_hand].origin.y > idle[right_hand].origin.y + 0.15,
			"VictoryDance lifts both open arms into a readable victory V")
		_expect(defeat[head].basis.get_rotation_quaternion().angle_to(
				idle[head].basis.get_rotation_quaternion()) > 0.2
				and defeat[chest].basis.get_rotation_quaternion().angle_to(
				idle[chest].basis.get_rotation_quaternion()) > 0.15,
			"Defeat visibly drops the head and chest")
	gel.free()


func _check_results_integration() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	await process_frame
	_expect(player.is_in_group(&"player") and player.is_local(),
		"results can identify this peer's owning player")
	_expect(PlayerAnimator.play_local_result(self, true),
		"a delivered result starts the owner celebration")
	player.animator.animate()
	_expect(player.anim_state == PlayerAnimator.ANIM_VICTORY
			and player.anim_clip == PlayerAnimator.ANIM_VICTORY
			and StringName(player.animator.anim_player.current_animation)
			== PlayerAnimator.ANIM_VICTORY,
		"delivery publishes and plays VictoryDance")
	_expect(PlayerAnimator.play_local_result(self, false),
		"a failed result starts the owner defeat")
	player.animator.animate()
	player.animator.update_movement(6.0, 0.0)
	player.animator.animate()
	_expect(player.anim_state == PlayerAnimator.ANIM_DEFEAT
			and player.anim_clip == PlayerAnimator.ANIM_DEFEAT
			and StringName(player.animator.anim_player.current_animation)
			== PlayerAnimator.ANIM_DEFEAT,
		"movement behind the result card cannot replace the defeat loop")
	player.seat_node_path = ^"DriverEyePoint"
	player.animator.animate()
	_expect(player.anim_clip == PlayerAnimator.ANIM_DEFEAT,
		"the result reaction takes precedence over a leftover seat pose")
	_expect(player.animator.anim_player.get_animation(PlayerAnimator.ANIM_DEFEAT).loop_mode
			== Animation.LOOP_LINEAR,
		"Defeat remains posed for as long as results are open")
	var sync := player.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	for property: NodePath in [NodePath(".:anim_state"), NodePath(".:anim_clip")]:
		_expect(sync.replication_config.has_property(property)
				and sync.replication_config.property_get_spawn(property)
				and sync.replication_config.property_get_replication_mode(property)
				== SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
			"%s carries the result reaction to peers and late joiners" % property)
	var hud_source: String = FileAccess.get_file_as_string(
		"res://scripts/ui/hud/hud_results.gd")
	_expect(hud_source.contains('results.has("delivered")')
			and hud_source.contains('_play_result_reaction(bool(results["delivered"]))')
			and hud_source.contains("PlayerAnimator.play_local_result"),
		"HudResults dispatches only delivery outcomes through the tested owner path")
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
