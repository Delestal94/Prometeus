extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/synth_audio/tests/test_synth_audio_golden.gd
##
## N-225: synth_audio.gd was split by responsibility (SynthAudioVehicle, Traps, Handling,
## World, Animals, Scenes, Care, plus the shared SynthAudioDsp) and must sound exactly as
## before. Every public sound is built after seeding the global RNG (the unseeded ones draw
## from it) and compared with what the single-file version produced: byte count, sample
## rate, loop points, peak and the sum of |sample| (the last two with a hair of tolerance so
## a different libm's last-bit rounding cannot fail it). Also: each accessor still shares
## one instance, and the cache keeps its sound names (the sound audit looks them up there).

## [name, bytes, mix rate, loop mode, loop end, peak, sum of |sample|]. The callout voices
## are "callout_voice_<slot>_<syllables>", built with SynthAudio.callout_voice(slot, syllables).
const GOLDEN: Array = [
	["engine_loop", 44100, 22050, 1, 22050, 13226, 140761356],
	["engine_idle_loop", 44100, 22050, 1, 22050, 13825, 137854684],
	["engine_high_loop", 44100, 22050, 1, 22050, 15107, 130990744],
	["impact_thud", 9702, 22050, 0, 0, 31899, 17886458],
	["tire_screech", 22050, 22050, 1, 11025, 26451, 91697305],
	["glass_chime", 22050, 22050, 0, 0, 30413, 26532423],
	["creature_groan", 52920, 22050, 1, 26460, 30102, 421563410],
	["wood_creak", 17640, 22050, 0, 0, 32767, 32490376],
	["liquid_slosh", 12348, 22050, 0, 0, 8197, 11568205],
	["explosive_tick", 3086, 22050, 0, 0, 21554, 5492609],
	["hostile_hiss", 14112, 22050, 0, 0, 12246, 16112900],
	["honk_horn", 18522, 22050, 0, 0, 19660, 80211149],
	["ambient_wind", 220500, 11025, 1, 110250, 19199, 262687189],
	["camera_shutter", 7056, 22050, 0, 0, 11618, 1205884],
	["tape_rip", 18522, 22050, 0, 0, 18567, 9280693],
	["cardboard_flap", 8820, 22050, 0, 0, 13123, 2954425],
	["tension_pulse", 88200, 22050, 1, 44100, 19690, 140344767],
	["rain_loop", 88200, 22050, 1, 44100, 15418, 68080485],
	["crossing_bell", 22050, 22050, 1, 11025, 12670, 13346575],
	["roller_door", 44100, 22050, 1, 22050, 12081, 81684458],
	["reverse_beep", 44100, 22050, 1, 22050, 11527, 69176269],
	["ambient_birds", 1234800, 22050, 1, 617400, 8272, 59370587],
	["night_crickets", 882000, 22050, 1, 441000, 9739, 55965438],
	["distant_road", 264600, 11025, 1, 132300, 22975, 280473311],
	["dog_bark", 10584, 22050, 0, 0, 32767, 16299666],
	["sheep_bleat", 26460, 22050, 0, 0, 13423, 108988949],
	["doorbell_ding_dong", 46304, 22050, 0, 0, 18019, 69599709],
	["neighbor_cheer", 27342, 22050, 0, 0, 22506, 58197170],
	["comic_ruin_stinger", 26460, 22050, 0, 0, 20058, 86070482],
	["comic_boom", 39690, 22050, 0, 0, 30805, 38984637],
	["forklift_motor_loop", 44100, 22050, 1, 22050, 10491, 88609160],
	["river_flow_loop", 198450, 11025, 1, 99225, 19488, 243099312],
	["train_horn", 57330, 22050, 0, 0, 17037, 151680647],
	["train_chug_loop", 44100, 22050, 1, 22050, 32767, 53147019],
	["scanner_beep", 3086, 22050, 0, 0, 8333, 8876900],
	["care_step", 4850, 22050, 0, 0, 13624, 6150272],
	["care_error", 10584, 22050, 0, 0, 11929, 26308686],
	["care_success", 21168, 22050, 0, 0, 10800, 24646959],
	["care_whoosh", 6614, 22050, 0, 0, 14745, 9721987],
	["care_tick", 1542, 22050, 0, 0, 10031, 906193],
	["callout_voice_0_3", 18080, 22050, 0, 0, 25313, 35974616],
	["callout_voice_2_1", 7496, 22050, 0, 0, 22916, 14732542],
	["callout_voice_5_4", 23372, 22050, 0, 0, 19905, 53952652],
]

var _failures: int = 0


func _initialize() -> void:
	for row: Array in GOLDEN:
		var sound_name: String = row[0]
		seed(77 if sound_name.begins_with("callout_voice_") else 1000 + GOLDEN.find(row))
		var stream: AudioStreamWAV = _build(sound_name)
		if stream == null:
			_expect(false, "%s builds an AudioStreamWAV" % sound_name)
			continue
		_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo,
			"%s is 16-bit mono" % sound_name)
		_expect(stream.data.size() == row[1], "%s has %d bytes (got %d)" % [sound_name, row[1], stream.data.size()])
		_expect(stream.mix_rate == row[2], "%s mixes at %d Hz (got %d)" % [sound_name, row[2], stream.mix_rate])
		_expect(stream.loop_mode == row[3], "%s loop mode %d (got %d)" % [sound_name, row[3], stream.loop_mode])
		_expect(stream.loop_end == row[4], "%s loop end %d (got %d)" % [sound_name, row[4], stream.loop_end])
		var peak: int = 0
		var total: int = 0
		for index: int in range(0, stream.data.size() - 1, 2):
			var value: int = absi(stream.data.decode_s16(index))
			peak = maxi(peak, value)
			total += value
		_expect(absi(peak - int(row[5])) <= 2 + int(row[5]) / 100, "%s peak %d (got %d)" % [sound_name, row[5], peak])
		_expect(absi(total - int(row[6])) <= 4 + int(row[6]) / 500,
			"%s loudness %d (got %d)" % [sound_name, row[6], total])
		if not sound_name.begins_with("callout_voice_"):
			_expect(Callable(SynthAudio, sound_name).call() == stream, "%s is built once and shared" % sound_name)
			_expect(SynthAudio._cache.get(StringName(sound_name)) == stream,
				"%s keeps its cache key" % sound_name)
	if _failures == 0:
		print("PASS: the split synth_audio scripts still build every sound as the single file did")
	quit(_failures)


func _build(sound_name: String) -> AudioStreamWAV:
	if sound_name.begins_with("callout_voice_"):
		var parts: PackedStringArray = sound_name.split("_")
		return SynthAudio.callout_voice(int(parts[2]), int(parts[3]))
	return Callable(SynthAudio, sound_name).call() as AudioStreamWAV


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
