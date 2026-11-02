class_name SynthAudioThemeMusic
extends RefCounted
## Nine short looping themes composed in code, each with its own character (THEMES: tempo, key, mode, lead timbre,
## how busy the drums are), four bars that loop seamlessly (every note starts and dies inside the loop). A game
## gives each place one of them. Pure synthesis; SynthAudio caches the streams. Each theme is normalized to
## MUSIC_RMS_DB.
##
## A theme: bass on the chord root of each bar (the progression's degrees), a lead tune drawn from the mode with a
## fixed seed (the same notes every time), and drums at its density. Lead timbres: "sine" (bells, soft), "square"
## (chiptune), "saw" (reed, accordion-like), "fm" (marimba, steel drum).

const Dsp = preload("res://modules/synth_audio/synth_audio_dsp.gd")
const RATE: int = 22050
const BEATS: int = 16
const MUSIC_RMS_DB: float = -18.0
const MODES: Dictionary = {
	"major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10], "dorian": [0, 2, 3, 5, 7, 9, 10],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10], "lydian": [0, 2, 4, 6, 7, 9, 11], "phrygian": [0, 1, 3, 5, 7, 8, 10],
	"major_penta": [0, 2, 4, 7, 9], "minor_penta": [0, 3, 5, 7, 10],
}
## bpm, root (Hz, the bass's), mode, lead timbre, drums (0 none - 1 busy), progression (scale degrees per bar).
const THEMES: Array[Dictionary] = [
	{"bpm": 112.0, "root": 110.0, "mode": "minor_penta", "lead": "square", "drums": 0.8, "degrees": [0, 0, 3, 4]},
	{"bpm": 118.0, "root": 130.81, "mode": "major", "lead": "fm", "drums": 0.9, "degrees": [0, 5, 3, 4]},
	{"bpm": 100.0, "root": 98.0, "mode": "major_penta", "lead": "sine", "drums": 0.5, "degrees": [0, 3, 0, 4]},
	{"bpm": 92.0, "root": 146.83, "mode": "mixolydian", "lead": "saw", "drums": 0.6, "degrees": [0, 6, 3, 0]},
	{"bpm": 104.0, "root": 87.31, "mode": "dorian", "lead": "fm", "drums": 0.6, "degrees": [0, 3, 0, 4]},
	{"bpm": 96.0, "root": 164.81, "mode": "major_penta", "lead": "fm", "drums": 0.7, "degrees": [0, 2, 3, 4]},
	{"bpm": 84.0, "root": 73.42, "mode": "minor", "lead": "saw", "drums": 0.3, "degrees": [0, 5, 2, 6]},
	{"bpm": 76.0, "root": 123.47, "mode": "lydian", "lead": "sine", "drums": 0.15, "degrees": [0, 1, 0, 4]},
	{"bpm": 124.0, "root": 82.41, "mode": "phrygian", "lead": "square", "drums": 1.0, "degrees": [0, 1, 0, 6]},
]


static func loop_samples(theme: int) -> int:
	return int(round(RATE * BEATS * 60.0 / float(THEMES[theme]["bpm"])))


static func make(theme: int) -> AudioStreamWAV:
	var index: int = clampi(theme, 0, THEMES.size() - 1)
	var spec: Dictionary = THEMES[index]
	var count: int = loop_samples(index)
	var beat_s: float = 60.0 / float(spec["bpm"])
	var mode: Array = MODES[spec["mode"]]
	var tune: Array[int] = _tune(index, mode.size())
	var noise := RandomNumberGenerator.new()
	noise.seed = 4300 + index
	var mix := PackedFloat32Array()
	mix.resize(count)
	var duration: float = float(count) / RATE
	for i: int in count:
		var t: float = float(i) / RATE
		var beat: int = mini(int(t / beat_s), BEATS - 1)
		var in_beat: float = t - beat * beat_s
		var degree: int = int(spec["degrees"][beat >> 2])
		var bass_pitch: float = float(spec["root"]) * _ratio(mode, degree)
		var bass: float = sin(TAU * bass_pitch * t) * minf(in_beat / 0.005, 1.0) * exp(-in_beat * 4.0) * 0.55
		var slot: int = mini(int(t / (beat_s * 0.5)), tune.size() - 1)
		var in_note: float = t - slot * beat_s * 0.5
		var lead: float = 0.0
		if tune[slot] >= 0:
			var pitch: float = float(spec["root"]) * 4.0 * _ratio(mode, degree + tune[slot])
			var shape: float = minf(in_note / 0.004, 1.0) * exp(-in_note * 5.0)
			lead = _voice(String(spec["lead"]), pitch, in_note) * shape * 0.4
		var drums: float = _drums(float(spec["drums"]), beat, in_beat, beat_s, noise.randf_range(-1.0, 1.0))
		var edge: float = minf(minf(t, duration - t) / 0.01, 1.0)
		mix[i] = (bass + lead + drums) * maxf(edge, 0.0)
	return Dsp.loop(Dsp.normalized(mix, RATE, MUSIC_RMS_DB), RATE, count)


## The tune: 32 eighths of scale steps over the bar's chord (-1 rests), from a seed per theme.
static func _tune(theme: int, steps: int) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + theme * 31
	var notes: Array[int] = []
	var step: int = 0
	for slot: int in BEATS * 2:
		if rng.randf() < 0.3:
			notes.append(-1)
			continue
		step = clampi(step + rng.randi_range(-2, 2), 0, steps + 2)
		notes.append(step)
	return notes


## Frequency ratio of scale `degree` (may pass the octave) over the root.
static func _ratio(mode: Array, degree: int) -> float:
	var octave: int = floori(float(degree) / mode.size())
	return pow(2.0, (float(mode[posmod(degree, mode.size())]) + 12.0 * octave) / 12.0)


static func _voice(timbre: String, pitch: float, t: float) -> float:
	var phase: float = TAU * pitch * t
	match timbre:
		"square":
			return clampf(sin(phase) * 3.0, -1.0, 1.0) * 0.6
		"saw":
			return (sin(phase) + sin(phase * 2.0) / 2.0 + sin(phase * 3.0) / 3.0 + sin(phase * 4.0) / 4.0) * 0.6
		"fm":
			return sin(phase + 2.2 * exp(-t * 8.0) * sin(phase * 3.5))
	return sin(phase) + sin(phase * 2.0) * 0.15


## Kick on 1 and 3 above a little density, a snare on 2 and 4 above more, hats on the eighths when busy.
static func _drums(density: float, beat: int, in_beat: float, beat_s: float, white: float) -> float:
	var out: float = 0.0
	if density > 0.1 and beat % 2 == 0:
		out += sin(TAU * (48.0 + 80.0 * exp(-in_beat * 28.0)) * in_beat) * exp(-in_beat * 10.0) * 0.8
	if density > 0.4 and beat % 2 == 1:
		out += white * exp(-in_beat * 20.0) * 0.35
	if density > 0.65:
		var eighth: float = fmod(in_beat, beat_s * 0.5)
		out += white * exp(-eighth * 80.0) * 0.15
	return out * density
