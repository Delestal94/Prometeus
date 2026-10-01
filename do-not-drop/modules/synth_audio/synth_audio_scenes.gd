class_name SynthAudioScenes
extends RefCounted
## The generators behind SynthAudio's scene sounds -- the doorbell and the
## neighbour's reaction, the comic ruin stingers, the forklift, the river and
## the train, the scanner, the callout voice. Split out of synth_audio.gd to
## keep it readable; SynthAudio still hands them out (and caches them), so
## callers never use this class directly.


## The delivery doorbell (docs/inventario-assets.md, "Timbre / panel de
## puerta"): its own two-note "ding-dong" instead of reusing Frágil's bright
## glass chime -- ringing a doorbell shouldn't sound like a box breaking.
## Two struck tones a fourth apart (A5 then E5), each a few harmonics through
## a soft, warm decay: lower and rounder than glass_chime's bright inharmonic
## partials, on purpose, so the two read as different things by ear alone.
const DOORBELL_DING_DONG_STREAM_LOUDEST_DB: float = -12.0


static func make_doorbell_ding_dong() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 1.05
	# [when it strikes, its pitch, how fast it decays]: "ding" first, then the
	# lower "dong" while the first is still ringing out.
	const NOTES: Array = [[0.0, 880.0, 6.0], [0.32, 659.25, 4.5]]
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	for note: Array in NOTES:
		var begin: int = int(float(note[0]) * RATE)
		var freq: float = note[1]
		var decay: float = note[2]
		for i: int in range(begin, sample_count):
			var t: float = float(i - begin) / RATE
			var envelope: float = exp(-t * decay) * minf(t / 0.006, 1.0)
			var wave: float = (sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 2.0 * t) * 0.22
					+ sin(TAU * freq * 3.0 * t) * 0.08)
			mix[i] += wave * envelope
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, DOORBELL_DING_DONG_STREAM_LOUDEST_DB, true)
	return stream


## The resident's happy reaction at the door (delivery_house.gd): a bright,
## three-note cartoon "ta-da" -- it used to reuse the truck's own two-tone
## horn, so a delivery going well sounded like somebody honking. Three
## plucked notes climbing a triad (C5-E5-G5), soft attacks, with a light
## vibrato on the last note's tail for the "cheer".
const NEIGHBOR_CHEER_STREAM_LOUDEST_DB: float = -12.0


static func make_neighbor_cheer() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.62
	const NOTES: Array = [[0.0, 523.25], [0.11, 659.25], [0.22, 783.99]]
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	for index: int in range(NOTES.size()):
		var begin: int = int(float(NOTES[index][0]) * RATE)
		var freq: float = NOTES[index][1]
		var last: bool = index == NOTES.size() - 1
		for i: int in range(begin, sample_count):
			var t: float = float(i - begin) / RATE
			var vibrato: float = 1.0 + (0.012 * sin(TAU * 7.0 * t) if last else 0.0)
			var envelope: float = minf(t / 0.008, 1.0) * exp(-t * (5.0 if last else 9.0))
			var wave: float = sin(TAU * freq * vibrato * t) * 0.6 + sin(TAU * freq * vibrato * 2.0 * t) * 0.25
			mix[i] += wave * envelope
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, NEIGHBOR_CHEER_STREAM_LOUDEST_DB, true)
	return stream


## A cartoon "aw, no" for any trap reaching RUINED (package_feedback.gd),
## alongside the confetti burst and whatever that trap's own cue already
## does -- Frágil gets its own pitched-down chime on top of this, but the
## other four traps had nothing marking the moment itself, only the tint and
## the burst. A muted "wah-wah-waaah", three falling notes trombone-style,
## each sliding down a little on its own, with a soft noise "crunch" right
## at the start where the box actually gives way.
const RUIN_STINGER_STREAM_LOUDEST_DB: float = -12.0


