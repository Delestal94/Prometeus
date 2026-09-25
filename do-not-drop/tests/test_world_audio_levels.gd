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
	"ambient": ["rms", -28.0],
	"nature": ["loudest", -24.0],
	"rain": ["rms", -24.0],
	"signal": ["loudest", -18.0],
	"detail": ["peak", -26.0],
	"music": ["rms", -24.0],
}
## [what, SynthAudio function, its level in world_mix.gd, class]
const SOUNDS: Array = [
	["truck engine", &"engine_loop", &"ENGINE_DB", "engine"],
	["truck impact", &"impact_thud", &"IMPACT_DB", "impact"],
	["tyre screech", &"tire_screech", &"SCREECH_DB", "signal"],
	["horn", &"honk_horn", &"HORN_DB", "signal"],
	["cargo clutter", &"impact_thud", &"CLUTTER_DB", "detail"],
	["wind", &"ambient_wind", &"WIND_DB", "ambient"],
	["birds", &"ambient_birds", &"BIRDS_DB", "nature"],
	["crickets", &"night_crickets", &"CRICKETS_DB", "nature"],
	["distant road", &"distant_road", &"DISTANT_ROAD_DB", "ambient"],
	["rain", &"rain_loop", &"RAIN_DB", "rain"],
	["crossing bell", &"crossing_bell", &"CROSSING_BELL_DB", "signal"],
	["dog bark", &"dog_bark", &"DOG_BARK_DB", "signal"],
	["sheep bleat", &"sheep_bleat", &"SHEEP_BLEAT_DB", "signal"],
	["doorbell", &"glass_chime", &"DOORBELL_DB", "signal"],
	["resident cheer", &"honk_horn", &"RESIDENT_CHEER_DB", "signal"],
	["resident groan", &"creature_groan", &"RESIDENT_GROAN_DB", "signal"],
	["warehouse hum", &"warehouse_hum", &"WAREHOUSE_HUM_DB", "ambient"],
	["depot radio", &"radio_tune", &"DEPOT_RADIO_DB", "music"],
	["forklift beeper", &"reverse_beep", &"FORKLIFT_BEEP_DB", "signal"],
	["forklift engine", &"engine_loop", &"FORKLIFT_ENGINE_DB", "ambient"],
	["roller door", &"roller_door", &"ROLLER_DOOR_DB", "signal"],
]

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
	if _failures == 0:
		print("PASS: every world and truck sound sits within %.0f dB of its class's target" % TOLERANCE_DB)
	quit(_failures)


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
