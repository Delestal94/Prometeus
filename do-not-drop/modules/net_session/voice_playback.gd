class_name VoicePlayback
extends AudioStreamPlayer3D
## One remote speaker's voice, played where they are: the playback half of
## SteamVoice. Portable module (docs/modulos.md). Feed it what
## `voice_received` hands out (16-bit mono little-endian PCM at a sample rate)
## with push_pcm(); it plays through an AudioStreamGenerator.
##
## A small jitter buffer sits in front of the generator. A phrase starts once
## `prebuffer_seconds` of it is queued (or once that long has passed), so
## packets that arrive a little uneven don't stutter. What is queued never
## passes `max_latency_seconds`: the oldest audio is dropped instead, so a
## burst after a network hiccup costs a skipped syllable, never a delay that
## stays for the rest of the conversation. With nothing to play for
## `idle_stop_seconds` it stops, so a quiet crewmate costs no mixing.
##
## Where the voice comes from and how it carries is the owner's call:
## `follow` is any Node3D (a head, a seat) whose position this copies every
## frame; carry_in_room() is a shared room (heard at full volume wherever the
## speaker is in it), carry_in_open() is open air (fades with distance, gone
## at `hearing_distance`, and with `muffled` heard through a wall: quieter and
## without its highs). `gain` is the linear volume; 0 drops what is queued.
##
## `gain` scales the samples as they come in, not `volume_db`: in Godot's
## AudioStreamPlayer3D a lower volume_db also counts as distance for the
## attenuation filter (measured: -20 dB of volume_db took a tone above the
## cutoff down 63 dB), so a crewmate turned down would also sound muffled.
## A new gain applies to the next packet; 0 is silent at once.
## A packet longer than the latency cap is cut to its newest part before it is
## converted: a flood costs at most that much conversion per packet.
##
## Nothing here is replicated: every peer plays the others locally.

const PCM_SCALE: float = 1.0 / 32768.0
const FALLBACK_SAMPLE_RATE: int = 24000
const MIN_SAMPLE_RATE: int = 8000
const MAX_SAMPLE_RATE: int = 48000
## The generator's own ring buffer (Godot rounds it up to a power of two):
## how far ahead of the mixer audio is handed over.
const GENERATOR_SECONDS: float = 0.1
## A cutoff above hearing: the distance filter is off.
const NO_FILTER_HZ: float = 20500.0
## Open air: far voices lose a little of their highs (Godot's default).
const OPEN_AIR_FILTER_HZ: float = 5000.0
## Through a wall: the highs go well before the voice does...
const MUFFLED_FILTER_HZ: float = 1200.0
## ...and it is quieter.
const MUFFLED_DB: float = -6.0

## The most audio held back (queued here plus handed to the mixer), seconds.
@export var max_latency_seconds: float = 0.3
## Audio gathered before a phrase starts, seconds.
@export var prebuffer_seconds: float = 0.06
## Silence after which the player stops, seconds.
@export var idle_stop_seconds: float = 0.5
## Open air: the distance at which the voice is still at full volume (metres).
@export var full_volume_distance: float = 3.0
## Open air: the distance past which it is not heard at all (metres).
@export var hearing_distance: float = 28.0
## The owner's mix level for voices, in dB (volume_db; see `gain` above).
@export var base_volume_db: float = 0.0

## What this player copies its position from every frame; null leaves it be.
var follow: Node3D = null
## Linear volume, 0..1, applied to the samples of each packet. At 0 nothing
## is queued and what was is dropped.
var gain: float = 1.0:
	set = set_gain
## The rate the generator runs at (the last push_pcm()'s).
var sample_rate: int = FALLBACK_SAMPLE_RATE
## Frames dropped to keep the latency bounded since this was created.
var dropped_frames: int = 0
## Frames converted from PCM since this was created (never more than the
## latency cap per packet).
var converted_frames: int = 0
## Whether carry_in_open(true) is in effect.
var muffled: bool = false

var _generator := AudioStreamGenerator.new()
var _playback: AudioStreamGeneratorPlayback = null
var _capacity: int = 0
var _pending := PackedVector2Array()
var _starved: bool = true
var _waiting: float = 0.0
var _idle: float = 0.0


func _init() -> void:
	_generator.mix_rate = FALLBACK_SAMPLE_RATE
	_generator.buffer_length = GENERATOR_SECONDS
	stream = _generator
	# Audio has no look to smooth, and the owner moves it in _process.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Voice is outside the simulation, like SteamVoice: a paused game still talks.
	process_mode = Node.PROCESS_MODE_ALWAYS
	carry_in_open()


func _process(delta: float) -> void:
	advance(delta)


## Queues a packet of 16-bit mono little-endian PCM at `rate` and plays it as
## soon as the jitter buffer allows.
func push_pcm(pcm: PackedByteArray, rate: int) -> void:
	if gain <= 0.0 or pcm.size() < 2 or not is_inside_tree():
		return
	var clamped: int = clampi(rate, MIN_SAMPLE_RATE, MAX_SAMPLE_RATE) if rate > 0 else FALLBACK_SAMPLE_RATE
	if clamped != sample_rate:
		_set_rate(clamped)
	var samples: int = pcm.size() >> 1
	var limit: int = _latency_limit()
	if samples > limit:
		# Only the newest part can ever be heard: don't convert the rest.
		dropped_frames += samples - limit
		pcm = pcm.slice((samples - limit) << 1, samples << 1)
		samples = limit
	_pending.append_array(pcm_to_frames(pcm, gain))
	converted_frames += samples
	_idle = 0.0
	_trim()
	_feed()


