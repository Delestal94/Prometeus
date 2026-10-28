extends SceneTree
## S-311.96: deterministic gel foley, four surface steps, bounded spatial
## players and hooks for the replicated movement/animation contract.

const PLAYER_SCENE := preload("res://scenes/gameplay/player/player.tscn")
const GelSounds = preload("res://modules/synth_audio/synth_audio_gel.gd")
const GelAudioScript = preload("res://scripts/gameplay/player/gel/gel_player_audio.gd")

var _failures: int = 0


func _initialize() -> void:
	_test_synthesized_streams()
	_test_surface_classes()
	await _test_player_integration()
	if _failures == 0:
		print("PASS: gel movement and reactions use bounded synthesized spatial foley")
	quit(_failures)


func _test_synthesized_streams() -> void:
	var footstep_bytes: Array[PackedByteArray] = []
	for surface: int in GelSounds.Surface.values():
		var step: AudioStreamWAV = SynthAudio.gel_footstep(surface)
		_check_stream(step, "gel footstep %s" % GelSounds.surface_name(surface), 0.12, 0.20)
		_expect(step == SynthAudio.gel_footstep(surface), "surface %d footstep is cached" % surface)
		footstep_bytes.append(step.data)
	for left: int in footstep_bytes.size():
		for right: int in range(left + 1, footstep_bytes.size()):
			_expect(footstep_bytes[left] != footstep_bytes[right],
				"surface footsteps %d and %d sound different" % [left, right])
	var cues: Array = [
		[SynthAudio.gel_jump, "jump", 0.24, 0.32],
		[SynthAudio.gel_landing, "landing", 0.32, 0.40],
		[SynthAudio.gel_bounce, "bounce", 0.24, 0.32],
		[SynthAudio.gel_hit, "hit", 0.24, 0.32],
		[SynthAudio.gel_stretch, "stretch", 0.42, 0.50],
		[SynthAudio.gel_melt, "melt", 0.84, 0.92],
		[SynthAudio.gel_reassemble, "reassemble", 0.98, 1.06],
	]
	for row: Array in cues:
		var stream: AudioStreamWAV = (row[0] as Callable).call()
		_check_stream(stream, row[1], row[2], row[3])
		_expect(stream == (row[0] as Callable).call(), "%s is cached" % row[1])


func _test_surface_classes() -> void:
	_expect(GelAudioScript.surface_from_roughness(0.0) == GelSounds.Surface.ROAD,
		"smooth route is the road squish")
	_expect(GelAudioScript.surface_from_roughness(0.25) == GelSounds.Surface.SOFT,
		"the verge uses the soft squish")
	_expect(GelAudioScript.surface_from_roughness(1.0) == GelSounds.Surface.GRAVEL,
		"rough route uses the gravel squish")


func _test_player_integration() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await process_frame
	var audio: Variant = player.get_node_or_null(^"GelEffects/GelAudio")
	_expect(audio != null, "the real player scene owns GelAudio")
	if audio == null:
		player.free()
		return
	_expect(audio.voice_count() == 4, "the spatial voice pool is fixed at four")
	for index: int in audio.voice_count():
		var voice := player.get_node_or_null(NodePath("GelFoley%d" % index)) as AudioStreamPlayer3D
		_expect(voice != null and voice.bus == &"SFX" and voice.max_distance <= 26.0,
			"voice %d is a bounded SFX player" % index)

	player.anim_clip = &"Jump"
	player.jump_anim_time = 0.1
	audio.update_audio(player, player.get_node(^"GelEffects/GelKnockout"), 0.016, true)
	_expect(audio.cue_counts.get(&"jump", 0) == 1, "entering Jump plays its elastic takeoff")
	player.jump_anim_time = 0.95
	audio.update_audio(player, player.get_node(^"GelEffects/GelKnockout"), 0.016, true)
	_expect(audio.cue_counts.get(&"landing", 0) == 1, "the replicated touchdown plays landing")
	player.anim_clip = &"GumStretch"
	audio.update_audio(player, player.get_node(^"GelEffects/GelKnockout"), 0.016, true)
	_expect(audio.cue_counts.get(&"stretch", 0) == 1, "GumStretch plays elastic foley")
	player.anim_clip = &"BallBounce"
	audio.update_audio(player, player.get_node(^"GelEffects/GelKnockout"), 0.016, true)
	_expect(audio.cue_counts.get(&"bounce", 0) == 1, "BallBounce plays bounce foley")

	player.anim_clip = &"Walk"
	player.locomotion_speed = Player.WALK_SPEED
	audio.update_audio(player, player.get_node(^"GelEffects/GelKnockout"), 0.35, true)
	_expect(audio.cue_counts.get(&"footstep", 0) == 1, "walking emits a surface squish")
	_expect(audio.last_surface == GelSounds.Surface.ROAD, "the default floor is road")
	audio.play_hit(3.0)
	audio.play_melt()
	audio.play_reassemble()
	_expect(audio.cue_counts.get(&"hit", 0) == 1, "package impacts play the gel hit")
	_expect(audio.cue_counts.get(&"melt", 0) == 1, "knockout/emote can play melt")
	_expect(audio.cue_counts.get(&"reassemble", 0) == 1, "recovery can play reassemble")
	player.free()
	await process_frame


func _check_stream(stream: AudioStreamWAV, label: String, minimum: float, maximum: float) -> void:
	_expect(stream != null, "%s builds a stream" % label)
	if stream == null:
		return
	var seconds: float = float(stream.data.size() / 2) / stream.mix_rate
	_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo,
		"%s is 16-bit mono" % label)
	_expect(seconds >= minimum and seconds <= maximum,
		"%s lasts %.2f seconds" % [label, seconds])
	var peak: int = 0
	for index: int in range(0, stream.data.size() - 1, 2):
		peak = maxi(peak, absi(stream.data.decode_s16(index)))
	_expect(peak > 8000, "%s is audible (peak %d)" % [label, peak])
	_expect(absi(stream.data.decode_s16(0)) < 1000
			and absi(stream.data.decode_s16(stream.data.size() - 2)) < 1000,
		"%s begins and ends near silence" % label)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
