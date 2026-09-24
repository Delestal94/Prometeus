class_name SynthAudio
extends RefCounted
## Tiny procedural waveforms, generated at runtime instead of shipping .wav
## assets -- same "no art yet, code is the source of truth" convention as
## route.gd's boxes and package_feedback.gd's confetti cubes.

## Every sound is synthesized sample by sample in GDScript -- up to ~12 ms
## for the wind bed -- so each one is built once and shared: a stream is
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


static func _make_wood_creak() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.35
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var progress: float = t / DURATION
		var freq: float = lerpf(260.0, 90.0, progress) + randf_range(-12.0, 12.0)
		phase += freq / RATE
		var envelope: float = (1.0 - progress) * (0.6 + 0.4 * sin(progress * PI))
		var wave: float = (fmod(phase, 1.0) * 2.0 - 1.0) * 0.6  # cheap sawtooth
		var sample: float = clampf(wave * envelope, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


## Liquid's wet slosh: a short low filtered-noise wobble, used only when
## the puddle grows so it signals trouble without becoming a constant loop.
static func liquid_slosh() -> AudioStreamWAV:
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


## World ambience (item #45): soft looping wind, low-passed white noise
## instead of raw hiss -- a one-pole filter (y[n] = y[n-1]*a + x[n]*(1-a))
## smooths it into something that reads as air movement, not static. A
## slow amplitude drift on top keeps it from feeling like a dead-flat loop.
static func ambient_wind() -> AudioStreamWAV:
	return _cached(&"ambient_wind", _make_ambient_wind)


static func _make_ambient_wind() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 4.0
	const FILTER_A: float = 0.985
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var filtered: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		filtered = filtered * FILTER_A + randf_range(-1.0, 1.0) * (1.0 - FILTER_A)
		var drift: float = 0.7 + 0.3 * sin(TAU * 0.13 * t)
		var sample: float = clampf(filtered * 5.0 * drift, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream

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


## The depot's room tone: ventilation and fluorescent tubes, a soft 100 Hz
## hum under filtered air. Quiet on purpose -- it's what silence sounds like
## in a warehouse.
static func warehouse_hum() -> AudioStreamWAV:
	return _cached(&"warehouse_hum", _make_warehouse_hum)


static func _make_warehouse_hum() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 3.0
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var air: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		air = air * 0.97 + rng.randf_range(-1.0, 1.0) * 0.03
		var hum: float = sin(TAU * 100.0 * t) * 0.18 + sin(TAU * 200.0 * t) * 0.05
		var edge: float = minf(float(i), float(sample_count - i)) / (RATE * 0.05)
		data.encode_s16(i * 2, roundi(clampf((hum + air * 3.2) * minf(edge, 1.0), -1.0, 1.0) * 12000.0))
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


## A cheerful little tune from the depot's radio: a plucked melody over a
## walking bass, band-limited and crackly like a small AM speaker. Eight bars
## that loop, lo-fi rate on purpose (it's a radio, and it's cheaper to build).
static func radio_tune() -> AudioStreamWAV:
	return _cached(&"radio_tune", _make_radio_tune)


static func _make_radio_tune() -> AudioStreamWAV:
	const RATE: int = 11025
	const BEAT: float = 0.3
	# Semitones from A3; -99 is a rest. Two phrases of 16 eighth notes.
	var melody: Array[int] = [7, 11, 14, 11, 12, 11, 7, -99, 9, 12, 16, 12, 14, 12, 9, -99,
		7, 11, 14, 19, 17, 14, 12, 11, 9, 11, 12, 9, 7, -99, 7, -99]
	var bass: Array[int] = [-12, -5, -10, -5, -8, -3, -10, -5]
	var total_beats: int = melody.size()
	var sample_count: int = int(RATE * BEAT * total_beats)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var low: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var beat: int = int(t / BEAT)
		var in_beat: float = t - beat * BEAT
		var sample: float = 0.0
		var note: int = melody[beat % total_beats]
		if note != -99:
			var freq: float = 220.0 * pow(2.0, note / 12.0)
			var pluck: float = exp(-in_beat * 9.0)
			sample += (sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 2.0 * t) * 0.2) * pluck * 0.5
		var bass_note: int = bass[(beat / 4) % bass.size()]
		var bass_freq: float = 220.0 * pow(2.0, bass_note / 12.0)
		var bass_in: float = t - (beat / 2) * BEAT * 2.0
		sample += sin(TAU * bass_freq * t) * exp(-bass_in * 4.0) * 0.35
		# Brushed hi-hat on the off-beats.
		if beat % 2 == 1:
			sample += rng.randf_range(-1.0, 1.0) * exp(-in_beat * 40.0) * 0.12
		# Small-speaker colour: gentle low-pass plus a bed of crackle.
		low = lerpf(low, sample, 0.55)
		var crackle: float = rng.randf_range(-1.0, 1.0) * 0.015 + (0.25 if rng.randf() < 0.0004 else 0.0)
		var edge: float = minf(float(i), float(sample_count - i)) / (RATE * 0.02)
		data.encode_s16(i * 2, roundi(clampf((low + crackle) * minf(edge, 1.0), -1.0, 1.0) * 16000.0))
	return _loop(data, RATE, sample_count)


## Birdsong for the outdoor bed (docs/tareas-nacho.md #20): a few short
## phrases of quick whistled chirps -- each a sine sweeping down or up by a
## few hundred hertz -- scattered over 9 s of silence, so the loop never
## sounds like a pattern. Seeded: the same birds on every machine.
static func ambient_birds() -> AudioStreamWAV:
	return _cached(&"ambient_birds", _make_ambient_birds)


static func _make_ambient_birds() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 9.0
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for phrase: int in range(6):
		var start: float = 0.4 + float(phrase) * 1.4 + rng.randf_range(0.0, 0.8)
		var base: float = rng.randf_range(2600.0, 4200.0)
		var chirps: int = rng.randi_range(2, 5)
		var gap: float = rng.randf_range(0.09, 0.16)
		var level: float = rng.randf_range(0.35, 0.8)
		var sweep: float = rng.randf_range(-700.0, 500.0)
		for chirp: int in range(chirps):
			var begin: int = int((start + float(chirp) * gap) * RATE)
			var length: int = int(rng.randf_range(0.04, 0.07) * RATE)
			var phase: float = 0.0
			for n: int in range(length):
				var index: int = begin + n
				if index >= sample_count:
					break
				var k: float = float(n) / float(length)
				phase += TAU * (base + sweep * k) / RATE
				# Quick attack, rounded tail.
				var envelope: float = sin(PI * k) * (1.0 - 0.4 * k)
				mix[index] += sin(phase) * envelope * level
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i: int in range(sample_count):
		data.encode_s16(i * 2, roundi(clampf(mix[i], -1.0, 1.0) * 14000.0))
	return _loop(data, RATE, sample_count)


## Night instead of birds: crickets, bursts of three short 4.6 kHz pulses
## about twice a second, with a little drift so it doesn't tick like a clock.
static func night_crickets() -> AudioStreamWAV:
	return _cached(&"night_crickets", _make_night_crickets)


static func _make_night_crickets() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 6.0
	const PITCH: float = 4600.0
	const BURST: float = 0.075
	const PULSE_PERIOD: float = 0.025
	const PULSE_LENGTH: float = 0.018
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var at: float = 0.1
	while at < DURATION - 0.2:
		var begin: int = int(at * RATE)
		for n: int in range(int(BURST * RATE)):
			var local: float = float(n) / RATE
			var pulse: float = fmod(local, PULSE_PERIOD)
			if pulse < PULSE_LENGTH:
				mix[begin + n] += sin(TAU * PITCH * (at + local)) * sin(PI * pulse / PULSE_LENGTH)
		at += rng.randf_range(0.42, 0.6)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i: int in range(sample_count):
		data.encode_s16(i * 2, roundi(clampf(mix[i], -1.0, 1.0) * 9000.0))
	return _loop(data, RATE, sample_count)


## Far-off road: a low, dull rumble that swells twice a loop as if a car went
## by somewhere out of sight. Heavily low-passed noise; the swell completes
## whole periods and the ends fade, so the loop point is seamless.
static func distant_road() -> AudioStreamWAV:
	return _cached(&"distant_road", _make_distant_road)


static func _make_distant_road() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 12.0
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var low: float = 0.0
	var lower: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.02)
		lower = lerpf(lower, low, 0.05)
		var swell: float = pow(0.5 - 0.5 * cos(TAU * 2.0 * t / DURATION), 3.0)
		var level: float = 0.35 + 0.65 * swell
		var edge: float = minf(float(i), float(sample_count - i)) / (RATE * 0.05)
		data.encode_s16(i * 2, roundi(clampf(lower * 9.0 * level * minf(edge, 1.0), -1.0, 1.0) * 20000.0))
	return _loop(data, RATE, sample_count)