static func make_comic_ruin_stinger() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.6
	const STARTS: Array[float] = [330.0, 262.0, 196.0]
	const ENDS: Array[float] = [300.0, 235.0, 165.0]
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var noise: float = 0.0
	var phase: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var k: float = t / DURATION
		var segment: int = mini(int(k * 3.0), 2)
		var seg_k: float = clampf(k * 3.0 - float(segment), 0.0, 1.0)
		var wobble: float = 1.0 + sin(TAU * 14.0 * t) * 0.02
		var freq: float = lerpf(STARTS[segment], ENDS[segment], seg_k) * wobble
		phase += TAU * freq / RATE
		var voice: float = sin(phase) * 0.5 + sin(phase * 2.0) * 0.22 + sin(phase * 3.0) * 0.08
		noise = lerpf(noise, randf_range(-1.0, 1.0), 0.5)
		var crunch: float = noise * exp(-t * 40.0) * 0.6
		var envelope: float = minf(t / 0.01, 1.0) * (1.0 - k * 0.15)
		mix[i] = (voice * 0.8 + crunch) * envelope
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, RUIN_STINGER_STREAM_LOUDEST_DB, true)
	return stream


## Explosivo's payoff when the timer runs out (explosive_trap_behavior.gd's
## get_hint() already just says "BOOM." at that point): a cartoon explosion
## instead of the countdown simply stopping -- a low thump, a burst of noise,
## and a little ringing "sparkle" as the smoke clears. Plays instead of
## comic_ruin_stinger() for this one trap (package_feedback.gd).
const COMIC_BOOM_STREAM_LOUDEST_DB: float = -10.0


static func make_comic_boom() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 0.9
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var noise: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var thump: float = sin(TAU * 68.0 * t) * exp(-t * 9.0)
		noise = lerpf(noise, randf_range(-1.0, 1.0), 0.7)
		var crackle: float = noise * exp(-t * 5.0)
		var sparkle: float = sin(TAU * 1800.0 * t) * exp(-t * 14.0) * (0.15 if t > 0.05 else 0.0)
		mix[i] = thump * 0.7 + crackle * 0.75 + sparkle
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, COMIC_BOOM_STREAM_LOUDEST_DB, true)
	return stream


## The forklift's electric drivetrain (depot_forklift.gd): it used to share
## the truck's own engine_loop() (just pitched differently), so the yard's
## reach truck sounded like a second diesel van. This is a small AC motor
## instead -- a higher, thinner electric hum with a metallic edge and no low
## rumble at all, plus the faint whistle of its hydraulics riding on top.
## depot_forklift.gd still drives its pitch (faster driving, or lifting).
const FORKLIFT_MOTOR_STREAM_RMS_DB: float = -16.0


static func make_forklift_motor_loop() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 1.0
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		# Whole cycles over one second (110/220/330 Hz hum, 1900/2850 Hz
		# whine): the loop's seam stays silent.
		var hum: float = sin(TAU * 110.0 * t) * 0.4 + sin(TAU * 220.0 * t) * 0.3 + sin(TAU * 330.0 * t) * 0.14
		var whine: float = sin(TAU * 1900.0 * t) * 0.05 + sin(TAU * 2850.0 * t) * 0.02
		mix[i] = hum + whine
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, FORKLIFT_MOTOR_STREAM_RMS_DB, false)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


## The river under the narrow bridge (docs/tareas-nacho.md #178 warns against
## repeating the depot's old zumbido: a flat drone with no real position).
## This is an ordinary positioned 3D loop instead, same recipe as the wind
## and the distant road -- water running over a bed, a band of noise
## (~180-650 Hz) that swells and eases every few seconds like the current
## picking up round a bend, plus a scatter of tiny high "droplet" clicks for
## texture. narrow_bridge_segment.gd places it at the water and lets the
## player's own unit_size/max_distance do the falling-off, so it's loud
## crossing right over it and fades well before the next segment.
const RIVER_FLOW_STREAM_RMS_DB: float = -20.0


