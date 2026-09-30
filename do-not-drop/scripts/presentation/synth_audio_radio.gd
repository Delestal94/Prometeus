extends RefCounted
## The generators behind the truck radio (tareas de Nacho N-406): a calm
## lo-fi pad, a loud driving beat, the newscast's jingle and the knob's click.
## Its own cache and accessors instead of going through SynthAudio (whose file
## is at the linter's line limit): calm_loop(), loud_loop(), news_jingle() and
## knob_click() build each sound once and share it, warm() builds them all on a
## worker thread. Callers preload this script.
##
## Everything is rendered at 11.025 kHz: it is a cab speaker, and a full-band
## loop this long would cost a visible hitch the first time the crew turns the
## knob. Loops are levelled to the music class (-24 dBFS RMS, world_mix.gd).

const RATE: int = 11025
const LOOP_RMS_DB: float = -24.0
## Beat of the loud program: 140 bpm.
const LOUD_BEAT: float = 60.0 / 140.0
## Seconds each chord of the calm program lasts.
const CALM_CHORD_SECONDS: float = 1.8
## Am7, Fmaj7, Cmaj7, G6 as MIDI notes (lowest is the bass).
const CALM_CHORDS: Array = [[45, 57, 60, 64, 67], [41, 57, 60, 64, 65], [48, 55, 60, 64, 67], [43, 55, 59, 62, 64]]
## Pluck notes over each chord (A minor pentatonic-ish), as [beat offset, MIDI].
const CALM_PLUCKS: Array = [[0.5, 76], [1.0, 72], [1.5, 79]]
## Root of each bar of the loud program (A, A, F, G) and the lead's notes.
const LOUD_ROOTS: Array = [33, 33, 29, 31]
const LOUD_LEAD: Array = [0, 3, 7, 10, 7, 3, 12, 10]


## Sound name -> its stream, filled on first use or by warm().
static var _cache: Dictionary = {}
static var _warming: bool = false
const SOUNDS: Array[StringName] = [&"calm_loop", &"loud_loop", &"news_jingle", &"knob_click"]


static func calm_loop() -> AudioStreamWAV:
	return _cached(&"calm_loop")


static func loud_loop() -> AudioStreamWAV:
	return _cached(&"loud_loop")


static func news_jingle() -> AudioStreamWAV:
	return _cached(&"news_jingle")


static func knob_click() -> AudioStreamWAV:
	return _cached(&"knob_click")


## Builds the four sounds on a worker thread (the calm loop alone takes ~85 ms
## of GDScript synthesis), so the first turn of the knob doesn't hitch the
## cab. Written into the cache on the main thread, like UiSounds does.
static func warm() -> void:
	if _warming or _cache.size() == SOUNDS.size():
		return
	_warming = true
	WorkerThreadPool.add_task(_warm_task)


static func _warm_task() -> void:
	for id: StringName in SOUNDS:
		_store.call_deferred(id, _build(id))


static func _store(id: StringName, stream: AudioStreamWAV) -> void:
	if not _cache.has(id):
		_cache[id] = stream
	if id == SOUNDS[-1]:
		_warming = false


static func _cached(id: StringName) -> AudioStreamWAV:
	if not _cache.has(id):
		_cache[id] = _build(id)
	return _cache[id]


static func _build(id: StringName) -> AudioStreamWAV:
	match id:
		&"calm_loop":
			return make_calm_loop()
		&"loud_loop":
			return make_loud_loop()
		&"news_jingle":
			return make_news_jingle()
	return make_knob_click()


static func hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## A slow pad: four soft seventh chords with a few plucked notes over them.
## 7.2 s, seamless (every chord fades in and out to silence).
static func make_calm_loop() -> AudioStreamWAV:
	var duration: float = CALM_CHORD_SECONDS * CALM_CHORDS.size()
	var count: int = int(RATE * duration)
	var mix := PackedFloat32Array()
	mix.resize(count)
	for chord_index: int in CALM_CHORDS.size():
		var begin: int = int(chord_index * CALM_CHORD_SECONDS * RATE)
		var end: int = mini(int((chord_index + 1) * CALM_CHORD_SECONDS * RATE), count)
		var notes: Array = CALM_CHORDS[chord_index]
		var freqs := PackedFloat64Array()
		for note: int in notes:
			freqs.append(hz(note))
		for i: int in range(begin, end):
			var t: float = float(i - begin) / RATE
			var envelope: float = minf(t / 0.35, 1.0) * minf((CALM_CHORD_SECONDS - t) / 0.4, 1.0)
			var wave: float = 0.0
			for f: float in freqs:
				wave += sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.0 * t)
			mix[i] += wave * 0.12 * envelope
		for pluck: Array in CALM_PLUCKS:
			var start: int = begin + int(float(pluck[0]) * CALM_CHORD_SECONDS * 0.5 * RATE)
			var f: float = hz(int(pluck[1]))
			for i: int in range(start, mini(start + int(0.7 * RATE), end)):
				var t: float = float(i - start) / RATE
				var pluck_wave: float = sin(TAU * f * t) + 0.2 * sin(TAU * f * 3.0 * t)
				mix[i] += pluck_wave * exp(-t * 6.0) * minf(t / 0.005, 1.0) * 0.28
	return _loop(mix, count)


