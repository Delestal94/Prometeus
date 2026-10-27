class_name PlayerAnimator
extends RefCounted
## The player's animation, in two halves with different authority:
##
## - State (owning peer only): picks anim_state -- Idle, Walk, TurnInPlace, or
##   a one-shot (Jump, PickUpPackage) that locks it for a moment -- and the
##   jump's sampled time. Player replicates both through its
##   MultiplayerSynchronizer; nothing here is synced on its own.
## - Clip choice (owning peer only): turns that state into the exact clip --
##   the gait for the speed, the pickup blend for the box's height -- and
##   publishes anim_clip through Player's MultiplayerSynchronizer.
## - Playback (every peer): plays only replicated anim_clip, keeping the step
##   phase across gait changes. Remote copies never infer a clip from local
##   carried-package timing or their own gait hysteresis.
##
## Only reads and writes the Player's public state.

## Gait clips: played at speed / authored speed, the planted feet keep pace
## with the ground. Hysteresis between them, so a stick held near one speed
## doesn't flicker.
const WALK_AUTHORED_SPEED: float = 3.6
const STROLL_AUTHORED_SPEED: float = 1.5
const STROLL_BELOW: float = 2.2
const WALK_ABOVE: float = 2.6
## Run (N-115): the owner switches Walk -> Run above RUN_ABOVE and back under
## RUN_BELOW, so a pace held near the boundary doesn't flicker. The jog with a
## Growing weight box (4.2 m/s) stays a fast Walk. The rounded character's Run
## (animation_library.py) is authored at RUN_AUTHORED_SPEED: 6 steps/s of 1 m.
## Its playback scale spans RUN_BELOW..RUN_AUTHORED_SPEED*1.3 so the planted foot
## keeps pace down to the switch back to Walk. Without a "Run" clip in the
## library (another model), Walk plays faster instead, up to RUN_FALLBACK_MAX_SCALE.
const RUN_AUTHORED_SPEED: float = 6.0
const RUN_ABOVE: float = 4.6
const RUN_BELOW: float = 4.0
const RUN_MIN_SCALE: float = RUN_BELOW / RUN_AUTHORED_SPEED
const RUN_FALLBACK_MAX_SCALE: float = 1.9
## Pickup blends between PickUpPackage and PickUpHigh, baked once per step.
const PICKUP_BLEND_STEPS: int = 8
const PICKUP_BLEND_LIBRARY: StringName = &"pickup_blend"
## Small steps in place while the player turns standing still. Rates in
## rad/s, smoothed; hysteresis so a mouse flick doesn't flicker it. Turning
## with the truck the player rides in doesn't count: the floor turns too.
const TURN_STEP_ABOVE: float = 1.5
const TURN_STEP_BELOW: float = 0.8
const TURN_RATE_SMOOTHING: float = 10.0
const GelMotionFit = preload("res://scripts/gameplay/player/gel/gel_animation_fit.gd")
const EmoteCatalogData = preload("res://scripts/core/emote_catalog.gd")
const RenderLayers = preload("res://scripts/core/render_layers.gd")
const ANIM_DRIVE: StringName = &"Drive"
const ANIM_CARRY_WALK: StringName = &"CarryWalk"
const ANIM_STUMBLE: StringName = &"Stumble"
const ANIM_BOX_HIT: StringName = &"BoxHit"
const ANIM_CONGA: StringName = &"Conga"
const EMOTE_CLIPS: Array[StringName] = [
	&"Wave", &"Clap", &"Facepalm", &"Shrug", &"Point", &"ThumbsUp",
	&"MeltAndReturn", &"ShakeLikeDog",
]
const DANCE_CLIPS: Array[StringName] = [
	&"SimpleStep", &"Robot", &"Disco", &"FloorWorm", &"Headbang",
	&"VictoryDance", &"Flan", ANIM_CONGA,
]
const LONG_IDLE_CLIPS: Array[StringName] = [&"InspectHand", &"BlowBubble", &"IdleBounce"]
const LONG_IDLE_DURATIONS: Dictionary = {
	&"InspectHand": 3.4,
	&"BlowBubble": 3.2,
	&"IdleBounce": 2.6,
}
const LONG_IDLE_DELAY_SECONDS: float = 15.0
## Players already replicate the selected clip. Conga only needs a shared
## presentation phase on each peer so nearby dancers visibly step together.
const CONGA_SYNC_RADIUS: float = 4.0
const STUMBLE_ANIM_LOCK_MS: int = 1050
const BOX_HIT_ANIM_LOCK_MS: int = 650
## Under this ground speed (m/s) the player stands (Idle), over it walks.
const IDLE_BELOW_SPEED: float = 0.3
## Clips that loop (the glTF importer drops Blender's loop flag).
const LOOPING: Array[StringName] = [
	Player.ANIM_IDLE, Player.ANIM_WALK, Player.ANIM_STROLL, Player.ANIM_RUN,
	ANIM_CARRY_WALK, Player.ANIM_SIT, ANIM_DRIVE, Player.ANIM_TURN,
] + DANCE_CLIPS
const GAIT_CLIPS: Array[StringName] = [
	Player.ANIM_WALK, Player.ANIM_STROLL, Player.ANIM_RUN, ANIM_CARRY_WALK]
