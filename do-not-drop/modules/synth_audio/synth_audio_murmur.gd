class_name SynthAudioMurmur
extends RefCounted
## Wordless murmurs, one voice per character (no recorded voice anywhere: text on screen and these). A murmur is a
## statement, not a call: one syllable per vowel group of the line (SYLLABLE_SECONDS each, at most MAX_SYLLABLES),
## a buzzing voice through a mouth that glides between vowels, the pitch settling down toward the end. Each voice
## is a preset of VOICES: its base pitch, how fast it talks, how much its pitch wanders, and whether it comes
## through a radio (a narrow band and a little hiss). Deterministic: the voice and the syllable count pick the
## vowels, so every peer hears the same line.

const RATE: int = 22050
const MAX_SYLLABLES: int = 12
const SYLLABLE_SECONDS: float = 0.11
const LOUDEST_DB: float = -14.0
## voice id -> {pitch (Hz), pace (syllable length factor), wander (0-1), radio (bool)}.
const VOICES: Dictionary = {
	&"boss": {"pitch": 205.0, "pace": 0.9, "wander": 0.08, "radio": true},
	&"depot_boss": {"pitch": 112.0, "pace": 1.2, "wander": 0.05, "radio": false},
	&"customer": {"pitch": 250.0, "pace": 1.0, "wander": 0.12, "radio": false},
	&"driver": {"pitch": 145.0, "pace": 1.05, "wander": 0.07, "radio": false},
}
const _VOWEL_FORMANTS: Array[Vector2] = [
	Vector2(800.0, 1250.0), Vector2(500.0, 1850.0), Vector2(320.0, 2300.0),
	Vector2(520.0, 900.0), Vector2(340.0, 750.0),
]


## The syllables of a line: its groups of vowels (Spanish or English), 1 to MAX_SYLLABLES.
static func syllables_of(text: String) -> int:
	var count: int = 0
	var in_vowel: bool = false
	for letter: String in text.to_lower():
		var vowel: bool = "aeiouáéíóúü".contains(letter)
		if vowel and not in_vowel:
			count += 1
		in_vowel = vowel
	return clampi(count, 1, MAX_SYLLABLES)


static func make(voice: StringName, count: int) -> AudioStreamWAV:
	var preset: Dictionary = VOICES.get(voice, VOICES[&"customer"])
	var syllable: float = SYLLABLE_SECONDS * float(preset["pace"])
	var duration: float = syllable * count + 0.08
	var sample_count: int = int(RATE * duration)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([voice, count])
	var vowels: Array[Vector2] = []
	var lifts: Array[float] = []
	var wander: float = float(preset["wander"])
	for s: int in range(count):
		vowels.append(_VOWEL_FORMANTS[rng.randi_range(0, _VOWEL_FORMANTS.size() - 1)])
		lifts.append(rng.randf_range(1.0 - wander, 1.0 + wander))
	var phase: float = 0.0
	var mouth_low := SynthAudioDsp.Resonator.new()
	var mouth_high := SynthAudioDsp.Resonator.new()
	var band := SynthAudioDsp.Resonator.new()
	var radio: bool = bool(preset["radio"])
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var s: int = mini(int(t / syllable), count - 1)
		var local: float = (t - s * syllable) / syllable
		# A statement: the line settles down toward its end.
		var pitch: float = float(preset["pitch"]) * lifts[s] * (1.0 - 0.12 * float(s) / count)
		phase = fmod(phase + pitch / RATE, 1.0)
		var buzz: float = 0.0
		for n: int in range(1, mini(int(4000.0 / pitch), 14) + 1):
			buzz += sin(TAU * phase * n) / float(n)
		var mouth: Vector2 = vowels[maxi(s - 1, 0)].lerp(vowels[s], minf(local * 4.0, 1.0))
		var sound: float = mouth_low.filter(buzz, mouth.x, 4.0, RATE)
		sound += mouth_high.filter(buzz, mouth.y, 6.0, RATE) * 0.5
		var envelope: float = 0.0
		if local <= 1.0:
			envelope = minf(local / 0.08, 1.0) * clampf((1.0 - local) / 0.25, 0.0, 1.0)
		sound *= envelope
		if radio:
			sound = band.filter(sound, 1400.0, 1.2, RATE) * 1.6 + rng.randf_range(-0.02, 0.02)
		mix[i] = sound
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, LOUDEST_DB, true)
	return stream
