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