## One frame: follow the anchor, hand queued audio to the mixer, stop when
## the speaker has gone quiet. Separate from _process so tests can drive it.
func advance(delta: float) -> void:
	if is_instance_valid(follow) and follow.is_inside_tree():
		global_position = follow.global_position
	if not playing and _pending.is_empty():
		return
	_idle += delta
	if _pending.is_empty():
		if _idle >= idle_stop_seconds:
			silence()
		elif _generator_queued() == 0:
			# Ran dry mid-phrase: gather a cushion again before going on.
			_starved = true
			_waiting = 0.0
		return
	if _starved:
		_waiting += delta
	_feed()


## Drops everything queued and stops.
func silence() -> void:
	_pending.clear()
	_starved = true
	_waiting = 0.0
	_idle = 0.0
	if playing:
		stop()
	_playback = null
	_capacity = 0


func set_gain(value: float) -> void:
	gain = clampf(value, 0.0, 1.0)
	if gain <= 0.0:
		silence()


## A shared room: everyone in it is heard at full volume, still from where
## they are.
func carry_in_room() -> void:
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	max_distance = 0.0
	attenuation_filter_cutoff_hz = NO_FILTER_HZ
	muffled = false
	_apply_volume()


## Open air: fades with distance and is gone at `hearing_distance`; with
## `through_wall` it is also quieter and loses its highs.
func carry_in_open(through_wall: bool = false) -> void:
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	unit_size = full_volume_distance
	max_distance = hearing_distance
	attenuation_filter_cutoff_hz = MUFFLED_FILTER_HZ if through_wall else OPEN_AIR_FILTER_HZ
	muffled = through_wall
	_apply_volume()


## Audio waiting to be heard (queued here plus handed to the mixer), seconds.
func buffered_seconds() -> float:
	return float(queued_frames()) / float(maxi(sample_rate, 1))


func queued_frames() -> int:
	return _pending.size() + _generator_queued()


## Whether there is voice to hear right now (a "talking" icon over a head).
func is_speaking() -> bool:
	return playing and queued_frames() > 0


## 16-bit signed little-endian mono samples to stereo frames in -1..1, times `scale`.
static func pcm_to_frames(pcm: PackedByteArray, scale: float = 1.0) -> PackedVector2Array:
	var count: int = pcm.size() >> 1
	var frames := PackedVector2Array()
	frames.resize(count)
	var factor: float = PCM_SCALE * scale
	for index: int in count:
		var sample: float = pcm.decode_s16(index << 1) * factor
		frames[index] = Vector2(sample, sample)
	return frames


## The ceiling follows the volume: up close, open air is never louder than
## the same voice in a room. Muffled, the lower volume_db also makes the
## distance filter bite up close: that is the wall.
func _apply_volume() -> void:
	volume_db = base_volume_db + (MUFFLED_DB if muffled else 0.0)
	max_db = clampf(volume_db, -24.0, 6.0)


## A new rate: the generator's mix_rate only takes effect on a new playback,
## and audio queued at the old one would play at the wrong pitch.
func _set_rate(rate: int) -> void:
	silence()
	sample_rate = rate
	_generator.mix_rate = rate


func _latency_limit() -> int:
	return maxi(1, int(max_latency_seconds * sample_rate))


## Drops the oldest queued audio past the latency limit.
func _trim() -> void:
	var excess: int = queued_frames() - _latency_limit()
	if excess <= 0:
		return
	var cut: int = mini(excess, _pending.size())
	_pending = _pending.slice(cut)
	dropped_frames += cut


## Hands queued audio to the mixer: never past the latency limit, and at the
## start of a phrase only once the cushion is there.
func _feed() -> void:
	if _pending.is_empty() or not is_inside_tree():
		return
	if _starved:
		if _pending.size() < int(prebuffer_seconds * sample_rate) and _waiting < prebuffer_seconds:
			return
		_starved = false
		_waiting = 0.0
	if not playing or _playback == null:
		_start()
		if _playback == null:
			return
	elif get_stream_playback() != _playback:
		# Restarted from outside (a sound check swapping streams): a new, empty one.
		_adopt_playback()
		if _playback == null:
			return
	var room: int = mini(_playback.get_frames_available(), _latency_limit() - _generator_queued())
	var count: int = mini(room, _pending.size())
	if count <= 0:
		return
	if count == _pending.size():
		_playback.push_buffer(_pending)
		_pending = PackedVector2Array()
	else:
		_playback.push_buffer(_pending.slice(0, count))
		_pending = _pending.slice(count)


func _start() -> void:
	play()
	_adopt_playback()


## Right after play() the generator is empty: everything free is the whole ring.
func _adopt_playback() -> void:
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback
	_capacity = _playback.get_frames_available() if _playback != null else 0


func _generator_queued() -> int:
	if _playback == null or not playing:
		return 0
	return maxi(0, _capacity - _playback.get_frames_available())
