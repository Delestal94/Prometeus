class_name SynthAudioWorkMusic
extends RefCounted
## A work loop in layers: four bars of an easy-going groove (I-vi-IV-V in D, LOOP_BPM), split in LAYERS stems
## of exactly the same length, so a player can run them in sync (AudioStreamSynchronized) and bring each in or
## out with its volume: an adaptive loop. Pure synthesis, no node; SynthAudio caches the streams.
##   0 "bed"     bass on every beat and a soft pad per bar: the floor that always plays;
##   1 "groove"  kick, clap and hats: comes in when there is work;
##   2 "lead"    a plucked pentatonic tune on the eighths: comes in when it gets busy.
## Every note starts and dies inside the loop (the pad swells and fades within its bar, the last notes are
## faded at the seam), so the loop point is silent-safe. Each stem is normalized to MUSIC_RMS_DB on its own.

const Dsp = preload("res://modules/synth_audio/synth_audio_dsp.gd")
const RATE: int = 22050
const LOOP_BPM: float = 108.0
const BEATS: int = 16
const LAYERS: int = 3
const MUSIC_RMS_DB: float = -18.0
## Bar roots (D3, B2, G2, A2) and their triads as semitones over the root (major, minor, major, major).
const ROOTS: Array[float] = [146.83, 123.47, 98.0, 110.0]
const TRIADS: Array = [[0, 4, 7], [0, 3, 7], [0, 4, 7], [0, 4, 7]]
## The tune: D major pentatonic degrees (semitones over D4) per eighth; -1 is a rest.
const TUNE: Array[int] = [
	0, -1, 4, 7, 9, -1, 7, 4, 2, -1, 4, 2, -1, -1, 9, 7,
	7, -1, 9, 12, 9, -1, 7, 4, 4, -1, 2, 4, 7, -1, -1, -1,
]
const TUNE_ROOT: float = 293.66
const NOISE_SEED: int = 1911


## Samples in one loop (every layer has exactly this many).
static func loop_samples() -> int:
	return int(round(RATE * BEATS * 60.0 / LOOP_BPM))


static func make_layer(layer: int) -> AudioStreamWAV:
	var count: int = loop_samples()
	var mix := PackedFloat32Array()
	mix.resize(count)
	var beat_seconds: float = 60.0 / LOOP_BPM
	var duration: float = float(count) / RATE
	var noise := RandomNumberGenerator.new()
	noise.seed = NOISE_SEED + layer
	for index: int in count:
		var time: float = float(index) / RATE
		var beat: int = mini(int(time / beat_seconds), BEATS - 1)
		var local: float = time - beat * beat_seconds
		var sample: float = 0.0
		match layer:
			0:
				sample = _bed(time, beat, local, beat_seconds)
			1:
				sample = _groove(beat, local, beat_seconds, noise.randf_range(-1.0, 1.0))
			_:
				sample = _lead(time, beat_seconds)
		var edge: float = minf(minf(time, duration - time) / 0.01, 1.0)
		mix[index] = sample * maxf(edge, 0.0)
	return Dsp.loop(Dsp.normalized(mix, RATE, MUSIC_RMS_DB), RATE, count)


## Bass pluck on the beat (root, an octave up on the off beats) and a pad triad that swells in its bar.
static func _bed(time: float, beat: int, local: float, beat_seconds: float) -> float:
	var bar: int = beat >> 2
	var root: float = ROOTS[bar]
	var pitch: float = root * (1.0 if beat % 2 == 0 else 2.0) * 0.5
	var pluck: float = minf(local / 0.006, 1.0) * exp(-local * 5.0)
	var bass: float = (sin(TAU * pitch * time) + sin(TAU * pitch * 2.0 * time) * 0.3) * pluck * 0.6
	var bar_seconds: float = beat_seconds * 4.0
	var in_bar: float = time - bar * bar_seconds
	var swell: float = smoothstep(0.0, 0.35, in_bar) * smoothstep(0.0, 0.35, bar_seconds - in_bar)
	var pad: float = 0.0
	for step: int in TRIADS[bar]:
		var tone: float = root * 2.0 * pow(2.0, float(step) / 12.0)
		pad += sin(TAU * tone * time + 0.4 * sin(TAU * 0.5 * time))
	return bass + pad * swell * 0.12


## Kick on 1 and 3, a clap on 2 and 4, closed hats on every eighth. `white` is this sample's noise.
static func _groove(beat: int, local: float, beat_seconds: float, white: float) -> float:
	var out: float = 0.0
	if beat % 2 == 0:
		var sweep: float = 50.0 + 90.0 * exp(-local * 30.0)
		out += sin(TAU * sweep * local) * exp(-local * 9.0) * 0.9
	else:
		out += white * exp(-local * 18.0) * 0.45
	var eighth: float = fmod(local, beat_seconds * 0.5)
	out += white * exp(-eighth * 70.0) * (0.22 if eighth < local else 0.14)
	return out


## The plucked tune: a soft square-ish tone per eighth that dies before the next.
static func _lead(time: float, beat_seconds: float) -> float:
	var eighth_seconds: float = beat_seconds * 0.5
	var slot: int = mini(int(time / eighth_seconds), TUNE.size() - 1)
	var degree: int = TUNE[slot]
	if degree < 0:
		return 0.0
	var into: float = time - slot * eighth_seconds
	var pitch: float = TUNE_ROOT * pow(2.0, float(degree) / 12.0)
	var phase: float = TAU * pitch * time
	var tone: float = sin(phase) + sin(phase * 3.0) / 5.0 + sin(phase * 2.0) * 0.2
	return tone * minf(into / 0.004, 1.0) * exp(-into * 7.0) * 0.5
