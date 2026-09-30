class_name SynthAudioVehicle
extends RefCounted
## The generators of the truck itself: the three engine layers, the impact thud,
## the tyre screech and the horn. Split out of synth_audio.gd by responsibility;
## SynthAudio hands them out (and caches them), so callers never use this class
## directly. VehiclePresentation and player.gd decide when, how loud and at what pitch.


## Quiet harmonic exhaust loop. Integer periods keep the seam continuous;
## pitch and volume are adjusted by VehiclePresentation, not by simulation.
static func make_engine_loop() -> AudioStreamWAV:
	const RATE: int = 22050
	var data := PackedByteArray()
	data.resize(RATE * 2)
	for index: int in range(RATE):
		var phase: float = TAU * 48.0 * float(index) / float(RATE)
		var wave: float = (sin(phase) * 0.46 + sin(phase * 2.0) * 0.22 + sin(phase * 3.0) * 0.10
			+ sin(phase * 0.5) * 0.10)
		data.encode_s16(index * 2, roundi(wave * 20000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = RATE
	return stream


## The engine's other two layers (tareas de Nacho N-401). VehiclePresentation
## crossfades idle / engine_loop() / high by a simulated rev counter, so the
## three are built to the same loudness (ENGINE_LAYER_RMS, engine_loop()'s own)
## and a crossfade never swells or dips. Integer frequencies over a one-second
## buffer: every partial ends where it started, so the loop has no seam.
const ENGINE_LAYER_RMS: float = 0.2286


## Ticking over: a low, lumpy rumble -- the firing rhythm (8 Hz) nods the
## level of a 32 Hz base with a strong second harmonic.
static func make_engine_idle_loop() -> AudioStreamWAV:
	return _engine_layer(func(t: float) -> float:
		var phase: float = TAU * 32.0 * t
		var lope: float = 0.72 + 0.28 * sin(TAU * 8.0 * t) * sin(TAU * 8.0 * t)
		return (sin(phase) * 0.5 + sin(phase * 2.0) * 0.34 + sin(phase * 3.0) * 0.12 + sin(phase * 0.5) * 0.18) * lope)


## Revving hard: the same engine higher up, its upper harmonics louder (the
## strain you hear in the cab just before a gear change).
static func make_engine_high_loop() -> AudioStreamWAV:
	return _engine_layer(func(t: float) -> float:
		var phase: float = TAU * 64.0 * t
		return (sin(phase) * 0.36 + sin(phase * 2.0) * 0.28 + sin(phase * 3.0) * 0.2 + sin(phase * 4.0) * 0.14
			+ sin(phase * 6.0) * 0.08))


static func _engine_layer(wave: Callable) -> AudioStreamWAV:
	const RATE: int = 22050
	var samples := PackedFloat32Array()
	samples.resize(RATE)
	var power: float = 0.0
	for index: int in range(RATE):
		var value: float = float(wave.call(float(index) / float(RATE)))
		samples[index] = value
		power += value * value
	var gain: float = ENGINE_LAYER_RMS / maxf(sqrt(power / float(RATE)), 0.0001)
	var data := PackedByteArray()
	data.resize(RATE * 2)
	for index: int in range(RATE):
		data.encode_s16(index * 2, roundi(clampf(samples[index] * gain, -1.0, 1.0) * 32767.0))
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
static func make_impact_thud() -> AudioStreamWAV:
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
static func make_tire_screech() -> AudioStreamWAV:
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


## A classic two-tone car horn: two square waves close enough in pitch to
## beat against each other, with a short fade in/out so it doesn't click.
static func make_honk_horn() -> AudioStreamWAV:
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
