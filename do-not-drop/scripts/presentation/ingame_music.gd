extends AudioStreamPlayer
## Background music in occasional phrases, leaving room for the world between
## plays. Slow fades and stable tuning keep the base atmosphere calm. Uses the
## "Music" bus, whose volume is the player's music setting (GameSettings).
## Local to each client -- nothing about it is networked.

const TRACK: AudioStream = preload("res://assets/audio/music/mus_ingame_loop.ogg")
## A bed under the engine, horn and trap sounds, not on top of them.
const VOLUME_DB: float = -14.0
const FADE_IN_SECONDS: float = 5.0
const FADE_OUT_SECONDS: float = 7.0
const FIRST_PAUSE_SECONDS := Vector2(18.0, 35.0)
const PAUSE_SECONDS := Vector2(45.0, 85.0)
const SILENT_DB: float = -80.0
## Tension (tareas de Nacho #22/#84): a restrained heartbeat layer for boxes
## actively at risk, without detuning the song or droning over old dents. Reads
## RunManager's cargo state, which every client already receives.
const TENSION_SILENT_DB: float = -60.0
const TENSION_FULL_DB: float = -23.0
const TENSION_ATTACK: float = 0.3
const TENSION_RELEASE: float = 0.2
var tension: float = 0.0
var _tension_layer: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _pause_left: float = 0.0
var _track_elapsed: float = 0.0


func _ready() -> void:
	name = "IngameMusic"
	var track := TRACK.duplicate() as AudioStreamOggVorbis
	track.loop = false
	stream = track
	bus = &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master"
	# Keeps playing under the pause menu instead of cutting out.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	volume_db = SILENT_DB
	_pause_left = _rng.randf_range(FIRST_PAUSE_SECONDS.x, FIRST_PAUSE_SECONDS.y)
	finished.connect(_on_track_finished)
	_tension_layer = AudioStreamPlayer.new()
	_tension_layer.name = "TensionLayer"
	_tension_layer.stream = SynthAudio.tension_pulse()
	_tension_layer.bus = bus
	_tension_layer.volume_db = TENSION_SILENT_DB
	add_child(_tension_layer)
	_tension_layer.play()


## Only an active warning needs musical tension. Old damage has its own UI
## and effects; it must not turn the rest of a peaceful trip into a drone.
static func cargo_risk(cargo: Dictionary) -> float:
	var risk: float = 0.0
	for entry: Dictionary in cargo.values():
		var state: int = int(entry.get("state", 0))
		if state == 1:
			risk = 1.0
	return risk


func _process(delta: float) -> void:
	_update_music(delta)
	var manager: Node = get_node_or_null(^"/root/RunManager")
	var target: float = 0.0
	if manager != null and bool(manager.get(&"is_running")):
		target = cargo_risk(manager.get(&"cargo"))
	tension = move_toward(tension, target, (TENSION_ATTACK if target > tension else TENSION_RELEASE) * delta)
	var gain: float = db_to_linear(TENSION_FULL_DB) * smoothstep(0.0, 1.0, tension)
	_tension_layer.volume_db = linear_to_db(maxf(gain, db_to_linear(TENSION_SILENT_DB)))


func _update_music(delta: float) -> void:
	if not playing:
		_pause_left = maxf(0.0, _pause_left - delta)
		if _pause_left <= 0.0:
			_track_elapsed = 0.0
			volume_db = SILENT_DB
			play()
		return
	_track_elapsed += delta
	var fade_in: float = smoothstep(0.0, FADE_IN_SECONDS, _track_elapsed)
	var fade_out: float = smoothstep(0.0, FADE_OUT_SECONDS, maxf(0.0, stream.get_length() - _track_elapsed))
	volume_db = linear_to_db(maxf(db_to_linear(VOLUME_DB) * minf(fade_in, fade_out), db_to_linear(SILENT_DB)))


func _on_track_finished() -> void:
	volume_db = SILENT_DB
	_pause_left = _rng.randf_range(PAUSE_SECONDS.x, PAUSE_SECONDS.y)
