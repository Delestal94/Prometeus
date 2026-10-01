extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/synth_audio/tests/test_synth_audio_warm.gd
##
## SynthAudio.warm() (N-408): the sounds are built on a worker thread and only
## reach the cache on the main thread, through warm_done(); afterwards the
## accessor hands out that same stream, built once. Unknown names are
## skipped, and warming what is already cached starts nothing.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var names: Array[StringName] = [&"ambient_birds", &"doorbell_ding_dong", &"engine_loop", &"not_a_sound"]
	SynthAudio.warm(names)
	_expect(not SynthAudio.is_cached(&"ambient_birds"), "The worker doesn't write the cache itself")
	var frames: int = 0
	while not SynthAudio.warm_done() and frames < 600:
		await process_frame
		frames += 1
	_expect(SynthAudio.warm_done(), "Warming finishes (%d frames)" % frames)
	for name: StringName in [&"ambient_birds", &"doorbell_ding_dong", &"engine_loop"]:
		_expect(SynthAudio.is_cached(name), "%s is in the cache after warm_done()" % name)
	_expect(not SynthAudio.is_cached(&"not_a_sound"), "An unknown name is skipped")
	var birds: AudioStreamWAV = SynthAudio.ambient_birds()
	_expect(birds != null and birds.data.size() > 0 and birds == SynthAudio.ambient_birds(),
		"The accessor hands out the warmed stream, the same one every time")
	SynthAudio.warm([&"ambient_birds"])
	_expect(SynthAudio.warm_done(), "Warming what is cached starts nothing")
	if _failures == 0:
		print("PASS: synth sounds warm on a worker and land in the cache on the main thread")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
