class_name PlayerAnimator
extends RefCounted
## The player's animation, in two halves with different authority:
##
## - State (owning peer only): picks anim_state -- Idle, Walk, TurnInPlace, or
##   a one-shot (Jump, PickUpPackage) that locks it for a moment -- and the
##   jump's sampled time. Player replicates both through its
##   MultiplayerSynchronizer; nothing here is synced on its own.
## - Playback (every peer): turns the replicated anim_state into the clip
##   that actually plays -- the gait for the speed, the pickup blend for the
##   box's height -- keeping the step phase across gait changes.
##
## Only reads and writes the Player's public state.

## Gait clips: played at speed / authored speed, the planted feet keep pace
## with the ground. Hysteresis between them, so a stick held near one speed
## doesn't flicker.
const WALK_AUTHORED_SPEED: float = 3.6
const STROLL_AUTHORED_SPEED: float = 1.5
const STROLL_BELOW: float = 2.2
const WALK_ABOVE: float = 2.6
## Pickup blends between PickUpPackage and PickUpHigh, baked once per step.
const PICKUP_BLEND_STEPS: int = 8
const PICKUP_BLEND_LIBRARY: StringName = &"pickup_blend"
## Small steps in place while the player turns standing still. Rates in
## rad/s, smoothed; hysteresis so a mouse flick doesn't flicker it. Turning
## with the truck the player rides in doesn't count: the floor turns too.
const TURN_STEP_ABOVE: float = 1.5
const TURN_STEP_BELOW: float = 0.8
const TURN_RATE_SMOOTHING: float = 10.0
## Under this ground speed (m/s) the player stands (Idle), over it walks.
const IDLE_BELOW_SPEED: float = 0.3
## Clips that loop (the glTF importer drops Blender's loop flag).
const LOOPING: Array[StringName] = [
	Player.ANIM_IDLE, Player.ANIM_WALK, Player.ANIM_STROLL, Player.ANIM_SIT, Player.ANIM_TURN]

## The character's AnimationPlayer; null for a model without one (state still runs).
var anim_player: AnimationPlayer

var _player: Player
var _face: Node
var _strolling: bool = false
## Last jump_anim_time seen here, to catch the touchdown (0.9) on every peer.
var _seen_jump_time: float = 0.0
## Look yaw applied since the last physics tick (owner only).
var _turn_yaw: float = 0.0
## While in the future (Time.get_ticks_msec()), a one-shot clip is playing and
## the per-frame movement state (Idle/Walk) must not stomp over it.
var _anim_lock_until_msec: int = 0
var _jump_airborne: bool = false
var _jump_landing_elapsed: float = -1.0


func _init(player: Player, animation_player: AnimationPlayer, face: Node) -> void:
	_player = player
	_face = face
	anim_player = animation_player
	if anim_player == null:
		return
	for loop_clip: StringName in LOOPING:
		if anim_player.has_animation(loop_clip):
			anim_player.get_animation(loop_clip).loop_mode = Animation.LOOP_LINEAR
	anim_player.play(Player.ANIM_IDLE)


# --- State (owning peer) --------------------------------------------------------


func add_look_yaw(yaw: float) -> void:
	_turn_yaw += yaw


## Idle/Walk while on foot, unless a one-shot (Jump, PickUpPackage) locked
## anim_state a moment ago -- checked every physics frame but only actually
## writes (and re-replicates) anim_state when the target state changes.
func update_movement(ground_speed: float, pickup_elapsed: float) -> void:
	measure_turn_rate(_player.get_physics_process_delta_time())
	# An interrupted pickup must not make a moving player slide on its
	# planted crouch. The package lift and hand contact continue independently.
	if _player.anim_state == Player.ANIM_PICKUP and ground_speed > 0.3 and pickup_elapsed > 0.16:
		_anim_lock_until_msec = 0
	if _player.anim_state == Player.ANIM_JUMP and _jump_airborne:
		return
	if Time.get_ticks_msec() < _anim_lock_until_msec:
		return
	var turning: bool = _player.anim_state == Player.ANIM_TURN
	var next_state: StringName = movement_state(ground_speed, _player.is_on_floor(), _player.turn_rate, turning)
	if _player.anim_state != next_state:
		_player.anim_state = next_state


## Walk when moving on the floor; standing, TurnInPlace while turning faster
## than TURN_STEP_ABOVE (until it drops under TURN_STEP_BELOW), else Idle.
static func movement_state(ground_speed: float, on_floor: bool, rate: float, turning: bool) -> StringName:
	if ground_speed > IDLE_BELOW_SPEED and on_floor:
		return Player.ANIM_WALK
	if on_floor and rate > (TURN_STEP_BELOW if turning else TURN_STEP_ABOVE):
		return Player.ANIM_TURN
	return Player.ANIM_IDLE


