extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_world_audio_levels.gd
##      (add `-- --report` to print the whole table)
##
## The world's and the truck's mix, measured instead of judged by ear (tareas
## de Nacho N-404): every sound SynthAudio makes for them is synthesized here,
## measured in dBFS, and its level from world_mix.gd added on top; the sum
## has to land within TOLERANCE_DB of its class's target (world_mix.gd lists
## the classes). Loops are measured by their RMS, one-shots that call for
## attention (and the sparse chirps of birds and crickets) by their loudest
## 100 ms, hits by their peak.

const SynthAudio = preload("res://scripts/presentation/synth_audio.gd")
const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const TOLERANCE_DB: float = 2.0
## class -> [measure, target dBFS]
const CLASSES: Dictionary = {
	"engine": ["rms", -20.0],
	"impact": ["peak", -14.0],
	"noise": ["rms", -35.0],
	"nature": ["loudest", -24.0],
	"rain": ["rms", -32.0],
	"signal": ["loudest", -18.0],
	"detail": ["peak", -26.0],
	"music": ["rms", -24.0],
	"machine": ["rms", -40.0],
	"repeat": ["loudest", -30.0],
}
## [what, SynthAudio function, its level in world_mix.gd, class]
const SOUNDS: Array = [
	["truck engine", &"engine_loop", &"ENGINE_DB", "engine"],
	["truck engine idle", &"engine_idle_loop", &"ENGINE_DB", "engine"],
	["truck engine revving", &"engine_high_loop", &"ENGINE_DB", "engine"],
	["truck impact", &"impact_thud", &"IMPACT_DB", "impact"],
	["tyre screech", &"tire_screech", &"SCREECH_DB", "signal"],
	["horn", &"honk_horn", &"HORN_DB", "signal"],
	["cargo clutter", &"impact_thud", &"CLUTTER_DB", "detail"],
	["wind", &"ambient_wind", &"WIND_DB", "noise"],
	["birds", &"ambient_birds", &"BIRDS_DB", "nature"],
	["crickets", &"night_crickets", &"CRICKETS_DB", "nature"],
	["distant road", &"distant_road", &"DISTANT_ROAD_DB", "noise"],
	["rain", &"rain_loop", &"RAIN_DB", "rain"],
	["crossing bell", &"crossing_bell", &"CROSSING_BELL_DB", "signal"],
	["dog bark", &"dog_bark", &"DOG_BARK_DB", "signal"],
	["sheep bleat", &"sheep_bleat", &"SHEEP_BLEAT_DB", "signal"],
	["doorbell", &"glass_chime", &"DOORBELL_DB", "signal"],
	["resident cheer", &"honk_horn", &"RESIDENT_CHEER_DB", "signal"],
	["resident groan", &"creature_groan", &"RESIDENT_GROAN_DB", "signal"],
	["forklift beeper", &"reverse_beep", &"FORKLIFT_BEEP_DB", "repeat"],
	["forklift engine", &"engine_loop", &"FORKLIFT_ENGINE_DB", "machine"],
	["roller door", &"roller_door", &"ROLLER_DOOR_DB", "signal"],
]

## Composed tracks (.ogg, tools/audio/compose_music.py): Godot can't hand a
## test their samples, so their RMS is read from the measurements the composer
## writes next to them (assets/audio/music/loudness.json).
## [what, file, its level in world_mix.gd, class]
const TRACKS: Array = [
	["depot radio", "mus_depot_radio_loop.ogg", &"DEPOT_RADIO_DB", "music"],
]
const LOUDNESS_PATH: String = "res://assets/audio/music/loudness.json"
## The menu theme sits as loud as the in-game track does (ingame_music.gd).
const IngameMusic = preload("res://scripts/presentation/ingame_music.gd")

var _failures: int = 0


