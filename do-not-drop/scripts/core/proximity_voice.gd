extends SteamVoice
## Proximity voice, Steam only (N-212), on the net_session module's
## SteamVoice and VoicePlayback (docs/modulos.md): this file is only what the
## game decides -- the general switch and push-to-talk live in GameSettings,
## the session is NetworkManager, and where a crewmate's voice is heard from.
##
## LAN/ENet has no voice (N-212.4, decided with critico-diseno in N-704.3):
## an AudioEffectCapture + encoder path would double the bugs in the feature
## that was the number one complaint in both reference games. Over LAN the
## crew is in the same room anyway.
##
## Playback (N-212.2), local on every peer, nothing replicated: each crewmate
## who talks gets a VoicePlayback ("VoiceChat") on their player node, at
## their head on foot or at their seat's eye point when seated (a seated
## player's body stays where they sat down; only its visual rides along).
## - Both in the truck -- this peer looks through a seat camera of the truck
##   (the rule of vehicle_presentation.gd's _apply_bus_routing) and the
##   speaker sits in one of its seats -- it goes to the Interior bus with no
##   distance attenuation: in the cab everyone is heard.
## - Otherwise it goes to the Exterior bus and fades with distance (gone at
##   VoicePlayback.hearing_distance); with one aboard the truck (seated, or
##   standing in its cargo bay: net_in_vehicle) and the other not, it is also
##   muffled "through the sheet metal" (the cheap version: critico-diseno
##   asked only for the 3D attenuation).
## Neither bus is under the "Voces" slider, so GameSettings.voice_volume
## scales the gain along with the crewmate's own volume; muted, at volume 0
## or with voice switched off it is silent at once. A crewmate who leaves
## (NetworkManager.peer_removed) or a session that ends takes theirs along.

const PLAYBACK_NAME: StringName = &"VoiceChat"
const INTERIOR_BUS: StringName = &"Interior"
const EXTERIOR_BUS: StringName = &"Exterior"
## Where the voice sits on a player without a Head node (player.tscn's is at 1.6 m).
const HEAD_HEIGHT: float = 1.6

var _speakers: Dictionary = {}  # peer_id -> VoicePlayback


func _ready() -> void:
	super()
	session = get_node_or_null(^"/root/NetworkManager") as NetSession
	voice_received.connect(_on_voice_received)
	if session != null:
		session.peer_removed.connect(release_speaker)
		session.roster_changed.connect(_on_roster_changed)


func _process(delta: float) -> void:
	super(delta)
	for peer_id: int in _speakers.keys():
		var playback: VoicePlayback = speaker(peer_id)
		# Also one still gathering its cushion: muting it must not let it start.
		if playback != null and (playback.playing or playback.queued_frames() > 0):
			_route(peer_id, playback)


## The VoicePlayback a crewmate is heard through, or null while they have none.
func speaker(peer_id: int) -> VoicePlayback:
	var playback: Variant = _speakers.get(peer_id)
	if is_instance_valid(playback) and not (playback as Node).is_queued_for_deletion():
		return playback as VoicePlayback
	_speakers.erase(peer_id)
	return null


## Frees a crewmate's playback (they left, or the session ended).
func release_speaker(peer_id: int) -> void:
	var playback: VoicePlayback = speaker(peer_id)
	_speakers.erase(peer_id)
	if playback != null:
		playback.silence()
		playback.queue_free()


func clear_peers() -> void:
	super()
	for peer_id: int in _speakers.keys():
		release_speaker(peer_id)


func _forget_peer(peer_id: int) -> void:
	super(peer_id)
	release_speaker(peer_id)


## A session of one (left, or the host is gone) has nobody to hear; otherwise
## only those still on the roster keep theirs.
func _on_roster_changed(peer_ids: Array) -> void:
	for peer_id: int in _speakers.keys():
		if not _connected() or not peer_ids.has(peer_id):
			release_speaker(peer_id)


