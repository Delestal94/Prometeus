extends AudioStreamPlayer
## The main menu's theme (tareas de Nacho N-403): assets/audio/music/
## mus_menu_loop.ogg, composed by tools/audio/compose_music.py, looped and
## faded in on the Music bus (the player's music volume). Self-contained:
## main_menu.gd only adds it, and it goes when the menu does.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const TRACK: AudioStream = preload("res://assets/audio/music/mus_menu_loop.ogg")
const FADE_IN_SECONDS: float = 1.5


func _ready() -> void:
	name = "MenuMusic"
	var track := TRACK.duplicate() as AudioStreamOggVorbis
	track.loop = true
	stream = track
	bus = &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master"
	process_mode = Node.PROCESS_MODE_ALWAYS
	volume_db = -60.0
	play()
	create_tween().tween_property(self, ^"volume_db", WorldMix.MENU_MUSIC_DB, FADE_IN_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