## The yaw rate of the body (which carries BodyVisual) from the look input
## since the last tick, smoothed: mouse motion lands in bursts between ticks.
func measure_turn_rate(delta: float) -> void:
	if delta <= 0.0:
		return
	var rate: float = absf(_turn_yaw) / delta
	_turn_yaw = 0.0
	_player.turn_rate = lerpf(_player.turn_rate, rate, 1.0 - exp(-TURN_RATE_SMOOTHING * delta))


func play_one_shot(clip: StringName, lock_ms: int) -> void:
	_player.anim_state = clip
	_anim_lock_until_msec = Time.get_ticks_msec() + lock_ms
	if clip == Player.ANIM_JUMP:
		_jump_airborne = true
		_jump_landing_elapsed = -1.0
		_player.jump_anim_time = 0.0


## Lets movement take anim_state back right away.
func release_lock() -> void:
	_anim_lock_until_msec = 0


## Samples the jump clip from the real ascent and landing instead of playing
## a crouch after leaving the floor.
func update_jump(delta: float, ground_speed: float) -> void:
	if _player.anim_state != Player.ANIM_JUMP:
		# Also pose an unplanned fall from a ledge, without changing physics.
		if not _player.is_on_floor() and _player.velocity.y < -1.0 and _player.anim_state != Player.ANIM_PICKUP:
			play_one_shot(Player.ANIM_JUMP, Player.JUMP_ANIM_LOCK_MS)
		else:
			return
	if not _player.is_on_floor():
		_jump_airborne = true
		_jump_landing_elapsed = -1.0
		var rise: float = _player.velocity.y / Player.JUMP_VELOCITY
		if _player.velocity.y >= 0.0:
			_player.jump_anim_time = lerpf(0.0, 0.4, clampf(1.0 - rise, 0.0, 1.0))
		else:
			_player.jump_anim_time = lerpf(0.4, 0.84, clampf(-rise, 0.0, 1.0))
	else:
		_jump_landing_elapsed = maxf(_jump_landing_elapsed, 0.0) + delta
		_player.jump_anim_time = minf(1.6, 0.9 + _jump_landing_elapsed)
		if _jump_landing_elapsed >= (0.24 if ground_speed > 0.3 else 0.65):
			_jump_airborne = false
			_anim_lock_until_msec = 0


# --- Playback (every peer) ------------------------------------------------------


## Runs for every peer's copy of the player, local or not -- anim_state is
## only ever written by the owning peer and reaches everyone else through the
## MultiplayerSynchronizer, same as seat_node_path.
func animate() -> void:
	if anim_player == null:
		return
	var clip: StringName = _player.anim_state if _player.seat_node_path.is_empty() else Player.ANIM_SIT
	if clip == Player.ANIM_WALK:
		clip = _gait_clip()
	elif clip == Player.ANIM_PICKUP:
		clip = pickup_clip()
	elif clip == Player.ANIM_TURN and not anim_player.has_animation(Player.ANIM_TURN):
		clip = Player.ANIM_IDLE
	if anim_player.current_animation != String(clip):
		_play_clip(clip)
	if clip == Player.ANIM_JUMP:
		anim_player.speed_scale = 0.0
		anim_player.seek(_player.jump_anim_time, true)
		# The eyes squeeze shut as the landing's squash hits.
		if _player.jump_anim_time >= 0.9 and _seen_jump_time < 0.9 and _face != null:
			_face.call(&"blink")
		_seen_jump_time = _player.jump_anim_time
	elif clip == Player.ANIM_WALK:
		anim_player.speed_scale = clampf(_player.locomotion_speed / WALK_AUTHORED_SPEED, 0.5, 1.5)
	elif clip == Player.ANIM_STROLL:
		anim_player.speed_scale = clampf(_player.locomotion_speed / STROLL_AUTHORED_SPEED, 0.2, 1.6)
	else:
		anim_player.speed_scale = 1.0


