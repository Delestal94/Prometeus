class_name SynthAudioAnimals
extends RefCounted
## The generators of the road's fauna: the chasing dog's bark and the flock's
## bleat. Split out of synth_audio.gd by responsibility; SynthAudio hands them
## out (and caches them), so callers never use this class directly.


## A dog's bark (the chasing dog, tareas de Nacho N-106/N-405): "guau", a
## voice through a mouth. The voice is a buzz of harmonics whose pitch
## jumps up as the bark opens and falls away, with a little breath on it;
## the mouth is two resonances (formants) that open from "u" to "a" and
## close again. The first version was a clipped sine sliding down, with
## no mouth at all -- it read as a synth, not a dog (playtest 2026-09-25).
## 0.24 s. One-shot; ChasingDog repeats it, doubled up now and then.
const DOG_BARK_STREAM_LOUDEST_DB: float = -12.0


static func make_dog_bark() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.24
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var phase: float = 0.0
	var breath: float = 0.0
	var wobble: float = 0.0
	var mouth_low := SynthAudioDsp.Resonator.new()
	var mouth_high := SynthAudioDsp.Resonator.new()
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var k: float = t / DURATION
		# Pitch: up fast as it opens (~0.03 s), then down; a slight roughness.
		wobble = lerpf(wobble, rng.randf_range(-1.0, 1.0), 0.02)
		var pitch: float = ((lerpf(360.0, 560.0, minf(t / 0.03, 1.0)) - 240.0 * maxf(k - 0.12, 0.0))
			* (1.0 + 0.03 * wobble))
		phase = fmod(phase + pitch / RATE, 1.0)
		# Band-limited buzz: harmonics falling off as 1/n, up to ~5 kHz.
		var voice: float = 0.0
		var harmonics: int = mini(int(5000.0 / pitch), 14)
		for n: int in range(1, harmonics + 1):
			voice += sin(TAU * phase * n) / float(n)
		breath = lerpf(breath, rng.randf_range(-1.0, 1.0), 0.7)
		var source: float = voice * 0.5 + breath * lerpf(0.9, 0.25, minf(k * 3.0, 1.0))
		# The mouth: "u" (closed) to "a" and back as the bark ends.
		var open: float = sin(PI * pow(k, 0.6))
		var sound: float = (mouth_low.filter(source, lerpf(380.0, 820.0, open), 3.5, RATE)
			+ mouth_high.filter(source, lerpf(1000.0, 1700.0, open), 5.0, RATE) * 0.6)
		var envelope: float = minf(t / 0.008, 1.0) * pow(1.0 - k, 1.8)
		mix[i] = sound * envelope
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, DOG_BARK_STREAM_LOUDEST_DB, true)
	return stream


## A sheep's bleat (the flock, tareas de Nacho N-106/N-405): a nasal
## "meeh" around 330 Hz with a fast vibrato that gives it the wobble,
## 0.6 s. One-shot.
static func make_sheep_bleat() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.6
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var k: float = t / DURATION
		var freq: float = 330.0 + sin(TAU * 17.0 * t) * 28.0 - k * 40.0
		phase += TAU * freq / RATE
		# Odd harmonics make it nasal.
		var wave: float = sin(phase) * 0.55 + sin(phase * 3.0) * 0.25 + sin(phase * 5.0) * 0.12
		var envelope: float = minf(k * 12.0, 1.0) * minf((1.0 - k) * 5.0, 1.0)
		data.encode_s16(i * 2, int(clampf(wave * envelope, -1.0, 1.0) * 32767.0 * 0.7))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
