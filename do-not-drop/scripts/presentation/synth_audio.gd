class_name SynthAudio
extends RefCounted
## Tiny procedural waveforms, generated at runtime instead of shipping .wav
## assets -- same "no art yet, code is the source of truth" convention as
## route.gd's boxes and package_feedback.gd's confetti cubes.

## Every sound is synthesized sample by sample in GDScript -- ~50 ms for
## the wind bed -- so each one is built once and shared: a stream is
## read-only data, and every AudioStreamPlayer keeps its own playback of it.
## Without this, opening a box or ringing a door re-synthesized its sound on
## the very frame it had to play.
static var _cache: Dictionary = {}


static func _cached(key: StringName, build: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]


## Quiet harmonic exhaust loop. Integer periods keep the seam continuous;
## pitch and volume are adjusted by VehiclePresentation, not by simulation.
static func engine_loop() -> AudioStreamWAV:
	return _cached(&"engine_loop", _make_engine_loop)


static func _make_engine_loop() -> AudioStreamWAV:
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


## The engine's other two layers (tareas de Nacho N-401). VehiclePresentation
## crossfades idle / engine_loop() / high by a simulated rev counter, so the
## three are built to the same loudness (ENGINE_LAYER_RMS, engine_loop()'s own)
## and a crossfade never swells or dips. Integer frequencies over a one-second
## buffer: every partial ends where it started, so the loop has no seam.
const ENGINE_LAYER_RMS: float = 0.2286


## Ticking over: a low, lumpy rumble -- the firing rhythm (8 Hz) nods the
## level of a 32 Hz base with a strong second harmonic.
static func engine_idle_loop() -> AudioStreamWAV:
	return _cached(&"engine_idle_loop", _make_engine_idle_loop)


static func _make_engine_idle_loop() -> AudioStreamWAV:
	return _engine_layer(func(t: float) -> float:
		var phase: float = TAU * 32.0 * t
		var lope: float = 0.72 + 0.28 * sin(TAU * 8.0 * t) * sin(TAU * 8.0 * t)
		return (sin(phase) * 0.5 + sin(phase * 2.0) * 0.34 + sin(phase * 3.0) * 0.12 + sin(phase * 0.5) * 0.18) * lope)


## Revving hard: the same engine higher up, its upper harmonics louder (the
## strain you hear in the cab just before a gear change).
static func engine_high_loop() -> AudioStreamWAV:
	return _cached(&"engine_high_loop", _make_engine_high_loop)


static func _make_engine_high_loop() -> AudioStreamWAV:
	return _engine_layer(func(t: float) -> float:
		var phase: float = TAU * 64.0 * t
		return sin(phase) * 0.36 + sin(phase * 2.0) * 0.28 + sin(phase * 3.0) * 0.2 + sin(phase * 4.0) * 0.14 + sin(phase * 6.0) * 0.08)


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
static func impact_thud() -> AudioStreamWAV:
	return _cached(&"impact_thud", _make_impact_thud)


static func _make_impact_thud() -> AudioStreamWAV:
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
	return _cached(&"tire_screech", _make_tire_screech)


static func _make_tire_screech() -> AudioStreamWAV:
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
	return _cached(&"glass_chime", _make_glass_chime)


static func _make_glass_chime() -> AudioStreamWAV:
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
	return _cached(&"creature_groan", _make_creature_groan)


static func _make_creature_groan() -> AudioStreamWAV:
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
	return _cached(&"wood_creak", _make_wood_creak)


## Stick-slip, the way wood actually creaks: the surfaces catch and let go
## in a run of tiny ticks, whose rate wanders slowly (here ~45-140 a
## second), and each tick rings the box's wooden body (three resonances).
## It used to be a raw sawtooth whose pitch was re-rolled every sample: a
## buzzing static that, repeating under load, sounded like interference
## (playtest 2026-09-25). Its loudest 100 ms land where the old one's did.
const WOOD_CREAK_STREAM_LOUDEST_DB: float = -12.0


static func _make_wood_creak() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.4
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var body := [_Resonator.new(), _Resonator.new(), _Resonator.new()]
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
	stream.data = _normalized(mix, RATE, WOOD_CREAK_STREAM_LOUDEST_DB, true)
	return stream


## Liquid's wet slosh: a short low filtered-noise wobble, used only when
## the puddle grows so it signals trouble without becoming a constant loop.
static func liquid_slosh() -> AudioStreamWAV:
	return _cached(&"liquid_slosh", _make_liquid_slosh)


static func _make_liquid_slosh() -> AudioStreamWAV:
	const RATE: int = 22050
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


