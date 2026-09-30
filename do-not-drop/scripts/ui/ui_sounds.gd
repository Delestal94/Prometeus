class_name UiSounds
extends RefCounted
## Short interface cues synthesized in code and routed through the SFX bus.
##
## UI audio stays separate from SynthAudio because that file is shared with
## the world/vehicle presentation domain. Streams are cached after their first
## use, while one root-level player per cue keeps rapid hover sounds cheap.
##
## Stingers (S-403) are the other family here: 2-4 s musical phrases for the
## moments that close something (result screen, unlock, route event). They go
## through the Music bus and share ONE root-level player, so a new stinger
## replaces the one still ringing instead of stacking on top of it.

const SAMPLE_RATE: int = 22050
const PLAYER_PREFIX: String = "UiSound_"
const BOUND_META: StringName = &"ui_sounds_bound"

const HOVER: StringName = &"hover"
const CLICK: StringName = &"click"
const PANEL_OPEN: StringName = &"panel_open"
const PANEL_CLOSE: StringName = &"panel_close"
const TOAST: StringName = &"toast"
const UNLOCK: StringName = &"unlock"
const VOTE: StringName = &"vote"
const ERROR: StringName = &"error"

const CUES: Array[StringName] = [
	HOVER, CLICK, PANEL_OPEN, PANEL_CLOSE, TOAST, UNLOCK, VOTE, ERROR,
]

const _SPECS: Dictionary = {
	HOVER: {"start": 880.0, "end": 1040.0, "duration": 0.045, "gain": 0.20, "volume_db": 2.7},
	CLICK: {"start": 520.0, "end": 360.0, "duration": 0.085, "gain": 0.32, "volume_db": -1.4},
	PANEL_OPEN: {"start": 330.0, "end": 660.0, "duration": 0.14, "gain": 0.28, "volume_db": -0.2},
	PANEL_CLOSE: {"start": 660.0, "end": 300.0, "duration": 0.12, "gain": 0.25, "volume_db": 0.7},
	TOAST: {"start": 720.0, "end": 920.0, "duration": 0.16, "gain": 0.24, "volume_db": 1.1},
	UNLOCK: {"start": 620.0, "end": 1320.0, "duration": 0.30, "gain": 0.30, "volume_db": -0.8},
	VOTE: {"start": 440.0, "end": 700.0, "duration": 0.11, "gain": 0.27, "volume_db": 0.1},
	ERROR: {"start": 190.0, "end": 120.0, "duration": 0.22, "gain": 0.35, "volume_db": -2.2},
}

const STINGER_PLAYER_NAME: String = "UiStinger"
const STINGER_QUEUED_META: StringName = &"stinger_queued"
const STINGER_RATE: int = 16000
## Normalised peak of every stinger: about -4 dBFS, so chords never clip.
const STINGER_PEAK: float = 0.63
const STINGER_ATTACK: float = 0.008
const STINGER_TAIL: float = 0.06

const STINGER_PERFECT: StringName = &"stinger_perfect"
const STINGER_LOSSES: StringName = &"stinger_losses"
const STINGER_RECORD: StringName = &"stinger_record"
const STINGER_UNLOCK: StringName = &"stinger_unlock"
const STINGER_EVENT_WON: StringName = &"stinger_event_won"
const STINGER_EVENT_FAILED: StringName = &"stinger_event_failed"

const STINGERS: Array[StringName] = [
	STINGER_PERFECT, STINGER_LOSSES, STINGER_RECORD, STINGER_UNLOCK, STINGER_EVENT_WON, STINGER_EVENT_FAILED,
]

