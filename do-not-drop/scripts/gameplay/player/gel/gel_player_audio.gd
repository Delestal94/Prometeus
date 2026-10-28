class_name GelPlayerAudio
extends Node
## Bounded spatial foley for one gel player. Replicated movement/animation and
## knockout state are already present on every peer, so sound needs no RPC.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const Knockout = preload("res://scripts/gameplay/player/gel/gel_knockout.gd")
const GelSounds = preload("res://modules/synth_audio/synth_audio_gel.gd")
const VOICE_COUNT: int = 4
const WALK_STEP_DISTANCE: float = 1.2
const RUN_STEP_DISTANCE: float = 2.0
const MIN_MOVEMENT_SPEED: float = 0.3
const CUE_COOLDOWN_MSEC: int = 80
const GAIT_CLIPS: Array[StringName] = [&"Walk", &"Stroll", &"Run", &"CarryWalk"]
const BOUNCE_CLIPS: Array[StringName] = [&"BallBounce", &"IdleBounce", &"Flan"]

var last_cue: StringName = &""
var cue_counts: Dictionary = {}
var last_surface: int = GelSounds.Surface.ROAD

var _player: Player
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _stride: float = 0.0
var _previous_clip: StringName = &""
var _previous_jump_time: float = 0.0
var _previous_knockout_phase: int = Knockout.Phase.ALIVE
var _last_cue_at: Dictionary = {}


func setup(player: Player) -> void:
	_player = player
	for voice: AudioStreamPlayer3D in _voices:
		if is_instance_valid(voice):
			voice.queue_free()
	_voices.clear()
	for index: int in VOICE_COUNT:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "GelFoley%d" % index
		voice.bus = &"SFX"
		voice.unit_size = 5.0
		voice.max_distance = 26.0
		voice.attenuation_filter_cutoff_hz = 10500.0
		player.add_child(voice)
		_voices.append(voice)
	_previous_clip = player.anim_clip
	_previous_jump_time = player.jump_anim_time
	_previous_knockout_phase = Knockout.Phase.ALIVE
	_stride = 0.0


func update_audio(player: Player, knockout: Node, delta: float, enabled: bool) -> void:
	if _voices.is_empty():
		return
	_update_clip_cues(player)
	_update_knockout_cues(knockout)
	_update_footsteps(player, maxf(delta, 0.0), enabled)


func play_hit(strength: float = 1.0) -> void:
	var amount: float = clampf(strength / 4.0, 0.0, 1.0)
	_play(&"hit", SynthAudio.gel_hit(), WorldMix.GEL_FOLEY_DB, lerpf(1.08, 0.88, amount))


func play_step(surface: int) -> void:
	last_surface = clampi(surface, GelSounds.Surface.ROAD, GelSounds.Surface.SOFT)
	_play(&"footstep", SynthAudio.gel_footstep(last_surface), WorldMix.FOOTSTEP_DB,
			randf_range(0.95, 1.05))


func play_jump() -> void:
	_play(&"jump", SynthAudio.gel_jump(), WorldMix.GEL_FOLEY_DB)


func play_landing() -> void:
	_play(&"landing", SynthAudio.gel_landing(), WorldMix.GEL_FOLEY_DB)


func play_bounce() -> void:
	_play(&"bounce", SynthAudio.gel_bounce(), WorldMix.GEL_FOLEY_DB)


func play_stretch() -> void:
	_play(&"stretch", SynthAudio.gel_stretch(), WorldMix.GEL_FOLEY_DB)


func play_melt() -> void:
	_play(&"melt", SynthAudio.gel_melt(), WorldMix.GEL_FOLEY_DB)


func play_reassemble() -> void:
	_play(&"reassemble", SynthAudio.gel_reassemble(), WorldMix.GEL_FOLEY_DB)


func voice_count() -> int:
	return _voices.size()