static func explosive_tick() -> AudioStreamWAV:
	return _cached(&"explosive_tick", _make_explosive_tick)


static func _make_explosive_tick() -> AudioStreamWAV:
	const RATE: int = 22050
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


static func hostile_hiss() -> AudioStreamWAV:
	return _cached(&"hostile_hiss", _make_hostile_hiss)


static func _make_hostile_hiss() -> AudioStreamWAV:
	const RATE: int = 22050
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


## A classic two-tone car horn: two square waves close enough in pitch to
## beat against each other, with a short fade in/out so it doesn't click.
static func honk_horn() -> AudioStreamWAV:
	return _cached(&"honk_horn", _make_honk_horn)


static func _make_honk_horn() -> AudioStreamWAV:
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


## World ambience (item #45): a soft looping wind, noise kept to a band
## between ~160 and ~800 Hz -- air moving, a "whoosh". It used to be white
## noise through one low-pass at ~50 Hz: all the energy in a sub-bass
## rumble that came and went, which on headphones read as wind buffeting a
## microphone, like interference (playtest 2026-09-25). Gusts brighten the
## band as they swell. Every gust completes whole cycles over the loop and
## the seam is cross-faded (_seamless_loop), so nothing jumps each lap:
## the old drift ended half a cycle off, a bump every four seconds.
static func ambient_wind() -> AudioStreamWAV:
	return _cached(&"ambient_wind", _make_ambient_wind)


const WIND_STREAM_RMS_DB: float = -20.0