func _on_voice_received(peer_id: int, pcm: PackedByteArray, sample_rate: int) -> void:
	var playback: VoicePlayback = speaker(peer_id)
	if playback == null:
		var player: Node3D = _player_of(peer_id)
		if player == null:
			return  # Not spawned (yet): no head to hear them from.
		playback = VoicePlayback.new()
		playback.name = PLAYBACK_NAME
		playback.position = Vector3(0.0, HEAD_HEIGHT, 0.0)
		player.add_child(playback)
		_speakers[peer_id] = playback
	_route(peer_id, playback)
	playback.push_pcm(pcm, sample_rate)


## Where the voice comes from, which bus, how it carries and how loud.
func _route(peer_id: int, playback: VoicePlayback) -> void:
	var gain: float = _gain(peer_id)
	if not is_equal_approx(playback.gain, gain):
		playback.gain = gain
	var player := playback.get_parent() as Node3D
	if player == null:
		return
	var vehicle: Node = get_tree().get_first_node_in_group(&"vehicle")
	var seat: Node3D = _seat_of(player)
	var head: Node3D = player.get_node_or_null(^"Head") as Node3D
	playback.follow = seat if seat != null else head
	var speaker_seated: bool = seat != null and vehicle != null and vehicle.is_ancestor_of(seat)
	var listener_seated: bool = _listener_inside(vehicle)
	if speaker_seated and listener_seated:
		_set_bus(playback, INTERIOR_BUS)
		if playback.attenuation_model != AudioStreamPlayer3D.ATTENUATION_DISABLED:
			playback.carry_in_room()
		return
	_set_bus(playback, EXTERIOR_BUS)
	# Standing in the cargo bay is aboard too: no sheet metal in between.
	var speaker_aboard: bool = speaker_seated or _standing_aboard(player)
	var listener_aboard: bool = listener_seated or _standing_aboard(_player_of(multiplayer.get_unique_id()))
	var through_wall: bool = speaker_aboard != listener_aboard
	if playback.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED or playback.muffled != through_wall:
		playback.carry_in_open(through_wall)


## The crewmate's volume times the "Voces" slider; 0 when muted or with
## voice switched off.
func _gain(peer_id: int) -> float:
	if is_peer_muted(peer_id) or not _voice_enabled():
		return 0.0
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	var master: float = float(settings.get(&"voice_volume")) if settings != null else 1.0
	return peer_volume(peer_id) * master


## The same rule as vehicle_presentation.gd's bus routing: this peer hears
## from inside when it looks through one of the truck's seat cameras.
func _listener_inside(vehicle: Node) -> bool:
	if vehicle == null or not vehicle.is_inside_tree():
		return false
	var camera: Camera3D = vehicle.get_viewport().get_camera_3d()
	return camera is SeatCamera and vehicle.is_ancestor_of(camera)


## On foot in the truck's cargo bay (net_in_vehicle, replicated by its owner).
func _standing_aboard(player: Node) -> bool:
	if player == null:
		return false
	var aboard: Variant = player.get(&"net_in_vehicle")
	return aboard is bool and aboard


## The seat (its eye point) a player sits in, replicated to every peer as
## seat_node_path; null on foot.
func _seat_of(player: Node) -> Node3D:
	var path: Variant = player.get(&"seat_node_path")
	if not path is NodePath or (path as NodePath).is_empty():
		return null
	return player.get_node_or_null(path as NodePath) as Node3D


func _player_of(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		if node is Node3D and node.get_multiplayer_authority() == peer_id and not node.is_queued_for_deletion():
			return node as Node3D
	return null


func _set_bus(playback: VoicePlayback, bus_name: StringName) -> void:
	var target: StringName = bus_name if AudioServer.get_bus_index(bus_name) >= 0 else &"Master"
	if playback.bus != target:
		playback.bus = target


## Off never records and never plays (N-212.3).
func _voice_enabled() -> bool:
	return _settings_bool(&"voice_chat_enabled", false)


## Push-to-talk is the default (critico-diseno, N-704.3); off means open mic.
func _push_to_talk() -> bool:
	return _settings_bool(&"voice_push_to_talk", true)


func _settings_bool(property: StringName, fallback: bool) -> bool:
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	if settings == null:
		return fallback
	return bool(settings.get(property))
