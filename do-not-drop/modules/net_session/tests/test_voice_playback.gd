extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_session/tests/test_voice_playback.gd
##
## VoicePlayback on its own (net_session module, docs/modulos.md), the
## playback half of SteamVoice:
## - 16-bit little-endian PCM becomes frames in -1..1 (both extremes, silence,
##   an odd trailing byte ignored);
## - a phrase waits for its jitter cushion (prebuffer_seconds of audio, or that
##   long) before it starts playing;
## - pushing far more than real time never holds more than
##   max_latency_seconds: the oldest audio is dropped and counted;
## - a new sample rate restarts the generator at that rate, dropping audio
##   queued at the old one;
## - gain 0 drops what is queued and refuses more; gain 0.5 is -6 dB; restarted
##   from outside (a sound check playing it again) it feeds the new playback;
## - with nothing coming in it stops after idle_stop_seconds;
## - it copies its position from `follow` every frame;
## - in a room: no distance attenuation and no filter; in open air: fades with
##   distance up to hearing_distance, and through a wall it is quieter and
##   loses its highs.
## Headless Godot mixes with its dummy driver in real time, so what the mixer
## has already played can only make the queue shorter: the checks are bounds.

const RATE: int = 24000

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_conversion()
	await _check_jitter_buffer()
	await _check_latency_cap()
	await _check_rate_and_gain()
	await _check_idle_and_follow()
	_check_carry()
	if _failures == 0:
		print("PASS: VoicePlayback converts PCM, buffers a little, caps its lag, carries in a room or outside")
	quit(_failures)


func _check_conversion() -> void:
	var pcm := PackedByteArray([0x00, 0x80, 0xff, 0x7f, 0x00, 0x00, 0x00, 0x40, 0x12])
	var frames: PackedVector2Array = VoicePlayback.pcm_to_frames(pcm)
	_expect(frames.size() == 4, "Four whole samples, the odd trailing byte ignored (got %d)" % frames.size())
	if frames.size() == 4:
		_expect(is_equal_approx(frames[0].x, -1.0) and frames[0].x == frames[0].y,
			"-32768 is -1 on both channels (got %s)" % frames[0])
		_expect(frames[1].x > 0.999 and frames[1].x < 1.0, "32767 is just under 1 (got %s)" % frames[1])
		_expect(frames[2] == Vector2.ZERO, "Silence stays silent (got %s)" % frames[2])
		_expect(is_equal_approx(frames[3].x, 0.5), "16384 is half (got %s)" % frames[3])


func _check_jitter_buffer() -> void:
	var voice := await _new_voice()
	voice.push_pcm(_pcm(0.02), RATE)
	_expect(not voice.playing, "A first packet shorter than the cushion waits")
	_expect(voice.queued_frames() == int(0.02 * RATE), "...and is queued (got %d)" % voice.queued_frames())
	voice.push_pcm(_pcm(0.05), RATE)
	_expect(voice.playing, "Once the cushion is queued the phrase starts")
	_expect(voice.is_speaking(), "...and it counts as speaking")
	voice.silence()
	_expect(not voice.playing and voice.queued_frames() == 0, "silence() stops and empties it")
	voice.push_pcm(_pcm(0.02), RATE)
	voice.advance(voice.prebuffer_seconds * 0.5)
	_expect(not voice.playing, "A short phrase keeps waiting within the cushion time")
	voice.advance(voice.prebuffer_seconds)
	_expect(voice.playing, "...and plays once the cushion time is over, even if nothing more came")
	voice.queue_free()
	await process_frame


func _check_latency_cap() -> void:
	var voice := await _new_voice()
	var limit: int = int(voice.max_latency_seconds * RATE)
	var worst: int = 0
	for packet: int in 100:
		voice.push_pcm(_pcm(0.02), RATE)
		worst = maxi(worst, voice.queued_frames())
	_expect(worst <= limit,
		"Two seconds pushed at once never queue more than the cap (worst %d, cap %d)" % [worst, limit])
	_expect(voice.dropped_frames >= 2 * RATE - limit - int(0.3 * RATE),
		"The oldest audio is dropped instead, and counted (got %d)" % voice.dropped_frames)
	_expect(voice.buffered_seconds() <= voice.max_latency_seconds + 0.001,
		"Buffered seconds stay under the cap (got %.3f)" % voice.buffered_seconds())
	voice.queue_free()
	await process_frame


