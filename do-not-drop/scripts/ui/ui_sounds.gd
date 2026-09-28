class_name UiSounds
extends RefCounted
## Short interface cues synthesized in code and routed through the SFX bus.
##
## UI audio stays separate from SynthAudio because that file is shared with
## the world/vehicle presentation domain. Streams are cached after their first
## use, while one root-level player per cue keeps rapid hover sounds cheap.

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
	HOVER: {"start": 880.0, "end": 1040.0, "duration": 0.045, "gain": 0.20},
	CLICK: {"start": 520.0, "end": 360.0, "duration": 0.085, "gain": 0.32},
	PANEL_OPEN: {"start": 330.0, "end": 660.0, "duration": 0.14, "gain": 0.28},
	PANEL_CLOSE: {"start": 660.0, "end": 300.0, "duration": 0.12, "gain": 0.25},
	TOAST: {"start": 720.0, "end": 920.0, "duration": 0.16, "gain": 0.24},
	UNLOCK: {"start": 620.0, "end": 1320.0, "duration": 0.30, "gain": 0.30},
	VOTE: {"start": 440.0, "end": 700.0, "duration": 0.11, "gain": 0.27},
	ERROR: {"start": 190.0, "end": 120.0, "duration": 0.22, "gain": 0.35},
}

static var _cache: Dictionary = {}


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
	player.play()


static func stream_for(cue: StringName) -> AudioStreamWAV:
	if not _SPECS.has(cue):
		return null
	if not _cache.has(cue):
		_cache[cue] = _build_stream(_SPECS[cue])
	return _cache[cue] as AudioStreamWAV


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