## The pickup clip for the player's pickup_high_weight: either authored clip
## at the ends, a baked blend of both in between (quantised, so at most a
## handful exist).
func pickup_clip() -> StringName:
	var step: int = roundi(_player.pickup_high_weight * PICKUP_BLEND_STEPS)
	if step <= 0 or not anim_player.has_animation(Player.ANIM_PICKUP_HIGH):
		return Player.ANIM_PICKUP
	if step >= PICKUP_BLEND_STEPS:
		return Player.ANIM_PICKUP_HIGH
	var blend_name := StringName("%s/%d" % [PICKUP_BLEND_LIBRARY, step])
	if not anim_player.has_animation(blend_name):
		if not anim_player.has_animation_library(PICKUP_BLEND_LIBRARY):
			anim_player.add_animation_library(PICKUP_BLEND_LIBRARY, AnimationLibrary.new())
		var blended: Animation = blend_clips(anim_player.get_animation(Player.ANIM_PICKUP),
				anim_player.get_animation(Player.ANIM_PICKUP_HIGH), float(step) / PICKUP_BLEND_STEPS)
		anim_player.get_animation_library(PICKUP_BLEND_LIBRARY).add_animation(StringName(str(step)), blended)
	return blend_name


## low blended toward high by weight, bone by bone, sampled at 30 Hz (the
## export's rate). Tracks high lacks, and non-transform tracks, come from low.
static func blend_clips(low: Animation, high: Animation, weight: float) -> Animation:
	var out := Animation.new()
	out.length = low.length
	var frames: int = ceili(low.length * 30.0)
	for track: int in low.get_track_count():
		var type: Animation.TrackType = low.track_get_type(track)
		var other: int = high.find_track(low.track_get_path(track), type)
		var index: int = out.add_track(type)
		out.track_set_path(index, low.track_get_path(track))
		out.track_set_interpolation_type(index, low.track_get_interpolation_type(track))
		var transform_track: bool = type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D,
				Animation.TYPE_SCALE_3D]
		if other < 0 or not transform_track:
			for key: int in low.track_get_key_count(track):
				out.track_insert_key(index, low.track_get_key_time(track, key), low.track_get_key_value(track, key))
			continue
		for frame: int in frames + 1:
			var t: float = minf(frame / 30.0, low.length)
			match type:
				Animation.TYPE_POSITION_3D:
					var position: Vector3 = low.position_track_interpolate(track, t)
					out.position_track_insert_key(index, t,
							position.lerp(high.position_track_interpolate(other, t), weight))
				Animation.TYPE_ROTATION_3D:
					var rotation: Quaternion = low.rotation_track_interpolate(track, t)
					out.rotation_track_insert_key(index, t,
							rotation.slerp(high.rotation_track_interpolate(other, t), weight))
				Animation.TYPE_SCALE_3D:
					var scale: Vector3 = low.scale_track_interpolate(track, t)
					out.scale_track_insert_key(index, t, scale.lerp(high.scale_track_interpolate(other, t), weight))
	return out


## Walk (a quick short-legged run) at full speed, Stroll for partial stick
## input: the run played slowly reads as slow motion, not as walking.
func _gait_clip() -> StringName:
	if _strolling and _player.locomotion_speed > WALK_ABOVE:
		_strolling = false
	elif not _strolling and _player.locomotion_speed < STROLL_BELOW:
		_strolling = true
	return Player.ANIM_STROLL if _strolling and anim_player.has_animation(Player.ANIM_STROLL) else Player.ANIM_WALK


## Both gaits start on the left foot's touchdown, so switching between them
## keeps the cycle phase: the feet carry on instead of skating to a new step.
func _play_clip(clip: StringName) -> void:
	var gaits: Array[String] = [String(Player.ANIM_WALK), String(Player.ANIM_STROLL)]
	var phase: float = -1.0
	if anim_player.current_animation in gaits and String(clip) in gaits:
		phase = anim_player.current_animation_position / maxf(anim_player.current_animation_length, 0.001)
	# A pickup whose height arrives late (anim_state replicated before the
	# pick_up RPC) swaps blends in place instead of restarting the squat.
	var pickup_time: float = -1.0
	if _is_pickup_clip(StringName(anim_player.current_animation)) and _is_pickup_clip(clip):
		pickup_time = anim_player.current_animation_position
	# Idle <-> TurnInPlace blend a little longer: a step cut short settles.
	var turn_blend: bool = clip == Player.ANIM_TURN or anim_player.current_animation == String(Player.ANIM_TURN)
	anim_player.play(String(clip), 0.2 if phase >= 0.0 or turn_blend else 0.15)
	if phase >= 0.0:
		anim_player.seek(phase * anim_player.current_animation_length)
	elif pickup_time >= 0.0:
		anim_player.seek(pickup_time)


func _is_pickup_clip(clip: StringName) -> bool:
	return clip == Player.ANIM_PICKUP or clip == Player.ANIM_PICKUP_HIGH \
			or String(clip).begins_with(String(PICKUP_BLEND_LIBRARY) + "/")
