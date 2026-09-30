class_name SynthAudioHandling
extends RefCounted
## The generators of handling the cargo and the phone: the camera shutter, the
## tape torn off a box, the cardboard flap, and the tension bed under the music.
## Split out of synth_audio.gd by responsibility; SynthAudio hands them out (and
## caches them), so callers never use this class directly.


## Two hard clicks a few milliseconds apart -- a shutter opening and closing.
## Short and dry on purpose: it has to read as a phone taking a picture over
## whatever ambience is playing, without becoming another sustained sound.
static func make_camera_shutter() -> AudioStreamWAV:
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
static func make_tape_rip() -> AudioStreamWAV:
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
static func make_cardboard_flap() -> AudioStreamWAV:
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
static func make_tension_pulse() -> AudioStreamWAV:
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