const REACTION_CLIPS: Array[StringName] = [
	ANIM_STUMBLE, &"Slip", &"Pushed", ANIM_BOX_HIT,
	&"Scared", &"Dizzy", &"ShakeOffWater"]
## Cross-fades are short into impacts, slower while settling out, and phase
## preserving between gaits. Keeping the policy here makes every peer apply
## the same authored timing to the replicated state.
const GAIT_BLEND: float = 0.12
const LOCOMOTION_BLEND: float = 0.18
const TURN_BLEND: float = 0.20
const ONE_SHOT_BLEND: float = 0.14
const REACTION_IN_BLEND: float = 0.06
const REACTION_OUT_BLEND: float = 0.18
const SEAT_BLEND: float = 0.24

## The character's AnimationPlayer; null for a model without one (state still runs).
var anim_player: AnimationPlayer

var _player: Player
var _face: Node
var _strolling: bool = false
## Owner: past RUN_ABOVE and not yet back under RUN_BELOW.
var _running_gait: bool = false
## Last jump_anim_time seen here, to catch the touchdown (0.9) on every peer.
var _seen_jump_time: float = 0.0
## Look yaw applied since the last physics tick (owner only).
var _turn_yaw: float = 0.0
## While in the future (Time.get_ticks_msec()), a one-shot clip is playing and
## the per-frame movement state (Idle/Walk) must not stomp over it.
var _anim_lock_until_msec: int = 0
var _jump_airborne: bool = false
var _jump_landing_elapsed: float = -1.0
## Replicated presentation factor. The authored IK targets retain their
## horizontal stride at every value; GelMotionFit therefore keeps gait tempo
## tied to ground speed while the longer/shorter leg rests change reach.
var _leg_length_factor: float = 1.0
var _long_idle_elapsed: float = 0.0
var _long_idle_index: int = 0
var _idle_bubble: MeshInstance3D


func _init(player: Player, animation_player: AnimationPlayer, face: Node) -> void:
	_player = player
	_face = face
	anim_player = animation_player
	var gel_state := _player.get_node_or_null(^"GelProportions") as PlayerGelProportionSync
	if gel_state != null:
		_fit_to_proportions(gel_state.proportions)
		gel_state.proportions_changed.connect(_fit_to_proportions)
	if anim_player == null:
		return
	for loop_clip: StringName in LOOPING:
		if anim_player.has_animation(loop_clip):
			anim_player.get_animation(loop_clip).loop_mode = Animation.LOOP_LINEAR
	anim_player.play(Player.ANIM_IDLE)
	_build_idle_bubble()


# --- State (owning peer) --------------------------------------------------------


func add_look_yaw(yaw: float) -> void:
	_turn_yaw += yaw


## Idle/Walk while on foot, unless a one-shot (Jump, PickUpPackage) locked
## anim_state a moment ago -- checked every physics frame but only actually
## writes (and re-replicates) anim_state when the target state changes.
func update_movement(ground_speed: float, pickup_elapsed: float) -> void:
	measure_turn_rate(_player.get_physics_process_delta_time())
	var active_motion: bool = ground_speed > IDLE_BELOW_SPEED or _player.turn_rate > TURN_STEP_BELOW
	if active_motion:
		note_activity()
	var long_idle_eligible: bool = not active_motion and _player.is_on_floor() \
			and _player.seat_node_path.is_empty() and not is_instance_valid(_player.carried_package)
	if update_long_idle(_player.get_physics_process_delta_time(), long_idle_eligible):
		return
	# Emotes are deliberate standing poses. Moving cancels them immediately
	# instead of sliding the character around on a planted full-body pose.
	if _player.anim_state in EMOTE_CLIPS and ground_speed > IDLE_BELOW_SPEED:
		_anim_lock_until_msec = 0
	# An interrupted pickup must not make a moving player slide on its
	# planted crouch. The package lift and hand contact continue independently.
	if _player.anim_state == Player.ANIM_PICKUP and ground_speed > 0.3 and pickup_elapsed > 0.16:
		_anim_lock_until_msec = 0
	if _player.anim_state == Player.ANIM_JUMP and _jump_airborne:
		return
	if Time.get_ticks_msec() < _anim_lock_until_msec:
		return
	var turning: bool = _player.anim_state == Player.ANIM_TURN
	if _running_gait and ground_speed < RUN_BELOW:
		_running_gait = false
	elif not _running_gait and ground_speed > RUN_ABOVE:
		_running_gait = true
	var next_state: StringName = movement_state(ground_speed, _player.is_on_floor(), _player.turn_rate, turning,
			_running_gait)
	if _player.anim_state != next_state:
		_player.anim_state = next_state