## A driving beat: kick on every beat, offbeat hats, a square bass on eighth
## notes and a bright square lead on top, all pushed into soft clipping.
## Four bars at 140 bpm, ~6.9 s, seamless.
static func make_loud_loop() -> AudioStreamWAV:
	var beats: int = LOUD_ROOTS.size() * 4
	var count: int = int(RATE * LOUD_BEAT * beats)
	var mix := PackedFloat32Array()
	mix.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 406
	for beat: int in beats:
		var beat_start: int = int(beat * LOUD_BEAT * RATE)
		# Kick: a sine sweeping down.
		var phase: float = 0.0
		for i: int in range(beat_start, mini(beat_start + int(0.22 * RATE), count)):
			var t: float = float(i - beat_start) / RATE
			phase += TAU * (48.0 + 110.0 * exp(-t * 28.0)) / RATE
			mix[i] += sin(phase) * exp(-t * 11.0) * 0.9
		# Hat on the offbeat: a burst of noise.
		var hat_start: int = beat_start + int(LOUD_BEAT * 0.5 * RATE)
		for i: int in range(hat_start, mini(hat_start + int(0.05 * RATE), count)):
			var t: float = float(i - hat_start) / RATE
			mix[i] += rng.randf_range(-1.0, 1.0) * exp(-t * 70.0) * 0.28
		# Two eighth notes of bass and lead per beat.
		var root: int = int(LOUD_ROOTS[beat >> 2])
		for half: int in 2:
			var start: int = beat_start + int(half * LOUD_BEAT * 0.5 * RATE)
			var length: int = int(LOUD_BEAT * 0.5 * RATE)
			var bass_f: float = hz(root if half == 0 else root + 12)
			var lead_f: float = hz(root + 36 + int(LOUD_LEAD[(beat * 2 + half) % LOUD_LEAD.size()]))
			for i: int in range(start, mini(start + length, count)):
				var t: float = float(i - start) / RATE
				var gate: float = minf(t / 0.004, 1.0) * exp(-t * 4.0)
				var bass: float = 1.0 if fmod(t * bass_f, 1.0) < 0.5 else -1.0
				var lead: float = 1.0 if fmod(t * lead_f, 1.0) < 0.35 else -1.0
				mix[i] += bass * gate * 0.3 + lead * gate * 0.13
	for i: int in count:
		mix[i] = tanh(mix[i] * 1.8)
	return _loop(mix, count)


## The newscast's jingle: a rising three-note "ta-ta-taa" through a small
## speaker. 0.9 s, once, no loop.
static func make_news_jingle() -> AudioStreamWAV:
	const NOTES: Array = [[0.0, 74, 0.16], [0.18, 74, 0.16], [0.36, 81, 0.5]]
	var count: int = int(RATE * 0.9)
	var mix := PackedFloat32Array()
	mix.resize(count)
	for note: Array in NOTES:
		var start: int = int(float(note[0]) * RATE)
		var f: float = hz(int(note[1]))
		var length: float = float(note[2])
		for i: int in range(start, mini(start + int(length * RATE), count)):
			var t: float = float(i - start) / RATE
			var envelope: float = minf(t / 0.006, 1.0) * minf((length - t) / 0.05, 1.0)
			mix[i] += (sin(TAU * f * t) * 0.7 + sin(TAU * f * 2.0 * t) * 0.25 + sin(TAU * f * 3.0 * t) * 0.1) * envelope
	return _one_shot(mix, 0.5)


## A dial's click: a short noise tick with a low thunk under it. 60 ms.
static func make_knob_click() -> AudioStreamWAV:
	var count: int = int(RATE * 0.06)
	var mix := PackedFloat32Array()
	mix.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4060
	for i: int in count:
		var t: float = float(i) / RATE
		mix[i] = (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 180.0 * t) * 0.7) * exp(-t * 70.0)
	return _one_shot(mix, 0.5)


## Scaled so the loop's RMS lands on LOOP_RMS_DB, looping forever.
static func _loop(mix: PackedFloat32Array, count: int) -> AudioStreamWAV:
	var total: float = 0.0
	for sample: float in mix:
		total += sample * sample
	var gain: float = db_to_linear(LOOP_RMS_DB) / maxf(sqrt(total / maxf(count, 1)), 0.000001)
	var stream := _stream(mix, gain)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream


## A one-shot at `gain` of full scale, peak-normalised.
static func _one_shot(mix: PackedFloat32Array, gain: float) -> AudioStreamWAV:
	var peak: float = 0.000001
	for sample: float in mix:
		peak = maxf(peak, absf(sample))
	return _stream(mix, gain / peak)


static func _stream(mix: PackedFloat32Array, gain: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(mix.size() * 2)
	for i: int in mix.size():
		data.encode_s16(i * 2, roundi(clampf(mix[i] * gain, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