static func make_river_flow_loop() -> AudioStreamWAV:
	const RATE: int = 11025
	const DURATION: float = 9.0
	const FADE: float = 1.2
	var loop_count: int = int(RATE * DURATION)
	var raw := PackedFloat32Array()
	raw.resize(loop_count + int(RATE * FADE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 59
	var band: float = 0.0
	var band_2: float = 0.0
	var rumble: float = 0.0
	var droplet: float = 0.0
	for i: int in range(raw.size()):
		var t: float = float(i) / RATE
		var swell: float = 0.7 + 0.3 * sin(TAU * t / DURATION + 0.6)
		var opening: float = lerpf(0.14, 0.27, swell)
		band = lerpf(band, rng.randf_range(-1.0, 1.0), opening)
		band_2 = lerpf(band_2, band, opening)
		rumble = lerpf(rumble, band_2, 0.1)
		var flow: float = (band_2 - rumble) * swell
		if rng.randf() < 0.006:
			droplet = rng.randf_range(0.2, 0.5)
		droplet *= 0.9
		raw[i] = flow * 0.85 + droplet * rng.randf_range(-1.0, 1.0) * 0.15
	return SynthAudioDsp.loop(SynthAudioDsp.normalized(SynthAudioDsp.seamless_loop(raw, loop_count), RATE,
			RIVER_FLOW_STREAM_RMS_DB), RATE, loop_count)


## The cartoon steam train's own horn (rail_crossing_segment.gd): a classic
## two-tone whistle chord over a breath of steam -- "toot, tooooot" as the
## cars start across, on top of the crossing bell rather than instead of it.
const TRAIN_HORN_STREAM_LOUDEST_DB: float = -12.0


static func make_train_horn() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 1.3
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var noise: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var attack: float = minf(t / 0.05, 1.0)
		var release: float = minf((DURATION - t) / 0.18, 1.0)
		# A short toot, a breath of silence, then the longer held blast.
		var gap: bool = t > 0.32 and t < 0.46
		var envelope: float = 0.0 if gap else attack * release
		var chord: float = (sin(TAU * 466.0 * t) + sin(TAU * 554.0 * t)) * 0.5
		noise = lerpf(noise, randf_range(-1.0, 1.0), 0.3)
		mix[i] = (chord * 0.85 + noise * 0.1) * envelope
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, TRAIN_HORN_STREAM_LOUDEST_DB, true)
	return stream


## The train's chugging as it crosses (rail_crossing_segment.gd, State.TRAIN):
## rhythmic steam "chuffs" -- decaying bursts of filtered noise -- with a
## wheel clack on the rail joints riding in between, looping for as long as
## the cars are actually on screen.
const TRAIN_CHUG_STREAM_RMS_DB: float = -14.0


static func make_train_chug_loop() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: float = 1.0
	var sample_count: int = int(RATE * DURATION)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var chuff: float = 0.0
	var clack: float = 0.0
	# Four evenly spaced chuffs a second (a driving wheel turning over), one
	# rail clack offset half a beat from them.
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		if fmod(t * 4.0, 1.0) < 4.0 / RATE:
			chuff = 1.0
		chuff *= 0.9975
		if fmod(t * 4.0 + 0.5, 1.0) < 4.0 / RATE:
			clack = 1.0
		clack *= 0.994
		mix[i] = chuff * randf_range(-1.0, 1.0) * 0.8 + clack * sin(TAU * 1400.0 * t) * 0.3
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, TRAIN_CHUG_STREAM_RMS_DB, false)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


## A parcel scanner's "bip" for menu buttons (main menu redesign,
## 2026-09-25): one short square-ish beep at 2.4 kHz, 70 ms, soft edges so
## it never clicks. Short on purpose -- it plays on every press.
static func make_scanner_beep() -> AudioStreamWAV:
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


