class_name SynthAudioNewspaper
extends RefCounted
## The sounds of the next-day newspaper scene (N-606.4a, docs/diario-final.md):
## the rooster and the little birds of the morning, the hawker's "extra, extra!"
## with its brass hit, the paper being unfolded and turned, and the Boss
## spitting out his mate. Split out of synth_audio.gd by responsibility;
## SynthAudio hands them out (and caches them), so callers never use this
## class directly.
##
## All of them are one-shots, seeded (the same sound on every machine),
## 22.05 kHz mono, and normalised to the same loudest-100-ms level as the other
## scene sounds: where each one sits in the mix is WorldMix's call.

const RATE: int = 22050
const STREAM_LOUDEST_DB: float = -12.0
## Open "o" and bright "ee" of the rooster, and the hawker's "e" and "a": the
## two formants (Hz) a mouth shaped like that puts on the voice.
const VOWEL_O: Array[float] = [650.0, 1100.0]
const VOWEL_EE: Array[float] = [450.0, 2300.0]
const VOWEL_E: Array[float] = [560.0, 1850.0]
const VOWEL_A: Array[float] = [800.0, 1300.0]

## "Ki-ki-ri-kiiiii": [when, length, pitch at the start, pitch at the end,
## vowel at the start (0 = "o", 1 = "ee"), vowel at the end] -- seconds and Hz.
const ROOSTER_NOTES: Array = [
	[0.00, 0.17, 430.0, 600.0, 0.0, 0.2],
	[0.21, 0.30, 620.0, 860.0, 0.2, 0.9],
	[0.56, 0.22, 800.0, 700.0, 0.9, 0.5],
	[0.84, 0.95, 760.0, 420.0, 0.5, 0.0],
]
## [when, length, Hz at the start, Hz at the end] of every chirp.
const CHIRPS: Array = [
	[0.05, 0.07, 3000.0, 3500.0], [0.17, 0.06, 3400.0, 2900.0], [0.30, 0.09, 2700.0, 3300.0],
	[0.62, 0.08, 3200.0, 2600.0], [0.74, 0.06, 3500.0, 3000.0], [0.97, 0.10, 2800.0, 3400.0],
	[1.12, 0.07, 3300.0, 2800.0], [1.55, 0.08, 3100.0, 3500.0], [1.66, 0.07, 3400.0, 2900.0],
]
## The brass hit after the shout: [when, length, pitches...] -- two quick
## notes (G4, C5) and then the held C major chord.
const FANFARE_NOTES: Array = [
	[0.52, 0.12, [392.0]], [0.66, 0.12, [523.25]], [0.80, 1.10, [261.63, 392.0, 523.25, 659.25]],
]


## The rooster of the morning, "ki-ki-ri-kiiiii": four notes of a bright, nasal
## voice (a buzz of harmonics through two moving formants) that climb on
## the second and fall on the long last one, which breaks up near its middle.
## ~1.8 s: it should read as a rooster from a distance, not as a siren.
static func make_rooster_crow() -> AudioStreamWAV:
	const DURATION: float = 1.85
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	for index: int in ROOSTER_NOTES.size():
		var note: Array = ROOSTER_NOTES[index]
		var begin: int = int(float(note[0]) * RATE)
		var length: float = note[1]
		var last: bool = index == ROOSTER_NOTES.size() - 1
		var phase: float = 0.0
		var wobble: float = 0.0
		var breath: float = 0.0
		var low := SynthAudioDsp.Resonator.new()
		var high := SynthAudioDsp.Resonator.new()
		for i: int in range(mini(int(length * RATE), sample_count - begin)):
			var t: float = float(i) / RATE
			var k: float = t / length
			wobble = lerpf(wobble, rng.randf_range(-1.0, 1.0), 0.03)
			var pitch: float = lerpf(note[2], note[3], k) * (1.0 + 0.02 * wobble)
			if last:
				# A fast climb in the first quarter, and a crack of the voice on the way down.
				pitch += 140.0 * sin(PI * minf(k * 4.0, 1.0))
				pitch *= 1.12 if k > 0.42 and k < 0.5 else 1.0
			phase = fmod(phase + pitch / RATE, 1.0)
			var voice: float = 0.0
			for n: int in range(1, mini(int(6000.0 / pitch), 10) + 1):
				voice += sin(TAU * phase * n) / pow(float(n), 0.8)
			breath = lerpf(breath, rng.randf_range(-1.0, 1.0), 0.6)
			var source: float = voice * 0.5 + breath * 0.12
			var vowel: float = lerpf(note[4], note[5], k)
			var sound: float = (low.filter(source, lerpf(VOWEL_O[0], VOWEL_EE[0], vowel), 4.0, RATE)
					+ high.filter(source, lerpf(VOWEL_O[1], VOWEL_EE[1], vowel), 6.0, RATE) * 0.7 + source * 0.08)
			var envelope: float = minf(t / 0.012, 1.0) * minf((length - t) / (0.12 if last else 0.03), 1.0)
			mix[begin + i] += sound * envelope
	return _stream(mix)


