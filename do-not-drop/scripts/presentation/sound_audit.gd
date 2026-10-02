extends RefCounted
## Every sound in the game, one by one, to find the one that grates
## (playtest 2026-09-25: "a noise like interference", loudest in the depot's
## loading zone, and no telling which sound it was). The options screen's
## "Sonidos del juego" (ui/sound_check_panel.gd) lists them and mutes or
## solos each.
##
## A sound here is who plays it and what: the forklift's engine and the
## truck's are the same synthesized loop, but not the same sound to find.
## Muting swaps the player's stream for a silent copy of the same length and
## loop, so it keeps "playing" and nothing that sets its volume or bus every
## frame can bring it back. A mute lasts until the game closes, level reloads
## included: a small node re-applies it to players that appear later.

const SynthAudioScript = preload("res://modules/synth_audio/synth_audio.gd")
const ORIGINAL_META := &"sound_audit_original"
const PROCESS_META := &"sound_audit_process_mode"
const REAPPLY_SECONDS: float = 0.3

const SOUND_NAMES: Dictionary = {
	&"engine_loop": "Motor", &"impact_thud": "Golpe", &"tire_screech": "Derrape",
	&"glass_chime": "Campanita", &"creature_groan": "Quejido", &"wood_creak": "Crujido de madera",
	&"liquid_slosh": "Chapoteo", &"explosive_tick": "Tic-tac", &"hostile_hiss": "Siseo",
	&"honk_horn": "Bocina", &"ambient_wind": "Viento", &"camera_shutter": "Obturador",
	&"tape_rip": "Cinta", &"cardboard_flap": "Solapa de cartón", &"tension_pulse": "Pulso de tensión",
	&"rain_loop": "Lluvia", &"crossing_bell": "Campana", &"roller_door": "Motor del portón",
	&"reverse_beep": "Beep de reversa", &"mus_depot_radio_loop": "Radio",
	&"ambient_birds": "Pájaros", &"night_crickets": "Grillos", &"distant_road": "Ruta lejana",
	&"dog_bark": "Ladrido", &"sheep_bleat": "Balido", &"scanner_beep": "Bip de los botones",
	&"doorbell_ding_dong": "Timbre", &"neighbor_cheer": "Alegría del vecino",
	&"comic_ruin_stinger": "Caja arruinada", &"comic_boom": "Explosión",
	&"forklift_motor_loop": "Motor eléctrico", &"river_flow_loop": "Río",
	&"train_horn": "Silbato del tren", &"train_chug_loop": "Traqueteo del tren",
	&"care_step": "Toque correcto", &"care_error": "Tecla equivocada", &"care_success": "Arreglo listo",
	&"care_whoosh": "Giro de la flecha", &"care_tick": "Avance de la herramienta",
	&"footstep": "Pisada",
	# Not a synthesized sound: a crewmate's voice chat (VoicePlayback, N-212.2).
	&"AudioStreamGenerator": "Voz",
}
## Whoever plays it: the nearest ancestor's script, by file name.
const SOURCE_NAMES: Dictionary = {
	"vehicle": "Camión", "vehicle_presentation": "Camión", "reference_truck": "Puertas del camión",
	"cargo_clutter": "Objetos sueltos del camión", "depot": "Depósito", "depot_forklift": "Autoelevador",
	"depot_roller_door": "Portón del depósito", "route": "Ruta", "route_sky": "Ambiente",
	"ingame_music": "Música", "package_feedback": "Caja (trampa)", "package_contents_view": "Caja (contenido)",
	"phone_camera": "Celular", "hud": "Pantalla", "hud_cargo_panel": "Pantalla", "delivery_house": "Casa",
	"chasing_dog": "Perro", "flock_crossing": "Ovejas", "rail_crossing_segment": "Paso a nivel",
	"narrow_bridge_segment": "Puente", "care_prompt_view": "Panel de cuidado",
	"player_sprint": "Jugador (correr)", "voice_playback": "Voz de compañero",
}