## Each phrase: "notes" are [midi, start_seconds, length_seconds, optional
## pitch bend in semitones over the note]; "harmonics" the amplitudes of
## partials 1..n; "decay" the release exponent (higher = plucked, lower =
## held); "vibrato" a depth in semitones for notes of 1 s or more.
const _STINGER_SPECS: Dictionary = {
	# C major fanfare: quick arpeggio up, a top note, then the held chord.
	STINGER_PERFECT: {
		"notes": [[72, 0.0, 0.30], [76, 0.13, 0.30], [79, 0.26, 0.30], [84, 0.42, 0.40],
			[72, 0.85, 1.65], [76, 0.85, 1.65], [79, 0.85, 1.65], [84, 0.85, 1.65]],
		"harmonics": [1.0, 0.30, 0.10], "decay": 1.6, "volume_db": -1.0,
	},
	# Sad trombone in B flat: four steps down, the last one sagging and wobbling.
	STINGER_LOSSES: {
		"notes": [[70, 0.0, 0.42], [69, 0.45, 0.42], [68, 0.90, 0.42], [67, 1.35, 1.35, -1.5]],
		"harmonics": [1.0, 0.0, 0.45, 0.0, 0.2], "decay": 0.9, "vibrato": 0.25, "volume_db": -2.0,
	},
	# G major, higher and bigger than PERFECT: a scale run, a shimmering chord.
	STINGER_RECORD: {
		"notes": [[67, 0.0, 0.30], [71, 0.10, 0.30], [74, 0.20, 0.30], [79, 0.30, 0.30], [83, 0.40, 0.30],
			[86, 0.50, 0.40], [79, 0.95, 2.05], [83, 0.95, 2.05], [86, 0.95, 2.05], [91, 0.95, 2.05],
			[95, 1.35, 0.30], [91, 1.60, 0.30], [95, 1.85, 0.60]],
		"harmonics": [1.0, 0.35, 0.12], "decay": 1.4, "vibrato": 0.08, "volume_db": -2.0,
	},
	# Bell-like sparkle rising over an E major chord, softer than the results.
	STINGER_UNLOCK: {
		"notes": [[76, 0.0, 0.35], [81, 0.10, 0.35], [83, 0.20, 0.35], [88, 0.30, 0.45],
			[76, 0.65, 1.85], [80, 0.65, 1.85], [83, 0.65, 1.85], [88, 0.65, 1.85]],
		"harmonics": [1.0, 0.15, 0.0, 0.35], "decay": 1.8, "volume_db": -2.5,
	},
	# F major pluck, short and confident: "task done".
	STINGER_EVENT_WON: {
		"notes": [[65, 0.0, 0.20], [69, 0.16, 0.20], [72, 0.32, 0.20], [77, 0.48, 0.40],
			[69, 0.90, 1.35], [72, 0.90, 1.35], [77, 0.90, 1.35]],
		"harmonics": [1.0, 0.50, 0.25], "decay": 2.4, "volume_db": -1.5,
	},
	# Low descending minor pluck that ends on a sagging note: "oops".
	STINGER_EVENT_FAILED: {
		"notes": [[65, 0.0, 0.32], [62, 0.34, 0.32], [59, 0.68, 0.32], [53, 1.02, 1.30, -1.0]],
		"harmonics": [1.0, 0.40, 0.0, 0.20], "decay": 2.0, "volume_db": -1.5,
	},
}

static var _cache: Dictionary = {}
static var _stinger_cache: Dictionary = {}


static func bind_button(button: Button) -> void:
	if bool(button.get_meta(BOUND_META, false)):
		return
	button.set_meta(BOUND_META, true)
	button.mouse_entered.connect(func() -> void: play(button, HOVER))
	button.pressed.connect(func() -> void: play(button, CLICK))


static func is_button_bound(button: Button) -> bool:
	return bool(button.get_meta(BOUND_META, false))


static func play(from: Node, cue: StringName) -> void:
	if from == null or not from.is_inside_tree() or not _SPECS.has(cue):
		return
	var root: Window = from.get_tree().root
	var player_name := StringName("%s%s" % [PLAYER_PREFIX, cue])
	var player := root.get_node_or_null(NodePath(String(player_name))) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = player_name
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.bus = &"SFX"
		root.add_child(player)
	player.stream = stream_for(cue)
	player.volume_db = volume_db_for(cue)
	player.play()


