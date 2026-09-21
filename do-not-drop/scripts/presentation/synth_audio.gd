class_name SynthAudio
extends RefCounted
## Tiny procedural waveforms, generated at runtime instead of shipping .wav
## assets -- same "no art yet, code is the source of truth" convention as
## route.gd's boxes and package_feedback.gd's confetti cubes.

## Quiet harmonic exhaust loop. Integer periods keep the seam continuous;
## pitch and volume are adjusted by VehiclePresentation, not by simulation.
static func engine_loop() -> AudioStreamWAV:
	const RATE: int = 22050
	var data := PackedByteArray()
	data.resize(RATE * 2)
	for index: int in range(RATE):
		var phase: float = TAU * 48.0 * float(index) / float(RATE)
		var wave: float = sin(phase) * 0.46 + sin(phase * 2.0) * 0.22 + sin(phase * 3.0) * 0.10 + sin(phase * 0.5) * 0.10
		data.encode_s16(index * 2, roundi(wave * 20000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = RATE
	return stream


## A short, low-frequency thump for vehicle_impact -- a sine "punch" under a
## burst of filtered noise, gone in a fifth of a second. Volume/whether it
## plays at all is VehiclePresentation's call (it already gates on strength);
## this only shapes what a single hit sounds like.
static func impact_thud() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.22
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var noise_state: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var envelope: float = exp(-t * 18.0)
		noise_state = lerpf(noise_state, randf_range(-1.0, 1.0), 0.6)
		var punch: float = sin(TAU * 75.0 * t) * 0.7
		var sample: float = clampf((punch + noise_state * 0.5) * envelope, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


## Looping tire screech -- harsh mid-band noise plus a resonant tone, meant
## to have its pitch/volume driven externally by wheel skid amount rather
## than baking speed into the clip itself.
static func tire_screech() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.5
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var noise_state: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		noise_state = lerpf(noise_state, randf_range(-1.0, 1.0), 0.5)
		var tone: float = sin(TAU * 950.0 * t) * 0.35
		var sample: float = clampf(noise_state * 0.55 + tone, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


## Frágil's cue: a short, bright, fast-decaying chime -- three inharmonic
## partials, the classic cheap "bell" trick. Pitched down a fourth for
## RUINED vs. AT_RISK by whoever plays it (see package_feedback.gd), so
## the same clip reads as two different severities.
static func glass_chime() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.5
	const PARTIALS: Array[float] = [1800.0, 2650.0, 3400.0]
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var envelope: float = exp(-t * 9.0)
		var wave: float = 0.0
		for partial: float in PARTIALS:
			wave += sin(TAU * partial * t)
		var sample: float = clampf(wave / PARTIALS.size() * envelope, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


## Ruidoso's cue: a low, looping, organic groan -- a wobbling low tone with
## a slow vibrato and a little noise, meant to be pitched/mixed by agitation
## rather than describing intensity itself.
static func creature_groan() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 1.2
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var noise_state: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var vibrato: float = sin(TAU * 4.5 * t) * 6.0
		var base_freq: float = 95.0 + vibrato
		noise_state = lerpf(noise_state, randf_range(-1.0, 1.0), 0.3)
		var wave: float = sin(TAU * base_freq * t) * 0.75 + sin(TAU * base_freq * 1.5 * t) * 0.15
		var sample: float = clampf(wave + noise_state * 0.08, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


## Peso Creciente's cue: a short, irregular downward pitch-bend burst with a
## little noise -- strained wood, not a smooth tone. One-shot, meant to be
## retriggered every so often while the crate is under distress rather than
## looped continuously (real creaking isn't constant).
static func wood_creak() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.35
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var progress: float = t / DURATION
		var freq: float = lerpf(260.0, 90.0, progress) + randf_range(-12.0, 12.0)
		phase += freq / RATE
		var envelope: float = (1.0 - progress) * (0.6 + 0.4 * sin(progress * PI))
		var wave: float = (fmod(phase, 1.0) * 2.0 - 1.0) * 0.6  # cheap sawtooth
		var sample: float = clampf(wave * envelope, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


## A classic two-tone car horn: two square waves close enough in pitch to
## beat against each other, with a short fade in/out so it doesn't click.
static func honk_horn() -> AudioStreamWAV:
	const SAMPLE_RATE: int = 22050
	const DURATION: float = 0.42
	const FREQ_A: float = 311.0
	const FREQ_B: float = 415.0
	const ATTACK: float = 0.02
	const RELEASE: float = 0.08

	var sample_count: int = int(SAMPLE_RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)  # 16-bit mono
	for i: int in range(sample_count):
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = 1.0
		if t < ATTACK:
			envelope = t / ATTACK
		elif t > DURATION - RELEASE:
			envelope = (DURATION - t) / RELEASE
		var wave: float = (signf(sin(TAU * FREQ_A * t)) + signf(sin(TAU * FREQ_B * t))) * 0.5
		var sample: float = clampf(wave * envelope * 0.6, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