## Keys muted this session.
static var muted: Dictionary = {}
static var _silent: Dictionary = {}
static var _keeper: Node


## Every sound playing or ready to play in the tree, grouped:
## [{key, label, bus, players, playing}], sorted by label.
static func groups(tree: SceneTree) -> Array[Dictionary]:
	var found: Dictionary = {}
	for player: Node in players(tree):
		var key: String = key_of(player)
		if not found.has(key):
			found[key] = {"key": key, "label": label_of(player), "bus": String(_bus(player)), "players": 0, "playing": 0}
		found[key]["players"] += 1
		if _is_playing(player) and not player.has_meta(ORIGINAL_META):
			found[key]["playing"] += 1
	var list: Array[Dictionary] = []
	list.assign(found.values())
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.label) < String(b.label))
	return list


static func players(tree: SceneTree) -> Array[Node]:
	var list: Array[Node] = []
	if tree == null or tree.root == null:
		return list
	for type: String in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		list.append_array(tree.root.find_children("*", type, true, false))
	return list


static func key_of(player: Node) -> String:
	return "%s|%s" % [_source_of(player), _sound_of(_original_stream(player))]


static func label_of(player: Node) -> String:
	var source: String = _source_of(player)
	var sound: String = _sound_of(_original_stream(player))
	return "%s · %s" % [SOURCE_NAMES.get(source, source.capitalize()), SOUND_NAMES.get(StringName(sound), sound.capitalize())]


static func is_muted(key: String) -> bool:
	return muted.has(key)


static func set_muted(tree: SceneTree, key: String, mute: bool) -> void:
	if mute:
		muted[key] = true
	else:
		muted.erase(key)
	_ensure_keeper(tree)
	apply(tree)


## Only this one heard: everything else found right now is muted.
static func solo(tree: SceneTree, key: String) -> void:
	muted.clear()
	for group: Dictionary in groups(tree):
		if group.key != key:
			muted[group.key] = true
	_ensure_keeper(tree)
	apply(tree)


static func mute_all(tree: SceneTree) -> void:
	for group: Dictionary in groups(tree):
		muted[group.key] = true
	_ensure_keeper(tree)
	apply(tree)


static func unmute_all(tree: SceneTree) -> void:
	muted.clear()
	apply(tree)


## Brings every player in line with `muted`.
static func apply(tree: SceneTree) -> void:
	for player: Node in players(tree):
		var silenced: bool = player.has_meta(ORIGINAL_META)
		var want: bool = muted.has(key_of(player))
		if want and not silenced:
			var original: AudioStream = _stream(player)
			if original == null:
				continue
			player.set_meta(ORIGINAL_META, original)
			_swap(player, _silent_copy(original))
		elif silenced and not want:
			var original: AudioStream = player.get_meta(ORIGINAL_META)
			player.remove_meta(ORIGINAL_META)
			_swap(player, original)
		elif silenced and not _stream(player) is AudioStreamWAV:
			# Not a WAV (the music track): held down by volume instead.
			_set_volume_db(player, -80.0)


## While the sound list is open over a paused game, every player keeps
## playing, so a mute can be heard the moment it's toggled.
static func play_through_pause(tree: SceneTree, on: bool) -> void:
	for player: Node in players(tree):
		if on and not player.has_meta(PROCESS_META):
			player.set_meta(PROCESS_META, player.process_mode)
			player.process_mode = Node.PROCESS_MODE_ALWAYS
		elif not on and player.has_meta(PROCESS_META):
			player.process_mode = player.get_meta(PROCESS_META)
			player.remove_meta(PROCESS_META)


static func _swap(player: Node, stream: AudioStream) -> void:
	var was_playing: bool = _is_playing(player)
	var at: float = _playback_position(player) if was_playing else 0.0
	_set_stream(player, stream)
	if was_playing:
		_play(player, at)


