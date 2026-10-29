extends SceneTree
## S-311.97: the gel owns a wet wordless voice and eight compact dance loops.

const GelPerformance = preload("res://modules/synth_audio/synth_audio_gel_performance.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_voices()
	_check_dance_library()
	await _check_player_component()
	if _failures == 0:
		print("PASS: gelatinous voices and eight dance identities use bounded cached emitters")
	quit(_failures)


func _check_voices() -> void:
	var first: AudioStreamWAV = SynthAudio.gel_voice(2, 3)
	_expect(first == SynthAudio.gel_voice(2, 3), "a gel voice is cached")
	_expect(first.data != SynthAudio.callout_voice(2, 3).data,
		"the gel reaction voice has a wetter identity than ping babble")
	_expect(first.data != SynthAudio.gel_voice(3, 3).data,
		"colour slots remain audibly distinct")
	_expect(_peak(first) > 1000, "the gel voice contains audible samples")


func _check_dance_library() -> void:
	var fingerprints: Dictionary = {}
	for clip: StringName in GelPerformance.DANCE_CLIPS:
		var stream: AudioStreamWAV = SynthAudio.gel_dance_music(clip)
		_expect(stream == SynthAudio.gel_dance_music(clip), "%s music is cached" % clip)
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s music loops" % clip)
		_expect(absf(stream.get_length() - float(GelPerformance.DANCE_DURATIONS[clip])) < 0.01,
			"%s music matches the dance duration" % clip)
		_expect(_peak(stream) > 1000, "%s music contains audible samples" % clip)
		fingerprints[hash(stream.data)] = true
	_expect(fingerprints.size() == GelPerformance.DANCE_CLIPS.size(),
		"all eight dances have distinct musical samples")


func _check_player_component() -> void:
	var player: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var component: Node = player.get_node_or_null(^"PlayerVoice/GelDanceAudio")
	_expect(component != null, "every player owns one dance-music component")
	if component == null:
		player.free()
		return
	var emitter: AudioStreamPlayer3D = component.get(&"music")
	_expect(emitter != null and emitter.bus == &"Exterior",
		"dance music starts on the listener's exterior environment bus")
	_expect(component.find_children("*", "AudioStreamPlayer3D", true, false).size() == 1,
		"one bounded positional emitter is reused")
	player.set(&"anim_clip", &"Robot")
	component.call(&"_process", 0.0)
	_expect(component.get(&"current_dance") == &"Robot" and emitter.playing,
		"entering a replicated dance starts its own loop")
	_expect(emitter.stream == SynthAudio.gel_dance_music(&"Robot"),
		"the selected dance owns the selected music")
	player.set(&"anim_clip", &"Idle")
	component.call(&"_process", 0.0)
	_expect(not emitter.playing and emitter.stream == null,
		"leaving the dance immediately releases its stream")
	player.free()


func _peak(stream: AudioStreamWAV) -> int:
	var result: int = 0
	for index: int in range(0, stream.data.size() - 1, 2):
		result = maxi(result, absi(stream.data.decode_s16(index)))
	return result


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