## The little birds of the morning: nine short chirps in three small groups,
## each a soft sine sweep a bit under 3.5 kHz with a quick flutter, rounded in
## and out, so they sit behind the rooster instead of piercing. ~1.8 s.
static func make_morning_chirps() -> AudioStreamWAV:
	const DURATION: float = 1.85
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for chirp: Array in CHIRPS:
		var begin: int = int(float(chirp[0]) * RATE)
		var length: float = chirp[1]
		var level: float = rng.randf_range(0.6, 1.0)
		var phase: float = 0.0
		for i: int in range(mini(int(length * RATE), sample_count - begin)):
			var t: float = float(i) / RATE
			var k: float = t / length
			var freq: float = lerpf(chirp[2], chirp[3], k) * (1.0 + 0.06 * sin(TAU * 38.0 * t))
			phase += TAU * freq / RATE
			var envelope: float = pow(sin(PI * k), 0.7)
			mix[begin + i] += (sin(phase) + sin(phase * 2.0) * 0.18) * envelope * level
	return _stream(mix)


## The hawker's "¡extra!" and the hit that follows it: a shouted "ex-tra" (a
## voice with the "e" and the "a" in its mouth, a hiss for the "x" and a click
## for the "t"), then two quick brass notes and a held major chord with a cymbal
## wash. It tells you the headline is a big one. ~1.9 s.
static func make_extra_stinger() -> AudioStreamWAV:
	const DURATION: float = 1.95
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	# "ex" (0 - 0.17 s), the "x" hiss, "tra" (0.27 - 0.52 s).
	_shout(mix, rng, 0.0, 0.17, 240.0, 270.0, VOWEL_E, VOWEL_E)
	_shout(mix, rng, 0.27, 0.27, 300.0, 235.0, VOWEL_E, VOWEL_A)
	var smooth: float = 0.0
	for i: int in range(int(0.17 * RATE), int(0.27 * RATE)):
		var t: float = float(i) / RATE - 0.17
		var noise: float = rng.randf_range(-1.0, 1.0)
		smooth = lerpf(smooth, noise, 0.4)
		var click: float = rng.randf_range(-1.0, 1.0) if t > 0.085 and t < 0.092 else 0.0
		mix[i] += (noise - smooth) * sin(PI * t / 0.1) * 0.5 + click * 0.4
	for note: Array in FANFARE_NOTES:
		var begin: int = int(float(note[0]) * RATE)
		var length: float = note[1]
		var chord: Array = note[2]
		var phases: Array = []
		phases.resize(chord.size())
		phases.fill(0.0)
		for i: int in range(mini(int(length * RATE), sample_count - begin)):
			var t: float = float(i) / RATE
			var bright: float = 0.35 + 0.65 * exp(-t * 3.0)
			var brass: float = 0.0
			for voice: int in chord.size():
				phases[voice] = fmod(float(phases[voice]) + float(chord[voice]) * (1.0 + 0.002 * voice) / RATE, 1.0)
				for n: int in range(1, 9):
					brass += sin(TAU * float(phases[voice]) * n) / float(n) * (1.0 if n < 3 else bright)
			var envelope: float = minf(t / 0.015, 1.0) * exp(-t * (2.4 if length > 0.5 else 5.0)) \
					* minf((length - t) / 0.04, 1.0)
			mix[begin + i] += brass * envelope / maxf(chord.size(), 1) * 0.9
	# The cymbal wash under the chord.
	var wash: float = 0.0
	for i: int in range(int(0.8 * RATE), sample_count):
		var t: float = float(i) / RATE - 0.8
		var noise: float = rng.randf_range(-1.0, 1.0)
		var bright_noise: float = noise - wash
		wash = lerpf(wash, noise, 0.3)
		mix[i] += bright_noise * exp(-t * 4.5) * minf(t / 0.004, 1.0) * minf((DURATION - 0.8 - t) / 0.05, 1.0) * 0.22
	return _stream(mix)


## Unfolding a newspaper: a crinkling, irregular crunch of high noise that swells
## and settles, ~0.75 s. Quiet, close, with no pitch to speak of.
static func make_paper_rustle() -> AudioStreamWAV:
	const DURATION: float = 0.75
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var body: float = 0.0
	var grain: float = 0.0
	for i: int in range(sample_count):
		var k: float = float(i) / sample_count
		var noise: float = rng.randf_range(-1.0, 1.0)
		body = lerpf(body, noise, 0.25)
		if rng.randf() < 90.0 / RATE:
			grain = rng.randf_range(0.3, 1.0)
		grain *= exp(-1.0 / (RATE * 0.006))
		var swell: float = pow(sin(PI * k), 0.8) * (0.65 + 0.35 * sin(TAU * 2.5 * k + 1.0))
		mix[i] = (noise - body) * grain * swell
	return _stream(mix)