func _check_rate_and_gain() -> void:
	var voice := await _new_voice()
	voice.push_pcm(_pcm(0.1), RATE)
	var stream := voice.stream as AudioStreamGenerator
	_expect(stream != null and is_equal_approx(stream.mix_rate, RATE), "The generator runs at the speaker's rate")
	voice.push_pcm(_pcm(0.08, 16000), 16000)
	_expect(voice.sample_rate == 16000 and is_equal_approx(stream.mix_rate, 16000.0),
		"A new rate restarts the generator at it (got %d)" % voice.sample_rate)
	_expect(voice.queued_frames() <= int(0.08 * 16000),
		"Audio queued at the old rate is dropped (got %d)" % voice.queued_frames())
	voice.push_pcm(_pcm(0.05), 0)
	_expect(voice.sample_rate == VoicePlayback.FALLBACK_SAMPLE_RATE, "A rate of 0 falls back to 24 kHz")
	voice.gain = 0.5
	_expect(absf(voice.volume_db - linear_to_db(0.5)) < 0.01, "Gain 0.5 is -6 dB (got %.2f)" % voice.volume_db)
	voice.gain = 0.0
	_expect(not voice.playing and voice.queued_frames() == 0, "Gain 0 drops what was queued")
	voice.push_pcm(_pcm(0.1), RATE)
	_expect(voice.queued_frames() == 0 and not voice.playing, "...and takes nothing more")
	voice.gain = 1.0
	voice.push_pcm(_pcm(0.1), RATE)
	_expect(voice.playing, "Back at full volume it plays again")
	# A sound check restarting it from outside (it swaps the stream and plays again).
	voice.play()
	var fresh := voice.get_stream_playback() as AudioStreamGeneratorPlayback
	var before: int = fresh.get_frames_available()
	voice.push_pcm(_pcm(0.1), RATE)
	_expect(fresh.get_frames_available() < before, "Restarted from outside, it feeds the new playback")
	voice.queue_free()
	await process_frame


func _check_idle_and_follow() -> void:
	var anchor := Node3D.new()
	root.add_child(anchor)
	anchor.global_position = Vector3(5.0, 1.6, -3.0)
	var voice := await _new_voice()
	voice.follow = anchor
	voice.push_pcm(_pcm(0.1), RATE)
	voice.advance(0.0)
	_expect(voice.global_position.is_equal_approx(anchor.global_position),
		"It sits where it follows (got %s)" % voice.global_position)
	anchor.global_position = Vector3(-2.0, 1.2, 8.0)
	voice.advance(0.0)
	_expect(voice.global_position.is_equal_approx(anchor.global_position),
		"...and moves with it (got %s)" % voice.global_position)
	voice.advance(voice.idle_stop_seconds * 0.5)
	_expect(voice.playing, "A moment without packets keeps it playing")
	voice.advance(voice.idle_stop_seconds)
	_expect(not voice.playing and voice.queued_frames() == 0, "Quiet for idle_stop_seconds, it stops")
	anchor.free()
	voice.advance(0.0)
	_expect(voice.global_position.is_equal_approx(Vector3(-2.0, 1.2, 8.0)), "A freed anchor leaves it where it was")
	voice.queue_free()
	await process_frame


func _check_carry() -> void:
	var voice := VoicePlayback.new()
	_expect(voice.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		and is_equal_approx(voice.max_distance, voice.hearing_distance), "It starts in open air")
	voice.carry_in_room()
	_expect(voice.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED, "In a room distance doesn't fade it")
	_expect(is_zero_approx(voice.max_distance) and voice.attenuation_filter_cutoff_hz >= 20000.0,
		"...nor cuts it off or filters it")
	var room_db: float = voice.volume_db
	voice.carry_in_open()
	_expect(voice.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		and is_equal_approx(voice.unit_size, voice.full_volume_distance), "In open air it fades with distance")
	_expect(voice.max_distance > 20.0 and voice.max_distance <= 30.0,
		"...and is gone at 20-30 m (got %.1f)" % voice.max_distance)
	_expect(is_equal_approx(voice.volume_db, room_db), "Open air is as loud as the room up close")
	_expect(voice.max_db <= voice.volume_db + 0.01, "...never louder (max_db %.1f)" % voice.max_db)
	var open_cutoff: float = voice.attenuation_filter_cutoff_hz
	voice.carry_in_open(true)
	_expect(voice.muffled and voice.attenuation_filter_cutoff_hz < open_cutoff,
		"Through a wall it loses its highs (cutoff %.0f Hz)" % voice.attenuation_filter_cutoff_hz)
	_expect(voice.volume_db < room_db - 3.0, "...and is quieter (%.1f dB)" % voice.volume_db)
	voice.carry_in_room()
	_expect(not voice.muffled and is_equal_approx(voice.volume_db, room_db), "Back in the room it is clear again")
	voice.free()


func _new_voice() -> VoicePlayback:
	var voice := VoicePlayback.new()
	root.add_child(voice)
	await process_frame
	return voice


## `seconds` of a quiet tone as 16-bit little-endian PCM.
func _pcm(seconds: float, rate: int = RATE) -> PackedByteArray:
	var count: int = int(seconds * rate)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	for index: int in count:
		pcm.encode_s16(index * 2, int(sin(index * 0.05) * 3000.0))
	return pcm


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
