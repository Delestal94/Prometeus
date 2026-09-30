class_name SynthAudioWorld
extends RefCounted
## The generators of the world's beds and fixtures: wind, rain, birds, crickets
## and the far-off road, the level-crossing bell, the depot's roller door and the
## forklift's reversing beep. Split out of synth_audio.gd by responsibility;
## SynthAudio hands them out (and caches them), so callers never use this class
## directly.


## World ambience (item #45): a soft looping wind, noise kept to a band
## between ~160 and ~800 Hz -- air moving, a "whoosh". It used to be white
## noise through one low-pass at ~50 Hz: all the energy in a sub-bass
## rumble that came and went, which on headphones read as wind buffeting a
## microphone, like interference (playtest 2026-09-25). Gusts brighten the
## band as they swell. Every gust completes whole cycles over the loop and
## the seam is cross-faded (SynthAudioDsp.seamless_loop), so nothing jumps each lap:
## the old drift ended half a cycle off, a bump every four seconds.
const WIND_STREAM_RMS_DB: float = -20.0


static func make_ambient_wind() -> AudioStreamWAV:
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
	return SynthAudioDsp.loop(
		SynthAudioDsp.normalized(SynthAudioDsp.seamless_loop(raw, loop_count), RATE, WIND_STREAM_RMS_DB),
		RATE, loop_count)


## Level crossing bell (rail_crossing_segment.gd): a bright ding twice a
## second, looping for as long as the barriers are moving or down.
static func make_crossing_bell() -> AudioStreamWAV:
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
static func make_roller_door() -> AudioStreamWAV:
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
	return SynthAudioDsp.loop(data, RATE, sample_count)


## Forklift reversing alarm: the classic beep, half a second on, half off.
static func make_reverse_beep() -> AudioStreamWAV:
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
	return SynthAudioDsp.loop(data, RATE, sample_count)


## Birdsong for the outdoor bed (docs/tareas-nacho.md #20): a few short
## phrases of quick whistled chirps -- each a sine sweeping down or up by a
## few hundred hertz -- scattered over 28 s with several seconds of quiet
## between phrases. Seeded: the same birds on every machine.
static func make_ambient_birds() -> AudioStreamWAV:
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
	return SynthAudioDsp.loop(SynthAudioDsp.normalized(mix, RATE, -20.0, true), RATE, sample_count)


## Night instead of birds: a few crickets in the grass, at different
## distances and pitches, each singing a short phrase of chirps and then
## keeping quiet for a few seconds -- most of the loop is silence. It was
## one cricket chirping twice a second without a break, the whole night,
## which grated (playtest 2026-09-25). Each pulse is a rounded tone with a
## slight downward slide, softer than the old hard-edged beeps.
const CRICKETS_STREAM_LOUDEST_DB: float = -20.0


static func make_night_crickets() -> AudioStreamWAV:
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
	return SynthAudioDsp.loop(SynthAudioDsp.normalized(mix, RATE, CRICKETS_STREAM_LOUDEST_DB, true), RATE, sample_count)


## Far-off road: tyres on asphalt somewhere out of sight, swelling twice a
## loop as a car goes by and brightening as it nears. A band of noise from
## ~130 to ~500 Hz: it used to be noise under ~70 Hz, a sub-bass rumble
## that only read as interference, and it faded to silence at the seam.
## The swell completes whole periods and the seam is cross-faded.
const DISTANT_ROAD_STREAM_RMS_DB: float = -20.0


static func make_distant_road() -> AudioStreamWAV:
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
	return SynthAudioDsp.loop(
		SynthAudioDsp.normalized(SynthAudioDsp.seamless_loop(raw, loop_count), RATE, DISTANT_ROAD_STREAM_RMS_DB),
		RATE, loop_count)


## Rain (docs/tareas-nacho.md #68): a dense hiss of drops, two seconds,
## looping. Played louder and through the Interior bus when heard from inside
## the truck, where it drums on the roof (route_sky.gd).
static func make_rain_loop() -> AudioStreamWAV:
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