func _initialize() -> void:
	var report: bool = OS.get_cmdline_user_args().has("--report")
	var levels: Dictionary = (WorldMix as Script).get_script_constant_map()
	if report:
		print("REPORT | sound | class | measure | stream dBFS | level dB | result | target | off")
	for sound: Array in SOUNDS:
		var stream: AudioStreamWAV = (SynthAudio as Script).call(sound[1])
		var measure: String = CLASSES[sound[3]][0]
		var target: float = CLASSES[sound[3]][1]
		var measured: float = measure_dbfs(stream, measure)
		var level: float = float(levels[sound[2]])
		var result: float = measured + level
		if report:
			print("REPORT | %s | %s | %s | %.1f | %.1f | %.1f | %.1f | %+.1f" % [sound[0], sound[3], measure, measured, level, result, target, result - target])
		_expect(absf(result - target) <= TOLERANCE_DB, "%s (%s) lands at %.1f dBFS %s, target %.1f +- %.0f (stream %.1f, level %s %.1f)" % [sound[0], sound[3], result, measure, target, TOLERANCE_DB, measured, sound[2], level])
	var loudness: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOUDNESS_PATH))
	_expect(loudness is Dictionary, "The composed tracks' loudness is on file (%s)" % LOUDNESS_PATH)
	if loudness is Dictionary:
		for track: Array in TRACKS:
			var entry: Dictionary = (loudness as Dictionary).get(track[1], {})
			var measured: float = float(entry.get("rms_dbfs", 0.0))
			var result: float = measured + float(levels[track[2]])
			var target: float = CLASSES[track[3]][1]
			if report:
				print("REPORT | %s | %s | rms | %.1f | %.1f | %.1f | %.1f | %+.1f" % [track[0], track[3], measured, float(levels[track[2]]), result, target, result - target])
			_expect(not entry.is_empty() and absf(result - target) <= TOLERANCE_DB,
				"%s lands at %.1f dBFS rms, target %.1f +- %.0f" % [track[0], result, target, TOLERANCE_DB])
		var menu: float = float(((loudness as Dictionary).get("mus_menu_loop.ogg", {}) as Dictionary).get("rms_dbfs", 0.0)) + float(levels[&"MENU_MUSIC_DB"])
		var ingame: float = float(((loudness as Dictionary).get("mus_ingame_loop.ogg", {}) as Dictionary).get("rms_dbfs", 0.0)) + IngameMusic.VOLUME_DB
		_expect(absf(menu - ingame) <= 1.0, "The menu theme plays as loud as the in-game track (%.1f vs %.1f dBFS)" % [menu, ingame])
		for file_name: String in ["mus_menu_loop.ogg", "mus_depot_radio_loop.ogg"]:
			_expect(ResourceLoader.exists("res://assets/audio/music/" + file_name), "%s is in the project" % file_name)
	_check_quiet_spaces()
	if _failures == 0:
		print("PASS: every world and truck sound sits within %.0f dB of its class's target" % TOLERANCE_DB)
	quit(_failures)


## Sparse birds must leave actual quiet, not simply quieter constant chirps.
func _check_quiet_spaces() -> void:
	var birds: AudioStreamWAV = SynthAudio.ambient_birds()
	var data: PackedByteArray = birds.data
	var quiet_samples: int = 0
	var quiet_run: int = 0
	var longest_quiet: int = 0
	for index: int in range(data.size() / 2):
		if absi(data.decode_s16(index * 2)) < 32:
			quiet_samples += 1
			quiet_run += 1
			longest_quiet = maxi(longest_quiet, quiet_run)
		else:
			quiet_run = 0
	_expect(float(quiet_samples) / (data.size() / 2) > 0.85, "Birdsong leaves most of the day bed quiet")
	_expect(float(longest_quiet) / birds.mix_rate > 3.0, "Bird phrases leave several seconds to hear the rest of the world")
	_expect(absi(data.decode_s16(0)) < 32 and absi(data.decode_s16(data.size() - 2)) < 32,
		"Birdsong begins and ends near silence so its seam doesn't click")


## "rms" over the whole clip (loops), "loudest" 100 ms window's RMS
## (one-shots), or "peak", in dBFS.
static func measure_dbfs(stream: AudioStreamWAV, measure: String) -> float:
	var data: PackedByteArray = stream.data
	var count: int = data.size() / 2
	var squares := PackedFloat64Array()
	squares.resize(count)
	var peak: float = 0.0
	var total: float = 0.0
	for index: int in range(count):
		var sample: float = data.decode_s16(index * 2) / 32768.0
		peak = maxf(peak, absf(sample))
		squares[index] = sample * sample
		total += sample * sample
	match measure:
		"peak":
			return linear_to_db(peak)
		"rms":
			return linear_to_db(sqrt(total / maxf(count, 1)))
	var window: int = mini(int(stream.mix_rate * 0.1), count)
	var running: float = 0.0
	for index: int in range(window):
		running += squares[index]
	var loudest: float = running
	for index: int in range(window, count):
		running += squares[index] - squares[index - window]
		loudest = maxf(loudest, running)
	return linear_to_db(sqrt(loudest / maxf(window, 1)))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
