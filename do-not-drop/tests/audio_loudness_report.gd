extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/audio_loudness_report.gd
##
## S-404: objective mix check for Slatex-owned trap and UI cues. Both RMS and
## peak are reported; the acceptance target uses RMS at the player's configured
## reference-distance level.

const SynthAudio = preload("res://scripts/presentation/synth_audio.gd")
const SynthAudioTraps = preload("res://scripts/presentation/synth_audio_traps.gd")
const PackageFeedback = preload("res://scripts/gameplay/package/package_feedback.gd")
const UiSounds = preload("res://scripts/ui/ui_sounds.gd")
const TOLERANCE_DB: float = 2.0
const TRAP_TARGET_DBFS: float = -18.0
const UI_TARGET_DBFS: float = -24.0

const TRAP_SOUNDS: Array = [
	[&"glass_chime", "Frágil"],
	[&"creature_groan", "Ruidoso"],
	[&"wood_creak", "Peso creciente"],
	[&"liquid_slosh", "Líquido"],
	[&"explosive_tick", "Explosivo"],
	[&"cushion_pad", "Frágil, amortiguado", SynthAudioTraps],
	[&"hostile_hiss", "Hostil"],
	[&"comic_ruin_stinger", "Ruina general"],
	[&"comic_boom", "Ruina explosiva"],
]

var _failures: int = 0


func _initialize() -> void:
	print("REPORT | group | sound | stream RMS | stream peak | level | result RMS | target | off")
	var trap_levels: Dictionary = (PackageFeedback as Script).get_script_constant_map()[&"TRAP_SOUND_LEVELS_DB"]
	for entry: Array in TRAP_SOUNDS:
		var cue: StringName = entry[0]
		var source: Script = entry[2] if entry.size() > 2 else SynthAudio
		var stream: AudioStreamWAV = source.call(cue)
		_check(String(entry[1]), "trap", stream, float(trap_levels[cue]), TRAP_TARGET_DBFS)
	for cue: StringName in UiSounds.CUES:
		_check(String(cue), "ui", UiSounds.stream_for(cue), UiSounds.volume_db_for(cue), UI_TARGET_DBFS)
	if _failures == 0:
		print("PASS: every trap and UI cue is within %.0f dB of its RMS target" % TOLERANCE_DB)
	quit(_failures)


func _check(label: String, group: String, stream: AudioStreamWAV, level_db: float, target_dbfs: float) -> void:
	var rms_dbfs: float = measure_rms_dbfs(stream)
	var peak_dbfs: float = measure_peak_dbfs(stream)
	var result_dbfs: float = rms_dbfs + level_db
	var difference: float = result_dbfs - target_dbfs
	print("REPORT | %s | %s | %.1f | %.1f | %.1f | %.1f | %.1f | %+.1f" % [
		group, label, rms_dbfs, peak_dbfs, level_db, result_dbfs, target_dbfs, difference,
	])
	_expect(absf(difference) <= TOLERANCE_DB,
		"%s %s lands at %.1f dBFS RMS, target %.1f ± %.0f" % [group, label, result_dbfs, target_dbfs, TOLERANCE_DB])


static func measure_rms_dbfs(stream: AudioStreamWAV) -> float:
	var data: PackedByteArray = stream.data
	var count: int = data.size() / 2
	var power: float = 0.0
	for index: int in range(count):
		var sample: float = data.decode_s16(index * 2) / 32768.0
		power += sample * sample
	return linear_to_db(sqrt(power / maxf(count, 1)))


static func measure_peak_dbfs(stream: AudioStreamWAV) -> float:
	var data: PackedByteArray = stream.data
	var peak: float = 0.0
	for index: int in range(data.size() / 2):
		peak = maxf(peak, absf(data.decode_s16(index * 2) / 32768.0))
	return linear_to_db(peak)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