static func stream_for(cue: StringName) -> AudioStreamWAV:
	if not _SPECS.has(cue):
		return null
	if not _cache.has(cue):
		_cache[cue] = _build_stream(_SPECS[cue])
	return _cache[cue] as AudioStreamWAV


static func volume_db_for(cue: StringName) -> float:
	return float((_SPECS.get(cue, {}) as Dictionary).get("volume_db", 0.0))


static func _build_stream(spec: Dictionary) -> AudioStreamWAV:
	var duration: float = float(spec["duration"])
	var sample_count: int = maxi(1, roundi(float(SAMPLE_RATE) * duration))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for index: int in range(sample_count):
		var progress: float = float(index) / float(sample_count)
		var frequency: float = lerpf(float(spec["start"]), float(spec["end"]), progress)
		phase += TAU * frequency / float(SAMPLE_RATE)
		var attack: float = minf(progress / 0.06, 1.0)
		var release: float = pow(1.0 - progress, 2.0)
		var tone: float = sin(phase) * 0.78 + sin(phase * 2.0) * 0.22
		var sample: float = clampf(tone * attack * release * float(spec["gain"]), -1.0, 1.0)
		data.encode_s16(index * 2, roundi(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream


## Which stinger closes the results screen. A new record wins over everything;
## otherwise it is PERFECT only when nothing was lost: a failed delivery, a
## ruined box, a door missed or a box left on the road all make it LOSSES.
## Endless has no delivery, so only ruined boxes count there.
static func result_stinger(results: Dictionary, is_record: bool) -> StringName:
	if is_record:
		return STINGER_RECORD
	if int(results.get("cargo_ruined", 0)) > 0:
		return STINGER_LOSSES
	if results.has("distance_traveled"):
		return STINGER_PERFECT
	if not bool(results.get("delivered", false)):
		return STINGER_LOSSES
	if int(results.get("houses_missed", 0)) + int(results.get("houses_lost", 0)) > 0:
		return STINGER_LOSSES
	for entry: Dictionary in results.get("deliveries", []):
		if StringName(entry.get("outcome", &"delivered_ok")) in [&"delivered_ruined", &"missed", &"lost"]:
			return STINGER_LOSSES
	return STINGER_PERFECT


## Plays a stinger on the shared Music-bus player, replacing whatever stinger
## is still ringing. Returns that player (null when the id or node is invalid).
static func play_stinger(from: Node, id: StringName) -> AudioStreamPlayer:
	if from == null or not from.is_inside_tree() or not _STINGER_SPECS.has(id):
		return null
	var player: AudioStreamPlayer = _stinger_player(from.get_tree().root)
	player.stream = stinger_stream(id)
	player.volume_db = stinger_volume_db(id)
	player.play()
	return player


## Plays a stinger without cutting the current one: one frame later (so a
## result stinger fired in the same frame gets there first) it starts at once
## if the player is idle, otherwise right after the ringing one finishes.
## The unlock toast uses it: unlock_earned fires just before the results
## screen, and both should be heard, results first.
static func queue_stinger(from: Node, id: StringName) -> void:
	if from == null or not from.is_inside_tree() or not _STINGER_SPECS.has(id):
		return
	from.get_tree().process_frame.connect(_start_queued.bind(from.get_tree().root, id), CONNECT_ONE_SHOT)


static func _start_queued(root: Window, id: StringName) -> void:
	var player: AudioStreamPlayer = _stinger_player(root)
	if player.playing:
		player.set_meta(STINGER_QUEUED_META, id)
	else:
		play_stinger(root, id)


## The shared stinger player, or null before the first stinger played.
static func stinger_player(from: Node) -> AudioStreamPlayer:
	if from == null or not from.is_inside_tree():
		return null
	return from.get_tree().root.get_node_or_null(NodePath(STINGER_PLAYER_NAME)) as AudioStreamPlayer


static func stinger_stream(id: StringName) -> AudioStreamWAV:
	if not _STINGER_SPECS.has(id):
		return null
	if not _stinger_cache.has(id):
		_stinger_cache[id] = _build_stinger(_STINGER_SPECS[id])
	return _stinger_cache[id] as AudioStreamWAV


static func stinger_duration(id: StringName) -> float:
	var stream: AudioStreamWAV = stinger_stream(id)
	return 0.0 if stream == null else float(stream.data.size()) / 2.0 / float(stream.mix_rate)


static func stinger_volume_db(id: StringName) -> float:
	return float((_STINGER_SPECS.get(id, {}) as Dictionary).get("volume_db", 0.0))


static func _stinger_player(root: Window) -> AudioStreamPlayer:
	var player := root.get_node_or_null(NodePath(STINGER_PLAYER_NAME)) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = STINGER_PLAYER_NAME
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.bus = &"Music"
		root.add_child(player)
		player.finished.connect(_play_queued.bind(player))
	return player


static func _play_queued(player: AudioStreamPlayer) -> void:
	var queued: StringName = StringName(player.get_meta(STINGER_QUEUED_META, &""))
	if queued.is_empty():
		return
	player.remove_meta(STINGER_QUEUED_META)
	play_stinger(player, queued)


static func _build_stinger(spec: Dictionary) -> AudioStreamWAV:
	var notes: Array = spec["notes"]
	var end_seconds: float = 0.0
	for note: Array in notes:
		end_seconds = maxf(end_seconds, float(note[1]) + float(note[2]))
	var sample_count: int = roundi((end_seconds + STINGER_TAIL) * float(STINGER_RATE))
	var mix := PackedFloat32Array()
	mix.resize(sample_count)
	for note: Array in notes:
		_add_stinger_note(mix, note, spec)
	var peak: float = 0.0
	for sample: float in mix:
		peak = maxf(peak, absf(sample))
	var scale: float = STINGER_PEAK / maxf(peak, 0.0001)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index: int in range(sample_count):
		data.encode_s16(index * 2, roundi(clampf(mix[index] * scale, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = STINGER_RATE
	stream.data = data
	return stream


## One note added into the mix: attack of a few ms, then a release that
## reaches exactly zero at the end of the note, so neither edge clicks.
static func _add_stinger_note(mix: PackedFloat32Array, note: Array, spec: Dictionary) -> void:
	var base_hz: float = 440.0 * pow(2.0, (float(note[0]) - 69.0) / 12.0)
	var first: int = roundi(float(note[1]) * float(STINGER_RATE))
	var count: int = mini(roundi(float(note[2]) * float(STINGER_RATE)), mix.size() - first)
	var bend: float = float(note[3]) if note.size() > 3 else 0.0
	var vibrato: float = float(spec.get("vibrato", 0.0)) if float(note[2]) >= 1.0 else 0.0
	var harmonics: Array = spec["harmonics"]
	var decay: float = float(spec["decay"])
	var phase: float = 0.0
	for index: int in range(count):
		var seconds: float = float(index) / float(STINGER_RATE)
		var progress: float = float(index) / float(count)
		var semitones: float = bend * progress + vibrato * sin(TAU * 5.5 * seconds) * minf(seconds / 0.4, 1.0)
		var hz: float = base_hz * pow(2.0, semitones / 12.0) if semitones != 0.0 else base_hz
		phase += TAU * hz / float(STINGER_RATE)
		var tone: float = 0.0
		for partial: int in range(harmonics.size()):
			tone += float(harmonics[partial]) * sin(phase * float(partial + 1))
		mix[first + index] += tone * minf(seconds / STINGER_ATTACK, 1.0) * pow(1.0 - progress, decay)