## Walk when moving on the floor (Run when `running`, the gait the owner has
## held since RUN_ABOVE); standing, TurnInPlace while turning faster
## than TURN_STEP_ABOVE (until it drops under TURN_STEP_BELOW), else Idle.
static func movement_state(ground_speed: float, on_floor: bool, rate: float, turning: bool,
		running: bool = false) -> StringName:
	if ground_speed > IDLE_BELOW_SPEED and on_floor:
		return Player.ANIM_RUN if running else Player.ANIM_WALK
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


func play_emote(clip: StringName) -> bool:
	if clip not in EMOTE_CLIPS or anim_player == null or not anim_player.has_animation(clip):
		return false
	# Seated presentation deliberately resolves to Sit/Drive; accepting an
	# emote there would replicate a choice that nobody can see.
	if not _player.seat_node_path.is_empty():
		return false
	play_one_shot(clip, EmoteCatalogData.lock_msec(clip))
	return true


## Any deliberate input interrupts an automatic idle and restarts its wait.
func note_activity() -> void:
	_long_idle_elapsed = 0.0
	if _player.anim_state in LONG_IDLE_CLIPS:
		_anim_lock_until_msec = 0
		_player.anim_state = Player.ANIM_IDLE


## Owner-only deterministic timer. The exact selected clip is already carried
## by anim_state/anim_clip, so observers and late joiners need no new RPC.
func update_long_idle(delta: float, eligible: bool) -> bool:
	if _player.anim_state in LONG_IDLE_CLIPS:
		return false
	if not eligible or _player.anim_state != Player.ANIM_IDLE \
			or Time.get_ticks_msec() < _anim_lock_until_msec:
		_long_idle_elapsed = 0.0
		return false
	_long_idle_elapsed += maxf(delta, 0.0)
	if _long_idle_elapsed < LONG_IDLE_DELAY_SECONDS:
		return false
	var clip: StringName = LONG_IDLE_CLIPS[_long_idle_index % LONG_IDLE_CLIPS.size()]
	_long_idle_index = (_long_idle_index + 1) % LONG_IDLE_CLIPS.size()
	_long_idle_elapsed = 0.0
	play_one_shot(clip, roundi(float(LONG_IDLE_DURATIONS[clip]) * 1000.0))
	return true


## Lets movement take anim_state back right away.
func release_lock() -> void:
	_anim_lock_until_msec = 0


func set_leg_length_factor(value: float) -> void:
	_leg_length_factor = clampf(value, GelMotionFit.MIN_LENGTH_FACTOR, GelMotionFit.MAX_LENGTH_FACTOR)


func _fit_to_proportions(proportions: GelBodyProportions) -> void:
	set_leg_length_factor(proportions.leg_length)


func leg_length_factor() -> float:
	return _leg_length_factor


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


## Runs for every peer's copy of the player. The owning peer resolves the
## exact clip into anim_clip; all copies then play that replicated value.
func animate() -> void:
	var clip: StringName = _player.anim_clip
	if _player.is_local():
		clip = _resolve_owned_clip()
		if _player.anim_clip != clip:
			_player.anim_clip = clip
	if anim_player == null:
		return
	_ensure_replicated_clip(clip)
	var run_fallback: bool = clip == Player.ANIM_RUN and not anim_player.has_animation(Player.ANIM_RUN)
	if run_fallback:
		clip = Player.ANIM_WALK
	if not anim_player.has_animation(clip):
		clip = Player.ANIM_IDLE
	if anim_player.current_animation != String(clip):
		_play_clip(clip)
	_apply_playback(clip, run_fallback)
	_update_idle_bubble(clip)
	if clip == ANIM_CONGA:
		_sync_nearby_conga()