## A crewmate's quick callout (N-505, the ping wheel): cartoon babble, not
## words -- one "syllable" per vowel group of the phrase, a buzzing voice
## through a mouth that jumps between vowels (the same formant trick as
## dog_bark()). The voice's base pitch is the player's colour slot
## (the index the game gives each player, wrapped to these eight), so with eyes on the road
## the driver can still tell who is calling. Deterministic: slot and
## syllable count pick the vowels, so every client hears the same call.

## One base pitch (Hz) per player colour slot, low to high: far enough
## apart (~20 %) that two crewmates never sound alike. One per seat of a full
## room (N-228.3); the first five are unchanged, 5..7 keep climbing by ~20 %.
const CALLOUT_VOICE_PITCHES: Array[float] = [150.0, 180.0, 215.0, 260.0, 310.0, 370.0, 440.0, 520.0]
const CALLOUT_MAX_SYLLABLES: int = 5
const CALLOUT_SYLLABLE_SECONDS: float = 0.12
const CALLOUT_VOICE_STREAM_LOUDEST_DB: float = -12.0
## Vowel mouths [first formant, second formant] in Hz: a, e, i, o, u.
const _VOWEL_FORMANTS: Array[Vector2] = [
	Vector2(800.0, 1250.0), Vector2(500.0, 1850.0), Vector2(320.0, 2300.0),
	Vector2(520.0, 900.0), Vector2(340.0, 750.0),
]


static func make_callout_voice(slot: int, count: int) -> AudioStreamWAV:
	const RATE: int = 22050
	var base_pitch: float = CALLOUT_VOICE_PITCHES[slot]
	var duration: float = CALLOUT_SYLLABLE_SECONDS * count + 0.05
	var sample_count: int = int(RATE * duration)
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 + slot * 16 + count
	var vowels: Array[Vector2] = []
	var lifts: Array[float] = []
	for s: int in range(count):
		vowels.append(_VOWEL_FORMANTS[rng.randi_range(0, _VOWEL_FORMANTS.size() - 1)])
		lifts.append(rng.randf_range(0.92, 1.1))
	var phase: float = 0.0
	var mouth_low := SynthAudioDsp.Resonator.new()
	var mouth_high := SynthAudioDsp.Resonator.new()
	for i: int in range(sample_count):
		var t: float = float(i) / RATE
		var s: int = mini(int(t / CALLOUT_SYLLABLE_SECONDS), count - 1)
		var local: float = (t - s * CALLOUT_SYLLABLE_SECONDS) / CALLOUT_SYLLABLE_SECONDS
		# A call, not a statement: every syllable bends up a little and the
		# phrase climbs toward its last one.
		var bend: float = 1.0 + 0.1 * sin(PI * minf(local, 1.0))
		var pitch: float = base_pitch * lifts[s] * (1.0 + 0.08 * float(s) / count) * bend
		phase = fmod(phase + pitch / RATE, 1.0)
		var voice: float = 0.0
		var harmonics: int = mini(int(4500.0 / pitch), 16)
		for n: int in range(1, harmonics + 1):
			voice += sin(TAU * phase * n) / float(n)
		# The mouth glides from the previous vowel into this one.
		var previous: Vector2 = vowels[maxi(s - 1, 0)]
		var mouth: Vector2 = previous.lerp(vowels[s], minf(local * 4.0, 1.0))
		var sound: float = (mouth_low.filter(voice, mouth.x, 4.0, RATE)
			+ mouth_high.filter(voice, mouth.y, 6.0, RATE) * 0.5)
		# Each syllable opens fast and closes before the next one (a consonant's gap).
		var envelope: float = 0.0
		if local <= 1.0:
			envelope = minf(local / 0.08, 1.0) * clampf((1.0 - local) / 0.25, 0.0, 1.0)
		mix[i] = sound * envelope
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = SynthAudioDsp.normalized(mix, RATE, CALLOUT_VOICE_STREAM_LOUDEST_DB, true)
	return stream