## Turning a page: a dry swish (noise through a band that sweeps up from the
## low mids to the highs) peaking at 0.35 s, and a soft flap where the sheet
## lands. ~0.55 s.
static func make_page_turn() -> AudioStreamWAV:
	const DURATION: float = 0.55
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	var band := SynthAudioDsp.Resonator.new()
	var soft: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var k: float = t / DURATION
		var noise: float = rng.randf_range(-1.0, 1.0)
		var swish: float = band.filter(noise, lerpf(700.0, 3200.0, pow(k, 1.5)), 1.4, RATE)
		swish *= pow(sin(PI * minf(pow(k / 0.75, 0.8), 1.0)), 1.2) if k < 0.75 else 0.0
		soft = lerpf(soft, noise, 0.08)
		var landed: float = t - 0.36
		var flap: float = soft * exp(-landed * 38.0) * minf(landed / 0.003, 1.0) if landed > 0.0 else 0.0
		mix[i] = swish * 3.0 + flap * 2.2
	return _stream(mix)


## The Boss spitting out his mate: a short wet "pffft" (noise through a band
## around 2.5 kHz with the lips fluttering at a slowing rate, loudest at the
## start) and then the drops falling on the paper: a few tiny "plip"s that
## fall in pitch, and two heavier splats. ~1.0 s of comic outrage.
static func make_mate_spit() -> AudioStreamWAV:
	const DURATION: float = 1.0
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 67
	var band := SynthAudioDsp.Resonator.new()
	var flutter_phase: float = 0.0
	for i: int in range(int(0.36 * RATE)):
		var t: float = float(i) / RATE
		var k: float = t / 0.36
		flutter_phase += TAU * lerpf(70.0, 25.0, k) / RATE
		var spray: float = band.filter(rng.randf_range(-1.0, 1.0), 2500.0, 0.7, RATE)
		var envelope: float = minf(t / 0.008, 1.0) * exp(-t * 7.0) * minf((0.36 - t) / 0.03, 1.0)
		mix[i] += spray * (0.55 + 0.45 * sin(flutter_phase)) * envelope * 2.0
	for drop: float in [0.34, 0.41, 0.47, 0.58, 0.66, 0.73, 0.88]:
		var begin: int = int(drop * RATE)
		var level: float = rng.randf_range(0.12, 0.25)
		var base: float = rng.randf_range(1100.0, 1600.0)
		for i: int in range(mini(int(0.02 * RATE), sample_count - begin)):
			var t: float = float(i) / RATE
			mix[begin + i] += sin(TAU * lerpf(base, base * 0.4, t / 0.02) * t) * exp(-t * 150.0) * level
	var dull: float = 0.0
	for splat: float in [0.52, 0.80]:
		var begin: int = int(splat * RATE)
		for i: int in range(mini(int(0.05 * RATE), sample_count - begin)):
			var t: float = float(i) / RATE
			dull = lerpf(dull, rng.randf_range(-1.0, 1.0), 0.2)
			mix[begin + i] += dull * exp(-t * 70.0) * minf(t / 0.002, 1.0) * 0.45
	return _stream(mix)


## A shouted syllable into `mix` at `when` seconds: a buzz of harmonics at the
## pitch (Hz, from `from_hz` to `to_hz`) through two formants that move from
## one vowel to the other. Shared by the hawker's "ex" and "tra".
static func _shout(mix: PackedFloat32Array, rng: RandomNumberGenerator, when: float, length: float,
		from_hz: float, to_hz: float, from_vowel: Array[float], to_vowel: Array[float]) -> void:
	var begin: int = int(when * RATE)
	var phase: float = 0.0
	var breath: float = 0.0
	var low := SynthAudioDsp.Resonator.new()
	var high := SynthAudioDsp.Resonator.new()
	for i: int in range(mini(int(length * RATE), mix.size() - begin)):
		var t: float = float(i) / RATE
		var k: float = t / length
		var pitch: float = lerpf(from_hz, to_hz, k)
		phase = fmod(phase + pitch / RATE, 1.0)
		var voice: float = 0.0
		for n: int in range(1, mini(int(5000.0 / pitch), 16) + 1):
			voice += sin(TAU * phase * n) / float(n)
		breath = lerpf(breath, rng.randf_range(-1.0, 1.0), 0.6)
		var source: float = voice * 0.5 + breath * 0.2
		var sound: float = (low.filter(source, lerpf(from_vowel[0], to_vowel[0], k), 4.0, RATE)
				+ high.filter(source, lerpf(from_vowel[1], to_vowel[1], k), 6.0, RATE) * 0.7)
		mix[begin + i] += sound * minf(t / 0.01, 1.0) * minf((length - t) / 0.04, 1.0) * 0.8


static func _stream(mix: PackedFloat32Array) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, STREAM_LOUDEST_DB, true)
	return stream
