class_name SynthAudioGelPerformance
extends RefCounted
## Wordless gel voice and one short procedural loop for each authored dance.
## SynthAudio caches the resulting streams; no recorded voice or music asset
## is shipped and every peer builds identical samples.

const Scenes = preload("res://modules/synth_audio/synth_audio_scenes.gd")
const Dsp = preload("res://modules/synth_audio/synth_audio_dsp.gd")
const RATE: int = 22050
const VOICE_LOUDEST_DB: float = -12.0
const MUSIC_RMS_DB: float = -18.0
const DANCE_CLIPS: Array[StringName] = [
	&"SimpleStep", &"Robot", &"Disco", &"FloorWorm", &"Headbang",
	&"VictoryDance", &"Flan", &"Conga",
]
const DANCE_DURATIONS: Dictionary = {
	&"SimpleStep": 2.4, &"Robot": 2.4, &"Disco": 2.8, &"FloorWorm": 3.2,
	&"Headbang": 1.6, &"VictoryDance": 2.8, &"Flan": 2.4, &"Conga": 2.4,
}
const ROOT_PITCHES: Array[float] = [196.0, 130.81, 220.0, 98.0, 82.41, 261.63, 174.61, 146.83]
const STEPS: Array = [
	[0, 4, 7, 4, 9, 7],
	[0, 0, 3, 0, 6, 3],
	[0, 7, 9, 7, 12, 9, 7],
	[0, -2, -5, -2, 3, 0, -2, -5],
	[0, 0, -2, 0, 3, 0, -2, 5],
	[0, 4, 7, 12, 11, 12, 16],
	[0, 3, 7, 10, 7, 3],
	[0, 3, 5, 7, 5, 3],
]


static func make_gel_voice(slot: int, syllables: int) -> AudioStreamWAV:
	var safe_slot: int = posmod(slot, Scenes.CALLOUT_VOICE_PITCHES.size())
	var safe_count: int = clampi(syllables, 1, Scenes.CALLOUT_MAX_SYLLABLES)
	var source: AudioStreamWAV = Scenes.make_callout_voice(safe_slot, safe_count)
	var sample_count: int = source.data.size() / 2
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var delay: int = int(RATE * 0.012)
	for index: int in sample_count:
		var time: float = float(index) / RATE
		var dry: float = float(source.data.decode_s16(index * 2)) / 32767.0
		var echo: float = 0.0
		if index >= delay:
			echo = float(source.data.decode_s16((index - delay) * 2)) / 32767.0
		var wobble: float = 1.0 + 0.09 * sin(TAU * 7.0 * time + safe_slot * 0.37)
		var bubble: float = sin(TAU * (410.0 + safe_slot * 18.0) * time) \
				* pow(maxf(sin(TAU * time / Scenes.CALLOUT_SYLLABLE_SECONDS), 0.0), 12.0) * 0.07
		mix[index] = dry * wobble * 0.82 + echo * 0.23 + bubble
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = Dsp.normalized(mix, RATE, VOICE_LOUDEST_DB, true)
	return stream


static func make_dance_music(clip: StringName) -> AudioStreamWAV:
	var dance: int = DANCE_CLIPS.find(clip)
	if dance < 0:
		dance = 0
	var duration: float = float(DANCE_DURATIONS[DANCE_CLIPS[dance]])
	var count: int = int(RATE * duration)
	var mix := PackedFloat32Array()
	mix.resize(count)
	var pattern: Array = STEPS[dance]
	var beat_seconds: float = duration / pattern.size()
	var root_pitch: float = ROOT_PITCHES[dance]
	for index: int in count:
		var time: float = float(index) / RATE
		var beat: int = mini(int(time / beat_seconds), pattern.size() - 1)
		var local: float = fmod(time, beat_seconds) / beat_seconds
		var pitch: float = root_pitch * pow(2.0, float(pattern[beat]) / 12.0)
		var tone: float = _dance_tone(dance, pitch, time, local)
		var rhythm: float = _dance_rhythm(dance, time, local, beat)
		var edge: float = minf(minf(time, duration - time) / 0.012, 1.0)
		mix[index] = (tone + rhythm) * maxf(edge, 0.0)
	var data: PackedByteArray = Dsp.normalized(mix, RATE, MUSIC_RMS_DB, false)
	return Dsp.loop(data, RATE, count)


static func _dance_tone(dance: int, pitch: float, time: float, local: float) -> float:
	var envelope: float = exp(-local * (4.0 if dance in [0, 5, 7] else 2.0))
	var phase: float = TAU * pitch * time
	match dance:
		0:
			return (sin(phase) + sin(phase * 2.0) * 0.28) * envelope * 0.34
		1:
			return (sin(phase) + sin(phase * 3.0) / 3.0 + sin(phase * 5.0) / 5.0) * 0.24
		2:
			return (sin(phase) * 0.34 + sin(phase * 0.5) * 0.24) * (0.72 + 0.28 * sin(TAU * 4.0 * time))
		3:
			return sin(phase + 1.8 * sin(TAU * 1.25 * time)) * 0.42
		4:
			return clampf(sin(phase) * 2.4, -1.0, 1.0) * exp(-local * 1.4) * 0.32
		5:
			return (sin(phase) + sin(phase * 1.5) * 0.42 + sin(phase * 2.0) * 0.25) * envelope * 0.32
		6:
			return sin(phase + 2.2 * sin(TAU * 3.0 * time)) * (0.65 + 0.35 * sin(TAU * 6.0 * time)) * 0.38
		_:
			return (sin(phase) * 0.32 + sin(phase * 2.0) * 0.16) * envelope


static func _dance_rhythm(dance: int, time: float, local: float, beat: int) -> float:
	var kick: float = sin(TAU * (72.0 - local * 24.0) * time) * exp(-local * 13.0)
	var click: float = sin(TAU * (1100.0 + dance * 95.0) * time) * exp(-local * 34.0)
	if dance == 7:
		return kick * 0.26 + click * (0.22 if beat % 2 == 0 else 0.13)
	if dance == 4:
		return kick * 0.48 + click * 0.08
	if dance == 2:
		return kick * 0.34 + click * (0.12 if beat % 2 == 1 else 0.04)
	return kick * 0.18 + click * 0.07