# The three players share no base class with these, so each is asked as
# what it is (players() finds only these three).
static func _stream(player: Node) -> AudioStream:
	if player is AudioStreamPlayer3D:
		return (player as AudioStreamPlayer3D).stream
	if player is AudioStreamPlayer2D:
		return (player as AudioStreamPlayer2D).stream
	return (player as AudioStreamPlayer).stream


static func _set_stream(player: Node, stream: AudioStream) -> void:
	if player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).stream = stream
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).stream = stream
	else:
		(player as AudioStreamPlayer).stream = stream


static func _is_playing(player: Node) -> bool:
	if player is AudioStreamPlayer3D:
		return (player as AudioStreamPlayer3D).playing
	if player is AudioStreamPlayer2D:
		return (player as AudioStreamPlayer2D).playing
	return (player as AudioStreamPlayer).playing


static func _bus(player: Node) -> StringName:
	if player is AudioStreamPlayer3D:
		return (player as AudioStreamPlayer3D).bus
	if player is AudioStreamPlayer2D:
		return (player as AudioStreamPlayer2D).bus
	return (player as AudioStreamPlayer).bus


static func _set_volume_db(player: Node, volume_db: float) -> void:
	if player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).volume_db = volume_db
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).volume_db = volume_db
	else:
		(player as AudioStreamPlayer).volume_db = volume_db


static func _playback_position(player: Node) -> float:
	if player is AudioStreamPlayer3D:
		return (player as AudioStreamPlayer3D).get_playback_position()
	if player is AudioStreamPlayer2D:
		return (player as AudioStreamPlayer2D).get_playback_position()
	return (player as AudioStreamPlayer).get_playback_position()


static func _play(player: Node, from: float) -> void:
	if player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).play(from)
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).play(from)
	else:
		(player as AudioStreamPlayer).play(from)


static func _original_stream(player: Node) -> AudioStream:
	return player.get_meta(ORIGINAL_META) if player.has_meta(ORIGINAL_META) else _stream(player)


## Same length, format and loop, all zeros. A non-WAV stream (the music)
## can't be copied like that and stays as is (apply() turns it down).
static func _silent_copy(original: AudioStream) -> AudioStream:
	var wav := original as AudioStreamWAV
	if wav == null:
		return original
	var id: int = wav.get_instance_id()
	if not _silent.has(id):
		var silent := wav.duplicate() as AudioStreamWAV
		var zeros := PackedByteArray()
		zeros.resize(wav.data.size())
		zeros.fill(0)
		silent.data = zeros
		_silent[id] = silent
	return _silent[id]


static func _source_of(player: Node) -> String:
	# From the player itself: the music is a player with its own script.
	var node: Node = player
	while node != null:
		var script: Script = node.get_script() as Script
		if script != null and not script.resource_path.is_empty():
			return script.resource_path.get_file().get_basename()
		node = node.get_parent()
	return String(player.get_parent().name) if player.get_parent() != null else "?"


static func _sound_of(stream: AudioStream) -> String:
	if stream == null:
		return "sin sonido"
	for name: StringName in SynthAudioScript._cache:
		if SynthAudioScript._cache[name] == stream:
			return String(name)
	if not stream.resource_path.is_empty():
		return stream.resource_path.get_file().get_basename()
	return stream.get_class()


static func _ensure_keeper(tree: SceneTree) -> void:
	if is_instance_valid(_keeper) or tree == null or tree.root == null:
		return
	_keeper = _Keeper.new()
	_keeper.name = "SoundAuditKeeper"
	tree.root.add_child.call_deferred(_keeper)


## Re-applies the mutes to players that appear later (a reloaded level).
class _Keeper extends Node:
	var _wait: float = 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_wait -= delta
		if _wait > 0.0:
			return
		var audit: Script = load("res://scripts/presentation/sound_audit.gd")
		_wait = audit.REAPPLY_SECONDS
		if not (audit.muted as Dictionary).is_empty():
			audit.apply(get_tree())