func _build_idle_bubble() -> void:
	_idle_bubble = MeshInstance3D.new()
	_idle_bubble.name = "LongIdleBubble"
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	sphere.radial_segments = 16
	sphere.rings = 8
	_idle_bubble.mesh = sphere
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color("8fe8ff58")
	material.metallic = 0.18
	material.roughness = 0.08
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_idle_bubble.material_override = material
	_idle_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_idle_bubble.layers = RenderLayers.LOCAL_BODY if _player.is_local() else RenderLayers.WORLD
	_idle_bubble.visible = false
	_player.add_child(_idle_bubble)


func _update_idle_bubble(clip: StringName) -> void:
	if not is_instance_valid(_idle_bubble) or anim_player == null or clip != &"BlowBubble":
		if is_instance_valid(_idle_bubble):
			_idle_bubble.visible = false
		return
	var at: float = anim_player.current_animation_position
	var amount: float = idle_bubble_amount(at)
	_idle_bubble.visible = amount > 0.01
	_idle_bubble.scale = Vector3.ONE * amount
	_idle_bubble.position = Vector3(0.0, 1.48 + 0.32 * bubble_float_amount(at), -0.43)


static func idle_bubble_amount(at: float) -> float:
	if at < 0.62 or at > 2.62:
		return 0.0
	var grow: float = smoothstep(0.62, 1.18, at)
	var fade: float = 1.0 - smoothstep(2.2, 2.62, at)
	return maxf(grow * fade, 0.0)


static func bubble_float_amount(at: float) -> float:
	return clampf((at - 1.0) / 1.62, 0.0, 1.0)


## Only the owner calls this. Everything it consults that is not replicated
## is collapsed into anim_clip before another peer renders the character.
func _resolve_owned_clip() -> StringName:
	if anim_player == null:
		return _player.anim_state
	var clip: StringName = _player.anim_state if _player.seat_node_path.is_empty() else _seat_clip()
	if clip == Player.ANIM_WALK:
		clip = _gait_clip()
	elif clip == Player.ANIM_PICKUP:
		clip = pickup_clip()
	elif clip == Player.ANIM_TURN and not anim_player.has_animation(Player.ANIM_TURN):
		clip = Player.ANIM_IDLE
	if clip != Player.ANIM_RUN and not anim_player.has_animation(clip):
		clip = Player.ANIM_IDLE
	return clip


func _apply_playback(clip: StringName, run_fallback: bool) -> void:
	if clip == Player.ANIM_JUMP:
		anim_player.speed_scale = 0.0
		anim_player.seek(_player.jump_anim_time, true)
		# The eyes squeeze shut as the landing's squash hits.
		if _player.jump_anim_time >= 0.9 and _seen_jump_time < 0.9 and _face != null:
			_face.call(&"blink")
		_seen_jump_time = _player.jump_anim_time
	elif clip == Player.ANIM_RUN:
		anim_player.speed_scale = GelMotionFit.gait_speed_scale(
			_player.locomotion_speed, RUN_AUTHORED_SPEED, _leg_length_factor, RUN_MIN_SCALE, 1.3
		)
	elif clip == Player.ANIM_WALK or clip == ANIM_CARRY_WALK:
		anim_player.speed_scale = GelMotionFit.gait_speed_scale(
			_player.locomotion_speed, WALK_AUTHORED_SPEED, _leg_length_factor, 0.5,
			RUN_FALLBACK_MAX_SCALE if run_fallback else 1.5
		)
	elif clip == Player.ANIM_STROLL:
		anim_player.speed_scale = GelMotionFit.gait_speed_scale(
			_player.locomotion_speed, STROLL_AUTHORED_SPEED, _leg_length_factor, 0.2, 1.6
		)
	else:
		anim_player.speed_scale = 1.0


## All conga copies visible on one peer use that peer's monotonic clock. This
## aligns nearby dancers without another network stream or dependence on who
## entered the dance first; distant solo dancers keep their natural start.
func _sync_nearby_conga() -> void:
	if not _player.is_inside_tree():
		return
	var has_partner: bool = false
	for candidate: Node in _player.get_tree().get_nodes_in_group(&"player"):
		var other := candidate as Player
		if other == null or other == _player or other.anim_clip != ANIM_CONGA:
			continue
		if conga_distance_is_near(_player.global_position.distance_to(other.global_position)):
			has_partner = true
			break
	if not has_partner:
		return
	var length: float = anim_player.current_animation_length
	if length > 0.0:
		anim_player.seek(conga_phase_msec(Time.get_ticks_msec(), length), true)


