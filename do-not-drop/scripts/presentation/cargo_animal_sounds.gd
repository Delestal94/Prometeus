class_name CargoAnimalSounds
extends RefCounted
## The two sounds of the animals that go for the cargo (N-109) that the rest
## of the world didn't have: the gull's cry and the bees' buzz. The dog uses
## SynthAudio.dog_bark(). Synthesized like every other sound here and built
## once (each stream is read-only data, shared by every player), but kept out
## of synth_audio.gd, which the whole team shares.

const RATE: int = 22050
## Peaks they are normalised to; WorldMix sets how loud they play on top of it
## (test_cargo_animals measures the result against the mix classes).
const GULL_PEAK_DB: float = -6.0
const BUZZ_PEAK_DB: float = -12.0

static var _cache: Dictionary = {}


## "Kee-aah": a harsh, falling whistle with a noisy edge, two calls back to
## back, 0.7 s. One-shot.
static func gull_cry() -> AudioStreamWAV:
	if not _cache.has(&"gull_cry"):
		_cache[&"gull_cry"] = _make_gull_cry()
	return _cache[&"gull_cry"]


## A steady, slightly wobbling drone around 210 Hz, 0.5 s, built from whole
## cycles so it loops without a click.
static func bee_buzz() -> AudioStreamWAV:
	if not _cache.has(&"bee_buzz"):
		_cache[&"bee_buzz"] = _make_bee_buzz()
	return _cache[&"bee_buzz"]


static func _make_gull_cry() -> AudioStreamWAV:
	const DURATION: float = 0.7
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var noise := RandomNumberGenerator.new()
	noise.seed = 4109
	# [start, length, pitch at the start, pitch at the end] of each call.
	for call_shape: Array in [[0.0, 0.3, 1750.0, 1050.0], [0.36, 0.34, 1600.0, 850.0]]:
		var begin: int = int(float(call_shape[0]) * RATE)
		var length: int = int(float(call_shape[1]) * RATE)
		var phase: float = 0.0
		for i: int in range(length):
			if begin + i >= sample_count:
				break
			var k: float = float(i) / length
			var freq: float = lerpf(float(call_shape[2]), float(call_shape[3]), k) + sin(TAU * 31.0 * k) * 60.0
			phase += TAU * freq / RATE
			var tone: float = sin(phase) * 0.6 + sin(phase * 2.0) * 0.3 + sin(phase * 3.0) * 0.12
			var envelope: float = minf(k * 14.0, 1.0) * pow(1.0 - k, 0.8)
			mix[begin + i] += (tone + noise.randf_range(-1.0, 1.0) * 0.22) * envelope
	return _stream(mix, false, GULL_PEAK_DB)


static func _make_bee_buzz() -> AudioStreamWAV:
	const CYCLES: int = 105
	const FREQ: float = 210.0
	var sample_count: int = int(round(CYCLES / FREQ * RATE))
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	for i: int in range(sample_count):
		var k: float = float(i) / sample_count
		# 21 whole wobbles over the loop: the seam is continuous.
		var wobble: float = 0.62 + 0.38 * sin(TAU * 21.0 * k)
		var wave: float = 0.0
		for harmonic: int in range(1, 6):
			wave += sin(TAU * CYCLES * harmonic * k) / harmonic
		mix[i] = wave * wobble
	return _stream(mix, true, BUZZ_PEAK_DB)


static func _stream(mix: PackedFloat32Array, looped: bool, peak_db: float) -> AudioStreamWAV:
	var peak: float = 0.0001
	for value: float in mix:
		peak = maxf(peak, absf(value))
	var gain: float = db_to_linear(peak_db) / peak
	var data := PackedByteArray()
	data.resize(mix.size() * 2)
	for i: int in range(mix.size()):
		data.encode_s16(i * 2, int(clampf(mix[i] * gain, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = mix.size()
	return stream