func _update_clip_cues(player: Player) -> void:
	var clip: StringName = player.anim_clip
	if clip != _previous_clip:
		if clip == &"Jump":
			play_jump()
		if clip in BOUNCE_CLIPS:
			play_bounce()
		if clip == &"GumStretch":
			play_stretch()
		if clip == &"MeltAndReturn":
			play_melt()
		elif _previous_clip == &"MeltAndReturn":
			play_reassemble()
		_previous_clip = clip
		_previous_jump_time = 0.0 if clip == &"Jump" else player.jump_anim_time
	if clip == &"Jump" and player.jump_anim_time >= 0.9 and _previous_jump_time < 0.9:
		play_landing()
	_previous_jump_time = player.jump_anim_time


func _update_knockout_cues(knockout: Node) -> void:
	if knockout == null:
		return
	var phase: int = int(knockout.get("phase"))
	if phase == _previous_knockout_phase:
		return
	if phase == Knockout.Phase.MELTING:
		play_melt()
	elif phase == Knockout.Phase.REASSEMBLING:
		play_reassemble()
	_previous_knockout_phase = phase


func _update_footsteps(player: Player, delta: float, enabled: bool) -> void:
	var moving: bool = enabled and player.anim_clip in GAIT_CLIPS \
			and player.locomotion_speed > MIN_MOVEMENT_SPEED and player.seat_node_path.is_empty()
	if not moving:
		_stride = minf(_stride, WALK_STEP_DISTANCE * 0.5)
		return
	_stride += player.locomotion_speed * delta
	var distance: float = RUN_STEP_DISTANCE if player.anim_clip == &"Run" else WALK_STEP_DISTANCE
	while _stride >= distance:
		_stride -= distance
		play_step(surface_for_player(player))


static func surface_for_player(player: Player) -> int:
	for index: int in player.get_slide_collision_count():
		var collision: KinematicCollision3D = player.get_slide_collision(index)
		if collision.get_normal().y < 0.45:
			continue
		var collider: Object = collision.get_collider()
		var tagged: int = _surface_from_collider(collider)
		if tagged >= 0:
			return tagged
	var route: Node = player.get_tree().get_first_node_in_group(&"route") if player.is_inside_tree() else null
	if route != null and route.has_method(&"ground_roughness"):
		return surface_from_roughness(float(route.call(&"ground_roughness", player.global_position)))
	return GelSounds.Surface.ROAD


static func surface_from_roughness(roughness: float) -> int:
	if roughness >= 0.65:
		return GelSounds.Surface.GRAVEL
	if roughness >= 0.12:
		return GelSounds.Surface.SOFT
	return GelSounds.Surface.ROAD


static func _surface_from_collider(collider: Object) -> int:
	if collider == null:
		return -1
	if collider.has_meta(&"gel_audio_surface"):
		var tag := StringName(collider.get_meta(&"gel_audio_surface", &"road"))
		var index: int = GelSounds.SURFACE_NAMES.find(tag)
		if index >= 0:
			return index
	var node := collider as Node
	var lowered: String = String(node.name).to_lower() if node != null else ""
	if "metal" in lowered or "vehicle" in lowered or "truck" in lowered or "shelf" in lowered:
		return GelSounds.Surface.METAL
	if "mud" in lowered or "grass" in lowered or "dirt" in lowered or "verge" in lowered:
		return GelSounds.Surface.SOFT
	return -1


func _play(cue: StringName, stream: AudioStreamWAV, volume_db: float, pitch: float = 1.0) -> void:
	if stream == null or _voices.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_last_cue_at.get(cue, -CUE_COOLDOWN_MSEC)) < CUE_COOLDOWN_MSEC:
		return
	_last_cue_at[cue] = now
	var voice: AudioStreamPlayer3D = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = clampf(pitch, 0.5, 1.5)
	voice.play()
	last_cue = cue
	cue_counts[cue] = int(cue_counts.get(cue, 0)) + 1