static func _make_ambient_wind() -> AudioStreamWAV:
	# Nothing in it above ~1 kHz: half the usual rate, half the work.
	const RATE: int = 11025
	const DURATION: float = 10.0
	const FADE: float = 1.5
	var loop_count: int = int(RATE * DURATION)
	var raw := PackedFloat32Array()
	raw.resize(loop_count + int(RATE * FADE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var band: float = 0.0
	var band_2: float = 0.0
	var rumble: float = 0.0
	for i: int in range(raw.size()):
		var t: float = float(i) / RATE
		var gust: float = (0.55 + 0.25 * sin(TAU * t / DURATION)
			+ 0.14 * sin(TAU * 3.0 * t / DURATION + 1.3) + 0.06 * sin(TAU * 7.0 * t / DURATION + 0.4))
		# Two one-pole low-passes, their corner riding the gust (~370-870 Hz)...
		var opening: float = lerpf(0.19, 0.39, gust)
		band = lerpf(band, rng.randf_range(-1.0, 1.0), opening)
		band_2 = lerpf(band_2, band, opening)
		# ...minus everything under ~160 Hz: no rumble.
		rumble = lerpf(rumble, band_2, 0.088)
		raw[i] = (band_2 - rumble) * gust
	return _loop(_normalized(_seamless_loop(raw, loop_count), RATE, WIND_STREAM_RMS_DB), RATE, loop_count)

## Two hard clicks a few milliseconds apart -- a shutter opening and closing.
## Short and dry on purpose: it has to read as a phone taking a picture over
## whatever ambience is playing, without becoming another sustained sound.
static func camera_shutter() -> AudioStreamWAV:
	return _cached(&"camera_shutter", _make_camera_shutter)


static func _make_camera_shutter() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.16
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var second_click: float = 0.075
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var first: float = exp(-t * 220.0)
		var second: float = exp(-maxf(t - second_click, 0.0) * 180.0) if t >= second_click else 0.0
		var envelope: float = maxf(first, second * 0.7)
		var wave: float = (randf() * 2.0 - 1.0) * 0.6 + sin(TAU * 2600.0 * t) * 0.4
		data.encode_s16(i * 2, roundi(clampf(wave * envelope, -1.0, 1.0) * 17000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


## Packing tape torn off a box: a run of short, rough noise bursts that
## speeds up as the tape lets go -- the first time a box is opened.
static func tape_rip() -> AudioStreamWAV:
	return _cached(&"tape_rip", _make_tape_rip)


static func _make_tape_rip() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.42
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var smooth: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		# Burst rate climbs from ~25 Hz to ~70 Hz: tape peeling faster.
		var phase: float = t * (25.0 + t * 110.0)
		var burst: float = pow(maxf(0.0, sin(phase * TAU)), 6.0)
		var envelope: float = minf(t * 40.0, 1.0) * (1.0 - t / DURATION)
		smooth = lerpf(smooth, randf_range(-1.0, 1.0), 0.45)
		var sample: float = smooth * (0.25 + burst) * envelope
		data.encode_s16(i * 2, roundi(clampf(sample, -1.0, 1.0) * 20000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


## A cardboard flap folding over: a soft, papery thump.
static func cardboard_flap() -> AudioStreamWAV:
	return _cached(&"cardboard_flap", _make_cardboard_flap)


static func _make_cardboard_flap() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.2
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var smooth: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var envelope: float = exp(-t * 26.0)
		smooth = lerpf(smooth, randf_range(-1.0, 1.0), 0.3)
		var thump: float = sin(TAU * 110.0 * t) * exp(-t * 40.0) * 0.6
		var sample: float = (smooth * 0.55 + thump) * envelope
		data.encode_s16(i * 2, roundi(clampf(sample, -1.0, 1.0) * 18000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


## Tension bed under the music (tareas de Nacho #22): a low drone with a
## double heartbeat thump, two seconds, looping seamlessly. Its volume is
## driven by how much trouble the cargo is in (see ingame_music.gd).
static func tension_pulse() -> AudioStreamWAV:
	return _cached(&"tension_pulse", _make_tension_pulse)


static func _make_tension_pulse() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 2.0
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		# Whole periods in 2 s (55 Hz, 82.5 Hz) keep the loop seam silent.
		var drone: float = sin(TAU * 55.0 * t) * 0.28 + sin(TAU * 82.5 * t) * 0.12
		var beat: float = 0.0
		for onset: float in [0.0, 0.28, 1.0, 1.28]:
			var since: float = t - onset
			if since >= 0.0 and since < 0.25:
				beat += sin(TAU * 48.0 * since) * exp(-since * 22.0) * (1.0 if int(onset) == int(onset + 0.5) else 0.7)
		var sample: float = clampf(drone * (0.75 + 0.25 * sin(TAU * 0.5 * t)) + beat * 0.8, -1.0, 1.0)
		data.encode_s16(i * 2, roundi(sample * 20000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


## Rain (docs/tareas-nacho.md #68): a dense hiss of drops, two seconds,
## looping. Played louder and through the Interior bus when heard from inside
## the truck, where it drums on the roof (route_sky.gd).
static func rain_loop() -> AudioStreamWAV:
	return _cached(&"rain_loop", _make_rain_loop)


static func _make_rain_loop() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 2.0
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hiss: float = 0.0
	var drop: float = 0.0
	for i: int in range(sample_count):
		hiss = lerpf(hiss, rng.randf_range(-1.0, 1.0), 0.45)
		# Individual drops: a sparse scatter of tiny clicks over the hiss.
		if rng.randf() < 0.004:
			drop = rng.randf_range(0.4, 0.9)
		drop *= 0.93
		var sample: float = hiss * 0.32 + drop * rng.randf_range(-1.0, 1.0)
		# Fade the first and last 20 ms into each other so the loop never clicks.
		var edge: float = minf(float(i), float(sample_count - i)) / (RATE * 0.02)
		data.encode_s16(i * 2, roundi(clampf(sample * minf(edge, 1.0), -1.0, 1.0) * 17000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


## Level crossing bell (rail_crossing_segment.gd): a bright ding twice a
## second, looping for as long as the barriers are moving or down.
static func crossing_bell() -> AudioStreamWAV:
	return _cached(&"crossing_bell", _make_crossing_bell)


static func _make_crossing_bell() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.5
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var envelope: float = exp(-t * 9.0)
		var ding: float = sin(TAU * 1320.0 * t) * 0.5 + sin(TAU * 1980.0 * t) * 0.25 + sin(TAU * 2640.0 * t) * 0.12
		data.encode_s16(i * 2, roundi(clampf(ding * envelope, -1.0, 1.0) * 16000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


## Depot roller door (depot_roller_door.gd): a geared motor drone with the
## slats rattling over it. Loops for as long as the door moves.
static func roller_door() -> AudioStreamWAV:
	return _cached(&"roller_door", _make_roller_door)


static func _make_roller_door() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 1.0
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var rattle: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		# Whole cycles of 60/120/180 Hz in one second: the seam never clicks.
		var drone: float = sin(TAU * 60.0 * t) * 0.35 + sin(TAU * 120.0 * t) * 0.22 + sin(TAU * 180.0 * t) * 0.08
		# A slat clacks over the drum eight times a second.
		if i % (RATE / 8) == 0:
			rattle = 0.8
		rattle *= 0.9985
		var clack: float = rattle * rng.randf_range(-1.0, 1.0) * 0.4
		data.encode_s16(i * 2, roundi(clampf(drone + clack, -1.0, 1.0) * 15000.0))
	return _loop(data, RATE, sample_count)


## Forklift reversing alarm: the classic beep, half a second on, half off.
static func reverse_beep() -> AudioStreamWAV:
	return _cached(&"reverse_beep", _make_reverse_beep)


static func _make_reverse_beep() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 1.0
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var on: float = 1.0 if t < 0.45 else 0.0
		var ramp: float = minf(minf(t, absf(0.45 - t)) / 0.01, 1.0) if t < 0.45 else 0.0
		var tone: float = sin(TAU * 1100.0 * t) * 0.8 + sin(TAU * 2200.0 * t) * 0.1
		data.encode_s16(i * 2, roundi(tone * on * ramp * 14000.0))
	return _loop(data, RATE, sample_count)


## Birdsong for the outdoor bed (docs/tareas-nacho.md #20): a few short
## phrases of quick whistled chirps -- each a sine sweeping down or up by a
## few hundred hertz -- scattered over 28 s with several seconds of quiet
## between phrases. Seeded: the same birds on every machine.
static func ambient_birds() -> AudioStreamWAV:
	return _cached(&"ambient_birds", _make_ambient_birds)


static func _make_ambient_birds() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 28.0
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for phrase: int in range(5):
		var start: float = 1.2 + float(phrase) * 5.2 + rng.randf_range(0.0, 1.6)
		var base: float = rng.randf_range(2000.0, 3300.0)
		var chirps: int = rng.randi_range(2, 4)
		var gap: float = rng.randf_range(0.16, 0.24)
		var level: float = rng.randf_range(0.35, 0.8)
		var sweep: float = rng.randf_range(-400.0, 300.0)
		for chirp: int in range(chirps):
			var begin: int = int((start + float(chirp) * gap) * RATE)
			var length: int = int(rng.randf_range(0.06, 0.11) * RATE)
			var phase: float = 0.0
			for n: int in range(length):
				var index: int = begin + n
				if index >= sample_count:
					break
				var k: float = float(n) / float(length)
				phase += TAU * (base + sweep * k) / RATE
				# Rounded attack and tail, with no abrupt whistle onset.
				var envelope: float = pow(sin(PI * k), 2.0) * (1.0 - 0.4 * k)
				mix[index] += sin(phase) * envelope * level
	return _loop(_normalized(mix, RATE, -20.0, true), RATE, sample_count)


## Night instead of birds: a few crickets in the grass, at different
## distances and pitches, each singing a short phrase of chirps and then
## keeping quiet for a few seconds -- most of the loop is silence. It was
## one cricket chirping twice a second without a break, the whole night,
## which grated (playtest 2026-09-25). Each pulse is a rounded tone with a
## slight downward slide, softer than the old hard-edged beeps.
static func night_crickets() -> AudioStreamWAV:
	return _cached(&"night_crickets", _make_night_crickets)


const CRICKETS_STREAM_LOUDEST_DB: float = -20.0


static func _make_night_crickets() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 20.0
	const PULSES: int = 3
	const PULSE_PERIOD: float = 0.03
	const PULSE_LENGTH: float = 0.02
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	# [pitch Hz, level, first phrase at s]: the near one, and two farther off.
	for cricket: Array in [[4300.0, 1.0, 0.6], [4750.0, 0.5, 5.2], [3950.0, 0.32, 11.5]]:
		var at: float = cricket[2]
		while at < DURATION - 1.2:
			var chirps: int = rng.randi_range(3, 7)
			for chirp: int in range(chirps):
				var chirp_at: float = at + float(chirp) * rng.randf_range(0.5, 0.62)
				var level: float = float(cricket[1]) * rng.randf_range(0.75, 1.0)
				for pulse: int in range(PULSES):
					var begin: int = int((chirp_at + float(pulse) * PULSE_PERIOD) * RATE)
					var length: int = int(PULSE_LENGTH * RATE)
					for n: int in range(length):
						if begin + n >= sample_count:
							break
						var k: float = float(n) / float(length)
						var pitch: float = float(cricket[0]) * (1.0 - 0.02 * k)
						mix[begin + n] += sin(TAU * pitch * float(n) / RATE) * pow(sin(PI * k), 2.0) * level
			# Then quiet: the next phrase a few seconds later.
			at += float(chirps) * 0.56 + rng.randf_range(3.0, 7.0)
	return _loop(_normalized(mix, RATE, CRICKETS_STREAM_LOUDEST_DB, true), RATE, sample_count)


## Far-off road: tyres on asphalt somewhere out of sight, swelling twice a
## loop as a car goes by and brightening as it nears. A band of noise from
## ~130 to ~500 Hz: it used to be noise under ~70 Hz, a sub-bass rumble
## that only read as interference, and it faded to silence at the seam.
## The swell completes whole periods and the seam is cross-faded.
static func distant_road() -> AudioStreamWAV:
	return _cached(&"distant_road", _make_distant_road)


const DISTANT_ROAD_STREAM_RMS_DB: float = -20.0


static func _make_distant_road() -> AudioStreamWAV:
	const RATE: int = 11025
	const DURATION: float = 12.0
	const FADE: float = 1.0
	var loop_count: int = int(RATE * DURATION)
	var raw := PackedFloat32Array()
	raw.resize(loop_count + int(RATE * FADE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var band: float = 0.0
	var band_2: float = 0.0
	var rumble: float = 0.0
	for i: int in range(raw.size()):
		var t: float = float(i) / RATE
		var swell: float = pow(0.5 - 0.5 * cos(TAU * 2.0 * t / DURATION), 3.0)
		var opening: float = lerpf(0.116, 0.243, swell)
		band = lerpf(band, rng.randf_range(-1.0, 1.0), opening)
		band_2 = lerpf(band_2, band, opening)
		rumble = lerpf(rumble, band_2, 0.073)
		raw[i] = (band_2 - rumble) * (0.3 + 0.7 * swell)
	return _loop(_normalized(_seamless_loop(raw, loop_count), RATE, DISTANT_ROAD_STREAM_RMS_DB), RATE, loop_count)


## `raw` holds a loop plus some run-on past its end: the first samples are
## cross-faded (equal power, for noise) from that run-on, the loop's own
## continuation, into the fresh start, so the last sample leads straight
## into the first. Returns just the loop.
static func _seamless_loop(raw: PackedFloat32Array, loop_count: int) -> PackedFloat32Array:
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
static func _normalized(mix: PackedFloat32Array, rate: int, target_db: float, loudest: bool = false) -> PackedByteArray:
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


static func _loop(data: PackedByteArray, rate: int, sample_count: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


## A dog's bark (the chasing dog, tareas de Nacho N-106/N-405): "guau", a
## voice through a mouth. The voice is a buzz of harmonics whose pitch
## jumps up as the bark opens and falls away, with a little breath on it;
## the mouth is two resonances (formants) that open from "u" to "a" and
## close again. The first version was a clipped sine sliding down, with
## no mouth at all -- it read as a synth, not a dog (playtest 2026-09-25).
## 0.24 s. One-shot; ChasingDog repeats it, doubled up now and then.
static func dog_bark() -> AudioStreamWAV:
	return _cached(&"dog_bark", _make_dog_bark)


const DOG_BARK_STREAM_LOUDEST_DB: float = -12.0


static func _make_dog_bark() -> AudioStreamWAV:
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
	var mouth_low := _Resonator.new()
	var mouth_high := _Resonator.new()
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var k: float = t / DURATION
		# Pitch: up fast as it opens (~0.03 s), then down; a slight roughness.
		wobble = lerpf(wobble, rng.randf_range(-1.0, 1.0), 0.02)
		var pitch: float = (lerpf(360.0, 560.0, minf(t / 0.03, 1.0)) - 240.0 * maxf(k - 0.12, 0.0)) * (1.0 + 0.03 * wobble)
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
	stream.data = _normalized(mix, RATE, DOG_BARK_STREAM_LOUDEST_DB, true)
	return stream


## A two-pole band-pass (RBJ, 0 dB at the peak) whose centre can move every
## sample: a formant for the bark, a wooden body for the creak.
class _Resonator:
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


## A sheep's bleat (the flock, tareas de Nacho N-106/N-405): a nasal
## "meeh" around 330 Hz with a fast vibrato that gives it the wobble,
## 0.6 s. One-shot.
static func sheep_bleat() -> AudioStreamWAV:
	return _cached(&"sheep_bleat", _make_sheep_bleat)


static func _make_sheep_bleat() -> AudioStreamWAV:
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


## A parcel scanner's "bip" for menu buttons (main menu redesign,
## 2026-09-25): one short square-ish beep at 2.4 kHz, 70 ms, soft edges so
## it never clicks. Short on purpose -- it plays on every press.
static func scanner_beep() -> AudioStreamWAV:
	return _cached(&"scanner_beep", _make_scanner_beep)


static func _make_scanner_beep() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.07
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		# Fundamental plus a little third harmonic: a scanner's buzzy edge
		# without a raw square wave's harshness.
		var wave: float = sin(TAU * 2400.0 * t) * 0.8 + sin(TAU * 7200.0 * t) * 0.15
		var envelope: float = minf(t / 0.004, 1.0) * minf((DURATION - t) / 0.012, 1.0)
		data.encode_s16(i * 2, roundi(clampf(wave * envelope, -1.0, 1.0) * 12000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