static func _loop(data: PackedByteArray, rate: int, sample_count: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


## A dog's bark (the chasing dog, tareas de Nacho N-106/N-405): a quick
## pitch drop from ~620 to ~380 Hz through a rough, buzzy wave, a burst of
## breath noise at the start, 0.22 s. One-shot; ChasingDog repeats it.
static func dog_bark() -> AudioStreamWAV:
	return _cached(&"dog_bark", _make_dog_bark)


static func _make_dog_bark() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.22
	var sample_count: int = int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	var noise_state: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var k: float = t / DURATION
		var freq: float = lerpf(620.0, 380.0, sqrt(k))
		phase += TAU * freq / RATE
		# Clipped sine plus its second harmonic: a bark, not a whistle.
		var wave: float = clampf(sin(phase) * 1.8, -1.0, 1.0) * 0.6 + sin(phase * 2.0) * 0.25
		noise_state = lerpf(noise_state, randf_range(-1.0, 1.0), 0.5)
		var breath: float = noise_state * 0.5 * maxf(0.0, 1.0 - k * 4.0)
		var envelope: float = minf(k * 25.0, 1.0) * pow(1.0 - k, 1.5)
		data.encode_s16(i * 2, int(clampf((wave + breath) * envelope, -1.0, 1.0) * 32767.0 * 0.8))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


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
