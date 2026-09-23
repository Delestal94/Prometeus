extends AudioStreamPlayer
## Background music while playing a level: one track, looped seamlessly,
## faded in so it doesn't slam in over the level loading. Plays on the
## "Music" bus, whose volume is the player's music setting (GameSettings).
## Local to each client -- nothing about it is networked.

const TRACK: AudioStream = preload("res://assets/audio/music/mus_ingame_loop.ogg")
## A bed under the engine, horn and trap sounds, not on top of them.
const VOLUME_DB: float = -14.0
const FADE_IN_SECONDS: float = 2.0
## Tension (tareas de Nacho #22/#84): a heartbeat layer that swells as the
## cargo gets into trouble, and the music itself leans a hair sharper. Reads
## RunManager's cargo state, which every client already receives.
const TENSION_SILENT_DB: float = -60.0
const TENSION_FULL_DB: float = -13.0
const TENSION_RESPONSE: float = 0.8
const TENSION_PITCH: float = 0.04
var tension: float = 0.0
var _tension_layer: AudioStreamPlayer


func _ready() -> void:
	name = "IngameMusic"
	var track := TRACK.duplicate() as AudioStreamOggVorbis
	track.loop = true
	stream = track
	bus = &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master"
	# Keeps playing under the pause menu instead of cutting out.
	process_mode = Node.PROCESS_MODE_ALWAYS
	volume_db = -60.0
	play()
	create_tween().tween_property(self, ^"volume_db", VOLUME_DB, FADE_IN_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tension_layer = AudioStreamPlayer.new()
	_tension_layer.name = "TensionLayer"
	_tension_layer.stream = SynthAudio.tension_pulse()
	_tension_layer.bus = bus
	_tension_layer.volume_db = TENSION_SILENT_DB
	add_child(_tension_layer)
	_tension_layer.play()


## 0 = all calm, 1 = a box aboard is at risk right now. Damage raises it
## part of the way before the trap itself says "at risk".
static func cargo_risk(cargo: Dictionary) -> float:
	var risk: float = 0.0
	for entry: Dictionary in cargo.values():
		var state: int = int(entry.get("state", 0))
		if state >= 2:
			continue  # Already ruined: nothing left to save, no reason to keep the dread up.
		var integrity: float = float(entry.get("integrity", 1.0)) / maxf(float(entry.get("maximum", 1.0)), 0.001)
		risk = maxf(risk, 1.0 if state == 1 else clampf((1.0 - integrity) * 1.4, 0.0, 0.7))
	return risk


func _process(delta: float) -> void:
	var manager: Node = get_node_or_null(^"/root/RunManager")
	var target: float = 0.0
	if manager != null and bool(manager.get(&"is_running")):
		target = cargo_risk(manager.get(&"cargo"))
	tension = move_toward(tension, target, TENSION_RESPONSE * delta)
	_tension_layer.volume_db = lerpf(TENSION_SILENT_DB, TENSION_FULL_DB, sqrt(tension))
	pitch_scale = 1.0 + TENSION_PITCH * tension
