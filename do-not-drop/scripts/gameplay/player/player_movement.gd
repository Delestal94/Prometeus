extends RefCounted
## What the owning peer does with its body on foot (N-225.5), split out of player.gd: walking, jumping, looking
## around, the footstep bob, the field of view and the rescue from a fall out of the world. The state (`_pitch`,
## `_bob_time`, `_last_safe_ground`, `velocity`...) stays on the Player, which keeps thin wrappers for what the
## tests call (`_apply_look`, `_update_ground_safety`) and the constants the rest of the project reads.

const CHARACTER_STEP := preload("res://modules/character_step/character_step.gd")
const GAME_SETTINGS := preload("res://scripts/core/game_settings.gd")  # What the GameSettings autoload runs.

## Three contexts, three frames -- walking, driving (FirstPersonCamera's own
## BASE_FOV) and carrying a package don't feel like the same view even
## though they used to share one flat 78°.
const WALK_FOV: float = 78.0
const CARRY_FOV: float = 70.0
const FOV_SMOOTH_SPEED: float = 6.0
## Footstep bob: a small vertical sine wave on the camera itself, so a held
## package (which follows the camera's hold point) bobs with it too --
## before this, walking anywhere felt perfectly flat, "on rails."
## Keep the first-person walk almost still. The former values read as a hard
## camera thump rather than natural gait, especially at the short walk speed.
const BOB_AMPLITUDE: float = 0.008
const BOB_FREQUENCY: float = 3.2
const BOB_SMOOTH_SPEED: float = 3.0
const PITCH_LIMIT: float = 1.4  # radians, ~80 degrees


## One physics tick on foot, after the seated and menu cases have returned: interact, assist, look, walk, jump,
## the carried box and the prompt for what is aimed at.
static func on_foot_step(p: Player, delta: float) -> void:
	p._interaction_component.poll_interact()
	if p.assisted_package != null:
		p._cargo_care.update_assisting()
	var stick: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	apply_look(p, stick * p.stick_sensitivity * delta)
	# get_vector's y is -1 for forward and +1 for back;
	# local forward is -Z, so the two negatives cancel out to a plain +basis.z.
	var input_vector: Vector2 = Input.get_vector(&"drive_left", &"drive_right", &"walk_forward", &"walk_backward")
	if Input.is_action_pressed(&"care_work") and p._cargo_care.target != null:
		input_vector = Vector2.ZERO
	# Holding a box that asks for a tap sequence: WASD taps it, not walks.
	if p._cargo_care.tapping:
		input_vector = Vector2.ZERO
	var move_direction: Vector3 = (p.global_basis.x * input_vector.x) + (p.global_basis.z * input_vector.y)
	if move_direction.length() > 1.0:
		move_direction = move_direction.normalized()
	var pace: float = p._sprint.ground_speed(input_vector)
	p.velocity.x = move_direction.x * pace
	p.velocity.z = move_direction.z * pace
	if p.is_on_floor():
		# Keep the body snapped to slopes when walking, but preserve a newly
		# requested jump impulse instead of immediately overwriting it.
		if Input.is_action_just_pressed(&"jump"):
			p.velocity.y = Player.JUMP_VELOCITY
			p.animator.play_one_shot(Player.ANIM_JUMP, Player.JUMP_ANIM_LOCK_MS)
		else:
			p.velocity.y = -0.2
	else:
		p.velocity.y -= Player.GRAVITY * delta
	CHARACTER_STEP.move_and_slide(p, delta)
	update_ground_safety(p)
	var ground_speed: float = Vector2(p.velocity.x, p.velocity.z).length()
	p.locomotion_speed = ground_speed
	p.animator.update_jump(delta, ground_speed)
	apply_head_bob(p, delta, ground_speed)
	p.animator.update_movement(ground_speed, p._pickup_elapsed)
	apply_context_fov(p, delta)
	if p.carried_package != null:
		p._carry_component.update_carried_package()
	var target: Interactable = p._interaction_component.closest_interactable()
	p._interaction_component.publish_prompt(target.get_prompt() if target != null else "")
	p._interaction_component.update_highlight(target)
	p._interaction_component.publish_lid_hint(p._lid_target(target))


static func update_ground_safety(p: Player) -> void:
	# A last grounded position also works on hills, unlike an absolute Y cutoff.
	if p.global_position.y < p._last_safe_ground.y - 15.0:
		p.global_position = p._last_safe_ground + Vector3.UP * 0.5
		p.velocity = Vector3.ZERO
		p.reset_physics_interpolation()  # A rescue, not a fall: no streak between the two spots.
	elif p.is_on_floor():
		p._last_safe_ground = p.global_position


static func apply_look(p: Player, motion: Vector2) -> void:
	# Sensitivity and Y inversion are player settings now (GameSettings), and
	# both get applied in this one place so mouse and stick stay consistent
	# with each other. 1.0 / not-inverted is exactly the tuning this shipped
	# with, so the defaults change nothing.
	var settings: GAME_SETTINGS = p.get_node_or_null(^"/root/GameSettings") as GAME_SETTINGS
	var sensitivity: float = settings.look_sensitivity if settings != null else 1.0
	var y_sign: float = settings.look_y_sign() if settings != null else 1.0
	motion.x *= sensitivity
	motion.y *= sensitivity * y_sign
	p.rotate_y(-motion.x)
	p.animator.add_look_yaw(motion.x)
	p._pitch = clampf(p._pitch - motion.y, -PITCH_LIMIT, PITCH_LIMIT)
	p._head.rotation.x = p._pitch


## Only runs on foot (the seated/driving path returns early above, and
## FirstPersonCamera -- a different node entirely -- has its own shake
## instead). A footstep sine wave that fades in/out with actual ground
## speed rather than snapping on the instant a key is pressed.
static func apply_head_bob(p: Player, delta: float, ground_speed: float) -> void:
	# Do not bob while airborne: the jump already provides the vertical motion.
	var moving: bool = ground_speed > 0.3 and p.is_on_floor()
	var target_amount: float = 1.0 if moving else 0.0
	p._bob_amount = move_toward(p._bob_amount, target_amount, BOB_SMOOTH_SPEED * delta)
	if moving:
		p._bob_time += delta * BOB_FREQUENCY * clampf(ground_speed / Player.WALK_SPEED, 0.45, 1.7)
	# Always write the offset so it eases back to eye height after stopping or
	# jumping; previously it could freeze at the final high/low bob position.
	p._camera.position.y = sin(p._bob_time * TAU) * BOB_AMPLITUDE * p._sprint.bob_scale() * p._bob_amount


static func apply_context_fov(p: Player, delta: float) -> void:
	# The options FOV is the neutral reference. Carrying still narrows the
	# view by the same readable amount, rather than silently ignoring a
	# player's accessibility preference.
	var settings: GAME_SETTINGS = p.get_node_or_null(^"/root/GameSettings") as GAME_SETTINGS
	var preferred_fov: float = settings.preferred_fov if settings != null else 82.0
	var fov_offset: float = preferred_fov - 82.0
	var target_fov: float = (CARRY_FOV if p.carried_package != null else WALK_FOV) + fov_offset + p._sprint.fov_bonus()
	p._camera.fov = move_toward(p._camera.fov, target_fov, FOV_SMOOTH_SPEED * delta)