static func conga_phase_msec(now_msec: int, length: float) -> float:
	return fposmod(float(now_msec) / 1000.0, maxf(length, 0.001))


static func conga_distance_is_near(distance: float) -> bool:
	return distance <= CONGA_SYNC_RADIUS


## A blended pickup clip is generated lazily per AnimationPlayer. The owner
## created its copy while resolving anim_clip; a remote peer creates the same
## deterministic blend from the replicated step name, without needing the
## owner's package or pickup height.
func _ensure_replicated_clip(clip: StringName) -> void:
	var prefix: String = String(PICKUP_BLEND_LIBRARY) + "/"
	if anim_player.has_animation(clip) or not String(clip).begins_with(prefix):
		return
	var step: int = String(clip).trim_prefix(prefix).to_int()
	_pickup_clip_for_step(step)


## The pickup clip for the player's pickup_high_weight: either authored clip
## at the ends, a baked blend of both in between (quantised, so at most a
## handful exist).
func pickup_clip() -> StringName:
	var step: int = roundi(_player.pickup_high_weight * PICKUP_BLEND_STEPS)
	return _pickup_clip_for_step(step)


func _pickup_clip_for_step(step: int) -> StringName:
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
	if is_instance_valid(_player.carried_package) and anim_player.has_animation(ANIM_CARRY_WALK):
		return ANIM_CARRY_WALK
	return Player.ANIM_STROLL if _strolling and anim_player.has_animation(Player.ANIM_STROLL) else Player.ANIM_WALK


func _seat_clip() -> StringName:
	var path: NodePath = _player.seat_node_path
	var last_name: StringName = path.get_name(path.get_name_count() - 1) if path.get_name_count() > 0 else &""
	if last_name == &"DriverEyePoint" and anim_player.has_animation(ANIM_DRIVE):
		return ANIM_DRIVE
	return Player.ANIM_SIT


## The gaits all start on the left foot's touchdown, so switching between them
## keeps the cycle phase: the feet carry on instead of skating to a new step.
func _play_clip(clip: StringName) -> void:
	var phase: float = -1.0
	var previous := StringName(anim_player.current_animation)
	if previous in GAIT_CLIPS and clip in GAIT_CLIPS:
		phase = anim_player.current_animation_position / maxf(anim_player.current_animation_length, 0.001)
	# A pickup whose height arrives late (anim_state replicated before the
	# pick_up RPC) swaps blends in place instead of restarting the squat.
	var pickup_time: float = -1.0
	if _is_pickup_clip(StringName(anim_player.current_animation)) and _is_pickup_clip(clip):
		pickup_time = anim_player.current_animation_position
	anim_player.play(String(clip), transition_blend_time(previous, clip))
	if phase >= 0.0:
		anim_player.seek(phase * anim_player.current_animation_length)
	elif pickup_time >= 0.0:
		anim_player.seek(pickup_time)


static func transition_blend_time(from_clip: StringName, to_clip: StringName) -> float:
	if from_clip.is_empty() or from_clip == to_clip:
		return 0.0
	if from_clip in GAIT_CLIPS and to_clip in GAIT_CLIPS:
		return GAIT_BLEND
	if to_clip in REACTION_CLIPS:
		return REACTION_IN_BLEND
	if from_clip in REACTION_CLIPS:
		return REACTION_OUT_BLEND
	if from_clip in [Player.ANIM_SIT, ANIM_DRIVE] \
			or to_clip in [Player.ANIM_SIT, ANIM_DRIVE]:
		return SEAT_BLEND
	if from_clip == Player.ANIM_TURN or to_clip == Player.ANIM_TURN:
		return TURN_BLEND
	if _is_pickup_clip(from_clip) or _is_pickup_clip(to_clip) \
			or from_clip == Player.ANIM_JUMP or to_clip == Player.ANIM_JUMP:
		return ONE_SHOT_BLEND
	if from_clip in GAIT_CLIPS or to_clip in GAIT_CLIPS:
		return LOCOMOTION_BLEND
	return ONE_SHOT_BLEND


static func _is_pickup_clip(clip: StringName) -> bool:
	return clip == Player.ANIM_PICKUP or clip == Player.ANIM_PICKUP_HIGH \
			or String(clip).begins_with(String(PICKUP_BLEND_LIBRARY) + "/")
