class_name SynthAudioCare
extends RefCounted
## The generators behind the care panel's cues (ui/hud/care_prompt_view.gd):
## short, bright interface sounds, so a passenger with their eyes on the road
## still hears "that tap counted", "wrong key" and "done". Split out like
## synth_audio_scenes.gd; SynthAudio hands them out and caches them, so
## callers never use this script directly.

const RATE: int = 22050


## A plucked "bip" for a tap that counted: 880 Hz plus its octave, quick
## decay, 110 ms. The panel raises its pitch step by step, so a sequence
## climbs as it's solved.
static func make_care_step() -> AudioStreamWAV:
	return _render(0.11, 0.55, func(t: float) -> float:
		var envelope: float = minf(t / 0.003, 1.0) * exp(-t * 28.0)
		return (sin(TAU * 880.0 * t) * 0.75 + sin(TAU * 1760.0 * t) * 0.2) * envelope)


## A low, falling double buzz for a wrong key: two soft-clipped tones
## (220 then 160 Hz), 240 ms. Clearly "no" without being a harsh alarm.
static func make_care_error() -> AudioStreamWAV:
	return _render(0.24, 0.5, func(t: float) -> float:
		var pitch: float = 220.0 if t < 0.11 else 160.0
		var local: float = t if t < 0.11 else t - 0.12
		if local < 0.0:
			return 0.0
		var envelope: float = minf(local / 0.006, 1.0) * exp(-local * 14.0)
		return tanh(sin(TAU * pitch * t) * 3.0) * 0.8 * envelope)


## A rising four-note arpeggio (C6 E6 G6 C7) for a finished job: a tool
## done, a module defused, a load secured. 480 ms.
static func make_care_success() -> AudioStreamWAV:
	const NOTES: Array[float] = [1046.5, 1318.5, 1568.0, 2093.0]
	const GAP: float = 0.075
	return _render(0.48, 0.5, func(t: float) -> float:
		var sample: float = 0.0
		for index: int in NOTES.size():
			var local: float = t - index * GAP
			if local < 0.0:
				continue
			var envelope: float = minf(local / 0.004, 1.0) * exp(-local * 9.0)
			sample += (sin(TAU * NOTES[index] * local) * 0.7 + sin(TAU * NOTES[index] * 2.0 * local) * 0.12) * envelope
		return sample * 0.55)


## A short airy swish for the arrow turning to a new direction: noise
## through a one-pole low-pass that opens and closes, 150 ms. Seeded, so
## it's the same swish every time.
static func make_care_whoosh() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var state: Array[float] = [0.0]
	return _render(0.15, 0.45, func(t: float) -> float:
		var shape: float = sin(PI * clampf(t / 0.15, 0.0, 1.0))
		var cutoff: float = lerpf(0.04, 0.35, shape)
		state[0] += (rng.randf_range(-1.0, 1.0) - state[0]) * cutoff
		return state[0] * shape * 1.6)


## A ratchet click for tool work creeping forward: a tiny noise burst with a
## 3 kHz edge, 35 ms. It repeats often, so it stays small.
static func make_care_tick() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	return _render(0.035, 0.4, func(t: float) -> float:
		var envelope: float = exp(-t * 130.0)
		return (rng.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * 3000.0 * t) * 0.5) * envelope)


## Samples `wave(t)` for `duration` seconds, fades the last 8 ms so nothing
## clicks, and scales to `gain` of full scale.
static func _render(duration: float, gain: float, wave: Callable) -> AudioStreamWAV:
	var count: int = int(RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i: int in count:
		var t: float = float(i) / RATE
		var fade: float = minf((duration - t) / 0.008, 1.0)
		var sample: float = clampf(float(wave.call(t)) * fade, -1.0, 1.0)
		data.encode_s16(i * 2, roundi(sample * gain * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
