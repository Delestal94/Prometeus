extends SceneTree
## S-311.80: the runtime resolves replicated player state into the authored
## gel clips, preserves gait phase, applies deliberate cross-fades and follows
## the replicated leg length used by the visible rig.

const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const MotionFit := preload("res://scripts/gameplay/player/gel/gel_animation_fit.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	await process_frame
	player.set_process(false)
	player.set_physics_process(false)
	var animation: AnimationPlayer = PlayerAppearance.find_animation_player(player.get_node(^"BodyVisual"))
	var animator: PlayerAnimator = player.animator
	_expect(animation != null and animator != null, "the active player exposes its animation state machine")
	if animation != null and animator != null:
		_check_clip_resolution(player, animation, animator)
		_check_transition_policy()
		_check_live_leg_length(player, animation, animator)
	player.free()
	if _failures == 0:
		print("PASS: PlayerAnimator resolves gameplay states, blends and proportioned gait timing")
	quit(_failures)


func _check_clip_resolution(
	player: Player,
	animation: AnimationPlayer,
	animator: PlayerAnimator
) -> void:
	player.anim_state = Player.ANIM_WALK
	player.locomotion_speed = PlayerAnimator.WALK_AUTHORED_SPEED
	animator.animate()
	_expect(animation.current_animation == String(Player.ANIM_WALK), "walking resolves to Walk")

	var package: DeliveryPackage = PACKAGE_SCENE.instantiate()
	root.add_child(package)
	player.carried_package = package
	animation.seek(0.12, true)
	var phase: float = animation.current_animation_position / animation.current_animation_length
	animator.animate()
	_expect(animation.current_animation == String(PlayerAnimator.ANIM_CARRY_WALK),
		"walking with a package resolves to CarryWalk")
	_expect(absf(animation.current_animation_position / animation.current_animation_length - phase) < 0.01,
		"entering CarryWalk preserves the planted-foot phase")

	animation.seek(0.21, true)
	phase = animation.current_animation_position / animation.current_animation_length
	player.carried_package = null
	animator.animate()
	_expect(animation.current_animation == String(Player.ANIM_WALK),
		"dropping the package returns to Walk")
	_expect(absf(animation.current_animation_position / animation.current_animation_length - phase) < 0.01,
		"leaving CarryWalk preserves the planted-foot phase")
	package.free()

	player.seat_node_path = ^"CabinInterior/DriverEyePoint"
	animator.animate()
	_expect(animation.current_animation == String(PlayerAnimator.ANIM_DRIVE), "the driver resolves to Drive")
	player.seat_node_path = ^"CabinInterior/CenterSeatEyePoint"
	animator.animate()
	_expect(animation.current_animation == String(Player.ANIM_SIT), "a passenger resolves to Sit")

	player.seat_node_path = NodePath()
	player.anim_state = PlayerAnimator.ANIM_STUMBLE
	animator.animate()
	_expect(animation.current_animation == String(PlayerAnimator.ANIM_STUMBLE), "a trip resolves to Stumble")
	player.anim_state = PlayerAnimator.ANIM_BOX_HIT
	animator.animate()
	_expect(animation.current_animation == String(PlayerAnimator.ANIM_BOX_HIT), "a package impact resolves to BoxHit")


func _check_transition_policy() -> void:
	_expect(PlayerAnimator.transition_blend_time(Player.ANIM_WALK, PlayerAnimator.ANIM_CARRY_WALK)
		== PlayerAnimator.GAIT_BLEND, "gaits use their short phase-preserving blend")
	_expect(PlayerAnimator.transition_blend_time(Player.ANIM_IDLE, Player.ANIM_WALK)
		== PlayerAnimator.LOCOMOTION_BLEND, "starting locomotion eases in")
	_expect(PlayerAnimator.transition_blend_time(Player.ANIM_WALK, PlayerAnimator.ANIM_STUMBLE)
		== PlayerAnimator.REACTION_IN_BLEND, "impacts enter quickly")
	_expect(PlayerAnimator.transition_blend_time(PlayerAnimator.ANIM_STUMBLE, Player.ANIM_WALK)
		== PlayerAnimator.REACTION_OUT_BLEND, "reactions settle back into locomotion")
	_expect(PlayerAnimator.transition_blend_time(Player.ANIM_IDLE, PlayerAnimator.ANIM_DRIVE)
		== PlayerAnimator.SEAT_BLEND, "boarding uses the longest body transition")


func _check_live_leg_length(
	player: Player,
	animation: AnimationPlayer,
	animator: PlayerAnimator
) -> void:
	var proportions := Proportions.new()
	proportions.leg_length = 1.25
	var state := player.get_node(^"GelProportions") as PlayerGelProportionSync
	state.packet = proportions.to_packet()
	player.anim_state = Player.ANIM_WALK
	player.locomotion_speed = PlayerAnimator.WALK_AUTHORED_SPEED
	animator.animate()
	_expect(absf(animator.leg_length_factor() - 1.25) < 0.01,
		"the animator receives the live replicated 1.25 leg length")
	var expected_scale: float = 1.0 / MotionFit.stride_factor(1.25)
	_expect(absf(animation.speed_scale - expected_scale) < 0.01,
		"the measured IK-foot stride calibrates live gait tempo")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
