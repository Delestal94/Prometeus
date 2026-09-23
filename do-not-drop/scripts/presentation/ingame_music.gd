extends AudioStreamPlayer
## Background music while playing a level: one track, looped seamlessly,
## faded in so it doesn't slam in over the level loading. Plays on the
## "Music" bus, whose volume is the player's music setting (GameSettings).
## Local to each client -- nothing about it is networked.

const TRACK: AudioStream = preload("res://assets/audio/music/mus_ingame_loop.ogg")
## A bed under the engine, horn and trap sounds, not on top of them.
const VOLUME_DB: float = -14.0
const FADE_IN_SECONDS: float = 2.0


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
