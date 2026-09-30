extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/synth_audio/tests/test_synth_audio.gd
##
## The synth_audio module on its own (docs/modulos.md): every generator
## returns a non-empty 16-bit stream, the same sound is built once and
## shared, loops are marked as loops, the scene sounds load their builder by
## a path relative to the module, and the care, step, trap and radio helpers
## answer too. No assets, no autoloads, no other module.

var _failures: int = 0


func _initialize() -> void:
	var one_shots: Array[Callable] = [
		SynthAudio.impact_thud, SynthAudio.tire_screech, SynthAudio.glass_chime, SynthAudio.creature_groan,
		SynthAudio.wood_creak, SynthAudio.liquid_slosh, SynthAudio.explosive_tick, SynthAudio.hostile_hiss,
		SynthAudio.honk_horn, SynthAudio.camera_shutter, SynthAudio.tape_rip, SynthAudio.cardboard_flap,
		SynthAudio.crossing_bell, SynthAudio.roller_door, SynthAudio.reverse_beep, SynthAudio.dog_bark,
		SynthAudio.sheep_bleat, SynthAudio.doorbell_ding_dong, SynthAudio.neighbor_cheer, SynthAudio.train_horn,
		SynthAudio.scanner_beep, SynthAudio.care_step, SynthAudio.care_error, SynthAudio.care_success,
		SynthAudio.care_whoosh, SynthAudio.care_tick,
	]
	for build: Callable in one_shots:
		_check_stream(build.call(), String(build.get_method()))
	var loops: Array[Callable] = [
		SynthAudio.engine_loop, SynthAudio.engine_idle_loop, SynthAudio.engine_high_loop, SynthAudio.ambient_wind,
		SynthAudio.rain_loop, SynthAudio.ambient_birds, SynthAudio.night_crickets, SynthAudio.distant_road,
		SynthAudio.river_flow_loop, SynthAudio.train_chug_loop,
	]
	for build: Callable in loops:
		var stream: AudioStreamWAV = _check_stream(build.call(), String(build.get_method()))
		if stream != null:
			_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops" % build.get_method())
	var first_horn: AudioStreamWAV = SynthAudio.honk_horn()
	_expect(first_horn == SynthAudio.honk_horn(), "The same sound is built once and shared")
	_check_stream(SynthAudio.callout_voice(2, 3), "callout_voice")
	_expect(SynthAudio.callout_voice(0, 2) != SynthAudio.callout_voice(1, 2), "Callouts differ by voice")
	_check_stream(SynthAudioSteps.footstep(), "footstep")
	_check_stream(SynthAudioTraps.cushion_pad(), "cushion_pad")
	_check_stream(SynthAudioRadio.knob_click(), "knob_click")
	if _failures == 0:
		print("PASS: every synthesized sound builds, caches and loops where it should")
	quit(_failures)


func _check_stream(stream: Variant, what: String) -> AudioStreamWAV:
	var wav := stream as AudioStreamWAV
	_expect(wav != null, "%s returns an AudioStreamWAV" % what)
	if wav == null:
		return null
	_expect(wav.format == AudioStreamWAV.FORMAT_16_BITS and wav.data.size() > 200,
		"%s has 16-bit samples (%d bytes)" % [what, wav.data.size()])
	# The whole stream, coarsely: a bird bed starts with silence.
	var loudest: int = 0
	for index: int in range(0, wav.data.size() - 1, 16):
		loudest = maxi(loudest, absi(wav.data.decode_s16(index)))
	_expect(loudest > 100, "%s is not silent (peak %d)" % [what, loudest])
	return wav


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
