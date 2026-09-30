class_name SynthAudioDsp
extends RefCounted
## The small tools every generator in this module shares: the cross-faded loop
## seam, the loudness normalizer, the looping stream wrapper and a moving
## band-pass. Pure functions, no state and no cache -- SynthAudio (and the other
## generator scripts) call them; nothing here knows about a particular sound.


## `raw` holds a loop plus some run-on past its end: the first samples are
## cross-faded (equal power, for noise) from that run-on, the loop's own
## continuation, into the fresh start, so the last sample leads straight
## into the first. Returns just the loop.
static func seamless_loop(raw: PackedFloat32Array, loop_count: int) -> PackedFloat32Array:
	var fade_count: int = raw.size() - loop_count
	var looped: PackedFloat32Array = raw.slice(0, loop_count)
	for i: int in range(fade_count):
		var k: float = float(i) / float(fade_count) * PI * 0.5
		looped[i] = raw[i] * sin(k) + raw[loop_count + i] * cos(k)
	return looped


## 16-bit samples scaled so the whole clip's RMS -- or with `loudest`, its
## loudest 100 ms (tests/test_world_audio_levels.gd measures the same way) --
## lands on `target_db`. The level in world_mix.gd then no longer depends on
## what the synthesis happened to come out at.
static func normalized(mix: PackedFloat32Array, rate: int, target_db: float, loudest: bool = false) -> PackedByteArray:
	var squares := PackedFloat32Array()
	squares.resize(mix.size())
	var total: float = 0.0
	for i: int in range(mix.size()):
		squares[i] = mix[i] * mix[i]
		total += squares[i]
	var power: float = total / maxf(mix.size(), 1)
	if loudest:
		var window: int = mini(int(rate * 0.1), mix.size())
		var running: float = 0.0
		for i: int in range(window):
			running += squares[i]
		var peak_window: float = running
		for i: int in range(window, mix.size()):
			running += squares[i] - squares[i - window]
			peak_window = maxf(peak_window, running)
		power = peak_window / maxf(window, 1)
	var gain: float = db_to_linear(target_db) / maxf(sqrt(power), 0.000001)
	var data := PackedByteArray()
	data.resize(mix.size() * 2)
	for i: int in range(mix.size()):
		data.encode_s16(i * 2, roundi(clampf(mix[i] * gain, -1.0, 1.0) * 32767.0))
	return data


static func loop(data: PackedByteArray, rate: int, sample_count: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


## A two-pole band-pass (RBJ, 0 dB at the peak) whose centre can move every
## sample: a formant for the bark, a wooden body for the creak.
class Resonator:
	var _x1: float = 0.0
	var _x2: float = 0.0
	var _y1: float = 0.0
	var _y2: float = 0.0

	func filter(x: float, centre: float, q: float, rate: int) -> float:
		var w0: float = TAU * centre / float(rate)
		var alpha: float = sin(w0) / (2.0 * q)
		var a0: float = 1.0 + alpha
		var y: float = (alpha * x - alpha * _x2 + 2.0 * cos(w0) * _y1 - (1.0 - alpha) * _y2) / a0
		_x2 = _x1
		_x1 = x
		_y2 = _y1
		_y1 = y
		return y
