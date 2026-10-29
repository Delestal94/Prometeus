extends Node3D
## Plays the short musical identity that belongs to the replicated dance clip.
## Presentation only: anim_clip already reaches every peer, so this adds no RPC
## or synchronised property. One bounded emitter is reused for every dance.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const GelPerformance = preload("res://modules/synth_audio/synth_audio_gel_performance.gd")
const Mix = preload("res://scripts/gameplay/player/gel/gel_audio_mix.gd")
const CONGA: StringName = &"Conga"

var player: Node
var music: AudioStreamPlayer3D
var current_dance: StringName = &""


func _init() -> void:
	name = &"GelDanceAudio"


func _ready() -> void:
	player = get_parent().get_parent()
	music = AudioStreamPlayer3D.new()
	music.name = &"DanceMusic"
	music.unit_size = 7.0
	music.max_distance = 28.0
	music.volume_db = WorldMix.GEL_DANCE_MUSIC_DB
	music.bus = Mix.listener_bus(player)
	add_child(music)


func _process(_delta: float) -> void:
	if player == null:
		return
	var target_bus: StringName = Mix.listener_bus(player)
	if music.bus != target_bus:
		music.bus = target_bus
	music.volume_db = Mix.with_setting(player, WorldMix.GEL_DANCE_MUSIC_DB, &"music_volume")
	music.pitch_scale = Mix.player_pitch(player)
	var observed: Variant = player.get(&"anim_clip")
	var clip: StringName = observed if observed is StringName else &""
	if clip == current_dance:
		return
	if not GelPerformance.DANCE_CLIPS.has(clip):
		current_dance = &""
		music.stop()
		music.stream = null
		return
	current_dance = clip
	music.stream = SynthAudio.gel_dance_music(clip)
	var offset: float = 0.0
	if clip == CONGA:
		offset = fposmod(float(Time.get_ticks_msec()) / 1000.0, music.stream.get_length())
	music.play(offset)
