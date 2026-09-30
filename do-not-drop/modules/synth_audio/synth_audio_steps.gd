class_name SynthAudioSteps
extends RefCounted
## The player's footfall (N-115: running makes steps you can hear, and the faster
## cadence is what tells a run from a walk). Split out like synth_audio_care.gd;
## SynthAudio hands it out and caches it, so callers never use this script directly.

const RATE: int = 22050
## Peak of the stream in full scale: world_mix.gd's FOOTSTEP_DB sits it in the
## "detail" class of the mix (small things, -26 dBFS peak).
const PEAK: float = 0.5


## The shared, cached stream; the sound audit finds it by SynthAudio's cache key.
static func footstep() -> AudioStreamWAV:
	return SynthAudio._cached(&"footstep", make_footstep)


## A soft shoe on the road: a low knock (the heel) and a short rustle of
## lowpassed noise (the gravel under it), 130 ms. Seeded, so every step is the
## same clip and the cadence carries the information.
static func make_footstep() -> AudioStreamWAV:
	const DURATION: float = 0.13
	var count: int = int(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var wave := PackedFloat32Array()
	wave.resize(count)
	var smooth: float = 0.0
	var peak: float = 0.0001
	for i: int in count:
		var t: float = float(i) / RATE
		var knock: float = sin(TAU * lerpf(110.0, 55.0, minf(t / 0.06, 1.0)) * t) * exp(-t * 38.0)
		smooth = lerpf(smooth, rng.randf_range(-1.0, 1.0), 0.28)
		var rustle: float = smooth * minf(t / 0.004, 1.0) * exp(-t * 55.0) * 0.7
		var sample: float = (knock + rustle) * minf((DURATION - t) / 0.01, 1.0)
		wave[i] = sample
		peak = maxf(peak, absf(sample))
	var data := PackedByteArray()
	data.resize(count * 2)
	for i: int in count:
		data.encode_s16(i * 2, roundi(wave[i] / peak * PEAK * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
