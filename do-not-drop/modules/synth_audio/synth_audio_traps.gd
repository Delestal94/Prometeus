class_name SynthAudioTraps
extends RefCounted
## The traps' sounds. The cues of each trap's state (Frágil's chime, Ruidoso's
## groan, Peso Creciente's creak, Liquid's slosh, the explosive's tick, the hostile's
## hiss) are built here by make_*, and SynthAudio hands them out and caches them.
## The later cushion landing has its own cache and accessor: callers preload this
## script for it.

const RATE: int = 22050
static var _cache: Dictionary = {}


## Fragile's "Amortiguá" landing (N-117): a short, soft thump that drops in
## pitch, the bump taken in a cushion instead of a chime of glass. Simple
## enough to leave as is; disenador-audio can retune it.
static func cushion_pad() -> AudioStreamWAV:
	if not _cache.has(&"cushion_pad"):
		_cache[&"cushion_pad"] = _make_cushion_pad()
	return _cache[&"cushion_pad"]


static func _make_cushion_pad() -> AudioStreamWAV:
	const DURATION: float = 0.16
	var data := PackedByteArray()
	var count: int = int(RATE * DURATION)
	data.resize(count * 2)
	for i: int in count:
		var t: float = float(i) / RATE
		var sample: float = sin(TAU * (170.0 - t * 300.0) * t) * exp(-t * 30.0)
		data.encode_s16(i * 2, roundi(sample * 20000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


## Frágil's cue: a short, bright, fast-decaying chime -- three inharmonic
## partials, the classic cheap "bell" trick. Pitched down a fourth for
## RUINED vs. AT_RISK by whoever plays it (see package_feedback.gd), so
## the same clip reads as two different severities.
static func make_glass_chime() -> AudioStreamWAV:
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
static func make_creature_groan() -> AudioStreamWAV:
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
## Stick-slip, the way wood actually creaks: the surfaces catch and let go
## in a run of tiny ticks, whose rate wanders slowly (here ~45-140 a
## second), and each tick rings the box's wooden body (three resonances).
## It used to be a raw sawtooth whose pitch was re-rolled every sample: a
## buzzing static that, repeating under load, sounded like interference
## (playtest 2026-09-25). Its loudest 100 ms land where the old one's did.
const WOOD_CREAK_STREAM_LOUDEST_DB: float = -12.0


static func make_wood_creak() -> AudioStreamWAV:
	const DURATION: float = 0.4
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var body := [SynthAudioDsp.Resonator.new(), SynthAudioDsp.Resonator.new(), SynthAudioDsp.Resonator.new()]
	var drift: float = 0.0
	var until_slip: float = 0.0
	for i: int in range(sample_count):
		var k: float = float(i) / float(sample_count)
		drift = lerpf(drift, rng.randf_range(-1.0, 1.0), 0.002)
		var excitation: float = 0.0
		until_slip -= 1.0
		if until_slip <= 0.0:
			var rate: float = lerpf(140.0, 45.0, k) * (1.0 + 0.35 * drift)
			until_slip = RATE / rate * rng.randf_range(0.85, 1.15)
			excitation = rng.randf_range(0.6, 1.0)
		var sound: float = (body[0].filter(excitation, 430.0, 9.0, RATE)
			+ body[1].filter(excitation, 1150.0, 11.0, RATE) * 0.7
			+ body[2].filter(excitation, 2350.0, 14.0, RATE) * 0.35)
		mix[i] = sound * sin(PI * pow(k, 0.7))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, WOOD_CREAK_STREAM_LOUDEST_DB, true)
	return stream


## Liquid's wet slosh: a short low filtered-noise wobble, used only when
## the puddle grows so it signals trouble without becoming a constant loop.
static func make_liquid_slosh() -> AudioStreamWAV:
	const DURATION: float = 0.28
	var data := PackedByteArray()
	var count: int = int(RATE * DURATION)
	data.resize(count * 2)
	var smooth: float = 0.0
	for i: int in count:
		var t: float = float(i) / RATE
		smooth = lerpf(smooth, randf_range(-1.0, 1.0), 0.12)
		var envelope: float = sin(clampf(t / DURATION, 0.0, 1.0) * PI)
		var wave: float = smooth * 0.75 + sin(TAU * (92.0 + t * 60.0) * t) * 0.25
		data.encode_s16(i * 2, roundi(clampf(wave * envelope, -1.0, 1.0) * 17000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


static func make_explosive_tick() -> AudioStreamWAV:
	const DURATION: float = 0.07
	var data := PackedByteArray()
	var count: int = int(RATE * DURATION)
	data.resize(count * 2)
	for i: int in count:
		var t: float = float(i) / RATE
		var envelope: float = exp(-t * 55.0)
		var sample: float = sin(TAU * 980.0 * t) * envelope
		data.encode_s16(i * 2, roundi(sample * 22000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


static func make_hostile_hiss() -> AudioStreamWAV:
	const DURATION: float = 0.32
	var data := PackedByteArray()
	var count: int = int(RATE * DURATION)
	data.resize(count * 2)
	var noise: float = 0.0
	for i: int in count:
		var t: float = float(i) / RATE
		noise = lerpf(noise, randf_range(-1.0, 1.0), 0.35)
		var envelope: float = sin(t / DURATION * PI)
		var tone: float = sin(TAU * (480.0 + t * 900.0) * t) * 0.22
		data.encode_s16(i * 2, roundi(clampf((noise * 0.7 + tone) * envelope, -1.0, 1.0) * 18000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
