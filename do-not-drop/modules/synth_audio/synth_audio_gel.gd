class_name SynthAudioGel
extends RefCounted
## Deterministic, asset-free foley for the gel player. Every cue is a short
## mono one-shot; SynthAudio owns the cache so all players share the samples.

enum Surface { ROAD, GRAVEL, METAL, SOFT }
enum Cue { FOOTSTEP, JUMP, LANDING, BOUNCE, HIT, STRETCH, MELT, REASSEMBLE }

const RATE: int = 22050
const PEAK: float = 0.58
const SURFACE_NAMES: Array[StringName] = [&"road", &"gravel", &"metal", &"soft"]


static func make_footstep(surface: int = Surface.ROAD) -> AudioStreamWAV:
	return _make(Cue.FOOTSTEP, clampi(surface, Surface.ROAD, Surface.SOFT))


static func make_jump() -> AudioStreamWAV:
	return _make(Cue.JUMP)


static func make_landing() -> AudioStreamWAV:
	return _make(Cue.LANDING)


static func make_bounce() -> AudioStreamWAV:
	return _make(Cue.BOUNCE)


static func make_hit() -> AudioStreamWAV:
	return _make(Cue.HIT)


static func make_stretch() -> AudioStreamWAV:
	return _make(Cue.STRETCH)


static func make_melt() -> AudioStreamWAV:
	return _make(Cue.MELT)


static func make_reassemble() -> AudioStreamWAV:
	return _make(Cue.REASSEMBLE)


static func surface_name(surface: int) -> StringName:
	return SURFACE_NAMES[clampi(surface, Surface.ROAD, Surface.SOFT)]


static func _make(cue: Cue, variant: int = 0) -> AudioStreamWAV:
	var duration: float = _duration(cue)
	var count: int = int(RATE * duration)
	var rng := RandomNumberGenerator.new()
	rng.seed = 311960 + int(cue) * 101 + variant * 17
	var wave := PackedFloat32Array()
	wave.resize(count)
	var loudest: float = 0.0001
	var smooth_noise: float = 0.0
	for index: int in count:
		var time: float = float(index) / RATE
		var progress: float = time / duration
		smooth_noise = lerpf(smooth_noise, rng.randf_range(-1.0, 1.0), 0.22)
		var sample: float = _sample(cue, variant, time, progress, smooth_noise)
		wave[index] = sample
		loudest = maxf(loudest, absf(sample))
	var data := PackedByteArray()
	data.resize(count * 2)
	for index: int in count:
		data.encode_s16(index * 2, roundi(wave[index] / loudest * PEAK * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


static func _duration(cue: Cue) -> float:
	match cue:
		Cue.FOOTSTEP:
			return 0.16
		Cue.JUMP, Cue.BOUNCE, Cue.HIT:
			return 0.28
		Cue.LANDING:
			return 0.36
		Cue.STRETCH:
			return 0.46
		Cue.MELT:
			return 0.88
		_:
			return 1.02


static func _sample(cue: Cue, variant: int, time: float, progress: float, noise: float) -> float:
	var release: float = smoothstep(1.0, 0.72, progress)
	var attack: float = smoothstep(0.0, 0.025, progress)
	match cue:
		Cue.FOOTSTEP:
			return _footstep_sample(variant, time, progress, noise) * attack * release
		Cue.JUMP:
			var suction: float = sin(TAU * (62.0 * time + 135.0 * time * time))
			return (suction * 0.82 + noise * 0.18) * attack * release
		Cue.LANDING:
			var plop: float = sin(TAU * (105.0 * time - 85.0 * time * time)) * exp(-time * 8.0)
			var slap: float = noise * exp(-time * 19.0)
			return (plop + slap * 0.62) * attack * release
		Cue.BOUNCE:
			var wobble: float = sin(TAU * (170.0 * time - 115.0 * time * time))
			return wobble * (0.72 + 0.28 * cos(TAU * 13.0 * time)) * attack * release
		Cue.HIT:
			var thump: float = sin(TAU * (92.0 * time - 52.0 * time * time)) * exp(-time * 11.0)
			return (thump + noise * exp(-time * 25.0) * 0.72) * attack * release
		Cue.STRETCH:
			var elastic: float = sin(TAU * (74.0 * time + 165.0 * time * time))
			return (elastic * 0.84 + noise * 0.16) * attack * release
		Cue.MELT:
			var sink: float = sin(TAU * (148.0 * time - 61.0 * time * time))
			var bubbles: float = sin(TAU * 17.0 * time) * sin(TAU * 6.0 * time)
			return (sink * 0.48 + noise * 0.38 + bubbles * 0.14) * attack * release
		_:
			var gather: float = sin(TAU * (55.0 * time + 102.0 * time * time))
			var beads: float = sin(TAU * 9.0 * time) * sin(TAU * 230.0 * time)
			return (gather * 0.72 + beads * 0.18 + noise * 0.10) * attack * release


static func _footstep_sample(surface: int, time: float, progress: float, noise: float) -> float:
	var falloff: float = exp(-time * 24.0)
	match surface:
		Surface.GRAVEL:
			var crackle: float = signf(noise) * pow(absf(noise), 0.35)
			return (sin(TAU * 78.0 * time) * 0.48 + crackle * 0.76) * falloff
		Surface.METAL:
			var ring: float = sin(TAU * 430.0 * time) + sin(TAU * 690.0 * time) * 0.42
			return (ring * 0.44 + sin(TAU * 96.0 * time) * 0.68) * falloff
		Surface.SOFT:
			var deep: float = sin(TAU * (72.0 * time - 25.0 * time * time))
			return (deep * 0.9 + noise * 0.26) * smoothstep(0.0, 0.08, progress) * falloff
		_:
			var squish: float = sin(TAU * (112.0 * time - 42.0 * time * time))
			return (squish * 0.78 + noise * 0.34) * falloff
